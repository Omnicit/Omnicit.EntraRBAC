# Live verification checklist -- access reviews of groups and the one-time review length (feat/group-and-role-access-reviews)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Only objects whose name starts with `oer-s126-`: the
prerequisite script's disabled user `oer-s126-reviewer`, the security groups `oer-s126-grp-a` and
`oer-s126-grp-b` (no member), the catalog `oer-s126-cat` with the access package `oer-s126-pkg` and
its administrator-only policy `oer-s126-pol`, the measurement reviews `oer-s126-m...` and
`oer-s126-g...` made before the plan, and the access reviews these checks create
(`oer-s126-rev-...`). Every review starts a week after the run, so no instance opens and no
reviewer is asked anything. Every check that expects no write runs with a fence that refuses any
write request, and every other check with a fence that refuses a write of an object without the
prefix.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A one-time review lasts the days it declares** (BL-168; "Write a one-time access review with
  the length it declares", "Compare a one-time review by the length Microsoft Graph uses"). The
  module now writes a one-time review as Microsoft Graph's one-time form (a numbered range with no
  occurrences, ending `durationInDays` after the start), which Graph stores; the diff and the export
  read the length from that range. Before, Graph stored 0 days and a 30-day range, and every later
  run sent an update Graph did not store.
- **B. An entry can review the members of a group** (BL-137; "Let an access review entry declare the
  group whose members it reviews", "Apply access reviews of a group's members ...", "Export access
  reviews of a group's members", "Create an access review of a group's members with
  New-OERAccessReviewDefinition -Group"). `accessReviews[]` takes `group` (a name or an object id) in
  place of `accessPackage` and `assignmentPolicy`; the export writes such a review; a review with the
  entry's name that reviews another group is refused with `AccessReviewScopeMismatch`.
- **C. A reviewer scope of a group's owners is no longer read as its members** ("Read a group
  reviewer scope only in the forms the module writes"). The export skips a review whose reviewers it
  cannot write back (such as a group's owners), and a review of a group's inactive users is never
  read as a review of all its members (checks 2.4, 3.1, 4.2). An older document that names the group
  behind an owners reviewer is not applied over it (offline only, see below).
- **D. A one-time review's end is never moved to today or earlier** (`AccessReviewEndNotInFuture`,
  check 1.5).

## What this file does not check, and why

- **C, an older document over an owners reviewer** (class B): it needs a document an export made
  before this branch; the unit tests of `Resolve-OERAccessReviewChange` hold it. The reviewer forms
  themselves: the unit tests of `Resolve-OERReviewerScopeQuery` hold every form,
  and the measurement before the plan read back the group reviewer form the module writes
  (`/v1.0/groups/{id}/transitiveMembers/microsoft.graph.user`, primary and fallback).
- **A review of a directory role** is not part of this step (decision A8).

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it (it holds `AccessReview.ReadWrite.All` since Sprint 10 step 6 round 1).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.
- The prerequisite script `Initialize-OerS126Prereq.ps1` beside OerLive: run it once with `-WhatIf`,
  then with `-Unattended`; every `Read back` line must be `True`.

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block).

### H.1. The helpers every check uses

- [x] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s126-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s126'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$ArBase = 'v1.0/identityGovernance/accessReviews/definitions'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$StartDay = [datetime]::UtcNow.Date.AddDays(7)
$Start = $StartDay.ToString('yyyy-MM-dd', $Inv)
$IdFile = Join-Path $Raw 'known-ids.json'
function Connect-S126 {
    Connect-OerLive -Arm
    $script:S126Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S126Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S126 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S126Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S126Module {
        $script:S126Log = [System.Collections.Generic.List[string]]::new()
        $script:S126NoWrite = $false
        $script:S126Real = ${function:Invoke-OERGraphRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
            $script:S126Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
            if (-not $Read -and $script:S126NoWrite) { throw "S126 fence: a $Method request was refused; this check expects no write." }
            if (-not $Read -and $Body -and $Body.ContainsKey('displayName') -and -not ([string]$Body.displayName).StartsWith('oer-s126-')) { throw "S126 fence: a $Method of an object without the prefix was refused." }
            & $script:S126Real @PSBoundParameters
        }
    }
}
function Set-S126NoWrite { param([bool]$On) & $script:S126Module { param($V) $script:S126NoWrite = $V } $On }
function Get-S126Count { & $script:S126Module { '{0} read(s), {1} write(s)' -f @($script:S126Log | Where-Object { $_ -eq 'read' }).Count, @($script:S126Log | Where-Object { $_ -ne 'read' }).Count } }
function Show-S126Row { param($Rows) foreach ($R in @($Rows)) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3} | record: {4}" -f $R.Section, $R.Item, $R.Action, $R.Detail, $(if ($R.Error) { ([string]$R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })) } }
function Get-S126Ids { if (Test-Path -LiteralPath $IdFile) { Get-Content -LiteralPath $IdFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} } }
function Add-S126Review {
    # Records a review this file created, so the teardown finds it even while the listing lags.
    param([string]$Name, [string]$Id)
    if (-not $Id) { return }
    $Ids = Get-S126Ids
    $Ids["review-$Name"] = @{ Kind = 'access review definition'; Id = $Id }
    $Ids | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $IdFile -Encoding utf8NoBOM
}
function Find-S126Review {
    # The one live review with this exact name, read raw (OData filter, then an exact client-side match).
    param([string]$Name)
    $R = Invoke-OerLiveGraph -Uri "$ArBase`?`$filter=displayName eq '$Name'"
    $null = Assert-OerLiveOk -Response $R -Activity "find $Name"
    $Hit = @($R.Body.value | Where-Object { [string]$_.displayName -ceq $Name })
    if ($Hit.Count -ne 1) { return $null }
    (Invoke-OerLiveRetry -Activity "read $Name" -ScriptBlock { Invoke-OerLiveGraph -Uri "$ArBase/$($Hit[0].id)" }).Body
}
function Show-S126Review {
    param($Def, [string]$Label)
    if (-not $Def) { Write-OerLiveStep "$Label`: not found"; return }
    $Range = $Def.settings.recurrence.range
    Write-OerLiveStep ("{0}: instanceDurationInDays {1}; pattern {2}; range {3} {4}..{5}; scope {6}" -f $Label, $Def.settings.instanceDurationInDays,
        $(if ($Def.settings.recurrence.pattern) { "$($Def.settings.recurrence.pattern.type) $($Def.settings.recurrence.pattern.interval)" } else { 'null' }),
        $Range.type, $Range.startDate, $Range.endDate, $Def.scope.query)
}
$Ids0 = Get-S126Ids
$GrpA = [string]$Ids0['grp-a'].Id; $GrpB = [string]$Ids0['grp-b'].Id
$Reviewer = "oer-s126-reviewer@$($Cfg.UserDomain)"
```

**Expect:** nothing printed.
**Failure looks like:** a parse error -- fix the block before any check runs.

Result: 2026-11-05 15:58 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The helpers block parses and loads in every check (the runner prepends it); it prints only OerLive's own load lines.
```

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the prerequisite objects exist. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
foreach ($Marker in @(
        @('A', 'function Get-OERAccessReviewDuration'),
        @('B', 'function Resolve-OERAccessReviewGroupScope'),
        @('B (-Group)', 'GroupMultiStage'))) {
    Write-OerLiveStep "The worktree's build carries $($Marker[0]): $([bool](Select-String -LiteralPath $Psm1 -SimpleMatch $Marker[1] -Quiet))"
}
foreach ($K in 'reviewer', 'grp-a', 'grp-b', 'cat', 'pkg', 'pol') { Write-OerLiveStep "Prerequisite $K recorded: $([bool]$Ids0[$K].Id)" }
```

**Expect:** a worktree that is not the main clone, on this branch with 0 tracked changes; A, B and
B (-Group) `True`; every prerequisite `True`.
**Failure looks like:** a marker `False` -- build the worktree (`./build.ps1 -Tasks build`), never
while the gate runs; a prerequisite `False` -- run the prerequisite script.

Result: 2026-11-05 15:58 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The worktree (not the main clone) is on this branch at fe4fd9e with 0 tracked changes; its build (gated green at fe4fd9e: 13840 passed, 0 failed, coverage 96.48 %) carries A, B and the -Group parameter sets; every prerequisite is recorded, and the prerequisite script read every object back True.

[oer-s126] The module loads from a worktree that is not the main clone: True
[oer-s126] Worktree: branch feat/group-and-role-access-reviews; HEAD fe4fd9e docs: state the old one-time length as measured; tracked changes: 0
[oer-s126] The worktree's build carries A: True
[oer-s126] The worktree's build carries B: True
[oer-s126] The worktree's build carries B (-Group): True
[oer-s126] Prerequisite reviewer recorded: True
[oer-s126] Prerequisite grp-a recorded: True
[oer-s126] Prerequisite grp-b recorded: True
[oer-s126] Prerequisite cat recorded: True
[oer-s126] Prerequisite pkg recorded: True
[oer-s126] Prerequisite pol recorded: True
```

## 1. A one-time review lasts the days it declares (A)

### 1.1. A one-time package review is created with 14 days, and Graph stores 14

- [x] **1.1** `Invoke-OERStructure` creates `oer-s126-rev-once` (OneTime, 14 days); read back raw, its range is numbered and ends 14 days after its start, and `instanceDurationInDays` is 14. #type/subtask

```powershell
Connect-S126
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-once'; accessPackage = 'oer-s126-pkg'; assignmentPolicy = 'oer-s126-pol'
            reviewers = @(); recurrence = 'OneTime'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S126Count)"
$Def = Find-S126Review -Name 'oer-s126-rev-once'
Add-S126Review -Name 'oer-s126-rev-once' -Id ([string]$Def.id)
Show-S126Review $Def 'read back'
$Days = if ($Def) { ([datetime]::Parse([string]$Def.settings.recurrence.range.endDate, $Inv) - [datetime]::Parse([string]$Def.settings.recurrence.range.startDate, $Inv)).Days } else { $null }
Write-OerLiveStep "The range lasts 14 days: $($Days -eq 14); instanceDurationInDays is 14: $([int]$Def.settings.instanceDurationInDays -eq 14); the start is the declared one: $([string]$Def.settings.recurrence.range.startDate -eq $Start)"
Disconnect-OerLive
```

**Expect:** one row `accessReviews | oer-s126-rev-once | Created | created access review
'oer-s126-rev-once' (recurrence: OneTime) | record: none`; `$? True`; 0 error records; read back
`instanceDurationInDays 14; pattern null; range numbered`; the three last values `True`.
**Failure looks like:** `instanceDurationInDays 0` and a 30-day range -- the old shape (A is not in
the build); `Failed` -- read the record.

Result: 2026-11-05 15:58 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Invoke-OERStructure created oer-s126-rev-once (OneTime, 14 days) with one write; read back raw, Graph stores instanceDurationInDays 14, pattern null and a numbered range from the declared start to 14 days later.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] row: accessReviews | oer-s126-rev-once | Created | created access review 'oer-s126-rev-once' (recurrence: OneTime) | record: none
[oer-s126] Run: rows 1; $? True; error records: 0; warnings: 0; requests: 4 read(s), 1 write(s)
[oer-s126] read back: instanceDurationInDays 14; pattern null; range numbered 2026-11-12..2026-11-26; scope /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000001' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000002')
[oer-s126] The range lasts 14 days: True; instanceDurationInDays is 14: True; the start is the declared one: True
```

### 1.2. A second run of the same document reports only Unchanged (G8)

- [x] **1.2** The same document again: one `Unchanged` row, `$? True`, and no write request (the fence refuses any). #type/subtask

```powershell
Connect-S126
Set-S126NoWrite $true
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-once'; accessPackage = 'oer-s126-pkg'; assignmentPolicy = 'oer-s126-pol'
            reviewers = @(); recurrence = 'OneTime'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S126Count)"
Disconnect-OerLive
```

**Expect:** `row: accessReviews | oer-s126-rev-once | Unchanged | access review 'oer-s126-rev-once'
already matches | record: none`; `$? True`; 0 error records; 0 writes.
**Failure looks like:** `Updated`, or a fence refusal -- the diff does not read the length Graph stores.

Result: 2026-11-05 15:58 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The same document again: one Unchanged row, $? True, 0 error records, 3 reads and 0 writes under the no-write fence (G8).

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] row: accessReviews | oer-s126-rev-once | Unchanged | access review 'oer-s126-rev-once' already matches | record: none
[oer-s126] Run: rows 1; $? True; error records: 0; warnings: 0; requests: 3 read(s), 0 write(s)
```

### 1.3. A one-time review in the older shape converges in one update

- [x] **1.3** A one-time review written raw in the shape the module sent before this branch (`oer-s126-rev-legacy`) reads back 0 days and a 30-day range; the document with `durationInDays` 14 updates it once, and the definition and its instance then end 14 days after the start. #type/subtask

```powershell
Connect-S126
$Ids = Get-S126Ids
$Scope = @{ '@odata.type' = '#microsoft.graph.accessReviewQueryScope'; queryType = 'MicrosoftGraph'
    query = "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq '$($Ids['pkg'].Id)' and assignmentPolicy/id eq '$($Ids['pol'].Id)'" }
$Old = Find-S126Review -Name 'oer-s126-rev-legacy'
if (-not $Old) {
    $Body = @{ displayName = 'oer-s126-rev-legacy'; descriptionForAdmins = 'Sprint 12 step 6 live check'; descriptionForReviewers = 'Sprint 12 step 6 live check'
        scope = $Scope; reviewers = @(); fallbackReviewers = @()
        settings = @{ mailNotificationsEnabled = $false; reminderNotificationsEnabled = $false; justificationRequiredOnApproval = $false; recommendationsEnabled = $false
            defaultDecisionEnabled = $false; defaultDecision = 'None'; instanceDurationInDays = 14; autoApplyDecisionsEnabled = $false } }
    $R = Invoke-OerLiveGraph -Method POST -Uri $ArBase -Body $Body
    $null = Assert-OerLiveOk -Response $R -Activity 'create oer-s126-rev-legacy'
    Add-S126Review -Name 'oer-s126-rev-legacy' -Id ([string]$R.Body.id)
    Start-Sleep -Seconds 5
    $Old = Find-S126Review -Name 'oer-s126-rev-legacy'
}
Show-S126Review $Old 'before'
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-legacy'; accessPackage = 'oer-s126-pkg'; assignmentPolicy = 'oer-s126-pol'
            reviewers = @(); recurrence = 'OneTime'; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S126Count)"
Start-Sleep -Seconds 5
$New = Find-S126Review -Name 'oer-s126-rev-legacy'
Show-S126Review $New 'after'
$Inst = @((Invoke-OerLiveGraph -Uri "$ArBase/$($New.id)/instances").Body.value)
foreach ($I in $Inst) {
    $Len = ([datetime]$I.endDateTime).Date - ([datetime]$I.startDateTime).Date
    Write-OerLiveStep "instance: status $($I.status); lasts $($Len.Days) day(s)"
}
Disconnect-OerLive
```

**Expect:** before: `instanceDurationInDays 0; pattern null; range noEnd`, a range of 30 days;
one row `Updated` naming `durationInDays=14`; `$? True`; 0 error records; after: `range numbered`
ending 14 days after its start, `instanceDurationInDays 14`; the instance lasts 14 days (or, when
Graph has made no instance yet, no instance line).
**Failure looks like:** `Failed` with "update not confirmed" -- Graph did not store the range.

Result: 2026-11-05 15:59 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. oer-s126-rev-legacy was written raw in the shape the module sent before this branch: Graph stores instanceDurationInDays 0 and a noEnd range of 30 days. The document with durationInDays 14 updated it once (one write, the Set PUT; Updated naming durationInDays=14); read back, the range is numbered and ends 14 days after the start, instanceDurationInDays 14, and the instance (NotStarted) now lasts 14 days.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] before: instanceDurationInDays 0; pattern null; range noEnd 2026-11-05..2026-12-05; scope /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000001' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000002')
[oer-s126] row: accessReviews | oer-s126-rev-legacy | Updated | updated access review 'oer-s126-rev-legacy' (durationInDays=14) | record: none
[oer-s126] Run: rows 1; $? True; error records: 0; warnings: 0; requests: 5 read(s), 1 write(s)
[oer-s126] after: instanceDurationInDays 14; pattern null; range numbered 2026-11-05..2026-11-19; scope /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000001' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000002')
[oer-s126] instance: status NotStarted; lasts 14 day(s)
```

### 1.4. A second run reports only Unchanged (G8)

- [x] **1.4** The document of 1.3 again: one `Unchanged` row, `$? True`, no write request. #type/subtask

```powershell
Connect-S126
Set-S126NoWrite $true
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-legacy'; accessPackage = 'oer-s126-pkg'; assignmentPolicy = 'oer-s126-pol'
            reviewers = @(); recurrence = 'OneTime'; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S126Count)"
Disconnect-OerLive
```

**Expect:** `Unchanged`; `$? True`; 0 error records; 0 writes.
**Failure looks like:** `Updated` again -- the update does not converge.

Result: 2026-11-05 15:59 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The document of 1.3 again: one Unchanged row, $? True, 0 error records, 0 writes under the no-write fence (G8 for the update path).

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] row: accessReviews | oer-s126-rev-legacy | Unchanged | access review 'oer-s126-rev-legacy' already matches | record: none
[oer-s126] Run: rows 1; $? True; error records: 0; warnings: 0; requests: 3 read(s), 0 write(s)
```

### 1.5. A one-time review's end is never moved to today or earlier

- [x] **1.5** `Set-OERAccessReviewDefinition` on `oer-s126-rev-once` with `-Recurrence OneTime -StartDate` ten days ago and `-DurationInDays 5` is refused with `AccessReviewEndNotInFuture`, and no write is sent. #type/subtask

```powershell
Connect-S126
Set-S126NoWrite $true
$Def = Find-S126Review -Name 'oer-s126-rev-once'
$Error.Clear()
$null = Set-OERAccessReviewDefinition -Id ([string]$Def.id) -Recurrence OneTime -StartDate ([datetime]::UtcNow.Date.AddDays(-10)) -DurationInDays 5 `
    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable SetErr
Write-OerLiveStep "Refused: $(@($SetErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessReviewEndNotInFuture*' }).Count) AccessReviewEndNotInFuture record(s); requests: $(Get-S126Count)"
$After = Find-S126Review -Name 'oer-s126-rev-once'
Write-OerLiveStep "The range is unchanged: $([string]$After.settings.recurrence.range.endDate -eq [string]$Def.settings.recurrence.range.endDate)"
Disconnect-OerLive
```

**Expect:** 1 record (inner copies may add more; at least 1); 0 writes; the range unchanged `True`.
**Failure looks like:** a PUT refused by the fence -- the guard is not in the build; another record.

Result: 2026-11-05 15:59 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Set-OERAccessReviewDefinition -Recurrence OneTime -StartDate (ten days ago) -DurationInDays 5 on oer-s126-rev-once was refused with AccessReviewEndNotInFuture after one read (the definition GET) and no write; the range read back unchanged.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] Refused: 1 AccessReviewEndNotInFuture record(s); requests: 1 read(s), 0 write(s)
[oer-s126] The range is unchanged: True
```

## 2. A review of a group's members (B)

### 2.1. The plan, then the real run, create a group review from a document

- [x] **2.1** `Invoke-OERStructure -WhatIf` plans `oer-s126-rev-group` (group `oer-s126-grp-a`, Monthly, a named reviewer) with no write; the real run creates it; read back, its scope is the transitive members of that group. #type/subtask

```powershell
Connect-S126
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-group'; group = 'oer-s126-grp-a'; descriptionForAdmins = 'Sprint 12 step 6 live check'
            reviewers = @($Reviewer); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
Set-S126NoWrite $true
$null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable PlanRows -ErrorVariable PlanErr 3>$null
$PlanOk = $?
Show-S126Row $PlanRows
Write-OerLiveStep "Plan: rows $(@($PlanRows).Count); `$? $PlanOk; error records: $(@($PlanErr).Count); requests: $(Get-S126Count)"
Set-S126NoWrite $false
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests over plan and run: $(Get-S126Count)"
Start-Sleep -Seconds 5
$Def = Find-S126Review -Name 'oer-s126-rev-group'
Add-S126Review -Name 'oer-s126-rev-group' -Id ([string]$Def.id)
Show-S126Review $Def 'read back'
Write-OerLiveStep "The scope is the transitive members of oer-s126-grp-a: $([string]$Def.scope.query -match ('^(/v1\.0)?/groups/' + [regex]::Escape($GrpA) + '/transitiveMembers(/microsoft\.graph\.user)?$'))"
Write-OerLiveStep "The reviewer is oer-s126-reviewer: $(@($Def.reviewers | Where-Object { [string]$_.query -match [regex]::Escape([string]$Ids0['reviewer'].Id) }).Count -eq 1)"
Disconnect-OerLive
```

**Expect:** the plan `accessReviews | oer-s126-rev-group | Skipped | would create access review
'oer-s126-rev-group' | record: none`, `$? True`, 0 writes; the run `Created ... (recurrence:
Monthly)`, `$? True`, 0 error records, 1 write in total; read back `pattern absoluteMonthly 1`; both
last values `True`.
**Failure looks like:** `Failed` with a validator Error (B is not in the build) or `GroupNotFound`
(Graph does not list the group yet -- run again a minute later and record both runs).

Result: 2026-11-05 16:00 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The plan (-WhatIf) of oer-s126-rev-group (group oer-s126-grp-a, Monthly, a named reviewer): one Skipped row "would create", $? True, 1 read and 0 writes. The real run created it (Created, recurrence Monthly; 1 write in total over plan and run). Read back raw, the scope is /v1.0/groups/(grp-a)/transitiveMembers/microsoft.graph.user and the reviewer is oer-s126-reviewer.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
What if: Performing the operation "Create access review definition" on target "oer-s126-rev-group".
[oer-s126] row: accessReviews | oer-s126-rev-group | Skipped | would create access review 'oer-s126-rev-group' | record: none
[oer-s126] Plan: rows 1; $? True; error records: 0; requests: 1 read(s), 0 write(s)
[oer-s126] row: accessReviews | oer-s126-rev-group | Created | created access review 'oer-s126-rev-group' (recurrence: Monthly) | record: none
[oer-s126] Run: rows 1; $? True; error records: 0; warnings: 0; requests over plan and run: 4 read(s), 1 write(s)
[oer-s126] read back: instanceDurationInDays 14; pattern absoluteMonthly 1; range noEnd 2026-11-12..9999-12-31; scope /v1.0/groups/00000000-0000-0000-0000-000000000003/transitiveMembers/microsoft.graph.user
[oer-s126] The scope is the transitive members of oer-s126-grp-a: True
[oer-s126] The reviewer is oer-s126-reviewer: True
```

### 2.2. A second run reports only Unchanged (G8)

- [x] **2.2** The document of 2.1 again: one `Unchanged` row, `$? True`, no write request. #type/subtask

```powershell
Connect-S126
Set-S126NoWrite $true
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-group'; group = 'oer-s126-grp-a'; descriptionForAdmins = 'Sprint 12 step 6 live check'
            reviewers = @($Reviewer); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S126Count)"
Disconnect-OerLive
```

**Expect:** `Unchanged ... already matches`; `$? True`; 0 error records; 0 writes.
**Failure looks like:** `Updated` -- a field of a group review does not converge; a fence refusal.

Result: 2026-11-05 16:00 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The document of 2.1 again: one Unchanged row, $? True, 0 error records, 3 reads and 0 writes under the no-write fence (G8 for a group review).

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] row: accessReviews | oer-s126-rev-group | Unchanged | access review 'oer-s126-rev-group' already matches | record: none
[oer-s126] Run: rows 1; $? True; error records: 0; warnings: 0; requests: 3 read(s), 0 write(s)
```

### 2.3. New-OERAccessReviewDefinition -Group creates a one-time group review, and its document entry is Unchanged

- [x] **2.3** `New-OERAccessReviewDefinition -Group oer-s126-grp-b -Recurrence OneTime -DurationInDays 10 -SelfReview` creates `oer-s126-rev-cmdlet`; read back, its scope is grp-b's members and its range lasts 10 days; then a document entry for it applies `Unchanged` with no write. #type/subtask

```powershell
Connect-S126
$Made = New-OERAccessReviewDefinition -DisplayName 'oer-s126-rev-cmdlet' -DescriptionForAdmins 'Sprint 12 step 6 live check' `
    -DescriptionForReviewers 'Sprint 12 step 6 live check' -Group 'oer-s126-grp-b' -SelfReview `
    -Recurrence OneTime -StartDate $StartDay -DurationInDays 10 -Confirm:$false -ErrorAction Stop
Add-S126Review -Name 'oer-s126-rev-cmdlet' -Id ([string]$Made.AccessReviewDefinitionId)
Write-OerLiveStep "Created: $([bool]$Made.AccessReviewDefinitionId); requests: $(Get-S126Count)"
Start-Sleep -Seconds 5
$Def = Find-S126Review -Name 'oer-s126-rev-cmdlet'
Show-S126Review $Def 'read back'
$Days = ([datetime]::Parse([string]$Def.settings.recurrence.range.endDate, $Inv) - [datetime]::Parse([string]$Def.settings.recurrence.range.startDate, $Inv)).Days
Write-OerLiveStep "The scope is the transitive members of oer-s126-grp-b: $([string]$Def.scope.query -match ('^(/v1\.0)?/groups/' + [regex]::Escape($GrpB) + '/transitiveMembers(/microsoft\.graph\.user)?$')); the range lasts 10 days: $($Days -eq 10)"
Set-S126NoWrite $true
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-cmdlet'; group = 'oer-s126-grp-b'; reviewers = @(); recurrence = 'OneTime'; durationInDays = 10 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); requests in total: $(Get-S126Count)"
Disconnect-OerLive
```

**Expect:** `Created: True` with 1 write (and the group lookup a read); read back `pattern null;
range numbered`; both values `True`; the document row `Unchanged`, `$? True`, 0 error records, still
1 write in total.
**Failure looks like:** a parameter binding error (the `-Group` set is not in the build); `GroupNotFound`.

Result: 2026-11-05 16:01 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. New-OERAccessReviewDefinition -Group oer-s126-grp-b -SelfReview -Recurrence OneTime -DurationInDays 10 created oer-s126-rev-cmdlet with 1 read (the group lookup) and 1 write; read back raw, its scope is /v1.0/groups/(grp-b)/transitiveMembers/microsoft.graph.user and its numbered range lasts 10 days (instanceDurationInDays 10). The document entry for it (group oer-s126-grp-b, OneTime, 10) applied Unchanged with no further write.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] Created: True; requests: 1 read(s), 1 write(s)
[oer-s126] read back: instanceDurationInDays 10; pattern null; range numbered 2026-11-12..2026-11-22; scope /v1.0/groups/00000000-0000-0000-0000-000000000004/transitiveMembers/microsoft.graph.user
[oer-s126] The scope is the transitive members of oer-s126-grp-b: True; the range lasts 10 days: True
[oer-s126] row: accessReviews | oer-s126-rev-cmdlet | Unchanged | access review 'oer-s126-rev-cmdlet' already matches | record: none
[oer-s126] Run: rows 1; $? True; error records: 0; requests in total: 3 read(s), 1 write(s)
```

### 2.4. Two reviews the module cannot write back are made raw: owners as reviewers, and inactive users

- [x] **2.4** Two group reviews are created raw (Graph v1.0 POST): `oer-s126-rev-owners` (scope the members of grp-a, reviewer the owners of grp-b) and `oer-s126-rev-inactive` (scope type inactive users of grp-a, 30 days); read back, the first's reviewer is the owners query and the second keeps its scope type. #type/subtask

```powershell
Connect-S126
$Rec = @{ pattern = [ordered]@{ type = 'absoluteMonthly'; interval = 1; dayOfMonth = $StartDay.Day }; range = [ordered]@{ type = 'noEnd'; startDate = $Start } }
$Settings = @{ mailNotificationsEnabled = $false; reminderNotificationsEnabled = $false; justificationRequiredOnApproval = $false; recommendationsEnabled = $false
    defaultDecisionEnabled = $false; defaultDecision = 'None'; instanceDurationInDays = 14; autoApplyDecisionsEnabled = $false; recurrence = $Rec }
$Specs = [ordered]@{
    'oer-s126-rev-owners'   = @{ scope = @{ '@odata.type' = '#microsoft.graph.accessReviewQueryScope'; query = "/groups/$GrpA/transitiveMembers"; queryType = 'MicrosoftGraph' }
        reviewers = @(@{ query = "/groups/$GrpB/owners"; queryType = 'MicrosoftGraph' }) }
    'oer-s126-rev-inactive' = @{ scope = @{ '@odata.type' = '#microsoft.graph.accessReviewInactiveUsersQueryScope'; inactiveDuration = 'P30D'; query = "/groups/$GrpA/transitiveMembers"; queryType = 'MicrosoftGraph' }
        reviewers = @(@{ query = "/users/$([string]$Ids0['reviewer'].Id)"; queryType = 'MicrosoftGraph' }) }
}
foreach ($Name in $Specs.Keys) {
    $Have = Find-S126Review -Name $Name
    if (-not $Have) {
        $Body = @{ displayName = $Name; descriptionForAdmins = 'Sprint 12 step 6 live check'; descriptionForReviewers = 'Sprint 12 step 6 live check'
            scope = $Specs[$Name].scope; reviewers = $Specs[$Name].reviewers; fallbackReviewers = @(); settings = $Settings }
        $R = Invoke-OerLiveGraph -Method POST -Uri $ArBase -Body $Body
        Write-OerLiveStep "create $Name`: $($R.Status) $($R.Code) $($R.Message)"
        if ($R.Ok) { Add-S126Review -Name $Name -Id ([string]$R.Body.id) }
        Start-Sleep -Seconds 5
        $Have = Find-S126Review -Name $Name
    }
    Write-OerLiveStep ("{0}: scope {1}; scope type {2}; reviewers {3}" -f $Name, $Have.scope.query, $Have.scope['@odata.type'], (@($Have.reviewers | ForEach-Object { $_.query }) -join ' | '))
}
Disconnect-OerLive
```

**Expect:** both created (201) or already there; `oer-s126-rev-owners` reviewers the owners query of grp-b;
`oer-s126-rev-inactive` scope type `#microsoft.graph.accessReviewInactiveUsersQueryScope`.
**Failure looks like:** a 400 for the inactive review -- record Graph's answer; checks 3.1 and 4.2 then
run without it and say so.

Result: 2026-11-05 16:01 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Both raw reviews were created (201). Measured: an owners reviewer reads back as /v1.0/groups/(grp-b)/owners, and a review of inactive users reads back with the SAME query as a review of all members (/v1.0/groups/(grp-a)/transitiveMembers/microsoft.graph.user) and scope type #microsoft.graph.accessReviewInactiveUsersQueryScope -- only the type tells them apart.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] create oer-s126-rev-owners: 201  
[oer-s126] oer-s126-rev-owners: scope /v1.0/groups/00000000-0000-0000-0000-000000000003/transitiveMembers/microsoft.graph.user; scope type #microsoft.graph.accessReviewQueryScope; reviewers /v1.0/groups/00000000-0000-0000-0000-000000000004/owners
[oer-s126] create oer-s126-rev-inactive: 201  
[oer-s126] oer-s126-rev-inactive: scope /v1.0/groups/00000000-0000-0000-0000-000000000003/transitiveMembers/microsoft.graph.user; scope type #microsoft.graph.accessReviewInactiveUsersQueryScope; reviewers /v1.0/users/00000000-0000-0000-0000-000000000005
```

## 3. The export writes a group review, and the export applies unchanged (B)

### 3.1. Export-OERInventory writes the group form, skips the forms it cannot write back, and the exported entries apply Unchanged

- [x] **3.1** `Export-OERInventory -Include AccessReviews` writes `oer-s126-rev-group` with `group` `oer-s126-grp-a` and no `accessPackage`; the guest-only and direct-member measurement reviews are not exported and are counted in the warning; the exported `oer-s126-rev-` entries validate with no Error and apply with only `Unchanged` rows and no write. #type/subtask

```powershell
Connect-S126
$Out = Join-Path $Raw 'export'
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
$null = Export-OERInventory -OutputPath $Out -Include AccessReviews -Confirm:$false -WarningVariable ExWarn 3>$null
Write-OerLiveStep "Export: requests $(Get-S126Count); warnings $(@($ExWarn).Count)"
$Skip = @($ExWarn | Where-Object { [string]$_ -like '*skipped*access review definition(s) the apply document cannot declare*' })
Write-OerLiveStep "The skip warning counts group reviews in a form the module cannot write back: $(@($Skip | Where-Object { [string]$_ -match '(\d+) review\(s\) of a group in a form the module cannot write back' -and [int]$Matches[1] -ge 2 }).Count -eq 1)"
$Inv0 = Get-Content -LiteralPath (Get-ChildItem -LiteralPath $Out -Recurse -Filter 'inventory.json' | Select-Object -First 1).FullName -Raw | ConvertFrom-Json
$Mine = @($Inv0.accessReviews | Where-Object { [string]$_.displayName -like 'oer-s126-rev-*' })
foreach ($E in $Mine) { Write-OerLiveStep ("exported: {0} | group {1} | accessPackage {2} | recurrence {3} | durationInDays {4} | reviewers {5}" -f $E.displayName, $E.group, $E.accessPackage, $E.recurrence, $E.durationInDays, (@($E.reviewers) -join ',')) }
Write-OerLiveStep "Measurement reviews of a guest-only or direct-member scope exported: $(@($Inv0.accessReviews | Where-Object { [string]$_.displayName -in 'oer-s126-g2-guests', 'oer-s126-g3-direct' }).Count)"
Write-OerLiveStep "The owners-reviewer and the inactive-users review exported: $(@($Inv0.accessReviews | Where-Object { [string]$_.displayName -in 'oer-s126-rev-owners', 'oer-s126-rev-inactive' }).Count)"
Write-OerLiveStep "The skip warning counts reviews whose reviewers the module cannot write back: $(@($Skip | Where-Object { [string]$_ -match '(\d+) review\(s\) whose reviewers the module cannot write back' -and [int]$Matches[1] -ge 1 }).Count -eq 1)"
$Doc = [ordered]@{ version = '1.0'; accessReviews = $Mine } | ConvertTo-Json -Depth 10
$Check = Test-OERStructure -Json $Doc
Write-OerLiveStep "Validator: Errors $(@($Check.Errors | Where-Object { $_.Severity -eq 'Error' }).Count)"
Set-S126NoWrite $true
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
$Ok = $?
Show-S126Row $Rows
Write-OerLiveStep "Apply of the export: rows $(@($Rows).Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); `$? $Ok; error records: $(@($Err).Count); requests in total: $(Get-S126Count)"
Disconnect-OerLive
```

**Expect:** the skip warning line `True`; `oer-s126-rev-group | group oer-s126-grp-a | accessPackage
(empty) | recurrence Monthly | durationInDays 14 | reviewers` the reviewer's address;
`oer-s126-rev-cmdlet` with `group oer-s126-grp-b`, OneTime, 10; `oer-s126-rev-once` and
`oer-s126-rev-legacy` with `accessPackage oer-s126-pkg`, OneTime, 14; 0 measurement reviews of the
two other forms exported; the owners-reviewer and inactive-users reviews not exported (0) and the third skip kind counted `True`; the validator 0 Errors; every row `Unchanged`, `$? True`, 0 error records,
0 writes.
**Failure looks like:** a group review exported with `accessPackage`; a guest-only review exported
as `group`; an Error; any row other than `Unchanged`.

Result: 2026-11-05 16:01 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Export-OERInventory -Include AccessReviews (36 reads, 0 writes, one warning: the skip warning). oer-s126-rev-group exported with group oer-s126-grp-a and no accessPackage (the name, unique in the tenant), oer-s126-rev-cmdlet with group oer-s126-grp-b, the two one-time package reviews with accessPackage oer-s126-pkg and durationInDays 14. The guest-only and direct-member measurement reviews, the owners-reviewer review and the inactive-users review were not exported, and the warning counts both skip kinds. The four exported entries validate with 0 Errors and apply with four Unchanged rows, $? True, 0 error records and 0 writes.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] Export: requests 36 read(s), 0 write(s); warnings 1
[oer-s126] The skip warning counts group reviews in a form the module cannot write back: True
[oer-s126] exported: oer-s126-rev-cmdlet | group oer-s126-grp-b | accessPackage  | recurrence OneTime | durationInDays 10 | reviewers self
[oer-s126] exported: oer-s126-rev-group | group oer-s126-grp-a | accessPackage  | recurrence Monthly | durationInDays 14 | reviewers oer-s126-reviewer@example.com
[oer-s126] exported: oer-s126-rev-legacy | group  | accessPackage oer-s126-pkg | recurrence OneTime | durationInDays 14 | reviewers self
[oer-s126] exported: oer-s126-rev-once | group  | accessPackage oer-s126-pkg | recurrence OneTime | durationInDays 14 | reviewers self
[oer-s126] Measurement reviews of a guest-only or direct-member scope exported: 0
[oer-s126] The owners-reviewer and the inactive-users review exported: 0
[oer-s126] The skip warning counts reviews whose reviewers the module cannot write back: True
[oer-s126] Validator: Errors 0
[oer-s126] row: accessReviews | oer-s126-rev-cmdlet | Unchanged | access review 'oer-s126-rev-cmdlet' already matches | record: none
[oer-s126] row: accessReviews | oer-s126-rev-group | Unchanged | access review 'oer-s126-rev-group' already matches | record: none
[oer-s126] row: accessReviews | oer-s126-rev-legacy | Unchanged | access review 'oer-s126-rev-legacy' already matches | record: none
[oer-s126] row: accessReviews | oer-s126-rev-once | Unchanged | access review 'oer-s126-rev-once' already matches | record: none
[oer-s126] Apply of the export: rows 4; not Unchanged: 0; $? True; error records: 0; requests in total: 47 read(s), 0 write(s)
```

## 4. A review with the entry's name that reviews another group is refused (B)

### 4.1. The plan and the real run refuse it, and nothing is written

- [x] **4.1** A document entry `oer-s126-rev-group` declaring group `oer-s126-grp-b` (the live review reviews grp-a) and a new description: the plan and the run each give one `Failed` row with `AccessReviewScopeMismatch`, no write is sent, and the live description is unchanged. #type/subtask

```powershell
Connect-S126
Set-S126NoWrite $true
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-group'; group = 'oer-s126-grp-b'; descriptionForAdmins = 'S126 4.1 must not be written'
            reviewers = @($Reviewer); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable PlanRows -ErrorVariable PlanErr 3>$null
Show-S126Row $PlanRows
Write-OerLiveStep "Plan: error records $(@($PlanErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessReviewScopeMismatch*' }).Count) AccessReviewScopeMismatch"
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
Show-S126Row $Rows
Write-OerLiveStep "Run: error records $(@($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessReviewScopeMismatch*' }).Count) AccessReviewScopeMismatch; requests in total: $(Get-S126Count)"
$Def = Find-S126Review -Name 'oer-s126-rev-group'
Write-OerLiveStep "The live description is unchanged: $([string]$Def.descriptionForAdmins -eq 'Sprint 12 step 6 live check')"
Disconnect-OerLive
```

**Expect:** both rows `accessReviews | oer-s126-rev-group | Failed | Access review
'oer-s126-rev-group' in the tenant reviews ... | record: AccessReviewScopeMismatch`; at least one
`AccessReviewScopeMismatch` record each; 0 writes; the description `True`.
**Failure looks like:** `Updated` or a fence refusal (the engine tried to write the other group's
review); `Failed` with another record.

Result: 2026-11-05 16:02 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The entry oer-s126-rev-group declaring group oer-s126-grp-b (the live review reviews grp-a): the plan and the real run each gave one Failed row with AccessReviewScopeMismatch naming both group ids (one record each, written as the non-terminating error shown), 4 reads (the review lookups and the group lookup) and 0 writes in total; the live description is unchanged.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
Invoke-OERStructure : Access review 'oer-s126-rev-group' in the tenant reviews the members of group '00000000-0000-0000-0000-000000000003', not the group 'oer-s126-grp-b' ('00000000-0000-0000-0000-000000000004') this entry declares, so it is not the review this entry declares. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
At HOME\.claude\jobs\a4eceff3\tmp\child-4.1.ps1:75 char:9
+ $null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable PlanRows  …
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+ CategoryInfo          : InvalidOperation: (oer-s126-rev-group:String) [Invoke-OERStructure], Exception
+ FullyQualifiedErrorId : AccessReviewScopeMismatch,Invoke-OERStructure
[oer-s126] row: accessReviews | oer-s126-rev-group | Failed | Access review 'oer-s126-rev-group' in the tenant reviews the members of group '00000000-0000-0000-0000-000000000003', not the group 'oer-s126-grp-b' ('00000000-0000-0000-0000-000000000004') this entry declares, so it is not the review this entry declares. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name. | record: AccessReviewScopeMismatch
[oer-s126] Plan: error records 1 AccessReviewScopeMismatch
Invoke-OERStructure : Access review 'oer-s126-rev-group' in the tenant reviews the members of group '00000000-0000-0000-0000-000000000003', not the group 'oer-s126-grp-b' ('00000000-0000-0000-0000-000000000004') this entry declares, so it is not the review this entry declares. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
At HOME\.claude\jobs\a4eceff3\tmp\child-4.1.ps1:78 char:9
+ $null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable R …
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+ CategoryInfo          : InvalidOperation: (oer-s126-rev-group:String) [Invoke-OERStructure], Exception
+ FullyQualifiedErrorId : AccessReviewScopeMismatch,Invoke-OERStructure
[oer-s126] row: accessReviews | oer-s126-rev-group | Failed | Access review 'oer-s126-rev-group' in the tenant reviews the members of group '00000000-0000-0000-0000-000000000003', not the group 'oer-s126-grp-b' ('00000000-0000-0000-0000-000000000004') this entry declares, so it is not the review this entry declares. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name. | record: AccessReviewScopeMismatch
[oer-s126] Run: error records 1 AccessReviewScopeMismatch; requests in total: 4 read(s), 0 write(s)
[oer-s126] The live description is unchanged: True
```

### 4.2. A review of the group's inactive users is not the review of all its members

- [x] **4.2** A document entry `oer-s126-rev-inactive` declaring group `oer-s126-grp-a` (the live review reviews only grp-a's inactive users): the plan and the run each give one `Failed` row with `AccessReviewScopeMismatch`, and no write is sent. #type/subtask

```powershell
Connect-S126
Set-S126NoWrite $true
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-inactive'; group = 'oer-s126-grp-a'; reviewers = @($Reviewer); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable PlanRows -ErrorVariable PlanErr 3>$null
Show-S126Row $PlanRows
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
Show-S126Row $Rows
Write-OerLiveStep "AccessReviewScopeMismatch records: plan $(@($PlanErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessReviewScopeMismatch*' }).Count), run $(@($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'AccessReviewScopeMismatch*' }).Count); requests: $(Get-S126Count)"
Disconnect-OerLive
```

**Expect:** both rows `Failed ... record: AccessReviewScopeMismatch`; at least one record each; 0 writes.
**Failure looks like:** `Unchanged` or `Updated` -- the inactive-users scope was read as all members.

Result: 2026-11-05 16:02 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The entry oer-s126-rev-inactive declaring group oer-s126-grp-a (the live review reviews only grp-a's inactive users, same query): the plan and the run each gave one Failed row with AccessReviewScopeMismatch naming the scope type, before any group lookup (2 reads in total, the two review lookups) and 0 writes.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
Invoke-OERStructure : Access review 'oer-s126-rev-inactive' in the tenant does not review the members of a group in the form this module writes (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000003/transitiveMembers/microsoft.graph.user' and its scope type is '#microsoft.graph.accessReviewInactiveUsersQueryScope'), so it is not the review this entry declares for group 'oer-s126-grp-a'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
At HOME\.claude\jobs\a4eceff3\tmp\child-4.2.ps1:74 char:9
+ $null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable PlanRows  …
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+ CategoryInfo          : InvalidOperation: (oer-s126-rev-inactive:String) [Invoke-OERStructure], Exception
+ FullyQualifiedErrorId : AccessReviewScopeMismatch,Invoke-OERStructure
[oer-s126] row: accessReviews | oer-s126-rev-inactive | Failed | Access review 'oer-s126-rev-inactive' in the tenant does not review the members of a group in the form this module writes (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000003/transitiveMembers/microsoft.graph.user' and its scope type is '#microsoft.graph.accessReviewInactiveUsersQueryScope'), so it is not the review this entry declares for group 'oer-s126-grp-a'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name. | record: AccessReviewScopeMismatch
Invoke-OERStructure : Access review 'oer-s126-rev-inactive' in the tenant does not review the members of a group in the form this module writes (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000003/transitiveMembers/microsoft.graph.user' and its scope type is '#microsoft.graph.accessReviewInactiveUsersQueryScope'), so it is not the review this entry declares for group 'oer-s126-grp-a'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
At HOME\.claude\jobs\a4eceff3\tmp\child-4.2.ps1:76 char:9
+ $null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable R …
+         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
+ CategoryInfo          : InvalidOperation: (oer-s126-rev-inactive:String) [Invoke-OERStructure], Exception
+ FullyQualifiedErrorId : AccessReviewScopeMismatch,Invoke-OERStructure
[oer-s126] row: accessReviews | oer-s126-rev-inactive | Failed | Access review 'oer-s126-rev-inactive' in the tenant does not review the members of a group in the form this module writes (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000003/transitiveMembers/microsoft.graph.user' and its scope type is '#microsoft.graph.accessReviewInactiveUsersQueryScope'), so it is not the review this entry declares for group 'oer-s126-grp-a'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name. | record: AccessReviewScopeMismatch
[oer-s126] AccessReviewScopeMismatch records: plan 1, run 1; requests: 2 read(s), 0 write(s)
```

## 5. A package review behaves as before the step

### 5.1. A Monthly package review is created, then Unchanged (G8)

- [x] **5.1** `oer-s126-rev-pkg` (package, Monthly, 14 days, self review) is created; the second run is `Unchanged` with no write. #type/subtask

```powershell
Connect-S126
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-pkg'; accessPackage = 'oer-s126-pkg'; assignmentPolicy = 'oer-s126-pol'
            reviewers = @(); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
Show-S126Row $Rows
Write-OerLiveStep "Run 1: `$? $?; error records $(@($Err).Count); requests $(Get-S126Count)"
Start-Sleep -Seconds 5
$Def = Find-S126Review -Name 'oer-s126-rev-pkg'
Add-S126Review -Name 'oer-s126-rev-pkg' -Id ([string]$Def.id)
Show-S126Review $Def 'read back'
Set-S126NoWrite $true
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows2 -ErrorVariable Err2 3>$null
Show-S126Row $Rows2
Write-OerLiveStep "Run 2: error records $(@($Err2).Count); requests in total $(Get-S126Count)"
Disconnect-OerLive
```

**Expect:** run 1 `Created ... (recurrence: Monthly)`, 1 write; read back `pattern absoluteMonthly 1;
range noEnd`; run 2 `Unchanged`, still 1 write in total, 0 error records.
**Failure looks like:** anything else.

Result: 2026-11-05 16:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The package review oer-s126-rev-pkg (Monthly, 14 days, self review) was created with one write and read back with pattern absoluteMonthly 1 and a noEnd range; the second run gave one Unchanged row with no further write (G8 for the package create path).

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s126] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s126] The module is the worktree's build: True
[oer-s126] Token fence in place: True
[oer-s126] row: accessReviews | oer-s126-rev-pkg | Created | created access review 'oer-s126-rev-pkg' (recurrence: Monthly) | record: none
[oer-s126] Run 1: $? True; error records 0; requests 4 read(s), 1 write(s)
[oer-s126] read back: instanceDurationInDays 14; pattern absoluteMonthly 1; range noEnd 2026-11-12..9999-12-31; scope /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq '00000000-0000-0000-0000-000000000001' and assignmentPolicy/id eq '00000000-0000-0000-0000-000000000002')
[oer-s126] row: accessReviews | oer-s126-rev-pkg | Unchanged | access review 'oer-s126-rev-pkg' already matches | record: none
[oer-s126] Run 2: error records 0; requests in total 7 read(s), 1 write(s)
```

### 5.2. The plan of a change is the same with the build of main and with this branch's build

- [x] **5.2** The same package document with a new `descriptionForAdmins`, planned with `-WhatIf` once with the build of `main` (the base of this branch) and once with this branch's build: the two plans give the same rows, and neither writes. #type/subtask

```powershell
$BaseRepo = $env:OER_LIVE_BASE_REPO
$Doc = [ordered]@{ version = '1.0'; accessReviews = @([ordered]@{
            displayName = 'oer-s126-rev-pkg'; accessPackage = 'oer-s126-pkg'; assignmentPolicy = 'oer-s126-pol'; descriptionForAdmins = 'S126 5.2 plan only'
            reviewers = @(); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$Plans = @{}
foreach ($Which in 'base', 'branch') {
    $Child = Join-Path $env:TEMP "s126-5.2-$Which.ps1"
    $Repo = if ($Which -eq 'base') { $BaseRepo } else { $Cfg.Repo }
    @"
`$env:PSModulePath = '$(Join-Path $Cfg.Repo 'output\RequiredModules')' + [IO.Path]::PathSeparator + `$env:PSModulePath
Import-Module (Join-Path '$VaultDir' 'OerLive\OerLive.psm1') -Force
`$Cfg = Import-OerLiveConfig -Prefix 'oer-s126-' -ConfigDirectory '$VaultDir'
`$Cfg.Repo = '$Repo'
Connect-OerLive -Arm
function global:Get-AzToken { throw 'S126 fence' }
`$null = Invoke-OERStructure -Json '$($Doc -replace "'", "''")' -WhatIf -OutVariable Rows 3>`$null
foreach (`$R in `$Rows) { '{0}|{1}|{2}|{3}' -f `$R.Section, `$R.Item, `$R.Action, `$R.Detail }
Disconnect-OerLive
"@ | Set-Content -LiteralPath $Child -Encoding utf8NoBOM
    $All = @(pwsh -NoProfile -NonInteractive -File $Child 2>$null)
    foreach ($L in @($All | Where-Object { $_ -match 'loaded from' })) { Write-OerLiveStep "$Which module: $(($L -replace '^\[oer-s126\] ', ''))" }
    $Plans[$Which] = @($All | Where-Object { $_ -match '^accessReviews\|' })
    Remove-Item -LiteralPath $Child
    foreach ($L in $Plans[$Which]) { Write-OerLiveStep "$Which plan: $L" }
}
Write-OerLiveStep "The two plans are the same: $((($Plans['base'] -join "`n") -ceq ($Plans['branch'] -join "`n")) -and $Plans['base'].Count -gt 0)"
```

**Expect:** each plan one row `accessReviews|oer-s126-rev-pkg|Skipped|would update access review
'oer-s126-rev-pkg' (descriptionForAdmins=S126 5.2 plan only)`; the two plans the same `True`.
**Failure looks like:** the rows differ -- the step changed what a package review plans.

Result: 2026-11-05 16:04 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A description change of the package review, planned with -WhatIf once with the build of main (1f8e905, built before the branch's first commit) and once with this branch's build, gave the same single row (Skipped, would update ... descriptionForAdmins=...), and neither wrote. The block was first run without the lines naming which build each plan loaded; it was amended to print them and run again (this result), with the same rows.

[oer-s126] base module: Omnicit.EntraRBAC 1.3.2 loaded from HOME\.claude\jobs\a4eceff3\tmp\before-1f8e905\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] base plan: accessReviews|oer-s126-rev-pkg|Skipped|would update access review 'oer-s126-rev-pkg' (descriptionForAdmins=S126 5.2 plan only)
[oer-s126] branch module: Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] branch plan: accessReviews|oer-s126-rev-pkg|Skipped|would update access review 'oer-s126-rev-pkg' (descriptionForAdmins=S126 5.2 plan only)
[oer-s126] The two plans are the same: True
```

## Teardown

### T.1. Remove every object with the prefix

- [x] **T.1** The prerequisite script's teardown removes the access review definitions first, then the policy and the package, the catalog, the groups and the user; the sweep is 0. #type/subtask

```powershell
pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS126Prereq.ps1') -Teardown -Unattended
```

**Expect:** `Teardown summary: Removed` the objects, `Residue 0`; `Teardown complete: the sweep is 0.`
**Failure looks like:** `Residue` above 0 or `Left:` lines -- run `-Teardown` again later and record
both runs.

Result: 2026-11-05 16:05 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The prerequisite script's teardown (OerLive 1.1.0, with the recorded ids) deleted the 17 access review definitions first (the measurement reviews and every review these checks made), then the policy, the package, the catalog, both groups and the user: removed 23, residue 0, unreadable 0, already gone 0, skipped 0. The sweep listed 2 objects once (listing lag) and then 0; teardown complete: the sweep is 0.

[oer-s126] Transcript (redacted): raw\s126\prereq-teardown-20261105-160407Z.log; OerLive 1.1.0.
[oer-s126] Omnicit.EntraRBAC 1.1.2 loaded from REPO\output\module\Omnicit.EntraRBAC\1.1.2.
[oer-s126] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s126] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s126-', the other 5 are left untouched.
[oer-s126] Teardown: Remove-OerLiveTestObjects for the prefix with the recorded ids.
[oer-s126] Teardown of 'oer-s126-': users 1, groups 2, access packages 1, access review definitions 17, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s126] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s126] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s126] Teardown 3/6: access review definitions, access package resource roles, access packages, catalog resources, catalogs.
[oer-s126] Deleted: access review definition oer-s126-rev-pkg (204).
[oer-s126] Deleted: access review definition oer-s126-rev-inactive (204).
[oer-s126] Deleted: access review definition oer-s126-rev-owners (204).
[oer-s126] Deleted: access review definition oer-s126-rev-cmdlet (204).
[oer-s126] Deleted: access review definition oer-s126-rev-group (204).
[oer-s126] Deleted: access review definition oer-s126-rev-legacy (204).
[oer-s126] Deleted: access review definition oer-s126-rev-once (204).
[oer-s126] Deleted: access review definition oer-s126-g5-group-reviewer (204).
[oer-s126] Deleted: access review definition oer-s126-g4-notype (204).
[oer-s126] Deleted: access review definition oer-s126-g3-direct (204).
[oer-s126] Deleted: access review definition oer-s126-g2-guests (204).
[oer-s126] Deleted: access review definition oer-s126-g1-members-monthly (204).
[oer-s126] Deleted: access review definition oer-s126-m5-numbered-future (204).
[oer-s126] Deleted: access review definition oer-s126-m4-enddate (204).
[oer-s126] Deleted: access review definition oer-s126-m3-numbered-noend (204).
[oer-s126] Deleted: access review definition oer-s126-m2-numbered-end (204).
[oer-s126] Deleted: access review definition oer-s126-m1-onetime-module (204).
[oer-s126] Deleted: oer-s126-pkg: assignment policy 'oer-s126-pol' (204).
[oer-s126] Deleted: access package oer-s126-pkg (204, 1 attempt(s)).
[oer-s126] Deleted: catalog oer-s126-cat (204, 1 attempt(s)).
[oer-s126] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s126] Teardown 5/6: the prefixed groups.
[oer-s126] Deleted: group oer-s126-grp-a (204).
[oer-s126] Deleted: group oer-s126-grp-b (204).
[oer-s126] Teardown 6/6: the prefixed users.
[oer-s126] DELETE user oer-s126-reviewer@example.com: 204  after 1 attempt(s), 0.2 s; first attempt no membership removed in this run.
[oer-s126] Teardown of 'oer-s126-': removed 23, residue 0, unreadable 0, already gone 0, skipped 0.
[oer-s126] Teardown summary: Removed 23, Residue 0, Unreadable 0, Unread 0, AlreadyGone 0, Skipped 0
[oer-s126] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s126-' is left.
[oer-s126] Sweep: 2 object(s) with the prefix, 0 unread kind(s).
[oer-s126] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s126-' is left.
[oer-s126] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s126-' is left.
[oer-s126] Sweep: 0 object(s) with the prefix, 0 unread kind(s).
[oer-s126] Teardown complete: the sweep is 0.
```

### T.2. The sweep is still 0 a minute later, and raw output is removed

- [x] **T.2** A minute after T.1 the prefix sweep is still 0, and the step's raw folder is deleted. #type/subtask

```powershell
Connect-OerLive -Graph
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "Sweep a minute later: $($Left.Count) object(s) or unread kind(s) with the prefix."
Disconnect-OerLive
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "Raw folder removed: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** 0; `Raw folder removed: True`.
**Failure looks like:** an object listed -- run T.1 again.

Result: 2026-11-05 16:06 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The prefix sweep a few minutes after T.1 is 0 objects and 0 unread kinds, and the step's raw folder in the clone is deleted. The redacted measurement answers made before the plan were copied first to the vault folder raw\s126 (38 files, leak check 0), where the report cites them.

[oer-s126] Omnicit.EntraRBAC 1.3.2 loaded from REPO\.claude\worktrees\s12-steg6\output\module\Omnicit.EntraRBAC\1.3.2.
[oer-s126] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s126] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s126] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s126-' is left.
[oer-s126] Sweep a minute later: 0 object(s) or unread kind(s) with the prefix.
[oer-s126] Raw folder removed: True
```
