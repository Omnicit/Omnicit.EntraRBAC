# Live verification checklist -- the session's account across tenant labels (fix/same-account-across-tenant-labels)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes nothing to the tenant.** No object is created, changed or removed, so there is no
prerequisite script and no teardown of objects; the prefix of the run is `oer-s153-`, and check T.1
proves that nothing carries it afterwards. Every command here reads, or signs in.

**Who runs it.** Section A: the dedicated certificate identity `oer-live-cc`, through the OerLive
library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in in section A is app-only, and every block of
section A runs in a process started with `pwsh -NonInteractive`, beside a fence that refuses every
token request that is not a certificate one, so no interactive sign-in can start. Section C is for a
person and is optional.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s153/`
(git-ignored). Every block prints through the library's redactor. The rows a read returns are
printed as a count and the first 12 hexadecimal characters of a SHA-256 over their sorted ids, never
as ids. **No credential, token, application id or certificate thumbprint is ever printed. Never
render an error record**: every block prints the error id only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash.

- **A. A user sign-in that names the session's tenant another way is held to the session's account**
  ("hold a user sign-in that names the tenant another way to the session's account"). A command that
  names the session's tenant by another label (its domain against its tenant ID, or any tenant after
  a sign-in that named none) inherits nothing from the session and signs in as `Interactive` with the
  default application. Its new token was compared with the session's account only when the session
  was that same kind of sign-in. Now it is also compared when the session and the new sign-in are
  both a user sign-in (interactive or device code, any application) in the same cloud and tenant:
  another account is refused with `SignInSuperseded` before `Connect-MgGraph`, or before an Azure
  Resource Manager token is cached, and the session stays the first account's. A switch between an
  app-only identity and a user, another cloud, another tenant and a token without an object id are not
  compared, and `Connect-OER` is never refused by it.
- **B. The texts** ("describe the session's account across tenant labels"): README, the about topic,
  the help of `Connect-OER`, CLAUDE.md and `docs/development/rationale.md`.

The new comparison only acts on a user sign-in, which the certificate identity cannot make. A live
tenant is needed for what the identity CAN show: that an app-only session, the module's unattended
case, behaves exactly as on `main` when a command names its tenant by the tenant ID and by the
domain, and that `Connect-OER` with the certificate still signs in under either label.

## What this file does not check, and why

- **The refusal itself** (a user session, another account picked in the browser) needs a person at a
  browser: class B, by the unit tests of Describe "Initialize-OERAuth never continues a renewal as
  another account (BL-119)", Context "a user sign-in that names the session's tenant by another label
  is held to the account whatever its method or application (A5)", and the no-try Context "a public
  command that names the session's tenant by another label after a device code sign-in, in a script
  with no try above it (A5)"; and section C, optional, for the operator.

## Setup, once

**You need:** the test tenant and the two configuration files OerLive reads beside it; OerLive 1.1.0
in the same folder (`OER_LIVE_DIR`); the identity `oer-live-cc` enabled for the run; this branch built
in the step's own worktree (`./build.ps1 -Tasks build`) and `OER_LIVE_REPO` naming that worktree.

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s153-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '$ContinuesUserSession = $script:_OERAuthState -and' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A"
```

**Expect:** `not the main clone: True`; the main clone on `main`; the worktree on this branch with 0
tracked changes; `A: True`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or on the last (build the
worktree first, never while the gate runs).

Result: 2026-11-11 13:30 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main; the worktree on fix/same-account-across-tenant-labels at 33fb154 with 0 tracked changes; the build carries A.

[oer-s153] The module loads from a worktree that is not the main clone: True
[oer-s153] Main clone: branch main
[oer-s153] Worktree: branch fix/same-account-across-tenant-labels; HEAD 33fb154 docs: add the live checklist for the session's account across tenant labels; tracked changes: 0
[oer-s153] The worktree's build carries A: True
```

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s153-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP; never sign in another way.

Result: 2026-11-11 13:30 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Every identity line True for the module session; identity check passed; the module is the worktree's build (1.6.1).

[oer-s153] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg3\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s153] The module is the worktree's build: True
```

## A. An app-only session behaves as on main under both labels

Checks A.1 and A.2 run the SAME sequence, A.1 on this branch's build and A.2 on `main` (commit
`9e748cc`, its `source/` taken with `git archive` into the step's raw folder and imported as it is,
beside the worktree's `output/RequiredModules`). Each block is run on its own, in a process of its
own: `pwsh -NoProfile -NonInteractive -File` the block. A.3 compares the two.

The sequence, as `oer-live-cc` with the certificate:

1. `Connect-OerLive -Arm` (the tenant named by its tenant ID), then the identity check.
2. A Microsoft Graph read (`Get-OERCatalog`) and an Azure Resource Manager read (`Get-OERSubscription`),
   each naming the tenant by its tenant ID, then each naming it by its domain.
3. `Disconnect-OerLive`, then `Connect-OER` with the certificate naming the tenant by its DOMAIN,
   with the identity printed as True/False (app, service principal, tenant).
4. The four reads again.
5. `Disconnect-OerLive`, then `Connect-OerLive -Arm` again (the tenant ID), then the reads by the
   tenant ID.

The fence (a global `Get-AzToken` that refuses every request without `-ClientCertificate`) stands
around every read and is removed before every sign-in.

### A.1. The sequence on this branch's build

- [x] **A.1** Every read under the session's own label returns rows; under the other label it is refused before any token request, and the fence is never reached; both `Connect-OER` sign-ins succeed.

```powershell
$Variant = 'branch'
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s153-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's153'
$null = New-Item -ItemType Directory -Force -Path $Raw
if ($Variant -eq 'main') {
    $Src = Join-Path $Raw 'before-9e748cc'
    if (-not (Test-Path -LiteralPath (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1'))) {
        $null = New-Item -ItemType Directory -Force -Path $Src
        git -C $Cfg.Repo archive --format=tar -o (Join-Path $Raw 'before-9e748cc.tar') 9e748cc source
        tar -xf (Join-Path $Raw 'before-9e748cc.tar') -C $Src
    }
    $env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
    Import-Module (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1') -Force -Global -ErrorAction Stop
}
$Out = [System.Collections.Generic.List[string]]::new()
function Note([string]$Text) { $Out.Add($Text); Write-OerLiveStep $Text }
$script:FenceHits = 0
function Set-Fence([bool]$On) {
    if ($On) {
        function global:Get-AzToken {
            [CmdletBinding()]
            param($ClientId, $ClientSecret, $Resource, $Tenant, $Scope, [switch]$Interactive, [switch]$DeviceCode,
                [switch]$ManagedIdentity, $ClientCertificate, $ClientCertificatePath, [switch]$Force, $Claim, $CredentialPrecedence)
            if (-not $PSBoundParameters.ContainsKey('ClientCertificate')) { $global:OerS153FenceHits++; throw 'FENCE: a token request that is not a certificate one was refused.' }
            AzAuth\Get-AzToken @PSBoundParameters
        }
        $global:OerS153FenceHits = 0
    } else {
        Remove-Item -Path function:global:Get-AzToken -ErrorAction SilentlyContinue
    }
}
function Get-Digest($Ids) {
    $Sorted = [string[]]@($Ids | ForEach-Object { ([string]$_).ToLowerInvariant() })
    [System.Array]::Sort($Sorted, [System.StringComparer]::Ordinal)
    $Hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Sorted -join "`n"))
    ([System.Convert]::ToHexString($Hash)).Substring(0, 12).ToLowerInvariant()
}
function Read-Both([string]$Phase, [string]$Label, [string]$Tenant) {
    foreach ($Read in @(@('Graph', 'Get-OERCatalog'), @('ARM', 'Get-OERSubscription'))) {
        $E = $null
        $Rows = @(& $Read[1] -TenantId $Tenant -ErrorAction SilentlyContinue -ErrorVariable E 3>$null)
        $Ids = @($Rows | ForEach-Object { if ($Read[0] -eq 'Graph') { $_.Id } else { $_.SubscriptionId } })
        $Errs = @($E | ForEach-Object { [string]$_.FullyQualifiedErrorId } | Where-Object { $_ })
        $S = & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState }
        Note ("$Phase, $($Read[0]) read naming the tenant by its $($Label): rows $($Rows.Count), digest $(if ($Rows.Count) { Get-Digest $Ids } else { 'none' }); errors: $($Errs -join ', '); " +
            "session after: certificate $([string]$S.AuthMethod -eq 'ClientCertificate'), label is the tenant ID $([string]$S.TenantId -eq $Cfg.TenantId), label is the domain $([string]$S.TenantId -eq $Cfg.UserDomain), signed-in object is the identity $([string]$S.SignedInObjectId -eq $SpId)")
    }
}
Connect-OerLive -Arm
$SpId = & (Get-Module OerLive) { $script:OerLive.SpId }
Note "Variant $Variant; module $((Get-Module Omnicit.EntraRBAC).Version); from the worktree's build: $((Get-Module Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Set-Fence $true
Read-Both '1 (signed in by tenant ID)' 'tenant ID' $Cfg.TenantId
Read-Both '1 (signed in by tenant ID)' 'domain' $Cfg.UserDomain
Note "Fence hits so far: $global:OerS153FenceHits"
Set-Fence $false
Disconnect-OerLive
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
$E = $null
try { $null = Connect-OER -TenantId $Cfg.UserDomain -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM -ErrorAction Stop }
catch { $E = [string]$PSItem.FullyQualifiedErrorId }
finally { $Cert = $null }
$S = & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState }
Note ("3 Connect-OER with the certificate naming the domain: error: $E; identity check: app-only certificate session with the identity's app id: $([string]$S.AuthMethod -eq 'ClientCertificate' -and ([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.AppId); " +
    "service principal is the token's signed-in object: $([string]$S.SignedInObjectId -eq $SpId); tenant is the test tenant: $([string]$S.TokenTenantId -eq $Cfg.TenantId); label is the domain: $([string]$S.TenantId -eq $Cfg.UserDomain); ARM token for the test tenant: $([bool]$S.ArmToken -and [string]$S.ArmTokenTenantId -eq $Cfg.TenantId)")
