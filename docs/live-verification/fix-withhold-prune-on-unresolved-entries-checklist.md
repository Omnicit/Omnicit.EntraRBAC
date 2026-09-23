# Live verification checklist -- withheld prune on unresolved entries, and the omitted-collection warning (fix/withhold-prune-on-unresolved-entries)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

**`-Prune` is destructive, and this file runs it for real.** Every apply below goes through the
`Invoke-S61Check` helper defined in Setup, which runs `Invoke-OERStructure -WhatIf` unless `-Apply`
is passed. The rule for every check is the same: run the `-Prune -WhatIf` plan first, read it
against the `Expect:` line, and only then run the `-Apply` line -- and only where the check has
one. Every object any document names was created by the prerequisite script for this file and
carries the prefix `oer-s61`; nothing else in the tenant is named in a document, and nothing else
is written.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s61/` --
the helper writes every document and a results log there, and the folder is git-ignored. What goes
into a `Result:` below is redacted first, per [README.md](README.md): object ids become
`00000000-0000-0000-0000-0000000000NN` in first-appearance order for THIS file (the same id always
gets the same placeholder -- several checks turn on two ids being the same), every user principal
name on the test domain becomes a `personN@example.com` address, and no credential and no bearer
token is ever pasted. The test objects' display names may stay.

## What changed and why this needs a live tenant

Three changes, all on this branch. Commits are named by SUBJECT, never by hash: the hashes change
when the branch is rebased onto `main` before it merges.

- **A. A declared entry that cannot be resolved now withholds the prune of its collection**
  ("fix: withhold prune when a declared entry cannot be resolved"; tests in "test: keep the
  sibling-resolution tests protective under the withheld rule"; help in "docs: describe the
  withheld prune in the apply handlers' help" and "docs: state what the engine keeps when an apply
  handler throws"). Every apply-engine prune pass builds a set of DECLARED keys and treats a live entry whose key is not in the set as undeclared: reported `Extra`,
  or removed under `-Prune`. A declared entry whose lookup gave nothing used to be skipped with
  `continue` -- and in `roleAssignments` a thrown sibling lookup was swallowed -- so it never
  entered the set, and its OWN live counterpart looked undeclared. `-Prune` then deleted exactly the
  object the document asked to keep: a failed lookup read as an empty fact in a deleting path. Now
  the private `ConvertTo-OERPruneWithheldResult` owns one rule: while any declared entry of a
  collection is unresolved, every live candidate in that collection is reported `Skipped`, with or
  without `-Prune`, with a Detail that starts
  `prune withheld: declared entry '<entry>' could not be resolved` (plural
  `prune withheld: declared entries '<a>', '<b>' could not be resolved` when several), and the full
  single-entry text is
  `prune withheld: declared entry '<entry>' could not be resolved, so <candidate> may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.`
  The unresolved entry keeps its own `Failed` row. No warning and no `ShouldProcess` prompt is
  issued for a withheld candidate. The collections: `roleAssignments` (every declared entry sharing
  the scope string; the entry label is `<role> -> <principal> @ <scope>`), group `members`, `owners`
  and `eligibility` (each per collection; the label is the declared reference), administrative-unit
  `members` and `scopedRoles`, and access-package `resourceRoles` (the label is the declared
  resource name). `roleAssignments` prunes only in the invocation for the FIRST item of each scope;
  if that item itself fails to resolve, the handler returns before the pass -- nothing is pruned
  and no `Skipped` row appears at all.
- **B. An omitted collection key that still prunes is now warned about** ("fix: warn when an
  omitted collection key would prune"). Five collections are reconciled even when their key is
  OMITTED, against an empty declared set, so `-Prune` removes every live entry in them:
  `groups[].members`, `administrativeUnits[].members`, `administrativeUnits[].scopedRoles`,
  `catalogs[].resources` and `accessPackages[].resourceRoles`. `Test-OERStructure` now reports each
  such omission as a Warning finding, and `Invoke-OERStructure -Prune` (under `-WhatIf` too) writes
  ONE warning listing them before anything is written. An explicit `null`, a declared array, and
  the `members` of a group or unit declared `"dynamic": true` are not reported. The private
  `Get-OEROmittedPruneCollection` owns which keys those are. **Its known limit** ("fix: state the
  dynamic limit of the omitted-collection warning"): the `members` exclusion trusts the DECLARED
  dynamic flag (compared with `-eq $true`). A document that declares `"dynamic": true` for a group
  that is static in the tenant -- `Set-OERGroup` cannot convert it -- or for an administrative unit
  whose conversion to dynamic is not applied in this run, still has its omitted `members` pruned,
  and neither the Warning finding nor the `-Prune` warning lists them. This file does not provoke
  that case (see "What this file does not check").
- **C. `Get-OERRequiredScope -Cmdlet Set-OERGroup` now lists `RoleManagement.ReadWrite.Directory`**
  ("fix: list the role-management scope for updating a role-assignable group"; needed for a
  role-assignable group). "fix: mark the Set-OERGroup scope entry as not confirmed by the API
  table" then set that entry's `Verified` to `False` with a `Note`: the Update group permission
  table does not list the permission, and it is stated only in the role-assignable group guidance.

The branch also carries "docs: name the withheld and omitted-key rules in the public help", which
changes help text only.

**Every unit test on this branch mocks the transport and the resolvers.** They prove the decision
given a lookup that returns `$null`. They cannot prove the four things this file is for:

1. That a real unresolvable reference -- a user's DISPLAY name where the engine resolves a group
   name or a user principal name, a service principal named without `principalType`, a misspelt
   catalog resource -- comes back from the REAL resolvers as "nothing" (the withheld path), and not
   as a throw (the abort path) or, worse, as some other object.
2. That the withheld rows carry the real live candidates' ids and that a real
   `-Prune -Confirm:$false` leaves every one of them in place.
3. That the guard stays out of the way when every entry resolves: section 6's controls show a
   genuine extra is still removed, so the fix did not turn `-Prune` into a no-op.
4. That the omitted-collection warning arrives once, FIRST, in a real run's warning stream, ahead
   of the handlers' own warnings, with the real item names in it.

## What this file does not check, and why

- **A lookup that THROWS** rather than giving nothing. It aborts the item ("handler error" in the
  engine's `Failed` row) before that collection's prune pass, and in `roleAssignments` a throwing
  sibling is recorded as unresolved. Both are pinned by the handler unit suites (the abort tests in
  the Group, AdministrativeUnit and AccessPackage suites, and the sibling-throws test in the
  RoleAssignment suite). Provoking a throw live needs a transport fault on demand, which no safe
  test object gives.
- **Group `owners` and administrative-unit `scopedRoles`.** They use the same helper through the
  same two-line call as `members`, and each has its own unit test. Exercising them live means
  changing the owners of a group or granting a directory role scoped to the unit -- a privileged
  grant this file has no other reason to make.
- **The permanent-eligibility loop.** It feeds the same unresolved list as the time-bound loop
  (unit-pinned); a permanent eligibility live would mean opening the group's PIM policy for
  permanent eligibility first, which is a policy change.
- **`catalogs[].resources`.** That pass has no lookup at all -- the declared key is the literal
  resource name or URL -- so the withheld rule is vacuous there and there is nothing to verify.
  (Its OMITTED key is still warned about; check 7.3 covers that.)
- **Access-package `assignmentPolicies`.** Not touched by this branch. When the key is declared,
  an undeclared live policy is only ever reported `Extra`, never removed; when it is omitted, as in
  every document below, the step does not run and no policy row appears at all.
- **The `-Include` filter and the template-group label in the omitted-collection warning**, beyond
  the one narrowing shown in 7.3. Unit-pinned.
- **The warning's dynamic limit.** A document declaring `"dynamic": true` for a group that is live
  static prunes its omitted `members` without listing them. Showing that live would mean running an
  unlisted `-Prune` against a real group's members. The limit is stated in the help of
  `Get-OEROmittedPruneCollection`, `Test-OERStructure` and `Invoke-OERStructure`; the unit tests pin
  only its offline half -- the helper never sees live state, so a declared-dynamic group's members
  are not listed, and a merely truthy flag such as the string `"false"` does not count as dynamic.
  7.5 checks the half that is safe to run: a declared-dynamic group is not listed.

---

## Setup, once

**You need:**

- A **test tenant** -- never a customer tenant -- with Microsoft Entra ID P2 or ID Governance
  licensing (PIM for Groups and entitlement management), a Tenant Profile alias for it
  (`Get-OERConfiguration`) whose profile names the commercial cloud, one verified domain, and one
  **test subscription**.
- One admin account in that tenant that can create users, groups, app registrations and
  administrative units, grant PIM-for-Groups eligibility, manage entitlement-management catalogs,
  and create resource groups and role assignments in the subscription. Global Administrator plus
  Owner on the test subscription covers all of it.
- The prerequisite script `Initialize-OerS61Prereq.ps1`. It is kept OUTSIDE this repository and is
  never committed; it is run by hand, by the operator, and never by Claude or CI.
- PowerShell 7 and a clone of this repository on this branch.

**Variables, build and module path.** Paste into one PowerShell 7 window and keep that window for
the whole file.

```powershell
$Repo    = '<your-clone-of-Omnicit.EntraRBAC>'   # the clone whose origin is github.com/Omnicit/Omnicit.EntraRBAC
$Prereq  = '<path-to-Initialize-OerS61Prereq.ps1>'
$Alias   = '<your-test-tenant-alias>'
$OrgName = '<your-test-tenant-display-name>'   # the organization display name, exactly as Graph reports it
$SubId   = '<your-test-subscription-id>'
$Domain  = '<your-verified-domain>'
$Prefix  = 'oer-s61'
$UserA   = "$Prefix-user-a@$Domain"
$UserB   = "$Prefix-user-b@$Domain"
$UserC   = "$Prefix-user-c@$Domain"
$NameB   = 'OER S61 User B'   # user B's DISPLAY name -- the reference the engine cannot resolve
$NameC   = 'OER S61 User C'   # user C's DISPLAY name, used only by check 3.4
$RgScope = "/subscriptions/$SubId/resourceGroups/$Prefix-rg"
$Raw     = Join-Path $Repo 'docs/live-verification/raw/s61'

Set-Location $Repo
git remote get-url origin
git branch --show-current
./build.ps1 -Tasks build
$Sep = [System.IO.Path]::PathSeparator
$env:PSModulePath = (Resolve-Path ./output/module).Path + $Sep + (Resolve-Path ./output/RequiredModules).Path + $Sep + $env:PSModulePath
$ModulePsd1 = (Get-ChildItem ./output/module/Omnicit.EntraRBAC/*/Omnicit.EntraRBAC.psd1 |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
New-Item -ItemType Directory -Path $Raw -Force | Out-Null
```

**Create the test objects.** The script runs in its own process, so this window keeps its own
sign-in. It signs in twice (Microsoft Graph for Phase 1, `Connect-OER` for Phase 2). Before its
first write it identifies the tenant positively: it reads the signed-in organization and refuses to
go on -- nothing written -- unless the organization's display name equals
`-ExpectedTenantDisplayName` EXACTLY, `-UserDomain` is one of its verified domains, and the Tenant
Profile's tenant id (or domain) names the same organization. Only then does it ask once for
confirmation, naming the organization display name, the tenant id and the subscription; the
`Connect-OER` sign-in must land in that same organization too. It ends with a summary of names and
REAL object ids -- redact those before pasting (check 0.2). It is idempotent: a second run creates
nothing that exists and only fills in what is missing. The `-WhatIf` line is optional (it still
signs in and identifies the tenant, and asks nothing).

```powershell
pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -WhatIf
pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1
```

What it creates, all named with the prefix: three DISABLED users `oer-s61-user-a/-b/-c` on your
domain (display names `OER S61 User A/B/C`, random passwords never printed); the app registration
and service principal `oer-s61-app`; the security groups `oer-s61-members` (members A, B, C),
`oer-s61-pim` (no members; a 30-day PIM-for-Groups member eligibility for A, B and C -- the first
one onboards the group), `oer-s61-ra` (no members), `oer-s61-ap-res1` and `oer-s61-ap-res2`; the
administrative unit `oer-s61-au` (members A, B, C); the catalog `oer-s61-catalog` holding both
resource groups, and the access package `oer-s61-ap` in it with the `Member` role of both bound (no
assignment policy); the resource group `oer-s61-rg` with Reader defined at it for `oer-s61-ra`, the
service principal `oer-s61-app` and user C. It refuses to run if a GROUP named `oer-s61-app`,
`OER S61 User B` or `OER S61 User C` exists, since the checks below rely on those names resolving to
nothing (user C's display name in check 3.4).

**Sign in, and define the helpers.**

```powershell
Import-Module Omnicit.EntraRBAC -Force
$ErrorActionPreference = 'Continue'   # module code reads the GLOBAL preference; Stop would end a run at its first Failed row
Connect-OER -TenantAlias $Alias -IncludeARM

function Invoke-S61Check {
    # Writes the document to the raw folder, validates it offline, then runs Invoke-OERStructure on
    # it -- under -WhatIf unless -Apply is given. Warnings are merged into the output stream (3>&1),
    # which keeps their order; the engine emits its result records last, after every warning.
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string[]]$Include,
        [switch]$Prune,
        [switch]$Apply,
        [switch]$ValidateOnly
    )
    $Path = Join-Path $Raw "$Id.json"
    Set-Content -Path $Path -Value $Json -Encoding utf8NoBOM
    Write-Host "=== $Id -- $Path"
    Get-Content -Path $Path | ForEach-Object { Write-Host "    $_" }

    $global:S61Validation = Test-OERStructure -Path $Path
    Write-Host "--- offline validation: Valid = $($S61Validation.Valid), findings = $(@($S61Validation.Errors).Count)"
    $S61Validation.Errors | Format-List Section, Item, Path, Severity, Message | Out-Host
    if ($ValidateOnly -or -not $S61Validation.Valid) { return }

    $Splat = @{ Path = $Path; Include = $Include; ErrorAction = 'Continue'; ErrorVariable = 'CheckError' }
    if ($Prune) { $Splat.Prune = $true }
    if ($Apply) { $Splat.Confirm = $false } else { $Splat.WhatIf = $true }
    Write-Host ('--- Invoke-OERStructure -Include {0}{1}{2}' -f ($Include -join ','),
        $(if ($Prune) { ' -Prune' } else { '' }), $(if ($Apply) { ' -Confirm:$false' } else { ' -WhatIf' }))

    $global:S61Out     = @(Invoke-OERStructure @Splat 3>&1)
    $global:S61Warning = @($S61Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $global:S61Result  = @($S61Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    $global:S61Error   = @($CheckError)

    Write-Host "--- first item of the merged output stream: $(if ($S61Out.Count) { $S61Out[0].GetType().Name } else { '(nothing)' })"
    Write-Host "--- warnings, in the order written: $($S61Warning.Count)"
    $S61Warning | ForEach-Object { Write-Host "    WARNING: $($_.Message)" }
    Write-Host "--- errors: $($S61Error.Count)"
    $S61Error | ForEach-Object { Write-Host "    ERROR [$($_.FullyQualifiedErrorId)]: $($_.Exception.Message)" }
    Write-Host "--- results: $($S61Result.Count)"
    $S61Result | Format-List Section, Item, Action, Detail | Out-Host
    Write-Host "--- action counts: $(($S61Result | Group-Object Action -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')"
    $S61Result | Select-Object @{ Name = 'CheckId'; Expression = { $Id } }, Section, Item, Action, Detail |
        Export-Csv -Path (Join-Path $Raw 'all-results.csv') -Append -NoTypeInformation
}

function Get-S61WithheldId {
    # The live candidate id named in each withheld row of the last run, sorted. For a resource-role
    # binding the key is 'Member|<origin id>'; the role prefix is stripped.
    @($S61Result | Where-Object { $_.Action -eq 'Skipped' -and $_.Detail -like 'prune withheld: *' } | ForEach-Object {
            if ($_.Detail -match "'([^']+)' may be ") { $Matches[1] -replace '^Member\|', '' }
        }) | Sort-Object
}
```

**The documents.** Paste this block as it stands -- every here-string must close at column 0.
Each check below shows its document as JSON, with the placeholders written out.

```powershell
$Docs = @{}

$Docs.RaWithheld = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "roleAssignments": [
    { "scope": "$RgScope", "role": "Reader", "principal": "$Prefix-ra", "principalType": "Group" },
    { "scope": "$RgScope", "role": "Reader", "principal": "$Prefix-app" }
  ]
}
"@

$Docs.RaWithheldFirst = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "roleAssignments": [
    { "scope": "$RgScope", "role": "Reader", "principal": "$Prefix-app" },
    { "scope": "$RgScope", "role": "Reader", "principal": "$Prefix-ra", "principalType": "Group" }
  ]
}
"@

$Docs.PimWithheld = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [
    {
      "displayName": "$Prefix-pim",
      "members": null,
      "eligibility": [
        { "principal": "$UserA", "durationDays": 30 },
        { "principal": "$NameB", "durationDays": 30 }
      ]
    }
  ]
}
"@

$Docs.MembersWithheld = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [ { "displayName": "$Prefix-members", "members": [ "$UserA", "$NameB" ] } ]
}
"@

$Docs.MembersWithheldTwo = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [ { "displayName": "$Prefix-members", "members": [ "$UserA", "$NameB", "$NameC" ] } ]
}
"@

$Docs.AuWithheld = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "administrativeUnits": [ { "displayName": "$Prefix-au", "members": [ "$UserA", "$NameB" ], "scopedRoles": null } ]
}
"@

$Docs.ApWithheld = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "accessPackages": [
    {
      "displayName": "$Prefix-ap",
      "catalog": "$Prefix-catalog",
      "resourceRoles": [
        { "resource": "$Prefix-ap-res1", "role": "Member" },
        { "resource": "$Prefix-ap-res2-typo", "role": "Member" }
      ]
    }
  ]
}
"@

$Docs.RaControl = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "roleAssignments": [
    { "scope": "$RgScope", "role": "Reader", "principal": "$Prefix-ra", "principalType": "Group" },
    { "scope": "$RgScope", "role": "Reader", "principal": "$Prefix-app", "principalType": "ServicePrincipal" }
  ]
}
"@

$Docs.PimControl = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [
    {
      "displayName": "$Prefix-pim",
      "members": null,
      "eligibility": [
        { "principal": "$UserA", "durationDays": 30 },
        { "principal": "$UserB", "durationDays": 30 }
      ]
    }
  ]
}
"@

$Docs.MembersControl = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [ { "displayName": "$Prefix-members", "members": [ "$UserA", "$UserB" ] } ]
}
"@

$Docs.AuControl = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "administrativeUnits": [ { "displayName": "$Prefix-au", "members": [ "$UserA", "$UserB" ], "scopedRoles": null } ]
}
"@

$Docs.ApControl = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "accessPackages": [
    {
      "displayName": "$Prefix-ap",
      "catalog": "$Prefix-catalog",
      "resourceRoles": [ { "resource": "$Prefix-ap-res1", "role": "Member" } ]
    }
  ]
}
"@

$Docs.MembersOmitted = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [ { "displayName": "$Prefix-members" } ]
}
"@

$Docs.FiveOmitted = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [ { "displayName": "$Prefix-members" } ],
  "administrativeUnits": [ { "displayName": "$Prefix-au" } ],
  "catalogs": [ { "displayName": "$Prefix-catalog" } ],
  "accessPackages": [ { "displayName": "$Prefix-ap", "catalog": "$Prefix-catalog" } ]
}
"@

$Docs.MembersNull = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [ { "displayName": "$Prefix-members", "members": null } ]
}
"@

$Docs.DynamicAbsent = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [ { "displayName": "$Prefix-dyn-absent", "dynamic": true, "membershipRule": "(user.department -eq \"$Prefix-dyn-none\")" } ]
}
"@
```

In the `Expect:` lines below, `<RgScope>` is `/subscriptions/<your-test-subscription-id>/resourceGroups/oer-s61-rg`,
`<UserA>` is `oer-s61-user-a@<your-verified-domain>` (likewise B and C), `<IdA>`, `<IdB>`, `<IdC>`,
`<IdSp>`, `<IdRes1>`, `<IdRes2>` are the object ids 0.3 records, `<ReaderId>` is the full Reader role
definition id 0.3 records, and `<reader-guid>` is its last segment.

**Run order.** Section 0 first. Sections 1-5 in any order after it. Section 6 only after 1-5, since
it removes the very entries 1-5 prove are kept, and 6.6 straight after 6.1-6.5. Sections 7 and 8 at
any time after section 0. Teardown last. If a check removes something it should not have, re-run
the prerequisite script (it restores exactly what is missing), record that you did, and carry on.

---

### 0. Preparation and baseline capture

- [ ] **0.1 The session runs THIS branch's build.**

  ```powershell
  git -C $Repo fetch origin
  git -C $Repo log --format=%s origin/main..HEAD
  $M = Get-Module Omnicit.EntraRBAC
  '{0} {1} from {2}' -f $M.Name, $M.Version, $M.ModuleBase
  & $M { Get-Command ConvertTo-OERPruneWithheldResult, Get-OEROmittedPruneCollection } | Format-Table Name, CommandType -AutoSize
  $Probe = Test-OERStructure -Json '{"version":"1.0","groups":[{"displayName":"probe"}]}'
  $Probe.Valid
  $Probe.Errors | Format-List Section, Item, Path, Severity, Message
  ```

  **Expect:** before the merge, the log lists at least these subjects (record any later one too):
  "fix: withhold prune when a declared entry cannot be resolved", "test: keep the
  sibling-resolution tests protective under the withheld rule", "docs: describe the withheld prune
  in the apply handlers' help", "docs: state what the engine keeps when an apply handler throws",
  "fix: warn when an omitted collection key would prune", "fix: list the role-management scope for
  updating a role-assignable group", "fix: mark the Set-OERGroup scope entry as not confirmed by
  the API table", "fix: state the dynamic limit of the omitted-collection warning", "docs: name
  the withheld and omitted-key rules in the public help", "docs: release notes for the withheld
  prune and the omitted-key warning" and "docs: live-verification checklist for the withheld
  prune". Subjects, not hashes: a rebase onto
  `main` rewrites every hash. After the merge the range is empty -- the squash merge folds the
  branch into one commit on `main`, and these subjects appear in that commit's body instead (read
  it with `git log -1 --format=%b <squash commit>`). `ModuleBase` lies under
  `<your-clone>/output/module/Omnicit.EntraRBAC/`; both private functions are listed as `Function`;
  `$Probe.Valid` is `True` with exactly one finding -- Path `groups[0].members`, Severity `Warning`,
  Message beginning `'members' is omitted at groups[0]. An omitted members key is still reconciled`.
  **Failure looks like:** `CommandNotFound` for either function, or `$Probe` with no finding -- a
  build without this branch's change is loaded. Rebuild, fix `PSModulePath`, re-import; nothing
  below means anything until this passes.
  **Result:**

- [ ] **0.2 The prerequisite script ran and every test object exists.** Paste its summary table,
  redacted.

  **Expect:** before any write the run printed
  `Identified the test tenant: organization '<your-test-tenant-display-name>', tenant id <id>, verified domain <your-verified-domain>.`,
  asked once with a question naming that organization, its tenant id and the subscription, and
  later printed `Phase 2 (Connect-OER) is signed in to the confirmed test tenant ...`. The run ends
  with `Done.` and no error; the summary has one row each for the three
  users, the app registration (object id and appId), the service principal, the five groups, the
  administrative unit, the catalog, the access package and the resource group, plus three
  `PIM eligibility (member, ...)` rows (A, B, C on `oer-s61-pim`), two `resource role binding` rows
  (`Member` of `oer-s61-ap-res1` and of `oer-s61-ap-res2`) and three `role assignment` rows
  (`Reader -> oer-s61-ra`, `Reader -> oer-s61-app`, `Reader -> OER S61 User C`). No row reads
  `(none -- not created)`.
  **Failure looks like:** a `(none -- not created)` row, or the script stopped on an error -- fix
  the cause and re-run the script before 0.3. A `Refusing to run: ...` line from the tenant
  identification means nothing was written: check `$OrgName` (exact, case-sensitive), `$Domain`
  and the Tenant Profile before trying again -- never weaken the check.
  **Result:**

- [ ] **0.3 Record the starting state of every test object, before the first write.** This is the
  baseline every read-back below is compared against.

  ```powershell
  $Members0 = @(Get-OERGroupMember -Group "$Prefix-members" -ErrorAction Stop)
  $Members0 | Sort-Object UserPrincipalName | Format-Table PrincipalId, UserPrincipalName, DisplayName -AutoSize
  $IdA = ($Members0 | Where-Object UserPrincipalName -eq $UserA).PrincipalId
  $IdB = ($Members0 | Where-Object UserPrincipalName -eq $UserB).PrincipalId
  $IdC = ($Members0 | Where-Object UserPrincipalName -eq $UserC).PrincipalId

  $Elig0 = @(Get-OERGroupEligibility -Group "$Prefix-pim" -ErrorAction Stop)
  $Elig0 | Sort-Object PrincipalId | Format-Table PrincipalId, AccessType, StartDateTime, EndDateTime, ScheduleInstanceId,
      @{ Name = 'Days'; Expression = { [math]::Round(([datetimeoffset]$_.EndDateTime - [datetimeoffset]$_.StartDateTime).TotalDays) } } -AutoSize
  @(Get-OERGroupMember -Group "$Prefix-pim" -ErrorAction Stop).Count

  $Au0 = Get-OERAdministrativeUnit -AdministrativeUnit "$Prefix-au" -IncludeMembers -IncludeScopedRoles -ErrorAction Stop
  $Au0 | Format-List DisplayName, MembershipType, Visibility
  $Au0.Members | Sort-Object UserPrincipalName | Format-Table PrincipalId, UserPrincipalName -AutoSize
  @($Au0.ScopedRoles).Count

  $Ra0 = @(Get-OERRoleAssignment -Scope $RgScope -AtScope -ResolveNames -ErrorAction Stop | Where-Object Scope -eq $RgScope)
  $Ra0 | Sort-Object PrincipalDisplayName | Format-Table PrincipalDisplayName, PrincipalType, RoleName, PrincipalId, RoleAssignmentId -AutoSize
  $IdSp     = ($Ra0 | Where-Object PrincipalDisplayName -eq "$Prefix-app").PrincipalId
  $ReaderId = ($Ra0 | Where-Object PrincipalDisplayName -eq "$Prefix-app").RoleDefinitionId

  $CatRes0 = @(Get-OERCatalogResource -Catalog "$Prefix-catalog" -ErrorAction Stop)
  $CatRes0 | Format-Table DisplayName, ResourceType, OriginId -AutoSize
  $IdRes1 = ($CatRes0 | Where-Object DisplayName -eq "$Prefix-ap-res1").OriginId
  $IdRes2 = ($CatRes0 | Where-Object DisplayName -eq "$Prefix-ap-res2").OriginId
  $ApId   = (Get-OERAccessPackage -Catalog "$Prefix-catalog" -ErrorAction Stop | Where-Object DisplayName -eq "$Prefix-ap").Id
  $ApRoles0 = @(Get-OERAccessPackageResourceRole -AccessPackage $ApId -ErrorAction Stop)
  $ApRoles0 | Format-Table ResourceDisplayName, RoleName, OriginId, ResourceRoleScopeId -AutoSize
  @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId -ErrorAction Stop).Count

  $IdA, $IdB, $IdC, $IdSp, $ReaderId, $IdRes1, $IdRes2, $ApId | ForEach-Object { [bool]$_ }
  [ordered]@{ Members = $Members0; Eligibility = $Elig0; AdministrativeUnit = $Au0; RoleAssignments = $Ra0
      CatalogResources = $CatRes0; ResourceRoles = $ApRoles0 } |
      ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Raw '0.3-baseline.json') -Encoding utf8NoBOM
  ```

  **Expect:** `oer-s61-members` has exactly A, B and C. `oer-s61-pim` has exactly three
  eligibilities, one per user, `AccessType` `member`, `Days` `30` on every row, and `0` members.
  `oer-s61-au` is `Assigned` (MembershipType), members exactly A, B and C, `0` scoped roles.
  Exactly three role assignments are DEFINED at `<RgScope>`: `Reader` for `oer-s61-ra` (`Group`),
  `oer-s61-app` (`ServicePrincipal`) and `OER S61 User C` (`User`). The catalog holds exactly
  `oer-s61-ap-res1` and `oer-s61-ap-res2`; the access package has exactly two bindings, `Member` of
  each; it has `0` assignment policies. The `[bool]` line prints `True` eight times.
  **Failure looks like:** any count off, or a `False` in the `[bool]` line. In particular, a `Days`
  value other than `30` changes what 2.1 expects for user A (see there). A FOURTH role assignment
  defined at the resource group is not a failure, but every check in sections 1 and 6 then has one
  more candidate row than its `Expect:` states -- record it here.
  **Result:**

---

### 1. `roleAssignments` -- an unresolved entry withholds the prune at its scope

The unresolvable entry is the service principal `oer-s61-app` declared WITHOUT `principalType`:
the engine's heuristic tries a group of that name, then a user whose user principal name is
`oer-s61-app`, and both find nothing. Its live Reader assignment, and user C's, are the candidates
the old code would have removed.

Document `$Docs.RaWithheld` -- the resolvable entry FIRST, the unresolvable one SECOND:

```json
{
  "version": "1.0",
  "tenantAlias": "<your-test-tenant-alias>",
  "roleAssignments": [
    { "scope": "<RgScope>", "role": "Reader", "principal": "oer-s61-ra", "principalType": "Group" },
    { "scope": "<RgScope>", "role": "Reader", "principal": "oer-s61-app" }
  ]
}
```

- [ ] **1.1 The `-Prune -WhatIf` plan withholds both candidates.**

  ```powershell
  Invoke-S61Check -Id '1.1' -Json $Docs.RaWithheld -Include RoleAssignments -Prune
  Compare-Object (Get-S61WithheldId) (@($IdSp, $IdC) | Sort-Object)
  ```

  **Expect:** validation `Valid = True`, no finding. No warning, no error, and no `What if:` line
  at all. Exactly four results, in this order:
  1. Item `Reader -> oer-s61-ra @ <RgScope>`, `Unchanged`, `role assignment already exists at '<RgScope>'`.
  2. and 3. Item `<reader-guid> -> <IdSp> @ <RgScope>` and Item `<reader-guid> -> <IdC> @ <RgScope>`
     (in the order Azure lists them), both `Skipped`, Detail
     `prune withheld: declared entry 'Reader -> oer-s61-app @ <RgScope>' could not be resolved, so undeclared assignment '<ReaderId>' for principal '<IdSp or IdC>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.`
  4. Item `Reader -> oer-s61-app @ <RgScope>`, `Failed`, `principal 'oer-s61-app' could not be resolved to an object id`.

  The `Compare-Object` line prints nothing.
  **Failure looks like:** a `Skipped` row reading `would remove undeclared assignment ...` plus a
  `Sync-OERStructureRoleAssignment: would remove ...` warning (the guard missed: the old
  behaviour); an `Extra` row; the `oer-s61-app` row `Unchanged` (the name resolved to something --
  a group of that name exists, and the trigger is gone); or the `oer-s61-app` row `Failed` with
  `could not resolve principal 'oer-s61-app': ...` (the lookup THREW -- the abort path, not this
  one; record the message).
  **Result:**

- [ ] **1.2 Without `-Prune` the rows are the same -- `Skipped`, not `Extra`.**

  ```powershell
  Invoke-S61Check -Id '1.2' -Json $Docs.RaWithheld -Include RoleAssignments
  Compare-Object (Get-S61WithheldId) (@($IdSp, $IdC) | Sort-Object)
  ```

  **Expect:** the same four rows as 1.1, byte for byte; no `Extra` row; `Compare-Object` prints
  nothing.
  **Failure looks like:** two `Extra` rows with `(use -Prune to remove)` in place of the withheld
  rows.
  **Result:**

- [ ] **1.3 The real `-Prune` run removes nothing, and the read-back proves it.**

  ```powershell
  Invoke-S61Check -Id '1.3' -Json $Docs.RaWithheld -Include RoleAssignments -Prune -Apply
  $Ra13 = @(Get-OERRoleAssignment -Scope $RgScope -AtScope -ResolveNames -ErrorAction Stop | Where-Object Scope -eq $RgScope)
  $Ra13 | Sort-Object PrincipalDisplayName | Format-Table PrincipalDisplayName, PrincipalType, RoleName, RoleAssignmentId -AutoSize
  Compare-Object @($Ra0.RoleAssignmentId) @($Ra13.RoleAssignmentId)
  ```

  **Expect:** the same four rows as 1.1, no `Removed` row, no warning; the read-back lists the same
  three `Reader` assignments as 0.3 -- `oer-s61-app` and `OER S61 User C` still there -- and
  `Compare-Object` prints nothing.
  **Failure looks like:** a `Removed` row, or the SP's or user C's assignment missing from the
  read-back. Restore with the prerequisite script and record it.
  **Result:**

- [ ] **1.4 Unresolved entry FIRST: no prune pass runs at all.**

  Document `$Docs.RaWithheldFirst` -- the same two entries, order reversed:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "roleAssignments": [
      { "scope": "<RgScope>", "role": "Reader", "principal": "oer-s61-app" },
      { "scope": "<RgScope>", "role": "Reader", "principal": "oer-s61-ra", "principalType": "Group" }
    ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '1.4a' -Json $Docs.RaWithheldFirst -Include RoleAssignments -Prune
  Invoke-S61Check -Id '1.4b' -Json $Docs.RaWithheldFirst -Include RoleAssignments -Prune -Apply
  $Ra14 = @(Get-OERRoleAssignment -Scope $RgScope -AtScope -ErrorAction Stop | Where-Object Scope -eq $RgScope)
  Compare-Object @($Ra0.RoleAssignmentId) @($Ra14.RoleAssignmentId)
  ```

  **Expect:** in BOTH runs exactly two results: `Reader -> oer-s61-app @ <RgScope>` `Failed`
  (`principal 'oer-s61-app' could not be resolved to an object id`), then
  `Reader -> oer-s61-ra @ <RgScope>` `Unchanged`. No `Skipped`, `Extra` or `Removed` row for the
  scope: the first item of a scope carries the prune pass, and it returned before reaching it. No
  warning. `Compare-Object` prints nothing.
  **Failure looks like:** any row whose Item starts with `<reader-guid> ->`, or a changed read-back.
  **Result:**

---

### 2. Group PIM eligibility -- the most dangerous pass

An eligibility prune revokes standing privileged access, so this is the pass where a failed lookup
read as an empty fact costs the most. `"members": null` keeps the member pass out of it entirely;
`owners` and `pimPolicy` are omitted, and neither of those runs on an omitted key.

**What user A's row will be, and why:** `Unchanged`, with Detail
`eligibility for '<UserA>' (member) already matches`. The time-bound loop matches A's live instance
on the (principal, access type) pair -- the access type defaults to `member` -- and
`Resolve-OERGroupEligibilityChange` compares the declared `durationDays` (30) with the live window,
which `Resolve-OEREligibilityDuration` measures as `EndDateTime - StartDateTime` in whole days,
rounded. The prerequisite script granted exactly 30 days, so nothing differs: no write and no
`ShouldProcess` call. If 0.3 recorded a `Days` value `N` other than 30, A's row is instead `Skipped`
under `-WhatIf` with `would set time-bound member eligibility for '<UserA>': member eligibility duration differs (live N days, declared 30 days)`
-- and the real run would re-issue it (`Updated`, `adminUpdate`). In that case set A's
`durationDays` to `N` in `$Docs.PimWithheld` before 2.2, so 2.2 writes nothing.

Document `$Docs.PimWithheld`:

```json
{
  "version": "1.0",
  "tenantAlias": "<your-test-tenant-alias>",
  "groups": [
    {
      "displayName": "oer-s61-pim",
      "members": null,
      "eligibility": [
        { "principal": "<UserA>", "durationDays": 30 },
        { "principal": "OER S61 User B", "durationDays": 30 }
      ]
    }
  ]
}
```

- [ ] **2.1 The `-Prune -WhatIf` plan withholds B's and C's eligibility.**

  ```powershell
  Invoke-S61Check -Id '2.1' -Json $Docs.PimWithheld -Include Groups -Prune
  Compare-Object (Get-S61WithheldId) (@($IdB, $IdC) | Sort-Object)
  ```

  **Expect:** validation `Valid = True`, no finding (in particular no omitted-collection Warning:
  `members` is an explicit null). No warning. One error, `PrincipalNotFound`:
  `Could not resolve eligibility principal 'OER S61 User B' to an object id.` No `What if:` line.
  Exactly five results, all Section `groups`, Item `oer-s61-pim`:
  1. `Unchanged` `group properties match`
  2. `Unchanged` `eligibility for '<UserA>' (member) already matches`
  3. `Failed` `could not resolve eligibility principal 'OER S61 User B'`
  4. and 5. `Skipped`, Detail
     `prune withheld: declared entry 'OER S61 User B' could not be resolved, so undeclared member eligibility for principal '<IdB or IdC>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.`

  `Compare-Object` prints nothing.
  **Failure looks like:** `would remove undeclared member eligibility for principal ...` rows and a
  `Sync-OERStructureGroup: would remove ...` warning (the old behaviour); B's row `Failed` with
  `handler error: ...` and no withheld rows (the lookup THREW and aborted the item -- a different
  path; record the message); any member row (the explicit null was not honoured).
  **Result:**

- [ ] **2.2 The real `-Prune` run revokes nothing.**

  ```powershell
  Invoke-S61Check -Id '2.2' -Json $Docs.PimWithheld -Include Groups -Prune -Apply
  $Elig22 = @(Get-OERGroupEligibility -Group "$Prefix-pim" -ErrorAction Stop)
  $Elig22 | Sort-Object PrincipalId | Format-Table PrincipalId, AccessType, EndDateTime, ScheduleInstanceId -AutoSize
  Compare-Object @($Elig0 | ForEach-Object { "$($_.PrincipalId)|$($_.AccessType)|$($_.EndDateTime)" }) `
                 @($Elig22 | ForEach-Object { "$($_.PrincipalId)|$($_.AccessType)|$($_.EndDateTime)" })
  ```

  **Expect:** the same five rows as 2.1, no `Removed` and no `Updated` row; the read-back still
  lists the three eligibilities of 0.3 with the same `EndDateTime`, and `Compare-Object` prints
  nothing.
  **Failure looks like:** a `Removed` row, or B's or C's eligibility missing from the read-back
  (restore with the prerequisite script and record it); an `Updated` row for A (see the note above
  the document).
  **Result:**

---

### 3. Group members

Document `$Docs.MembersWithheld`:

```json
{
  "version": "1.0",
  "tenantAlias": "<your-test-tenant-alias>",
  "groups": [ { "displayName": "oer-s61-members", "members": [ "<UserA>", "OER S61 User B" ] } ]
}
```

- [ ] **3.1 The `-Prune -WhatIf` plan withholds B and C.**

  ```powershell
  Invoke-S61Check -Id '3.1' -Json $Docs.MembersWithheld -Include Groups -Prune
  Compare-Object (Get-S61WithheldId) (@($IdB, $IdC) | Sort-Object)
  ```

  **Expect:** validation `Valid = True`, no finding. No warning (no omitted-collection warning:
  `members` is declared). One error, `PrincipalNotFound`:
  `Could not resolve principal 'OER S61 User B' to an object id.` No `What if:` line. Exactly five
  results, Section `groups`, Item `oer-s61-members`:
  1. `Unchanged` `group properties match`
  2. `Unchanged` `member '<UserA>' already present`
  3. `Failed` `could not resolve member 'OER S61 User B'`
  4. and 5. `Skipped`, Detail
     `prune withheld: declared entry 'OER S61 User B' could not be resolved, so undeclared member '<IdB or IdC>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.`

  `Compare-Object` prints nothing.
  **Failure looks like:** `would remove undeclared member ...` rows with
  `Sync-OERStructureGroup: would remove undeclared member ...` warnings; B's row reading
  `handler error: ...` (a thrown lookup).
  **Result:**

- [ ] **3.2 Without `-Prune`, the same rows -- `Skipped`, not `Extra`.**

  ```powershell
  Invoke-S61Check -Id '3.2' -Json $Docs.MembersWithheld -Include Groups
  ```

  **Expect:** the same five rows as 3.1; no `Extra` row.
  **Failure looks like:** two `Extra` rows `undeclared member '<id>' (use -Prune to remove)`.
  **Result:**

- [ ] **3.3 The real `-Prune` run removes nothing.**

  ```powershell
  Invoke-S61Check -Id '3.3' -Json $Docs.MembersWithheld -Include Groups -Prune -Apply
  $Members33 = @(Get-OERGroupMember -Group "$Prefix-members" -ErrorAction Stop)
  $Members33 | Sort-Object UserPrincipalName | Format-Table PrincipalId, UserPrincipalName, DisplayName -AutoSize
  Compare-Object @($Members0.PrincipalId) @($Members33.PrincipalId)
  ```

  **Expect:** the same five rows as 3.1, no `Removed` row; A, B and C are all still members and
  `Compare-Object` prints nothing.
  **Failure looks like:** a `Removed` row, or B or C missing from the read-back.
  **Result:**

- [ ] **3.4 Two unresolved entries: the plural form names both (`-WhatIf` only).**

  Document `$Docs.MembersWithheldTwo`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "groups": [ { "displayName": "oer-s61-members", "members": [ "<UserA>", "OER S61 User B", "OER S61 User C" ] } ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '3.4' -Json $Docs.MembersWithheldTwo -Include Groups -Prune
  ```

  **Expect:** two `Failed` rows (`could not resolve member 'OER S61 User B'`, then `... 'OER S61 User C'`)
  and two errors; the two `Skipped` rows (for `<IdB>` and `<IdC>`) read
  `prune withheld: declared entries 'OER S61 User B', 'OER S61 User C' could not be resolved, so undeclared member '<IdB or IdC>' may be the live counterpart of one of them and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entries to reconcile this collection.`
  **Failure looks like:** the singular form naming only one entry.
  **Result:**

---

### 4. Administrative unit members

Document `$Docs.AuWithheld` -- `"scopedRoles": null` keeps the scoped-role pass out of it:

```json
{
  "version": "1.0",
  "tenantAlias": "<your-test-tenant-alias>",
  "administrativeUnits": [ { "displayName": "oer-s61-au", "members": [ "<UserA>", "OER S61 User B" ], "scopedRoles": null } ]
}
```

- [ ] **4.1 The `-Prune -WhatIf` plan withholds B and C.**

  ```powershell
  Invoke-S61Check -Id '4.1' -Json $Docs.AuWithheld -Include AdministrativeUnits -Prune
  Compare-Object (Get-S61WithheldId) (@($IdB, $IdC) | Sort-Object)
  ```

  **Expect:** validation `Valid = True`, no finding. No warning. One error, `PrincipalNotFound`:
  `Could not resolve principal 'OER S61 User B' to an object id.` No `What if:` line. Exactly five
  results, Section `administrativeUnits`, Item `oer-s61-au`:
  1. `Unchanged` `administrative unit properties match`
  2. `Unchanged` `member '<UserA>' already present`
  3. `Failed` `could not resolve member 'OER S61 User B'`
  4. and 5. `Skipped`, Detail
     `prune withheld: declared entry 'OER S61 User B' could not be resolved, so undeclared member '<IdB or IdC>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.`

  No scoped-role row. `Compare-Object` prints nothing.
  **Failure looks like:** `would remove undeclared member ...` rows with
  `Sync-OERStructureAdministrativeUnit: would remove ...` warnings; any scoped-role row.
  **Result:**

- [ ] **4.2 The real `-Prune` run removes nothing.**

  ```powershell
  Invoke-S61Check -Id '4.2' -Json $Docs.AuWithheld -Include AdministrativeUnits -Prune -Apply
  $Au42 = Get-OERAdministrativeUnit -AdministrativeUnit "$Prefix-au" -IncludeMembers -ErrorAction Stop
  $Au42.Members | Sort-Object UserPrincipalName | Format-Table PrincipalId, UserPrincipalName -AutoSize
  Compare-Object @($Au0.Members.PrincipalId) @($Au42.Members.PrincipalId)
  ```

  **Expect:** the same five rows as 4.1, no `Removed` row; A, B and C still members;
  `Compare-Object` prints nothing.
  **Failure looks like:** a `Removed` row, or B or C missing.
  **Result:**

---

### 5. Access package `resourceRoles`

The unresolvable entry is a misspelt resource, `oer-s61-ap-res2-typo`: it matches no resource in
the catalog by display name, and no group by that name either. `assignmentPolicies` is omitted, so
the policy step does not run and no policy row appears -- keep policies out of the verdict.

Document `$Docs.ApWithheld`:

```json
{
  "version": "1.0",
  "tenantAlias": "<your-test-tenant-alias>",
  "accessPackages": [
    {
      "displayName": "oer-s61-ap",
      "catalog": "oer-s61-catalog",
      "resourceRoles": [
        { "resource": "oer-s61-ap-res1", "role": "Member" },
        { "resource": "oer-s61-ap-res2-typo", "role": "Member" }
      ]
    }
  ]
}
```

- [ ] **5.1 The `-Prune -WhatIf` plan withholds the res2 binding.**

  ```powershell
  Invoke-S61Check -Id '5.1' -Json $Docs.ApWithheld -Include AccessPackages -Prune
  Compare-Object (Get-S61WithheldId) @($IdRes2)
  ```

  **Expect:** validation `Valid = True` with exactly one finding, a Warning at
  `accessPackages[0].catalog`: `Catalog 'oer-s61-catalog' is not declared in this document. It may already exist in the tenant.`
  -- harmless, the document does not declare the catalog on purpose. No warning, NO error (this
  `Failed` row carries no error record), no `What if:` line. Exactly four results, Section
  `accessPackages`, Item `oer-s61-ap`:
  1. `Unchanged` `access package properties match`
  2. `Unchanged` `resourceRole 'Member' on 'oer-s61-ap-res1' already bound`
  3. `Failed` `could not resolve resource 'oer-s61-ap-res2-typo' to an origin id in catalog 'oer-s61-catalog'`
  4. `Skipped`, Detail
     `prune withheld: declared entry 'oer-s61-ap-res2-typo' could not be resolved, so undeclared resourceRole binding 'Member|<IdRes2>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.`

  `Compare-Object` prints nothing.
  **Failure looks like:** `would remove undeclared resourceRole binding 'Member|<IdRes2>'` with a
  `Sync-OERStructureAccessPackage: would remove ...` warning; the typo row `Unchanged` or
  `Created` (it resolved to something); a `Failed` "handler error" row.
  **Result:**

- [ ] **5.2 The real `-Prune` run unbinds nothing.**

  ```powershell
  Invoke-S61Check -Id '5.2' -Json $Docs.ApWithheld -Include AccessPackages -Prune -Apply
  $ApRoles52 = @(Get-OERAccessPackageResourceRole -AccessPackage $ApId -ErrorAction Stop)
  $ApRoles52 | Format-Table ResourceDisplayName, RoleName, OriginId, ResourceRoleScopeId -AutoSize
  Compare-Object @($ApRoles0.ResourceRoleScopeId) @($ApRoles52.ResourceRoleScopeId)
  ```

  **Expect:** the same four rows as 5.1, no `Removed` row; both `Member` bindings still there;
  `Compare-Object` prints nothing.
  **Failure looks like:** a `Removed` row, or the res2 binding missing.
  **Result:**

---

### 6. Controls -- with every entry resolvable, `-Prune` still removes a genuine extra

Each control declares the same collection with every entry resolvable, so user C (or the res2
binding) is a genuine extra. These are the only writes in this file that remove anything, and they
remove only the one candidate each check names. `a` is the plan, `b` the real run.

- [ ] **6.1 `roleAssignments`: user C's Reader is removed.**

  Document `$Docs.RaControl` -- the SP entry now carries `principalType`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "roleAssignments": [
      { "scope": "<RgScope>", "role": "Reader", "principal": "oer-s61-ra", "principalType": "Group" },
      { "scope": "<RgScope>", "role": "Reader", "principal": "oer-s61-app", "principalType": "ServicePrincipal" }
    ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '6.1a' -Json $Docs.RaControl -Include RoleAssignments -Prune
  Invoke-S61Check -Id '6.1b' -Json $Docs.RaControl -Include RoleAssignments -Prune -Apply
  Get-OERRoleAssignment -Scope $RgScope -AtScope -ResolveNames -ErrorAction Stop | Where-Object Scope -eq $RgScope |
      Format-Table PrincipalDisplayName, PrincipalType, RoleName, RoleAssignmentId -AutoSize
  ```

  **Expect (6.1a):** no withheld row. Three results: `Reader -> oer-s61-ra @ <RgScope>` `Unchanged`;
  `<reader-guid> -> <IdC> @ <RgScope>` `Skipped` `would remove undeclared assignment '<ReaderId>' for principal '<IdC>'`;
  `Reader -> oer-s61-app @ <RgScope>` `Unchanged` `role assignment already exists at '<RgScope>'`.
  One warning:
  `Sync-OERStructureRoleAssignment: would remove undeclared assignment '<ReaderId>' for principal '<IdC>' at scope '<RgScope>'.`
  and one `What if:` line for `Remove undeclared role assignment '<C's RoleAssignmentId>'`.
  **Expect (6.1b):** the same rows with `Removed` `removed undeclared assignment '<ReaderId>' for principal '<IdC>'`
  in place of the `Skipped` row, and the warning reading `removing` instead of `would remove`.
  The read-back lists exactly two assignments, `oer-s61-ra` and `oer-s61-app`.
  **Failure looks like:** a withheld row (the guard fires with nothing unresolved), or C's
  assignment still in the read-back.
  **Result:**

- [ ] **6.2 Eligibility: C's eligibility is revoked.**

  Document `$Docs.PimControl` -- B by user principal name:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "groups": [
      {
        "displayName": "oer-s61-pim",
        "members": null,
        "eligibility": [
          { "principal": "<UserA>", "durationDays": 30 },
          { "principal": "<UserB>", "durationDays": 30 }
        ]
      }
    ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '6.2a' -Json $Docs.PimControl -Include Groups -Prune
  Invoke-S61Check -Id '6.2b' -Json $Docs.PimControl -Include Groups -Prune -Apply
  Get-OERGroupEligibility -Group "$Prefix-pim" -ErrorAction Stop | Format-Table PrincipalId, AccessType, EndDateTime -AutoSize
  ```

  **Expect (6.2a):** `Unchanged` `group properties match`; `Unchanged` for A and for B
  (`eligibility for '<UserB>' (member) already matches`); `Skipped`
  `would remove undeclared member eligibility for principal '<IdC>'`; one warning
  `Sync-OERStructureGroup: would remove undeclared member eligibility for principal '<IdC>' from group 'oer-s61-pim'.`
  **Expect (6.2b):** the same with `Removed` `removed undeclared member eligibility for principal '<IdC>'`
  and the warning reading `removing`. The read-back lists A and B only. A revoked instance can take
  a minute to disappear: if C is still listed, re-read after a minute and record both reads.
  **Failure looks like:** a withheld row; C still eligible after the second read.
  **Result:**

- [ ] **6.3 Group members: C is removed.**

  Document `$Docs.MembersControl`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "groups": [ { "displayName": "oer-s61-members", "members": [ "<UserA>", "<UserB>" ] } ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '6.3a' -Json $Docs.MembersControl -Include Groups -Prune
  Invoke-S61Check -Id '6.3b' -Json $Docs.MembersControl -Include Groups -Prune -Apply
  Get-OERGroupMember -Group "$Prefix-members" -ErrorAction Stop | Format-Table PrincipalId, UserPrincipalName -AutoSize
  ```

  **Expect (6.3a):** two `member '...' already present` rows, `Skipped` `would remove undeclared member '<IdC>'`,
  warning `Sync-OERStructureGroup: would remove undeclared member '<IdC>' from group 'oer-s61-members'.`
  **Expect (6.3b):** `Removed` `removed undeclared member '<IdC>'`; the read-back lists A and B only.
  **Failure looks like:** a withheld row, or C still a member.
  **Result:**

- [ ] **6.4 Administrative unit members: C is removed.**

  Document `$Docs.AuControl`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "administrativeUnits": [ { "displayName": "oer-s61-au", "members": [ "<UserA>", "<UserB>" ], "scopedRoles": null } ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '6.4a' -Json $Docs.AuControl -Include AdministrativeUnits -Prune
  Invoke-S61Check -Id '6.4b' -Json $Docs.AuControl -Include AdministrativeUnits -Prune -Apply
  (Get-OERAdministrativeUnit -AdministrativeUnit "$Prefix-au" -IncludeMembers -ErrorAction Stop).Members |
      Format-Table PrincipalId, UserPrincipalName -AutoSize
  ```

  **Expect (6.4a):** `Skipped` `would remove undeclared member '<IdC>'`, warning
  `Sync-OERStructureAdministrativeUnit: would remove undeclared member '<IdC>' from unit 'oer-s61-au'.`
  **Expect (6.4b):** `Removed` `removed undeclared member '<IdC>'`; the read-back lists A and B only.
  **Failure looks like:** a withheld row, or C still a member.
  **Result:**

- [ ] **6.5 Access package: the res2 binding is removed.**

  Document `$Docs.ApControl`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "accessPackages": [
      {
        "displayName": "oer-s61-ap",
        "catalog": "oer-s61-catalog",
        "resourceRoles": [ { "resource": "oer-s61-ap-res1", "role": "Member" } ]
      }
    ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '6.5a' -Json $Docs.ApControl -Include AccessPackages -Prune
  Invoke-S61Check -Id '6.5b' -Json $Docs.ApControl -Include AccessPackages -Prune -Apply
  Get-OERAccessPackageResourceRole -AccessPackage $ApId -ErrorAction Stop | Format-Table ResourceDisplayName, RoleName, OriginId -AutoSize
  ```

  **Expect (6.5a):** the catalog Warning at validation (as 5.1); `Skipped`
  `would remove undeclared resourceRole binding 'Member|<IdRes2>'`, warning
  `Sync-OERStructureAccessPackage: would remove undeclared resourceRole binding 'Member|<IdRes2>' from access package 'oer-s61-ap'.`
  **Expect (6.5b):** `Removed` `removed undeclared resourceRole binding 'Member|<IdRes2>'`; the
  read-back lists the res1 binding only. (`oer-s61-ap-res2` stays a catalog resource: the catalog is
  not in the document.)
  **Failure looks like:** a withheld row, or the res2 binding still there.
  **Result:**

- [ ] **6.6 Convergence: each control document applied again changes nothing.**

  ```powershell
  $Controls = [ordered]@{
      '6.1' = @($Docs.RaControl, 'RoleAssignments')
      '6.2' = @($Docs.PimControl, 'Groups')
      '6.3' = @($Docs.MembersControl, 'Groups')
      '6.4' = @($Docs.AuControl, 'AdministrativeUnits')
      '6.5' = @($Docs.ApControl, 'AccessPackages')
  }
  foreach ($Key in $Controls.Keys) {
      Invoke-S61Check -Id "6.6-$Key-plan" -Json $Controls[$Key][0] -Include $Controls[$Key][1] -Prune
      Invoke-S61Check -Id "6.6-$Key-apply" -Json $Controls[$Key][0] -Include $Controls[$Key][1] -Prune -Apply
  }
  Import-Csv (Join-Path $Raw 'all-results.csv') | Where-Object CheckId -like '6.6-*' | Group-Object CheckId, Action -NoElement |
      Format-Table Count, Name -AutoSize
  ```

  **Expect:** every one of the ten runs reports only `Unchanged` rows -- `6.1`: 2, `6.2`: 3,
  `6.3`: 3, `6.4`: 3, `6.5`: 2 -- with no `Skipped`, `Removed`, `Extra` or `Failed` row, no
  warning, no error and no `What if:` line. (The two `6.5` documents still show the catalog Warning
  at validation, exactly as in 5.1; that is a validation finding, not a run warning.)
  **Failure looks like:** any row other than `Unchanged`; a `Removed` row means the first apply did
  not converge.
  **Result:**

---

### 7. The omitted-collection warning

**7.2 and 7.3 plan the removal of every live entry in the omitted collections. NEVER run either one
without `-WhatIf` -- never add `-Apply` to them.** 7.5 would create a dynamic group: `-WhatIf` only
as well.

Document `$Docs.MembersOmitted`, used by 7.1, 7.2 and 7.6:

```json
{
  "version": "1.0",
  "tenantAlias": "<your-test-tenant-alias>",
  "groups": [ { "displayName": "oer-s61-members" } ]
}
```

- [ ] **7.1 `Test-OERStructure` reports the omitted `members` key as a Warning.**

  ```powershell
  Invoke-S61Check -Id '7.1' -Json $Docs.MembersOmitted -Include Groups -ValidateOnly
  ```

  **Expect:** `Valid = True` with exactly one finding: Section `groups`, Item `oer-s61-members`,
  Path `groups[0].members`, Severity `Warning`, Message
  `'members' is omitted at groups[0]. An omitted members key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.`
  **Failure looks like:** no finding, or the finding as an `Error` (`Valid = False`).
  **Result:**

- [ ] **7.2 `Invoke-OERStructure -Prune -WhatIf` writes ONE warning, before anything else.**
  **`-WhatIf` only.**

  ```powershell
  Invoke-S61Check -Id '7.2' -Json $Docs.MembersOmitted -Include Groups -Prune
  $S61Out[0].GetType().Name
  $S61Out[0].Message
  @($S61Warning | Where-Object Message -like 'Invoke-OERStructure:*').Count
  ```

  **Expect:** the first item of the merged stream is a `WarningRecord` whose Message is
  `Invoke-OERStructure: -Prune is set and the document omits 1 collection key(s) that are still reconciled when omitted, so every live entry in them would be removed: groups 'oer-s61-members' members. Declare each key (an empty array removes the entries deliberately), or set it to null to leave that collection untouched.`
  The count line prints `1`. After it, one
  `Sync-OERStructureGroup: would remove undeclared member '<id>' from group 'oer-s61-members'.`
  per live member (A and B once section 6 has run; A, B and C before). Results: `Unchanged`
  `group properties match` and one `Skipped` `would remove undeclared member '<id>'` per live
  member. `Get-OERGroupMember -Group oer-s61-members` afterwards is unchanged.
  **Failure looks like:** no `Invoke-OERStructure:` warning; two of them; the warning not first;
  `will be removed` under `-WhatIf`.
  **Result:**

- [ ] **7.3 All five collections, and the `-Include` narrowing. `-WhatIf` only.**

  Document `$Docs.FiveOmitted`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "groups": [ { "displayName": "oer-s61-members" } ],
    "administrativeUnits": [ { "displayName": "oer-s61-au" } ],
    "catalogs": [ { "displayName": "oer-s61-catalog" } ],
    "accessPackages": [ { "displayName": "oer-s61-ap", "catalog": "oer-s61-catalog" } ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '7.3a' -Json $Docs.FiveOmitted -Include Groups, AdministrativeUnits, Catalogs, AccessPackages -Prune
  $S61Out[0].Message
  Invoke-S61Check -Id '7.3b' -Json $Docs.FiveOmitted -Include Groups, AdministrativeUnits -Prune
  $S61Out[0].Message
  ```

  **Expect:** validation `Valid = True` with five Warning findings, at `groups[0].members`,
  `administrativeUnits[0].members`, `administrativeUnits[0].scopedRoles`, `catalogs[0].resources`
  and `accessPackages[0].resourceRoles`. 7.3a's first stream item reads
  `Invoke-OERStructure: -Prune is set and the document omits 5 collection key(s) that are still reconciled when omitted, so every live entry in them would be removed: groups 'oer-s61-members' members; administrativeUnits 'oer-s61-au' members; administrativeUnits 'oer-s61-au' scopedRoles; catalogs 'oer-s61-catalog' resources; accessPackages 'oer-s61-ap' resourceRoles. Declare each key (an empty array removes the entries deliberately), or set it to null to leave that collection untouched.`
  7.3b's reads `... omits 3 collection key(s) ... would be removed: groups 'oer-s61-members' members; administrativeUnits 'oer-s61-au' members; administrativeUnits 'oer-s61-au' scopedRoles. ...`
  The plan rows are `... properties match` (`Unchanged`) and `would remove ...` (`Skipped`) rows
  only -- nothing is written. (If the unit's scoped-role read is refused for lack of consent, that
  unit's row is `Failed`; the warning is still the verdict here.)
  **Failure looks like:** a count other than 5 / 3; a collection missing or listed twice; the order
  not groups, units (members before scopedRoles), catalogs, access packages.
  **Result:**

- [ ] **7.4 An explicit `"members": null` is not warned about.**

  Document `$Docs.MembersNull`:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "groups": [ { "displayName": "oer-s61-members", "members": null } ]
  }
  ```

  ```powershell
  Invoke-S61Check -Id '7.4' -Json $Docs.MembersNull -Include Groups -Prune
  ```

  **Expect:** validation `Valid = True`, no finding; no warning at all; one result, `Unchanged`
  `group properties match`.
  **Failure looks like:** the omitted-collection Warning or warning appears; any member row.
  **Result:**

- [ ] **7.5 The `members` of a group declared `"dynamic": true` are not warned about. `-WhatIf` only.**

  Document `$Docs.DynamicAbsent` -- a group name that does not exist:

  ```json
  {
    "version": "1.0",
    "tenantAlias": "<your-test-tenant-alias>",
    "groups": [ { "displayName": "oer-s61-dyn-absent", "dynamic": true, "membershipRule": "(user.department -eq \"oer-s61-dyn-none\")" } ]
  }
  ```

  ```powershell
  Get-OERGroup -Filter "displayName eq '$Prefix-dyn-absent'" -ErrorAction Continue
  Invoke-S61Check -Id '7.5' -Json $Docs.DynamicAbsent -Include Groups -Prune
  ```

  **Expect:** the `Get-OERGroup` line writes a `GroupNotFound` error (`No group found for ...`) --
  the group does not exist. Validation `Valid = True` with no omitted-collection finding; no
  warning; one result, `Skipped` `would create group oer-s61-dyn-absent`.
  **Failure looks like:** a `groups 'oer-s61-dyn-absent' members` entry in a Warning finding or in
  an `Invoke-OERStructure:` warning.
  **Result:**

- [ ] **7.6 The same omitted document WITHOUT `-Prune`: no warning.**

  ```powershell
  Invoke-S61Check -Id '7.6' -Json $Docs.MembersOmitted -Include Groups
  ```

  **Expect:** validation shows the 7.1 Warning finding (validation does not know about `-Prune`),
  but the run writes no warning at all; results: `Unchanged` `group properties match` and one
  `Extra` `undeclared member '<id>' (use -Prune to remove)` per live member.
  **Failure looks like:** an `Invoke-OERStructure:` warning without `-Prune`.
  **Result:**

---

### 8. `Get-OERRequiredScope` -- `Set-OERGroup`

- [ ] **8.1 `Set-OERGroup` lists `RoleManagement.ReadWrite.Directory`.** Offline: this reads a
  static table and signs in to nothing.

  ```powershell
  Get-OERRequiredScope -Cmdlet Set-OERGroup | Format-List Cmdlet, Transport, GraphScope, AzureRole, Note, Verified
  (Get-OERRequiredScope -Cmdlet Set-OERGroup).GraphScope -contains 'RoleManagement.ReadWrite.Directory'
  ```

  **Expect:** `GraphScope` lists `Group.ReadWrite.All` and `RoleManagement.ReadWrite.Directory`;
  `Note` begins
  `RoleManagement.ReadWrite.Directory is needed only when the group is role-assignable (isAssignableToRole)`;
  `Verified` is `False` -- the Update group permission table does not list the permission, so the
  entry is marked as not confirmed by it; the second line prints `True`.
  **Failure looks like:** `GraphScope` is `Group.ReadWrite.All` alone -- a build without this
  branch's scope-map change; or `Verified` is `True` -- a build without "fix: mark the Set-OERGroup
  scope entry as not confirmed by the API table".
  **Result:**

---

### Teardown

- [ ] **T.1 Read the teardown plan.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -Teardown -WhatIf
  ```

  **Expect:** the tenant is identified first, exactly as in 0.2 (the `Identified the test tenant`
  line, no question under `-WhatIf`); then `What if:` lines, and nothing else changed, for: the role assignments defined at
  `oer-s61-rg` (two after 6.1: `oer-s61-ra` and `oer-s61-app`), the resource group, the remaining
  binding of `oer-s61-ap` (res1 after 6.5), the access package, the two catalog resources, the
  catalog, the eligibilities on `oer-s61-pim` (A and B after 6.2), the administrative unit, the
  five groups, the app registration and the three users. Every name starts with `oer-s61`.
  **Failure looks like:** any target without the prefix -- stop, do not run T.2.
  **Result:**

- [ ] **T.2 Remove every test object.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -Teardown
  ```

  **Expect:** the tenant is identified and the one question names the organization, its tenant id
  and the subscription BEFORE anything is removed; the Phase 2 and the second Phase 1 sign-in each
  report `... is signed in to the confirmed test tenant ...`. `Done.`; the Phase 2 sweep reports no catalog, no access package, and at most the
  resource group in `Deleting` state (Azure deletes it asynchronously); the Phase 1 sweep reports
  no user, group, app registration, service principal or administrative unit starting with
  `oer-s61`. The eligibilities are removed explicitly; deleting `oer-s61-pim` then removes anything
  left together with the group's own PIM-for-Groups policies, which the prerequisite script's first
  eligibility created and no check ever changed.
  **Failure looks like:** a sweep line `still present: ...` other than a `Deleting` resource group;
  an error. Re-run T.2 (it only removes what is still there) and record both runs.
  **Result:**

- [ ] **T.3 Read back through the module that everything is gone.**

  ```powershell
  Get-OERGroup -Filter "startswith(displayName,'$Prefix')" -ErrorAction Continue
  Get-OERAdministrativeUnit -Filter "startswith(displayName,'$Prefix')" -ErrorAction Continue
  Get-OERCatalog -DisplayName "$Prefix-catalog"
  Get-OERAccessPackage -DisplayName "$Prefix-ap"
  Get-OERResourceGroup -Subscription $SubId | Where-Object ResourceGroup -like "$Prefix*"
  ```

  **Expect:** the group and unit lines write a not-found error (or nothing), and the other three
  print nothing. If the resource group is still listed as `Deleting`, re-read after a few minutes
  and record when it went.
  **Failure looks like:** any object listed.
  **Result:**

- [ ] **T.4 Read back through Microsoft Graph that no user, app registration or service principal is
  left.** The module has no user or application read, so this signs in separately, read-only, at
  the very end.

  ```powershell
  $TenantId = (Get-OERConfiguration -TenantAlias $Alias).TenantId
  Disconnect-OER
  Connect-MgGraph -TenantId $TenantId -Scopes 'User.Read.All', 'Application.Read.All' -ContextScope Process -NoWelcome
  $F = [uri]::EscapeDataString("startswith(userPrincipalName,'$Prefix')")
  @((Invoke-MgGraphRequest -Uri "v1.0/users?`$filter=$F&`$select=id,userPrincipalName").value).Count
  $F = [uri]::EscapeDataString("startswith(displayName,'$Prefix')")
  @((Invoke-MgGraphRequest -Uri "v1.0/applications?`$filter=$F&`$select=id,displayName").value).Count
  @((Invoke-MgGraphRequest -Uri "v1.0/servicePrincipals?`$filter=$F&`$select=id,displayName").value).Count
  Disconnect-MgGraph
  $Error.Clear()   # a failed raw Graph call leaves an ErrorRecord that can carry the bearer token -- README.md, "Credentials"
  ```

  **Expect:** `0`, `0`, `0`. The three users and the app registration now sit in Deleted items for
  30 days, which is Entra ID's design; they hold no role, membership or eligibility, and the next
  prerequisite run can create the same names again.
  **Failure looks like:** any count above `0`.
  **Result:**

- [ ] **T.5 No object outside the prefix was touched, and nothing but the five controls was
  removed.**

  ```powershell
  $All = Import-Csv (Join-Path $Raw 'all-results.csv')
  $All | Where-Object Action -in 'Created', 'Updated', 'Removed' | Format-Table CheckId, Section, Item, Action, Detail -Wrap
  @($All | Where-Object { $_.Item -notlike "*$Prefix*" }).Count
  ```

  **Expect:** exactly five rows, all `Removed`: `6.1b` (user C's Reader), `6.2b` (user C's
  eligibility), `6.3b` and `6.4b` (user C's memberships) and `6.5b` (the res2 binding) -- and no
  `Created` or `Updated` row in any check. The count line prints `0`: every row of every run names
  an `oer-s61` object (a role-assignment row names the scope `.../resourceGroups/oer-s61-rg`). No
  document ever named an object outside the prefix, none declared a `pimPolicy`, `owners` or a
  non-null `scopedRoles`, and no pre-existing object or policy in the tenant was read for a verdict
  or written.
  **Failure looks like:** any other `Removed` row (record which check and whether 0.3's state was
  restored); an `Updated` row for user A's eligibility (2.1's note); a row outside the prefix.
  **Result:**

- [ ] **T.6 Redact, then clean up.** Move what the results above need from
  `docs/live-verification/raw/s61/` into this file, redacted per [README.md](README.md) -- ids to
  `00000000-0000-0000-0000-0000000000NN`, user principal names to `personN@example.com`, no
  credential, no bearer token. Then delete the folder.

  ```powershell
  Remove-Item -LiteralPath $Raw -Recurse -Force
  git -C $Repo status --short docs/live-verification
  ```

  **Expect:** `git status` shows only this checklist as modified; nothing under `raw/` is ever
  staged.
  **Result:**
