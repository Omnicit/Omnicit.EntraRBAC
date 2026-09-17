# Live verification checklist -- ARM throttle backoff and access review read pacing (issues #57, #74)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened. A recorded observation is the deliverable there -- do
not substitute a guess.

**Three box states, and the middle one is the point of this file.** `- [x]` is a check that ran and
whose evidence supports it. `- [ ]` is a check that has not been run. `- [~]` is a check that
EXECUTED cleanly and still proves nothing, because the tenant held no data for it to measure -- a
`Match True` over zero rows, or an `Empty 0` over zero rows, is a vacuous pass, and ticking one
would record a verification that did not happen. A `- [~]` box is a debt, not a failure of the code.

## What this run established, and what it did not

**Run once, on 2026-09-07, against the `Omnicit` tenant** (interactive/delegated), from
`C:\Git\Omnicit.EntraRBAC` at `b58f7a4` on `fix/arm-throttle-and-review-pacing`, with a `main`
baseline captured in the same session by check 0.B.

- **Section 1 -- the ARM walk (issue #57) -- is genuine evidence and it is clean.** Every one of
  the twelve checks ran against real ARM, every count matched the `main` baseline with a delta of
  `0`, and the export walk produced identical item counts on both sides. Read section 4 for the
  ARM paging caveat that number hides.
- **Section 3 -- the access review `$select` (issue #74) -- is only PARTLY verified.** Check 0.0
  discovered that no access review in this tenant has a single decision, on any instance of any
  definition; 3.2 then found that the definition 0.0 picked has no second stage either. Checks 3.2,
  3.3 and 3.6 therefore executed over zero rows and are marked `- [~]`: their evidence is kept, and
  it is not evidence. **Issue #74's central risk -- a `$select` that silently drops a decision field -- is not
  live-verified by this run.** It needs a tenant with a decided review.
- **Two commits on this branch have no check at all** (`67188a9`, `b58f7a4`, the server-side
  `displayName eq` filter on `Get-OERAccessReviewDefinition`). Checks 3.7 and 3.8 were added for
  them after the run and are unticked; they are for the next connection.

**Everything below is READ-ONLY.** Nothing in this document creates, updates or deletes a tenant
object, and there is no `-Prune`, no `-Confirm:$false` and no write path anywhere in it. Section T
says so explicitly rather than leaving a teardown section off.

## Redact before you commit

Read `docs/live-verification/README.md` first. The rules that bite here:

- Every tenant identifier pasted into a `Result:` block becomes
  `00000000-0000-0000-0000-0000000000NN`, counting up from `01` per DISTINCT identifier in
  first-appearance order, restarting in this file. Subscription ids, management group ids, role
  definition GUIDs, principal ids, access review definition and instance ids -- all of them.
- An ARM `ResourceId` pasted from console output contains a subscription GUID inside the path.
  Redact the GUID inside the path; keep the path shape.
- Email addresses outside `example.com`/`contoso.com` become `person1@example.com`,
  `person2@example.com`, ...
- **No credential ever goes in.** Section 2 deliberately searches a captured stream for a bearer
  token. If it ever finds one, that is a finding -- record the FACT and the file and line it was
  found at, and never the value. A leaked token's minting secret is rotated, not redacted.

`tests/QA/dochygiene.tests.ps1` fails the gate on a violation and reports file and line without
printing the value. It is a backstop, not a substitute for redacting as you write.

## What changed and why this needs a live tenant

Two issues, both in a transport wrapper, both invisible to a mocked suite in exactly the way this
document exists to cover.

- **#57 -- ARM had no throttle handling at all.** `Invoke-OERArmRequest` normalized every response
  to `{ StatusCode; Content }` and destroyed the header collection on that line, so whatever
  `Retry-After` ARM sent was gone before the status was judged. A 429 fell straight through to
  `Convert-ArmHttpException` as a plain failure. The normalized shape now carries `Headers`, and a
  429 -- plus a 503 that NAMES a wait -- is retried with a bounded backoff whose constants mirror
  the Graph wrapper's: 300 s of waiting per request (per page under `-All`), a 900 s per-call
  deadline, a hard cap of 10 retries per request, and every single wait clamped to 1..120 s. The
  header collection never leaves the wrapper; only its `Retry-After` entry is ever read.
- **#74 -- `Get-OERAccessReviewInstance` asked Graph for everything.** The instance and decision
  reads now send `$select` naming exactly the fields their converters read. The stage read
  deliberately sends none. **A wrong `$select` is a silent bug**: the dropped field arrives `$null`
  with no error anywhere, which is the same defect class PR #45 fixed. Section 3 is where that is
  checked against real Graph data rather than against a fixture.

**Every test on this branch mocks the transport.** The ARM suite mocks `Invoke-WebRequest` and
supplies its own headers; the access review suite mocks `Invoke-OERGraphRequest`. That proves the
module BUILDS the intended request and REACTS correctly to a supplied response. It proves nothing
about what real ARM sends back, and nothing about what real Graph returns for a `$select`ed read.

## Why this checklist is a full walk and not a provoked 429

**An ARM throttle cannot be provoked on demand from one workstation, and a checklist demanding one
is a debt nobody can pay.** The arithmetic is the same one that parked PR #77's checklist on the
Graph side, where it was measured rather than assumed: a serial command loop from a single machine
issues roughly two requests a second, against a bucket sized in the hundreds per second. That is
about two orders of magnitude below the limit. PR #77's own live run confirmed it -- 11 requests in
5 s, then 10 rounds over 8 definitions in 473 s, and the tenant never throttled once.

So this document does not ask for a 429. What a **full ARM walk** does prove, and what no mocked
test can, is that the widened response shape, the new backoff wrapper and the new per-call budget
did not break the ordinary path -- in every ARM cmdlet, across many pages, against real ARM
responses with real headers. That is the primary evidence here, and section 1 is where it is
collected. Section 4 states plainly what is left unproved.

---

## Setup, once

> **This environment (Omnicit AB, tenant alias `Omnicit`, run 2026-09-07 from
> `C:\Git\Omnicit.EntraRBAC` on branch `fix/arm-throttle-and-review-pacing`, PR #84).** No
> pre-req script this time: there is nothing to create, since every check is a read.
> `Initialize-OerDvPrereq.ps1` / `Remove-OerTestObjects.ps1` are not involved.
>
> **Two things differ from Sprint 1, 1.5 and 2, and both are handled in section 0 rather than by
> hand:** (a) the values this file needs (a subscription, a management group, an access review
> definition with instances and decisions) are DISCOVERED by check 0.0 and assigned to `$Sub`,
> `$Mg`, `$Def`, `$One` -- override any of them after the listing if the auto-pick is a bad one;
> (b) checks 1.1 and 1.3--1.12 are all "the same count as on `main`", and there is no earlier
> ARM baseline for this tenant (Sprint 1 ran app-only without `-IncludeARM`; Sprint 1.5's ARM run
> was the GCC High tenant). Check 0.B builds `main`, captures the baseline into
> `$BaselineFile`, and rebuilds the branch. Do not skip it -- a comparison against nothing proves
> nothing.
>
> **The `output/` build is STALE at the time of writing** (built 2026-09-07 03:07 UTC; `e8fb1f5`
> at 03:48 UTC touched `Invoke-OERArmRequest.ps1` and `Get-OERAccessReviewInstance.ps1`). The
> Setup block below rebuilds before anything else; 0.1 is the tell that it worked.
>
> | Placeholder | Real value |
> |---|---|
> | `<your-tenant-alias>` | `Omnicit` (`Connect-OER -TenantAlias Omnicit -IncludeARM`, interactive, the maintainer's admin account -- needs Reader on the subscriptions/management groups and `AccessReview.Read.All`) |
> | `<your-subscription-display-name>` / `$Sub` | set by 0.0 -- the first `Enabled` subscription, held as its **GUID** (unambiguous; a display name can collide). Chosen: `00000000-0000-0000-0000-000000000001` (`Subscription A`) |
> | `<your-management-group-name>` / `$Mg` | set by 0.0 -- the tenant root management group (`ManagementGroupName` = tenant id) if visible, else the first listed. `-Name` takes the group NAME, never the display name. Chosen: `00000000-0000-0000-0000-000000000002` (the root group) |
> | `<your-access-review-definition-display-name>` / `$Def` | set by 0.0 -- the definition whose instances carry the most decisions, held as its **id**. Chosen: `00000000-0000-0000-0000-000000000003` (`oer-dv-ap - oer-dv-policy`) |
> | `$One` | set by 0.0 -- the instance of `$Def` with the most decisions. Chosen: `00000000-0000-0000-0000-000000000004` -- and it has **no** decisions, see 0.0. |
> | `$LogDir` | `%TEMP%\oer-arm-live` (verbose captures, both bundles, baseline) |
> | `$BaselineFile` | `%TEMP%\oer-arm-live\baseline-main.json` (written by 0.B, read by every "same as before" check) |
> | Fallback if `Omnicit` has no ARM surface at all | section 1 can be run against the sovereign-cloud (GCC High) tenant the Sprint 1.5 checklist section 4 used instead (`Connect-OER -TenantId <gcc-tenant> -Environment USGov -IncludeARM`) -- it has one subscription and one management group. Say so on every section 1 result line if you do. Section 3 stays on `Omnicit`. Not needed: `Omnicit` has an ARM surface. |
>
> Redact every real value before any of this is pasted into the repository. **This file is the
> redacted copy** -- every object id below is a `00000000-0000-0000-0000-0000000000NN` placeholder,
> and every subscription, management group and access review display name the tenant already owned
> is a neutral stand-in (`Subscription A`, `ManagementGroupA`, `Access Review A`, ...). The
> `oer-dv-*` names are test objects a checklist created and are kept, per
> `docs/live-verification/README.md`.

You need:

- **The built module from this branch.** The Setup block runs `./build.ps1 -Tasks build` on
  `fix/arm-throttle-and-review-pacing`; the output lands in
  `output/module/Omnicit.EntraRBAC/0.9.0/`.
- **An Azure tenant with a real ARM surface** -- at least one subscription with resource groups and
  role assignments, and ideally a management group hierarchy, so section 1's paging checks have
  more than one page to walk. 0.0 shows what `Omnicit` actually has.
- **At least one access review definition with instances and decisions.** A definition whose
  instances have no decisions at all leaves checks 3.3, 3.6 and part of 3.5 unanswerable; say so on
  the result line rather than ticking them. 0.0 shows the candidates and their decision counts.
- **Reader on the subscriptions and management groups you enumerate**, plus
  `AccessReview.Read.All` on the Graph side.
- **A previous run to compare against.** Check 0.B produces it.
- **An interactive (delegated) session is easiest**, because section 2 wants you watching the
  verbose stream.
- **A clean worktree** in `C:\Git\Omnicit.EntraRBAC` -- 0.B switches branches. `git status --short`
  must print nothing before you start.

Paste this block once per session. It sets the fixed values, defines the four helpers every check
below uses, rebuilds the branch, imports it and connects.

```powershell
$Alias        = 'Omnicit'
$Branch       = 'fix/arm-throttle-and-review-pacing'
$Repo         = 'C:\Git\Omnicit.EntraRBAC'
$LogDir       = Join-Path ([System.IO.Path]::GetTempPath()) 'oer-arm-live'
$BaselineFile = Join-Path $LogDir 'baseline-main.json'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogDir

# Import the NEWEST manifest under output/module, whatever version folder it landed in, and print
# the tell (version-prerelease, path, current git branch). A re-import drops the module's auth
# state, so every block that calls this also calls Connect-OER right after.
function Import-OerBuild {
    $Psd1 = Get-ChildItem (Join-Path $Repo 'output\module\Omnicit.EntraRBAC') -Recurse -Filter 'Omnicit.EntraRBAC.psd1' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Remove-Module Omnicit.EntraRBAC -Force -ErrorAction SilentlyContinue
    Import-Module $Psd1.FullName -Force
    $M = Get-Module Omnicit.EntraRBAC
    '{0} {1}-{2}  built {3:yyyy-MM-dd HH:mm}  branch={4}' -f $M.Name, $M.Version, $M.PrivateData.PSData.Prerelease,
        $Psd1.LastWriteTime, (git -C $Repo branch --show-current)
    $M.Path
}

# One object holding every count checks 1.3-1.11 compare. Run ONCE on main (0.B) and once on the
# branch (1.3-1.11 print the live number next to the baseline number). Same code path both times,
# so the comparison is like for like.
function Get-OerArmWalkCount {
    param([Parameter(Mandatory)][string]$Sub, [Parameter(Mandatory)][string]$Mg, [string]$Label = '')
    $M  = Get-Module Omnicit.EntraRBAC
    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $Mgs = @(Get-OERManagementGroup)
    [PSCustomObject]@{
        Label                   = $Label
        Build                   = '{0}-{1}' -f $M.Version, $M.PrivateData.PSData.Prerelease
        Subscriptions           = @(Get-OERSubscription).Count
        ManagementGroups        = $Mgs.Count
        ManagementGroupsUnique  = @($Mgs | Select-Object -ExpandProperty ResourceId | Sort-Object -Unique).Count
        MgRecurseChildren       = @((Get-OERManagementGroup -Name $Mg -Recurse).Children).Count
        ResourceGroups          = @(Get-OERResourceGroup -Subscription $Sub).Count
        Resources               = @(Get-OERResource -Subscription $Sub).Count
        RoleAssignments         = @(Get-OERRoleAssignment -Subscription $Sub).Count
        RoleDefinitions         = @(Get-OERRoleDefinition -Subscription $Sub).Count
        EligibleRoleAssignments = @(Get-OEREligibleRoleAssignment -Subscription $Sub).Count
        ActiveRoleAssignments   = @(Get-OERActiveRoleAssignment -Subscription $Sub).Count
        WalkSeconds             = [math]::Round($Sw.Elapsed.TotalSeconds, 1)
    }
}

# The full ARM inventory walk (check 1.1 / 1.12), timed with a Stopwatch instead of Measure-Command
# so the returned bundle object is never lost to a child scope. Export-OERInventory never writes
# into -OutputPath itself: it creates oer-inventory-<tenantId>-<stamp> beneath it, and BundlePath
# on the returned object is the only reliable way to address that folder afterwards.
function Invoke-OerExportWalk {
    param([Parameter(Mandatory)][string]$OutRoot, [string]$Label = '')
    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $Bundle = Export-OERInventory -OutputPath $OutRoot -Include RoleAssignments,RoleManagementPolicies -Force `
        -WarningVariable ExportWarnings
    $Sw.Stop()
    $Inv = Get-Content -Raw (Join-Path $Bundle.BundlePath 'inventory.json') | ConvertFrom-Json
    [PSCustomObject]@{
        Label                  = $Label
        BundlePath             = $Bundle.BundlePath
        ExportSeconds          = [math]::Round($Sw.Elapsed.TotalSeconds, 1)
        SkippedScopeWarnings   = @($ExportWarnings | Where-Object { "$_" -match 'Skipping scope|Could not enumerate Azure scopes' }).Count
        OtherWarnings          = @($ExportWarnings | Where-Object { "$_" -notmatch 'Skipping scope|Could not enumerate Azure scopes' }).Count
        RoleAssignments        = @($Inv.roleAssignments).Count
        RoleManagementPolicies = @($Inv.roleManagementPolicies).Count
    }
}

# Per-property population count over a set of rows: "Empty = 0" is the pass condition section 3
# reads. Presence is judged on the stringified value, so an empty array counts as empty and a
# datetime or a nested object counts as populated.
function Test-OerPopulated {
    param([Parameter(ValueFromPipeline)]$InputObject, [Parameter(Mandatory)][string[]]$Property)
    begin { $Rows = [System.Collections.Generic.List[object]]::new() }
    process { if ($null -ne $InputObject) { $Rows.Add($InputObject) } }
    end {
        foreach ($P in $Property) {
            $Empty = @($Rows | Where-Object { [string]::IsNullOrEmpty([string]$_.$P) }).Count
            [PSCustomObject]@{ Property = $P; Rows = $Rows.Count; Populated = $Rows.Count - $Empty; Empty = $Empty }
        }
    }
}

# Rebuild THIS branch (the output/ folder was stale when this file was written), import, connect.
git -C $Repo status --short          # must print nothing
git -C $Repo switch $Branch
Push-Location $Repo; ./build.ps1 -Tasks build; Pop-Location
Import-OerBuild
Connect-OER -TenantAlias $Alias -IncludeARM
```

`$LogDir` deliberately sits in the system temp directory, **not** in the repo. The verbose captures
below contain live subscription, resource and principal ids, and `docs/live-verification/README.md`
is explicit that unredacted output belongs only in `docs/live-verification/raw/` or a `*.log` beside
this file -- both git-ignored. Either of those would be safe too; temp is chosen so the captures
never enter the worktree at all, which means no ignore rule has to hold and there is nothing left in
the tree to clean up after T.2. **Never** write a capture anywhere else under the repo: no other
path is ignored, and a `git add .` would stage it.

| Placeholder | What it is |
|---|---|
| `<your-tenant-alias>` | The `Get-OERConfiguration` alias for the tenant under test. |
| `<your-subscription-display-name>` | A subscription with enough resource groups and role assignments to be worth walking. Held as a GUID in `$Sub`; `-Subscription` accepts either. |
| `<your-management-group-name>` | Any management group. Its list read is the `@nextLink` paging shape, which is the one section 1.11 exists for. `-Name` is the group NAME (`ManagementGroupName`), not the display name. |
| `<your-access-review-definition-display-name>` | A definition with instances, used by all of section 3. Held as an id in `$Def`; `-Definition` accepts either. |
| `$LogDir` | Where every verbose capture lands. Outside the repo, on purpose. |

- [x] **0.0 Discover what the tenant has, and pick the values every later block reads.** Lists
  every subscription, management group and access review definition the signed-in account can see,
  then assigns `$Sub`, `$Mg`, `$Def` and `$One`. The auto-pick rules are printed with the listing;
  override any variable by hand on the line after if a better candidate is visible (a subscription
  with more resources, a definition with more decisions). `-ErrorAction SilentlyContinue` on the
  decision probe is acceptable HERE and nowhere else in this file: it is a listing, not a check.

  ```powershell
  # --- ARM ---
  $Subs = @(Get-OERSubscription)
  $Subs | Format-Table DisplayName, State, SubscriptionId -AutoSize
  $Mgs  = @(Get-OERManagementGroup)
  $Mgs  | Format-Table DisplayName, ManagementGroupName, TenantId -AutoSize
  $Sub  = ($Subs | Where-Object State -eq 'Enabled' | Select-Object -First 1).SubscriptionId
  $Root = $Mgs | Where-Object { $_.ManagementGroupName -eq $_.TenantId } | Select-Object -First 1
  if (-not $Root) { $Root = $Mgs | Select-Object -First 1 }
  $Mg   = $Root.ManagementGroupName
  # --- Access reviews: every definition, its instance count, and decisions on up to 5 instances each ---
  $Defs = @(Get-OERAccessReviewDefinition -All -IncludeInstances)
  $Defs | Select-Object DisplayName, Status, @{ n = 'Instances'; e = { @($_.Instances).Count } }, AccessReviewDefinitionId |
      Format-Table -AutoSize
  $Candidates = foreach ($D in ($Defs | Where-Object { @($_.Instances).Count -gt 0 })) {
      foreach ($I in ($D.Instances | Select-Object -First 5)) {
          [PSCustomObject]@{
              Definition   = $D.DisplayName
              DefinitionId = $D.AccessReviewDefinitionId
              InstanceId   = $I.AccessReviewInstanceId
              Status       = $I.Status
              Decisions    = @(Get-OERAccessReviewInstanceDecision -Definition $D.AccessReviewDefinitionId `
                                   -Instance $I.AccessReviewInstanceId -ErrorAction SilentlyContinue).Count
          }
      }
  }
  $Candidates | Sort-Object Decisions -Descending | Format-Table -AutoSize
  $Pick = $Candidates | Sort-Object Decisions -Descending | Select-Object -First 1
  $Def  = $Pick.DefinitionId
  $One  = $Pick.InstanceId
  # --- what was picked ---
  [PSCustomObject]@{ Sub = $Sub; Mg = $Mg; Def = $Def; DefName = $Pick.Definition; One = $One; OneDecisions = $Pick.Decisions }
  ```

  **Expect:** at least one `Enabled` subscription, at least one management group, and a `$Pick`
  with `Decisions` greater than `0`. All four variables non-empty.
  **Failure looks like:** an empty `$Sub` or `$Mg` -- the tenant has no ARM surface the account can
  read; use the fallback tenant named in the environment note for section 1 and say so. An empty
  `$Def` or a `$Pick.Decisions` of `0` -- no definition has decided instances; 3.3, 3.6 and part of
  3.5 then read "cannot be verified" and the rest of section 3 still runs.
  **Record:** the four chosen values (redacted) and the decision count. Copy them into the
  environment table above as well.
  **Result:**
  ```powershell
> Import-OerBuild  
Omnicit.EntraRBAC 0.9.0-fix0001 built 2026-09-07 10:49 branch=fix/arm-throttle-and-review-pacing  
C:\Git\Omnicit.EntraRBAC\output\module\Omnicit.EntraRBAC\0.9.0\Omnicit.EntraRBAC.psm1  
> Connect-Oer -TenantAlias Omnicit -IncludeARM  
> # --- ARM ---  
> $Subs = @(Get-OERSubscription)  
> $Subs | Format-Table DisplayName, State, SubscriptionId -AutoSize  
  
DisplayName State SubscriptionId  
----------- ----- --------------  
Subscription A Enabled 00000000-0000-0000-0000-000000000001  
Subscription B Enabled 00000000-0000-0000-0000-000000000005  
Subscription C Enabled 00000000-0000-0000-0000-000000000006  
Subscription D Enabled 00000000-0000-0000-0000-000000000007  
Subscription E Enabled 00000000-0000-0000-0000-000000000008  
Subscription F Disabled 00000000-0000-0000-0000-000000000009  
Subscription G Enabled 00000000-0000-0000-0000-000000000010  
Subscription H Disabled 00000000-0000-0000-0000-000000000011  
Subscription I Enabled 00000000-0000-0000-0000-000000000012  
Subscription J Enabled 00000000-0000-0000-0000-000000000013  
Subscription K Enabled 00000000-0000-0000-0000-000000000014  
Subscription L Enabled 00000000-0000-0000-0000-000000000015  
Subscription M Enabled 00000000-0000-0000-0000-000000000016  
Subscription N Enabled 00000000-0000-0000-0000-000000000017  
  
> $Mgs = @(Get-OERManagementGroup)  
> $Mgs | Format-Table DisplayName, ManagementGroupName, TenantId -AutoSize  
  
DisplayName ManagementGroupName TenantId  
----------- ------------------- --------  
Tenant Root Group 00000000-0000-0000-0000-000000000002 00000000-0000-0000-0000-000000000002  
ManagementGroupA ManagementGroupA 00000000-0000-0000-0000-000000000002  
Management Group B ManagementGroupB 00000000-0000-0000-0000-000000000002  
ManagementGroupC ManagementGroupC 00000000-0000-0000-0000-000000000002  
ManagementGroupD ManagementGroupD 00000000-0000-0000-0000-000000000002  
  
> $Sub = ($Subs | Where-Object State -eq 'Enabled' | Select-Object -First 1).SubscriptionId  
> $Root = $Mgs | Where-Object { $_.ManagementGroupName -eq $_.TenantId } | Select-Object -First 1  
> if (-not $Root) { $Root = $Mgs | Select-Object -First 1 }  
> $Mg = $Root.ManagementGroupName  
> # --- Access reviews: every definition, its instance count, and decisions on up to 5 instances each ---  
> $Defs = @(Get-OERAccessReviewDefinition -All -IncludeInstances)   
> $Defs | Select-Object DisplayName, Status, @{ n = 'Instances'; e = { @($_.Instances).Count } }, AccessReviewDefinitionId |  
> Format-Table -AutoSize  
  
DisplayName Status Instances AccessReviewDefinitionId  
----------- ------ --------- ------------------------  
oer-dv-ap - oer-dv-policy InProgress 2 00000000-0000-0000-0000-000000000003  
Access Review A InProgress 2 00000000-0000-0000-0000-000000000018  
Access Review B Completed 1 00000000-0000-0000-0000-000000000019  
Access Review C InProgress 2 00000000-0000-0000-0000-000000000020  
Access Review D InProgress 3 00000000-0000-0000-0000-000000000021  
Access Review E InProgress 5 00000000-0000-0000-0000-000000000022  
  
> $Candidates = foreach ($D in ($Defs | Where-Object { @($_.Instances).Count -gt 0 })) {  
> foreach ($I in ($D.Instances | Select-Object -First 5)) {  
> [PSCustomObject]@{  
> Definition = $D.DisplayName  
> DefinitionId = $D.AccessReviewDefinitionId  
> InstanceId = $I.AccessReviewInstanceId  
> Status = $I.Status  
> Decisions = @(Get-OERAccessReviewInstanceDecision -Definition $D.AccessReviewDefinitionId `  
> -Instance $I.AccessReviewInstanceId -ErrorAction SilentlyContinue).Count  
> }  
> }  
> }  
> $Candidates | Sort-Object Decisions -Descending | Format-Table -AutoSize  
  
Definition DefinitionId InstanceId Status Decisions  
---------- ------------ ---------- ------ ---------  
oer-dv-ap - oer-dv-policy 00000000-0000-0000-0000-000000000003 00000000-0000-0000-0000-000000000004 NotStarted 0  
oer-dv-ap - oer-dv-policy 00000000-0000-0000-0000-000000000003 00000000-0000-0000-0000-000000000023 Completed 0  
Access Review A 00000000-0000-0000-0000-000000000018 00000000-0000-0000-0000-000000000024 NotStarted 0  
Access Review A 00000000-0000-0000-0000-000000000018 00000000-0000-0000-0000-000000000025 Completed 0  
Access Review B 00000000-0000-0000-0000-000000000019 00000000-0000-0000-0000-000000000019 Completed 0  
Access Review C 00000000-0000-0000-0000-000000000020 00000000-0000-0000-0000-000000000026 NotStarted 0  
Access Review C 00000000-0000-0000-0000-000000000020 00000000-0000-0000-0000-000000000027 Completed 0  
Access Review D 00000000-0000-0000-0000-000000000021 00000000-0000-0000-0000-000000000028 NotStarted 0  
Access Review D 00000000-0000-0000-0000-000000000021 00000000-0000-0000-0000-000000000029 Completed 0  
Access Review D 00000000-0000-0000-0000-000000000021 00000000-0000-0000-0000-000000000030 Completed 0  
Access Review E 00000000-0000-0000-0000-000000000022 00000000-0000-0000-0000-000000000031 NotStarted 0  
Access Review E 00000000-0000-0000-0000-000000000022 00000000-0000-0000-0000-000000000032 Completed 0  
Access Review E 00000000-0000-0000-0000-000000000022 00000000-0000-0000-0000-000000000033 Completed 0  
Access Review E 00000000-0000-0000-0000-000000000022 00000000-0000-0000-0000-000000000034 Completed 0  
Access Review E 00000000-0000-0000-0000-000000000022 00000000-0000-0000-0000-000000000035 Completed 0  
  
> $Pick = $Candidates | Sort-Object Decisions -Descending | Select-Object -First 1  
> $Def = $Pick.DefinitionId  
> $One = $Pick.InstanceId  
> # --- what was picked ---  
> [PSCustomObject]@{ Sub = $Sub; Mg = $Mg; Def = $Def; DefName = $Pick.Definition; One = $One; OneDecisions = $Pick.Decisions }  
  
Sub : 00000000-0000-0000-0000-000000000001  
Mg : 00000000-0000-0000-0000-000000000002  
Def : 00000000-0000-0000-0000-000000000003  
DefName : oer-dv-ap - oer-dv-policy  
One : 00000000-0000-0000-0000-000000000004  
OneDecisions : 0  
  
>
  ```

  **`$Sub`, `$Mg`, `$Def` and `$One` are all non-empty, and `$Pick.Decisions` is `0`.** That is the
  documented branch of this check's own **Failure looks like** clause, and it is taken: **no access
  review in this tenant has a single decision.** The candidate table above is exhaustive for the
  probe it ran, and the probe was exhaustive: 6 definitions declaring 15 instances between them,
  and all 15 rows are in the table with `Decisions 0` -- the `Select-Object -First 5` cap never bit,
  since the largest definition has exactly 5. The auto-pick therefore had nothing better to choose
  and returned the first row of a table sorted on a column that is `0` all the way down.

  Per this check's own clause: **3.3, 3.6 and part of 3.5 read "cannot be verified", and the rest of
  section 3 still runs.** 3.2 joins them on the same grounds once it is run: the picked definition
  is not a multi-stage review, so its stage collection is empty too. Those three boxes are marked
  `- [~]` below, not `- [x]`. Nothing here indicates a defect in the code -- it is a property of
  this tenant, and it is the reason issue #74's central risk leaves this run unproved. Section 4
  records that as a debt.

- [x] **0.B Capture the baseline on `main`, then come back.** Builds `main` into the same
  `output/` folder, imports it, connects, runs the exact walk the branch will run (1.3--1.11 through
  `Get-OerArmWalkCount`, 1.1/1.12 through `Invoke-OerExportWalk`), writes both to `$BaselineFile`,
  then rebuilds and re-imports the branch. The two helper functions are defined in this session and
  survive the module swap, so the same code measures both sides. **Run this AFTER 0.0** -- it reads
  `$Sub` and `$Mg`.

  ```powershell
  git -C $Repo status --short          # must still print nothing
  git -C $Repo switch main
  Push-Location $Repo; ./build.ps1 -Tasks build; Pop-Location
  Import-OerBuild                      # expect: 0.9.0-<something that is NOT fix0001>, branch=main
  Connect-OER -TenantAlias $Alias -IncludeARM
  $Baseline       = Get-OerArmWalkCount -Sub $Sub -Mg $Mg -Label 'main'
  $BaselineExport = Invoke-OerExportWalk -OutRoot (Join-Path $LogDir 'bundle-before') -Label 'main'
  $Baseline | Add-Member -NotePropertyName ExportSeconds          -NotePropertyValue $BaselineExport.ExportSeconds
  $Baseline | Add-Member -NotePropertyName ExportSkippedScopes    -NotePropertyValue $BaselineExport.SkippedScopeWarnings
  $Baseline | Add-Member -NotePropertyName ExportRoleAssignments  -NotePropertyValue $BaselineExport.RoleAssignments
  $Baseline | Add-Member -NotePropertyName ExportRolePolicies     -NotePropertyValue $BaselineExport.RoleManagementPolicies
  $Baseline | Add-Member -NotePropertyName ExportBundlePath       -NotePropertyValue $BaselineExport.BundlePath
  $Baseline | ConvertTo-Json | Set-Content -Path $BaselineFile -Encoding utf8
  $Baseline | Format-List *
  # --- back to the branch ---
  git -C $Repo switch $Branch
  Push-Location $Repo; ./build.ps1 -Tasks build; Pop-Location
  Import-OerBuild                      # expect: 0.9.0-fix0001, branch=fix/arm-throttle-and-review-pacing
  Connect-OER -TenantAlias $Alias -IncludeARM
  ```

  If the session is ever restarted after this point, reload the baseline instead of re-measuring it:
  `$Baseline = Get-Content -Raw $BaselineFile | ConvertFrom-Json`.

  **Expect:** two clean builds, the `main` import showing a prerelease label that is NOT `fix0001`,
  the branch import showing `fix0001`, and a `$Baseline` with every count populated and
  `ExportRoleAssignments` greater than `0`.
  **Failure looks like:** a build error on either side (stop; nothing below is comparable), or a
  `$Baseline` count of `0` where 0.0 showed objects -- that is a scope or permission problem to fix
  BEFORE measuring the branch, not a baseline.
  **Record:** the full `$Baseline | Format-List *` output. **Redact the tenant id inside
  `ExportBundlePath`.**
  **Result:**
  ```powershell
Done /build/Create_changelog_release_output 00:00:01.3468268  
Done /build 00:00:15.8431619  
Build succeeded. 7 tasks, 0 errors, 0 warnings 00:00:24.8392399  
> Import-OerBuild  
Omnicit.EntraRBAC 0.9.0-preview0001 built 2026-09-07 13:12 branch=main  
C:\Git\Omnicit.EntraRBAC\output\module\Omnicit.EntraRBAC\0.9.0\Omnicit.EntraRBAC.psm1  
> Connect-OER -TenantAlias $Alias -IncludeARM  
> $Baseline = Get-OerArmWalkCount -Sub $Sub -Mg $Mg -Label 'main'  
> $BaselineExport = Invoke-OerExportWalk -OutRoot (Join-Path $LogDir 'bundle-before') -Label 'main'  
> $Baseline | Add-Member -NotePropertyName ExportSeconds -NotePropertyValue $BaselineExport.ExportSeconds  
> $Baseline | Add-Member -NotePropertyName ExportSkippedScopes -NotePropertyValue $BaselineExport.SkippedScopeWarnings  
> $Baseline | Add-Member -NotePropertyName ExportRoleAssignments -NotePropertyValue $BaselineExport.RoleAssignments  
> $Baseline | Add-Member -NotePropertyName ExportRolePolicies -NotePropertyValue $BaselineExport.RoleManagementPolicies  
> $Baseline | Add-Member -NotePropertyName ExportBundlePath -NotePropertyValue $BaselineExport.BundlePath  
> $Baseline | ConvertTo-Json | Set-Content -Path $BaselineFile -Encoding utf8  
> $Baseline | Format-List *  
  
Label : main  
Build : 0.9.0-preview0001  
Subscriptions : 14  
ManagementGroups : 5  
ManagementGroupsUnique : 5  
MgRecurseChildren : 6  
ResourceGroups : 0  
Resources : 0  
RoleAssignments : 9  
RoleDefinitions : 940  
EligibleRoleAssignments : 1  
ActiveRoleAssignments : 9  
WalkSeconds : 8,2  
ExportSeconds : 181,2  
ExportSkippedScopes : 0  
ExportRoleAssignments : 75  
ExportRolePolicies : 17862  
ExportBundlePath : C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541  
  
>  Push-Location $Repo; ./build.ps1 -Tasks build; Pop-Location
...
Done /build/Create_changelog_release_output 00:00:01.0841293  
Done /build 00:00:08.6959720  
Build succeeded. 7 tasks, 0 errors, 0 warnings 00:00:09.2996889  
> Import-OerBuild # expect: 0.9.0-fix0001, branch=fix/arm-throttle-and-review-pacing  
Omnicit.EntraRBAC 0.9.0-fix0001 built 2026-09-07 13:17 branch=fix/arm-throttle-and-review-pacing  
C:\Git\Omnicit.EntraRBAC\output\module\Omnicit.EntraRBAC\0.9.0\Omnicit.EntraRBAC.psm1  
> Connect-OER -TenantAlias $Alias -IncludeARM  
>

  ```

- [x] **0.1 Prove you are running THIS branch's build before measuring anything.** Two offline
  tells, neither costing a tenant call: the module version, and the three throttle constants that
  did not exist in the ARM wrapper before this branch.

  ```powershell
  $M = Get-Module Omnicit.EntraRBAC
  "$($M.Name) $($M.Version)"
  $M.PrivateData.PSData.Prerelease
  $M.Path
  git -C $Repo branch --show-current
  git -C $Repo log -1 --format='%h %cd'
  @(Select-String -Path $M.Path -Pattern 'function Get-ArmThrottleDelay').Count
  @(Select-String -Path $M.Path -Pattern 'function Get-ArmRetryAfterHeaderValue').Count
  @(Select-String -Path $M.Path -Pattern 'function Invoke-ArmCallWithBackoff').Count
  ```

  **Expect:** version `0.9.0`. `$M.Version` is a three-part `[version]` and NEVER shows a prerelease
  label, so do not look for one there; the label lives in `$M.PrivateData.PSData.Prerelease` and on
  this branch reads `fix0001` at `e8fb1f5` (the `fix` comes from the branch prefix, the digits
  track the commit count -- read it as "present and `fix`-prefixed", not as a fixed value). Then a
  path ending `output\module\Omnicit.EntraRBAC\0.9.0\Omnicit.EntraRBAC.psm1`; the branch name; a
  HEAD of `e8fb1f5` or later; and `1` from each of the three counts.
  **Failure looks like:** a `0` from any count -- you are running an older build or an installed
  copy from `PSModulePath`. Rebuild and re-import before running anything else, or every result
  below describes the wrong code.
  **Result:**
  ```powershell
> $M = Get-Module Omnicit.EntraRBAC  
> "$($M.Name) $($M.Version)"  
Omnicit.EntraRBAC 0.9.0  
> $M.PrivateData.PSData.Prerelease  
fix0001  
> $M.Path  
C:\Git\Omnicit.EntraRBAC\output\module\Omnicit.EntraRBAC\0.9.0\Omnicit.EntraRBAC.psm1  
> git -C $Repo branch --show-current  
fix/arm-throttle-and-review-pacing  
> git -C $Repo log -1 --format='%h %cd'  
b58f7a4 Mon Sep 7 11:33:37 2026 +0200  
> @(Select-String -Path $M.Path -Pattern 'function Get-ArmThrottleDelay').Count  
1  
> @(Select-String -Path $M.Path -Pattern 'function Get-ArmRetryAfterHeaderValue').Count  
1  
> @(Select-String -Path $M.Path -Pattern 'function Invoke-ArmCallWithBackoff').Count  
1  
>
  ```

- [x] **0.2 Connect, and confirm the session carries an ARM token.**

  ```powershell
  Connect-OER -TenantAlias $Alias -IncludeARM
  Get-OERSubscription | Select-Object -First 1 | Format-List DisplayName, ResourceId
  ```

  **Expect:** one subscription row with both fields populated. `DisplayName` and `ResourceId` are
  the names `ConvertTo-OERSubscription` actually emits -- `Format-List` silently prints nothing for
  a property that does not exist, so a mistyped name here would make this check unfailable rather
  than failing. If this errors on the token, nothing below is runnable.
  **Redact the subscription GUID inside the pasted `ResourceId` path; keep the path shape.**
  **Result:**
  ```powershell
> Get-OERSubscription | Select-Object -First 1 | Format-List DisplayName, ResourceId  
  
DisplayName : Subscription A  
ResourceId : /subscriptions/00000000-0000-0000-0000-000000000001
  ```

---

### 1. The full ARM walk -- the primary evidence

Read "Why this checklist is a full walk and not a provoked 429" above before running this section.
The short version: one workstation issues roughly two requests a second against an ARM bucket sized
in the hundreds, so a throttle cannot be provoked on demand; the same arithmetic parked PR #77's
checklist. What a full walk DOES prove is that the widened `{ StatusCode; Content; Headers }` shape,
the new backoff wrapper and the new per-call budget did not break the ordinary path in any of the
ARM cmdlets, across many pages.

**Run 1.1 first, then 1.3 once** -- `$After` from 1.3 is what 1.4--1.11 print their live number
from, so those blocks cost no further tenant calls; each of them ALSO re-runs its own cmdlet once so
the result block shows the live call, not just a cached number.

- [x] **1.1 The whole ARM inventory walk, timed.** `Export-OERInventory` with both Azure sections
  enumerates the entire scope tree -- every management group and every subscription it can reach --
  and issues one `Get-OERInventory` per scope. It is the longest ARM walk the module can make, which
  makes it the best single exercise of the paging path. `Invoke-OerExportWalk` is the same helper
  0.B measured `main` with, and it KEEPS the returned bundle object (`BundlePath`) for 1.12.

  ```powershell
  $AfterExport = Invoke-OerExportWalk -OutRoot (Join-Path $LogDir 'bundle-after') -Label 'branch'
  $AfterExport | Format-List *
  [PSCustomObject]@{
      ElapsedSeconds  = '{0} (main: {1})' -f $AfterExport.ExportSeconds, $Baseline.ExportSeconds
      SkippedScopes   = '{0} (main: {1})' -f $AfterExport.SkippedScopeWarnings, $Baseline.ExportSkippedScopes
  }
  ```

  **Expect:** completes without a terminating error; the elapsed time is in the same range as the
  `main` run; and `BundlePath` prints an absolute path ending `oer-inventory-<tenantId>-<stamp>`.
  Warnings naming individual skipped scopes are normal if your account lacks Reader somewhere --
  the skipped count must match the `main` run, so check 1.12 compares like with like.
  **Failure looks like:** an `ArmTransportError`, an unexpected 5xx, or a run that is dramatically
  slower than the `main` baseline (which would suggest the backoff is waiting when it should not).
  An empty `BundlePath` means the export did not write -- fix that before running 1.12 rather than
  guessing the folder name.
  **Record:** the elapsed seconds and the count of scope-skipped warnings, both sides. **Redact the
  tenant id in the pasted `BundlePath`.**
  **Result:**
  ```powershell
> [PSCustomObject]@{  
> ElapsedSeconds = '{0} (main: {1})' -f $AfterExport.ExportSeconds, $Baseline.ExportSeconds  
> SkippedScopes = '{0} (main: {1})' -f $AfterExport.SkippedScopeWarnings, $Baseline.ExportSkippedScopes  
> }  
  
ElapsedSeconds SkippedScopes  
-------------- -------------  
172,3 (main: 181,2) 0 (main: 0)
  ```

- [x] **1.2 No new error records.** Clear `$Error` FIRST, then re-run one ARM read, then count.
  This is the check that catches a newly noisy path -- Sprint 1's live run found 288 phantom error
  records exactly this way.

  ```powershell
  $Error.Clear()
  $null = Get-OERInventory -Include RoleAssignments -Subscription $Sub -IncludeARM
  $Error.Count
  $Error | Select-Object -First 5 | ForEach-Object { $_.FullyQualifiedErrorId }
  ```

  **Expect:** `0`. The widened response shape is read by the status logic, the backoff helper and
  `Convert-ArmHttpException`; a shape mismatch in any of them would surface here as a swallowed
  error record even on a run that returned data.
  **Failure looks like:** any non-zero count on a run that otherwise succeeded.
  **Result:**
  ```powershell
> $Error.Clear()  
> $null = Get-OERInventory -Include RoleAssignments -Subscription $Sub -IncludeARM  
> $Error.Count  
0  
> $Error | Select-Object -First 5 | ForEach-Object { $_.FullyQualifiedErrorId }  
>
  ```

- [x] **1.3 `Get-OERSubscription` -- and the whole branch walk in one object.** This is the block
  that runs `Get-OerArmWalkCount` on the branch; 1.4--1.11 read `$After` from it.

  ```powershell
  $After = Get-OerArmWalkCount -Sub $Sub -Mg $Mg -Label 'branch'
  # side by side, every count, delta must be 0 on every row
  foreach ($P in 'Subscriptions','ManagementGroups','ManagementGroupsUnique','MgRecurseChildren','ResourceGroups',
                 'Resources','RoleAssignments','RoleDefinitions','EligibleRoleAssignments','ActiveRoleAssignments') {
      [PSCustomObject]@{ Count = $P; Main = $Baseline.$P; Branch = $After.$P; Delta = $After.$P - $Baseline.$P }
  }
  '{0} s on the branch, {1} s on main' -f $After.WalkSeconds, $Baseline.WalkSeconds
  @(Get-OERSubscription).Count
  ```

  **Expect:** `Delta` `0` on every row, and a subscription count equal to `$Baseline.Subscriptions`.
  **Result:**
  ```powershell
> $After = Get-OerArmWalkCount -Sub $Sub -Mg $Mg -Label 'branch'  
> # side by side, every count, delta must be 0 on every row  
> foreach ($P in 'Subscriptions','ManagementGroups','ManagementGroupsUnique','MgRecurseChildren','ResourceGroups',  
> 'Resources','RoleAssignments','RoleDefinitions','EligibleRoleAssignments','ActiveRoleAssignments') {  
> [PSCustomObject]@{ Count = $P; Main = $Baseline.$P; Branch = $After.$P; Delta = $After.$P - $Baseline.$P }  
> }  
  
Count Main Branch Delta  
----- ---- ------ -----  
Subscriptions 14 14 0  
ManagementGroups 5 5 0  
ManagementGroupsUnique 5 5 0  
MgRecurseChildren 6 6 0  
ResourceGroups 0 0 0  
Resources 0 0 0  
RoleAssignments 9 9 0  
RoleDefinitions 940 940 0  
EligibleRoleAssignments 1 1 0  
ActiveRoleAssignments 9 9 0  
  
> '{0} s on the branch, {1} s on main' -f $After.WalkSeconds, $Baseline.WalkSeconds  
5,9 s on the branch, 8,2 s on main  
> @(Get-OERSubscription).Count  
14  
>
  ```

- [x] **1.4 `Get-OERManagementGroup`.**

  ```powershell
  @(Get-OERManagementGroup).Count
  'main: {0}' -f $Baseline.ManagementGroups
  ```

  **Expect:** the same count as before the branch.
  **Result:**
  ```powershell
> @(Get-OERManagementGroup).Count  
5  
> 'main: {0}' -f $Baseline.ManagementGroups  
main: 5  
>
  ```

- [x] **1.5 `Get-OERResourceGroup`.**

  ```powershell
  @(Get-OERResourceGroup -Subscription $Sub).Count
  'main: {0}' -f $Baseline.ResourceGroups
  ```

  **Expect:** the same count as before the branch.
  **Result:**
  ```powershell
> @(Get-OERResourceGroup -Subscription $Sub).Count  
0  
> 'main: {0}' -f $Baseline.ResourceGroups  
main: 0  
>
  ```

- [x] **1.6 `Get-OERResource`.** The heaviest list read in the module, and the one most likely to
  page more than once.

  ```powershell
  @(Get-OERResource -Subscription $Sub).Count
  'main: {0}' -f $Baseline.Resources
  ```

  **Expect:** the same count as before the branch.
  **Result:**
  ```powershell
> @(Get-OERResource -Subscription $Sub).Count  
0  
> 'main: {0}' -f $Baseline.Resources  
main: 0  
>
  ```

  A real match, and a weak one. The subscription 0.0 picked holds no resources, so "the heaviest
  list read in the module, and the one most likely to page more than once" walked a single empty
  page here -- `0` against a baseline of `0`. The delta is legitimate; it is not paging evidence.
  Same for 1.5. Section 4 records it.

- [x] **1.7 `Get-OERRoleAssignment`.**

  ```powershell
  @(Get-OERRoleAssignment -Subscription $Sub).Count
  'main: {0}' -f $Baseline.RoleAssignments
  ```

  **Expect:** the same count as before the branch.
  **Result:**
  ```powershell
> @(Get-OERRoleAssignment -Subscription $Sub).Count  
9  
> 'main: {0}' -f $Baseline.RoleAssignments  
main: 9  
>
  ```

- [x] **1.8 `Get-OERRoleDefinition`.**

  ```powershell
  @(Get-OERRoleDefinition -Subscription $Sub).Count
  'main: {0}' -f $Baseline.RoleDefinitions
  ```

  **Expect:** the same count as before the branch.
  **Result:**
  ```powershell
> @(Get-OERRoleDefinition -Subscription $Sub).Count  
940  
> 'main: {0}' -f $Baseline.RoleDefinitions  
main: 940  
>
  ```

- [x] **1.9 `Get-OEREligibleRoleAssignment`.** An Azure PIM read, pinned to a different api-version
  from the plain RBAC reads above.

  ```powershell
  @(Get-OEREligibleRoleAssignment -Subscription $Sub).Count
  'main: {0}' -f $Baseline.EligibleRoleAssignments
  ```

  **Expect:** the same count as before the branch. A `0` on both sides is a valid match if the
  subscription has no PIM eligibility -- say so.
  **Result:**
  ```powershell
> @(Get-OEREligibleRoleAssignment -Subscription $Sub).Count  
1  
> 'main: {0}' -f $Baseline.EligibleRoleAssignments  
main: 1  
>
  ```

- [x] **1.10 `Get-OERActiveRoleAssignment`.**

  ```powershell
  @(Get-OERActiveRoleAssignment -Subscription $Sub).Count
  'main: {0}' -f $Baseline.ActiveRoleAssignments
  ```

  **Expect:** the same count as before the branch.
  **Result:**
  ```powershell
> @(Get-OERActiveRoleAssignment -Subscription $Sub).Count  
9   
> 'main: {0}' -f $Baseline.ActiveRoleAssignments  
main: 9  
>
  ```

- [x] **1.11 The `@nextLink` paging shape specifically.** Management group lists page on
  `@nextLink`, not `nextLink`. The wrapper reads both, and the backoff now sits between the two
  reads on that loop, so this is the one shape a single-page test would never exercise.

  ```powershell
  $Mgs = Get-OERManagementGroup
  @($Mgs).Count
  # ResourceId is the id ConvertTo-OERManagementGroup emits (an ARM-scoped shape exposes the ARM
  # path as ResourceId, never a bare Id), and it is unique per management group. No
  # -ErrorAction SilentlyContinue: a name that stopped resolving must fail loudly here rather than
  # yield nothing and be read as a duplicate-page finding.
  @($Mgs | Select-Object -ExpandProperty ResourceId | Sort-Object -Unique).Count
  'main: {0} total, {1} unique, {2} children under {3}' -f $Baseline.ManagementGroups, $Baseline.ManagementGroupsUnique, $Baseline.MgRecurseChildren, $Mg
  $Tree = Get-OERManagementGroup -Name $Mg -Expand -Recurse
  $Tree | Format-List DisplayName, ManagementGroupName, ResourceId, ParentName
  @($Tree.Children).Count
  $Tree.Children | Select-Object name, displayName, type | Format-Table -AutoSize
  ```

  **Expect:** the same total as check 1.4, no duplicate ids (a duplicate would mean a page was
  aggregated twice), and the recursive read returns its children -- the same number `main` saw.
  Every page aggregated, count unchanged.
  **Failure looks like:** a count that differs from 1.4, or a unique-id count lower than the total.
  **Redact every GUID in the pasted `ResourceId` paths and child names (a root management group's
  name IS the tenant id).**
  **Result:**
  ```powershell
> $Mgs = Get-OERManagementGroup  
> @($Mgs).Count  
5  
> # ResourceId is the id ConvertTo-OERManagementGroup emits (an ARM-scoped shape exposes the ARM  
> # path as ResourceId, never a bare Id), and it is unique per management group. No  
> # -ErrorAction SilentlyContinue: a name that stopped resolving must fail loudly here rather than   
> # yield nothing and be read as a duplicate-page finding.  
> @($Mgs | Select-Object -ExpandProperty ResourceId | Sort-Object -Unique).Count  
5  
> 'main: {0} total, {1} unique, {2} children under {3}' -f $Baseline.ManagementGroups, $Baseline.ManagementGroupsUnique, $Baseline.MgRecurseChildren, $Mg  
main: 5 total, 5 unique, 6 children under 00000000-0000-0000-0000-000000000002  
> $Tree = Get-OERManagementGroup -Name $Mg -Expand -Recurse  
> $Tree | Format-List DisplayName, ManagementGroupName, ResourceId, ParentName  
  
DisplayName : Tenant Root Group  
ManagementGroupName : 00000000-0000-0000-0000-000000000002  
ResourceId : /providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000002  
ParentName :  
  
> @($Tree.Children).Count  
6  
> $Tree.Children | Select-Object name, displayName, type | Format-Table -AutoSize  
  
name displayName type  
---- ----------- ----  
ManagementGroupA ManagementGroupA Microsoft.Management/managementGroups  
ManagementGroupD ManagementGroupD Microsoft.Management/managementGroups  
ManagementGroupC ManagementGroupC Microsoft.Management/managementGroups  
ManagementGroupB Management Group B Microsoft.Management/managementGroups  
00000000-0000-0000-0000-000000000016 Subscription M /subscriptions  
00000000-0000-0000-0000-000000000017 Subscription N /subscriptions  
   
>
  ```

- [x] **1.12 The exported bundle matches the previous export.** Compare the item counts, not the
  bytes -- an export carries timestamps. `$AfterExport` is the object 1.1 kept; the counts were read
  out of `inventory.json` inside `BundlePath`, never from `<OutputPath>/inventory.json`, which
  `Export-OERInventory` never writes.

  ```powershell
  # Lost $AfterExport to a new session? Recover the folder instead of guessing its stamp:
  #   $BundlePath = (Get-ChildItem (Join-Path $LogDir 'bundle-after') -Directory | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
  #   $Inv = Get-Content -Raw (Join-Path $BundlePath 'inventory.json') | ConvertFrom-Json
  [PSCustomObject]@{ Count = 'roleAssignments';        Main = $Baseline.ExportRoleAssignments; Branch = $AfterExport.RoleAssignments;        Delta = $AfterExport.RoleAssignments - $Baseline.ExportRoleAssignments }
  [PSCustomObject]@{ Count = 'roleManagementPolicies'; Main = $Baseline.ExportRolePolicies;    Branch = $AfterExport.RoleManagementPolicies; Delta = $AfterExport.RoleManagementPolicies - $Baseline.ExportRolePolicies }
  Get-ChildItem $AfterExport.BundlePath -Filter '*.json' | Select-Object Name, Length
  ```

  **Expect:** `Delta` `0` on both rows -- identical to the same two counts from the `main` export
  of the same tenant.
  **Failure looks like:** either count LOWER than the baseline. That is the shape of a truncated
  enumeration, which is the outcome the "enforce bounds at the decision to wait, never by stopping a
  paging loop" rule exists to prevent -- a short list read as drift is what makes the apply engine
  write.
  **Record:** both counts, and both baseline counts.
  **Result:**
  ```powershell
> [PSCustomObject]@{ Count = 'roleAssignments'; Main = $Baseline.ExportRoleAssignments; Branch = $AfterExport.RoleAssignments; Delta = $AfterExport.RoleAssignments - $Baseline.ExportRoleAssignments }  
  
Count Main Branch Delta  
----- ---- ------ -----  
roleAssignments 75 75 0  
  
> [PSCustomObject]@{ Count = 'roleManagementPolicies'; Main = $Baseline.ExportRolePolicies; Branch = $AfterExport.RoleManagementPolicies; Delta = $AfterExport.RoleManagementPolicies - $Baseline.ExportRolePolicies }  
  
Count Main Branch Delta  
----- ---- ------ -----  
roleManagementPolicies 17862 17862 0  
  
> Get-ChildItem $AfterExport.BundlePath -Filter '*.json' | Select-Object Name, Length  
  
Name Length  
---- ------  
inventory.json 10707082  
roleAssignments.json 15193  
roleManagementPolicies.json 10155001  
schema.json 22605  
scopeHierarchy.json 4129  
  
>
  ```

---

### 2. The verbose stream carries the new diagnostics and leaks nothing

- [x] **2.1 One request line per request, and no `Throttled` line on a healthy tenant.**

  ```powershell
  $Verbose = (Get-OERResource -Subscription $Sub -Verbose 4>&1) |
      Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
      ForEach-Object { $_.Message }
  $Verbose | Set-Content -Path (Join-Path $LogDir 'verbose-arm.log')
  @($Verbose).Count
  @($Verbose | Where-Object { $_ -match '^\[Invoke-OERArmRequest\] GET ' }).Count
  @($Verbose | Where-Object { $_ -match 'Throttled' }).Count
  # the request lines themselves, so the shape is on record (redact the subscription GUID in each path)
  $Verbose | Where-Object { $_ -match '^\[Invoke-OERArmRequest\] ' }
  ```

  **Expect:** one or more `[Invoke-OERArmRequest] GET <path>` lines -- one per request, so more than
  one if the read paged -- and `0` `Throttled` lines. A `Throttled` line on a healthy tenant would
  mean the backoff is firing on something that is not a throttle.
  **Record:** both counts.
  **Result:**
  ```powershell
> $Verbose = (Get-OERResource -Subscription $Sub -Verbose 4>&1) |  
> Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |  
> ForEach-Object { $_.Message }  
> $Verbose | Set-Content -Path (Join-Path $LogDir 'verbose-arm.log')  
> @($Verbose).Count  
2  
> @($Verbose | Where-Object { $_ -match '^\[Invoke-OERArmRequest\] GET ' }).Count  
1  
> @($Verbose | Where-Object { $_ -match 'Throttled' }).Count  
0  
> # the request lines themselves, so the shape is on record (redact the subscription GUID in each path)  
> $Verbose | Where-Object { $_ -match '^\[Invoke-OERArmRequest\] ' }  
[Invoke-OERArmRequest] GET /subscriptions/00000000-0000-0000-0000-000000000001/resources?api-version=2025-04-01  
>
  ```

- [x] **2.2 No header material in the captured stream.** This is the one live check the mocked suite
  structurally cannot make: its mocks supply the headers themselves, so it can only prove the module
  does not print the headers IT was handed. Here they come from real ARM.

  ```powershell
  $Text = (Get-Content -Raw (Join-Path $LogDir 'verbose-arm.log'))
  $Text.Length
  $Text -match '(?i)bearer|x-ms-request-id|x-ms-correlation|client-request-id|x-ms-ratelimit'
  # if True: the LINE NUMBER and the pattern only -- never the line
  if ($Text -match '(?i)bearer|x-ms-request-id|x-ms-correlation|client-request-id|x-ms-ratelimit') {
      Select-String -Path (Join-Path $LogDir 'verbose-arm.log') -Pattern '(?i)bearer|x-ms-request-id|x-ms-correlation|client-request-id|x-ms-ratelimit' |
          Select-Object LineNumber, @{ n = 'Pattern'; e = { $_.Matches[0].Value } }
  }
  ```

  **Expect:** `False`, and a non-zero `Length` (an empty capture would make `False` vacuous).
  **Failure looks like:** `True`. If it is `True`, do NOT paste the matching line. Record the fact,
  the pattern that matched, and the line number only.
  **Result:**
  ```powershell
> $Text = (Get-Content -Raw (Join-Path $LogDir 'verbose-arm.log'))  
> $Text.Length  
214  
> $Text -match '(?i)bearer|x-ms-request-id|x-ms-correlation|client-request-id|x-ms-ratelimit'  
False  
> # if True: the LINE NUMBER and the pattern only -- never the line  
> if ($Text -match '(?i)bearer|x-ms-request-id|x-ms-correlation|client-request-id|x-ms-ratelimit') {  
> Select-String -Path (Join-Path $LogDir 'verbose-arm.log') -Pattern '(?i)bearer|x-ms-request-id|x-ms-correlation|client-request-id|x-ms-ratelimit' |  
> Select-Object LineNumber, @{ n = 'Pattern'; e = { $_.Matches[0].Value } }  
> }  
>
  ```

  `False`, over a `Length` of 214 -- non-zero, so the guard is not vacuous. Note what those 214
  characters are, though: 2.1 recorded 2 verbose records and one `[Invoke-OERArmRequest] GET` line,
  so this is one ARM request that was not paged, not retried and did not fail. What is proved is
  that the happy path of a single request prints no header name. A paged read, a retry and an error
  path are all unexamined, and section 4 records that the error path is the one that has leaked
  header material in this module before.

- [x] **2.3 The token itself is not in the stream.** Separate from 2.2 on purpose: 2.2 looks for
  header NAMES, this looks for the credential.

  ```powershell
  $Text -match 'eyJ[A-Za-z0-9_-]{10,}'
  # if True: line number only
  if ($Text -match 'eyJ[A-Za-z0-9_-]{10,}') {
      Select-String -Path (Join-Path $LogDir 'verbose-arm.log') -Pattern 'eyJ[A-Za-z0-9_-]{10,}' | Select-Object LineNumber
  }
  ```

  **Expect:** `False`. **Do not paste the token, and do not paste a match, into the result line.**
  Record `False`, or -- if it is `True` -- record only that it matched and at which line, then treat
  it as a credential incident: rotate per `docs/live-verification/README.md`, do not merely redact.
  **Result:**
  ```powershell
> $Text -match 'eyJ[A-Za-z0-9_-]{10,}'  
False  
> # if True: line number only  
> if ($Text -match 'eyJ[A-Za-z0-9_-]{10,}') {  
> Select-String -Path (Join-Path $LogDir 'verbose-arm.log') -Pattern 'eyJ[A-Za-z0-9_-]{10,}' | Select-Object LineNumber  
> }  
>
  ```

---

### 3. The access review reads still return every field

The `$select` on the instance and decision reads is the whole of issue #74's change, and its failure
mode is silent. Graph returns ONLY what was asked for, so a field the select forgot arrives absent,
the converter reads `$null`, and no error is raised anywhere. The unit suite has two tests that
parse the select out of the URI and trim their fixtures to match, which closes most of this -- but
they still decide for themselves what Graph would have returned. These checks read the real thing.

Every block prints two things: a `Format-List *` of the first rows, so the shape is on record, and a
`Test-OerPopulated` table over ALL rows, where `Empty` is the number to read. **Redact the
definition id, every instance id, every principal/resource id and every display name that is a
person in the pasted output.**

- [x] **3.1 The list read returns a fully populated instance.** **`Scope` is the field a careless
  `$select` would null out, and this is the single most important line in this checklist.**

  ```powershell
  $Instances = @(Get-OERAccessReviewInstance -Definition $Def)
  $Instances.Count
  $Instances | Select-Object -First 2 | Format-List *
  $Instances | Test-OerPopulated -Property AccessReviewInstanceId, Status, StartDateTime, EndDateTime, AccessReviewDefinitionId, Scope
  ```

  **Expect:** `Empty` `0` on all six rows -- `AccessReviewInstanceId`, `Status`, `StartDateTime`,
  `EndDateTime`, `AccessReviewDefinitionId` and `Scope` populated on every instance.
  **Failure looks like:** any of the six with `Empty` above `0`. `Scope` empty means the select
  dropped it; the other five would mean the same for their own field. `AccessReviewDefinitionId` is
  the one field that does NOT come from Graph -- the cmdlet supplies it -- so an empty one there is
  a different bug.
  **Result:**
  ```powershell
> $Instances = @(Get-OERAccessReviewInstance -Definition $Def)  
> $Instances.Count  
2  
> $Instances | Select-Object -First 2 | Format-List *  
  
AccessReviewInstanceId : 00000000-0000-0000-0000-000000000004  
Status : NotStarted  
StartDateTime : 2026-12-06 21:59:59  
EndDateTime : 2026-12-27 21:59:59  
AccessReviewDefinitionId : 00000000-0000-0000-0000-000000000003  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000036' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000037')  
Id : 00000000-0000-0000-0000-000000000004  
DefinitionId : 00000000-0000-0000-0000-000000000003  
  
AccessReviewInstanceId : 00000000-0000-0000-0000-000000000023  
Status : Completed  
StartDateTime : 2026-09-06 21:59:59  
EndDateTime : 2026-10-01 21:59:59  
AccessReviewDefinitionId : 00000000-0000-0000-0000-000000000003  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000036' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000037')  
Id : 00000000-0000-0000-0000-000000000023  
DefinitionId : 00000000-0000-0000-0000-000000000003  
  
> $Instances | Test-OerPopulated -Property AccessReviewInstanceId, Status, StartDateTime, EndDateTime, AccessReviewDefinitionId, Scope  
  
Property Rows Populated Empty  
-------- ---- --------- -----  
AccessReviewInstanceId 2 2 0  
Status 2 2 0  
StartDateTime 2 2 0  
EndDateTime 2 2 0  
AccessReviewDefinitionId 2 2 0  
Scope 2 2 0  
  
>
  ```

- [~] **3.2 `-IncludeStages` -- the untouched path.** The stages read sends no `$select` at all,
  deliberately: the stage converter reads every property the v1.0 resource has, so naming them all
  would be a longer URL for no reduction. This proves that omission did not break anything.

  ```powershell
  $Stages = @(Get-OERAccessReviewInstance -Definition $Def -IncludeStages -WarningVariable StageWarnings |
      Select-Object -ExpandProperty Stages)
  $Stages.Count
  @($StageWarnings).Count                     # 'Could not read stages ...' would land here
  $Stages | Select-Object -First 2 | Format-List *
  $Stages | Test-OerPopulated -Property AccessReviewStageId, Status, StartDateTime, EndDateTime, AccessReviewInstanceId, AccessReviewDefinitionId, Reviewers, FallbackReviewers
  ```

  **Expect:** `0` warnings; `Empty` `0` for the stage's own id, status, dates and the two parent
  ids; `Reviewers` and `FallbackReviewers` populated where the review has them. A single-stage
  review may legitimately have no fallback reviewers -- say so on the result line rather than
  calling it a failure.
  **Result:**
  ```powershell
> $Stages = @(Get-OERAccessReviewInstance -Definition $Def -IncludeStages -WarningVariable StageWarnings |  
> Select-Object -ExpandProperty Stages)  
> $Stages.Count  
0  
> @($StageWarnings).Count # 'Could not read stages ...' would land here  
0  
> $Stages | Select-Object -First 2 | Format-List *  
> $Stages | Test-OerPopulated -Property AccessReviewStageId, Status, StartDateTime, EndDateTime, AccessReviewInstanceId, AccessReviewDefinitionId, Reviewers, FallbackReviewers  
  
Property Rows Populated Empty  
-------- ---- --------- -----  
AccessReviewStageId 0 0 0  
Status 0 0 0  
StartDateTime 0 0 0  
EndDateTime 0 0 0  
AccessReviewInstanceId 0 0 0  
AccessReviewDefinitionId 0 0 0  
Reviewers 0 0 0  
FallbackReviewers 0 0 0  
  
>
  ```

  **Cannot be verified on this tenant, and therefore we do not know.** The read itself is clean --
  it issued the stage request, raised no warning and threw nothing -- but `$Stages.Count` is `0`,
  so the `Test-OerPopulated` table below it reports `Rows 0 / Populated 0 / Empty 0` on all eight
  properties. **`Empty 0` over zero rows is not the pass condition this check was written to read**;
  it is the same number an entirely broken stage read would print. The definition 0.0 picked is not
  a multi-stage review, so it has no stage collection for the untouched path to return, and every
  other definition in the tenant is in the same state (0.0's table). Marked `- [~]`: executed,
  vacuous, still owed. It needs a tenant holding a multi-stage access review.

- [~] **3.3 `-IncludeDecisions` -- the longer select, and the complex types.**

  ```powershell
  $Decisions = @(Get-OERAccessReviewInstance -Definition $Def -IncludeDecisions -WarningVariable DecisionWarnings |
      Select-Object -ExpandProperty Decisions)
  $Decisions.Count
  @($DecisionWarnings).Count                  # 'Could not read decisions ...' would land here
  $Decisions | Select-Object -First 2 | Format-List *
  $Decisions | Test-OerPopulated -Property Id, Decision, PrincipalId, PrincipalDisplayName, ResourceId, ResourceDisplayName, ReviewedByDisplayName, ReviewedDateTime, AppliedByDisplayName, ApplyResult, Recommendation, Justification
  ```

  **Expect:** `0` warnings. `PrincipalId`, `PrincipalDisplayName`, `ResourceId`,
  `ResourceDisplayName`, `ReviewedByDisplayName` and `AppliedByDisplayName` populated where the
  decision has them. These six come from four complex types (`principal`, `resource`,
  `reviewedBy`, `appliedBy`) that the select names WHOLE. The converter reaches into `.id` AND
  `.displayName` on `principal` and `resource`, and into `.displayName` alone on `reviewedBy` and
  `appliedBy` -- so dropping either of the first two parent names nulls two output properties at
  once, and dropping either of the last two nulls one. Naming the parent is what the select must do
  in all four cases; `principal/id` would not be. These six are what a wrong `$select` would break.
  **Failure looks like:** `PrincipalId` populated but `PrincipalDisplayName` empty (or the reverse),
  or the same pair for `Resource` -- that is a complex type arriving partially selected. A decision
  that has not been applied yet legitimately has an empty `AppliedByDisplayName`, and a `NotReviewed`
  decision legitimately has an empty `ReviewedByDisplayName`/`ReviewedDateTime`/`Justification`;
  note that rather than failing it -- 3.6 is where "legitimately empty" is told apart from "dropped".
  **Result:**
  ```powershell
> $Decisions = @(Get-OERAccessReviewInstance -Definition $Def -IncludeDecisions -WarningVariable DecisionWarnings |  
> Select-Object -ExpandProperty Decisions)  
> $Decisions.Count  
0  
> @($DecisionWarnings).Count # 'Could not read decisions ...' would land here  
0  
> $Decisions | Select-Object -First 2 | Format-List *  
> $Decisions | Test-OerPopulated -Property Id, Decision, PrincipalId, PrincipalDisplayName, ResourceId, ResourceDisplayName, ReviewedByDisplayName, ReviewedDateTime, AppliedByDisplayName, ApplyResult, Recommendation, Justification  
  
Property Rows Populated Empty  
-------- ---- --------- -----  
Id 0 0 0  
Decision 0 0 0  
PrincipalId 0 0 0  
PrincipalDisplayName 0 0 0  
ResourceId 0 0 0  
ResourceDisplayName 0 0 0  
ReviewedByDisplayName 0 0 0  
ReviewedDateTime 0 0 0  
AppliedByDisplayName 0 0 0  
ApplyResult 0 0 0  
Recommendation 0 0 0  
Justification 0 0 0  
   
>
  ```

  **Cannot be verified on this tenant, and therefore we do not know. This is the check issue #74
  most needed, and it measured nothing.** The read is clean -- one request per instance, no
  warning, no error -- but `$Decisions.Count` is `0`, so all twelve rows read
  `Rows 0 / Populated 0 / Empty 0`. **The whole point of this check is the six complex-type fields
  a wrong `$select` would silently null out, and a field cannot be observed as null on a row that
  does not exist.** `Empty 0` here is arithmetic over an empty set, not a populated decision; a
  `$select` that dropped `principal` entirely would print exactly the same table. 0.0 established
  that no instance of any of the tenant's six definitions carries a decision, so no other pick would
  have helped. Marked `- [~]`: executed, vacuous, still owed. Section 4 records it as the run's
  largest gap.

- [x] **3.4 The request URL really carries `$select`.**

  ```powershell
  $ArVerbose = (Get-OERAccessReviewInstance -Definition $Def -IncludeDecisions -Verbose 4>&1) |
      Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
      ForEach-Object { $_.Message } |
      Where-Object { $_ -match '\$select=' }
  @($ArVerbose).Count
  $ArVerbose | Select-Object -Unique | Select-Object -First 4
  ```

  **Expect:** at least two lines -- one `.../instances?$select=id,status,startDateTime,endDateTime,scope`
  and one `.../decisions?$select=id,decision,justification,reviewedBy,reviewedDateTime,appliedBy,applyResult,principal,resource,recommendation`
  (one per instance for the latter, hence the `-Unique`).
  **Redact the definition id and every instance id in the pasted lines.**
  **Result:**
  ```powershell
> $ArVerbose = (Get-OERAccessReviewInstance -Definition $Def -IncludeDecisions -Verbose 4>&1) |  
> Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |  
> ForEach-Object { $_.Message } |  
> Where-Object { $_ -match '\$select=' }  
> @($ArVerbose).Count  
3  
> $ArVerbose | Select-Object -Unique | Select-Object -First 4  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000003/instances?$select=id,status,startDateTime,endDateTime,scope  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000003/instances/00000000-0000-0000-0000-000000000004/decisions?$select=id,decision,justification,reviewedBy,reviewedDateTime,appliedBy,applyResult,principal,resource,recommendation 
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000003/instances/00000000-0000-0000-0000-000000000023/decisions?$select=id,decision,justification,reviewedBy,reviewedDateTime,appliedBy,applyResult,principal,resource,recommendation 
>
  ```

- [x] **3.5 The single-instance read.** A different code path from the list read, with the same
  select. `$One` is the instance 0.0 picked (the one with the most decisions).

  ```powershell
  $Single = Get-OERAccessReviewInstance -Definition $Def -Instance $One
  $Single | Format-List *
  $Single | Test-OerPopulated -Property AccessReviewInstanceId, Status, StartDateTime, EndDateTime, AccessReviewDefinitionId, Scope
  ```

  **Expect:** identical field population to check 3.1 -- all six fields, `Scope` included, `Empty`
  `0` on every row.
  **Redact `$One` in the pasted output.**
  **Result:**
  ```powershell
> $Single = Get-OERAccessReviewInstance -Definition $Def -Instance $One  
> $Single | Format-List *  
  
AccessReviewInstanceId : 00000000-0000-0000-0000-000000000004  
Status : NotStarted  
StartDateTime : 2026-12-06 21:59:59  
EndDateTime : 2026-12-27 21:59:59  
AccessReviewDefinitionId : 00000000-0000-0000-0000-000000000003  
Scope : /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000036' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000037')  
Id : 00000000-0000-0000-0000-000000000004  
DefinitionId : 00000000-0000-0000-0000-000000000003  
  
> $Single | Test-OerPopulated -Property AccessReviewInstanceId, Status, StartDateTime, EndDateTime, AccessReviewDefinitionId, Scope  
  
Property Rows Populated Empty  
-------- ---- --------- -----  
AccessReviewInstanceId 1 1 0  
Status 1 1 0  
StartDateTime 1 1 0  
EndDateTime 1 1 0  
AccessReviewDefinitionId 1 1 0  
Scope 1 1 0  
  
>
  ```

  **The instance half of this check is genuinely verified; the decision half of its premise is
  not.** One real row came back and all six fields are populated on it, `Scope` included, matching
  3.1 -- that is the single-instance code path and its `$select`, proved against real Graph data.
  What is NOT true is the sentence above the code block: `$One` is described as "the instance 0.0
  picked (the one with the most decisions)", and 0.0 picked it out of a table where every row read
  `Decisions 0`. So `$One` carries no decisions, and 3.5 proves nothing about the decision select
  and does not set 3.6 up to prove anything either. That is the "part of 3.5" 0.0's failure clause
  names. The box stays `- [x]` for what it did measure -- six fields on a real instance -- and the
  caveat is written here rather than left to be inferred from 3.6's empty table.

- [~] **3.6 The cross-check against the cmdlet that was NOT changed.**
  `Get-OERAccessReviewInstanceDecision` shares the decision converter but sends no `$select` of its
  own, so it sees whatever Graph returns by default. A field populated here and empty in check 3.3
  is the `$select` having dropped it -- which is exactly the failure this pair is arranged to
  expose. The block reads the SAME instance both ways and compares per property, so a legitimately
  empty field (unapplied, not reviewed) is empty on both sides and a dropped one is not.

  ```powershell
  $WithSelect    = @(Get-OERAccessReviewInstance -Definition $Def -Instance $One -IncludeDecisions | Select-Object -ExpandProperty Decisions)
  $WithoutSelect = @(Get-OERAccessReviewInstanceDecision -Definition $Def -Instance $One)
  '{0} decisions with $select, {1} without' -f $WithSelect.Count, $WithoutSelect.Count
  $WithoutSelect | Select-Object -First 1 | Format-List *
  foreach ($P in 'Id','Decision','Justification','ReviewedByDisplayName','ReviewedDateTime','AppliedByDisplayName',
                 'ApplyResult','PrincipalId','PrincipalDisplayName','ResourceId','ResourceDisplayName','Recommendation') {
      $A = @($WithSelect    | Where-Object { -not [string]::IsNullOrEmpty([string]$_.$P) }).Count
      $B = @($WithoutSelect | Where-Object { -not [string]::IsNullOrEmpty([string]$_.$P) }).Count
      [PSCustomObject]@{ Property = $P; PopulatedWithSelect = $A; PopulatedWithoutSelect = $B; Match = ($A -eq $B) }
  }
  ```

  **Expect:** the same decision count both ways, and `Match` `True` on every one of the twelve rows
  -- the same six complex-type fields populated as in check 3.3, for the same decisions.
  **Failure looks like:** any row with `PopulatedWithoutSelect` HIGHER than `PopulatedWithSelect`
  -- populated by the unchanged cmdlet, dropped by the select.
  **Result:**
  ```powershell
> $WithSelect = @(Get-OERAccessReviewInstance -Definition $Def -Instance $One -IncludeDecisions | Select-Object -ExpandProperty Decisions)  
> $WithoutSelect = @(Get-OERAccessReviewInstanceDecision -Definition $Def -Instance $One)  
> '{0} decisions with $select, {1} without' -f $WithSelect.Count, $WithoutSelect.Count  
0 decisions with $select, 0 without  
> $WithoutSelect | Select-Object -First 1 | Format-List *  
> foreach ($P in 'Id','Decision','Justification','ReviewedByDisplayName','ReviewedDateTime','AppliedByDisplayName',  
> 'ApplyResult','PrincipalId','PrincipalDisplayName','ResourceId','ResourceDisplayName','Recommendation') {  
> $A = @($WithSelect | Where-Object { -not [string]::IsNullOrEmpty([string]$_.$P) }).Count  
> $B = @($WithoutSelect | Where-Object { -not [string]::IsNullOrEmpty([string]$_.$P) }).Count  
> [PSCustomObject]@{ Property = $P; PopulatedWithSelect = $A; PopulatedWithoutSelect = $B; Match = ($A -eq $B) }  
> }  
  
Property PopulatedWithSelect PopulatedWithoutSelect Match  
-------- ------------------- ---------------------- -----  
Id 0 0 True  
Decision 0 0 True  
Justification 0 0 True  
ReviewedByDisplayName 0 0 True  
ReviewedDateTime 0 0 True  
AppliedByDisplayName 0 0 True  
ApplyResult 0 0 True  
PrincipalId 0 0 True  
PrincipalDisplayName 0 0 True  
ResourceId 0 0 True  
ResourceDisplayName 0 0 True  
Recommendation 0 0 True  
  
>
  ```

  **Cannot be verified on this tenant, and therefore we do not know.** `0 decisions with $select, 0
  without` -- the comparison ran over two empty collections, so every one of the twelve rows reads
  `PopulatedWithSelect 0 / PopulatedWithoutSelect 0 / Match True`. **`Match True` over zero rows is
  the vacuous form of this check's pass condition**, and it is precisely the reading a dropped field
  would also produce: `0 -eq 0` is true whether the select is right, wrong, or absent. This pair is
  the arrangement designed to tell "legitimately empty" apart from "dropped", and with no decisions
  on either side it cannot tell them apart at all. 0.0 established that no instance in the tenant
  carries a decision. Marked `- [~]`: executed, vacuous, still owed.

- [ ] **3.7 A wildcard-free `-DisplayName` issues ONE filtered request, not a full walk.** Added
  after the run: commits `67188a9` and `b58f7a4` rewrote `Get-OERAccessReviewDefinition` so a name
  with no wildcard character resolves SERVER-SIDE through
  `$filter=displayName eq '<name>'` instead of paging the whole definitions collection with
  `$top=100` and narrowing client-side. Nothing above exercises it -- 0.0 calls the cmdlet with
  `-All`, which still takes the paged path -- so the one behaviour the two commits changed has no
  check of its own. This is that check.

  ```powershell
  # $DefName is the display name of a definition that EXISTS, spelled with the same case the
  # tenant stores. Take it from 0.0's definitions table.
  $DefName = '<a definition display name from 0.0>'
  $ByName = (Get-OERAccessReviewDefinition -DisplayName $DefName -Verbose 4>&1)
  @($ByName | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }).Count
  $Lines = @($ByName | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
  @($Lines | Where-Object { $_ -match [regex]::Escape('definitions?$filter=displayName eq') }).Count
  @($Lines | Where-Object { $_ -match [regex]::Escape('definitions?$top=100') }).Count
  $Lines | Where-Object { $_ -match '^\[Invoke-OERGraphRequest\] ' }
  ```

  **Expect:** the definition comes back (one row, the same id 0.0 listed for that name); exactly
  `1` line carrying `definitions?$filter=displayName eq`; and `0` lines carrying
  `definitions?$top=100`. **The `$top=100` count is the load-bearing half** -- a `1` there means the
  filtered read came back empty and the cmdlet fell back to the full paged walk, which is a
  functional pass and a performance failure, and the row count alone would not show it.
  **Redact the definition id in the pasted lines, and replace the display name with the stand-in
  0.0 uses for it.**
  **Failure looks like:** `0` rows returned for a name that 0.0 listed -- the server-side filter
  matched nothing AND the fallback did not save it; or a `$top=100` line present, which means the
  filtered request returned zero rows. Note that `displayName eq` is case-SENSITIVE where the old
  client-side `-like` walk was not: a name that differs from the stored one only in case now
  returns fewer rows than it did before this branch. That is the documented behaviour change, and
  this tenant holds no two definitions differing only in case, so this check does not exercise it.
  **Result:**

- [ ] **3.8 A wildcard `-DisplayName` still returns through the paged walk.** The other half of the
  same change: only a name with no `*`, `?` or `[` goes server-side. Everything else must still page
  the unfiltered collection and narrow client-side, exactly as before the branch -- if that path
  regressed, wildcard lookups return nothing and no error is raised.

  ```powershell
  # Same definition as 3.7, named with a trailing wildcard.
  $Wild = (Get-OERAccessReviewDefinition -DisplayName '<the same name, truncated>*' -Verbose 4>&1)
  @($Wild | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }).Count
  $WildLines = @($Wild | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
  @($WildLines | Where-Object { $_ -match [regex]::Escape('definitions?$top=100') }).Count
  @($WildLines | Where-Object { $_ -match [regex]::Escape('definitions?$filter=displayName eq') }).Count
  ```

  **Expect:** at least the one definition 3.7 returned; `1` or more `definitions?$top=100` lines
  (more than one only if the collection pages); and `0` `definitions?$filter=displayName eq` lines
  -- a wildcard must never reach the server-side filter, since this endpoint silently IGNORES
  `startswith(displayName,...)` and would return the whole collection as if it had matched.
  **Failure looks like:** `0` rows, or any `displayName eq` line.
  **Result:**

---

### 4. What this checklist deliberately does NOT prove

**The ARM retry path itself is not verified live, and this document does not claim it is.** It is
proved only by the mocked, mutation-proved unit suite in
`tests/Unit/Private/Invoke-OERArmRequest.Tests.ps1`, because ARM throttling cannot be provoked from
one workstation against a small tenant -- see the arithmetic at the top of this file, which was
measured on the Graph side in PR #77 rather than assumed. Everything in section 1 is evidence that
the ordinary path still works; none of it is evidence that a 429 is handled correctly.

That is the same state PR #77 merged in, and it is honest as long as it is written down here rather
than left for a later reader to discover.

**If a genuine ARM 429 is ever observed in the field, capture the verbose line.** One line is
emitted per retry and it names the delay, the attempt number and whether the value was
`server-directed` or an `exponential fallback`:

```
[Invoke-OERArmRequest] Throttled (status=429). Waiting 60 s (server-directed) before retry 1; ...
```

That line is the evidence, and its ABSENCE on a real throttle is what exposed the equivalent Graph
bug in PR #77. Paste it into this section when it happens; a real observation retires the debt that
this section records.

**Two further things this file does not cover, both deliberate:**

- **The per-call deadline caps a THROTTLED call only.** It is consulted at the decision to wait and
  nowhere else, so an `-All` walk that is never throttled follows `nextLink` for as long as ARM
  keeps handing out pages and never reads it. That gap is pre-existing and out of scope for this
  branch; it is recorded at `docs/development/rationale.md#arm-transport`.
- **No batching and no pre-emptive pacing was added for issue #74.** Only `$select`. Reading a
  definition with 30 instances and both switches still issues 60+ paged requests in a tight loop;
  they are simply smaller responses now.

**And four things the 2026-09-07 RUN did not prove, which were expected to be proved and were not.**
The four above are design decisions. These four are debts this particular tenant left behind, and
they are written here for the same reason the 429 gap is: so a later reader does not read a ticked
box as evidence it is not.

- **Issue #74's central risk is not live-verified.** No access review in this tenant carries a
  single decision -- 0.0 probed all 15 instances of all 6 definitions and every one returned `0`.
  The decision-field evidence a wrong `$select` would destroy therefore does not exist here to be
  destroyed: checks 3.3 and 3.6 executed cleanly over empty collections, printing `Empty 0` and
  `Match True` on 24 rows between them, and neither number would have changed if the select had
  dropped `principal`, `resource`, `reviewedBy` and `appliedBy` outright. 3.2 is in the same
  position for the stage read, one definition-shape further out: the picked definition is not a
  multi-stage review. **This is the same class of gap as the ARM 429 above** -- the code path is
  proved only by the mocked suite, and the live evidence that would have been independent of that
  suite's own assumptions was not obtainable here. It needs a tenant holding a review with decided
  rows and a second stage, and it stays owed until one is run.
- **The paging evidence in section 1 is thinner than the deltas make it look.** The subscription
  0.0 auto-picked -- the first `Enabled` one, held by GUID -- reports `ResourceGroups 0` and
  `Resources 0`. So check 1.6, titled "the heaviest list read in the module, and the one most likely
  to page more than once", walked a single empty page, and 1.5 did the same. Their `Delta 0` rows
  are legitimate matches and they are also `0` compared with `0`, which says nothing whatever about
  aggregating a second page. What DOES carry real paging weight in this run is 1.1/1.12 (17,862
  `roleManagementPolicies` and 75 `roleAssignments`, identical on both sides) and 1.11's
  `@nextLink` management-group walk with its unique-id check. A rerun on a subscription that
  actually holds resources would close 1.5 and 1.6 properly.
- **The header-leak checks passed over a 214-character capture.** 2.2 and 2.3 read
  `verbose-arm.log` from a single ARM request that was not paged, not retried and not an error --
  2.1 recorded 2 verbose records and 1 `[Invoke-OERArmRequest] GET` line. `$Text.Length 214` is
  non-zero, so neither check is vacuous in the way section 3's are; what they demonstrate is that
  **the happy path of one successful request prints no header name and no JWT.** They do not cover a
  paged request, a retried one, or an error path -- and the error path is where header material has
  leaked in this module before (the `HttpRequestMessage` in an `ErrorRecord` renders
  `Authorization: Bearer` in full, which is why `Remove-OERErrorRecord` exists and why
  `tests/QA/dochygiene.tests.ps1` scans for it). A capture taken across a failing ARM call would be
  the check that matters, and this run does not have one.
- **Two commits on this branch had no check at all when it was run.** `67188a9` and `b58f7a4`
  rewrote `Get-OERAccessReviewDefinition` so a wildcard-free `-DisplayName` issues one server-side
  `displayName eq` request instead of paging every definition with `$top=100`, with a documented
  behaviour change: `eq` is case-sensitive where the old client-side `-like` walk was not, so a name
  that matched only case-insensitively can now return fewer rows. Every call in this file uses
  `-All`, which still takes the paged path, so none of it touched the changed branch. Checks 3.7 and
  3.8 were added afterwards and are unticked -- they are for the next connection, not something this
  run covered.

---

### T. Teardown

- [x] **T.1 Nothing to undo in the tenant.** There is nothing to run here, and that is the point:
  every check above is a read. The only cmdlets this file executes are `Connect-OER`,
  `Get-OER*` and `Export-OERInventory` (which writes to `$LogDir`, on disk, outside the repo -- not
  to the tenant). No `New-`, `Set-`, `Remove-`, `Add-` or `Invoke-OERStructure` call appears
  anywhere in it, and neither does `-Prune` or `-Confirm:$false` outside this sentence and the
  preamble. Confirm that by reading back over the sections you actually ran, and tick this box only
  once you have. The one thing this file DID change outside the tenant is the local repo: 0.B
  switched branches and rebuilt twice -- confirm you are back on the branch with a clean tree.

  ```powershell
  git -C $Repo branch --show-current
  git -C $Repo status --short
  ```

  **Expect:** you find no executed command that wrote to the tenant; the branch name; an empty
  status.
  **Failure looks like:** you find one. Say which, and restore whatever it changed before ticking
  anything else.
  **Result:**
  ```powershell
> git -C $Repo branch --show-current  
fix/arm-throttle-and-review-pacing  
> git -C $Repo status --short  
>
  ```

- [x] **T.2 Delete the capture files, then disconnect.** The captures hold live subscription,
  resource and principal ids, and `$BaselineFile` holds the bundle path with the tenant id. They
  were written outside the repo on purpose; delete them anyway once the results above are
  transcribed and redacted -- the baseline numbers live in 0.B's result block from now on.

  ```powershell
  Get-ChildItem $LogDir -Recurse -File | Select-Object FullName, Length
  Remove-Item $LogDir -Recurse -Force
  Test-Path $LogDir
  Disconnect-OER
  ```

  **Expect:** `False` from `Test-Path`, and a clean `Disconnect-OER`.
  **Result:**
  ```powershell
> Get-ChildItem $LogDir -Recurse -File | Select-Object FullName, Length  
  
FullName Length  
-------- ------  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\baseline-main.json 634  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\verbose-arm.log 214  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-121926\inventory.json 10707082  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-121926\rbac-architect-prompt.md 21312  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-121926\README.md 4782  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-121926\roleAssignments.json 15193  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-121926\roleManagementPolicies.json 10155001  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-121926\schema.json 22605  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-121926\scopeHierarchy.json 4129  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-132209\inventory.json 10707082  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-132209\rbac-architect-prompt.md 21312  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-132209\README.md 4782  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-132209\roleAssignments.json 15193  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-132209\roleManagementPolicies.json 10155001  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-132209\schema.json 22605  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-after\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-132209\scopeHierarchy.json 4129  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541\inventory.json 10707082  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541\rbac-architect-prompt.md 21312  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541\README.md 4782  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541\roleAssignments.json 15193  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541\roleManagementPolicies.json 10155001  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541\schema.json 22605  
C:\Users\<user>\AppData\Local\Temp\oer-arm-live\bundle-before\oer-inventory-00000000-0000-0000-0000-000000000002-20260907-131541\scopeHierarchy.json 4129  
  
> Remove-Item $LogDir -Recurse -Force  
> Test-Path $LogDir  
False  
> Disconnect-OER  
>
  ```

  Deleted, and `Test-Path` confirms it. One note on the listing itself: it holds THREE bundle
  folders, not the two this document describes -- a `bundle-after` stamped `121926`, which precedes
  the `main` baseline export (`bundle-before`, `131541`) and the branch export this file records
  (`bundle-after`, `132209`). So the session was not the single linear sequence the document reads
  as; an earlier export was taken and discarded before the baseline was captured. The counts
  transcribed into 1.1, 1.12 and 0.B are the `131541`/`132209` pair, which are the two the helper
  objects returned. All three were deleted together.

- [ ] **T.3 What cannot be undone.**

  - **Nothing was written to the tenant.** Every command in this document is a read.
  - **The read load is in the tenant's Graph and ARM telemetry** and cannot be removed. Section 1.1
    is a full scope-tree walk, and 0.B ran it a second time on `main`; if your tenant alerts on ARM
    request volume, expect it to have fired twice.
  - **The exported bundles in `$LogDir` under-declare nothing intentionally**, but if any scope was
    skipped in check 1.1 or 0.B, do not keep them and do not apply them -- an inventory with a
    missing scope, applied later with `-Prune`, deletes real assignments. T.2 deletes both.

  **Record:** anything that fired, was alerted on, or has to be told to someone:
  ```powershell

  ```

  **Unticked on purpose.** The Record block above is empty. This box asks for an observation --
  what fired, what was alerted on, what has to be told to someone -- and no observation was written
  down, so there is nothing here to read as one. An empty result is an unrun check, not a "nothing
  happened", and the difference matters for exactly the reason the preamble gives. Fill it in, or
  write "nothing fired" if that is what was seen, on the next connection.