Set-Fence $true
Read-Both '4 (signed in by domain)' 'domain' $Cfg.UserDomain
Read-Both '4 (signed in by domain)' 'tenant ID' $Cfg.TenantId
Note "Fence hits so far: $global:OerS153FenceHits"
Set-Fence $false
Connect-OerLive -Arm
Set-Fence $true
Read-Both '5 (signed in by tenant ID again)' 'tenant ID' $Cfg.TenantId
Note "Fence hits in all: $global:OerS153FenceHits"
Set-Fence $false
Disconnect-OerLive
[System.IO.File]::WriteAllLines((Join-Path $Raw "outcome-$Variant.txt"), [string[]]@($Out | Where-Object { $_ -notlike 'Variant *' }))
```

**Expect:** every read under the label the session signed in with: rows above 0, no error, the session
unchanged; under the other label: rows 0, errors `InteractiveSignInUnavailable,Initialize-OERAuth`
first (the command inherits nothing and would sign in as a user, which a `-NonInteractive` host
refuses before any token request) and the command's own refusal of its request after it, the session
still the certificate one under its own label; the same digest for the same read in phases 1, 4 and
5; `Connect-OER` naming the domain with no error and every True/False `True`; `Fence hits in all: 0`.
No `SignInSuperseded` anywhere.
**Failure looks like:** `SignInSuperseded` (an app-only session compared with a user sign-in), a fence
hit (an interactive request was made), or a digest that differs between phases.

Result: 2026-11-11 13:30 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Under the label the session signed in with, both reads returned rows with no error (Graph 5 rows, Azure Resource Manager 1, the same digest for the same read in phases 1, 4 and 5); under the other label each read was refused with InteractiveSignInUnavailable before any token request, then the command's own SignInRefused (the plain SignInRefused entries between are inner-layer copies), and the session stayed the certificate one under its own label; Connect-OER with the certificate naming the domain signed in with every True/False True; fence hits 0; no SignInSuperseded anywhere.

[oer-s153] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg3\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s153] Variant branch; module 1.6.1; from the worktree's build: True
[oer-s153] 1 (signed in by tenant ID), Graph read naming the tenant by its tenant ID: rows 5, digest 9d4e1f209dc6; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 1 (signed in by tenant ID), ARM read naming the tenant by its tenant ID: rows 1, digest 6510588245d9; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 1 (signed in by tenant ID), Graph read naming the tenant by its domain: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERCatalog; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 1 (signed in by tenant ID), ARM read naming the tenant by its domain: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERSubscription; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] Fence hits so far: 0
[oer-s153] 3 Connect-OER with the certificate naming the domain: error: ; identity check: app-only certificate session with the identity's app id: True; service principal is the token's signed-in object: True; tenant is the test tenant: True; label is the domain: True; ARM token for the test tenant: True
[oer-s153] 4 (signed in by domain), Graph read naming the tenant by its domain: rows 5, digest 9d4e1f209dc6; errors: ; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] 4 (signed in by domain), ARM read naming the tenant by its domain: rows 1, digest 6510588245d9; errors: ; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] 4 (signed in by domain), Graph read naming the tenant by its tenant ID: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERCatalog; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] 4 (signed in by domain), ARM read naming the tenant by its tenant ID: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERSubscription; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] Fence hits so far: 0
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s153] 5 (signed in by tenant ID again), Graph read naming the tenant by its tenant ID: rows 5, digest 9d4e1f209dc6; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 5 (signed in by tenant ID again), ARM read naming the tenant by its tenant ID: rows 1, digest 6510588245d9; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] Fence hits in all: 0
```

### A.2. The same sequence on main

- [x] **A.2** The block of A.1 with `$Variant = 'main'`, in a process of its own.

```powershell
$Variant = 'main'
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s153-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's153'
$null = New-Item -ItemType Directory -Force -Path $Raw
if ($Variant -eq 'main') {
    $Src = Join-Path $Raw 'before-9e748cc'
    if (-not (Test-Path -LiteralPath (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1'))) {
        $null = New-Item -ItemType Directory -Force -Path $Src
        git -C $Cfg.Repo archive --format=tar -o (Join-Path $Raw 'before-9e748cc.tar') 9e748cc source
        tar -xf (Join-Path $Raw 'before-9e748cc.tar') -C $Src
    }
    $env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
    Import-Module (Join-Path $Src 'source\Omnicit.EntraRBAC.psd1') -Force -Global -ErrorAction Stop
}
$Out = [System.Collections.Generic.List[string]]::new()
function Note([string]$Text) { $Out.Add($Text); Write-OerLiveStep $Text }
$script:FenceHits = 0
function Set-Fence([bool]$On) {
    if ($On) {
        function global:Get-AzToken {
            [CmdletBinding()]
            param($ClientId, $ClientSecret, $Resource, $Tenant, $Scope, [switch]$Interactive, [switch]$DeviceCode,
                [switch]$ManagedIdentity, $ClientCertificate, $ClientCertificatePath, [switch]$Force, $Claim, $CredentialPrecedence)
            if (-not $PSBoundParameters.ContainsKey('ClientCertificate')) { $global:OerS153FenceHits++; throw 'FENCE: a token request that is not a certificate one was refused.' }
            AzAuth\Get-AzToken @PSBoundParameters
        }
        $global:OerS153FenceHits = 0
    } else {
        Remove-Item -Path function:global:Get-AzToken -ErrorAction SilentlyContinue
    }
}
function Get-Digest($Ids) {
    $Sorted = [string[]]@($Ids | ForEach-Object { ([string]$_).ToLowerInvariant() })
    [System.Array]::Sort($Sorted, [System.StringComparer]::Ordinal)
    $Hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Sorted -join "`n"))
    ([System.Convert]::ToHexString($Hash)).Substring(0, 12).ToLowerInvariant()
}
function Read-Both([string]$Phase, [string]$Label, [string]$Tenant) {
    foreach ($Read in @(@('Graph', 'Get-OERCatalog'), @('ARM', 'Get-OERSubscription'))) {
        $E = $null
        $Rows = @(& $Read[1] -TenantId $Tenant -ErrorAction SilentlyContinue -ErrorVariable E 3>$null)
        $Ids = @($Rows | ForEach-Object { if ($Read[0] -eq 'Graph') { $_.Id } else { $_.SubscriptionId } })
        $Errs = @($E | ForEach-Object { [string]$_.FullyQualifiedErrorId } | Where-Object { $_ })
        $S = & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState }
        Note ("$Phase, $($Read[0]) read naming the tenant by its $($Label): rows $($Rows.Count), digest $(if ($Rows.Count) { Get-Digest $Ids } else { 'none' }); errors: $($Errs -join ', '); " +
            "session after: certificate $([string]$S.AuthMethod -eq 'ClientCertificate'), label is the tenant ID $([string]$S.TenantId -eq $Cfg.TenantId), label is the domain $([string]$S.TenantId -eq $Cfg.UserDomain), signed-in object is the identity $([string]$S.SignedInObjectId -eq $SpId)")
    }
}
Connect-OerLive -Arm
$SpId = & (Get-Module OerLive) { $script:OerLive.SpId }
Note "Variant $Variant; module $((Get-Module Omnicit.EntraRBAC).Version); from the worktree's build: $((Get-Module Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Set-Fence $true
Read-Both '1 (signed in by tenant ID)' 'tenant ID' $Cfg.TenantId
Read-Both '1 (signed in by tenant ID)' 'domain' $Cfg.UserDomain
Note "Fence hits so far: $global:OerS153FenceHits"
Set-Fence $false
Disconnect-OerLive
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
$E = $null
try { $null = Connect-OER -TenantId $Cfg.UserDomain -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM -ErrorAction Stop }
catch { $E = [string]$PSItem.FullyQualifiedErrorId }
finally { $Cert = $null }
$S = & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState }
Note ("3 Connect-OER with the certificate naming the domain: error: $E; identity check: app-only certificate session with the identity's app id: $([string]$S.AuthMethod -eq 'ClientCertificate' -and ([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.AppId); " +
    "service principal is the token's signed-in object: $([string]$S.SignedInObjectId -eq $SpId); tenant is the test tenant: $([string]$S.TokenTenantId -eq $Cfg.TenantId); label is the domain: $([string]$S.TenantId -eq $Cfg.UserDomain); ARM token for the test tenant: $([bool]$S.ArmToken -and [string]$S.ArmTokenTenantId -eq $Cfg.TenantId)")
Set-Fence $true
Read-Both '4 (signed in by domain)' 'domain' $Cfg.UserDomain
Read-Both '4 (signed in by domain)' 'tenant ID' $Cfg.TenantId
Note "Fence hits so far: $global:OerS153FenceHits"
Set-Fence $false
Connect-OerLive -Arm
Set-Fence $true
Read-Both '5 (signed in by tenant ID again)' 'tenant ID' $Cfg.TenantId
Note "Fence hits in all: $global:OerS153FenceHits"
Set-Fence $false
Disconnect-OerLive
[System.IO.File]::WriteAllLines((Join-Path $Raw "outcome-$Variant.txt"), [string[]]@($Out | Where-Object { $_ -notlike 'Variant *' }))
```

**Expect:** `from the worktree's build: False` (main's source is loaded), and otherwise what A.1 expects.
**Failure looks like:** as A.1.

Result: 2026-11-11 13:30 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. main's source (commit 9e748cc, loaded as source, manifest version 0.0.1) printed the same outcome lines as A.1: rows, digests, error ids, session lines, fence hits 0.

[oer-s153] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s153] Variant main; module 0.0.1; from the worktree's build: False
[oer-s153] 1 (signed in by tenant ID), Graph read naming the tenant by its tenant ID: rows 5, digest 9d4e1f209dc6; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 1 (signed in by tenant ID), ARM read naming the tenant by its tenant ID: rows 1, digest 6510588245d9; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 1 (signed in by tenant ID), Graph read naming the tenant by its domain: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERCatalog; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 1 (signed in by tenant ID), ARM read naming the tenant by its domain: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERSubscription; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] Fence hits so far: 0
[oer-s153] 3 Connect-OER with the certificate naming the domain: error: ; identity check: app-only certificate session with the identity's app id: True; service principal is the token's signed-in object: True; tenant is the test tenant: True; label is the domain: True; ARM token for the test tenant: True
[oer-s153] 4 (signed in by domain), Graph read naming the tenant by its domain: rows 5, digest 9d4e1f209dc6; errors: ; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] 4 (signed in by domain), ARM read naming the tenant by its domain: rows 1, digest 6510588245d9; errors: ; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] 4 (signed in by domain), Graph read naming the tenant by its tenant ID: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERCatalog; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] 4 (signed in by domain), ARM read naming the tenant by its tenant ID: rows 0, digest none; errors: InteractiveSignInUnavailable,Initialize-OERAuth, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused, SignInRefused,Get-OERSubscription; session after: certificate True, label is the tenant ID False, label is the domain True, signed-in object is the identity True
[oer-s153] Fence hits so far: 0
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s153] 5 (signed in by tenant ID again), Graph read naming the tenant by its tenant ID: rows 5, digest 9d4e1f209dc6; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] 5 (signed in by tenant ID again), ARM read naming the tenant by its tenant ID: rows 1, digest 6510588245d9; errors: ; session after: certificate True, label is the tenant ID True, label is the domain False, signed-in object is the identity True
[oer-s153] Fence hits in all: 0
```

### A.3. Branch and main print the same lines

- [x] **A.3** The outcome files of A.1 and A.2 are identical, line for line.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s153-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's153'
$B = @(Get-Content -LiteralPath (Join-Path $Raw 'outcome-branch.txt'))
$M = @(Get-Content -LiteralPath (Join-Path $Raw 'outcome-main.txt'))
$Diff = @(Compare-Object -ReferenceObject $M -DifferenceObject $B -SyncWindow 0)
Write-OerLiveStep "Lines: branch $($B.Count), main $($M.Count); lines that differ: $($Diff.Count)"
foreach ($D in $Diff) { Write-OerLiveStep "$($D.SideIndicator) $($D.InputObject)" }
```

**Expect:** the same number of lines (above 0) and `lines that differ: 0`.
**Failure looks like:** any differing line: name it in the report.

Result: 2026-11-11 13:30 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. 14 outcome lines on each side, 0 lines differ: the app-only session behaves on this branch exactly as on main under both labels.

[oer-s153] Lines: branch 14, main 14; lines that differ: 0
```

## C, for Philip, optional

Not run by Claude Code: the identity `oer-live-cc` is app-only and cannot make a user sign-in. This
check does not block the merge. It shows the new refusal with a real browser and two accounts of the
test tenant.

### C.1. Another account picked for a command that names the tenant by its domain is refused

- [~] **C.1** After an interactive sign-in naming the tenant by its tenant ID, a command naming it by its domain, answered in the browser by ANOTHER account, is refused with `SignInSuperseded`, and the session is still the first account.

Steps, in a new PowerShell 7 window (not started with `-NonInteractive`), with this branch's build:

1. `Import-Module` the worktree's built `Omnicit.EntraRBAC.psd1`, with the worktree's
   `output\RequiredModules` first on `PSModulePath`.
2. `Connect-OER -TenantId` the test tenant's tenant ID (a GUID) `-Force`. Sign in as account 1.
3. `Get-OERCatalog | Select-Object -First 1` -- rows come back (the session works).
4. `Get-OERCatalog -TenantId` the test tenant's domain `-ErrorVariable E`. The browser opens, since
   the command names the tenant another way. Pick account 2 (another account of the same tenant).
5. `$E | ForEach-Object FullyQualifiedErrorId`.
6. `& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.Account; $script:_OERAuthState.TenantId }`.
7. `Get-OERCatalog -TenantId` the tenant ID `| Select-Object -First 1`.

**Expect:** step 5 lists `SignInSuperseded,Initialize-OERAuth` first; step 6 prints account 1 and the
tenant ID (the session is still account 1's); step 7 returns rows without a browser while account 1's
token is valid. On `main` the same steps make the session account 2's at step 4, with no error, when
account 1 signed in with `-DeviceCode` or with an own `-ClientId` -- run the same steps with
`Connect-OER -TenantId` the tenant ID `-DeviceCode -Force` at step 2 to see the case this change
closes: on this branch step 5 lists `SignInSuperseded,Initialize-OERAuth` there too.
**Failure looks like:** no error at step 4 and account 2 at step 6.

Result: 2026-11-11 13:30 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Not run by Claude Code: the identity oer-live-cc is app-only and cannot make a user sign-in (A5, class C). Optional for Philip after the merge; it does not block it. The refusal itself is class B: the Context 'a user sign-in that names the session's tenant by another label is held to the account whatever its method or application (A5)' and the no-try Context 'a public command that names the session's tenant by another label after a device code sign-in, in a script with no try above it (A5)' in tests/Unit/Private/Initialize-OERAuth.Tests.ps1.
```

## T. Teardown

### T.1. Nothing carries the prefix

- [x] **T.1** The sweep for `oer-s153-` is 0, and the module holds no session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s153-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Hits = @(Find-OerLivePrefixed)
Write-OerLiveStep "Objects with the prefix: $(@($Hits | Where-Object Kind -ne 'unread').Count); unread kinds: $(@($Hits | Where-Object Kind -eq 'unread').Count)"
Disconnect-OerLive
Write-OerLiveStep "The module holds a session: $($null -ne (& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState }))"
```

**Expect:** `Objects with the prefix: 0; unread kinds: 0`; `The module holds a session: False`.
**Failure looks like:** a prefixed object (this file creates none -- STOP and report it), or an unread kind.

Result: 2026-11-11 13:30 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Nothing was created: the sweep for oer-s153- is 0 with 0 unread kinds, and the module holds no session afterwards.

[oer-s153] Omnicit.EntraRBAC 1.6.1 loaded from REPO\.claude\worktrees\s15-steg3\output\module\Omnicit.EntraRBAC\1.6.1.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s153] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s153] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s153-' is left.
[oer-s153] Objects with the prefix: 0; unread kinds: 0
[oer-s153] The module holds a session: False
```
