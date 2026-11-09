# Live verification checklist -- typed throws and the Graph next link (fix/typed-exception-throws)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. No object is created, changed or removed, and no
object of the prefix `oer-s143-` exists before or after the run. Every check that signs in runs
with a request fence in the module's scope that refuses every request other than a read, and with a
token fence that refuses every token request after the sign-in. Check 2.1 also sends the module's one
unauthenticated request, the OpenID discovery lookup of the tenant domain, to the public authority:
no token and nothing written.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A Graph next link goes only to the session's Graph host** (`fix: send a Graph next link only to
  the session's Graph host`): `Invoke-OERGraphRequest -All` refuses an `@odata.nextLink` that is not
  https on the host and port of the session cloud's Microsoft Graph address, with
  `GraphPagingIncomplete`, before it is requested. Live shows that a real walk of many pages is
  followed as before and that every link Microsoft Graph hands out is on that host.
- **B. Three private helpers throw typed records** (`fix: throw typed records from three private
  helpers`): the tenant lookup, the directory role name map and the rename registration. The
  published records are unchanged; live shows the two the tenant can produce.
- **C. Gate 11 sees more shapes** (`test: gate 11 sees more string shapes and exception throws`): a
  source gate, nothing to run live.

## What this file does not check, and why

- **A next link on another host** is class B: it is never sent live. The unit tests hold it: the
  Describe `Invoke-OERGraphRequest -All sends a next link only to the session's Graph host (BL-179,
  A10)` and the probe `S20` of `Invoke-OERGraphRequest stops at each of its own throws, outside any
  try (F3)` in `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`.
- **A sovereign cloud** cannot be reached from the test tenant; the unit tests hold the USGov,
  USGovDoD and China hosts.
- **The rename registration refusal** is a caller error no public command can produce.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm` enabled for the
  run. This file adds no permission to either.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.
- No prerequisite script: nothing is created.

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block).

### H.1. The helpers every check uses

- [ ] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s143-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$MissingDomain = 'oer-s143-missing.invalid'
function Install-S143Fence {
    $script:S143Module = Get-Module -Name Omnicit.EntraRBAC
    $global:S143TokenRequests = 0
    function global:Get-AzToken { $global:S143TokenRequests++; throw 'S143 fence: no token request is expected here.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S143Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S143Module {
        $script:S143Writes = 0
        $script:S143Pages = [System.Collections.Generic.List[object]]::new()
        $script:S143RealGraph = ${function:Invoke-OERGraphRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            if ($Method -ne 'GET') { $script:S143Writes++; throw "S143 fence: a $Method request was refused." }
            & $script:S143RealGraph @PSBoundParameters
        }
        # Records, for every request the transport sends, whether its address is absolute and on the
        # session's Graph host -- never the address itself. It declares only what a read without
        # -ExpectedErrorCode passes (the checks below use none).
        function script:Invoke-MgGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [uri]$Uri, $Body)
            $SessionHost = ([uri](Get-OERCloudEndpoint -Environment ([string]$script:_OERAuthState.Environment)).GraphResource).IdnHost
            $script:S143Pages.Add([PSCustomObject]@{ Absolute = $Uri.IsAbsoluteUri; OnHost = ($Uri.IsAbsoluteUri -and [string]::Equals($Uri.IdnHost, $SessionHost, [System.StringComparison]::OrdinalIgnoreCase) -and $Uri.Scheme -ceq 'https') })
            Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fence and page recorder in place: $((& $script:S143Module { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString().Contains('S143 fence') -and (Get-Command Invoke-MgGraphRequest).CommandType -eq 'Function' }))"
}
function Connect-S143 {
    param([switch]$NoPerm)
    if ($NoPerm) { Connect-OerLive -Arm -NoPerm } else { Connect-OerLive -Arm }
    Write-OerLiveStep "The module is the worktree's build: $((Get-Module -Name Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    Install-S143Fence
}
function Show-S143Walk {
    param([string]$Label, $Result, [int]$Expected)
    $Pages = @(& $script:S143Module { $script:S143Pages })
    $Later = @($Pages | Select-Object -Skip 1)
    Write-OerLiveStep "${Label}: pages $($Pages.Count); items $(@($Result.value).Count); equal to the independent read ($Expected): $(@($Result.value).Count -eq $Expected)"
    Write-OerLiveStep "${Label}: page 1 sent as a relative path: $($Pages.Count -gt 0 -and -not $Pages[0].Absolute)"
    Write-OerLiveStep "${Label}: every next link absolute https on the session's Graph host: $($Later.Count -gt 0 -and @($Later | Where-Object { -not $_.OnHost }).Count -eq 0)"
    Write-OerLiveStep "${Label}: writes $(& $script:S143Module { $script:S143Writes }); token requests after the sign-in $global:S143TokenRequests"
}
function Get-S143Refusal {
    param([scriptblock]$Call)
    $Error.Clear()
    $Caught = $null
    try { & $Call } catch { $Caught = $PSItem }
    $Caught
}
```

**Expect:** nothing printed.
**Failure looks like:** a parse error -- fix the block before any check runs.

Result:

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and nothing with the prefix exists. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Get-Content -LiteralPath (Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1') -Raw
Write-OerLiveStep "The build carries A: $($Psm1.Contains("does not address the Microsoft Graph host of the session's cloud"))"
$TenantMarker = $Psm1 -match '\$RequestError\.Exception\),\s+''TenantResolutionFailed'''
$MapMarker = $Psm1 -match '\$PSItem\.Exception\),\s+''AdministrativeUnitScopedRoleReadFailed'''
Write-OerLiveStep "The build carries B (tenant lookup): $TenantMarker"
Write-OerLiveStep "The build carries B (role name map): $MapMarker"
Write-OerLiveStep "The build carries B (rename registration): $($Psm1.Contains("'RenameRegistrationInvalid'"))"
Connect-OerLive -Graph
$Before = @(Find-OerLivePrefixed -Prefix 'oer-s143-' -Quiet)
Write-OerLiveStep "Objects with the prefix before the run: $($Before.Count)"
```

**Expect:** every line `True`; the HEAD is this branch's tip; 0 tracked changes; 0 objects with the
prefix.
**Failure looks like:** `False` on a marker (rebuild the worktree), or the main clone named.

Result:

## 1. A paged read follows Microsoft Graph's next links as before (A)

### 1.1. A v1.0 walk of many pages

- [ ] **1.1** `Invoke-OERGraphRequest -Uri 'v1.0/groups?$top=5&$select=id' -All` follows every page, returns as many groups as an independent read, and every next link it followed is absolute https on the session's Graph host. #type/subtask

```powershell
Connect-S143
$Independent = @((Invoke-OerLiveGraph -Uri 'v1.0/groups?$top=999&$select=id' -All).Body.value).Count
$Walk = & $script:S143Module { Invoke-OERGraphRequest -Uri 'v1.0/groups?$top=5&$select=id' -All -ErrorAction Stop }
Show-S143Walk -Label 'v1.0 groups' -Result $Walk -Expected $Independent
```

**Expect:** more than one page; the item count equals the independent read; page 1 relative; every
later link `True`; 0 writes and 0 token requests.
**Failure looks like:** `GraphPagingIncomplete` (a link Microsoft Graph handed out was refused), a
count that differs, or a link off the host.

Result:

### 1.2. A beta walk of many pages

- [ ] **1.2** The same walk on the `beta` endpoint (`beta/groups?$top=5&$select=id`) gives the same answer. #type/subtask

```powershell
Connect-S143
$Independent = @((Invoke-OerLiveGraph -Uri 'beta/groups?$top=999&$select=id' -All).Body.value).Count
$Walk = & $script:S143Module { Invoke-OERGraphRequest -Uri 'beta/groups?$top=5&$select=id' -All -ErrorAction Stop }
Show-S143Walk -Label 'beta groups' -Result $Walk -Expected $Independent
```

**Expect:** as 1.1.
**Failure looks like:** as 1.1.

Result:

## 2. A tenant named by a domain that does not exist (B)

### 2.1. TenantResolutionFailed, the same record as on main, and no token request

- [ ] **2.1** `Connect-OER -TenantId oer-s143-missing.invalid` with the certificate identity is refused with `TenantResolutionFailed` before any token request, and the published record is the same as the one the base commit publishes. #type/subtask

```powershell
Disconnect-OerLive
$env:PSModulePath = (Resolve-Path -LiteralPath (Join-Path $Cfg.Repo 'output\RequiredModules')).Path + [System.IO.Path]::PathSeparator + $env:PSModulePath
$Cert = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $Cfg.CertificateThumbprint)
$Rows = foreach ($Build in 'branch', 'base') {
    $Psd1 = if ($Build -eq 'branch') {
        (Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    } else {
        $Base = Join-Path ([System.IO.Path]::GetTempPath()) 'oer-s143-base'
        if (Test-Path -LiteralPath $Base) { Remove-Item -LiteralPath $Base -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $Base
        git -C $Cfg.Repo archive --format=zip -o (Join-Path $Base 'base.zip') origin/main source
        Expand-Archive -LiteralPath (Join-Path $Base 'base.zip') -DestinationPath $Base
        Join-Path $Base 'source\Omnicit.EntraRBAC.psd1'
    }
    Get-Module -Name Omnicit.EntraRBAC | Remove-Module -Force
    Import-Module $Psd1 -Force -Global
    Install-S143Fence
    $R = Get-S143Refusal { Connect-OER -TenantId $MissingDomain -ClientId $Cfg.AppId -Certificate $Cert -ErrorAction Stop }
    [PSCustomObject]@{
        Build = $Build; Id = ([string]$R.FullyQualifiedErrorId -split ',')[0]; Category = [string]$R.CategoryInfo.Category
        Target = [string]$R.TargetObject; Message = [string]$R.Exception.Message
        Inner = if ($R.Exception.InnerException) { $R.Exception.InnerException.GetType().FullName } else { 'none' }
        InnerMessage = if ($R.Exception.InnerException) { [string]$R.Exception.InnerException.Message } else { '' }
        Tokens = $global:S143TokenRequests
    }
}
foreach ($Row in $Rows) {
    Write-OerLiveStep "$($Row.Build): id $($Row.Id); category $($Row.Category); target is the domain $($Row.Target -ceq $MissingDomain); inner $($Row.Inner); token requests $($Row.Tokens)"
    Write-OerLiveStep "$($Row.Build): message: $($Row.Message)"
}
Write-OerLiveStep "Branch and base publish the same id, category, target, message and inner exception: $(($Rows[0].Id -ceq $Rows[1].Id) -and ($Rows[0].Category -ceq $Rows[1].Category) -and ($Rows[0].Target -ceq $Rows[1].Target) -and ($Rows[0].Message -ceq $Rows[1].Message) -and ($Rows[0].Inner -ceq $Rows[1].Inner) -and ($Rows[0].InnerMessage -ceq $Rows[1].InnerMessage))"
Remove-Item -LiteralPath (Join-Path ([System.IO.Path]::GetTempPath()) 'oer-s143-base') -Recurse -Force
```

**Expect:** both builds: `TenantResolutionFailed`, `AuthenticationError`, target the domain, inner
`System.InvalidOperationException`, 0 token requests; the message names the authority's refusal;
the comparison line `True`.
**Failure looks like:** a token request, another id, or a message that differs between the builds.

Result:

## 3. The directory role name map (B)

### 3.1. The map reads as oer-live-cc

- [ ] **3.1** `Get-OERDirectoryRoleNameMap -ThrowOnFailure` (in the module's scope) returns a map of the activated directory roles, read only. #type/subtask

```powershell
Connect-S143
$Map = & $script:S143Module { Get-OERDirectoryRoleNameMap -ThrowOnFailure -ErrorAction Stop }
Write-OerLiveStep "The map holds entries: $($Map.Count -gt 0); entries $($Map.Count)"
Write-OerLiveStep "Every entry names a role: $(@($Map.Values | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0)"
Write-OerLiveStep "Requests: $(@(& $script:S143Module { $script:S143Pages }).Count) read(s), $(& $script:S143Module { $script:S143Writes }) write(s); token requests $global:S143TokenRequests"
```

**Expect:** a non-empty map, every entry a name; reads only.
**Failure looks like:** an `AdministrativeUnitScopedRoleReadFailed` record (the read failed), or an
empty map.

Result:

### 3.2. A refused read is the typed record, as oer-live-cc-noperm

- [ ] **3.2** As `oer-live-cc-noperm` the same read is refused and the helper throws `AdministrativeUnitScopedRoleReadFailed` (ReadError, target the read) whose message names the read and whose inner exception is the refusal. #type/subtask

```powershell
Connect-S143 -NoPerm
$R = & $script:S143Module { $Caught = $null; try { $null = Get-OERDirectoryRoleNameMap -ThrowOnFailure -ErrorAction Stop } catch { $Caught = $PSItem }; $Caught }
Write-OerLiveStep "Refused: $($null -ne $R)"
Write-OerLiveStep "id $(([string]$R.FullyQualifiedErrorId -split ',')[0]); category $([string]$R.CategoryInfo.Category); target $([string]$R.TargetObject)"
Write-OerLiveStep "The message names the read: $(([string]$R.Exception.Message).StartsWith("Could not read the directory roles ('v1.0/directoryRoles') that name the roles: "))"
Write-OerLiveStep "Exception type $($R.Exception.GetType().FullName); inner exception present: $($null -ne $R.Exception.InnerException)"
Write-OerLiveStep "The inner refusal names an authorization failure: $(([string]$R.Exception.Message) -match 'Authorization_RequestDenied|Insufficient privileges|403|Forbidden')"
Write-OerLiveStep "Writes $(& $script:S143Module { $script:S143Writes }); token requests $global:S143TokenRequests"
```

**Expect:** refused; `AdministrativeUnitScopedRoleReadFailed`, `ReadError`, target
`v1.0/directoryRoles`; the message names the read; `System.Exception` with the refusal inside; 0
writes and 0 token requests. If noperm CAN read the directory roles, the check records that and
the refusal stays class B (unit tests).
**Failure looks like:** another id, a message that does not name the read, or a token request.

Result:

## Teardown

### T.1. Nothing was created

- [ ] **T.1** The sweep finds no object with the prefix, and the session is ended. #type/subtask

```powershell
Connect-OerLive -Graph
$After = @(Find-OerLivePrefixed -Prefix 'oer-s143-' -Quiet)
Write-OerLiveStep "Objects with the prefix after the run: $($After.Count)"
Disconnect-OerLive
```

**Expect:** 0 objects with the prefix.
**Failure looks like:** any object with the prefix (none was created by this file).

Result:
