# Live verification checklist -- a failed lookup is reported as itself, not as not found (fix/resolver-failure-is-not-not-found)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s72-`.** The
prerequisite script creates one security group, one empty catalog and one hidden access package in
it with no binding -- and no assignment policy and no assignment, so nobody can request or receive
the package. The checklist itself then makes exactly two writes through the module: it adds the group
as the catalog's resource (2.1) and binds the group's Member role to the package through
`Invoke-OERStructure` (2.6). It changes no directory role, no policy and no object outside the
prefix. Every other check only READS the tenant, and the checks that must not write run behind a
read-only fence that refuses every Microsoft Graph request that is not a read (see Setup).

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS72Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Section 1 signs in as
`oer-live-cc-noperm`, the same certificate's identity with no permission at all, so that every
lookup is refused: a 403 there is the expected outcome, not a stop. Every sign-in is app-only;
nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown, and
the apply in 2.6, run first with `-WhatIf`; read the plan against the `Expect:` line before running
the line that writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s72/` -- the
library writes its transcript and the baseline there, and the folder is git-ignored. Every block
below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The library keeps one
real-to-placeholder map per step, outside the clone and the operator's notes, and deletes it after
the write-up. **No credential, token, application id or certificate thumbprint is ever printed.**
**Never render an error record** (`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw
Graph failure's record carries the bearer token. Every block prints the error id, category and
message only.

## What changed and why this needs a live tenant

The branch closes the places where a failed lookup was reported as a missing object, and one place
where a name shared by several objects acted on the first of them. Commits are named by SUBJECT,
never by hash: the hashes change when the branch is rebased onto `main` before it merges.

- **A. Twenty-one lookups report a failure as itself** ("Report a failed group, catalog or
  application lookup as itself"). Seventeen cmdlets resolve a catalog, group or application name
  in a `try`; an ambiguous name was refused, but any other throw -- a 403, an exhausted 429, a 5xx --
  fell through to `CatalogNotFound`, `GroupNotFound` or `ApplicationNotFound`. It is now published as
  itself; only a name that matches nothing is not found. A cohort test in
  `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1` runs every public resolver call site with a 403.
- **B. The catalog resource read** ("Report a failed catalog resource read as itself, never as an
  empty fact"). `Add-OERAccessPackageResourceRole` reported a refused read of the catalog's resources
  as `CatalogResourceNotFound`; `Add-OERCatalogResource` went on to POST an `adminAdd` when its check
  for an existing resource failed, and said nothing when the read-back after a successful POST
  failed. The first two now report the failure (and the second stops before the POST); the third
  warns that the resource was added but could not be read back.
- **C. User, group, catalog and policy lookups behind the approval, requestor and review cmdlets**
  ("Report a failed user, group, catalog or policy lookup as itself"): six lookups inside three
  private helpers returned "not found" for a failed read; the five cmdlets that use them now publish
  the failure as itself.
- **D. The remaining swallowed reads** ("Report a failed definition, policy-id or profile read as
  itself"): `Remove-OERAccessReviewDefinition` and `Set-OERAccessReviewDefinition` publish a failed
  definition lookup as itself, `Add-OERGroupEligibility` no longer says a group is not onboarded when
  its policy could not be read, and an apply run reports an unreadable Tenant Profile instead of "no
  default".
- **E. An ambiguous access review definition name is refused** ("Refuse an ambiguous access review
  definition name instead of acting on the first match", "Refuse an ambiguous access review
  definition name in the apply engine", "Report a failed access review definition lookup as a
  ReadError, not an ObjectNotFound"). Graph does not enforce unique review names, and
  `Remove-OERAccessReviewDefinition -DisplayName` deleted, `Set-OERAccessReviewDefinition` and
  `Invoke-OERStructure` updated, the first of several same-named definitions. The lookup now refuses
  such a name with `AmbiguousName` naming every candidate id, in all seven cmdlets and in the apply
  engine, and nothing is deleted or written. The same holds for an assignment policy name that two
  policies of one access package share ("Refuse an ambiguous assignment policy name"): the apply
  engine reports that policy `Failed` naming the candidates and writes nothing to either, and
  `New-OERAccessReviewDefinition` refuses to scope a review to one of them.
- **F. Access reviews in the inventory** ("Report a failed access review name lookup as partial and
  leave no stray records for a deleted target", "Write the id for an access review name answer that
  carries no name, ..."). A review whose access package or policy cannot be read is written with the
  id and named in `InventoryPartial`; a review whose package or policy was deleted is written with
  the id and leaves no stray error record -- step 1's export left about twenty per such review.
- **G. More names that several objects share** ("Refuse an ambiguous catalog resource name in an
  access package binding", "Refuse a group that shares its name with a non-group catalog resource,
  and withhold the prune for a group outside the catalog", "Refuse a name that a group outside the
  catalog shares with another group the catalog recorded", "Refuse a resource role display name that
  several roles of a catalog resource share", "Refuse an ambiguous subscription or management group
  display name when resolving a scope"). A binding whose resource name can identify more than one
  catalog resource is `Failed` and the package's binding prune is withheld -- earlier versions bound
  the first match and, under `-Prune`, removed the binding of the resource the document meant;
  `Add-OERAccessPackageResourceRole` refuses a role name several roles of the resource share; a
  subscription or management group display name several share is refused in the Azure cmdlets and
  the apply engine, where `Remove-OERResourceGroup` and the role assignment cmdlets used the first.
- **H. An administrative unit's scoped roles are not removed when the role names cannot be read**
  ("Treat an unreadable directory role name map as unread scoped roles, not as undeclared roles").
  A failed read of the directory role names gave every scoped role an empty name, and `-Prune`
  removed every scoped role the document declared by name; the unit is now `Failed` and nothing is
  removed, and `Get-OERInventory` exports its `scopedRoles` as `null` named in `InventoryPartial`.

A live tenant is needed for what mocks cannot show: that each refused lookup reaches the operator as
Graph's own refusal (section 1), that the success and not-found paths are unchanged and the two Add
cmdlets converge (section 2), and that the real inventory of the test tenant's access reviews reads
without stray records (section 3).

## What this file does not check, and why

- **The ambiguous name cannot be provoked here.** `oer-live-cc` reads access reviews but cannot
  create one (`AccessReview.Read.All` only, and no permission is added in this sprint), so two
  definitions with the same name cannot be made. The refusal in the resolver, the seven cmdlets and
  the apply engine is proven by mocked, mutation-proven unit tests:
  `tests/Unit/Private/Resolve-OERAccessReviewDefinitionId.Tests.ps1`, the seven cmdlets' own tests,
  the cohort cases in `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1`, and the Describe
  `Sync-OERStructureAccessReview refuses an ambiguous definition name` -- where removing
  the check makes `Remove-OERAccessReviewDefinition` DELETE and the apply engine update the first
  match. An ambiguous assignment policy name is proven the same way, in
  `tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1`, `Resolve-OERAccessReviewScopeTarget.Tests.ps1`
  and `New-OERAccessReviewDefinition.Tests.ps1`: making two same-named policies here would mean creating
  assignment policies on a real package, which this file's setup deliberately never does.
- **The other shared-name refusals (G) and the scoped-role guard (H)** need objects this file cannot
  make safely or at all -- two same-named catalog resources, two same-named roles of one application,
  two same-named subscriptions, a refused directory role read -- and are proven by mocked,
  mutation-proven tests in `tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1`,
  `tests/Unit/Public/Add-OERAccessPackageResourceRole.Tests.ps1`, `tests/Unit/Private/Resolve-OERScope.Tests.ps1`,
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1` and `tests/Unit/Public/Get-OERAdministrativeUnit.Tests.ps1`.
- **A failure behind a successful first lookup cannot be provoked selectively.** `oer-live-cc` reads
  everything section 2 touches and `oer-live-cc-noperm` reads nothing, so `noperm` always fails at a
  cmdlet's FIRST lookup (1.2 shows it for `Add-OERAccessPackageResourceRole`, whose first lookup was
  already correct). The later lookups -- the catalog resource read in both Add cmdlets, and the
  read-back after a POST -- are proven by mocked, mutation-proven tests in their own test files.
- **A failed read in the inventory's access review section** cannot be provoked with a working
  identity; it is proven by the real-transport tests in `tests/Unit/Public/Get-OERInventory.Tests.ps1`.
  3.1 measures the not-found side, which the test tenant has.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- with entitlement management, and the two
  configuration files OerLive reads beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS72Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder (the environment variable `OER_LIVE_DIR`). Every block starts with the same four lines, so
  each block also runs on its own in a fresh window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` reads and writes entitlement management and groups
  (`EntitlementManagement.ReadWrite.All`, `Group.ReadWrite.All`) and reads the directory; no other
  permission is needed by this file.
- The **built module of this branch** in the clone OerLive loads from (S.1 does it).

**The fence.** Every check that runs a module cmdlet replaces the module's Graph transport, in the
module's own scope, with a thin wrapper that records each request's method and path. In the checks
marked read-only it also refuses every request that is not a GET, with an error naming the method
and path. A lookup and a `-WhatIf` make no other request, so the fence changes nothing on the
success path; and should a cmdlet try to write where it must not, the write is refused instead of
sent, and the count shows it.

### S.1. Point the clone at this branch and build it

- [ ] **S.1** The clone OerLive loads from holds this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Write-OerLiveStep "Tracked changes in the clone before the switch: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$null = git -C $Cfg.Repo fetch origin fix/resolver-failure-is-not-not-found 2>&1
$null = git -C $Cfg.Repo switch --detach FETCH_HEAD 2>&1
Write-OerLiveStep "Clone at: $(git -C $Cfg.Repo log -1 --format='%h %s')"
Push-Location -LiteralPath $Cfg.Repo
try { ./build.ps1 -Tasks build *> (Join-Path $env:TEMP 'oer-s72-build.log'); $Code = $LASTEXITCODE } finally { Pop-Location }
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'but reading it back failed, so it is not returned' -Quiet)
Write-OerLiveStep "Build exit code: $Code; the built module carries this branch's fix: $Fix"
```

**Expect:** `Tracked changes in the clone before the switch: 0`; the clone at the branch head (its
subject is the last commit of this branch); `Build exit code: 0; the built module carries this
branch's fix: True`.
**Failure looks like:** tracked changes in the clone -- stop, the clone is someone's work; a build
exit code other than 0; `False` -- the clone did not get this branch, and every check below would
measure `main`.

Result:

### 0. Preparation

### 0.1. Identity check as oer-live-cc, Graph and the module session

- [ ] **0.1** Both sign-ins pass the identity check, and the module is this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Graph
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the clone's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True` for both sign-ins (app-only certificate session with the
identity's app id, the app name `oer-live-cc`, the test tenant, the service principal of that app id
named `oer-live-cc` and, for the module session, the token's signed-in object; the organization name,
a verified domain and the organization id; the ARM token from the certificate; the test subscription
belongs to the test tenant and is Enabled), each sign-in ending `identity check passed: True`, and
`The module is the clone's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result:

### 0.2. Identity check as oer-live-cc-noperm, the module session and Graph

- [ ] **0.2** The no-permission identity signs in to a module session and to Graph.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm -NoPerm
Connect-OerLive -Graph -NoPerm
Disconnect-OerLive
```

**Expect:** for both sign-ins the lines for `oer-live-cc-noperm`: app-only with its app id `True`,
the app name in the session is `oer-live-cc-noperm`: `True`, the test tenant `True`, for the module
session the ARM token from the certificate `True`, and `identity check passed: True`. It proves its
name through the session, since it can read nothing.
**Failure looks like:** any `False` -- STOP; section 1 needs both sessions.

Result:

### 0.3. The prerequisite script's plan

- [ ] **0.3** `-WhatIf` plans only `oer-s72-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS72Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s72\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s72-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s72-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s72-`
object; the plan names the transcript and the baseline file under `raw\s72\` and, in the tenant, the
group `oer-s72-grp`, the catalog `oer-s72-catalog` and the package `oer-s72-ap` -- three tenant
targets, every one starting with `oer-s72-`; `WhatIf: nothing was created, removed or written`;
exit code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result:

### 0.4. The prerequisite script, for real

- [ ] **0.4** The test objects exist: the group, the empty catalog and the hidden package with no binding.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS72Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created group oer-s72-grp`,
`Created catalog oer-s72-catalog`, `Created access package oer-s72-ap (hidden)` and the catalog
listing the package; the summary with the three objects `present` and the checklist's own writes
(resource, binding) `absent`; exit code `0`. A `likely replication delay` line on a fresh object is
expected, and is not a failure.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way.

Result:

### 1. Every lookup refused, as oer-live-cc-noperm

Each check signs in as `oer-live-cc-noperm`, runs one cmdlet against the test objects behind the
fence, and prints only the records that cmdlet itself published -- not the engine's own capture of
the inner throw, which `-ErrorVariable` also holds -- then repeats the lookup that failed on the raw
transport, to show the HTTP status Graph answered with. A 403 here is the expected outcome.

### 1.1. Add-OERCatalogResource: the catalog lookup refused

- [ ] **1.1** The refused catalog lookup is reported as itself, never as `CatalogNotFound`, and nothing is written.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Add-OERCatalogResource -Catalog 'oer-s72-catalog' -Group 'oer-s72-grp' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
$Mine = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Add-OERCatalogResource' })
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Output: $($Out.Count) object(s); records Add-OERCatalogResource published: $($Mine.Count)"
foreach ($E in $Mine) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) [$($E.CategoryInfo.Category)] -- $($E.Exception.Message)" }
Write-OerLiveStep "A published id names NotFound: $(@($Mine | Where-Object { $_.FullyQualifiedErrorId -match 'NotFound' }).Count -gt 0)"
Write-OerLiveStep "Requests: $($Fence.Seen.Count) [$($Fence.Seen -join '; ')]; refused by the fence: $($Fence.Refused.Count)"
Connect-OerLive -Graph -NoPerm
$R = Invoke-OerLiveGraph -Uri ("v1.0/identityGovernance/entitlementManagement/catalogs?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-catalog'"))
Write-OerLiveStep "The same catalog lookup on the raw transport: HTTP $($R.Status) $($R.Code)"
Disconnect-OerLive
```

**Expect:** `Output: 0 object(s); records Add-OERCatalogResource published: 1`, its id the refusal's
own Graph code followed by `,Add-OERCatalogResource` (not `CatalogNotFound`), category
`OperationStopped`, the message naming the refusal; `A published id names NotFound: False`; one
request, a GET of the catalogs listing, and `refused by the fence: 0`; the raw lookup `HTTP 403`.
On `main` the same call publishes `CatalogNotFound,Add-OERCatalogResource` -- "Catalog
'oer-s72-catalog' not found." -- about a catalog that exists.
**Failure looks like:** a published id ending in `NotFound`; no published record; a request that is
not a GET; a raw status other than 403 -- read it before going on.

Result:

### 1.2. Add-OERAccessPackageResourceRole: the first lookup refused

- [ ] **1.2** The refused lookup is reported as itself, never as a not-found, and nothing is written.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Add-OERAccessPackageResourceRole -AccessPackage 'oer-s72-ap' -Catalog 'oer-s72-catalog' -Group 'oer-s72-grp' -Role 'Member' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
$Mine = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Add-OERAccessPackageResourceRole' })
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Output: $($Out.Count) object(s); records Add-OERAccessPackageResourceRole published: $($Mine.Count)"
foreach ($E in $Mine) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) [$($E.CategoryInfo.Category)] -- $($E.Exception.Message)" }
Write-OerLiveStep "A published id names NotFound: $(@($Mine | Where-Object { $_.FullyQualifiedErrorId -match 'NotFound' }).Count -gt 0)"
Write-OerLiveStep "Requests: $($Fence.Seen.Count) [$($Fence.Seen -join '; ')]; refused by the fence: $($Fence.Refused.Count)"
Connect-OerLive -Graph -NoPerm
$R = Invoke-OerLiveGraph -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-ap'"))
Write-OerLiveStep "The same access package lookup on the raw transport: HTTP $($R.Status) $($R.Code)"
Disconnect-OerLive
```

**Expect:** `Output: 0 object(s); records Add-OERAccessPackageResourceRole published: 1`, its id the
refusal's own code followed by `,Add-OERAccessPackageResourceRole`; `A published id names NotFound:
False`; one request, a GET of the access packages listing, and `refused by the fence: 0`; the raw
lookup `HTTP 403`. The access package is this cmdlet's FIRST lookup, and it already reported a
failure as itself before this branch (issue #71's fix); the catalog, group and application lookups
this branch changed come after it, so `oer-live-cc-noperm` never reaches them. This check therefore
proves the cmdlet's refused path as a whole; the changed lookups are proven by the unit tests named
under "What this file does not check".
**Failure looks like:** a published id ending in `NotFound`; no published record; a request that is
not a GET.

Result:

### 1.3. Get-OERGroupMember: the group lookup refused

- [ ] **1.3** The refused group lookup is reported as itself, never as `GroupNotFound`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Get-OERGroupMember -Group 'oer-s72-grp' -ErrorAction SilentlyContinue -ErrorVariable Err)
$Mine = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroupMember' })
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Output: $($Out.Count) object(s); records Get-OERGroupMember published: $($Mine.Count)"
foreach ($E in $Mine) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) [$($E.CategoryInfo.Category)] -- $($E.Exception.Message)" }
Write-OerLiveStep "A published id names NotFound: $(@($Mine | Where-Object { $_.FullyQualifiedErrorId -match 'NotFound' }).Count -gt 0)"
Write-OerLiveStep "Requests: $($Fence.Seen.Count) [$($Fence.Seen -join '; ')]; refused by the fence: $($Fence.Refused.Count)"
Connect-OerLive -Graph -NoPerm
$R = Invoke-OerLiveGraph -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-grp'"))
Write-OerLiveStep "The same group lookup on the raw transport: HTTP $($R.Status) $($R.Code)"
Disconnect-OerLive
```

**Expect:** `Output: 0 object(s); records Get-OERGroupMember published: 1`, its id the refusal's own
code followed by `,Get-OERGroupMember` (not `GroupNotFound`); `A published id names NotFound:
False`; one request, a GET of the groups listing, and `refused by the fence: 0`; the raw lookup
`HTTP 403`. On `main` the same call publishes `GroupNotFound,Get-OERGroupMember` about a group that
exists.
**Failure looks like:** a published id ending in `NotFound`; no published record.

Result:

### 1.4. Remove-OERAccessReviewDefinition: the definition lookup refused

- [ ] **1.4** The refused definition lookup is reported as itself, never as `AccessReviewDefinitionNotFound`, and nothing is deleted.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Remove-OERAccessReviewDefinition -DisplayName 'oer-s72-review' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)
$Mine = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessReviewDefinition' })
$Seen = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Records Remove-OERAccessReviewDefinition published: $($Mine.Count)"
foreach ($E in $Mine) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) [$($E.CategoryInfo.Category)] -- $($E.Exception.Message)" }
Write-OerLiveStep "A published id names NotFound: $(@($Mine | Where-Object { $_.FullyQualifiedErrorId -match 'NotFound' }).Count -gt 0)"
Write-OerLiveStep "Requests: $($Seen.Seen.Count) [$($Seen.Seen -join '; ')]; refused by the fence: $($Seen.Refused.Count)"
Connect-OerLive -Graph -NoPerm
$R = Invoke-OerLiveGraph -Uri ("v1.0/identityGovernance/accessReviews/definitions?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-review'"))
Write-OerLiveStep "The same definition lookup on the raw transport: HTTP $($R.Status) $($R.Code)"
Disconnect-OerLive
```

**Expect:** `Records Remove-OERAccessReviewDefinition published: 1`, its id the refusal's own Graph code
followed by `,Remove-OERAccessReviewDefinition` (not `AccessReviewDefinitionNotFound`); `A published
id names NotFound: False`; one request, a GET of the definitions listing, `refused by the fence: 0`;
no `What if:` line (the lookup fails before the plan); the raw lookup `HTTP 403`. On `main` the same
call publishes `AccessReviewDefinitionNotFound` -- "Access review definition not found." -- for a read
that was refused.
**Failure looks like:** a published id ending in `NotFound`; a `What if:` line; a request that is not a GET.

Result:

### 1.5. Get-OERAccessReviewInstance: the refused lookup keeps its failure id and now carries the cause

- [ ] **1.5** The refused definition lookup is `AccessReviewDefinitionResolveFailed` with the refusal in its message.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Get-OERAccessReviewInstance -Definition 'oer-s72-review' -ErrorAction SilentlyContinue -ErrorVariable Err)
$Mine = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessReviewInstance' })
$Seen = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Output: $($Out.Count) object(s); records Get-OERAccessReviewInstance published: $($Mine.Count)"
foreach ($E in $Mine) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) [$($E.CategoryInfo.Category)] -- $($E.Exception.Message)" }
Write-OerLiveStep "Requests: $($Seen.Seen.Count) [$($Seen.Seen -join '; ')]; refused by the fence: $($Seen.Refused.Count)"
Disconnect-OerLive
```

**Expect:** `Output: 0 object(s); records Get-OERAccessReviewInstance published: 1`:
`AccessReviewDefinitionResolveFailed,Get-OERAccessReviewInstance`, its message "Failed to resolve access
review definition 'oer-s72-review'" followed by the refusal's own text; one GET; `refused by the
fence: 0`. On `main` the message stops after the name and the cause is lost.
**Failure looks like:** a message without the refusal; an id ending in `NotFound`.

Result:

### 2. The success path and the not-found path, as oer-live-cc

### 2.1. Add-OERCatalogResource adds the group to the catalog

- [ ] **2.1** The group is added as the catalog's resource, with one POST, and the catalog lists it.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Add-OERCatalogResource -Catalog 'oer-s72-catalog' -Group 'oer-s72-grp' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Seen = & (Get-Module Omnicit.EntraRBAC) { @($script:S72Seen) }
Write-OerLiveStep "Output: $($Out.Count) object(s)"
foreach ($O in $Out) { Write-OerLiveStep "Resource ($($O.PSObject.TypeNames[0])): $(ConvertTo-Json -InputObject ($O | Select-Object -Property *) -Depth 3 -Compress)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Requests: $($Seen.Count); not a GET: $(@($Seen | Where-Object { $_ -notlike 'GET *' }).Count) [$(@($Seen | Where-Object { $_ -notlike 'GET *' }) -join '; ')]"
Connect-OerLive -Graph
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Cat = Invoke-OerLiveGraph -Uri ("$Em/catalogs?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-catalog'"))
$Grp = Invoke-OerLiveGraph -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-grp'"))
$CatId = [string]@($Cat.Body['value'])[0]['id']
$GrpId = ([string]@($Grp.Body['value'])[0]['id']).ToLowerInvariant()
$W = Wait-OerLiveConverged -Activity 'oer-s72-catalog lists oer-s72-grp as its one resource' -Read {
    $R = Invoke-OerLiveGraph -All -Uri "$Em/catalogs/$CatId/resources"
    Assert-OerLiveOk -Response $R -Activity 'Reading the resources of oer-s72-catalog' | Out-Null
    , @($R.Body['value'])
} -Test { @($args[0]).Count -eq 1 -and ([string]@($args[0])[0]['originId']).ToLowerInvariant() -eq $GrpId }
Disconnect-OerLive
```

**Expect:** `Output: 1 object(s)`: an `Omnicit.EntraRBAC.CatalogResource` for `oer-s72-grp`, origin
system `AadGroup`, its origin id the group's placeholder; no error and no warning; exactly one request
that is not a GET, `POST v1.0/identityGovernance/entitlementManagement/resourceRequests`; the catalog
listing the group as its one resource (converged). Record whether the response carried the resource
inline or the cmdlet read it back (a second GET of the catalog's resources after the POST).
**Failure looks like:** an error -- a `400 ResourceNotFoundInOriginSystem` is replication of the new
group, so wait a minute and run 2.1 again; anything else, read it. A second POST.

Result:

### 2.2. The same call again returns the existing resource, and writes nothing

- [ ] **2.2** Behind the read-only fence the cmdlet finds the resource and makes no POST.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Add-OERCatalogResource -Catalog 'oer-s72-catalog' -Group 'oer-s72-grp' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Output: $($Out.Count) object(s)"
foreach ($O in $Out) { Write-OerLiveStep "Resource ($($O.PSObject.TypeNames[0])): $(ConvertTo-Json -InputObject ($O | Select-Object -Property *) -Depth 3 -Compress)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Requests: $($Fence.Seen.Count) [$($Fence.Seen -join '; ')]; not a GET: $(@($Fence.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** `Output: 1 object(s)`, the same resource as 2.1 (same origin id placeholder, same id); no
error and no warning; every request a GET (the catalog lookup, the group lookup and the catalog's
resources), `not a GET: 0; refused by the fence: 0`.
**Failure looks like:** `refused by the fence` above 0 -- the idempotency check did not find the
resource and the cmdlet tried to add it again; an error.

Result:

### 2.3. A group name that does not exist is GroupNotFound

- [ ] **2.3** A name that matches no group is `GroupNotFound`, with no POST.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Add-OERCatalogResource -Catalog 'oer-s72-catalog' -Group 'oer-s72-missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
$Mine = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Add-OERCatalogResource' })
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Output: $($Out.Count) object(s); records Add-OERCatalogResource published: $($Mine.Count)"
foreach ($E in $Mine) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) [$($E.CategoryInfo.Category)] -- $($E.Exception.Message)" }
Write-OerLiveStep "Requests: $($Fence.Seen.Count) [$($Fence.Seen -join '; ')]; refused by the fence: $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** `Output: 0 object(s); records Add-OERCatalogResource published: 1`:
`GroupNotFound,Add-OERCatalogResource [ObjectNotFound] -- Group 'oer-s72-missing' not found.`; two
requests, both GET (the catalog lookup and the group lookup); `refused by the fence: 0`.
**Failure looks like:** any other id -- the not-found path changed; a request that is not a GET.

Result:

### 2.4. Add-OERAccessPackageResourceRole by name, as a plan

- [ ] **2.4** With `-WhatIf` every lookup succeeds and the bind is planned, not sent.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Add-OERAccessPackageResourceRole -AccessPackage 'oer-s72-ap' -Catalog 'oer-s72-catalog' -Group 'oer-s72-grp' -Role 'Member' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Output: $($Out.Count) object(s); errors: $(@($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count)"
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Write-OerLiveStep "Requests: $($Fence.Seen.Count) [$($Fence.Seen -join '; ')]; not a GET: $(@($Fence.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** one `What if:` line, `Bind resource role 'Member' of` the group's placeholder, on the
package's placeholder as target; `Output: 0 object(s); errors: 0`; every request a GET (the package,
catalog and group lookups, the catalog's resources and the group's roles in the catalog);
`not a GET: 0; refused by the fence: 0`. This runs every lookup this branch changed in this cmdlet
on its success path.
**Failure looks like:** an error -- in particular `CatalogResourceNotFound` would mean 2.1's resource
is not visible yet (run 2.2 first); a request that is not a GET.

Result:

### 2.5. The apply document's plan: the binding would be added, nothing else changes

- [ ] **2.5** `Invoke-OERStructure -WhatIf` plans exactly one change, the Member binding of `oer-s72-ap`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Just = 'Omnicit.EntraRBAC live verification (oer-s72): a failed lookup is reported as itself.'
$Doc = [ordered]@{
    version        = '1.0'
    catalogs       = @([ordered]@{ displayName = 'oer-s72-catalog'; description = $Just; externallyVisible = $false; resources = @([ordered]@{ type = 'Group'; name = 'oer-s72-grp' }) })
    accessPackages = @([ordered]@{ displayName = 'oer-s72-ap'; catalog = 'oer-s72-catalog'; description = $Just; hidden = $true; resourceRoles = @([ordered]@{ resource = 'oer-s72-grp'; role = 'Member' }); assignmentPolicies = @() })
}
$Rows = @(Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include Catalogs, AccessPackages -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
foreach ($Row in $Rows) { Write-OerLiveStep "Row: $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
Write-OerLiveStep "Requests: $($Fence.Seen.Count); not a GET: $(@($Fence.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Fence.Refused.Count)"
Disconnect-OerLive
```

**Expect:** rows for `oer-s72-catalog` and `oer-s72-ap` only; the catalog's rows `Unchanged`
(its properties, and the resource `oer-s72-grp` already present); for `oer-s72-ap` one `Skipped` row
saying the Member binding of `oer-s72-grp` would be added, and the rest `Unchanged`; no `Failed`,
no removal (no `-Prune`), no error; every request a GET, `refused by the fence: 0`.
**Failure looks like:** a `Failed` row; a row for an object without the prefix -- STOP; a planned
change other than the binding (the description or a flag would be rewritten -- read it before 2.6).

Result:

### 2.6. The apply document, for real: the binding is added through Add-OERAccessPackageResourceRole

- [ ] **2.6** The apply adds the Member binding with one POST and changes nothing else.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        & $script:S72Transport @PSBoundParameters
    }
}
$Just = 'Omnicit.EntraRBAC live verification (oer-s72): a failed lookup is reported as itself.'
$Doc = [ordered]@{
    version        = '1.0'
    catalogs       = @([ordered]@{ displayName = 'oer-s72-catalog'; description = $Just; externallyVisible = $false; resources = @([ordered]@{ type = 'Group'; name = 'oer-s72-grp' }) })
    accessPackages = @([ordered]@{ displayName = 'oer-s72-ap'; catalog = 'oer-s72-catalog'; description = $Just; hidden = $true; resourceRoles = @([ordered]@{ resource = 'oer-s72-grp'; role = 'Member' }); assignmentPolicies = @() })
}
$Rows = @(Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include Catalogs, AccessPackages -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Seen = & (Get-Module Omnicit.EntraRBAC) { @($script:S72Seen) }
foreach ($Row in $Rows) { Write-OerLiveStep "Row: $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
Write-OerLiveStep "Requests: $($Seen.Count); not a GET: $(@($Seen | Where-Object { $_ -notlike 'GET *' }).Count) [$(@($Seen | Where-Object { $_ -notlike 'GET *' }) -join '; ')]"
Connect-OerLive -Graph
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Ap = Invoke-OerLiveGraph -Uri ("$Em/accessPackages?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-ap'"))
$ApId = [string]@($Ap.Body['value'])[0]['id']
$W = Wait-OerLiveConverged -Activity 'oer-s72-ap lists one binding, the Member role' -Read {
    $R = Invoke-OerLiveGraph -All -Uri "$Em/accessPackages/$ApId/resourceRoleScopes?`$expand=role,scope"
    Assert-OerLiveOk -Response $R -Activity 'Reading the bindings of oer-s72-ap' | Out-Null
    , @($R.Body['value'])
} -Test { @($args[0]).Count -eq 1 -and [string]@($args[0])[0]['role']['displayName'] -ceq 'Member' }
Disconnect-OerLive
```

**Expect:** the same rows as 2.5, with the binding row `Updated` instead of `Skipped`; no error;
exactly one request that is not a GET, `POST` to the package's `resourceRoleScopes`; the package
listing one binding, the Member role (converged).
**Failure looks like:** a `Failed` row -- its Detail is the real error (before this branch, a failed
lookup inside the handler's call would have read `not found`); a second POST.

Result:

### 2.7. The same document again: only Unchanged, nothing written (G8)

- [ ] **2.7** Run twice, the document converges: the second run is all `Unchanged` and writes nothing.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Just = 'Omnicit.EntraRBAC live verification (oer-s72): a failed lookup is reported as itself.'
$Doc = [ordered]@{
    version        = '1.0'
    catalogs       = @([ordered]@{ displayName = 'oer-s72-catalog'; description = $Just; externallyVisible = $false; resources = @([ordered]@{ type = 'Group'; name = 'oer-s72-grp' }) })
    accessPackages = @([ordered]@{ displayName = 'oer-s72-ap'; catalog = 'oer-s72-catalog'; description = $Just; hidden = $true; resourceRoles = @([ordered]@{ resource = 'oer-s72-grp'; role = 'Member' }); assignmentPolicies = @() })
}
$Rows = @(Invoke-OERStructure -Json (ConvertTo-Json -InputObject $Doc -Depth 10) -Include Catalogs, AccessPackages -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
foreach ($Row in $Rows) { Write-OerLiveStep "Row: $($Row.Section) | $($Row.Item) | $($Row.Action) | $($Row.Detail)" }
foreach ($E in @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Rows: $($Rows.Count); by action: $(($Rows | Group-Object Action | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')"
Write-OerLiveStep "Requests: $($Fence.Seen.Count); not a GET: $(@($Fence.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Fence.Refused.Count)"
Connect-OerLive -Graph
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Cat = Invoke-OerLiveGraph -Uri ("$Em/catalogs?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-catalog'"))
$Ap = Invoke-OerLiveGraph -Uri ("$Em/accessPackages?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq 'oer-s72-ap'"))
$Res = Invoke-OerLiveGraph -All -Uri "$Em/catalogs/$([string]@($Cat.Body['value'])[0]['id'])/resources"
$Bind = Invoke-OerLiveGraph -All -Uri "$Em/accessPackages/$([string]@($Ap.Body['value'])[0]['id'])/resourceRoleScopes?`$expand=role,scope"
Write-OerLiveStep "Read back: oer-s72-catalog resources $(@($Res.Body['value']).Count) [$((@($Res.Body['value']) | ForEach-Object { [string]$_['displayName'] }) -join ', ')]; oer-s72-ap bindings $(@($Bind.Body['value']).Count) [$((@($Bind.Body['value']) | ForEach-Object { [string]$_['role']['displayName'] }) -join ', ')]"
Disconnect-OerLive
```

**Expect:** the same rows as 2.6, every one `Unchanged`; no error; every request a GET,
`refused by the fence: 0`; read back: the catalog holds one resource, `oer-s72-grp`, and the package
one binding, `Member`.
**Failure looks like:** any row other than `Unchanged` -- the cmdlets' writes do not converge; a
request refused by the fence.

Result:

### 2.8. Remove-OERAccessReviewDefinition with a name no definition has: not found, nothing deleted

- [ ] **2.8** A name that matches no definition is `AccessReviewDefinitionNotFound`, with no DELETE.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Out = @(Remove-OERAccessReviewDefinition -DisplayName 'oer-s72-review' -WhatIf -ErrorAction SilentlyContinue -ErrorVariable Err)
$Mine = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessReviewDefinition' })
$Seen = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
Write-OerLiveStep "Records Remove-OERAccessReviewDefinition published: $($Mine.Count)"
foreach ($E in $Mine) { Write-OerLiveStep "Published: $($E.FullyQualifiedErrorId) [$($E.CategoryInfo.Category)] -- $($E.Exception.Message)" }
Write-OerLiveStep "Requests: $($Seen.Seen.Count) [$($Seen.Seen -join '; ')]; not a GET: $(@($Seen.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Seen.Refused.Count)"
Disconnect-OerLive
```

**Expect:** `Records Remove-OERAccessReviewDefinition published: 1`:
`AccessReviewDefinitionNotFound,Remove-OERAccessReviewDefinition [ObjectNotFound] -- Access review definition
not found.`; one GET of the definitions listing; `not a GET: 0; refused by the fence: 0`; no `What if:`
line. The not-found path is unchanged by this branch.
**Failure looks like:** any other id; a `What if:` line naming a definition -- the name matched one.

Result:

### 3. The inventory, as oer-live-cc

### 3.1. A review pointing at a deleted package or policy is written by id, and leaves no stray record

- [ ] **3.1** The access review section reads without error records, and no failed read is hidden.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Inv = Get-OERInventory -Include AccessReviews -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn
$Seen = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
$Guid = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$Reviews = @($Inv.accessReviews)
Write-OerLiveStep "Access reviews exported: $($Reviews.Count); accessPackage written as an id: $(@($Reviews | Where-Object { [string]$_.accessPackage -match $Guid }).Count); assignmentPolicy written as an id: $(@($Reviews | Where-Object { [string]$_.assignmentPolicy -match $Guid }).Count)"
$Records = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "Error records: $($Records.Count)$(if ($Records.Count) { '; by id: ' + (($Records | Group-Object { ($_.FullyQualifiedErrorId -split ',')[0] } | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ') })"
foreach ($E in @($Records | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' })) { Write-OerLiveStep "Partial: $($E.Exception.Message)" }
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Requests: $($Seen.Seen.Count); not a GET: $(@($Seen.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Seen.Refused.Count)"
Disconnect-OerLive
```

**Expect:** the tenant's access reviews exported (only counts are printed, never their names); the
reviews whose package or policy has been deleted written with the id; `Error records: 0` -- no
`AccessPackageNotFound`, `PolicyNotFound` or `InvokeGraphHttpResponseException` record, where step 1's
1.1 recorded about twenty per such review on `main`; no `InventoryPartial`; a warning for any
review that is not access-package-scoped or is multi-stage, as before; `refused by the fence: 0`.
**Failure looks like:** a not-found record for a deleted package or policy -- the leak is back; an
`InventoryPartial` naming an access review -- a lookup failed: read its cause.

Result:

### 3.2. Administrative units: scoped roles still exported with their names

- [ ] **3.2** With the directory role names readable, every exported scoped role carries a role name and nothing is reported partial.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S72Seen = [System.Collections.Generic.List[string]]::new()
    $script:S72Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S72Transport) { $script:S72Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S72Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') { $script:S72Refused.Add("$($Method.ToUpperInvariant()) $Path"); throw "S72 read-only fence: refused $($Method.ToUpperInvariant()) $Path" }
        & $script:S72Transport @PSBoundParameters
    }
}
$Inv = Get-OERInventory -Include AdministrativeUnits -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn
$Seen = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = @($script:S72Seen); Refused = @($script:S72Refused) } }
$Units = @($Inv.administrativeUnits)
$Roles = @($Units | ForEach-Object { @($_.scopedRoles) } | Where-Object { $null -ne $_ })
Write-OerLiveStep "Administrative units exported: $($Units.Count); with scopedRoles null: $(@($Units | Where-Object { $null -eq $_.scopedRoles -and $_.PSObject.Properties.Name -contains 'scopedRoles' }).Count); scoped roles: $($Roles.Count); written as a role id instead of a name: $(@($Roles | Where-Object { [string]$_.role -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' }).Count)"
$Records = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep "Error records: $($Records.Count)$(if ($Records.Count) { '; by id: ' + (($Records | Group-Object { ($_.FullyQualifiedErrorId -split ',')[0] } | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ') })"
foreach ($W in @($Warn)) { Write-OerLiveStep "Warning: $W" }
Write-OerLiveStep "Requests: $($Seen.Seen.Count); a directoryRoles read: $(@($Seen.Seen | Where-Object { $_ -like 'GET v1.0/directoryRoles*' }).Count -gt 0); not a GET: $(@($Seen.Seen | Where-Object { $_ -notlike 'GET *' }).Count); refused by the fence: $($Seen.Refused.Count)"
Disconnect-OerLive
```

**Expect:** the tenant's administrative units exported (counts only); `with scopedRoles null: 0`;
every scoped role written with its name (`written as a role id instead of a name: 0`); `Error records: 0`; if any unit has a
scoped role, `a directoryRoles read: True`; `refused by the fence: 0`. If no unit has a scoped role,
record that the name map was never needed and the check shows only the unchanged export.
**Failure looks like:** a unit with `scopedRoles` null or an `InventoryPartial` -- the directory role
names could not be read: record the cause; a scoped role written as an id -- the map lacks it: record which.

Result:

## Teardown

### T.1. The teardown's plan

- [ ] **T.1** `-Teardown -WhatIf` plans the removal of only `oer-s72-` objects.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS72Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s72\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s72-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s72-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the plan removes, in the library's order, the Member binding
of `oer-s72-ap`, the package `oer-s72-ap`, the resource `oer-s72-grp` of `oer-s72-catalog`, the
catalog and the group `oer-s72-grp` -- every tenant target starting with `oer-s72-`;
`WhatIf: nothing was created, removed or written`; exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result:

### T.2. The teardown

- [ ] **T.2** Every `oer-s72-` object is removed, and the tenant's counts are back at the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS72Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** each removal answered and read back as gone, in the library's order; the sweep finds no
`oer-s72-` object (a group deleted seconds earlier can still show in the listing for a few seconds --
T.3 reads again); `Counts: catalogs ... equal: True` and `Counts: accessPackages ... equal: True`;
no residue; exit code `0`.
**Failure looks like:** exit code `3` -- residue: record each RESIDUE line, T.3 retries; exit code
`1` -- read the stop line.

Result:

### T.3. Read back, and clean up

- [ ] **T.3** Nothing with the prefix is left, no residue, and the raw folder and the redaction map are deleted.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s72-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s72'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS72Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Clean = [bool]($Code -eq 0 -and ($Out -match 'prefixed objects left: 0; unread collections: 0; residue rows: 0'))
Write-OerLiveStep "Read back clean: $Clean"
if ($Clean) {
    if (Test-Path -LiteralPath $Raw) { [System.IO.Directory]::Delete($Raw, $true) }
    Write-OerLiveStep "raw\s72 deleted: $(-not (Test-Path -LiteralPath $Raw))"
    Clear-OerLiveRedactionMap
}
```

**Expect:** `Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.`; both
counts equal to the baseline; `Read back clean: True`; `raw\s72 deleted: True`; the redaction map
cleared.
**Failure looks like:** a prefixed object left, or a residue row -- record it in the report, do not
delete the raw folder.

Result:
