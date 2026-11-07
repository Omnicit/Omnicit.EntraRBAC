# Live verification checklist -- access reviews of directory roles (feat/directory-role-access-reviews)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Only objects of the prefix `oer-s134-`, and access reviews
only of the two low-risk directory roles Reports Reader and Message Center Reader. The prerequisite
script creates the security group `oer-s134-grp` (no member), the catalog `oer-s134-cat`, the access
package `oer-s134-ap` with its direct-assignment policy `oer-s134-pol`, and four self-review access
reviews that start seven days ahead and send no mail: `oer-s134-pkg` (the package and policy),
`oer-s134-grpr` (the members of `oer-s134-grp`), `oer-s134-other` (every assignment of Message
Center Reader) and `oer-s134-elig` (the eligible assignments of Reports Reader). The checks create
`oer-s134-role` and `oer-s134-cmd` the same way and change the description of `oer-s134-role`, and
nothing else. Every check runs with a request fence in the module's scope that refuses a write whose
target is not a prefixed review, and the checks that expect no write run with a fence that refuses
every write.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A new document form, `directoryRole`.** An `accessReviews[]` entry may declare `directoryRole`
  (a role name or a role definition id) in place of `group` or `accessPackage` and `assignmentPolicy`:
  a review of the users assigned to that role. Microsoft Graph refuses
  the query form Microsoft Learn shows for a review of a role's active and eligible assignments (measured: 400), so the module writes the
  `principalResourceMembershipsScope` Graph accepts (users x the role definition); Graph reads it back
  with the version segments `/v1.0` and `/beta`.
- **B. `New-OERAccessReviewDefinition -DirectoryRole`** creates such a review.
- **C. The target check** refuses a live review found by the entry's name that reviews another role,
  only the eligible or only the active assignments, or anything that is not a role
  (`AccessReviewScopeMismatch`), before anything is written.
- **D. The export** writes `directoryRole` (the role's name when the module's own lookup finds only
  this role under it, else its id) and skips, and counts, a role review in a form the document cannot
  write back.
- **E. The package and group reviews are unchanged.**

## What this file does not check, and why

- **A role whose display name has the form of an object id, or a name two roles share** (class B):
  the test tenant holds neither and a custom role cannot carry the prefix in such a name; the unit
  tests hold both.
- **A failed role lookup** (class B): `oer-live-cc` reads role definitions; the unit tests hold the
  three ids (`RoleDefinitionNotFound`, `AmbiguousRoleName`, `RoleDefinitionReadFailed`). Check 2.2
  shows the not-found one live.
- **Who is actually asked to review** (no instance starts: every review starts seven days ahead and is
  deleted in the teardown). The scope the module writes is the one Microsoft Learn names "all users
  assigned to a directory role" (example 14 without its guest filter); what Graph enumerates from it
  is not measured.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it; it reads role definitions with the `RoleManagement.ReadWrite.Directory` it holds.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree; for
  check 5.1 also a build of the base commit, its path in `OER_BASE_MODULE` (the folder holding
  `Omnicit.EntraRBAC\<version>\Omnicit.EntraRBAC.psd1`).
- The prerequisite script `Initialize-OerS134Prereq.ps1` beside OerLive: run it once with `-WhatIf`,
  then with `-Unattended`; every `Read back` line must be `True`.

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block).

### H.1. The helpers every check uses

- [ ] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s134-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s134'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$ArBase = 'v1.0/identityGovernance/accessReviews/definitions'
$IdFile = Join-Path $Raw 'known-ids.json'
$Ids0 = if (Test-Path -LiteralPath $IdFile) { Get-Content -LiteralPath $IdFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
$CheckFile = Join-Path $Raw 'check-ids.json'
$Start = (Get-Date).ToUniversalTime().Date.AddDays(7).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
function New-S134Entry {
    # One accessReviews[] entry: a one-time self-review seven days ahead that sends no mail.
    param([string]$Name, [hashtable]$Target, [string]$Description = 'Sprint 13 step 4 live check (oer-s134-)')
    $E = [ordered]@{ displayName = $Name }
    foreach ($K in $Target.Keys) { $E[$K] = $Target[$K] }
    $E.descriptionForAdmins = $Description; $E.descriptionForReviewers = 'Sprint 13 step 4 live check (oer-s134-)'
    $E.reviewers = @('self'); $E.recurrence = 'OneTime'; $E.startDate = $Start; $E.durationInDays = 3
    $E.mailNotification = $false; $E.reminderNotification = $false; $E.requireJustification = $false
    $E.recommendationsEnabled = $false; $E.autoApplyDecisions = $false; $E.defaultDecision = 'None'
    $E
}
function New-S134Doc { param([object[]]$Entry) [ordered]@{ version = '1.0'; accessReviews = @($Entry) } | ConvertTo-Json -Depth 10 }
function Connect-S134 {
    Connect-OerLive -Arm
    $script:S134Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S134Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S134 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S134Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S134Module {
        $script:S134Log = [System.Collections.Generic.List[string]]::new()
        $script:S134Created = [System.Collections.Generic.List[string]]::new()
        $script:S134NoWrite = $false
        $script:S134RealGraph = ${function:Invoke-OERGraphRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
            $script:S134Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
            if (-not $Read) {
                if ($script:S134NoWrite) { throw "S134 fence: a $Method request was refused; this check expects no write." }
                $Ok = $Uri -match '^v1\.0/identityGovernance/accessReviews/definitions(/[0-9a-f-]{36})?$' -and
                    ($Method -ne 'POST' -or ([string]$Body.displayName).StartsWith('oer-s134-', [System.StringComparison]::Ordinal))
                if (-not $Ok) { throw "S134 fence: a $Method outside the prefixed access reviews was refused." }
            }
            $R = & $script:S134RealGraph @PSBoundParameters
            if ($Method -eq 'POST' -and $R.id) { $script:S134Created.Add([string]$R.id) }
            $R
        }
    }
    Write-OerLiveStep "Request fence in place: $((& $script:S134Module { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S134 fence' }))"
}
function Set-S134NoWrite { param([bool]$On) & $script:S134Module { param($V) $script:S134NoWrite = $V } $On }
function Get-S134Count { & $script:S134Module { '{0} read(s), {1} write(s)' -f @($script:S134Log | Where-Object { $_ -eq 'read' }).Count, @($script:S134Log | Where-Object { $_ -ne 'read' }).Count } }
function Save-S134Created {
    # The ids this check created, kept for the teardown's -KnownId and the later checks.
    $New = @(& $script:S134Module { $script:S134Created.ToArray() })
    $Old = if (Test-Path -LiteralPath $CheckFile) { @(Get-Content -LiteralPath $CheckFile -Raw | ConvertFrom-Json) } else { @() }
    @($Old + $New | Select-Object -Unique) | ConvertTo-Json | Set-Content -LiteralPath $CheckFile -Encoding utf8NoBOM
}
function Show-S134Row { param($Rows) foreach ($R in @($Rows)) { Write-OerLiveStep ("row: {0} | {1} | {2} | record: {3}" -f $R.Section, $R.Item, $R.Action, $(if ($R.Error) { ([string]$R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })) } }
function Get-S134RoleId {
    param([string]$Name)
    $R = Invoke-OerLiveGraph -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq '$Name'&`$select=id"
    [string]@($R.Body.value)[0].id
}
function Read-S134Review {
    # The review of that exact name, raw, as Graph lists it (one expected).
    param([string]$Name)
    $R = Invoke-OerLiveGraph -Uri "$ArBase`?`$filter=displayName eq '$Name'"
    @($R.Body.value | Where-Object { [string]$_.displayName -ceq $Name })
}
function Get-S134ScopeText {
    # The scope as compact JSON with the two role ids written as ROLE-RR and ROLE-MCR.
    param($Scope, [string]$Rr, [string]$Mcr)
    (ConvertTo-Json -InputObject $Scope -Depth 10 -Compress).Replace($Rr, 'ROLE-RR').Replace($Mcr, 'ROLE-MCR')
}
function Test-S134AllForm {
    # Graph's read-back of the All form for that role id (measured during the step).
    param($Scope, [string]$RoleId)
    $P = @($Scope.principalScopes); $Q = @($Scope.resourceScopes)
    [bool]([string]$Scope['@odata.type'] -eq '#microsoft.graph.principalResourceMembershipsScope' -and $P.Count -eq 1 -and $Q.Count -eq 1 -and
        [string]$P[0].query -eq '/v1.0/users' -and [string]$Q[0].query -eq "/beta/roleManagement/directory/roleDefinitions/$RoleId")
}
```

**Expect:** nothing printed.
**Failure looks like:** a parse error -- fix the block before any check runs.

Result:

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the prerequisite objects are recorded. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Get-Content -LiteralPath (Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1') -Raw
foreach ($Marker in @(
        , @('A (owner)', 'function Resolve-OERAccessReviewRoleScope')
        , @('A (builder)', 'DirectoryRoleId')
        , @('B', 'DirectoryRoleSingleStage')
        , @('D', 'review(s) of a directory role in a form the module cannot write back'))) {
    Write-OerLiveStep "The build carries $($Marker[0]): $($Psm1.Contains($Marker[1]))"
}
Write-OerLiveStep ("Recorded: group {0}, catalog {1}, package {2}, policy {3}, reviews pkg {4} grpr {5} other {6} elig {7}" -f
    [bool]$Ids0['grp'].Id, [bool]$Ids0['cat'].Id, [bool]$Ids0['ap'].Id, [bool]$Ids0['pol'].Id, [bool]$Ids0['pkgr'].Id, [bool]$Ids0['grpr'].Id, [bool]$Ids0['other'].Id, [bool]$Ids0['elig'].Id)
```

**Expect:** every line `True`; the HEAD is this branch's tip; 0 tracked changes.
**Failure looks like:** `False` on a marker (rebuild the worktree), or the main clone named.

Result:

## 1. A role review from a document (A, C)

### 1.1. The plan, then the run, create the review in the form Graph accepts

- [ ] **1.1** `Invoke-OERStructure -WhatIf` of a document declaring `directoryRole: Reports Reader` plans the review and writes nothing; the real run creates it, and Graph reads back the All form of Reports Reader. #type/subtask

```powershell
Connect-S134
$Rr = Get-S134RoleId -Name 'Reports Reader'; $Mcr = Get-S134RoleId -Name 'Message Center Reader'
$Doc = New-S134Doc -Entry (New-S134Entry -Name 'oer-s134-role' -Target @{ directoryRole = 'Reports Reader' })
Set-S134NoWrite $true
$Plan = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction Continue)
Show-S134Row $Plan
Write-OerLiveStep "Plan: $(Get-S134Count)"
Set-S134NoWrite $false
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S134Row $Rows
Save-S134Created
Write-OerLiveStep "Run and plan: $(Get-S134Count)"
$Live = Wait-OerLiveConverged -Activity 'the new review is listed' -Read { Read-S134Review -Name 'oer-s134-role' } -Test { param($V) @($V).Count -eq 1 }
$Rv = @($Live.Value)[0]
Write-OerLiveStep "Listed once: $(@($Live.Value).Count -eq 1); read back: $(Get-S134ScopeText -Scope $Rv.scope -Rr $Rr -Mcr $Mcr)"
Write-OerLiveStep "The read-back is the All form of Reports Reader: $(Test-S134AllForm -Scope $Rv.scope -RoleId $Rr)"
```

**Expect:** the plan row `Skipped` (it would create), 0 writes in the plan; the run row `Created`, 1
write (one POST); the read-back is the All form of Reports Reader.
**Failure looks like:** a `Failed` row, a fence refusal, or another scope read back.

Result:

### 1.2. The same document again: only Unchanged (G8)

- [ ] **1.2** The document of 1.1 applied again reports `Unchanged` and writes nothing. #type/subtask

```powershell
Connect-S134
$Doc = New-S134Doc -Entry (New-S134Entry -Name 'oer-s134-role' -Target @{ directoryRole = 'Reports Reader' })
Set-S134NoWrite $true
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S134Row $Rows
Write-OerLiveStep "Every row Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0) ($($Rows.Count) row(s)); $(Get-S134Count)"
```

**Expect:** one row `Unchanged`; 0 writes.
**Failure looks like:** `Updated` (the diff does not converge) or a fence refusal.

Result:

### 1.3. An update, then the same document again: only Unchanged (G8 on the update path)

- [ ] **1.3** A changed `descriptionForAdmins` is written with one PUT and the scope stays the All form; the same document again is `Unchanged` with no write. #type/subtask

```powershell
Connect-S134
$Rr = Get-S134RoleId -Name 'Reports Reader'
$Doc = New-S134Doc -Entry (New-S134Entry -Name 'oer-s134-role' -Target @{ directoryRole = 'Reports Reader' } -Description 'Sprint 13 step 4 live check (oer-s134-) updated')
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S134Row $Rows
Write-OerLiveStep "Update: $(Get-S134Count)"
$Settled = Wait-OerLiveConverged -Activity 'the description reads back' -Read { Read-S134Review -Name 'oer-s134-role' } -Test { param($V) [string]@($V)[0].descriptionForAdmins -like '* updated' }
Write-OerLiveStep "The description reads back: $([string]@($Settled.Value)[0].descriptionForAdmins -like '* updated'); the scope is still the All form: $(Test-S134AllForm -Scope @($Settled.Value)[0].scope -RoleId $Rr)"
Start-Sleep -Seconds 30
& $script:S134Module { $script:S134Log.Clear() }
Set-S134NoWrite $true
$Again = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue)
Show-S134Row $Again
Write-OerLiveStep "Again, every row Unchanged: $(@($Again | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0); $(Get-S134Count)"
```

**Expect:** the first row `Updated` with 1 write (one PUT); both read-back lines `True`; the second run
`Unchanged` with 0 writes.
**Failure looks like:** a second `Updated` (the update path does not converge) or another scope.

Result:

## 2. New-OERAccessReviewDefinition -DirectoryRole (B)

### 2.1. The cmdlet creates a review of a role by name

- [ ] **2.1** `New-OERAccessReviewDefinition -DirectoryRole 'Message Center Reader' -SelfReview` creates `oer-s134-cmd` with one POST, and Graph reads back the All form of Message Center Reader. #type/subtask

```powershell
Connect-S134
$Rr = Get-S134RoleId -Name 'Reports Reader'; $Mcr = Get-S134RoleId -Name 'Message Center Reader'
$New = New-OERAccessReviewDefinition -DisplayName 'oer-s134-cmd' -DescriptionForAdmins 'Sprint 13 step 4 live check (oer-s134-)' `
    -DescriptionForReviewers 'Sprint 13 step 4 live check (oer-s134-)' -DirectoryRole 'Message Center Reader' -SelfReview `
    -Recurrence OneTime -StartDate ([datetime]$Start) -DurationInDays 3 -ErrorAction Stop
Save-S134Created
Write-OerLiveStep "Returned: $([bool]$New); ScopeType $($New.ScopeType); $(Get-S134Count)"
$Live = Wait-OerLiveConverged -Activity 'the new review is listed' -Read { Read-S134Review -Name 'oer-s134-cmd' } -Test { param($V) @($V).Count -eq 1 }
Write-OerLiveStep "Read back: $(Get-S134ScopeText -Scope @($Live.Value)[0].scope -Rr $Rr -Mcr $Mcr)"
Write-OerLiveStep "The read-back is the All form of Message Center Reader: $(Test-S134AllForm -Scope @($Live.Value)[0].scope -RoleId $Mcr)"
```

**Expect:** `Returned: True`, ScopeType `#microsoft.graph.principalResourceMembershipsScope`, 1 write;
the read-back is the All form of Message Center Reader.
**Failure looks like:** an error record, or a scope of another role.

Result:

### 2.2. A role name that matches nothing is refused and nothing is sent

- [ ] **2.2** `-DirectoryRole 'oer-s134-no-such-role'` publishes `RoleDefinitionNotFound` and sends no write. #type/subtask

```powershell
Connect-S134
Set-S134NoWrite $true
$Err = $null
$Out = New-OERAccessReviewDefinition -DisplayName 'oer-s134-none' -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
    -DirectoryRole 'oer-s134-no-such-role' -SelfReview -Recurrence OneTime -StartDate ([datetime]$Start) `
    -ErrorAction SilentlyContinue -ErrorVariable Err
$Own = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',New-OERAccessReviewDefinition', [System.StringComparison]::Ordinal) })
Write-OerLiveStep "Own records: $($Own.Count); id: $(if ($Own) { ([string]$Own[0].FullyQualifiedErrorId -split ',')[0] } else { 'none' }); category: $(if ($Own) { $Own[0].CategoryInfo.Category } else { 'none' }); output: $([bool]$Out); $(Get-S134Count)"
```

**Expect:** 1 own record, `RoleDefinitionNotFound`, `ObjectNotFound`; no output; 0 writes.
**Failure looks like:** a write, or another id.

Result:

## 3. The export (D)

### 3.1. The export writes directoryRole and skips the eligible-only review

- [ ] **3.1** `Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s134-*'` writes the two role reviews and `oer-s134-other` with `directoryRole`, the package and group reviews as before, leaves `oer-s134-elig` out and counts it. #type/subtask

```powershell
Connect-S134
Set-S134NoWrite $true
$Warn = $null
$Doc = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s134-*' -ErrorAction Stop -WarningVariable Warn -WarningAction SilentlyContinue
foreach ($E in @($Doc.accessReviews | Sort-Object displayName)) {
    $Form = if ($E.directoryRole) { "directoryRole '$($E.directoryRole)'" } elseif ($E.group) { "group '$($E.group)'" } elseif ($E.accessPackage) { "accessPackage '$($E.accessPackage)', assignmentPolicy '$($E.assignmentPolicy)'" } else { 'no target' }
    Write-OerLiveStep "entry: $($E.displayName) | $Form | reviewers $(@($E.reviewers) -join ',')"
}
Write-OerLiveStep "oer-s134-elig left out: $(@($Doc.accessReviews | Where-Object { $_.displayName -ceq 'oer-s134-elig' }).Count -eq 0)"
Write-OerLiveStep "Skip warning names one review of a directory role: $(@($Warn | Where-Object { [string]$_ -match '1 review\(s\) of a directory role in a form the module cannot write back' }).Count -eq 1)"
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'export-3.1.json') -Encoding utf8NoBOM
Write-OerLiveStep "Requests: $(Get-S134Count)"
```

**Expect:** five entries: `oer-s134-cmd` and `oer-s134-other` with `directoryRole 'Message Center
Reader'`, `oer-s134-role` with `directoryRole 'Reports Reader'`, `oer-s134-grpr` with
`group 'oer-s134-grp'`, `oer-s134-pkg` with the package and policy names, each reviewer `self`; both
lines `True`; 0 writes.
**Failure looks like:** a role written by id although its name is unique, `oer-s134-elig` exported, or
another count.

Result:

### 3.2. The export applies with only Unchanged

- [ ] **3.2** `Invoke-OERStructure` of the export of 3.1 reports every row `Unchanged` and writes nothing. #type/subtask

```powershell
Connect-S134
Set-S134NoWrite $true
$Json = Get-Content -LiteralPath (Join-Path $Raw 'export-3.1.json') -Raw
$Rows = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Continue)
Show-S134Row $Rows
Write-OerLiveStep "Every row Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0) ($($Rows.Count) row(s)); $(Get-S134Count)"
```

**Expect:** five rows, all `Unchanged`; 0 writes.
**Failure looks like:** an `Updated` or `Failed` row, or a fence refusal.

Result:

## 4. The target check (C)

### 4.1. A review of the same name that reviews another role is refused

- [ ] **4.1** An entry `oer-s134-other` declaring `directoryRole: Reports Reader` (the live review reviews Message Center Reader) is refused with `AccessReviewScopeMismatch` in the plan and the run, and the live review is unchanged. #type/subtask

```powershell
Connect-S134
$Before = @(Read-S134Review -Name 'oer-s134-other')[0]
$Doc = New-S134Doc -Entry (New-S134Entry -Name 'oer-s134-other' -Target @{ directoryRole = 'Reports Reader' } -Description 'changed by a refused entry')
Set-S134NoWrite $true
$Plan = @(Invoke-OERStructure -Json $Doc -WhatIf -ErrorAction SilentlyContinue)
Show-S134Row $Plan
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction SilentlyContinue)
Show-S134Row $Rows
$After = @(Read-S134Review -Name 'oer-s134-other')[0]
$Same = (ConvertTo-Json -InputObject $Before -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject $After -Depth 20 -Compress)
Write-OerLiveStep "The live review reads the same before and after: $Same; $(Get-S134Count)"
```

**Expect:** both rows `Failed` with `AccessReviewScopeMismatch`; `True`; 0 writes.
**Failure looks like:** an `Updated` row, a fence refusal (the fence caught a write the check should
have stopped), or `False`.

Result:

### 4.2. A review of the right role in another form is refused

- [ ] **4.2** An entry `oer-s134-elig` declaring `directoryRole: Reports Reader` (the live review reviews only the eligible assignments of Reports Reader) is refused with `AccessReviewScopeMismatch`, nothing written. #type/subtask

```powershell
Connect-S134
Set-S134NoWrite $true
$Doc = New-S134Doc -Entry (New-S134Entry -Name 'oer-s134-elig' -Target @{ directoryRole = 'Reports Reader' })
$Rows = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction SilentlyContinue)
Show-S134Row $Rows
Write-OerLiveStep "Requests: $(Get-S134Count)"
```

**Expect:** one row `Failed` with `AccessReviewScopeMismatch`; 0 writes.
**Failure looks like:** `Updated` or `Unchanged` (the eligible-only review was read as the All form).

Result:

## 5. The package and group reviews are unchanged (E)

### 5.1. The base build exports the package and group reviews exactly as this branch does

- [ ] **5.1** With the base commit's build, `Get-OERInventory` of the same filter writes `oer-s134-pkg` and `oer-s134-grpr` byte-for-byte as the export of 3.1 does, and none of the role reviews. #type/subtask

```powershell
Import-Module (Join-Path $env:OER_BASE_MODULE 'Omnicit.EntraRBAC') -Force -Global
$Base = Get-Module -Name Omnicit.EntraRBAC
Connect-OerLive -Arm
function global:Get-AzToken { throw 'S134 fence: no token request is expected after the sign-in.' }
Write-OerLiveStep "The base build is loaded: $($Base.ModuleBase.StartsWith($env:OER_BASE_MODULE, [System.StringComparison]::OrdinalIgnoreCase)); it lacks the owner: $(-not (& $Base { Get-Command Resolve-OERAccessReviewRoleScope -ErrorAction SilentlyContinue }))"
$Old = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s134-*' -ErrorAction Stop -WarningAction SilentlyContinue
$New = Get-Content -LiteralPath (Join-Path $Raw 'export-3.1.json') -Raw | ConvertFrom-Json
foreach ($N in 'oer-s134-pkg', 'oer-s134-grpr') {
    $A = ConvertTo-Json -InputObject @($Old.accessReviews | Where-Object { $_.displayName -ceq $N })[0] -Depth 10 -Compress
    $B = ConvertTo-Json -InputObject @($New.accessReviews | Where-Object { $_.displayName -ceq $N })[0] -Depth 10 -Compress
    Write-OerLiveStep "${N}: the same entry from both builds: $($A -ceq $B)"
}
Write-OerLiveStep "The base build exports no role review: $(@($Old.accessReviews | Where-Object { $_.displayName -in 'oer-s134-role', 'oer-s134-cmd', 'oer-s134-other' }).Count -eq 0)"
```

**Expect:** every line `True`.
**Failure looks like:** `False` on an entry (this branch changed a package or group export).

Result:

### 5.2. A group entry and a package entry against a live role review are still refused

- [ ] **5.2** An entry `oer-s134-other` declaring `group: oer-s134-grp`, and one declaring the package and policy, are each refused with `AccessReviewScopeMismatch`, nothing written. #type/subtask

```powershell
Connect-S134
Set-S134NoWrite $true
$Doc = New-S134Doc -Entry (New-S134Entry -Name 'oer-s134-other' -Target @{ group = 'oer-s134-grp' })
Show-S134Row @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction SilentlyContinue)
$Doc = New-S134Doc -Entry (New-S134Entry -Name 'oer-s134-other' -Target ([ordered]@{ accessPackage = 'oer-s134-ap'; assignmentPolicy = 'oer-s134-pol' }))
Show-S134Row @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction SilentlyContinue)
Write-OerLiveStep "Requests: $(Get-S134Count)"
```

**Expect:** two rows `Failed` with `AccessReviewScopeMismatch`; 0 writes.
**Failure looks like:** any other row.

Result:

## Teardown

### T.1. The prerequisite objects and the checks' reviews are removed

- [ ] **T.1** `Initialize-OerS134Prereq.ps1 -Teardown -Unattended` removes every prefixed review definition first, then the policy, the package, the catalog and the group, and the sweep is 0. #type/subtask

```powershell
pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS134Prereq.ps1') -Teardown -Unattended
```

**Expect:** the access review definitions are deleted first; `Teardown complete: the sweep is 0.`
**Failure looks like:** `Teardown NOT complete` -- run it again later and write the residue here.

Result:

### T.2. A read-back a minute later is clean

- [ ] **T.2** A sweep a minute after T.1 lists nothing with the prefix, and the step's raw folder is deleted. #type/subtask

```powershell
Connect-OerLive -Graph
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "Sweep: $($Left.Count) object(s) or unread kind(s) with the prefix."
if ($Left.Count -eq 0) { Remove-Item -LiteralPath $Raw -Recurse -Force -ErrorAction SilentlyContinue; Write-OerLiveStep "raw\s134 deleted: $(-not (Test-Path -LiteralPath $Raw))" }
```

**Expect:** `Sweep: 0`, `raw\s134 deleted: True`.
**Failure looks like:** a listed object -- write it here as residue.

Result:
