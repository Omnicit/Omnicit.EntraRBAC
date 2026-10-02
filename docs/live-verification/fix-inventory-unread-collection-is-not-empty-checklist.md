# Live verification checklist -- an unread collection is never exported as empty (fix/inventory-unread-collection-is-not-empty)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant, and to nothing outside the prefix `oer-s71-`.** The
prerequisite script creates one security group, one catalog with that group as its resource, and
one hidden access package in the catalog with the group's Member role bound -- and no assignment
policy and no assignment, so nobody can request or receive the package. It changes no directory
role, no policy and no object outside the prefix. Every other check only READS the tenant: the two
exports read it, and the one apply in this file (2.1) is a `-Prune -WhatIf` plan, run behind a
read-only fence that refuses every Microsoft Graph request that is not a read (see Setup).

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library and
the prerequisite script `Initialize-OerS71Prereq.ps1`, which live beside the operator's copy of this
file outside the repository ([README.md](README.md), first paragraph). Section 3 signs in as
`oer-live-cc-noperm`, the same certificate's identity with no permission at all, to see the export
fail. Every sign-in is app-only; nothing here signs in as a person.

**Every write is preceded by its `-WhatIf` plan.** The prerequisite script's setup and teardown both
run first with `-WhatIf`; read the plan against the `Expect:` line before running the line that
writes.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s71/` -- the
library writes its transcript, the baseline and both export bundles there, and the folder is
git-ignored. The bundles and the baseline hold real object ids: never copy any of them into a tracked
file. Every block below prints through the library's redactor, so its lines are already redacted per
[README.md](README.md): an object id becomes `00000000-0000-0000-0000-0000000000NN` (the same id the
same placeholder, within this file), the tenant's domain `example.com`, any other address
`personN@example.com`, the organization name `Contoso Test`, the clone `REPO`. The library keeps one
real-to-placeholder map per step, outside the clone and the operator's notes, and deletes it after
the write-up, so the numbering does not restart at `01` here; within this file the rule holds. **No
credential, token, application id or certificate thumbprint is ever printed.** **Never render an
error record** (`Format-List` on `$Error[0]` or on an `-ErrorVariable`): a raw Graph failure's record
carries the bearer token. Every block prints the error id and message only.

## What changed and why this needs a live tenant

The branch closes the last place where a failed read in the export becomes a fact in the apply
document. Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased
onto `main` before it merges.

- **A. An unread resource role binding set is `null`** ("fix: project an unread access package
  binding set as null"). `Get-OERInventory` read an access package's bindings with
  `-ErrorAction SilentlyContinue` and no error capture, so a refused, throttled or failed read was
  written as `"resourceRoles": []` with no `InventoryPartial`. `Sync-OERStructureAccessPackage` reads
  `[]` as declared, so `Invoke-OERStructure -Prune` then removed every binding of the package. The
  read now runs with `-ErrorAction Stop` in a `try`, and a failure is written as an explicit
  `"resourceRoles": null` -- the documented "leave the bindings untouched" signal -- and named in
  `InventoryPartial` as `accessPackages/<package>/resourceRoles`.
- **B. An unread catalog resource set is `null`** ("fix: project an unread catalog resource set as
  null"). The catalog resource read had no error handling at all: its error reached the caller's
  stream, but the document still said `"resources": []`, and the catalog handler prunes against that.
  It is now `"resources": null` and `catalogs/<catalog>/resources` in `InventoryPartial`.
- **C. `schema.json` accepts that `null`** ("fix: accept a null resources or resourceRoles in
  schema.json"). The schema written beside a bundle must accept the document the bundle contains;
  the two keys gain `null` in their type, as `members` and `scopedRoles` did when the export first
  produced a `null` for them.
- **D. Four reads that never prune are now reported** ("fix: report an unread resource-name map in
  the inventory", "fix: report an unread catalog or package list in the inventory", "fix: report an
  unread assignment policy set in the inventory"). The names a package's bindings are written under,
  the catalog list, each catalog's package list and each package's assignment policies are written
  as far as they were read -- no handler removes an absent catalog, package or policy -- but a failed
  read of any of them is now named in `InventoryPartial`. A `-Catalog` id that Graph answers with a
  not-found code is reported as that error, not as unread ("fix: report a by-id 404 on the catalog
  filter as itself"); which code Graph uses for a missing catalog id was not known, and 1.3 measures it.
- **E. A group binding is never written under a stale name** ("fix: write a group binding under its
  object id when the names cannot be read"). When the read that names a package's bindings fails, a
  group's binding used to fall back to the name the catalog recorded when the group was added, which
  Graph keeps after a rename -- and if another group of the catalog now carries that name, the apply
  bound the wrong group and `-Prune` removed the real binding. It is now written under the group's
  object id, which the apply engine resolves to exactly that group.
- **F. `Export-OERInventory`** folds all of it into its one `InventoryPartial` and its
  `IncompleteReads`, as before; its help, its message, the bundle's README and the LLM prompt now
  say that `resources` and `resourceRoles` can be `null` too, and that such a `null` must never be
  turned into `[]`.

A live tenant is needed for what mocks cannot show: that the success path is unchanged against
real Graph answers (section 1), that the unchanged export of a real tenant applied with `-Prune`
plans no removal in `catalogs` and `accessPackages` at all (section 2), and what an export does when
every read is refused (section 3).

## What this file does not check, and why

- **The failure branch itself cannot be provoked selectively here.** No identity can read access
  packages but not their bindings, or catalogs but not their resources: `oer-live-cc` reads all of
  them, and `oer-live-cc-noperm` reads none, so its export fails at the catalog list before any
  binding or resource is read (section 3 records exactly that). The branches of A, B, D and E are
  proven by mocked, mutation-proven unit tests in `tests/Unit/Public/Get-OERInventory.Tests.ps1`
  (Context `an unread access package or catalog collection is never stated as a fact`), and the
  export-to-apply chain by `tests/Unit/Public/Export-OERInventory.Tests.ps1` (Describe
  `Export-OERInventory (an unread collection is never applied as empty)`), where a binding read that
  fails during the export leaves the apply with `-Prune` planning no removal, and the same document
  with `[]` instead does plan one. That is check class B of the sprint: a unit test plus this file's
  measured success path.
- **No write path changed.** The branch changes only what the export writes, so there is no apply
  of a changed document to converge; 2.1 is the convergence check of the export itself.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- with entitlement management, and the two
  configuration files OerLive reads beside it (tenant values live there and nowhere else).
- **OerLive 1.0.2** and `Initialize-OerS71Prereq.ps1` in the same folder; `$VaultDir` below is that
  folder. Every block starts with the same four lines, so each block also runs on its own in a fresh
  window.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, and its no-permission
  twin `oer-live-cc-noperm`. `oer-live-cc` reads and writes entitlement management and groups
  (`EntitlementManagement.ReadWrite.All`, `Group.ReadWrite.All`) and reads the directory; no other
  permission is needed by this file.
- The **built module of this branch** in the clone OerLive loads from (S.1 does it).

**The read-only fence.** 1.1, 2.1 and 3.1 replace the module's Graph transport, in the module's
own scope, with a thin wrapper that lets a GET through, and a POST only to
`v1.0/directoryObjects/getByIds` or `.../getMemberGroups` (two reads that Graph models as a POST),
and refuses everything else with an error naming the method and path. It counts what it saw. The
export and a `-WhatIf` apply make no other request, so the fence changes nothing on the success path,
and should a handler ever write despite `-WhatIf`, the write is refused instead of sent.

### S.1. Point the clone at this branch and build it

- [ ] **S.1** The clone OerLive loads from holds this branch's build.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Write-OerLiveStep "Tracked changes in the clone before the switch: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$null = git -C $Cfg.Repo fetch origin fix/inventory-unread-collection-is-not-empty 2>&1
$null = git -C $Cfg.Repo switch --detach FETCH_HEAD 2>&1
Write-OerLiveStep "Clone at: $(git -C $Cfg.Repo log -1 --format='%h %s')"
Push-Location -LiteralPath $Cfg.Repo
try { ./build.ps1 -Tasks build *> (Join-Path $env:TEMP 'oer-s71-build.log'); $Code = $LASTEXITCODE } finally { Pop-Location }
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Fix = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch "Could not read an access package's resource role bindings" -Quiet)
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
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
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

### 0.2. Identity check as oer-live-cc-noperm, the module session

- [ ] **0.2** The no-permission identity signs in to a module session.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Connect-OerLive -Arm -NoPerm
Disconnect-OerLive
```

**Expect:** the lines for `oer-live-cc-noperm`: app-only with its app id `True`, the app name in the
session is `oer-live-cc-noperm`: `True`, the test tenant `True`, the ARM token from the certificate
`True`, and `identity check passed: True`. It proves its name through the session, since it can read
nothing.
**Failure looks like:** any `False` -- STOP; section 3 needs this session.

Result:

### 0.3. The prerequisite script's plan

- [ ] **0.3** `-WhatIf` plans only `oer-s71-` objects in the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS71Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
$Tenant = @($Targets | Where-Object { $_ -notmatch '^raw\\s71\\' })
Write-OerLiveStep "What-if targets: $($Targets.Count); in the tenant: $($Tenant.Count); every tenant target starts with oer-s71-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s71-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the identity check passes; the sweep reads all six collections and finds no `oer-s71-`
object; the plan names the baseline file under `raw\s71\` and, in the tenant, the group
`oer-s71-res`, the catalog `oer-s71-catalog`, the resource `oer-s71-catalog: resource oer-s71-res`,
the package `oer-s71-ap` and the binding `oer-s71-ap: Member role of oer-s71-res` -- five tenant
targets, every one starting with `oer-s71-`; `WhatIf: nothing was created, removed or written`; exit
code `0`.
**Failure looks like:** a tenant target without the prefix -- STOP; a refusal line -- read it, the
tenant holds something this script did not create; a sweep line `UNREAD` -- STOP (a missing
permission).

Result:

### 0.4. The prerequisite script, for real

- [ ] **0.4** The test objects exist, bound as planned.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS71Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** the baseline written and read back before the first write; `Created group oer-s71-res`,
`Created catalog oer-s71-catalog`, the resource request (201) and the catalog listing the group as
a resource, the Member role listed, `Created access package oer-s71-ap (hidden)`, the binding (201)
and the package listing one binding; the summary with everything `present`; exit code `0`. A
`likely replication delay` line on a fresh object is expected, and is not a failure.
**Failure looks like:** a stop line, or an exit code other than 0: run 0.4 again (the script
completes an earlier run) or tear down; never sign in another way.

Result:

### 1. The export, read as oer-live-cc

### 1.1. The default export: the test package and catalog with their binding and resource

- [ ] **1.1** The export carries `oer-s71-ap` with its binding and `oer-s71-catalog` with its resource, and its partial signal names exactly what it could not read.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S71Seen = [System.Collections.Generic.List[string]]::new()
    $script:S71Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S71Transport) { $script:S71Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S71Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S71Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S71 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S71Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-1.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S71Seen.Count; NotGet = @($script:S71Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S71Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)$(if ($Fence.Refused.Count) { ': ' + ($Fence.Refused -join '; ') })"
Write-OerLiveStep ("Summary: groups {0}, administrative units {1}, catalogs {2}, access packages {3}, access reviews {4}, directory role policies {5}, directory role assignments {6}, role assignments {7}; scopes enumerated {8}, read {9}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.Catalogs, $Bundle.AccessPackages, $Bundle.AccessReviews, $Bundle.DirectoryRoleManagementPolicies, $Bundle.DirectoryRoleAssignments, $Bundle.RoleAssignments, $Bundle.ScopesEnumerated, $Bundle.ScopeCount)
Write-OerLiveStep "SkippedScopes: $(@($Bundle.SkippedScopes).Count) [$(@($Bundle.SkippedScopes) -join '; ')]"
Write-OerLiveStep "SkippedEligibilityScopes: $(@($Bundle.SkippedEligibilityScopes).Count) [$(@($Bundle.SkippedEligibilityScopes) -join '; ')]"
Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count) [$(@($Bundle.IncompleteReads) -join '; ')]"
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($ExpWarn)) { Write-OerLiveStep "Warning: $W" }
$Doc = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Ap = @($Doc.accessPackages | Where-Object { $_.displayName -ceq 'oer-s71-ap' })
$Cat = @($Doc.catalogs | Where-Object { $_.displayName -ceq 'oer-s71-catalog' })
Write-OerLiveStep "oer-s71-ap entries: $($Ap.Count); $(if ($Ap.Count) { ConvertTo-Json -InputObject $Ap[0] -Depth 10 -Compress })"
Write-OerLiveStep "oer-s71-catalog entries: $($Cat.Count); $(if ($Cat.Count) { ConvertTo-Json -InputObject $Cat[0] -Depth 10 -Compress })"
Disconnect-OerLive
```

**Expect:** the fence saw only reads (`not a GET` counts the `getByIds` and `getMemberGroups` posts
only) and refused `0`; `oer-s71-ap entries: 1` with `"catalog":"oer-s71-catalog"`, `"hidden":true`,
`"resourceRoles":[{"resource":"oer-s71-res","role":"Member"}]` and `"assignmentPolicies":[]`;
`oer-s71-catalog entries: 1` with `"resources":[{"type":"Group","name":"oer-s71-res"}]`; no `null`
on either. The partial signal is empty, or names exactly what could not be read, each with its cause:
`oer-live-cc` holds no management-group read, so the Azure walk is expected to name
`<management groups: the listing failed>` in `SkippedScopes` and `SkippedEligibilityScopes`, and
the export to end with one `InventoryPartial,Export-OERInventory` error saying so. Record every
`IncompleteReads` entry, warning and error as it is.
**Failure looks like:** `refused` above 0 -- a read path tried to write: record it, it is a defect;
the package or catalog missing, a `null` or `[]` on either, or a binding or resource other than
`oer-s71-res`'s Member role -- the success path changed; an `IncompleteReads` entry naming an
`oer-s71-` object.

Result:

### 1.2. The bundle's nulls agree with its partial signal, and it validates

- [ ] **1.2** Every `null` collection in `inventory.json` is named in `IncompleteReads`, and the document passes both the module's validator and the bundle's own `schema.json`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Connect-OerLive -Arm
$BundlePath = (Get-ChildItem -LiteralPath (Join-Path $Raw 'export-1.1') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$Json = Get-Content -LiteralPath (Join-Path $BundlePath 'inventory.json') -Raw
$Doc = $Json | ConvertFrom-Json
$Nulls = @(
    foreach ($G in @($Doc.groups)) { if ($G.PSObject.Properties.Name -contains 'members' -and $null -eq $G.members) { "groups/$($G.displayName)/members" } }
    foreach ($A in @($Doc.administrativeUnits)) { foreach ($K in 'members', 'scopedRoles') { if ($A.PSObject.Properties.Name -contains $K -and $null -eq $A.$K) { "administrativeUnits/$($A.displayName)/$K" } } }
    foreach ($C in @($Doc.catalogs)) { if ($C.PSObject.Properties.Name -contains 'resources' -and $null -eq $C.resources) { "catalogs/$($C.displayName)/resources" } }
    foreach ($P in @($Doc.accessPackages)) { if ($P.PSObject.Properties.Name -contains 'resourceRoles' -and $null -eq $P.resourceRoles) { "accessPackages/$($P.displayName)/resourceRoles" } }
)
Write-OerLiveStep "Null collections in inventory.json: $($Nulls.Count)$(if ($Nulls.Count) { ' [' + ($Nulls -join '; ') + ']' })"
$Valid = Test-OERStructure -Path (Join-Path $BundlePath 'inventory.json') -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -WarningVariable TsWarn
Write-OerLiveStep "Test-OERStructure: Valid $($Valid.Valid), findings $(@($Valid.Errors).Count), warnings $(@($TsWarn).Count)"
$Schema = Get-Content -LiteralPath (Join-Path $BundlePath 'schema.json') -Raw
Write-OerLiveStep "Test-Json against the bundle's schema.json: $(Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue)"
Disconnect-OerLive
```

**Expect:** `Null collections in inventory.json` equal to the `members`/`scopedRoles`/`resources`/
`resourceRoles` triples 1.1 printed in `IncompleteReads` that belong to an entry the bundle keeps (a
group the export filters out as not RBAC-relevant is in `IncompleteReads` but not in the document);
none of them an `oer-s71-` object. `Test-OERStructure: Valid True, findings 0`; `Test-Json against
the bundle's schema.json: True`.
**Failure looks like:** a null that 1.1's `IncompleteReads` does not name -- the document holds an
unread collection without the signal; `Valid False`, or `Test-Json` `False` -- the bundle's own schema
rejects its document.

Result:

### 1.3. A catalog id that does not exist: the error Graph gives, reported as itself

- [ ] **1.3** `-Catalog` with an id no catalog has is reported as Graph's not-found error, not as an unread collection.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Connect-OerLive -Arm
$Missing = [guid]::NewGuid().ToString()
$Inv = Get-OERInventory -Include Catalogs -Catalog $Missing -ErrorAction SilentlyContinue -ErrorVariable CatErr -WarningAction SilentlyContinue
$Published = @($CatErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERInventory' })
foreach ($E in $Published) { Write-OerLiveStep "Published by Get-OERInventory: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
Write-OerLiveStep "Catalogs in the document: $(@($Inv.Catalogs).Count); InventoryPartial: $(@($Published | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }).Count)"
Disconnect-OerLive
```

**Expect:** one error published by `Get-OERInventory` whose id starts with one of `ResourceNotFound`,
`Request_ResourceNotFound`, `ItemNotFound` or `NotFound`, the not-found codes the module recognises;
`Catalogs in the document: 0; InventoryPartial: 0`. Record the error id as it is: it is the first
measurement of what Graph answers for a missing catalog id.
**Failure looks like:** `InventoryPartial: 1` naming `catalogs` -- Graph answers a missing catalog id
with a code outside that set, so the id filter's not-found is reported as unread; record the code,
it is the one the set must learn.

Result:

### 2. The unchanged export applied with -Prune -WhatIf

### 2.1. The whole tenant's catalogs and access packages: no removal planned

- [ ] **2.1** Applying 1.1's `inventory.json` to `catalogs` and `accessPackages` with `-Prune -WhatIf` plans no removal anywhere, and the test objects are `Unchanged`.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Connect-OerLive -Arm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S71Seen = [System.Collections.Generic.List[string]]::new()
    $script:S71Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S71Transport) { $script:S71Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S71Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S71Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S71 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S71Transport @PSBoundParameters
    }
}
$BundlePath = (Get-ChildItem -LiteralPath (Join-Path $Raw 'export-1.1') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$Doc = Get-Content -LiteralPath (Join-Path $BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Doc21 = [ordered]@{ version = $Doc.version; catalogs = @($Doc.catalogs); accessPackages = @($Doc.accessPackages) }
$Path21 = Join-Path $Raw 'apply-2.1.json'
[System.IO.File]::WriteAllText($Path21, (ConvertTo-Json -InputObject $Doc21 -Depth 30), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "Document: catalogs $(@($Doc21.catalogs).Count), access packages $(@($Doc21.accessPackages).Count)"
$Rows = @(Invoke-OERStructure -Path $Path21 -Include Catalogs, AccessPackages -Prune -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ApErr -WarningAction SilentlyContinue -WarningVariable ApWarn 6>$null)
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S71Seen.Count; NotGet = @($script:S71Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S71Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)$(if ($Fence.Refused.Count) { ': ' + ($Fence.Refused -join '; ') })"
foreach ($G in @($Rows | Group-Object Section, Action | Sort-Object Name)) { Write-OerLiveStep "Rows: $($G.Name) = $($G.Count)" }
$Remove = @($Rows | Where-Object { $_.Section -in 'catalogs', 'accessPackages' -and ([string]$_.Detail -match 'would remove|^removed' -or $_.Action -eq 'Removed') })
$WarnRemove = @($ApWarn | Where-Object { "$_" -match 'would remove|removing' })
Write-OerLiveStep "Rows that would remove: $($Remove.Count); warnings that would remove: $($WarnRemove.Count)"
foreach ($R in @($Rows | Where-Object { $_.Item -like 'oer-s71-*' })) { Write-OerLiveStep "Test object: [$($R.Section)] $($R.Item) | $($R.Action) | $($R.Detail)" }
foreach ($R in @($Rows | Where-Object { $_.Action -notin 'Unchanged' -and $_.Item -notlike 'oer-s71-*' })) { Write-OerLiveStep "Other row: [$($R.Section)] $($R.Action) | $($R.Detail)" }
foreach ($E in @($ApErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($ApWarn)) { Write-OerLiveStep "Warning: $W" }
Disconnect-OerLive
```

**Expect:** the fence refused `0`; `Rows that would remove: 0; warnings that would remove: 0`; the
test objects `[catalogs] oer-s71-catalog | Unchanged` and `[accessPackages] oer-s71-ap | Unchanged`
(one row each, or one per reconciled part, all `Unchanged`); the count of rows per section and
action recorded. Rows for other catalogs and packages are printed only when not `Unchanged`; record
them as they are.
**Failure looks like:** a row or warning that would remove anything -- the unchanged export does not
round-trip on this tenant: record it with its section and detail, it is the defect class this branch
is about; a test-object row that is not `Unchanged`; the fence refusing a request -- an apply path
wrote under `-WhatIf`.

Result:

### 2.2. The test objects are as they were

- [ ] **2.2** After 2.1 the package still binds one role and the catalog still holds one resource.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Connect-OerLive -Graph
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Found = @(Find-OerLivePrefixed -Quiet)
$Ap = @($Found | Where-Object { $_.Kind -eq 'access package' -and $_.Name -ceq 'oer-s71-ap' })
$Cat = @($Found | Where-Object { $_.Kind -eq 'catalog' -and $_.Name -ceq 'oer-s71-catalog' })
$B = Invoke-OerLiveGraph -All -Uri "$Em/accessPackages/$($Ap[0].Id)/resourceRoleScopes?`$expand=role,scope"
$R = Invoke-OerLiveGraph -All -Uri "$Em/catalogs/$($Cat[0].Id)/resources"
Write-OerLiveStep "oer-s71-ap bindings: $(@($B.Body['value']).Count) ($(@($B.Body['value']) | ForEach-Object { [string]$_['role']['displayName'] }))"
Write-OerLiveStep "oer-s71-catalog resources: $(@($R.Body['value']).Count) ($(@($R.Body['value']) | ForEach-Object { [string]$_['displayName'] }))"
Disconnect-OerLive
```

**Expect:** `oer-s71-ap bindings: 1 (Member)`; `oer-s71-catalog resources: 1 (oer-s71-res)`.
**Failure looks like:** 0 of either -- something removed it; record what 2.1 printed.

Result:

### 3. The export, read as oer-live-cc-noperm

### 3.1. Every read refused: the outcome as it is, and no `[]` from a failed read

- [ ] **3.1** The no-permission export reports what it could not read, and its document, if written, states no failed read as an empty collection.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
Connect-OerLive -Arm -NoPerm
& (Get-Module Omnicit.EntraRBAC) {
    $script:S71Seen = [System.Collections.Generic.List[string]]::new()
    $script:S71Refused = [System.Collections.Generic.List[string]]::new()
    if (-not $script:S71Transport) { $script:S71Transport = ${function:Invoke-OERGraphRequest} }
    function script:Invoke-OERGraphRequest {
        [CmdletBinding()]
        param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode)
        $Path = ($Uri -replace '^https://[^/]+/', '') -replace '\?.*$', ''
        $script:S71Seen.Add("$($Method.ToUpperInvariant()) $Path")
        if ($Method -ne 'GET' -and $Path -notmatch '^v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)$') {
            $script:S71Refused.Add("$($Method.ToUpperInvariant()) $Path")
            throw "S71 read-only fence: refused $($Method.ToUpperInvariant()) $Path"
        }
        & $script:S71Transport @PSBoundParameters
    }
}
$Out = Join-Path $Raw 'export-3.1'
$null = New-Item -ItemType Directory -Force -Path $Out
$Bundle = Export-OERInventory -OutputPath $Out -ErrorAction SilentlyContinue -ErrorVariable ExpErr -WarningAction SilentlyContinue -WarningVariable ExpWarn
$Fence = & (Get-Module Omnicit.EntraRBAC) { [PSCustomObject]@{ Seen = $script:S71Seen.Count; NotGet = @($script:S71Seen | Where-Object { $_ -notlike 'GET *' }).Count; Refused = @($script:S71Refused) } }
Write-OerLiveStep "Fence: requests $($Fence.Seen), not a GET $($Fence.NotGet), refused $($Fence.Refused.Count)"
if ($Bundle) {
    Write-OerLiveStep ("Summary: groups {0}, administrative units {1}, catalogs {2}, access packages {3}, access reviews {4}, directory role policies {5}, directory role assignments {6}, role assignments {7}" -f $Bundle.Groups, $Bundle.AdministrativeUnits, $Bundle.Catalogs, $Bundle.AccessPackages, $Bundle.AccessReviews, $Bundle.DirectoryRoleManagementPolicies, $Bundle.DirectoryRoleAssignments, $Bundle.RoleAssignments)
    Write-OerLiveStep "IncompleteReads: $(@($Bundle.IncompleteReads).Count) [$(@($Bundle.IncompleteReads) -join '; ')]"
    Write-OerLiveStep "SkippedScopes: $(@($Bundle.SkippedScopes).Count) [$(@($Bundle.SkippedScopes) -join '; ')]"
    $Json = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw
    $Doc = $Json | ConvertFrom-Json
    $Empty = @(
        foreach ($C in @($Doc.catalogs)) { if ($null -ne $C.resources -and @($C.resources).Count -eq 0) { "catalogs/$($C.displayName)/resources" } }
        foreach ($P in @($Doc.accessPackages)) { if ($null -ne $P.resourceRoles -and @($P.resourceRoles).Count -eq 0) { "accessPackages/$($P.displayName)/resourceRoles" } }
    )
    Write-OerLiveStep "Empty resources or resourceRoles in inventory.json: $($Empty.Count)$(if ($Empty.Count) { ' [' + ($Empty -join '; ') + ']' })"
} else { Write-OerLiveStep 'No bundle was written.' }
foreach ($E in @($ExpErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { Write-OerLiveStep "Error: $($E.FullyQualifiedErrorId) -- $($E.Exception.Message)" }
foreach ($W in @($ExpWarn)) { Write-OerLiveStep "Warning: $W" }
Disconnect-OerLive
```

**Expect:** the outcome as it is, recorded whole. What the code predicts: section warnings for the
groups, administrative units and access reviews (each a 403); the catalog list refused, so
`IncompleteReads` names `catalogs, accessPackages` (fix D) and both sections are empty; the
directory role sections unread; the Azure walk skipped; one `InventoryPartial,Export-OERInventory`
error at the end; and `Empty resources or resourceRoles in inventory.json: 0`. A 403 here is the
expected answer, not a stop: this identity holds no permission.
**Failure looks like:** an empty `resources` or `resourceRoles` in the document -- a failed read
stated as a fact; a catalog list refusal that `IncompleteReads` does not name; the fence refusing a
request.

Result:

## Teardown

### T.1. The teardown's plan

- [ ] **T.1** `-Teardown -WhatIf` plans the removal of only `oer-s71-` objects.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS71Prereq.ps1') -Teardown -WhatIf 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Targets = @($Out | ForEach-Object { if ($_ -match '^What if: Performing the operation ".*" on target "(.*)"\.$') { $Matches[1] } })
Write-OerLiveStep "What-if targets: $($Targets.Count); every target starts with oer-s71-: $(@($Targets | Where-Object { -not $_.StartsWith('oer-s71-') }).Count -eq 0); exit code: $Code"
```

**Expect:** the teardown of `oer-s71-`: users 0, groups 1, access packages 1, catalogs 1; targets in
the library's order -- the binding of `oer-s71-ap`, the package, the catalog's resource
`oer-s71-res`, the catalog, the group -- every one starting with `oer-s71-`; `removed 0, residue 0,
unreadable 0 (WhatIf: nothing was removed)`; exit code `0`.
**Failure looks like:** a target without the prefix -- STOP.

Result:

### T.2. The teardown

- [ ] **T.2** Every `oer-s71-` object is removed, and the tenant's counts are back at the baseline.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS71Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
Write-OerLiveRaw -InputObject ($Out -join "`n")
Write-OerLiveStep "Exit code: $Code"
```

**Expect:** each removal answered (a binding `Removed`, the package and the catalog `Deleted` after a
few attempts while the catalog lets go of its resource, the resource `Removed`, the group `Deleted`);
`removed 5, residue 0, unreadable 0`; the sweep `no user, group, administrative unit, catalog,
access package or app registration starting with 'oer-s71-' is left`; both counts equal the
baseline; exit code `0`.
**Failure looks like:** exit code `3` -- residue: read the `RESIDUE` lines and run T.2 again later
(the script retries residue first); exit code `1` -- a stop line, read it.

Result:

### T.3. Read back, and clean up

- [ ] **T.3** Nothing with the prefix is left, no residue, and the raw folder and the redaction map are deleted.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s71-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s71'
$Out = @(pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS71Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
Write-OerLiveRaw -InputObject ($Out -join "`n")
$Clean = [bool]($Out -match 'prefixed objects left: 0; unread collections: 0; residue rows: 0')
Write-OerLiveStep "Read-back clean: $Clean"
if ($Clean) {
    Clear-OerLiveRedactionMap -Confirm:$false
    if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
    Write-OerLiveStep "raw\s71 removed: $(-not (Test-Path -LiteralPath $Raw)); redaction map removed: True"
}
```

**Expect:** `prefixed objects left: 0; unread collections: 0; residue rows: 0`; both counts equal the
baseline; `Read-back clean: True`; `raw\s71 removed: True`.
**Failure looks like:** anything left -- leave `raw\s71` and the map in place and record what is
left; never delete residue by hand.

Result:
