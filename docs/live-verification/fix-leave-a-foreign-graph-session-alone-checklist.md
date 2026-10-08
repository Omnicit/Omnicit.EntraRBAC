# Live verification checklist -- the session: a foreign Graph session is left alone, and ARM never sends without a token (fix/leave-a-foreign-graph-session-alone)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant: nothing.** No object is created, changed or removed, so there
is no prerequisite script and no baseline. Every Azure Resource Manager call is a read, every
`Invoke-OERStructure` run is a `-WhatIf` plan that a refusal stops before it reads anything, and
section 3 writes tenant profiles only to a temporary folder outside the repository and outside the
real profile folder, `oer-s103-profiles` under the user's temp folder, which T.1 deletes.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. 5.3 also signs in as
`oer-live-cc-noperm`, to give the module a second identity. A 401 or 403 as `oer-live-cc` is a stop.

**Sign-ins.** Every block's FIRST sign-in goes through `Connect-OerLive` (`-Arm` for the module's
session, `-Graph` for a Graph SDK session the module does not connect), which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block installs
the no-prompt fence (H.1) right after it. Two checks sign in a SECOND time inside the block without
disconnecting the module first, because the state that sign-in leaves is what they test: 2.2 makes
another `Connect-MgGraph` replace the module's Graph SDK session (with `Disconnect-MgGraph` first,
as measured in `fix-refuse-a-changed-graph-sdk-session-checklist.md`), and 5.3 makes a later command
in a pipeline sign in as another identity (the shape `Invoke-OERStructure` checks were run with in
Sprint 9). Both use the same certificate, and each prints its identity as True/False.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s103/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line, a warning and an error that
stops a script go straight to the host, so each block is run in its own process whose WHOLE output
(standard output and standard error) is written to a file under `raw\s103\`, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-67 (decision A4): `Disconnect-OER` ends only the module's own Microsoft Graph PowerShell SDK
  session** ("fix: leave a Graph SDK session the module did not connect"). It used to call
  `Disconnect-MgGraph` whatever session the process held, so it also ended a session the operator, or
  another tool, had started. It now calls it only when the session is the one the module connected
  (`Own`). A session the module did not connect is left, with a warning written before the
  confirmation; the module's own state is always cleared.
- **B. BL-65 and BL-96: the Azure Resource Manager transport never sends a request without a token**
  ("fix: never send an Azure Resource Manager request without a token"). A session with no ARM token
  used to send its request with an empty bearer -- to the public cloud when there was no session at
  all. Such a request is now refused before it is sent with the existing `ArmTokenAcquisitionFailed`,
  and a session with no recorded ARM host takes its cloud's host instead of the public one.
- **C. BL-96: `New-OERConfiguration` and `Set-OERConfiguration` refuse a tenant id of white space**
  at parameter binding ("fix: refuse a blank tenant id when a tenant profile is written"); a profile
  already stored with one is read as before.
- **D. BL-92 and BL-93 (one point): the `SignInSuperseded` and A10 messages fit their cause** ("fix:
  say why a superseded or uncertain sign-in sent nothing"). After `Disconnect-OER` the
  `SignInSuperseded` message says `Disconnect-OER` ended the session; when `Invoke-OERStructure`
  refuses a whole document it says the document was not applied; and the A10 message no longer says
  the session may belong to the tenant before, which was wrong after a failed renewal in the same
  tenant.

A live tenant is needed for what the unit tests stub: the real Graph SDK sessions -- one the module
did not connect (1.1), the module's own (2.1) and one another `Connect-MgGraph` put in its place
(2.2) -- and what `Disconnect-OER` leaves of each; the real session state of a certificate sign-in
with its ARM token or host taken away (4.2, 4.3) beside an unchanged ARM regression (4.1); and the
four new messages, each produced by a real pipeline or a real refused renewal (5.1 to 5.4). Section 3
needs no tenant at all and is here because the step's prompt asks for it.

## What this file does not check, and why

- **A sovereign cloud's ARM host (class B, G9).** The test tenant is in the commercial cloud and
  there is no sovereign tenant to sign in to. Proved offline in
  `tests/Unit/Private/Invoke-OERArmRequest.Tests.ps1`, Describe `Invoke-OERArmRequest takes its host
  from the session's cloud (BL-65)`: a state for `USGov`, `USGovDoD` and `China` with no recorded host
  sends to that cloud's host from `Get-OERCloudEndpoint`. 4.3 runs the same code path live for the
  commercial cloud.
- **A request without an ARM token from a public cmdlet.** Every Azure cmdlet signs in with
  `-IncludeARM` at entry, which acquires a token or is refused and latches the cmdlet, and the latch
  gate refuses its requests before the new check is reached. The check is a second guard behind
  that; 4.2 reaches it in a real session by calling the transport directly, and the no-`try` proof is
  in the same unit test file (Describe `Invoke-OERArmRequest sends nothing without an ARM token,
  outside any try (BL-65, BL-96)`).
- **The A10 message after a refused sign-in to ANOTHER tenant.** Only the test tenant is reachable.
  The text is one text for every refusal that marks the session (proved in
  `tests/Unit/Private/New-OERSignInRefusedError.Tests.ps1` and the A10 Describe of
  `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`); 5.4 shows it live after the case BL-93 names, a
  failed renewal in the same tenant.
- **`SignInSuperseded` for a request when another identity signed in.** Its text is unchanged by this
  branch and was run live in Sprint 8 and Sprint 9.
- **G8 (convergence).** This branch changes no write path of the apply engine; `Invoke-OERStructure`
  is run here only to be refused before it reads anything.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and `oer-live-cc-noperm`
  for 5.3. This file adds no permission to either.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 reads that it was not).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences and the
readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s103-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s103'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
# Section 3's profiles: a temporary folder outside the repository and the real profile folder.
$ProfileDir = Join-Path ([System.IO.Path]::GetTempPath()) 'oer-s103-profiles'
$ExpectedWarning = 'Disconnect-OER leaves the Microsoft Graph PowerShell SDK session in this process connected, since Omnicit.EntraRBAC has no record of connecting it. Run Disconnect-MgGraph to end that session.'

function Import-S103Module {
    # The worktree's build, for the blocks that sign in nowhere (section 3).
    $Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Import-Module -Name $Psd1.FullName -Force -Global -ErrorAction Stop
    Write-OerLiveStep "The module is the worktree's build: $((Get-Module -Name Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
}

function Start-S103NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S103TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S103TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S103 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S103Count {
    # Counts every request the module sends: Azure Resource Manager (with the host it goes to) through a
    # global proxy of Invoke-WebRequest, Microsoft Graph through one of Invoke-MgGraphRequest. The
    # module's transports call both unqualified, so the proxies are what they reach.
    $global:S103Arm = [System.Collections.Generic.List[string]]::new()
    $global:S103Graph = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S103Arm.Add(([uri]`$Uri).Host); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S103Graph.Add('request'); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S103Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-WebRequest', 'Invoke-MgGraphRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S103Sent {
    "token requests: $global:S103TokenCalls; Microsoft Graph requests: $(@($global:S103Graph).Count); Azure Resource Manager requests: $(@($global:S103Arm).Count)$(if (@($global:S103Arm).Count) { " (hosts: $((@($global:S103Arm) | Sort-Object -Unique) -join ', '))" })"
}

function Get-S103GraphSession {
    # The Graph SDK session the process holds, as True/False and its kind only: whether there is one, its
    # AuthType (AppOnly for a certificate Connect-MgGraph, UserProvidedAccessToken for the module's own),
    # and whether its client is oer-live-cc in the test tenant. Never a value.
    $C = Get-MgContext
    $Mine = [bool]($C -and [string]$C.ClientId -eq [string]$Cfg.AppId -and [string]$C.TenantId -eq [string]$Cfg.TenantId)
    "Graph SDK session present: $([bool]$C)$(if ($C) { "; kind: $([string]$C.AuthType); client oer-live-cc in the test tenant: $Mine" })"
}

function Get-S103ModuleView {
    # The module's own comparison of that session (Get-OERGraphSessionState) and whether it holds a state.
    $M = Get-Module -Name Omnicit.EntraRBAC
    $V = & $M { [PSCustomObject]@{ State = Get-OERGraphSessionState; Held = ($null -ne $script:_OERAuthState) } }
    "the module's view of it: $($V.State); module state held: $($V.Held)"
}

function Write-S103Error {
    # One error record as a line: its id, category, target and message (redacted by Write-OerLiveStep).
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Record)
    if ($Record -isnot [System.Management.Automation.ErrorRecord]) { Write-OerLiveStep "$Label error (not an ErrorRecord): $($Record.GetType().Name)"; return }
    Write-OerLiveStep "$Label error: $([string]$Record.FullyQualifiedErrorId) ($($Record.CategoryInfo.Category), target '$([string]$Record.TargetObject)'): $([string]$Record.Exception.Message)"
}

function Write-S103Errors {
    # Prints the records of the module's own ids in full and only counts the rest: an inner layer's record
    # can carry a raw request as its target, which is never printed here.
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Errors, [Parameter(Mandatory)][string[]]$Ids)
    $Own = @($Errors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and (([string]$_.FullyQualifiedErrorId) -split ',')[0] -in $Ids })
    $I = 0
    foreach ($E in $Own) { $I++; Write-S103Error -Label "$Label [$I]" -Record $E }
    Write-OerLiveStep "$Label records with the ids $($Ids -join ', '): $($Own.Count); other items in -ErrorVariable (counted, not printed): $(@($Errors).Count - $Own.Count)"
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
Write-OerLiveStep "The worktree's build carries A: $(& $Has 'since Omnicit.EntraRBAC has no record of connecting it'); B: $(& $Has 'holds no Azure Resource Manager token'); C: $(& $Has 'The TenantId consists only of white space'); D: $(& $Has 'did not apply this document') and $(& $Has 'may not be the one that sign-in asked for')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `The worktree's build carries A:
True; B: True; C: True; D: True and True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result:

## 1. A Graph SDK session the module did not connect (A)

### 1.1. Disconnect-OER leaves it, says so, and clears the module's state

- [ ] **1.1** After `Connect-OerLive -Graph` -- a certificate `Connect-MgGraph` as `oer-live-cc`, which the module did not make -- `Disconnect-OER` writes the warning once, leaves that Graph SDK session connected and holds no module state; `Disconnect-MgGraph` then ends the session.

```powershell
Connect-OerLive -Graph
Start-S103NoPrompt
Write-OerLiveStep "Before: $(Get-S103GraphSession); $(Get-S103ModuleView)"
$W = $null
Disconnect-OER -Confirm:$false -WarningVariable W -WarningAction SilentlyContinue
Write-OerLiveStep "Disconnect-OER warnings: $(@($W).Count); the expected text: $(@($W).Count -eq 1 -and [string]$W[0].Message -ceq $ExpectedWarning)"
foreach ($One in @($W)) { Write-OerLiveStep "warning: $([string]$One.Message)" }
Write-OerLiveStep "After Disconnect-OER: $(Get-S103GraphSession); $(Get-S103ModuleView)"
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-OerLiveStep "After Disconnect-MgGraph: $(Get-S103GraphSession)"
Write-OerLiveStep (Get-S103Sent)
```

**Expect:** before: `Graph SDK session present: True; kind: AppOnly; client oer-live-cc in the test
tenant: True`, the module's view `Untracked`, module state held `False`; `Disconnect-OER warnings: 1;
the expected text: True`; after `Disconnect-OER` the same session line as before (present, AppOnly,
True) and module state held `False`; after `Disconnect-MgGraph`, `present: False`; token requests 0.
**Failure looks like:** `present: False` after `Disconnect-OER` -- it ended a session the module did
not connect (BL-67 not fixed); no warning, or another text.

Result:

## 2. The module's own Graph SDK session, and one another Connect-MgGraph put in its place (A)

### 2.1. Disconnect-OER ends the session the module connected, with no warning

- [ ] **2.1** After `Connect-OerLive -Arm` (the module's own `Connect-OER` with the certificate), the module reads its session as `Own`; `Disconnect-OER` writes no warning, ends the Graph SDK session and holds no module state.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
Write-OerLiveStep "Before: $(Get-S103GraphSession); $(Get-S103ModuleView)"
$W = $null
Disconnect-OER -Confirm:$false -WarningVariable W -WarningAction SilentlyContinue
Write-OerLiveStep "Disconnect-OER warnings: $(@($W).Count)"
Write-OerLiveStep "After Disconnect-OER: $(Get-S103GraphSession); $(Get-S103ModuleView)"
Write-OerLiveStep (Get-S103Sent)
```

**Expect:** before: `present: True; kind: UserProvidedAccessToken; client oer-live-cc in the test
tenant: True`, the module's view `Own`, module state held `True`; `Disconnect-OER warnings: 0`; after:
`Graph SDK session present: False`, the module's view `Untracked`, module state held `False`; token
requests 0.
**Failure looks like:** the session still present after `Disconnect-OER`, or a warning.

Result:

### 2.2. A session another Connect-MgGraph put in place of the module's is left, with the warning

- [ ] **2.2** After `Connect-OerLive -Arm`, `Disconnect-MgGraph` and a certificate `Connect-MgGraph` as `oer-live-cc`, the module reads the session as `Changed`; `Disconnect-OER` writes the warning once, leaves that session connected and clears the module's state.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
# Another Connect-MgGraph replaces the module's session: Disconnect-MgGraph first, since a certificate
# Connect-MgGraph straight after Connect-OER fails on the SDK's process token cache (measured, Sprint 8).
# Its exception message is never printed: MSAL quotes the start of that cache in it.
Disconnect-MgGraph -ErrorAction Stop | Out-Null
try {
    Connect-MgGraph -ClientId $Cfg.AppId -TenantId $Cfg.TenantId -CertificateThumbprint $Cfg.CertificateThumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
} catch {
    Write-OerLiveStep "STOP: the certificate Connect-MgGraph failed ($($PSItem.Exception.GetType().Name)); its message is not printed."
    throw 'STOP: 2.2 could not set up the replaced session.'
}
Write-OerLiveStep "Before: $(Get-S103GraphSession); $(Get-S103ModuleView)"
$W = $null
Disconnect-OER -Confirm:$false -WarningVariable W -WarningAction SilentlyContinue
Write-OerLiveStep "Disconnect-OER warnings: $(@($W).Count); the expected text: $(@($W).Count -eq 1 -and [string]$W[0].Message -ceq $ExpectedWarning)"
Write-OerLiveStep "After Disconnect-OER: $(Get-S103GraphSession); $(Get-S103ModuleView)"
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-OerLiveStep "After Disconnect-MgGraph: $(Get-S103GraphSession)"
Write-OerLiveStep (Get-S103Sent)
```

**Expect:** before: `present: True; kind: AppOnly; client oer-live-cc in the test tenant: True`, the
module's view `Changed`, module state held `True`; `Disconnect-OER warnings: 1; the expected text:
True`; after `Disconnect-OER`: the same AppOnly session present, the module's view `Untracked`, module
state held `False`; after `Disconnect-MgGraph`, `present: False`; token requests 0.
**Failure looks like:** the session gone after `Disconnect-OER`; the module's view not `Changed`
before (the replacing connect did not take, so the check proves nothing -- not a pass).

Result:

## 3. A tenant id of white space in a tenant profile (C)

### 3.1. New-OERConfiguration refuses it at parameter binding and writes nothing

- [ ] **3.1** `New-OERConfiguration -TenantId` with three spaces, a tab and a no-break space is refused at parameter binding with `ParameterArgumentValidationError,New-OERConfiguration` and the white-space message; an empty value still reads the empty-value message; no file is written to the temporary profile folder.

```powershell
Import-S103Module
if (Test-Path -LiteralPath $ProfileDir) { Remove-Item -LiteralPath $ProfileDir -Recurse -Force }
New-Item -ItemType Directory -Path $ProfileDir | Out-Null
foreach ($Case in @(
        @{ Label = 'three spaces'; Value = '   ' }
        @{ Label = 'a tab'; Value = "`t" }
        @{ Label = 'a no-break space'; Value = [string][char]0x00A0 }
        @{ Label = 'empty (control)'; Value = '' })) {
    try {
        New-OERConfiguration -TenantAlias 'oer-s103-blank' -TenantId $Case.Value -BasePath $ProfileDir -Confirm:$false -ErrorAction Stop | Out-Null
        Write-OerLiveStep "$($Case.Label): no error"
    } catch {
        Write-S103Error -Label $Case.Label -Record $PSItem
    }
}
Write-OerLiveStep "Files in the temporary profile folder: $(@(Get-ChildItem -LiteralPath $ProfileDir -File).Count)"
```

**Expect:** for the three white-space values `ParameterArgumentValidationError,New-OERConfiguration`
with the message `Cannot validate argument on parameter 'TenantId'. The TenantId consists only of
white space. Supply the tenant ID or a verified domain of the tenant.`; for the empty value the same
id with `The argument is null or empty.` in its message; `Files in the temporary profile folder: 0`.
**Failure looks like:** `no error` for a white-space value, or a file written.

Result:

### 3.2. Set-OERConfiguration refuses it, typed and piped, and leaves the profile as it was

- [ ] **3.2** On a profile written first with `contoso.onmicrosoft.com`, `Set-OERConfiguration -TenantId` with a tab is refused at binding, and so is a piped object whose `TenantId` is two spaces; the file is byte for byte unchanged and still names the tenant it named.

```powershell
Import-S103Module
if (-not (Test-Path -LiteralPath $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir | Out-Null }
New-OERConfiguration -TenantAlias 'oer-s103-set' -TenantId 'contoso.onmicrosoft.com' -BasePath $ProfileDir -Confirm:$false -ErrorAction Stop | Out-Null
$File = Join-Path $ProfileDir 'oer-s103-set.psd1'
$Hash = (Get-FileHash -LiteralPath $File).Hash
try {
    Set-OERConfiguration -TenantAlias 'oer-s103-set' -TenantId "`t" -BasePath $ProfileDir -Confirm:$false -ErrorAction Stop | Out-Null
    Write-OerLiveStep 'typed: no error'
} catch {
    Write-S103Error -Label 'typed' -Record $PSItem
}
$E = $null
$Out = @([pscustomobject]@{ TenantAlias = 'oer-s103-set'; TenantId = '  ' } | Set-OERConfiguration -BasePath $ProfileDir -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable E)
Write-OerLiveStep "piped: objects returned $($Out.Count)"
Write-S103Errors -Label 'piped' -Errors $E -Ids @('ParameterArgumentValidationError')
$Read = Get-OERConfiguration -TenantAlias 'oer-s103-set' -BasePath $ProfileDir -ErrorAction Stop
Write-OerLiveStep "The profile file is unchanged: $((Get-FileHash -LiteralPath $File).Hash -eq $Hash); it still names contoso.onmicrosoft.com: $([string]$Read.TenantId -eq 'contoso.onmicrosoft.com')"
```

**Expect:** `typed error: ParameterArgumentValidationError,Set-OERConfiguration` with the white-space
message; piped: objects returned 0 and one record with that id and message; `The profile file is
unchanged: True; it still names contoso.onmicrosoft.com: True`.
**Failure looks like:** `no error`, an object returned, or `False` on the last line.

Result:

### 3.3. A profile already stored with a tenant id of white space is read as before

- [ ] **3.3** A profile file whose `TenantId` was changed to three spaces by hand is read by `Get-OERConfiguration` as before: the profile is returned, and its `TenantId` is those three spaces.

```powershell
Import-S103Module
if (-not (Test-Path -LiteralPath $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir | Out-Null }
New-OERConfiguration -TenantAlias 'oer-s103-stored' -TenantId 'contoso.onmicrosoft.com' -BasePath $ProfileDir -Confirm:$false -ErrorAction Stop | Out-Null
$File = Join-Path $ProfileDir 'oer-s103-stored.psd1'
$Text = [System.IO.File]::ReadAllText($File)
[System.IO.File]::WriteAllText($File, $Text.Replace("'contoso.onmicrosoft.com'", "'   '"), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "The stored tenant id is three spaces now: $((Import-PowerShellDataFile -LiteralPath $File).TenantId -eq '   ')"
$Read = @(Get-OERConfiguration -TenantAlias 'oer-s103-stored' -BasePath $ProfileDir -ErrorAction Stop)
Write-OerLiveStep "profiles returned: $($Read.Count); TenantId is three spaces: $($Read.Count -eq 1 -and [string]$Read[0].TenantId -eq '   ')"
```

**Expect:** `The stored tenant id is three spaces now: True`; `profiles returned: 1; TenantId is three
spaces: True`.
**Failure looks like:** an error from `Get-OERConfiguration`, or no profile returned -- this branch
changed how a stored profile is read, which it must not.

Result:

## 4. Azure Resource Manager (B)

### 4.1. A session with ARM reads as before (regression)

- [ ] **4.1** After `Connect-OerLive -Arm`, `Get-OERSubscription` lists the test subscription and `Get-OERResourceGroup` lists its resource groups, with no error, every ARM request going to the commercial cloud's host.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
Start-S103Count
$E = $null
$Subs = @(Get-OERSubscription -ErrorVariable E -ErrorAction Continue)
$Rg = @(Get-OERResourceGroup -Subscription $Cfg.SubscriptionId -ErrorVariable +E -ErrorAction Continue)
Stop-S103Count
Write-OerLiveStep "subscriptions listed: $($Subs.Count); the test subscription among them: $(@($Subs | Where-Object { [string]$_.SubscriptionId -eq [string]$Cfg.SubscriptionId }).Count -eq 1); resource groups listed: $($Rg.Count); errors: $(@($E).Count)"
Write-OerLiveStep (Get-S103Sent)
Disconnect-OerLive
```

**Expect:** at least one subscription, `the test subscription among them: True`, a resource group
count, `errors: 0`; Azure Resource Manager requests at least 2, all to `management.azure.com`; token
requests 0 (the session's ARM token is used).
**Failure looks like:** any error, or a request to another host.

Result:

### 4.2. A real session whose ARM token is taken away sends no ARM request

- [ ] **4.2** In a real certificate session with its ARM token removed from the module's state (its host kept), the module's ARM transport refuses a request with `ArmTokenAcquisitionFailed` (`AuthenticationError`) and the new message, and sends nothing.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
& $M { $null = $script:_OERAuthState.Remove('ArmToken') }
Write-OerLiveStep "The module state holds an ARM token: $(& $M { [bool]$script:_OERAuthState.ArmToken }); it records the ARM host: $(& $M { [bool]$script:_OERAuthState.ArmResourceUrl })"
Start-S103Count
$R = & $M { try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'; 'no error' } catch { $PSItem } }
Stop-S103Count
if ($R -is [System.Management.Automation.ErrorRecord]) { Write-S103Error -Label 'the transport' -Record $R } else { Write-OerLiveStep "the transport: $R" }
Write-OerLiveStep (Get-S103Sent)
Disconnect-OerLive
```

**Expect:** `holds an ARM token: False; it records the ARM host: True`; `the transport error:
ArmTokenAcquisitionFailed (AuthenticationError, target '/subscriptions?api-version=2022-12-01'): No
Azure Resource Manager request was sent: the module's session holds no Azure Resource Manager token.
Run Connect-OER -IncludeARM to acquire one -- for an app-only session with its certificate or client
secret -- and run the command again.`; Azure Resource Manager requests 0.
**Failure looks like:** one ARM request sent (an empty bearer) and a 401 from Azure Resource Manager.

Result:

### 4.3. A real session with no recorded ARM host takes its cloud's host

- [ ] **4.3** In a real certificate session with its recorded ARM host removed (its token kept), the transport takes the host of the session's cloud (`Global`) from `Get-OERCloudEndpoint`, and the request is answered.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
& $M { $null = $script:_OERAuthState.Remove('ArmResourceUrl') }
Write-OerLiveStep "The module state records the ARM host: $(& $M { [bool]$script:_OERAuthState.ArmResourceUrl }); the session's cloud: $(& $M { [string]$script:_OERAuthState.Environment })"
Start-S103Count
$R = & $M { try { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } catch { $PSItem } }
Stop-S103Count
if ($R -is [System.Management.Automation.ErrorRecord]) { Write-S103Error -Label 'the transport' -Record $R } else { Write-OerLiveStep "subscriptions listed: $(@($R.value).Count); the test subscription among them: $(@($R.value | Where-Object { [string]$_.subscriptionId -eq [string]$Cfg.SubscriptionId }).Count -eq 1)" }
Write-OerLiveStep (Get-S103Sent)
Disconnect-OerLive
```

**Expect:** `records the ARM host: False; the session's cloud: Global`; at least one subscription and
`the test subscription among them: True`; Azure Resource Manager requests at least 1, all to
`management.azure.com`.
**Failure looks like:** an error, or a request to another host.

Result:

## 5. The messages (D)

### 5.1. A request refused after Disconnect-OER says Disconnect-OER ended the session

- [ ] **5.1** In `[pscustomobject]@{ SubscriptionId = ... } | ForEach-Object { Disconnect-OER; $_ } | Get-OERResourceGroup`, `Get-OERResourceGroup` signs in at its start, then `Disconnect-OER` ends the module's session before its request; the request is refused with `SignInSuperseded` and the message that `Disconnect-OER` ended the session, and nothing is sent.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
Start-S103Count
$E = $null
$Out = @([pscustomobject]@{ SubscriptionId = $Cfg.SubscriptionId } |
        ForEach-Object { Disconnect-OER -Confirm:$false -WarningAction SilentlyContinue; $_ } |
        Get-OERResourceGroup -ErrorAction SilentlyContinue -ErrorVariable E)
Stop-S103Count
Write-OerLiveStep "objects returned: $($Out.Count)"
Write-S103Errors -Label '5.1' -Errors $E -Ids @('SignInSuperseded')
Write-OerLiveStep (Get-S103Sent)
Write-OerLiveStep "After: $(Get-S103GraphSession); $(Get-S103ModuleView)"
Disconnect-OerLive
```

**Expect:** objects returned 0; one `SignInSuperseded` record targeting `Get-OERResourceGroup` whose
message is `Disconnect-OER ended the module's session after Get-OERResourceGroup began, so
Omnicit.EntraRBAC sends nothing while Get-OERResourceGroup runs: this request was not sent. Run
Disconnect-OER as a statement of its own, after the commands that use the session.`; token, Graph and
Azure Resource Manager requests 0; after: no Graph SDK session, no module state.
**Failure looks like:** an ARM request sent, or the old text that another command signed in to a
different tenant or identity.

Result:

### 5.2. A document refused after Disconnect-OER says it was not applied, and why

- [ ] **5.2** `Invoke-OERStructure -Json ... -WhatIf` with no `-TenantId`, followed in the pipeline by a `ForEach-Object` whose `-Begin` runs `Disconnect-OER`, refuses the document with `SignInSuperseded` and the message that `Disconnect-OER` ended the session and the document was not applied; nothing is requested.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
Start-S103Count
$Doc = [ordered]@{ version = '1.0'; groups = @([ordered]@{ displayName = 'oer-s103-never' }) } | ConvertTo-Json -Depth 5
$E = $null
$Out = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E |
        ForEach-Object -Begin { Disconnect-OER -Confirm:$false -WarningAction SilentlyContinue } -Process { $_ })
Stop-S103Count
Write-OerLiveStep "rows returned: $($Out.Count)"
Write-S103Errors -Label '5.2' -Errors $E -Ids @('SignInSuperseded')
Write-OerLiveStep (Get-S103Sent)
Disconnect-OerLive
```

**Expect:** rows returned 0; one `SignInSuperseded` record targeting `Invoke-OERStructure` whose message
is `Disconnect-OER ended the module's session after Invoke-OERStructure began, so Invoke-OERStructure
did not apply this document and Omnicit.EntraRBAC sent nothing for it. Run Disconnect-OER as a
statement of its own, after the commands that use the session.`; token, Graph and Azure Resource
Manager requests 0.
**Failure looks like:** a group read sent for `oer-s103-never`, or "this request was not sent".

Result:

### 5.3. A document refused after another identity signed in says it was not applied

- [ ] **5.3** The same pipeline whose `-Begin` signs in with `Connect-OER` as `oer-live-cc-noperm` refuses the document with `SignInSuperseded` and the message that another command signed in to a different tenant or identity and the document was not applied; nothing is requested for the document.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
$Doc = [ordered]@{ version = '1.0'; groups = @([ordered]@{ displayName = 'oer-s103-never' }) } | ConvertTo-Json -Depth 5
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
Start-S103Count
$E = $null
$Out = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E |
        ForEach-Object -Begin { Connect-OER -TenantId $Cfg.TenantId -ClientId $Cfg.NoPermAppId -Certificate $Cert -ErrorAction Stop } -Process { $_ })
Stop-S103Count
$Cert = $null
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is now signed in as oer-live-cc-noperm: $(& $M { param($Id) [bool]($script:_OERAuthState -and [string]$script:_OERAuthState.ClientId -eq $Id -and [string]$script:_OERAuthState.AuthMethod -eq 'ClientCertificate') } $Cfg.NoPermAppId)"
Write-OerLiveStep "rows returned: $($Out.Count)"
Write-S103Errors -Label '5.3' -Errors $E -Ids @('SignInSuperseded')
Write-OerLiveStep (Get-S103Sent)
Disconnect-OerLive
```

**Expect:** `signed in as oer-live-cc-noperm: True`; rows returned 0; one `SignInSuperseded` record
targeting `Invoke-OERStructure` whose message is `Another OER command in the same pipeline signed in to
a different tenant or identity after Invoke-OERStructure began, so Invoke-OERStructure did not apply
this document and Omnicit.EntraRBAC sent nothing for it. Run the commands as separate statements, so
that each one signs in and finishes before the next one starts.`; one token request (the noperm
sign-in), and only the Graph requests of that sign-in itself (none for the document).
**Failure looks like:** the document planned under the noperm identity, or "this request was not sent".

Result:

### 5.4. After a failed renewal in the same tenant, the A10 refusal no longer speaks of the tenant before

- [ ] **5.4** With the module's Graph token moved into its renewal window, a first `Get-OERSubscription` that names no tenant cannot renew an app-only session (`AppOnlySessionCredentialUnavailable`) and sends nothing; a second one is refused with `SignInRefused` and the new A10 message, which does not say the session may belong to the tenant before; nothing is sent, and `Disconnect-OER` makes the module send again.

```powershell
Connect-OerLive -Arm
Start-S103NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
# The same tenant, the same identity: only the Graph token's recorded expiry moves into the five-minute
# renewal window (measured to force a renewal, Sprint 9). An app-only session cannot renew, since the
# module keeps no certificate: that is the failed renewal BL-93 names.
& $M { $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2) }
Start-S103Count
$E1 = $null
$O1 = @(Get-OERSubscription -ErrorAction SilentlyContinue -ErrorVariable E1)
Write-OerLiveStep "first: objects returned $($O1.Count)"
Write-S103Errors -Label 'first' -Errors $E1 -Ids @('AppOnlySessionCredentialUnavailable', 'SignInRefused')
$E2 = $null
$O2 = @(Get-OERSubscription -ErrorAction SilentlyContinue -ErrorVariable E2)
Write-OerLiveStep "second: objects returned $($O2.Count)"
Write-S103Errors -Label 'second' -Errors $E2 -Ids @('SignInRefused')
$A10 = @($E2 | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).StartsWith('SignInRefused,') } | Select-Object -First 1)
Write-OerLiveStep "The A10 message speaks of the tenant before: $(@($A10).Count -eq 1 -and ([string]$A10[0].Exception.Message).Contains('tenant before'))"
Stop-S103Count
Write-OerLiveStep (Get-S103Sent)
Disconnect-OER -Confirm:$false
Write-OerLiveStep "After Disconnect-OER: the marker is clear: $(& $M { -not [bool]$script:_OERSessionUncertain })"
Disconnect-OerLive
```

**Expect:** first: objects returned 0, an `AppOnlySessionCredentialUnavailable` record (it names the
tenant, redacted) and a `SignInRefused` record for its refused ARM request; second: objects returned 0
and a `SignInRefused` record targeting `Get-OERSubscription` whose message is `An earlier sign-in in this
PowerShell session failed or was refused, so the module's session may not be the one that sign-in
asked for, and Omnicit.EntraRBAC sends nothing for a command that names no tenant: this request was not sent.
Name the tenant with -TenantId, or run Connect-OER or Disconnect-OER, to send requests again.`; `The
A10 message speaks of the tenant before: False`; token, Graph and Azure Resource Manager requests 0;
the marker clear after `Disconnect-OER`.
**Failure looks like:** a token request (a renewal was attempted), an ARM request sent, or the old text
("may still belong to the tenant before it").

Result:

## Teardown

### T.1. Nothing left: no session, no profile folder, nothing with the prefix

- [ ] **T.1** No module state and no Graph SDK session is left in the process; the temporary profile folder is deleted; the sweep finds nothing with the prefix `oer-s103-` in the tenant.

```powershell
Connect-OerLive -Graph
Start-S103NoPrompt
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "After Disconnect-OerLive: $(Get-S103GraphSession)"
if (Test-Path -LiteralPath $ProfileDir) { Remove-Item -LiteralPath $ProfileDir -Recurse -Force }
Write-OerLiveStep "The temporary profile folder is gone: $(-not (Test-Path -LiteralPath $ProfileDir))"
```

**Expect:** objects with the prefix 0, unread collections 0; `Graph SDK session present: False`; the
temporary profile folder gone `True`.
**Failure looks like:** an object with the prefix -- this file creates none, so it is someone else's
and a stop; an unread collection -- the sweep is not a proof of absence.

Result:
