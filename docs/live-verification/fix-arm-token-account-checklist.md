# Live verification checklist -- Microsoft Graph and Azure Resource Manager act as one account (fix/arm-token-account)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. Every check signs in, or lists subscriptions
(a count only). There is no prerequisite script and no test object; the teardown only proves that
nothing carries the prefix `oer-s125-` and that no session is left.

**Who runs it.** Two dedicated certificate identities of the test tenant, through the OerLive library,
which lives beside the operator's copy of this file outside the repository ([README.md](README.md),
first paragraph): `oer-live-cc` and `oer-live-cc-noperm`. They are two accounts of one tenant (two
service principals, one certificate). Every sign-in is app-only; nothing here signs in as a person. A
401 or 403 as `oer-live-cc` is a stop; `oer-live-cc-noperm` holds no permission, and what it reads is
reported as a count.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s125/`, which
is git-ignored. Every block prints through the library's redactor. **No credential, token,
application id, object id, tenant id, domain, account or certificate thumbprint is ever printed** --
every comparison, the account a token was issued to included, is printed as True or False -- and **no
error record is ever rendered**: a block prints the error id only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The account term** ("drop the cached Azure token when the account changes"). A cached Azure
  Resource Manager token is carried into a rebuilt sign-in state only when the rebuilt session's
  account (`SignedInObjectId`, the Microsoft Graph token's oid) is the same object id, a GUID, as the
  old session's. A sign-in as another account -- `Connect-OER -Force` included, without
  `-IncludeARM` -- drops the previous account's token, so the next Azure command needs a token of its
  own.
- **B. The account check at every acquisition** ("refuse an Azure token of another account at
  sign-in"). An Azure Resource Manager token whose oid differs from the session's `SignedInObjectId`,
  both GUIDs, is never cached: a renewal's is refused with `SignInSuperseded` as before, and any other
  sign-in's -- the first one and `Connect-OER -IncludeARM` included -- with the new
  `ArmAccountMismatch`, the Microsoft Graph half standing.
- **C.** The texts and the release note ("state that Graph and Azure act as one account").

A live tenant is needed for what the unit tests stub: real tokens of two real accounts, their real
object ids, and real Azure Resource Manager requests after each switch, counted with the account of the
token each one carried.

## What this file does not check, and why

- **The account term itself on a switch with the same application.** The two identities are two
  APPLICATIONS (two client ids), so a switch between them drops the cached Azure Resource Manager token
  through the client term as well -- on `main` too. A switch of account under the SAME tenant, method,
  client and cloud is a delegated sign-in (another user in the account picker), which no app identity
  can make: class B, proven by the unit tests of the Context "the cached Azure Resource Manager token
  follows the account (BL-163)". This file measures what the operator sees: that no Azure request is ever
  sent with the other account's token.
- **An Azure Resource Manager token of another account at the first sign-in** (`ArmAccountMismatch`).
  A certificate sign-in's two tokens are issued to the same service principal, so the refusal cannot be
  induced live: class B, proven by the unit tests, including a runspace with no `try` above the real
  `Connect-OER`.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm`, enabled for the run.
  This file adds no permission to either.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.

**Run every numbered block in its OWN PowerShell process.**

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s125-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s125'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
$A = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch '$NewSignedInObjectId -eq $script:_OERAuthState.SignedInObjectId' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch "-ErrorId 'ArmAccountMismatch'" -Quiet)
Write-OerLiveStep "The worktree's build carries A (the account term): $A; B (ArmAccountMismatch): $B"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `A (the account term): True; B
(ArmAccountMismatch): True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any other `False` -- build the worktree first (`./build.ps1 -Tasks build`), never while the
gate runs.

Result: 2026-11-05 UTC, run by Claude Code as oer-live-cc and oer-live-cc-noperm through the redacting runner (OerLive 1.1.0).

```text
Verdict: PASS. Run 2026-11-05 UTC, no sign-in. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree is on this branch at ac12150 (the checklist commit; its code is feb0a33's, built there and gated green: 13647 passed, 0 failed, coverage 96.43 %) with 0 tracked changes; the build carries A (the account term) and B (ArmAccountMismatch).

[oer-s125] The module loads from a worktree that is not the main clone: True
[oer-s125] Main clone: branch main
[oer-s125] Worktree: branch fix/arm-token-account; HEAD ac12150 docs: add the live checklist for one account across Graph and Azure; tracked changes: 0
[oer-s125] The worktree's build carries A (the account term): True; B (ArmAccountMismatch): True
```

## 1. One account for Graph and Azure, across a switch of identity

### 1.1. oer-live-cc with Azure, then oer-live-cc-noperm without it, then back

- [x] **1.1** In one process: `Connect-OER -IncludeARM` as `oer-live-cc` and an Azure Resource Manager read; `Connect-OER` as `oer-live-cc-noperm` without `-IncludeARM`; an Azure Resource Manager read then sends nothing with the first account's token; `Connect-OER -IncludeARM` as `oer-live-cc-noperm` and a read whose every request carries its own token; back as `oer-live-cc` with `-IncludeARM`, and a read succeeds with its own token.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s125-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s125'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
# The two service principals' object ids, read as oer-live-cc; never printed, only compared.
$CcSp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.AppId)
$NpSp = Invoke-OerLiveGraph -Uri ("v1.0/servicePrincipals(appId='{0}')?`$select=id" -f $Cfg.NoPermAppId)
$CcOid = ([string]$CcSp.Body['id']).ToLowerInvariant()
$NpOid = ([string]$NpSp.Body['id']).ToLowerInvariant()
Write-OerLiveStep "Both service principals read: $($CcSp.Ok -and $NpSp.Ok); two different objects: $($CcOid -and $NpOid -and $CcOid -ne $NpOid)"
if (-not ($CcSp.Ok -and $NpSp.Ok -and $CcOid -ne $NpOid)) { Disconnect-OerLive; throw 'STOP: the two service principals could not be told apart; nothing was called.' }
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint)
function New-S125Fence {
    param([string]$Name, [string]$Body)
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name $Name -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { $Body }"
    Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create($Text))
}
# Every Azure Resource Manager request is counted with the oid of the token it carries (read through the
# module's own Get-OERTokenObjectId, kept in memory, never printed).
New-S125Fence -Name 'Invoke-WebRequest' -Body ('$global:S125Arm++; $Auth = [string]$PSBoundParameters[''Headers''][''Authorization'']; ' +
    '$Sec = [System.Net.NetworkCredential]::new('''', $Auth.Substring(7)).SecurePassword; $Auth = $null; ' +
    '$global:S125Bearer.Add([string](& (Get-Module -Name Omnicit.EntraRBAC) { param($T) Get-OERTokenObjectId -Token $T } $Sec)); $Sec = $null; ' +
    'Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters')
New-S125Fence -Name 'Get-AzToken' -Body ('if ([string]$PSBoundParameters[''Resource''] -like ''*management*'') { $global:S125ArmToken++ } else { $global:S125GraphToken++ }; ' +
    'if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { throw [System.InvalidOperationException]::new(''S125 fence: a token request without the certificate was refused before it was sent.'') }; AzAuth\Get-AzToken @PSBoundParameters')
$Fenced = @('Invoke-WebRequest', 'Get-AzToken' | ForEach-Object { (& $Module { param($N) Get-Command -Name $N } $_).CommandType -eq 'Function' })
Write-OerLiveStep "The module resolves the two fenced commands to the fences: $(@($Fenced) -notcontains $false)"
if (@($Fenced) -contains $false) { Disconnect-OerLive; throw 'STOP: the fences do not shadow the module''s calls; nothing was called.' }
Disconnect-OerLive
function Reset-S125 { $global:S125Arm = 0; $global:S125ArmToken = 0; $global:S125GraphToken = 0; $global:S125Bearer = [System.Collections.Generic.List[string]]::new() }
function Get-S125Ids { param($All) $Ids = @($All | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }); if ($Ids) { $Ids -join ', ' } else { 'none' } }
function Write-S125State {
    param([string]$Step, [string]$ExpectedClient, [string]$ExpectedOid)
    $S = & $Module { $script:_OERAuthState }
    $ArmOid = if ($S.ArmToken) { & $Module { param($T) Get-OERTokenObjectId -Token $T } $S.ArmToken } else { $null }
    Write-OerLiveStep ("{0} state: the client is the expected app: {1}; the signed-in object is the expected service principal: {2}; the Graph token was issued for the test tenant: {3}; the module holds an ARM token: {4}; that ARM token is the same account as the Graph token: {5}" -f
        $Step, ([string]$S.ClientId -eq $ExpectedClient), ([string]$S.SignedInObjectId -eq $ExpectedOid), ([string]$S.TokenTenantId -eq $Cfg.TenantId),
        [bool]$S.ArmToken, $(if ($S.ArmToken) { [string]$ArmOid -eq [string]$S.SignedInObjectId } else { 'no token' }))
    $S = $null
}
function Invoke-S125Read {
    param([string]$Step)
    Reset-S125
    $All = @(Get-OERSubscription -TenantId $Cfg.TenantId 2>&1)
    $Subs = @($All | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $Bearer = @($global:S125Bearer)
    Write-OerLiveStep ("{0} Get-OERSubscription: errors: {1}; subscriptions returned: {2}; ARM token requests: {3}; ARM requests sent: {4}; sent with oer-live-cc's token: {5}; sent with oer-live-cc-noperm's token: {6}; sent with a token of neither: {7}" -f
        $Step, (Get-S125Ids $All), $Subs.Count, $global:S125ArmToken, $global:S125Arm,
        @($Bearer | Where-Object { $_ -eq $CcOid }).Count, @($Bearer | Where-Object { $_ -eq $NpOid }).Count,
        @($Bearer | Where-Object { $_ -ne $CcOid -and $_ -ne $NpOid }).Count)
}

# a. oer-live-cc with -IncludeARM, and an ARM read.
Reset-S125
$All = @(Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM 2>&1)
Write-OerLiveStep "1.1a Connect-OER -IncludeARM as oer-live-cc: errors: $(Get-S125Ids $All); Graph token requests: $global:S125GraphToken; ARM token requests: $global:S125ArmToken"
Write-S125State -Step '1.1a' -ExpectedClient $Cfg.AppId -ExpectedOid $CcOid
Invoke-S125Read -Step '1.1a'

# b. oer-live-cc-noperm WITHOUT -IncludeARM, straight after, no disconnect in between.
Reset-S125
$All = @(Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.NoPermAppId -Certificate $Cert 2>&1)
Write-OerLiveStep "1.1b Connect-OER as oer-live-cc-noperm (no -IncludeARM): errors: $(Get-S125Ids $All); Graph token requests: $global:S125GraphToken; ARM token requests: $global:S125ArmToken"
Write-S125State -Step '1.1b' -ExpectedClient $Cfg.NoPermAppId -ExpectedOid $NpOid

# c. An ARM read now: nothing may be sent with oer-live-cc's token.
Invoke-S125Read -Step '1.1c'

# d. oer-live-cc-noperm WITH -IncludeARM, and an ARM read with its own token.
Reset-S125
$All = @(Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.NoPermAppId -Certificate $Cert -IncludeARM 2>&1)
Write-OerLiveStep "1.1d Connect-OER -IncludeARM as oer-live-cc-noperm: errors: $(Get-S125Ids $All); Graph token requests: $global:S125GraphToken; ARM token requests: $global:S125ArmToken"
Write-S125State -Step '1.1d' -ExpectedClient $Cfg.NoPermAppId -ExpectedOid $NpOid
Invoke-S125Read -Step '1.1d'

# e. Back as oer-live-cc with -IncludeARM, and an ARM read.
Reset-S125
$All = @(Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.AppId -Certificate $Cert -IncludeARM 2>&1)
Write-OerLiveStep "1.1e Connect-OER -IncludeARM as oer-live-cc: errors: $(Get-S125Ids $All); Graph token requests: $global:S125GraphToken; ARM token requests: $global:S125ArmToken"
Write-S125State -Step '1.1e' -ExpectedClient $Cfg.AppId -ExpectedOid $CcOid
Invoke-S125Read -Step '1.1e'

$Cert = $null
Remove-Item -Path 'function:global:Invoke-WebRequest', 'function:global:Get-AzToken'
Disconnect-OerLive
```

**Expect:** every identity line `True`; the build, both service principals and the fences `True`.
1.1a: `errors: none`, one Graph and one ARM token request; the state lines `True`, the ARM token the
same account `True`; the read `errors: none`, subscriptions more than 0, ARM requests sent at least 1,
every one with oer-live-cc's token, 0 with noperm's and 0 with neither.
1.1b: `errors: none`, one Graph token request and 0 ARM; the client and the object noperm's `True`;
`the module holds an ARM token: False`.
1.1c: `AppOnlySessionCredentialUnavailable` (an inherited app-only session cannot mint an ARM token:
the module never keeps the certificate) and `SignInRefused` (the transport refuses the latched
command), 0 ARM token requests, 0 ARM requests sent -- and above all 0 sent with oer-live-cc's token.
1.1d: `errors: none`, 0 Graph token requests (the same identity's Graph token is cached; corrected after the run) and one ARM token request; state `True`, the ARM token the same account
`True`; the read sends every request with noperm's token and 0 with oer-live-cc's (noperm holds no Azure
role, so its subscription count is reported as it is).
1.1e: as 1.1a.
**Failure looks like:** `application is disabled` -- STOP: an identity is not enabled for this run;
a 401 or 403 as oer-live-cc -- STOP; any request sent with oer-live-cc's token in 1.1c or 1.1d, or
with noperm's in 1.1a or 1.1e -- the defect this branch closes.

Result: 2026-11-05 UTC, run by Claude Code as oer-live-cc and oer-live-cc-noperm through the redacting runner (OerLive 1.1.0).

```text
Verdict: PASS. Run 2026-11-05 UTC in one process (every identity line True; both service principals read and told apart; both fences shadow the module's calls). 1.1a oer-live-cc with -IncludeARM: no error, one Graph and one ARM token request, the ARM token the same account as the Graph token; one ARM request, sent with oer-live-cc's token. 1.1b oer-live-cc-noperm without -IncludeARM, no disconnect in between: no error, the module holds no ARM token. 1.1c an ARM read then: AppOnlySessionCredentialUnavailable and SignInRefused, 0 ARM token requests, 0 ARM requests -- nothing sent with oer-live-cc's token. 1.1d noperm with -IncludeARM: no error and ONE ARM token request but 0 Graph token requests (the Expect said one: Connect-OER without -Force answers the Graph half from the same identity's cached token, so only the ARM token was requested and compared with the session's account -- the ARM-only path of the new check; the Expect is corrected below); the ARM token the same account; the read sent its one request with noperm's token, 0 with oer-live-cc's (0 subscriptions: noperm holds no Azure role). 1.1e back as oer-live-cc with -IncludeARM: as 1.1a. As the file states, the two identities are two applications, so the drop in 1.1b also follows from the client term on main; the account term and ArmAccountMismatch themselves are class B.

[oer-s125] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg5\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s125] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s125] The module is the worktree's build: True
[oer-s125] Both service principals read: True; two different objects: True
[oer-s125] The module resolves the two fenced commands to the fences: True
[oer-s125] 1.1a Connect-OER -IncludeARM as oer-live-cc: errors: none; Graph token requests: 1; ARM token requests: 1
[oer-s125] 1.1a state: the client is the expected app: True; the signed-in object is the expected service principal: True; the Graph token was issued for the test tenant: True; the module holds an ARM token: True; that ARM token is the same account as the Graph token: True
[oer-s125] 1.1a Get-OERSubscription: errors: none; subscriptions returned: 1; ARM token requests: 0; ARM requests sent: 1; sent with oer-live-cc's token: 1; sent with oer-live-cc-noperm's token: 0; sent with a token of neither: 0
[oer-s125] 1.1b Connect-OER as oer-live-cc-noperm (no -IncludeARM): errors: none; Graph token requests: 1; ARM token requests: 0
[oer-s125] 1.1b state: the client is the expected app: True; the signed-in object is the expected service principal: True; the Graph token was issued for the test tenant: True; the module holds an ARM token: False; that ARM token is the same account as the Graph token: no token
[oer-s125] 1.1c Get-OERSubscription: errors: AppOnlySessionCredentialUnavailable, SignInRefused; subscriptions returned: 0; ARM token requests: 0; ARM requests sent: 0; sent with oer-live-cc's token: 0; sent with oer-live-cc-noperm's token: 0; sent with a token of neither: 0
[oer-s125] 1.1d Connect-OER -IncludeARM as oer-live-cc-noperm: errors: none; Graph token requests: 0; ARM token requests: 1
[oer-s125] 1.1d state: the client is the expected app: True; the signed-in object is the expected service principal: True; the Graph token was issued for the test tenant: True; the module holds an ARM token: True; that ARM token is the same account as the Graph token: True
[oer-s125] 1.1d Get-OERSubscription: errors: none; subscriptions returned: 0; ARM token requests: 0; ARM requests sent: 1; sent with oer-live-cc's token: 0; sent with oer-live-cc-noperm's token: 1; sent with a token of neither: 0
[oer-s125] 1.1e Connect-OER -IncludeARM as oer-live-cc: errors: none; Graph token requests: 1; ARM token requests: 1
[oer-s125] 1.1e state: the client is the expected app: True; the signed-in object is the expected service principal: True; the Graph token was issued for the test tenant: True; the module holds an ARM token: True; that ARM token is the same account as the Graph token: True
[oer-s125] 1.1e Get-OERSubscription: errors: none; subscriptions returned: 1; ARM token requests: 0; ARM requests sent: 1; sent with oer-live-cc's token: 1; sent with oer-live-cc-noperm's token: 0; sent with a token of neither: 0
```

## Teardown

### T.1. Nothing carries the prefix, no session is left, the main clone was never switched

- [x] **T.1** No object carries `oer-s125-`, the module holds no session, and the raw folder for the step is deleted after the results are copied.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s125-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s125'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "T.1 objects carrying the prefix: $(@($Left | Where-Object { $_.Kind -ne 'unread' }).Count); collections that could not be read: $(@($Left | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "T.1 the module holds a session after Disconnect-OerLive: $([bool](& $Module { $script:_OERAuthState }))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
Write-OerLiveStep "T.1 main clone: branch $(([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', '')"
```

**Expect:** `objects carrying the prefix: 0; collections that could not be read: 0`; `the module holds
a session after Disconnect-OerLive: False`; the main clone on `main`.
**Failure looks like:** a count above 0 -- this file creates nothing, so an object with the prefix is
not this run's: STOP.

Result: 2026-11-05 UTC, run by Claude Code as oer-live-cc and oer-live-cc-noperm through the redacting runner (OerLive 1.1.0).

```text
Verdict: PASS. Run 2026-11-05 UTC as oer-live-cc. No user, group, administrative unit, catalog, access package, access review definition or app registration carries oer-s125- (0), every collection was read (0 unread), the module holds no session after Disconnect-OerLive, and the main clone is on main. The runner kept its raw capture in its own scratch folder and deleted it after redaction; no raw\s125 folder was created.

[oer-s125] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg5\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s125] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s125] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s125] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s125-' is left.
[oer-s125] T.1 objects carrying the prefix: 0; collections that could not be read: 0
[oer-s125] T.1 the module holds a session after Disconnect-OerLive: False
[oer-s125] T.1 main clone: branch main
```
