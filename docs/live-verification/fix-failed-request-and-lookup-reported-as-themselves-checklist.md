# Live verification checklist -- a failed request or lookup is reported as itself (fix/failed-request-and-lookup-reported-as-themselves)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s83-`.** The
prerequisite script creates one catalog, `oer-s83-catalog` (published, visible to external users),
one hidden access package in it, `oer-s83-ap`, and one assignment policy on the package,
`oer-s83-ext`, whose `allowedTargetScope` is `allExternalUsers`, with a raw Graph POST (the module
could not build that scope before this branch). Check 1.3 has the module create a second policy on
the same package, `oer-s83-ext2`. Nothing else is written: section 2 runs every command with
`-WhatIf` as an identity that holds no permission at all, and no group, role, policy or review
outside the prefix is touched.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS83Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Section 2 signs in as
`oer-live-cc-noperm`, the same certificate's identity with no permission, so that every lookup is
refused; a 403 there is the expected answer, not a stop. A 401 or 403 as `oer-live-cc` is a stop.
Every sign-in is app-only; nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown both
run first with `-WhatIf`, and so does each apply in section 1; read the plan against the `Expect:`
line before running the line that writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s83/` -- the
library writes its transcript, the baseline and the export bundles there, and the folder is
git-ignored. The bundles hold real object ids: never copy any of them into a tracked file. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. **No credential,
token, application id or certificate thumbprint is ever printed. Never render an error record**
(`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw failure's record can carry the
bearer token. Every block prints the error id, category and message only.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A request Graph accepts but answers `status: Failed` is an error** ("report a failed
  eligibility request as an error", BL-04). `Add-OERGroupEligibility` still returns the request object,
  and then writes `EligibilityRequestFailed`; `Invoke-OERStructure` reports such an eligibility of a
  group that already existed `Failed`, never `Updated`. A group created in the same run keeps its
  replication wait unchanged.
- **B. The requestor scope takes every v1.0 value** (BL-11, decision A7). `AllExternalUsers`,
  `AllDirectoryServicePrincipals` and `AllDirectoryAgentIdentities` are accepted, read and written, so
  an exported policy with one of them applies as `Unchanged` instead of `Failed`.
  `SpecificDirectoryServicePrincipals` is read but refused by the builder, `unknownFutureValue` read
  from Graph makes that policy `Failed` without a write, and a policy whose write would drop connected
  organization targets is refused.
- **C. An approver lookup follows the rule for every other lookup** (BL-14, decision A5). An
  ambiguous approver name is `AmbiguousApproverName`, a failed lookup is reported as itself, and only
  an approver that does not exist is `ApproverNotFound`, in `Set-OERGroupPimPolicy`,
  `Set-OERDirectoryRoleManagementPolicy`, `Set-OERRoleManagementPolicy` and the three apply paths.
- **D. Three places no longer swallow a failure** (BL-15, decision A6): the catalog read behind a
  derived access review scope, the definition read before `Remove-OERAccessReviewDefinition` deletes,
  and the instances read of `Get-OERAccessReviewDefinition`.

A live tenant is needed for what mocks cannot show: what a real v1.0 read returns for a policy whose
scope is `allExternalUsers` and that such a policy round-trips through an export and an apply
(section 1), and that a real refusal of each lookup is reported as itself (section 2).

## What this file does not check, and why

- **A cannot be provoked here.** Graph answers `status: Failed` only while a group created moments
  ago is not yet known to PIM for Groups (measured live in Sprint 7 step 3, run 0: two 404s, then a
  201 whose status was already Failed); no request can be made to fail on demand. It is check class B:
  mocked, mutation-proven unit tests that run the REAL `Add-OERGroupEligibility` with only the
  transport answering, in `tests/Unit/Public/Add-OERGroupEligibility.Tests.ps1` and
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` (Context `a request Graph accepts but answers
  status Failed (Sprint 8 step 3, BL-04)`), with that live answer as the fixture.
- **`SpecificDirectoryServicePrincipals`, the connected organization guard and `unknownFutureValue`
  are class B unless section 1 meets them.** The first needs service principal targets the module
  cannot create, the second a connected organization, and the third appears live only if Graph
  answers a scope as `unknownFutureValue`. Unit tests in
  `tests/Unit/Public/New-OERAccessPackageRequestorScope.Tests.ps1`,
  `tests/Unit/Private/ConvertTo-OERAssignmentPolicy.Tests.ps1` and
  `tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1` prove them.
- **An ambiguous or missing approver is class B.** The tenant holds no two groups of one name on
  demand; `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1` and the cmdlet and handler tests prove
  both, for every call site. Section 2 proves the refusal live.
- **The access review catalog read and the instances read are class B**
  (`tests/Unit/Private/Resolve-OERAccessReviewScopeTarget.Tests.ps1`,
  `tests/Unit/Public/Get-OERAccessReviewDefinition.Tests.ps1`); 2.3 runs the third place live.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS83Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same five lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` creates and deletes a catalog, an access package and its
  policies with the permission it already holds (`EntitlementManagement.ReadWrite.All`); this file
  adds none.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. Each
  block's fifth line sets the session's `Repo` to it, so the module loads from the worktree's build;
  the main clone is never checked out on another commit or branch (S.1 and T.3 read that it was not).

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$A = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'EligibilityRequestFailed' -Quiet)
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'allDirectoryAgentIdentities' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'AmbiguousApproverName' -Quiet)
$D = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'so the check for an assignment policy' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $A; B: $B; C: $C; D: $D"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.3); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; B: True; C: True; D: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone, and the run would load whatever the main clone last built; any `False` on the last line --
build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True` (app-only certificate session with the identity's app id,
the app name `oer-live-cc`, the test tenant, the service principal of that app id named
`oer-live-cc` and the token's signed-in object; the organization name, a verified domain and the
organization id; the ARM token from the certificate; the test subscription belongs to the test
tenant and is Enabled), `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result:

### 0.2. Identity check as oer-live-cc-noperm, the module session

- [ ] **0.2** The no-permission identity signs in to a module session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, the ARM token from the certificate
`True`, `identity check passed: True`, and `The module is the worktree's build: True`.
**Failure looks like:** any `False` -- STOP; section 2 needs this session.

Result:

### 0.3. The prerequisite script's plan

- [ ] **0.3** `-WhatIf` plans only `oer-s83-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s83\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s83-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s83-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s83-`
object; the plan names the transcript and the baseline under `raw\s83\` and, in the tenant, the
catalog `oer-s83-catalog`, the access package `oer-s83-ap` and the policy `oer-s83-ext` -- three
tenant targets, every one starting with `oer-s83-`; `WhatIf: nothing was created, removed or
written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result:

### 0.4. The prerequisite script, for real

- [ ] **0.4** The test objects exist: the catalog, the hidden access package and its policy for all external users.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created catalog
oer-s83-catalog`, `Created access package oer-s83-ap`, `Created policy oer-s83-ext`, each readable;
a line `oer-s83-ext reads allowedTargetScope '...' (raw v1.0 read, no Prefer header)` that RECORDS
what a raw read returns (the measurement 1.1 compares against); the summary with all three
`present`; exit code `0`. A `likely replication delay` line on a fresh object is expected.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way. A refused POST of the policy --
record Graph's code and message; it is a finding about what Graph accepts, not about the module.

Result:

### 1. The export and the apply, as oer-live-cc

### 1.1. The export gives the policy with its scope

- [ ] **1.1** `Export-OERInventory` writes `oer-s83-ext` with the scope Graph returned, and the value is recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Out = Join-Path $Raw 'export-1.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -Include Catalogs, AccessPackages -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
Write-OerLiveStep "Warnings: $(@($ExpWarn).Count); IncompleteReads: $(@($Bundle.IncompleteReads).Count)"
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Cat = @($Doc.catalogs | Where-Object { $_.displayName -ceq 'oer-s83-catalog' })
$Ap = @($Doc.accessPackages | Where-Object { $_.displayName -ceq 'oer-s83-ap' })
Write-OerLiveStep "inventory.json: catalogs named oer-s83-catalog $($Cat.Count) (externallyVisible $(@($Cat | ForEach-Object { $_.externallyVisible }) -join ',')); access packages named oer-s83-ap $($Ap.Count) (hidden $(@($Ap | ForEach-Object { $_.hidden }) -join ','))"
foreach ($Pol in @($Ap | ForEach-Object { $_.assignmentPolicies })) {
    Write-OerLiveStep "policy '$($Pol.displayName)': requestorScope.scope '$($Pol.requestorScope.scope)'; users $(@($Pol.requestorScope.users).Count); groups $(@($Pol.requestorScope.groups).Count)"
}
$Live = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap[0].displayName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -ceq 'oer-s83-ext' })
Write-OerLiveStep "Get-OERAccessPackageAssignmentPolicy: oer-s83-ext AllowedTargetScope '$(@($Live | ForEach-Object { $_.AllowedTargetScope }) -join ',')'; RequestorScope.scope '$(@($Live | ForEach-Object { $_.RequestorScope.scope }) -join ',')'"
Disconnect-OerLive
```

**Expect:** no error and no `IncompleteReads` entry for the catalogs or access packages; one
`oer-s83-catalog` (externallyVisible `True`) and one `oer-s83-ap` (hidden `True`); the policy
`oer-s83-ext` with `requestorScope.scope` `AllExternalUsers` and no users or groups, and the cmdlet
reading `allExternalUsers` / `AllExternalUsers`. **Record the value exactly as read:** if Graph
answers `unknownFutureValue` (the module sends no `Prefer: include-unknown-enum-members`), that is
written here, and 1.2 then expects `Failed` for this policy (decision A7).
**Failure looks like:** the policy missing from the export, or a scope other than the two above.

Result:

### 1.2. The unchanged export applied: Unchanged with -WhatIf, and for real (G8)

- [ ] **1.2** The export's `oer-s83-catalog` and `oer-s83-ap` entries, applied unchanged, give `Unchanged` for `oer-s83-ext` and no write, first with `-WhatIf`, then for real.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Bundle = Get-ChildItem -LiteralPath (Join-Path $Raw 'export-1.1') -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.FullName 'inventory.json') -Raw | ConvertFrom-Json
$Mini = [ordered]@{
    catalogs       = @($Doc.catalogs | Where-Object { $_.displayName -ceq 'oer-s83-catalog' })
    accessPackages = @($Doc.accessPackages | Where-Object { $_.displayName -ceq 'oer-s83-ap' })
}
$Json = $Mini | ConvertTo-Json -Depth 30
Set-Content -LiteralPath (Join-Path $Raw 'doc-1.2.json') -Value $Json -Encoding utf8
Write-OerLiveStep "Document: catalogs $(@($Mini.catalogs).Count), access packages $(@($Mini.accessPackages).Count), policies $(@($Mini.accessPackages | ForEach-Object { $_.assignmentPolicies }).Count)"
Connect-OerLive -Arm
foreach ($Run in 'WhatIf', 'Real') {
    $Rows = if ($Run -eq 'WhatIf') {
        @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    } else {
        @(Invoke-OERStructure -Json $Json -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    }
    Write-OerLiveStep "$Run rows: $(($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
    foreach ($R in $Rows) { Write-OerLiveStep "$Run row: [$($R.Section)] $($R.Item) $($R.Action) -- $($R.Detail)" }
    foreach ($E in @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "$Run error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
}
Disconnect-OerLive
```

**Expect:** the document holds one catalog, one access package and one policy. Both runs give only
`Unchanged` rows (the catalog, the package, `assignmentPolicy 'oer-s83-ext' matches`), no
`Created`, `Updated`, `Removed` or `Failed`, and no error. Before this branch the policy was `Failed`
before the diff, with `-WhatIf` too, since the builder refused the scope. If 1.1 recorded
`unknownFutureValue`: the policy is `Failed` in both runs with the detail naming
`Prefer: include-unknown-enum-members`, and nothing is written -- record it as a finding.
**Failure looks like:** a `Failed` row for `oer-s83-ext` that names the builder or a parameter value,
or any `Updated` or `Created` row (the export did not round-trip).

Result:

### 1.3. A second policy for all external users: Created, then only Unchanged (G8)

- [ ] **1.3** The same document plus a policy `oer-s83-ext2` with `requestorScope.scope` `AllExternalUsers` gives `Created` for it, and a run after that only `Unchanged`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Mini = Get-Content -LiteralPath (Join-Path $Raw 'doc-1.2.json') -Raw | ConvertFrom-Json
$Ext2 = [PSCustomObject][ordered]@{
    displayName       = 'oer-s83-ext2'
    description       = 'Omnicit.EntraRBAC live verification (oer-s83-): a second policy for all external users.'
    requestorScope    = [PSCustomObject]@{ scope = 'AllExternalUsers' }
    requestorSettings = [PSCustomObject]@{ allowSelfRequest = $true }
    requireApproval   = $false
}
$Ap = @($Mini.accessPackages)[0]
$Ap.assignmentPolicies = @(@($Ap.assignmentPolicies) | Where-Object { $_.displayName -cne 'oer-s83-ext2' }) + $Ext2
$Json = $Mini | ConvertTo-Json -Depth 30
Set-Content -LiteralPath (Join-Path $Raw 'doc-1.3.json') -Value $Json -Encoding utf8
Connect-OerLive -Arm
$Em = 'v1.0/identityGovernance/entitlementManagement'
foreach ($Run in 'WhatIf', 'Create', 'Again') {
    if ($Run -eq 'Again') {
        $ApId = (Get-OERAccessPackage -DisplayName 'oer-s83-ap' -ErrorAction Stop | Select-Object -First 1).Id
        $Filter = [uri]::EscapeDataString("accessPackage/id eq '$ApId'")
        $null = Wait-OerLiveConverged -Activity 'oer-s83-ext2 is listed on oer-s83-ap' -Read {
            $L = Invoke-OerLiveGraph -All -Uri "$Em/assignmentPolicies?`$filter=$Filter"
            if ($L.Refused) { Assert-OerLiveOk -Response $L -Activity 'Reading the policies of oer-s83-ap' | Out-Null }
            , @(if ($L.Ok) { @($L.Body['value']) | Where-Object { [string]$_['displayName'] -ceq 'oer-s83-ext2' } })
        } -Test { @($args[0]).Count -ge 1 }
    }
    $Rows = if ($Run -eq 'WhatIf') {
        @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    } else {
        @(Invoke-OERStructure -Json $Json -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
    }
    Write-OerLiveStep "$Run rows: $(($Rows | Group-Object Action | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
    foreach ($R in $Rows) { Write-OerLiveStep "$Run row: [$($R.Section)] $($R.Item) $($R.Action) -- $($R.Detail)" }
    foreach ($E in @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "$Run error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
}
$Live = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-s83-ap' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'oer-s83-ext*' })
foreach ($P in $Live) { Write-OerLiveStep "Live policy '$($P.DisplayName)': AllowedTargetScope '$($P.AllowedTargetScope)'" }
Disconnect-OerLive
```

**Expect:** `WhatIf` plans `would create assignmentPolicy 'oer-s83-ext2'` and nothing else that
writes; `Create` gives `Created` for `oer-s83-ext2` and `Unchanged` for the rest; the wait lists the
new policy; `Again` gives only `Unchanged`, `oer-s83-ext2` included; no error in any run; both live
policies read `allExternalUsers`. If 1.1 recorded `unknownFutureValue`, `Again` gives `Failed` for
both policies instead -- record it as a finding (the convergence of such a policy then needs the
Prefer header, which this step does not add).
**Failure looks like:** a `Failed` row on `Create` (the builder refused the value), a second
`Created` on `Again`, or any `Updated` on `Again` (the policy did not converge).

Result:

### 2. The lookups, as oer-live-cc-noperm

### 2.1. Set-OERGroupPimPolicy: a refused approver lookup is not ApproverNotFound

- [ ] **2.1** `Set-OERGroupPimPolicy -ApproverUser ... -WhatIf` against a made-up group id reports the refused approver lookup as itself, never as `ApproverNotFound`; the error id and the HTTP status are recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Approver = "oer-s83-nobody@$($Cfg.UserDomain)"
$Res = @(Set-OERGroupPimPolicy -Group '00000000-0000-0000-0000-000000000099' -AccessType member -ApproverUser $Approver -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
$All = @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Own = @($All | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERGroupPimPolicy' })
Write-OerLiveStep "Output objects: $($Res.Count); error records: $($All.Count); the cmdlet's own: $($Own.Count)"
foreach ($E in $Own) { Write-OerLiveStep "Own error: $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category); target '$($E.TargetObject)' -- $($E.Exception.Message)" }
Write-OerLiveStep "Any ApproverNotFound: $(@($All | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count -gt 0)"
$Filter = [uri]::EscapeDataString("userPrincipalName eq '$Approver'")
$Probe = Invoke-OerLiveGraph -Uri "v1.0/users?`$filter=$Filter&`$select=id"
Write-OerLiveStep "The same lookup, raw: HTTP $($Probe.Status) $($Probe.Code)"
Disconnect-OerLive
```

**Expect:** no output object; the cmdlet's own error is the refused lookup itself
(`Authorization_RequestDenied,Set-OERGroupPimPolicy`, the transport's id), never `ApproverNotFound`
and never `AmbiguousApproverName`; `Any ApproverNotFound: False`; the raw lookup answers
`HTTP 403 Authorization_RequestDenied`. Before this branch the cmdlet wrote `ApproverNotFound`
(category ObjectNotFound) for the same refusal. Nothing is written: `-WhatIf`, and an identity with no
permission.
**Failure looks like:** `ApproverNotFound` -- the defect of this branch; a 403 as `oer-live-cc` would
be a stop, but this is the no-permission identity.

Result:

### 2.2. Set-OERDirectoryRoleManagementPolicy: the same, for a low-risk role

- [ ] **2.2** `Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser ... -WhatIf` reports the refused approver lookup as itself; the error id and the HTTP status are recorded.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Approver = "oer-s83-nobody@$($Cfg.UserDomain)"
$Res = @(Set-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' -ApproverUser $Approver -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue)
$All = @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Own = @($All | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Set-OERDirectoryRoleManagementPolicy' })
Write-OerLiveStep "Output objects: $($Res.Count); error records: $($All.Count); the cmdlet's own: $($Own.Count)"
foreach ($E in $Own) { Write-OerLiveStep "Own error: $($E.FullyQualifiedErrorId); category $($E.CategoryInfo.Category); target '$($E.TargetObject)' -- $($E.Exception.Message)" }
Write-OerLiveStep "Any ApproverNotFound: $(@($All | Where-Object { [string]$_.FullyQualifiedErrorId -like 'ApproverNotFound*' }).Count -gt 0)"
$Filter = [uri]::EscapeDataString("userPrincipalName eq '$Approver'")
$Probe = Invoke-OerLiveGraph -Uri "v1.0/users?`$filter=$Filter&`$select=id"
Write-OerLiveStep "The same lookup, raw: HTTP $($Probe.Status) $($Probe.Code)"
Disconnect-OerLive
```

**Expect:** as 2.1 for this cmdlet: `Authorization_RequestDenied,Set-OERDirectoryRoleManagementPolicy`,
never `ApproverNotFound`; the raw lookup `HTTP 403 Authorization_RequestDenied`. The approvers are
resolved before the role and its policy are read, so the role lookup is never reached. Nothing is
written.
**Failure looks like:** `ApproverNotFound`; an error about the role instead of the approver (the order
changed).

Result:

### 2.3. Remove-OERAccessReviewDefinition: a refused read warns that the Lifecycle check could not be made

- [ ] **2.3** `Remove-OERAccessReviewDefinition -WhatIf` against a made-up id warns that the definition could not be read and the Lifecycle check could not be made, writes no error, and still plans the delete.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Res = @(Remove-OERAccessReviewDefinition -Id '00000000-0000-0000-0000-000000000099' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable RunErr -WarningAction SilentlyContinue -WarningVariable RunWarn)
$All = @($RunErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$Own = @($All | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Remove-OERAccessReviewDefinition' })
Write-OerLiveStep "Output objects: $($Res.Count); warnings: $(@($RunWarn).Count); error records: $($All.Count); the cmdlet's own: $($Own.Count)"
foreach ($W in @($RunWarn)) { Write-OerLiveStep "Warning: $W" }
$Probe = Invoke-OerLiveGraph -Uri 'v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000099'
Write-OerLiveStep "The same read, raw: HTTP $($Probe.Status) $($Probe.Code)"
Disconnect-OerLive
```

**Expect:** a `What if:` line for the delete of the made-up id; one warning that names the read's
error and says the check for an assignment policy's Lifecycle access review could not be made; the
cmdlet's own errors `0`; the raw read answers `HTTP 403`. Before this branch the failed read was
swallowed and nothing said the check had not been made. Nothing is written: `-WhatIf`, and an
identity with no permission.
**Failure looks like:** no warning (the failure is still swallowed); an error record from the cmdlet
(under a global Stop it would stop the delete).

Result:

## Teardown

### T.1. The teardown's plan

- [ ] **T.1** `-Teardown -WhatIf` plans only `oer-s83-` objects.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s83\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s83-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s83-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the plan deletes, through the library (step 3 of 6), the policies `oer-s83-ext` and
`oer-s83-ext2`, the access package `oer-s83-ap` and the catalog `oer-s83-catalog`, every tenant target
starting with `oer-s83-`; `WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP.

Result:

### T.2. The teardown

- [ ] **T.2** Every `oer-s83-` object is gone, and the counts match the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the library deleting both policies, the package and the catalog; the sweep finding no
`oer-s83-` object (a catalog or package deleted seconds earlier can still be listed for a while --
T.3 reads again); `Counts: catalogs ... equal: True` and `accessPackages ... equal: True`; exit code
`0`.
**Failure looks like:** a `RESIDUE` line or exit code `3` -- record it in the report; exit code `1`.

Result:

### T.3. Read back, and clean up

- [ ] **T.3** Minutes later the sweep is clean, the counts match the baseline, the main clone is still on `main` at the HEAD S.1 recorded, and the redaction map is deleted after the write-up.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s83-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s83'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS83Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7)); exit code: $Code"
```

**Expect:** `prefixed objects left: 0; unread collections: 0; residue rows: 0`; both counts `equal:
True`; the main clone on `main` at the HEAD S.1 recorded; exit code `0`. After the results are
copied into this file: `Clear-OerLiveRedactionMap`, and `raw\s83\` deleted.
**Failure looks like:** a prefixed object left, or a residue row -- the teardown did not finish;
record it in the report.

Result:
