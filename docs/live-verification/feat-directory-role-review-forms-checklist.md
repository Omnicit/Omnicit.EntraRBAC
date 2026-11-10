# Live verification checklist -- eligible-only and active-only directory role reviews (feat/directory-role-review-forms)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Only objects of the prefix `oer-s144-`, and access reviews
only of the two low-risk directory roles Reports Reader and Message Center Reader. The measurement
(`Initialize-OerS144Prereq.ps1 -Measure`) created `oer-s144-m-elig` and `oer-s144-m-active`; the
prerequisite script creates three more: `oer-s144-elig` (the eligible assignments of Reports Reader),
`oer-s144-act` (the active assignments of Message Center Reader) and `oer-s144-all` (the users assigned to
Reports Reader, the form written before this branch). The checks create
`oer-s144-del`, `oer-s144-dact`, `oer-s144-cel` and `oer-s144-cact`. Every review is a one-time
self-review that starts seven days ahead and sends no mail, so no instance starts while it exists.
Every check runs with a request fence in the module's scope that refuses a write whose target is not
a prefixed review, and the checks that expect no write run with a fence that refuses every write.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A new document key, `directoryRoleAssignmentType`** (`Eligible` or `Active`) beside
  `directoryRole`: a review of only the eligible or only the active assignments of the role. Omitted
  means the review of the users assigned to the role, as before.
- **B. `New-OERAccessReviewDefinition -DirectoryRoleAssignmentType`** (in the two directory role
  parameter sets only) creates such a review.
- **C. The target check** refuses a live review found by the entry's name in another form of the role
  (`AccessReviewScopeMismatch`), before anything is written: the scope of a review cannot change.
- **D. The export** writes `directoryRoleAssignmentType` for an eligible-only or active-only review
  instead of skipping it; a role review in any other form is still skipped and counted.
- **E. A document without the key gives the same result as on `main`.**

## What this file does not check, and why

- **Who is asked to review** (BL-175b): no instance starts (every review starts seven days ahead and is
  deleted in the teardown), and neither low-risk role holds an assignee in the test tenant, so an
  instance would have no decision to read. Measured in M.3 as not measurable.
- **An unknown `directoryRoleAssignmentType` value** (class B): the offline validator refuses it before
  any request; the unit tests hold it.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree; for
  check 5.1 also the base commit's source, its folder in `OER_BASE_SOURCE` (the folder holding
  `Omnicit.EntraRBAC.psd1`, loaded in development mode with the worktree's `output\RequiredModules`).
- The prerequisite script `Initialize-OerS144Prereq.ps1` beside OerLive: run it once with `-WhatIf`,
  then with `-Unattended`; every `Read back` line must be `True`.

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block).

### H.1. The helpers every check uses

- [x] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s144-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s144'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$ArBase = 'v1.0/identityGovernance/accessReviews/definitions'
$IdFile = Join-Path $Raw 'known-ids.json'
$Ids0 = @{}
if (Test-Path -LiteralPath $IdFile) { $Ids0 = Get-Content -LiteralPath $IdFile -Raw | ConvertFrom-Json -AsHashtable }
$CheckFile = Join-Path $Raw 'check-ids.json'
$Start = (Get-Date).ToUniversalTime().Date.AddDays(7).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
function New-S144Entry {
    # One accessReviews[] entry: a one-time self-review seven days ahead that sends no mail.
    param([string]$Name, [System.Collections.IDictionary]$Target, [string]$Description = 'Sprint 14 step 4 live check (oer-s144-)')
    $E = [ordered]@{ displayName = $Name }
    foreach ($K in $Target.Keys) { $E[$K] = $Target[$K] }
    $E.descriptionForAdmins = $Description; $E.descriptionForReviewers = 'Sprint 14 step 4 live check (oer-s144-)'
    $E.reviewers = @('self'); $E.recurrence = 'OneTime'; $E.startDate = $Start; $E.durationInDays = 3
    $E.mailNotification = $false; $E.reminderNotification = $false; $E.requireJustification = $false
    $E.recommendationsEnabled = $false; $E.autoApplyDecisions = $false; $E.defaultDecision = 'None'
    $E
}
function New-S144Doc { param([object[]]$Entry) [ordered]@{ version = '1.0'; accessReviews = @($Entry) } | ConvertTo-Json -Depth 10 }
function Connect-S144 {
    Connect-OerLive -Arm
    $script:S144Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S144Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    Install-S144Fence
}
function Install-S144Fence {
    function global:Get-AzToken { throw 'S144 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S144Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S144Module {
        $script:S144Log = [System.Collections.Generic.List[string]]::new()
        $script:S144Created = [System.Collections.Generic.List[string]]::new()
        $script:S144NoWrite = $false
        $script:S144RealGraph = ${function:Invoke-OERGraphRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
            $script:S144Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
            if (-not $Read) {
                if ($script:S144NoWrite) { throw "S144 fence: a $Method request was refused; this check expects no write." }
                $Ok = $Uri -match '^v1\.0/identityGovernance/accessReviews/definitions(/[0-9a-f-]{36})?$' -and
                    ($Method -ne 'POST' -or ([string]$Body.displayName).StartsWith('oer-s144-', [System.StringComparison]::Ordinal))
                if (-not $Ok) { throw "S144 fence: a $Method outside the prefixed access reviews was refused." }
            }
            $R = & $script:S144RealGraph @PSBoundParameters
            if ($Method -eq 'POST' -and $R.id) { $script:S144Created.Add([string]$R.id) }
            $R
        }
    }
    Write-OerLiveStep "Request fence in place: $((& $script:S144Module { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S144 fence' }))"
}
function Set-S144NoWrite { param([bool]$On) & $script:S144Module { param($V) $script:S144NoWrite = $V } $On }
function Get-S144Count { & $script:S144Module { '{0} read(s), {1} write(s)' -f @($script:S144Log | Where-Object { $_ -eq 'read' }).Count, @($script:S144Log | Where-Object { $_ -ne 'read' }).Count } }
function Reset-S144Count { & $script:S144Module { $script:S144Log.Clear() } }
function Save-S144Created {
    # The ids this check created, kept for the teardown's -KnownId.
    $New = @(& $script:S144Module { $script:S144Created.ToArray() })
    $Old = @()
    if (Test-Path -LiteralPath $CheckFile) { $Old = @(Get-Content -LiteralPath $CheckFile -Raw | ConvertFrom-Json) }
    ConvertTo-Json -InputObject @(@($Old) + @($New) | Select-Object -Unique) | Set-Content -LiteralPath $CheckFile -Encoding utf8NoBOM
}
function Show-S144Row { param($Rows) foreach ($R in @($Rows)) { Write-OerLiveStep ("row: {0} | {1} | {2} | record: {3}" -f $R.Section, $R.Item, $R.Action, $(if ($R.Error) { ([string]$R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })) } }
function Get-S144RoleId {
    param([string]$Name)
    $R = Invoke-OerLiveGraph -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq '$Name'&`$select=id"
    [string]@($R.Body.value)[0].id
}
function Read-S144Review {
    # The review of that exact name, raw, as Graph lists it (one expected).
    param([string]$Name)
    $R = Invoke-OerLiveGraph -Uri "$ArBase`?`$filter=displayName eq '$Name'"
    @($R.Body.value | Where-Object { [string]$_.displayName -ceq $Name })
}
function Get-S144ScopeText {
    # The scope as compact JSON with the two role ids written as ROLE-RR and ROLE-MCR.
    param($Scope, [string]$Rr, [string]$Mcr)
    (ConvertTo-Json -InputObject $Scope -Depth 10 -Compress).Replace($Rr, 'ROLE-RR').Replace($Mcr, 'ROLE-MCR')
}
function Test-S144Form {
    # Graph's read-back of the eligible-only or active-only form for that role id (measured in M.1, M.2).
    param($Scope, [ValidateSet('Eligible', 'Active')][string]$Form, [string]$RoleId)
    $Q = if ($Form -eq 'Eligible') {
        "/beta/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '$RoleId')"
    } else {
        "/beta/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '$RoleId')"
    }
    [bool]([string]$Scope['@odata.type'] -eq '#microsoft.graph.accessReviewQueryScope' -and [string]$Scope.query -ceq $Q)
}
```

**Expect:** nothing printed.
**Failure looks like:** a parse error -- fix the block before any check runs.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The helpers parse and load in every check (the runner prepends them); nothing is printed by them and nothing is sent.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
```

## M. The measurement, before any code (A6)

### M.1. Graph accepts the eligible-only form and reads it back as the same form

- [x] **M.1** `Initialize-OerS144Prereq.ps1 -Measure` created `oer-s144-m-elig` with the eligible-only query of Reports Reader written exactly as `Resolve-OERAccessReviewRoleScope` reads it (no version prefix): POST 201; the read by id and the list return it with a leading `/beta`; the base build's converter and classifier read it as `Eligible` with the same role id. #type/subtask

The measurement ran once, before any code of this branch was written
(`pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS144Prereq.ps1') -Measure -Unattended`);
this block reads its redacted record. Do not run the measurement again: a second run finds the recorded
reviews and sends no POST.

```powershell
$M = Get-Content -LiteralPath (Join-Path $Raw 'measure.json') -Raw | ConvertFrom-Json
$F = @($M.Forms | Where-Object { $_.Form -eq 'elig' })[0]
Write-OerLiveStep "elig: POST $($F.PostStatus); read by id $($F.ReadByIdStatus); kind by id $($F.KindById), listed $($F.KindListed); same role id $($F.RoleIdMatchesById)/$($F.RoleIdMatchesListed)"
Write-OerLiveStep "elig stored: $($F.ReadByIdScope.query)"
```

**Expect:** POST 201; read 200; `Eligible` both ways; `True/True`; the stored query is the written one with a leading `/beta`.
**Failure looks like:** a 400 (the form is not built, A6), or another kind.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Measured before any code (2026-11-10 02:53 UTC): the eligible-only query of Reports Reader, written exactly as the classifier reads it, answered POST 201; the read by id answered 200; Graph stores it with a leading /beta; the base build's converter and classifier read it as Eligible by id and in the list, with the same role id.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] elig: POST 201; read by id 200; kind by id Eligible, listed Eligible; same role id True/True
[oer-s144] elig stored: /beta/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal&$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq 'ROLE-RR')
```

### M.2. Graph accepts the active-only form and reads it back as the same form

- [x] **M.2** The same for `oer-s144-m-active` (the active-only query of Reports Reader): POST 201; read back with a leading `/beta`; classified `Active` with the same role id. #type/subtask

```powershell
$M = Get-Content -LiteralPath (Join-Path $Raw 'measure.json') -Raw | ConvertFrom-Json
$F = @($M.Forms | Where-Object { $_.Form -eq 'active' })[0]
Write-OerLiveStep "active: POST $($F.PostStatus); read by id $($F.ReadByIdStatus); kind by id $($F.KindById), listed $($F.KindListed); same role id $($F.RoleIdMatchesById)/$($F.RoleIdMatchesListed)"
Write-OerLiveStep "active stored: $($F.ReadByIdScope.query)"
```

**Expect:** as M.1, with `Active`.
**Failure looks like:** as M.1.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Measured before any code: the active-only query of Reports Reader answered POST 201, read 200, stored with a leading /beta, classified Active both ways with the same role id.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] active: POST 201; read by id 200; kind by id Active, listed Active; same role id True/True
[oer-s144] active stored: /beta/roleManagement/directory/roleAssignmentScheduleInstances?$expand=principal&$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq 'ROLE-RR')
```

### M.3. Who a role review's instance covers (BL-175b)

- [~] **M.3** The measurement counts the assignees of the two low-risk roles by principal type; with a service principal assignee it would create two reviews starting today and read their decisions. #type/subtask

```powershell
$M = Get-Content -LiteralPath (Join-Path $Raw 'measure.json') -Raw | ConvertFrom-Json
foreach ($Role in 'Reports Reader', 'Message Center Reader') {
    $A = $M.Assignees.$Role
    Write-OerLiveStep "${Role}: active $(@($A.Active.PSObject.Properties).Count) principal type(s), eligible $(@($A.Eligible.PSObject.Properties).Count) principal type(s)"
}
Write-OerLiveStep "Note: $($M.InstanceNote)"
```

**Expect:** a count per role and the note; when no role has a service principal assignee, the check is `[~]`.
**Failure looks like:** a read error.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: NOT MEASURED (BL-175b). Neither low-risk role holds any assignee in the test tenant (active 0, eligible 0, every principal type), so an instance would have no decision to read; giving a service principal the role needs a role assignment and an app registration, objects outside this step. Nothing was created for it.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Reports Reader: active 0 principal type(s), eligible 0 principal type(s)
[oer-s144] Message Center Reader: active 0 principal type(s), eligible 0 principal type(s)
[oer-s144] Note: no low-risk role has a service principal assignee: BL-175b not measured (giving one needs a role assignment to an object outside the prefix or an app registration)
```

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the prerequisite objects are recorded. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Get-Content -LiteralPath (Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1') -Raw
foreach ($Marker in @(
        , @('A (schema)', '"directoryRoleAssignmentType": {')
        , @('B', '$DirectoryRoleAssignmentType')
        , @('D', '(guest users only, or another query)'))) {
    Write-OerLiveStep "The build carries $($Marker[0]): $($Psm1.Contains($Marker[1]))"
}
Write-OerLiveStep ("Recorded: reviews elig {0} act {1} all {2} m-elig {3} m-active {4}" -f
    [bool]$Ids0['elig'].Id, [bool]$Ids0['act'].Id, [bool]$Ids0['all'].Id, [bool]$Ids0['m-elig'].Id, [bool]$Ids0['m-active'].Id)
```

**Expect:** every line `True`; the HEAD is this branch's tip; 0 tracked changes.
**Failure looks like:** `False` on a marker (rebuild the worktree), or the main clone named.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The module loads from the step worktree's build (built by the green gate at 683ebae; the later commits change only this checklist); every marker is present; every prerequisite review is recorded; 0 tracked changes.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] The module loads from a worktree that is not the main clone: True
[oer-s144] Worktree: branch feat/directory-role-review-forms; HEAD 13231f9 docs: name the earlier role review form in the live checklist as measured; tracked changes: 0
[oer-s144] The build carries A (schema): True
[oer-s144] The build carries B: True
[oer-s144] The build carries D: True
[oer-s144] Recorded: reviews elig True act True all True m-elig True m-active True
```

## 1. A review in each form from a document (A, C)

### 1.1. Eligible: the plan, then the run, create the review

- [x] **1.1** `Invoke-OERStructure -WhatIf` of a document declaring `directoryRole: Reports Reader` with `directoryRoleAssignmentType: Eligible` plans the review and writes nothing; the real run creates `oer-s144-del`, and Graph reads back the eligible-only form of Reports Reader. #type/subtask

```powershell
Connect-S144
$Rr = Get-S144RoleId -Name 'Reports Reader'; $Mcr = Get-S144RoleId -Name 'Message Center Reader'
$Doc = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-del' -Target ([ordered]@{ directoryRole = 'Reports Reader'; directoryRoleAssignmentType = 'Eligible' }))
Set-S144NoWrite $true
$Plan = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction Continue)
Show-S144Row $Plan
Write-OerLiveStep "Plan: $(Get-S144Count)"
Set-S144NoWrite $false
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S144Row $Rows
Save-S144Created
Write-OerLiveStep "Run and plan: $(Get-S144Count)"
$Live = Wait-OerLiveConverged -Activity 'the new review is listed' -Read { Read-S144Review -Name 'oer-s144-del' } -Test { param($V) @($V).Count -eq 1 }
$Rv = @($Live.Value)[0]
Write-OerLiveStep "Listed once: $(@($Live.Value).Count -eq 1); read back: $(Get-S144ScopeText -Scope $Rv.scope -Rr $Rr -Mcr $Mcr)"
Write-OerLiveStep "The read-back is the eligible-only form of Reports Reader: $(Test-S144Form -Scope $Rv.scope -Form Eligible -RoleId $Rr)"
```

**Expect:** the plan row `Skipped` (it would create), 0 writes in the plan; the run row `Created`, 1
write (one POST); the read-back is the eligible-only form of Reports Reader.
**Failure looks like:** a `Failed` row, a fence refusal, or another scope read back (the All form).

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Plan: Skipped (would create), 1 read, 0 writes. Run: Created with 1 write (one POST). Graph reads back the eligible-only form of Reports Reader (the written query with a leading /beta).

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
What if: Performing the operation "Create access review definition" on target "oer-s144-del".
[oer-s144] row: accessReviews | oer-s144-del | Skipped | record: none
[oer-s144] Plan: 1 read(s), 0 write(s)
[oer-s144] row: accessReviews | oer-s144-del | Created | record: none
[oer-s144] Run and plan: 3 read(s), 1 write(s)
[oer-s144] the new review is listed: converged after 1 read(s), 0.1 s.
[oer-s144] Listed once: True; read back: {"queryType":"MicrosoftGraph","queryRoot":null,"@odata.type":"#microsoft.graph.accessReviewQueryScope","query":"/beta/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal&$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq 'ROLE-RR')"}
[oer-s144] The read-back is the eligible-only form of Reports Reader: True
```

### 1.2. Eligible: the same document again, only Unchanged (G8)

- [x] **1.2** The document of 1.1 applied again reports `Unchanged` and writes nothing. #type/subtask

```powershell
Connect-S144
$Doc = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-del' -Target ([ordered]@{ directoryRole = 'Reports Reader'; directoryRoleAssignmentType = 'Eligible' }))
Set-S144NoWrite $true
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S144Row $Rows
Write-OerLiveStep "Every row Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0) ($($Rows.Count) row(s)); $(Get-S144Count)"
```

**Expect:** one row `Unchanged`; 0 writes.
**Failure looks like:** `Updated`, `Failed` (the form was read as another), or a fence refusal.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The same document again: one row Unchanged, 2 reads, 0 writes (G8).

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-del | Unchanged | record: none
[oer-s144] Every row Unchanged: True (1 row(s)); 2 read(s), 0 write(s)
```

### 1.3. Active: the plan, then the run, create the review

- [x] **1.3** The same with `directoryRole: Message Center Reader` and `directoryRoleAssignmentType: Active`: the plan writes nothing, the run creates `oer-s144-dact`, and Graph reads back the active-only form of Message Center Reader. #type/subtask

```powershell
Connect-S144
$Rr = Get-S144RoleId -Name 'Reports Reader'; $Mcr = Get-S144RoleId -Name 'Message Center Reader'
$Doc = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-dact' -Target ([ordered]@{ directoryRole = 'Message Center Reader'; directoryRoleAssignmentType = 'Active' }))
Set-S144NoWrite $true
$Plan = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction Continue)
Show-S144Row $Plan
Write-OerLiveStep "Plan: $(Get-S144Count)"
Set-S144NoWrite $false
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S144Row $Rows
Save-S144Created
Write-OerLiveStep "Run and plan: $(Get-S144Count)"
$Live = Wait-OerLiveConverged -Activity 'the new review is listed' -Read { Read-S144Review -Name 'oer-s144-dact' } -Test { param($V) @($V).Count -eq 1 }
$Rv = @($Live.Value)[0]
Write-OerLiveStep "Listed once: $(@($Live.Value).Count -eq 1); read back: $(Get-S144ScopeText -Scope $Rv.scope -Rr $Rr -Mcr $Mcr)"
Write-OerLiveStep "The read-back is the active-only form of Message Center Reader: $(Test-S144Form -Scope $Rv.scope -Form Active -RoleId $Mcr)"
```

**Expect:** as 1.1, with the active-only form of Message Center Reader.
**Failure looks like:** as 1.1.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Plan: Skipped, 0 writes. Run: Created with 1 write. Graph reads back the active-only form of Message Center Reader.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
What if: Performing the operation "Create access review definition" on target "oer-s144-dact".
[oer-s144] row: accessReviews | oer-s144-dact | Skipped | record: none
[oer-s144] Plan: 1 read(s), 0 write(s)
[oer-s144] row: accessReviews | oer-s144-dact | Created | record: none
[oer-s144] Run and plan: 3 read(s), 1 write(s)
[oer-s144] the new review is listed: converged after 1 read(s), 0.3 s.
[oer-s144] Listed once: True; read back: {"query":"/beta/roleManagement/directory/roleAssignmentScheduleInstances?$expand=principal&$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq 'ROLE-MCR')","@odata.type":"#microsoft.graph.accessReviewQueryScope","queryRoot":null,"queryType":"MicrosoftGraph"}
[oer-s144] The read-back is the active-only form of Message Center Reader: True
```

### 1.4. Active: the same document again, only Unchanged (G8)

- [x] **1.4** The document of 1.3 applied again reports `Unchanged` and writes nothing. #type/subtask

```powershell
Connect-S144
$Doc = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-dact' -Target ([ordered]@{ directoryRole = 'Message Center Reader'; directoryRoleAssignmentType = 'Active' }))
Set-S144NoWrite $true
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S144Row $Rows
Write-OerLiveStep "Every row Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0) ($($Rows.Count) row(s)); $(Get-S144Count)"
```

**Expect:** one row `Unchanged`; 0 writes.
**Failure looks like:** as 1.2.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The same document again: one row Unchanged, 0 writes (G8).

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-dact | Unchanged | record: none
[oer-s144] Every row Unchanged: True (1 row(s)); 2 read(s), 0 write(s)
```

## 2. New-OERAccessReviewDefinition -DirectoryRoleAssignmentType (B)

### 2.1. The parameter creates an eligible-only review

- [x] **2.1** `New-OERAccessReviewDefinition -DirectoryRole 'Message Center Reader' -DirectoryRoleAssignmentType Eligible -SelfReview` creates `oer-s144-cel` with one POST, and Graph reads back the eligible-only form of Message Center Reader. #type/subtask

```powershell
Connect-S144
$Rr = Get-S144RoleId -Name 'Reports Reader'; $Mcr = Get-S144RoleId -Name 'Message Center Reader'
$New = New-OERAccessReviewDefinition -DisplayName 'oer-s144-cel' -DescriptionForAdmins 'Sprint 14 step 4 live check (oer-s144-)' `
    -DescriptionForReviewers 'Sprint 14 step 4 live check (oer-s144-)' -DirectoryRole 'Message Center Reader' -DirectoryRoleAssignmentType Eligible `
    -SelfReview -Recurrence OneTime -StartDate ([datetime]$Start) -DurationInDays 3 -ErrorAction Stop
Save-S144Created
Write-OerLiveStep "Returned: $([bool]$New); ScopeType $($New.ScopeType); $(Get-S144Count)"
$Live = Wait-OerLiveConverged -Activity 'the new review is listed' -Read { Read-S144Review -Name 'oer-s144-cel' } -Test { param($V) @($V).Count -eq 1 }
Write-OerLiveStep "Read back: $(Get-S144ScopeText -Scope @($Live.Value)[0].scope -Rr $Rr -Mcr $Mcr)"
Write-OerLiveStep "The read-back is the eligible-only form of Message Center Reader: $(Test-S144Form -Scope @($Live.Value)[0].scope -Form Eligible -RoleId $Mcr)"
```

**Expect:** `Returned: True`, ScopeType `#microsoft.graph.accessReviewQueryScope`, 1 write; the
read-back is the eligible-only form of Message Center Reader.
**Failure looks like:** an error record, or the All form read back.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. New-OERAccessReviewDefinition -DirectoryRoleAssignmentType Eligible returned the definition (ScopeType accessReviewQueryScope) with 1 read (the role name) and 1 write (one POST); Graph reads back the eligible-only form of Message Center Reader.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] Returned: True; ScopeType #microsoft.graph.accessReviewQueryScope; 1 read(s), 1 write(s)
[oer-s144] the new review is listed: converged after 1 read(s), 0.3 s.
[oer-s144] Read back: {"query":"/beta/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal&$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq 'ROLE-MCR')","queryRoot":null,"@odata.type":"#microsoft.graph.accessReviewQueryScope","queryType":"MicrosoftGraph"}
[oer-s144] The read-back is the eligible-only form of Message Center Reader: True
```

### 2.2. The parameter creates an active-only review

- [x] **2.2** `-DirectoryRole 'Reports Reader' -DirectoryRoleAssignmentType Active` creates `oer-s144-cact` with one POST, and Graph reads back the active-only form of Reports Reader. #type/subtask

```powershell
Connect-S144
$Rr = Get-S144RoleId -Name 'Reports Reader'; $Mcr = Get-S144RoleId -Name 'Message Center Reader'
$New = New-OERAccessReviewDefinition -DisplayName 'oer-s144-cact' -DescriptionForAdmins 'Sprint 14 step 4 live check (oer-s144-)' `
    -DescriptionForReviewers 'Sprint 14 step 4 live check (oer-s144-)' -DirectoryRole 'Reports Reader' -DirectoryRoleAssignmentType Active `
    -SelfReview -Recurrence OneTime -StartDate ([datetime]$Start) -DurationInDays 3 -ErrorAction Stop
Save-S144Created
Write-OerLiveStep "Returned: $([bool]$New); ScopeType $($New.ScopeType); $(Get-S144Count)"
$Live = Wait-OerLiveConverged -Activity 'the new review is listed' -Read { Read-S144Review -Name 'oer-s144-cact' } -Test { param($V) @($V).Count -eq 1 }
Write-OerLiveStep "Read back: $(Get-S144ScopeText -Scope @($Live.Value)[0].scope -Rr $Rr -Mcr $Mcr)"
Write-OerLiveStep "The read-back is the active-only form of Reports Reader: $(Test-S144Form -Scope @($Live.Value)[0].scope -Form Active -RoleId $Rr)"
```

**Expect:** as 2.1, with the active-only form of Reports Reader.
**Failure looks like:** as 2.1.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. -DirectoryRoleAssignmentType Active: 1 read, 1 write; Graph reads back the active-only form of Reports Reader.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] Returned: True; ScopeType #microsoft.graph.accessReviewQueryScope; 1 read(s), 1 write(s)
[oer-s144] the new review is listed: converged after 1 read(s), 0.1 s.
[oer-s144] Read back: {"query":"/beta/roleManagement/directory/roleAssignmentScheduleInstances?$expand=principal&$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq 'ROLE-RR')","@odata.type":"#microsoft.graph.accessReviewQueryScope","queryRoot":null,"queryType":"MicrosoftGraph"}
[oer-s144] The read-back is the active-only form of Reports Reader: True
```

## 3. The export (D)

### 3.1. The export writes the key for the eligible-only and active-only reviews

- [x] **3.1** `Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s144-*'` writes every prefixed review with `directoryRole`; the eligible-only and active-only ones carry `directoryRoleAssignmentType` `Eligible` or `Active`, and `oer-s144-all` carries no such key. #type/subtask

```powershell
Connect-S144
Set-S144NoWrite $true
$Warn = $null
$Doc = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s144-*' -ErrorAction Stop -WarningVariable Warn -WarningAction SilentlyContinue
foreach ($E in @($Doc.accessReviews | Sort-Object displayName)) {
    $Keys = @($E.PSObject.Properties.Name)
    $Form = if ($Keys -contains 'directoryRoleAssignmentType') { $E.directoryRoleAssignmentType } else { '(no key)' }
    Write-OerLiveStep "entry: $($E.displayName) | directoryRole '$($E.directoryRole)' | directoryRoleAssignmentType $Form"
}
Write-OerLiveStep "Skip warning names a review of a directory role: $(@($Warn | Where-Object { [string]$_ -match 'review\(s\) of a directory role' }).Count)"
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'export-3.1.json') -Encoding utf8NoBOM
Write-OerLiveStep "Requests: $(Get-S144Count)"
```

**Expect:** nine entries: `oer-s144-all` with `directoryRole 'Reports Reader'` and no key; `oer-s144-elig`,
`oer-s144-del` and `oer-s144-m-elig` (Reports Reader) and `oer-s144-cel` (Message Center Reader) with
`Eligible`; `oer-s144-act`, `oer-s144-dact` (Message Center Reader), `oer-s144-cact` and
`oer-s144-m-active` (Reports Reader) with `Active`; no skip warning for a role review (`0`); 0 writes.
**Failure looks like:** a review left out, a key on `oer-s144-all`, or a wrong value.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. Nine entries, all with directoryRole by name: oer-s144-all without the key; the four eligible-only reviews with Eligible and the four active-only reviews with Active; no skip warning for a role review; 12 reads, 0 writes.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] entry: oer-s144-act | directoryRole 'Message Center Reader' | directoryRoleAssignmentType Active
[oer-s144] entry: oer-s144-all | directoryRole 'Reports Reader' | directoryRoleAssignmentType (no key)
[oer-s144] entry: oer-s144-cact | directoryRole 'Reports Reader' | directoryRoleAssignmentType Active
[oer-s144] entry: oer-s144-cel | directoryRole 'Message Center Reader' | directoryRoleAssignmentType Eligible
[oer-s144] entry: oer-s144-dact | directoryRole 'Message Center Reader' | directoryRoleAssignmentType Active
[oer-s144] entry: oer-s144-del | directoryRole 'Reports Reader' | directoryRoleAssignmentType Eligible
[oer-s144] entry: oer-s144-elig | directoryRole 'Reports Reader' | directoryRoleAssignmentType Eligible
[oer-s144] entry: oer-s144-m-active | directoryRole 'Reports Reader' | directoryRoleAssignmentType Active
[oer-s144] entry: oer-s144-m-elig | directoryRole 'Reports Reader' | directoryRoleAssignmentType Eligible
[oer-s144] Skip warning names a review of a directory role: 0
[oer-s144] Requests: 12 read(s), 0 write(s)
```

### 3.2. The export applied twice: only Unchanged (G8)

- [x] **3.2** `Invoke-OERStructure` of the export of 3.1, run twice, reports every row `Unchanged` both times and writes nothing. #type/subtask

```powershell
Connect-S144
Set-S144NoWrite $true
$Json = Get-Content -LiteralPath (Join-Path $Raw 'export-3.1.json') -Raw
foreach ($Run in 1, 2) {
    Reset-S144Count
    $Rows = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Continue)
    Show-S144Row $Rows
    Write-OerLiveStep "Run ${Run}: every row Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0) ($($Rows.Count) row(s)); $(Get-S144Count)"
}
```

**Expect:** nine rows, all `Unchanged`, in both runs; 0 writes.
**Failure looks like:** an `Updated` or `Failed` row, or a fence refusal.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The export of 3.1 applied twice: nine rows Unchanged in each run, 18 reads and 0 writes each (G8 on the export path).

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-cact | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-cel | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-dact | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-del | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-all | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-act | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-elig | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-m-active | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-m-elig | Unchanged | record: none
[oer-s144] Run 1: every row Unchanged: True (9 row(s)); 18 read(s), 0 write(s)
[oer-s144] row: accessReviews | oer-s144-cact | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-cel | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-dact | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-del | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-all | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-act | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-elig | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-m-active | Unchanged | record: none
[oer-s144] row: accessReviews | oer-s144-m-elig | Unchanged | record: none
[oer-s144] Run 2: every row Unchanged: True (9 row(s)); 18 read(s), 0 write(s)
```

## 4. A review in another form under the same name is refused (C)

### 4.1. A live eligible-only review declared as active-only

- [x] **4.1** An entry `oer-s144-elig` declaring `directoryRole: Reports Reader`, `directoryRoleAssignmentType: Active` (the live review reviews only the eligible assignments) is refused with `AccessReviewScopeMismatch` in the plan and the run, and the live review reads the same before and after. #type/subtask

```powershell
Connect-S144
$Before = @(Read-S144Review -Name 'oer-s144-elig')[0]
$Doc = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-elig' -Target ([ordered]@{ directoryRole = 'Reports Reader'; directoryRoleAssignmentType = 'Active' }) -Description 'changed by a refused entry')
Set-S144NoWrite $true
$Err = $null
$Plan = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction SilentlyContinue)
Show-S144Row $Plan
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
Show-S144Row $Rows
Write-OerLiveStep "The run's message: $(@($Rows | Where-Object { $_.Error })[0].Error.Exception.Message)"
$After = @(Read-S144Review -Name 'oer-s144-elig')[0]
$Same = (ConvertTo-Json -InputObject $Before -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject $After -Depth 20 -Compress)
Write-OerLiveStep "The live review reads the same before and after: $Same; $(Get-S144Count)"
```

**Expect:** both rows `Failed` with `AccessReviewScopeMismatch`; the message says the live review does not
review only the active assignments; `True`; 0 writes.
**Failure looks like:** `Updated`, a fence refusal, or `False`.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A live eligible-only review declared as active-only: Failed with AccessReviewScopeMismatch in the plan and the run; the message says the live review does not review only the active assignments; the live review reads the same before and after; 0 writes.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-elig | Failed | record: AccessReviewScopeMismatch
[oer-s144] row: accessReviews | oer-s144-elig | Failed | record: AccessReviewScopeMismatch
[oer-s144] The run's message: Access review 'oer-s144-elig' in the tenant does not review only the active assignments to a directory role in the form this module writes (its scope is '/beta/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal&$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq 'ID-FRAGMENT')'), so it is not the review this entry declares for directory role 'Reports Reader'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s144] The live review reads the same before and after: True; 2 read(s), 0 write(s)
```

### 4.2. A live active-only review declared as eligible-only

- [x] **4.2** An entry `oer-s144-act` declaring `directoryRole: Message Center Reader`, `directoryRoleAssignmentType: Eligible` is refused with `AccessReviewScopeMismatch`, nothing written. #type/subtask

```powershell
Connect-S144
Set-S144NoWrite $true
$Doc = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-act' -Target ([ordered]@{ directoryRole = 'Message Center Reader'; directoryRoleAssignmentType = 'Eligible' }))
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction SilentlyContinue)
Show-S144Row $Rows
Write-OerLiveStep "Requests: $(Get-S144Count)"
```

**Expect:** one row `Failed` with `AccessReviewScopeMismatch`; 0 writes.
**Failure looks like:** `Updated` or `Unchanged`.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A live active-only review declared as eligible-only: Failed with AccessReviewScopeMismatch after 1 read (the listing); 0 writes.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-act | Failed | record: AccessReviewScopeMismatch
[oer-s144] Requests: 1 read(s), 0 write(s)
```

### 4.3. A live review of the form written before this branch declared as eligible-only

- [x] **4.3** An entry `oer-s144-all` declaring `directoryRole: Reports Reader`, `directoryRoleAssignmentType: Eligible` (the live review is of the form written before this branch) is refused with `AccessReviewScopeMismatch`, nothing written. #type/subtask

```powershell
Connect-S144
Set-S144NoWrite $true
$Doc = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-all' -Target ([ordered]@{ directoryRole = 'Reports Reader'; directoryRoleAssignmentType = 'Eligible' }))
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction SilentlyContinue)
Show-S144Row $Rows
Write-OerLiveStep "Requests: $(Get-S144Count)"
```

**Expect:** one row `Failed` with `AccessReviewScopeMismatch`; 0 writes.
**Failure looks like:** `Updated` or `Unchanged`.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A live review of the form written before this branch declared as eligible-only: Failed with AccessReviewScopeMismatch after 1 read; 0 writes.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-all | Failed | record: AccessReviewScopeMismatch
[oer-s144] Requests: 1 read(s), 0 write(s)
```

## 5. A document without the key gives the same result as on main (E)

### 5.1. The base build and this branch apply the same documents with the same rows and messages

- [x] **5.1** With the base commit's source (`OER_BASE_SOURCE`, development mode) and then with this branch's build, a document declaring `oer-s144-all` with `directoryRole: Reports Reader` and no key is `Unchanged` with 0 writes, a document declaring `oer-s144-elig` the same way is `Failed` with `AccessReviewScopeMismatch` and the same message from both, and the export of `oer-s144-all` is the same entry from both. #type/subtask

```powershell
$Docs = [ordered]@{
    all  = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-all' -Target @{ directoryRole = 'Reports Reader' })
    elig = New-S144Doc -Entry (New-S144Entry -Name 'oer-s144-elig' -Target @{ directoryRole = 'Reports Reader' })
}
$Results = [ordered]@{}
foreach ($Build in 'base', 'branch') {
    if ($Build -eq 'base') {
        $env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
        Import-Module (Join-Path $env:OER_BASE_SOURCE 'Omnicit.EntraRBAC.psd1') -Force -Global
        Connect-OerLive -Arm
        $script:S144Module = Get-Module -Name Omnicit.EntraRBAC
        Write-OerLiveStep "The base source is loaded: $($script:S144Module.ModuleBase.StartsWith($env:OER_BASE_SOURCE, [System.StringComparison]::OrdinalIgnoreCase)); it lacks the parameter: $(-not (Get-Command New-OERAccessReviewDefinition).Parameters.ContainsKey('DirectoryRoleAssignmentType'))"
        Install-S144Fence
    } else {
        # The base phase's token fence would refuse this sign-in: remove it first (unqualified, from this scope).
        Remove-Item -Path function:Get-AzToken -ErrorAction SilentlyContinue
        Remove-Module Omnicit.EntraRBAC -Force
        Connect-S144
    }
    Set-S144NoWrite $true
    foreach ($K in $Docs.Keys) {
        Reset-S144Count
        $Rows = @(Invoke-OERStructure -Json $Docs[$K] -Confirm:$false -ErrorAction SilentlyContinue)
        Show-S144Row $Rows
        $Results["$Build-$K"] = '{0}|{1}|{2}' -f (@($Rows | ForEach-Object Action) -join ','), (@($Rows | Where-Object { $_.Error } | ForEach-Object { ([string]$_.Error.FullyQualifiedErrorId -split ',')[0] }) -join ','), (@($Rows | Where-Object { $_.Error } | ForEach-Object { $_.Error.Exception.Message }) -join ' / ')
        Write-OerLiveStep "${Build} ${K}: $(@($Rows | ForEach-Object Action) -join ','); $(Get-S144Count)"
    }
    $Exp = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s144-all' -ErrorAction Stop -WarningAction SilentlyContinue
    $Results["$Build-export"] = ConvertTo-Json -InputObject @($Exp.accessReviews | Where-Object { $_.displayName -ceq 'oer-s144-all' })[0] -Depth 10 -Compress
}
foreach ($K in 'all', 'elig', 'export') { Write-OerLiveStep "${K}: the same from both builds: $($Results["base-$K"] -ceq $Results["branch-$K"])" }
```

**Expect:** `all` Unchanged and `elig` Failed (AccessReviewScopeMismatch) in both builds, 0 writes; the
three closing lines `True`.
**Failure looks like:** `False` on a closing line (this branch changed what a document without the key does).

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The base source (dc955c1, development mode) and this branch give the same rows and messages for a document without the key: oer-s144-all Unchanged and oer-s144-elig Failed (AccessReviewScopeMismatch) in both, 0 writes; the export of oer-s144-all is the same entry from both. The first run stopped at the branch sign-in on a block bug (the base phase's token fence was still in place; nothing was written); the block now removes it first, and the second run passed.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The base source is loaded: True; it lacks the parameter: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-all | Unchanged | record: none
[oer-s144] base all: Unchanged; 2 read(s), 0 write(s)
[oer-s144] row: accessReviews | oer-s144-elig | Failed | record: AccessReviewScopeMismatch
[oer-s144] base elig: Failed; 1 read(s), 0 write(s)
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s144] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s144] The module is the worktree's build: True
[oer-s144] Token fence in place: True
[oer-s144] Request fence in place: True
[oer-s144] row: accessReviews | oer-s144-all | Unchanged | record: none
[oer-s144] branch all: Unchanged; 2 read(s), 0 write(s)
[oer-s144] row: accessReviews | oer-s144-elig | Failed | record: AccessReviewScopeMismatch
[oer-s144] branch elig: Failed; 1 read(s), 0 write(s)
[oer-s144] all: the same from both builds: True
[oer-s144] elig: the same from both builds: True
[oer-s144] export: the same from both builds: True
```

## Teardown

### T.1. The prerequisite objects and the checks' reviews are removed

- [x] **T.1** `Initialize-OerS144Prereq.ps1 -Teardown -Unattended` removes every prefixed review definition, and the sweep is 0. #type/subtask

```powershell
pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS144Prereq.ps1') -Teardown -Unattended
```

**Expect:** the access review definitions are deleted; `Teardown complete: the sweep is 0.`
**Failure looks like:** `Teardown NOT complete` -- run it again later and write the residue here.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. The teardown added the 4 review ids the checks recorded and deleted the nine prefixed access review definitions (204 each): removed 9, residue 0, unreadable 0, already gone 0, skipped 0; the sweep is 0.

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Transcript (redacted): raw\s144\prereq-teardown-20261110-070206Z.log; OerLive 1.1.0.
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s144] Residue: raw\residue.json holds 5 row(s); 0 carry the prefix 'oer-s144-', the other 5 are left untouched.
[oer-s144] Teardown: 4 review id(s) recorded by the checks are added.
[oer-s144] Teardown: Remove-OerLiveTestObjects for the prefix with the recorded ids (access review definitions first).
[oer-s144] Teardown of 'oer-s144-': users 0, groups 0, access packages 0, access review definitions 9, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s144] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s144] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s144] Teardown 3/6: access review definitions, access package resource roles, access packages, catalog resources, catalogs.
[oer-s144] Deleted: access review definition oer-s144-cact (204).
[oer-s144] Deleted: access review definition oer-s144-cel (204).
[oer-s144] Deleted: access review definition oer-s144-dact (204).
[oer-s144] Deleted: access review definition oer-s144-del (204).
[oer-s144] Deleted: access review definition oer-s144-all (204).
[oer-s144] Deleted: access review definition oer-s144-act (204).
[oer-s144] Deleted: access review definition oer-s144-elig (204).
[oer-s144] Deleted: access review definition oer-s144-m-active (204).
[oer-s144] Deleted: access review definition oer-s144-m-elig (204).
[oer-s144] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s144] Teardown 5/6: the prefixed groups.
[oer-s144] Teardown 6/6: the prefixed users.
[oer-s144] Teardown of 'oer-s144-': removed 9, residue 0, unreadable 0, already gone 0, skipped 0.
[oer-s144] Teardown summary: Removed 9, Residue 0, Unreadable 0, Unread 0, AlreadyGone 0, Skipped 0
[oer-s144] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s144-' is left.
[oer-s144] Sweep: 0 object(s) with the prefix, 0 unread kind(s).
[oer-s144] Teardown complete: the sweep is 0.
```

### T.2. A read-back a minute later is clean

- [x] **T.2** A sweep a minute after T.1 lists nothing with the prefix, and the step's raw folder is deleted. #type/subtask

```powershell
Connect-OerLive -Graph
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "Sweep: $($Left.Count) object(s) or unread kind(s) with the prefix."
if ($Left.Count -eq 0) { Remove-Item -LiteralPath $Raw -Recurse -Force -ErrorAction SilentlyContinue; Write-OerLiveStep "raw\s144 deleted: $(-not (Test-Path -LiteralPath $Raw))" }
```

**Expect:** `Sweep: 0`, `raw\s144 deleted: True`.
**Failure looks like:** a listed object -- write it here as residue.

Result: 2026-11-10 07:03 UTC, written by Write-OerLiveResult (OerLive 1.1.0).

```text
Verdict: PASS. A sweep about a minute after T.1 lists nothing with the prefix; raw\s144 is deleted (the redacted measurement is kept outside the repo and the vault for the report).

oer-testmiljo.psd1 loaded: True; oer-cc-identitet.psd1 loaded: True; worktree exists: True; base source exists: True
[oer-s144] Omnicit.EntraRBAC 1.5.1 loaded from REPO\.claude\worktrees\s14-steg4\output\module\Omnicit.EntraRBAC\1.5.1.
[oer-s144] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s144] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s144] Sweep: no user, group, administrative unit, catalog, access package, access review definition or app registration starting with 'oer-s144-' is left.
[oer-s144] Sweep: 0 object(s) or unread kind(s) with the prefix.
[oer-s144] raw\s144 deleted: True
```
