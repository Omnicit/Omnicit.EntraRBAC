# Live verification checklist -- the sign-in and the profile findings (fix/sign-in-and-profile-findings)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.** A box with no
result line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible to run,
write "cannot be verified, and therefore we do not know" on its result line and say why; do not leave it blank and
do not tick it. A check that could not run for a stated reason is marked `[~]`, never `[x]`. **Section B lists what
is proved offline only (class B), and section C the one manual check (class C), the operator's optional check.**

**What this file writes to the tenant: nothing.** No check creates, changes or deletes a tenant object, so there is
no prerequisite script and no tenant teardown. What the checks write is local: a tenant profile under the step's
raw folder (`raw\s1113\profiles\`, never the operator's real profile folder), an export document under
`raw\s1113\exports\`, and the child processes' output files under `raw\s1113\`. T.1 deletes the raw folder.

**The tenant's object names are never printed.** The blocks print counts, True/False, error ids and the step's own
prefixed names only.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which lives beside the
operator's copy of this file outside the repository (the repository's `docs/live-verification/README.md`, first
paragraph). Every sign-in is app-only, with the certificate; nothing here signs in as a person. Section 3 starts a
host with no session at all and expects it to sign in to nothing. A 401 or 403 is a stop.

**Permissions.** The reads use the permissions `oer-live-cc` already holds. Granting a permission is the operator's
decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER` and
`Disconnect-MgGraph` first and then checks the identity as True/False, or through `Connect-OER` with the
certificate in 1.2; every block that runs the module installs the no-prompt fence (H.1) right after loading it.

**Redact before you commit.** Every block prints through the library's redactor. **No credential, token, application
id, tenant id, subscription id, account or certificate thumbprint is ever printed.** Each block is run in its own
process whose WHOLE output (every stream) is written to a file outside the repository, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main` before it
merges.

- **A. The profile file** ("fix: escape every single quote PowerShell reads as one in the tenant profile file",
  BL-113). `Export-OERConfiguration` escapes U+0027, U+2018, U+2019, U+201A and U+201B in keys, list values and
  values, so such a character no longer ends the literal, breaks the profile or adds a key (for example
  `Environment`).
- **B. The examples in messages** ("fix: escape the value in the copy-paste examples of messages", BL-113): every
  example command in an error or warning escapes the value it quotes.
- **C. The sign-in** (BL-115, BL-100, BL-20): an interactive session is renewed with a non-interactive
  `Get-AzToken` in the same tenant first (AzAuth 2.11.0, the new floor); a host started with `-NonInteractive`
  refuses an interactive sign-in with `InteractiveSignInUnavailable` before any token request.
- **D. The reports** (BL-37, BL-78, BL-157, BL-111): `Resolve-OERScope` throws typed records; `New-OERGroup`
  names a refused sign-in in `GroupResolveFailed`; `Get-OERInventory` names no tenant after its own refused
  sign-in; `-TenantId` of the profile cmdlets refuses invisible formatting characters.

A live tenant is needed for what the unit tests cannot show: that the module still signs in and reads with the
real AzAuth 2.11.0; that a profile carrying every single-quote character is written, read and used for a real
sign-in in the right tenant and cloud; that a real refused sign-in leaves `Get-OERInventory`'s document naming no
tenant; and that a real `pwsh -NonInteractive` host is refused at once instead of waiting for a browser.

## What this file does not check, and why

- **The silent renewal of an interactive session (class C, C.1).** It needs a person's interactive sign-in, which
  this identity never makes. Offline, the unit tests prove which calls go silent and that a failed silent call
  falls back exactly once (B.1); AzAuth 2.11.0's own source proves the reuse (B.1).
- **The escaped examples in messages (class B, B.2)**, the typed `Resolve-OERScope` records (B.3), the
  `GroupResolveFailed` text after a refused lookup (B.4), the invisible `-TenantId` refusal (B.5) and the BL-20
  shape (B.6): each is a message or a binding decision the unit tests read exactly; no tenant state changes them.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads beside it.
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc`, enabled for the run.
- The **built module of this branch** in the step's own worktree, built there with `./build.ps1 -Tasks build`, and
  the environment variable `OER_LIVE_REPO` naming that worktree. Its `output\RequiredModules` holds AzAuth 2.11.0.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fence and the readers. Nothing
here signs in or writes to the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1113-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = [System.IO.Path]::GetFullPath($env:OER_LIVE_REPO).TrimEnd('\', '/') }
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$null = New-Item -ItemType Directory -Path $Raw -Force
$Prefix = 'oer-s1113-'
$NewIds = 'InteractiveSignInUnavailable', 'Test-OERHostNonInteractive', '_OERInteractiveCredential', 'EscapeSingleQuotedStringContent'

function Start-S1113NoPrompt {
    # A token request without the certificate would be an interactive or device-code sign-in: refuse it, count all.
    $global:S1113TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S1113TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S1113 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S1113Count {
    # Counts every request the module sends and refuses every write: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest.
    $global:S1113Graph = 0
    $global:S1113Arm = 0
    $Fence = 'if ($PSBoundParameters.ContainsKey(''Method'') -and ([string]$Method).ToUpperInvariant() -ne ''GET'') { throw ''S1113 fence: a write request was refused.'' }'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S1113Graph++; $Fence; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S1113Arm++; $Fence; Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S1113Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S1113IdCounts {
    # "id xN" for each distinct first id segment of a set of records (an ErrorRecord, or one an exception carries).
    param($Records)
    $Ids = foreach ($R in @($Records)) {
        $Rec = if ($R -is [System.Management.Automation.ErrorRecord]) { $R } elseif ($R -is [System.Management.Automation.IContainsErrorRecord]) { $R.ErrorRecord } else { $null }
        if ($Rec) { ([string]$Rec.FullyQualifiedErrorId -split ',')[0] }
    }
    (@($Ids) | Group-Object | Sort-Object Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', '
}

function Get-S1113Quotes {
    # The five characters PowerShell reads as a single quote, by code point (this file stays ASCII).
    @([char]0x27, [char]0x2018, [char]0x2019, [char]0x201A, [char]0x201B)
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Found = @(foreach ($Id in $NewIds) { '{0}: {1}' -f $Id, [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Id -Quiet) })
Write-OerLiveStep "The branch build ($((Split-Path -Leaf (Split-Path -Parent $Psm1.FullName)))): $($Found -join '; ')"
$Psd1 = Import-PowerShellDataFile -LiteralPath ($Psm1.FullName -replace '\.psm1$', '.psd1')
Write-OerLiveStep "The build's AzAuth floor: $(@($Psd1.RequiredModules | Where-Object { $_.ModuleName -eq 'AzAuth' } | ForEach-Object { $_.ModuleVersion }) -join ',')"
Write-OerLiveStep "AzAuth versions in the build's RequiredModules: $(@(Get-ChildItem -Directory -Path (Join-Path $Cfg.Repo 'output\RequiredModules\AzAuth') | ForEach-Object Name) -join ',')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on `main`; the
worktree on this branch with 0 tracked changes; `True` on every mark; the floor `2.11.0`; `2.11.0` among the AzAuth
versions.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone; a `False`
mark -- build the worktree first; a floor of `2.9.0`.

Result: 2026-10-22 00:45 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113] The module loads from a worktree that is not the main clone: True
[oer-s1113] Main clone: branch main
[oer-s1113] Worktree: branch fix/sign-in-and-profile-findings; HEAD e8f107f fix: correct the renewal and refusal texts and close the final review findings; tracked changes: 0
[oer-s1113] The branch build (1.3.1): InteractiveSignInUnavailable: True; Test-OERHostNonInteractive: True; _OERInteractiveCredential: True; EscapeSingleQuotedStringContent: True
[oer-s1113] The build's AzAuth floor: 2.11.0
[oer-s1113] AzAuth versions in the build's RequiredModules: 2.11.0
```

## 0. Sign-in and a read with AzAuth 2.11.0

### 0.1. Connect-OER as oer-live-cc and a reading command, with AzAuth 2.11.0

- [x] **0.1** The module session passes the identity check with AzAuth 2.11.0 loaded, and `Get-OERSubscription` and `Get-OERGroup` read, sending no write and requesting no token without the certificate. #type/subtask

```powershell
Connect-OerLive -Arm
Start-S1113NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Write-OerLiveStep "AzAuth loaded: $(@(Get-Module -Name AzAuth | ForEach-Object { $_.Version.ToString() }) -join ',')"
Start-S1113Count
$Subs = @(Get-OERSubscription -ErrorAction SilentlyContinue -ErrorVariable SubErr)
$Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue -ErrorVariable GrpErr)
Stop-S1113Count
Write-OerLiveStep "Subscriptions read: $($Subs.Count -gt 0); test subscription among them: $(@($Subs | Where-Object { [string]$_.SubscriptionId -eq $Cfg.SubscriptionId }).Count -eq 1); errors: [$(Get-S1113IdCounts $SubErr)]"
Write-OerLiveStep "Groups read: $($Groups.Count) (any number is fine); errors: [$(Get-S1113IdCounts $GrpErr)]"
Write-OerLiveStep "Requests: Microsoft Graph $global:S1113Graph, Azure Resource Manager $global:S1113Arm; token requests after the sign-in: $global:S1113TokenCalls"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, the worktree's build, AzAuth `2.11.0`; subscriptions
read with the test subscription among them and no error; a group count with no error; at least one request in each
transport; 0 token requests after the sign-in (the session is cached).
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), AzAuth `2.10.0`, an error id,
or a fence refusal.

Result: 2026-10-22 00:45 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed on run 2. Run 1 stopped at a checklist error, not a module one: Get-OERGroup -Filter with -All is no parameter set; the block now uses -Filter alone, with a filter that matches groups (a prefix filter matching nothing answers GroupNotFound, existing behaviour).
[oer-s1113] Omnicit.EntraRBAC 1.3.1 loaded from REPO\.claude\worktrees\s11-steg13\output\module\Omnicit.EntraRBAC\1.3.1.
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s1113] The module is the worktree's build: True; version 1.3.1
[oer-s1113] AzAuth loaded: 2.11.0
[oer-s1113] Subscriptions read: True; test subscription among them: True; errors: []
[oer-s1113] Groups read: 93 (any number is fine); errors: []
[oer-s1113] Requests: Microsoft Graph 1, Azure Resource Manager 1; token requests after the sign-in: 0
```

## 1. A profile with every single-quote character

### 1.1. The profile is written, changed and read back unchanged, and no value adds a key

- [x] **1.1** `New-OERConfiguration` and `Set-OERConfiguration` write a profile in the step's raw folder whose Naming and Defaults carry each of the five characters in a key, a value and a list item, plus a value built to close the literal and add `Environment`; `Get-OERConfiguration` reads every value back unchanged, and the file has exactly the keys written. #type/subtask

```powershell
& (Get-Module -Name OerLive) { Import-OerLiveModule }
$ProfDir = Join-Path $Raw 'profiles'
$null = New-Item -ItemType Directory -Path $ProfDir -Force
$Alias = 'oer-s1113-quotes'
$Q = Get-S1113Quotes
$Naming = [ordered]@{}
$Defaults = [ordered]@{}
for ($I = 0; $I -lt $Q.Count; $I++) {
    $Naming["key$I$($Q[$I])x"] = "value$I$($Q[$I])x"
    $Defaults["list$I"] = @("item$I$($Q[$I])a", "item$I$($Q[$I])b")
    $Defaults["inject$I"] = "x$($Q[$I]); Environment = $($Q[$I])China"
}
New-OERConfiguration -TenantAlias $Alias -TenantId $Cfg.TenantId -Naming ([hashtable]$Naming) -BasePath $ProfDir -ErrorAction Stop
Set-OERConfiguration -TenantAlias $Alias -Defaults ([hashtable]$Defaults) -BasePath $ProfDir -ErrorAction Stop
$File = Join-Path $ProfDir "$Alias.psd1"
$Data = Import-PowerShellDataFile -LiteralPath $File
$Read = Get-OERConfiguration -TenantAlias $Alias -BasePath $ProfDir -ErrorAction Stop
if ($Data -isnot [hashtable] -or $null -eq $Read) { throw 'S1113: the profile was not written, did not parse or was not read back.' }
$NamingOk = @($Naming.Keys | Where-Object { -not ($Data.Naming.ContainsKey($_) -and $Data.Naming[$_] -ceq $Naming[$_]) }).Count -eq 0
$ListOk = @(0..4 | Where-Object { (@($Data.Defaults["list$_"]) -join '|') -cne (@($Defaults["list$_"]) -join '|') }).Count -eq 0
$InjectOk = @(0..4 | Where-Object { $Data.Defaults["inject$_"] -cne $Defaults["inject$_"] }).Count -eq 0
Write-OerLiveStep "The file parses: $($Data -is [hashtable]); top-level keys: $(@($Data.Keys | Sort-Object) -join ',')"
Write-OerLiveStep "Naming keys and values unchanged: $NamingOk; list items unchanged: $ListOk; the built values unchanged: $InjectOk"
Write-OerLiveStep "Defaults keys: $(@($Data.Defaults.Keys).Count) (expected 10); an Environment key anywhere: $($Data.ContainsKey('Environment') -or $Data.Defaults.ContainsKey('Environment') -or $Data.Naming.ContainsKey('Environment'))"
Write-OerLiveStep "Get-OERConfiguration: alias $([string]$Read.TenantAlias -ceq $Alias); tenant is the test tenant: $([string]$Read.TenantId -eq $Cfg.TenantId); Environment: '$([string]$Read.Environment)'"
```

**Expect:** the file parses, top-level keys `Defaults,Naming,TenantId`; `True` on all three unchanged checks; 10
Defaults keys and `False` for an Environment key; the alias and tenant `True` and an empty Environment.
**Failure looks like:** a parse error, a top-level `Environment` key, or a value read back changed.

Result: 2026-10-22 00:45 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed on run 2. Run 1 called Import-OerLiveModule, which OerLive does not export; the block now calls it in OerLive's scope and throws when the profile was not written, parsed or read back (run 1's hard-coded 'parses: True' hid that).
[oer-s1113] Omnicit.EntraRBAC 1.3.1 loaded from REPO\.claude\worktrees\s11-steg13\output\module\Omnicit.EntraRBAC\1.3.1.
[oer-s1113] The file parses: True; top-level keys: Defaults,Naming,TenantId
[oer-s1113] Naming keys and values unchanged: True; list items unchanged: True; the built values unchanged: True
[oer-s1113] Defaults keys: 10 (expected 10); an Environment key anywhere: False
[oer-s1113] Get-OERConfiguration: alias True; tenant is the test tenant: True; Environment: ''
TenantAlias      TenantId                             Environment Path
-----------      --------                             ----------- ----
oer-s1113-quotes 00000000-0000-0000-0000-000000000004             REPO\docs\live-verification\raw\…
oer-s1113-quotes 00000000-0000-0000-0000-000000000004             REPO\docs\live-verification\raw\…
```

### 1.2. Connect-OER -TenantAlias signs in with that profile, in the test tenant and the Global cloud

- [x] **1.2** `Connect-OER -TenantAlias oer-s1113-quotes -BasePath` the raw profile folder, with the certificate, signs in as oer-live-cc in the test tenant and the Global cloud, and a read follows. #type/subtask

```powershell
& (Get-Module -Name OerLive) { Import-OerLiveModule }
Start-S1113NoPrompt
Disconnect-OerLive
$ProfDir = Join-Path $Raw 'profiles'
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\{0}' -f $Cfg.CertificateThumbprint) -ErrorAction Stop
try { $null = Connect-OER -TenantAlias 'oer-s1113-quotes' -BasePath $ProfDir -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction Stop } finally { $Cert = $null }
$S = & (Get-Module -Name Omnicit.EntraRBAC) { $script:_OERAuthState }
Write-OerLiveStep "Session: app-only certificate $([string]$S.AuthMethod -eq 'ClientCertificate'); client is the identity $(([string]$S.ClientId).ToLowerInvariant() -eq $Cfg.AppId); tenant is the test tenant $(([string]$S.TokenTenantId).ToLowerInvariant() -eq $Cfg.TenantId); cloud '$([string]$S.Environment)'"
$S = $null
Start-S1113Count
$Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -ErrorAction SilentlyContinue -ErrorVariable GrpErr)
Stop-S1113Count
Write-OerLiveStep "Groups read: $($Groups.Count); errors: [$(Get-S1113IdCounts $GrpErr)]; Microsoft Graph requests $global:S1113Graph; token requests $global:S1113TokenCalls"
Disconnect-OerLive
```

**Expect:** `True` on the three session checks and cloud `Global`; a group count with no error; 1 token request (the
certificate sign-in).
**Failure looks like:** a parse error of the profile (the old writer), cloud `China`, or a fence refusal.

Result: 2026-10-22 00:45 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed on its first run with the corrected module import.
[oer-s1113] Omnicit.EntraRBAC 1.3.1 loaded from REPO\.claude\worktrees\s11-steg13\output\module\Omnicit.EntraRBAC\1.3.1.
[oer-s1113] Session: app-only certificate True; client is the identity True; tenant is the test tenant True; cloud 'Global'
[oer-s1113] Groups read: 93; errors: []; Microsoft Graph requests 1; token requests 1
```

## 2. Get-OERInventory after its own refused sign-in names no tenant (BL-157)

### 2.1. A refused sign-in after a session of the test tenant leaves the document without a tenantId

- [x] **2.1** After a session in the test tenant, `Get-OERInventory -TenantId` a domain that names no tenant is refused (`TenantResolutionFailed`), carries on as before (no try) and emits a partial document whose `TenantId` is empty, sending no Microsoft Graph or Azure Resource Manager request. #type/subtask

```powershell
# The block runs as a script file in a child process with no try around the call, as at a prompt.
$Child = Join-Path $Raw 'block-2-1.ps1'
@'
param($VaultDir, $Repo, $Out)
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s1113-' -ConfigDirectory $VaultDir
$Cfg.Repo = $Repo
Connect-OerLive -Arm
$Before = & (Get-Module -Name Omnicit.EntraRBAC) { [string]$script:_OERAuthState.TokenTenantId }
$global:Graph = 0
$Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:Graph++; throw 'S1113 fence: no Graph request is expected here.' }"))
$global:Tokens = 0
$Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:Tokens++; throw 'S1113 fence: no token request is expected here.' }"))
$Error.Clear()
$Inv = Get-OERInventory -TenantId 'oer-sovereign-verify-doesnotexist.onmicrosoft.com' -Include Groups -ErrorVariable InvErr
$Ids = foreach ($R in @($Error)) { $Rec = if ($R -is [System.Management.Automation.ErrorRecord]) { $R } elseif ($R -is [System.Management.Automation.IContainsErrorRecord]) { $R.ErrorRecord }; if ($Rec) { ([string]$Rec.FullyQualifiedErrorId -split ',')[0] } }
[ordered]@{
    SessionTenantWasTest = ($Before.ToLowerInvariant() -eq $Cfg.TenantId)
    Emitted = [bool]$Inv
    Type = if ($Inv) { $Inv.PSObject.TypeNames[0] } else { '' }
    TenantIdEmpty = if ($Inv) { [string]::IsNullOrEmpty([string]$Inv.TenantId) } else { $null }
    TenantIdIsTest = if ($Inv) { ([string]$Inv.TenantId).ToLowerInvariant() -eq $Cfg.TenantId } else { $null }
    Errors = ((@($Ids) | Group-Object | Sort-Object Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', ')
    Graph = $global:Graph; Tokens = $global:Tokens
} | ConvertTo-Json | Set-Content -LiteralPath $Out -Encoding utf8NoBOM
Remove-Item -Path function:Invoke-MgGraphRequest, function:Get-AzToken
Disconnect-OerLive
'END'
'@ | Set-Content -LiteralPath $Child -Encoding utf8NoBOM
$Out = Join-Path $Raw 'result-2-1.json'
$Log = Join-Path $Raw 'block-2-1.log'
& pwsh -NoProfile -File $Child -VaultDir $VaultDir -Repo $Cfg.Repo -Out $Out *> $Log
$R = Get-Content -LiteralPath $Out -Raw | ConvertFrom-Json
Write-OerLiveStep "Child process ended with END: $([bool](Select-String -LiteralPath $Log -SimpleMatch 'END' -Quiet))"
Write-OerLiveStep "Session tenant before was the test tenant: $($R.SessionTenantWasTest); document emitted: $($R.Emitted) ($($R.Type)); its TenantId empty: $($R.TenantIdEmpty); names the test tenant: $($R.TenantIdIsTest)"
Write-OerLiveStep "Errors: [$($R.Errors)]; Microsoft Graph requests: $($R.Graph); token requests: $($R.Tokens)"
```

**Expect:** `END`; the session tenant `True`; a document `Omnicit.EntraRBAC.Inventory`, TenantId empty `True`,
names the test tenant `False`; errors `TenantResolutionFailed x1` and the partial and refusal records the section
writes (`InventoryPartial`, and `SignInRefused` for the refused read, if any); 0 Graph requests and 0 token requests.
**Failure looks like:** the document naming the test tenant (the defect), a Graph request, or a token request.

Result: 2026-10-22 00:45 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113] Child process ended with END: True
[oer-s1113] Session tenant before was the test tenant: True; document emitted: True (Omnicit.EntraRBAC.Inventory); its TenantId empty: True; names the test tenant: False
[oer-s1113] Errors: [InventoryPartial x1, TenantResolutionFailed x1]; Microsoft Graph requests: 0; token requests: 0
```

## 3. A host started with -NonInteractive is refused at once (BL-100)

### 3.1. With no session, an interactive sign-in is refused before any token request, without waiting

- [x] **3.1** In `pwsh -NoProfile -NonInteractive` with no session, `Get-OERGroup` and `Connect-OER -Interactive` are each refused with `InteractiveSignInUnavailable` within seconds, no token request and no tenant lookup sent; the same `Get-OERGroup` in a host without `-NonInteractive`, under a fence that refuses every token request, reaches the token request instead. #type/subtask

```powershell
$Child = Join-Path $Raw 'block-3-1.ps1'
@'
param($Repo, $Out)
$Front = @((Join-Path $Repo 'output\module'), (Join-Path $Repo 'output\RequiredModules'))
$env:PSModulePath = ($Front -join [System.IO.Path]::PathSeparator) + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$global:Tokens = 0; $global:Lookups = 0; $global:Graph = 0
foreach ($Name in 'Get-AzToken', 'Invoke-RestMethod', 'Invoke-MgGraphRequest') {
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name $Name -CommandType Cmdlet))
    $Counter = @{ 'Get-AzToken' = 'Tokens'; 'Invoke-RestMethod' = 'Lookups'; 'Invoke-MgGraphRequest' = 'Graph' }[$Name]
    Set-Item -Path "function:global:$Name" -Value ([scriptblock]::Create([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:$Counter++; throw 'S1113 fence: refused.' }"))
}
$Rows = foreach ($Call in 'Get-OERGroup -All', 'Connect-OER -Interactive') {
    $Error.Clear()
    $W = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-Expression $Call
    $W.Stop()
    $Ids = foreach ($R in @($Error)) { $Rec = if ($R -is [System.Management.Automation.ErrorRecord]) { $R } elseif ($R -is [System.Management.Automation.IContainsErrorRecord]) { $R.ErrorRecord }; if ($Rec) { ([string]$Rec.FullyQualifiedErrorId -split ',')[0] } }
    [ordered]@{ Call = $Call; Seconds = [math]::Round($W.Elapsed.TotalSeconds, 1); Errors = ((@($Ids) | Group-Object | Sort-Object Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', ') }
}
[ordered]@{ Rows = @($Rows); Tokens = $global:Tokens; Lookups = $global:Lookups; Graph = $global:Graph } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Out -Encoding utf8NoBOM
'END'
'@ | Set-Content -LiteralPath $Child -Encoding utf8NoBOM
foreach ($Mode in 'NonInteractive', 'Interactive') {
    $Out = Join-Path $Raw "result-3-1-$Mode.json"
    $Log = Join-Path $Raw "block-3-1-$Mode.log"
    $PwshArgs = @('-NoProfile') + $(if ($Mode -eq 'NonInteractive') { @('-NonInteractive') } else { @() }) + @('-File', $Child, '-Repo', $Cfg.Repo, '-Out', $Out)
    $W = [System.Diagnostics.Stopwatch]::StartNew()
    & pwsh @PwshArgs *> $Log
    $W.Stop()
    $R = Get-Content -LiteralPath $Out -Raw | ConvertFrom-Json
    Write-OerLiveStep "Host $($Mode): ended with END $([bool](Select-String -LiteralPath $Log -SimpleMatch 'END' -Quiet)) after $([math]::Round($W.Elapsed.TotalSeconds, 1)) s; token requests $($R.Tokens); tenant lookups $($R.Lookups); Microsoft Graph requests $($R.Graph)"
    foreach ($Row in @($R.Rows)) { Write-OerLiveStep "  $($Row.Call): $($Row.Seconds) s; errors [$($Row.Errors)]" }
}
```

**Expect:** `NonInteractive`: `END`, 0 token requests, 0 lookups, 0 Graph requests; both calls in under 5 s, each
with `InteractiveSignInUnavailable x1` (and, for `Get-OERGroup`, the refused request's `SignInRefused`). `Interactive`
(the control): `END`; `Get-OERGroup` reaches the fence (token requests 1 or more, `GraphTokenAcquisitionFailed`),
no `InteractiveSignInUnavailable`. No browser opens in either host: the fence refuses every token request.
**Failure looks like:** a token request in the `NonInteractive` host, a wait near 120 s, or `InteractiveSignInUnavailable`
in the control host.

Result: 2026-10-22 00:45 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113] Host NonInteractive: ended with END True after 2.6 s; token requests 0; tenant lookups 0; Microsoft Graph requests 0
[oer-s1113]   Get-OERGroup -All: 0.5 s; errors [InteractiveSignInUnavailable x1, SignInRefused x1]
[oer-s1113]   Connect-OER -Interactive: 0.2 s; errors [InteractiveSignInUnavailable x1]
[oer-s1113] Host Interactive: ended with END True after 2.7 s; token requests 2; tenant lookups 0; Microsoft Graph requests 0
[oer-s1113]   Get-OERGroup -All: 0.5 s; errors [GraphTokenAcquisitionFailed x1, SignInRefused x1]
[oer-s1113]   Connect-OER -Interactive: 0.1 s; errors [GraphTokenAcquisitionFailed x1]
```

## B. Proved offline (class B)

- **B.1** The silent renewal (A22, BL-115): which calls go silent (only a renewal of an `Interactive` session of the
  same tenant, client and cloud, not Connect-OER, not under Force or a claims challenge, only while AzAuth holds the
  credential of that resource's client), that a failed or foreign silent token falls back to the interactive call
  exactly once, and the AzAuth 2.11.0 reuse itself (its source, `TokenManager.NonInteractive.cs:71`, PR 236).
  `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`.
- **B.2** The escaped examples in messages: `tests/Unit/Public` and `tests/Unit/Private` files of each changed
  cmdlet, Contexts named BL-113.
- **B.3** `Resolve-OERScope`'s typed records: `tests/Unit/Private/Resolve-OERScope.Tests.ps1`.
- **B.4** `GroupResolveFailed` naming a refused sign-in: `tests/Unit/Public/New-OERGroup.Tests.ps1`.
- **B.5** The invisible `-TenantId`: the BL-111 Contexts of the New- and Set-OERConfiguration test files.
- **B.6** BL-20's measured shape (one sign-in failure record, the refused request's `SignInRefused`, no warning):
  `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`.

## C. Manual (class C, optional, after the merge)

- [ ] **C.1** The operator signs in interactively (`Connect-OER -TenantId` the test tenant), waits until the Microsoft Graph token is within five minutes of its expiry (or moves `GraphTokenExpiry` in module scope), and runs a Graph read: it answers without a browser, `-Verbose` shows the silent renewal, and the state carries the same account. #type/subtask

Result:

## T. Teardown

### T.1. The step's raw folder is gone, and nothing was created in the tenant

- [x] **T.1** The raw folder `raw\s1113\` (profile, export, child output) is deleted, and no object with the prefix exists in the tenant. #type/subtask

```powershell
Connect-OerLive -Arm
$Found = Invoke-OerLiveGraph -All -Uri "v1.0/groups?`$filter=startswith(displayName,'$Prefix')&`$select=id"
Write-OerLiveStep "Groups with the prefix: $(@($Found.Body['value']).Count)"
Disconnect-OerLive
Remove-Item -LiteralPath $Raw -Recurse -Force
Write-OerLiveStep "Raw folder gone: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** 0 groups with the prefix; `Raw folder gone: True`.
**Failure looks like:** a prefixed object (STOP: this file creates none) or the folder still there.

Result: 2026-10-22 00:45 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Passed.
[oer-s1113] Omnicit.EntraRBAC 1.3.1 loaded from REPO\.claude\worktrees\s11-steg13\output\module\Omnicit.EntraRBAC\1.3.1.
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s1113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s1113] Groups with the prefix: 0
[oer-s1113] Raw folder gone: True
```
