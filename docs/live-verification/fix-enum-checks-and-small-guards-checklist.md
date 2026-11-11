# Live verification checklist -- enum checks and small guards (fix/enum-checks-and-small-guards)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s152-`.** The
prerequisite script creates two catalogs, `oer-s152-cat-a` and `oer-s152-cat-b`, each holding an
access package named `oer-s152-ap`, and a direct-assignment policy `oer-s152-pol` on each package.
The checks write only one more object with the prefix: the access package `oer-s152-new` in
`oer-s152-cat-a` (check 1.2). Every other write is run with `-WhatIf` or is refused before it is
sent. No assignment is made, no role is assigned and no policy outside the prefix is touched.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS152Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Every sign-in is app-only;
nothing here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s152/`
(git-ignored). Every block prints through the library's redactor, and the blocks print the test
objects by their key in the prerequisite script's id file (`catA`, `catB`, `apA`, `apB`, `polA`,
`polB`), never by id; any other object id becomes `00000000-0000-0000-0000-0000000000NN`. **No
credential, token, application id or certificate thumbprint is ever printed. Never render an error
record**: every block prints the error id and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash.

- **A. The validator refuses a one-element array** ("refuse a one-element array at every enum check
  of the validator"). Nine enum checks of `Test-OERStructureSchema` test that the value is a string
  before the membership, and an access package's `catalog` that is not a string is an Error.
- **B. A role definition id is a path only when it begins with `/`** ("send a role definition id as a
  path only when it begins with a slash"). `Get-OERRoleDefinition -Role` and the resolver every Azure
  role cmdlet uses look any other value up as a role NAME. `Remove-`/`Set-OERRoleAssignment` refuse an
  `-Id` with a line break in or after its last segment (`InvalidRoleAssignmentId`).
- **C. The tenant domain lookup returns after each refusal** ("return after each refusal of the tenant
  domain lookup"). Internal, held by unit tests in a runspace with no `try`; not checked here.
- **D. A piped access package binds its own catalog and id** ("bind a piped access package by its own
  catalog and id"). `New-OERAccessPackage -Catalog` lists `CatalogId` before `Id`;
  `Get-OERAccessPackageAssignmentPolicy` and `New-OERAccessPackageAssignment` resolve a package piped
  from `Get-OERAccessPackage` by its own id with or without `-Catalog`.

A live tenant is needed for what mocks cannot show: that Azure Resource Manager answers the name
lookup of a host-shaped value as an empty list (B), and that a package two catalogs share by name is
reached, from the pipeline, as the one piped (D).

## What this file does not check, and why

- **C** is internal: the only caller has a `try`, and a lookup that fails on purpose needs a domain
  the authority refuses. Class B: the Describe "Resolve-OERTenantDomain stops after each throw,
  outside any try (BL-182)".
- **New-OERAccessPackage and New-OERAccessPackageAssignment are run with `-WhatIf` only.** The
  `What if` line and the requests before it show what the step changes; nothing needs creating.
- **Remove-OERRoleAssignment is run with `-WhatIf`**, on an id no assignment has: the refusal comes
  before any request.

## Setup, once

**You need:** the test tenant and the two configuration files OerLive reads beside it; OerLive 1.1.0
and `Initialize-OerS152Prereq.ps1` in the same folder (`OER_LIVE_DIR`); the identity `oer-live-cc`
enabled for the run; this branch built in the step's own worktree (`./build.ps1 -Tasks build`) and
`OER_LIVE_REPO` naming that worktree.

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "must be a string.`"" -Quiet) -and [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'BL-159' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch '[^/\r\n]+\z' -Quiet)
$D = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "[Alias('CatalogId', 'Id')]" -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; D: $D"
```

**Expect:** `not the main clone: True`; the main clone on `main`; the worktree on this branch with 0
tracked changes; `A: True; B: True; D: True`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or on the last (build the
worktree first, never while the gate runs).

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP; never sign in another way.

Result:

### 0.2. The prerequisite script's plan

- [ ] **0.2** `-WhatIf` plans only `oer-s152-` objects.

```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS152Prereq.ps1 -WhatIf
```

**Expect:** every `What if` line names an `oer-s152-` object (or, on a re-run, none: the objects exist).
**Failure looks like:** a target without the prefix -- STOP.

Result:

### 0.3. The prerequisite script, for real

- [ ] **0.3** The test objects exist, each package in its own catalog.

```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS152Prereq.ps1 -Unattended
```

**Expect:** every `Read back` line `True`, among them `package apA in its catalog: True` and `package apB in its catalog: True`.
**Failure looks like:** a `False`, or `STOP` -- stop the run.

Result:

## 1. The validator (A)

### 1.1. A one-element array in two enum fields and in the catalog is an Error, offline

- [ ] **1.1** `Test-OERStructure` reports an Error at each array, and the same document with strings has none there; nothing signs in.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's152'
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Import-Module $Psd1.FullName -Force
Write-OerLiveStep "The module is the worktree's build: $((Get-Module Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
$Paths = 'groups[0].membershipRuleProcessingState', 'directoryRoleAssignments[0].assignmentType', 'accessPackages[0].catalog'
foreach ($Form in 'array', 'string') {
    $V = if ($Form -eq 'array') { { param($S) , @($S) } } else { { param($S) $S } }
    $Doc = [ordered]@{
        version                  = '1.0'
        groups                   = @([ordered]@{ displayName = 'oer-s152-dyn'; membershipRule = '(user.department -eq "oer-s152")'; membershipRuleProcessingState = (& $V 'Paused') })
        directoryRoleAssignments = @([ordered]@{ role = 'Reports Reader'; principal = 'oer-s152-nobody'; assignmentType = (& $V 'Eligible') })
        accessPackages           = @([ordered]@{ displayName = 'oer-s152-new'; catalog = (& $V 'oer-s152-cat-a') })
    }
    $File = Join-Path $Raw "structure-1.1-$Form.json"
    $Doc | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $File -Encoding utf8NoBOM
    $R = Test-OERStructure -Path $File
    foreach ($P in $Paths) {
        $Hit = @($R.Errors | Where-Object { $_.Path -eq $P -and $_.Severity -eq 'Error' })
        Write-OerLiveStep "${Form}: Errors (Severity Error) at ${P}: $($Hit.Count)$(@($Hit) | ForEach-Object { ' | ' + $_.Message })"
    }
    Write-OerLiveStep "${Form}: Valid $($R.Valid)"
}
Write-OerLiveStep "A session exists: $($null -ne (& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState }))"
```

**Expect:** `array`: exactly one Errors (Severity Error) entry at each of the three paths, the first two
with the existing "must be one of" message, the third `'catalog' at accessPackages[0] must be a string.`,
and `Valid False`; `string`: 0 Errors (Severity Error) at each path (a Warning at the catalog path is
expected and not counted); `A session exists: False`.
**Failure looks like:** 0 Errors at a path for the array form (the array is still accepted), or an
Error there for the string form.

Result:

### 1.2. The apply engine refuses the array document and converges on the string one (G8)

- [ ] **1.2** `Invoke-OERStructure` refuses the array form with nothing written; the string form creates `oer-s152-new` in `catA`, and a second run is `Unchanged`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's152'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
Connect-OerLive -Arm
$Em = 'v1.0/identityGovernance/entitlementManagement'
foreach ($Form in 'array', 'string') {
    $Cat = if ($Form -eq 'array') { , @('oer-s152-cat-a') } else { 'oer-s152-cat-a' }
    $Doc = Join-Path $Raw "structure-1.2-$Form.json"
    [ordered]@{ version = '1.0'; accessPackages = @([ordered]@{ displayName = 'oer-s152-new'; catalog = $Cat; description = 'Sprint 15 step 2 live check (oer-s152-)'; hidden = $true }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Doc -Encoding utf8NoBOM
    $Runs = if ($Form -eq 'array') { @('first') } else { @('plan', 'first', 'second') }
    foreach ($Run in $Runs) {
        $script:E = $null
        $Rows = if ($Run -eq 'plan') { @(Invoke-OERStructure -Path $Doc -WhatIf -ErrorAction SilentlyContinue -ErrorVariable script:E 3>$null) } else { @(Invoke-OERStructure -Path $Doc -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable script:E 3>$null) }
        $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
        Write-OerLiveStep "$Form ${Run}: own errors: $($Own -join ', '); rows: $((@($Rows) | ForEach-Object { '{0} {1} {2}' -f $_.Section, $_.Item, $_.Action }) -join '; ')"
        if ($Run -eq 'first' -and $Form -eq 'string') { Start-Sleep -Seconds 30 }
    }
    $R = Invoke-OerLiveGraph -Uri "$Em/accessPackages?`$filter=displayName eq 'oer-s152-new'&`$expand=catalog"
    Write-OerLiveStep "$Form, after: packages named oer-s152-new: $((@($R.Body.value) | ForEach-Object { '{0} in {1}' -f (L ([string]$_.id)), (L ([string]$_.catalog.id)) }) -join ', ')"
}
Disconnect-OerLive
```

**Expect:** `array first`: one own error, the validator's refusal, and no row; `array, after`: no
package named `oer-s152-new`; `string plan`: `accessPackages oer-s152-new Skipped`; `string first`
`Created`; `string second` `Unchanged`; `string, after`: one package (`another id`) in `catA`.
**Failure looks like:** a row or a package after the array run, or a second create.

Result:

## 2. Role definition ids and role assignment ids (B)

### 2.1. A host-shaped -Role is looked up as a name and never sent as a path

- [ ] **2.1** `Get-OERRoleDefinition -Role` with a value that does not begin with `/` sends one name lookup on the Azure Resource Manager host and reports `RoleDefinitionNotFound`; a `/`-leading id is still read as a path.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
function Req($Out) { @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like '`[Invoke-OERArmRequest`] GET *' } | ForEach-Object { $_.Message -replace '^\[Invoke-OERArmRequest\] ', '' }) }
Connect-OerLive -Arm
$Reader = @(Get-OERRoleDefinition -Role 'Reader')[0]
$Tail = ([string]$Reader.RoleDefinitionId).Substring(([string]$Reader.RoleDefinitionId).IndexOf('/providers/'))
Write-OerLiveStep "Control, by name: one role named $($Reader.RoleName); its id begins with /providers/Microsoft.Authorization/roleDefinitions/: $($Tail -like '/providers/Microsoft.Authorization/roleDefinitions/*')"
$script:E = $null
$Out = @(Get-OERRoleDefinition -Role $Tail -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E 4>&1)
$Got = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
Write-OerLiveStep "Control, by id: role $($Got.RoleName); errors $(@($script:E).Count); request is the id path: $((Req $Out) -join ' | ' -eq "$Tail`?api-version=2022-04-01")"
foreach ($Shape in @(@('a host suffix', '.contoso.invalid'), @('an at sign', ('@' + 'contoso.invalid')), @('a scheme and host', 'https://contoso.invalid'))) {
    $Value = $Shape[1] + $Tail
    $script:E = $null
    $Out = @(Get-OERRoleDefinition -Role $Value -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E 4>&1)
    $Got = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
    $Requests = @(Req $Out)
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERRoleDefinition') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    $AsName = ($Requests.Count -eq 1) -and $Requests[0].StartsWith('/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&$filter=')
    $AsPath = @($Requests | Where-Object { $_.StartsWith($Shape[1]) }).Count
    Write-OerLiveStep "$($Shape[0]): requests $($Requests.Count); one name lookup on the ARM host: $AsName; requests sent as the value's path: $AsPath; output $($Got.Count); own errors: $($Own -join ', ')"
}
Disconnect-OerLive
```

**Expect:** the control by name finds one role and its id begins with the provider path; the control
by id returns the role with 0 errors and requests exactly the id path; each of the three shapes:
`requests 1; one name lookup on the ARM host: True; requests sent as the value's path: 0; output 0;
own errors: RoleDefinitionNotFound`.
**Failure looks like:** `ArmRequestOutsideCloudHost` (the value was still used as a path), a request
starting with the shape, or the control by id no longer read as a path.

Result:

### 2.2. A role assignment id with a trailing line break is refused before any request

- [ ] **2.2** `Remove-OERRoleAssignment -WhatIf` refuses an `-Id` ending in a line feed, and accepts the same id without it.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Id = "/subscriptions/$($Cfg.SubscriptionId)/providers/Microsoft.Authorization/roleAssignments/$([guid]::NewGuid())"
foreach ($Case in @(@('with a trailing line feed', "$Id`n"), @('without it', $Id))) {
    $script:E = $null
    $Lines = @(Remove-OERRoleAssignment -Id $Case[1] -WhatIf -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E 3>&1 4>&1)
    $Requests = @($Lines | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like '`[Invoke-OERArmRequest`] *' })
    $Warn = @($Lines | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $Own = @($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Remove-OERRoleAssignment') } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] })
    Write-OerLiveStep "$($Case[0]): ARM requests $($Requests.Count); deletion warnings $($Warn.Count); own errors: $($Own -join ', ')"
}
Disconnect-OerLive
```

**Expect:** `with a trailing line feed: ARM requests 0; deletion warnings 0; own errors:
InvalidRoleAssignmentId`; `without it: ARM requests 0; deletion warnings 1; own errors:` (none -- the
`-WhatIf` gate stops it after the warning).
**Failure looks like:** no `InvalidRoleAssignmentId` for the line feed, or a warning for it.

Result:

## 3. The pipeline (D)

### 3.1. A piped package reaches its own policies without -Catalog

- [ ] **3.1** `apB` piped from `Get-OERAccessPackage` reaches its policy in `Get-OERAccessPackageAssignmentPolicy` and `New-OERAccessPackageAssignment -WhatIf` without `-Catalog`, while the typed shared name is still refused as ambiguous.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's152'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
function Own($E, [string]$C) { @($E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(",$C") } | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ' }
Connect-OerLive -Arm
$Piped = @(Get-OERAccessPackage -Catalog 'oer-s152-cat-b' | Where-Object DisplayName -eq 'oer-s152-ap')
Write-OerLiveStep "Piped from catB: $((@($Piped) | ForEach-Object { L ([string]$_.Id) }) -join ', ')"
$script:E = $null
$Po = @($Piped | Get-OERAccessPackageAssignmentPolicy -ErrorAction SilentlyContinue -ErrorVariable script:E)
Write-OerLiveStep "| Get-OERAccessPackageAssignmentPolicy: own errors: $(Own $script:E 'Get-OERAccessPackageAssignmentPolicy'); policies: $((@($Po) | ForEach-Object { '{0} of {1}' -f (L ([string]$_.Id)), (L ([string]$_.AccessPackageId)) }) -join ', ')"
$script:E = $null
$Po = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s152-ap' -ErrorAction SilentlyContinue -ErrorVariable script:E)
Write-OerLiveStep "Typed name, no -Catalog: policies $($Po.Count); own errors: $(Own $script:E 'Get-OERAccessPackageAssignmentPolicy')"
Write-OerLiveStep "Keys: apA is $($Ids.apA.Id); apB is $($Ids.apB.Id)"
$script:E = $null
$Piped | New-OERAccessPackageAssignment -Policy $Ids.polB.Id -TargetId '00000000-0000-0000-0000-000000000000' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable script:E
Write-OerLiveStep "| New-OERAccessPackageAssignment -WhatIf: own errors: $(Own $script:E 'New-OERAccessPackageAssignment')"
Disconnect-OerLive
```

**Expect:** piped `apB`; policies `polB of apB` with no own error; the typed name `policies 0` and
`AmbiguousAccessPackageName`; the `What if` line names the placeholder the `Keys` line gives `apB`
(`Assign to access package ...`) and no own error.
**Failure looks like:** `AmbiguousAccessPackageName` for a piped call, or `apA` anywhere.

Result:

### 3.2. New-OERAccessPackage takes a piped package's catalog, not its id

- [ ] **3.2** `apB | New-OERAccessPackage -DisplayName oer-s152-new2 -WhatIf` looks the name up in `catB` and plans the create there.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s152-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's152'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ids = Get-Content (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$Label = @{}; foreach ($K in $Ids.Keys) { $Label[[string]$Ids[$K].Id] = $K }
function L([string]$V) { if ($Label.ContainsKey($V)) { $Label[$V] } elseif ($V) { 'another id' } else { 'none' } }
function T([string]$S) { foreach ($K in $Label.Keys) { $S = $S.Replace($K, $Label[$K]) }; $S }
Connect-OerLive -Arm
$Piped = @(Get-OERAccessPackage -Catalog 'oer-s152-cat-b' | Where-Object DisplayName -eq 'oer-s152-ap')
Write-OerLiveStep "Piped from catB: $((@($Piped) | ForEach-Object { L ([string]$_.Id) }) -join ', '); its CatalogId: $((@($Piped) | ForEach-Object { L ([string]$_.CatalogId) }) -join ', ')"
$script:E = $null
$Out = @($Piped | New-OERAccessPackage -DisplayName 'oer-s152-new2' -WhatIf -Verbose -ErrorAction SilentlyContinue -ErrorVariable script:E 4>&1)
$Requests = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like '`[Invoke-OERGraphRequest`] *' } | ForEach-Object { T ($_.Message -replace '^\[Invoke-OERGraphRequest\] ', '') })
Write-OerLiveStep "| New-OERAccessPackage -WhatIf: own errors: $(@($script:E | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',New-OERAccessPackage') }).Count); requests: $($Requests -join ' | ')"
$R = Invoke-OerLiveGraph -Uri "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'oer-s152-new2'"
Write-OerLiveStep "Packages named oer-s152-new2 after the -WhatIf: $(@($R.Body.value).Count)"
Disconnect-OerLive
```

**Expect:** piped `apB` with CatalogId `catB`; no own error; the requests filter on `catalog/id eq
'catB'` and never name `apB` as a catalog; the `What if` line is `Create access package` on
`oer-s152-new2`; 0 packages named `oer-s152-new2`.
**Failure looks like:** `catalog/id eq 'apB'` (the package's own id taken as its catalog).

Result:

## T. Teardown

### T.1. Every prefixed object is removed

- [ ] **T.1** The teardown removes every `oer-s152-` object and the sweep is 0.

```powershell
Set-Location $env:OER_LIVE_DIR
pwsh -NoProfile -File .\Initialize-OerS152Prereq.ps1 -Teardown -Unattended
```

**Expect:** `Teardown complete: the sweep is 0.`
**Failure looks like:** `Left:` lines -- run it again later, and name every remainder in the report.

Result:
