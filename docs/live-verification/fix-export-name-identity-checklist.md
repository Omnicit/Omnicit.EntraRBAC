# Live verification checklist -- exported names the apply engine can identify (fix/export-name-identity)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Only objects of the prefix `oer-s132-`: the prerequisite
script's security groups `oer-s132-grp-a` (no member) and `oer-s132-guid`, and the access review
definitions these checks create (`oer-s132-rev-...` and the two `oer-s132-twin` reviews). The group
`oer-s132-guid` is the one object whose DISPLAY NAME does not carry the prefix: the prerequisite
script gives it a display name in the form of an object id, drawn at random when it is created and
recorded beside its id, while its mail nickname and description carry the prefix; the script
identifies it by its recorded id and checks its mail nickname before every write, and its teardown
renames it back to `oer-s132-guid` before anything is removed, so the prefix sweep and the removal
see it. Every review starts a week after the run, so no instance opens and no reviewer is asked
anything. Every check that expects no write runs with a fence that refuses any write request, and
every other check with a fence that refuses a write of an object without the prefix.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A group whose display name has the form of an object id is written by its id** (BL-171c).
  The apply engine reads such a name as an object id wherever it resolves a group, so the export
  writes the group's object id at every place it references a group by name -- a role assignment
  or directory role assignment principal, a reviewed group, a reviewer and a fallback reviewer, a
  catalog resource and an access package binding, a group's PIM eligibility principal -- and leaves
  such a group's own `groups` entry out of the document, named in the partial signal. The same rule
  covers a service principal named as a role assignment principal or an eligibility principal, and
  an application catalog resource, which the engine reads the same way.
- **B. Access review names are counted over every review the export read** (BL-171d). A review
  whose namesake is in a form the export skips (a guest-only review, for one) is left out with the
  counted shared-name cause instead of being written by a name the apply engine refuses as
  ambiguous.

## What this file does not check, and why

- **A, the other reference positions** (class B): a role assignment or directory role assignment
  principal (a group or a service principal), a catalog resource (a group or an application), an
  access package binding and a PIM eligibility principal take the same rule through the same owner
  (`Get-OERGroupReference`); their unit tests hold each position. This file checks the reviewer, the
  reviewed group and the group's own entry, which `oer-live-cc` can create and remove with no role
  assignment, no Azure scope and no application.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.
- The prerequisite script `Initialize-OerS132Prereq.ps1` beside OerLive: run it once with `-WhatIf`,
  then with `-Unattended`; every `Read back` line must be `True`.

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block).

### H.1. The helpers every check uses

- [ ] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s132-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s132'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$ArBase = 'v1.0/identityGovernance/accessReviews/definitions'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture
$StartDay = [datetime]::UtcNow.Date.AddDays(7)
$Start = $StartDay.ToString('yyyy-MM-dd', $Inv)
$IdFile = Join-Path $Raw 'known-ids.json'
$BaseDir = Join-Path $Raw 'base-a0ef3e5'
function Connect-S132 {
    # -Base: the module of main before this branch (a0ef3e5), imported from its archived source in dev
    # mode BEFORE Connect-OerLive, which then keeps it (S.2 writes the archive).
    param([switch]$Base)
    if ($Base) {
        $env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
        Import-Module (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1') -Global -Force
    }
    Connect-OerLive -Arm
    $script:S132Module = Get-Module -Name Omnicit.EntraRBAC
    $Expected = if ($Base) { Join-Path $BaseDir 'source' } else { Join-Path $Cfg.Repo 'output\module' }
    Write-OerLiveStep "The module is the $(if ($Base) { 'base (a0ef3e5)' } else { "worktree's build" }): $($script:S132Module.ModuleBase.StartsWith($Expected, [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S132 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S132Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S132Module {
        $script:S132Log = [System.Collections.Generic.List[string]]::new()
        $script:S132NoWrite = $false
        $script:S132Real = ${function:Invoke-OERGraphRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
            $script:S132Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
            if (-not $Read -and $script:S132NoWrite) { throw "S132 fence: a $Method request was refused; this check expects no write." }
            if (-not $Read -and $Body -and $Body.ContainsKey('displayName') -and -not ([string]$Body.displayName).StartsWith('oer-s132-')) { throw "S132 fence: a $Method of an object without the prefix was refused." }
            if (-not $Read -and $Uri -match '^v1\.0/groups/') { throw "S132 fence: a $Method of a group was refused; no check writes a group." }
            & $script:S132Real @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fence in place: $((& $script:S132Module { Get-Command Invoke-OERGraphRequest }).ScriptBlock.ToString() -match 'S132 fence')"
}
function Set-S132NoWrite { param([bool]$On) & $script:S132Module { param($V) $script:S132NoWrite = $V } $On }
function Get-S132Count { & $script:S132Module { '{0} read(s), {1} write(s)' -f @($script:S132Log | Where-Object { $_ -eq 'read' }).Count, @($script:S132Log | Where-Object { $_ -ne 'read' }).Count } }
function Show-S132Row { param($Rows) foreach ($R in @($Rows)) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3} | record: {4}" -f $R.Section, $R.Item, $R.Action, $R.Detail, $(if ($R.Error) { ([string]$R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })) } }
function Get-S132Ids { if (Test-Path -LiteralPath $IdFile) { Get-Content -LiteralPath $IdFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} } }
function Add-S132Review {
    # Records a review this file created, so the teardown finds it even while the listing lags.
    param([string]$Key, [string]$Id)
    if (-not $Id) { return }
    $Ids = Get-S132Ids
    $Ids["review-$Key"] = @{ Kind = 'access review definition'; Id = $Id }
    $Ids | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $IdFile -Encoding utf8NoBOM
}
function Find-S132Review {
    # Every live review with this exact name, read raw (OData filter, then an exact client-side match), each read by id.
    param([string]$Name)
    $R = Invoke-OerLiveGraph -Uri "$ArBase`?`$filter=displayName eq '$Name'"
    $null = Assert-OerLiveOk -Response $R -Activity "find $Name"
    foreach ($Hit in @($R.Body.value | Where-Object { [string]$_.displayName -ceq $Name })) {
        (Invoke-OerLiveRetry -Activity "read $Name" -ScriptBlock { Invoke-OerLiveGraph -Uri "$ArBase/$($Hit.id)" }).Body
    }
}
function Get-S132Export {
    # The entries of an inventory.json under a folder, and its raw text.
    param([string]$Folder)
    $File = (Get-ChildItem -LiteralPath $Folder -Recurse -Filter 'inventory.json' | Select-Object -First 1).FullName
    [pscustomobject]@{ Text = (Get-Content -LiteralPath $File -Raw); Doc = (Get-Content -LiteralPath $File -Raw | ConvertFrom-Json) }
}
$Ids0 = Get-S132Ids
$GrpA = [string]$Ids0['grp-a'].Id; $GuidId = [string]$Ids0['guid'].Id; $GuidName = [string]$Ids0['guid'].GuidName
```

**Expect:** nothing printed.
**Failure looks like:** a parse error -- fix the block before any check runs.

Result:

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the prerequisite objects exist. #type/subtask

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
foreach ($Marker in @(
        , @('A (the owner)', 'KeepSharedName')
        , @('A (the groups entry)', 'has the form of an object id, which Invoke-OERStructure reads as an object id')
        , @('B', 'AccessReviewExternalIds'))) {
    Write-OerLiveStep "The worktree's build carries $($Marker[0]): $([bool](Select-String -LiteralPath $Psm1 -SimpleMatch $Marker[1] -Quiet))"
}
foreach ($K in 'grp-a', 'guid') { Write-OerLiveStep "Prerequisite $K recorded: $([bool]$Ids0[$K].Id)" }
Write-OerLiveStep "The group guid's recorded display name has the form of an object id: $($GuidName -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z')"
Write-OerLiveStep "The group guid's display name is not its id: $($GuidName -ne $GuidId)"
```

**Expect:** a worktree that is not the main clone, on this branch with 0 tracked changes; the three
markers `True`; both prerequisites `True`; both last values `True`.
**Failure looks like:** a marker `False` -- build the worktree (`./build.ps1 -Tasks build`), never
while the gate runs; a prerequisite `False` -- run the prerequisite script.

Result:

### S.2. The source of main before this branch is archived for the before checks

- [ ] **S.2** The source of `a0ef3e5` is unpacked under the step's raw folder, and its module carries none of the three markers. #type/subtask

```powershell
$null = New-Item -ItemType Directory -Force -Path $Raw
$Zip = Join-Path $Raw 'base-a0ef3e5.zip'
if (-not (Test-Path -LiteralPath (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1'))) {
    git -C $Cfg.Repo archive --format=zip -o $Zip a0ef3e5 source
    Expand-Archive -LiteralPath $Zip -DestinationPath $BaseDir -Force
}
Write-OerLiveStep "The base source is unpacked: $(Test-Path -LiteralPath (Join-Path $BaseDir 'source\Omnicit.EntraRBAC.psd1'))"
$BaseText = (Get-ChildItem -LiteralPath (Join-Path $BaseDir 'source') -Recurse -Filter '*.ps1' | Get-Content -Raw) -join "`n"
foreach ($M in 'KeepSharedName', 'has the form of an object id, which Invoke-OERStructure reads as an object id', 'AccessReviewExternalIds') {
    Write-OerLiveStep "The base source carries '$M': $($BaseText.Contains($M))"
}
```

**Expect:** unpacked `True`; each of the three `False`.
**Failure looks like:** `git archive` fails -- the worktree's git must know `a0ef3e5` (`git fetch`).

Result:

## 1. A group whose display name has the form of an object id (A)

### 1.1. Two reviews that reference the group guid are created from a document

- [ ] **1.1** `Invoke-OERStructure` creates `oer-s132-rev-reviewer` (members of grp-a, reviewer the group guid by its id) and `oer-s132-rev-of-guid` (members of the group guid by its id, a self review); read back raw, the first's reviewer and the second's scope name the group guid's id. #type/subtask

```powershell
Connect-S132
$Doc = [ordered]@{ version = '1.0'; accessReviews = @(
        [ordered]@{ displayName = 'oer-s132-rev-reviewer'; group = 'oer-s132-grp-a'; descriptionForAdmins = 'Sprint 13 step 2 live check'
            reviewers = @($GuidId); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }
        [ordered]@{ displayName = 'oer-s132-rev-of-guid'; group = $GuidId; descriptionForAdmins = 'Sprint 13 step 2 live check'
            reviewers = @('self'); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err -WarningVariable Warn 3>$null
$Ok = $?
Show-S132Row $Rows
Write-OerLiveStep "Run: rows $(@($Rows).Count); `$? $Ok; error records: $(@($Err).Count); warnings: $(@($Warn).Count); requests: $(Get-S132Count)"
Start-Sleep -Seconds 5
$Rev = @(Find-S132Review -Name 'oer-s132-rev-reviewer'); $Of = @(Find-S132Review -Name 'oer-s132-rev-of-guid')
Add-S132Review -Key 'rev-reviewer' -Id ([string]$Rev[0].id); Add-S132Review -Key 'rev-of-guid' -Id ([string]$Of[0].id)
Write-OerLiveStep "One live review of each name: $($Rev.Count -eq 1 -and $Of.Count -eq 1)"
Write-OerLiveStep "oer-s132-rev-reviewer's reviewer is the group guid by its id: $(@($Rev[0].reviewers | Where-Object { [string]$_.query -match ('^(/v1\.0)?/groups/' + [regex]::Escape($GuidId) + '/') }).Count -eq 1)"
Write-OerLiveStep "oer-s132-rev-of-guid reviews the members of the group guid: $([string]$Of[0].scope.query -match ('^(/v1\.0)?/groups/' + [regex]::Escape($GuidId) + '/transitiveMembers'))"
Disconnect-OerLive
```

**Expect:** two `Created` rows, `$? True`, 0 error records, 2 writes; the three last values `True`.
**Failure looks like:** `Failed` with `GroupNotFound` (Graph does not list a group yet -- run again a
minute later and record both runs).

Result:

### 1.2. A second run of the same document reports only Unchanged (G8)

- [ ] **1.2** The document of 1.1 applied again reports `Unchanged` for both reviews, with no write. #type/subtask

```powershell
Connect-S132
$Doc = [ordered]@{ version = '1.0'; accessReviews = @(
        [ordered]@{ displayName = 'oer-s132-rev-reviewer'; group = 'oer-s132-grp-a'; descriptionForAdmins = 'Sprint 13 step 2 live check'
            reviewers = @($GuidId); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }
        [ordered]@{ displayName = 'oer-s132-rev-of-guid'; group = $GuidId; descriptionForAdmins = 'Sprint 13 step 2 live check'
            reviewers = @('self'); recurrence = 'Monthly'; startDate = $Start; durationInDays = 14 }) } | ConvertTo-Json -Depth 8
Set-S132NoWrite $true
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
$Ok = $?
Show-S132Row $Rows
Write-OerLiveStep "Second run: rows $(@($Rows).Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); `$? $Ok; error records: $(@($Err).Count); requests: $(Get-S132Count)"
Disconnect-OerLive
```

**Expect:** two `Unchanged` rows, 0 not Unchanged, `$? True`, 0 error records, 0 writes.
**Failure looks like:** an `Updated` row -- the reviewer or the group is compared on another key than
the id.

Result:

### 1.3. Before this branch: the export writes the group guid by its display name, and applying it would change both reviews

- [ ] **1.3** With the module of `a0ef3e5`, `Get-OERInventory -Include AccessReviews` writes the group guid's GUID display name (not its id) as the reviewer of `oer-s132-rev-reviewer` and as the group of `oer-s132-rev-of-guid`; the plan of those two entries is not `Unchanged`. #type/subtask

```powershell
Connect-S132 -Base
$Inv0 = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s132-rev-*' -ErrorAction SilentlyContinue 3>$null
$Mine = @($Inv0.accessReviews | Where-Object { [string]$_.displayName -in 'oer-s132-rev-reviewer', 'oer-s132-rev-of-guid' })
foreach ($E in $Mine) { Write-OerLiveStep ("base export: {0} | group {1} | reviewers {2}" -f $E.displayName, $E.group, (@($E.reviewers) -join ',')) }
Write-OerLiveStep "The base export names the group guid by its display name: $(@($Mine | Where-Object { [string]$_.group -ceq $GuidName -or @($_.reviewers) -contains $GuidName }).Count -eq 2)"
Write-OerLiveStep "The base export names the group guid by its id: $(@($Mine | Where-Object { [string]$_.group -eq $GuidId -or @($_.reviewers) -contains $GuidId }).Count)"
$Doc = [ordered]@{ version = '1.0'; accessReviews = $Mine } | ConvertTo-Json -Depth 10
Set-S132NoWrite $true
$null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable Rows -ErrorVariable Err 3>$null
Show-S132Row $Rows
Write-OerLiveStep "Base plan of the base export: rows $(@($Rows).Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); requests: $(Get-S132Count)"
Disconnect-OerLive
```

**Expect:** both base export lines show the GUID display name (a placeholder other than the group
guid's id) where the group guid stands; `by its display name: True`; `by its id: 0`; the plan has two
rows that are not `Unchanged` (each a would-update or a refusal) and 0 writes.
**Failure looks like:** the base export already writes the id -- the defect is not what the step
assumed; stop and record it.

Result:

### 1.4. This branch: the export writes the group guid by its id, and the export applies Unchanged (G8)

- [ ] **1.4** `Export-OERInventory -Include AccessReviews` writes the group guid's id as the reviewer of `oer-s132-rev-reviewer` and the group of `oer-s132-rev-of-guid`, the GUID display name appears nowhere in `inventory.json`, and the two exported entries apply with only `Unchanged` rows and no write. #type/subtask

```powershell
Connect-S132
$Out = Join-Path $Raw 'export-1-4'
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
$null = Export-OERInventory -OutputPath $Out -Include AccessReviews -Confirm:$false -WarningVariable ExWarn -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep "Export: requests $(Get-S132Count); warnings $(@($ExWarn).Count)"
$Ex = Get-S132Export -Folder $Out
$Mine = @($Ex.Doc.accessReviews | Where-Object { [string]$_.displayName -in 'oer-s132-rev-reviewer', 'oer-s132-rev-of-guid' })
foreach ($E in $Mine) { Write-OerLiveStep ("export: {0} | group {1} | reviewers {2}" -f $E.displayName, $E.group, (@($E.reviewers) -join ',')) }
Write-OerLiveStep "Both entries name the group guid by its id: $(@($Mine | Where-Object { [string]$_.group -eq $GuidId -or @($_.reviewers) -contains $GuidId }).Count -eq 2)"
Write-OerLiveStep "The GUID display name appears in inventory.json: $($Ex.Text.Contains($GuidName))"
$Doc = [ordered]@{ version = '1.0'; accessReviews = $Mine } | ConvertTo-Json -Depth 10
$Check = Test-OERStructure -Json $Doc
Write-OerLiveStep "Validator: Errors $(@($Check.Errors | Where-Object { $_.Severity -eq 'Error' }).Count)"
Set-S132NoWrite $true
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
$Ok = $?
Show-S132Row $Rows
Write-OerLiveStep "Apply of the export: rows $(@($Rows).Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); `$? $Ok; error records: $(@($Err).Count); requests in total: $(Get-S132Count)"
Disconnect-OerLive
```

**Expect:** both export lines show the group guid's id (the same placeholder as in 1.1's document,
never the GUID display name's); `by its id: True`; `appears in inventory.json: False`; the
validator 0 Errors; two `Unchanged` rows, `$? True`, 0 error records, 0 writes.
**Failure looks like:** a line with the GUID display name -- the position does not go through the
owner; any row other than `Unchanged`.

Result:

### 1.5. This branch: the group guid's own groups entry is left out and named unread

- [ ] **1.5** `Get-OERInventory -Include Groups` over the prefixed groups (by mail nickname) writes `oer-s132-grp-a` and no entry for the group guid; its partial error names `groups/` followed by the GUID display name, with the cause that the name has the form of an object id. #type/subtask

```powershell
Connect-S132
$Inv1 = Get-OERInventory -Include Groups -GroupFilter "startswith(mailNickname,'oer-s132-')" -ErrorAction SilentlyContinue -ErrorVariable InvErr 3>$null
Write-OerLiveStep "groups written: $(@($Inv1.groups).Count); oer-s132-grp-a written: $(@($Inv1.groups | Where-Object { [string]$_.displayName -ceq 'oer-s132-grp-a' }).Count -eq 1)"
Write-OerLiveStep "An entry for the group guid written: $(@($Inv1.groups | Where-Object { [string]$_.displayName -eq $GuidName }).Count)"
$Partial = @($InvErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InventoryPartial*' })
Write-OerLiveStep "InventoryPartial records: $($Partial.Count)"
$Msg = if ($Partial.Count -gt 0) { [string]$Partial[0].Exception.Message } else { '' }
Write-OerLiveStep "The partial error names groups/ and the GUID display name: $($Msg.Contains("groups/$GuidName"))"
Write-OerLiveStep "The partial error gives the cause: $($Msg.Contains('has the form of an object id'))"
Write-OerLiveStep "Requests: $(Get-S132Count)"
Disconnect-OerLive
```

**Expect:** `oer-s132-grp-a written: True`; 0 entries for the group guid; 1 InventoryPartial record;
both partial lines `True`; 0 writes.
**Failure looks like:** an entry whose displayName is the GUID -- the reader does not leave it out.

Result:

## 2. Two reviews of one name, one in a form the export skips (B)

### 2.1. Two reviews named oer-s132-twin are made raw: all members of grp-a, and its guest users only

- [ ] **2.1** Two group reviews named `oer-s132-twin` are created raw (Graph v1.0 POST): one of all members of grp-a, one of grp-a's guest users only; read back, both exist under the one name, with the two scope queries. #type/subtask

```powershell
Connect-S132
$Rec = @{ pattern = [ordered]@{ type = 'absoluteMonthly'; interval = 1; dayOfMonth = $StartDay.Day }; range = [ordered]@{ type = 'noEnd'; startDate = $Start } }
$Settings = @{ mailNotificationsEnabled = $false; reminderNotificationsEnabled = $false; justificationRequiredOnApproval = $false; recommendationsEnabled = $false
    defaultDecisionEnabled = $false; defaultDecision = 'None'; instanceDurationInDays = 14; autoApplyDecisionsEnabled = $false; recurrence = $Rec }
$Specs = [ordered]@{
    'twin-members' = "/groups/$GrpA/transitiveMembers"
    'twin-guests'  = "/groups/$GrpA/transitiveMembers/microsoft.graph.user/?`$count=true&`$filter=(userType eq 'Guest')"
}
$Have = @(Find-S132Review -Name 'oer-s132-twin')
foreach ($Key in $Specs.Keys) {
    $Query = $Specs[$Key]
    $IsGuest = $Key -eq 'twin-guests'
    if (@($Have | Where-Object { ([string]$_.scope.query -match 'Guest') -eq $IsGuest }).Count -gt 0) { Write-OerLiveStep "$Key already there"; continue }
    $Body = @{ displayName = 'oer-s132-twin'; descriptionForAdmins = 'Sprint 13 step 2 live check'; descriptionForReviewers = 'Sprint 13 step 2 live check'
        scope = @{ '@odata.type' = '#microsoft.graph.accessReviewQueryScope'; query = $Query; queryType = 'MicrosoftGraph' }
        reviewers = @(); fallbackReviewers = @(); settings = $Settings }
    $R = Invoke-OerLiveGraph -Method POST -Uri $ArBase -Body $Body
    Write-OerLiveStep "create $Key`: $($R.Status) $($R.Code) $($R.Message)"
    if ($R.Ok) { Add-S132Review -Key $Key -Id ([string]$R.Body.id) }
}
Start-Sleep -Seconds 5
$Have = @(Find-S132Review -Name 'oer-s132-twin')
foreach ($D in $Have) { Write-OerLiveStep ("oer-s132-twin: scope {0}; reviewers {1}" -f $D.scope.query, @($D.reviewers).Count) }
Write-OerLiveStep "Two live reviews named oer-s132-twin: $($Have.Count -eq 2)"
Write-OerLiveStep "One of them is the guest-only form: $(@($Have | Where-Object { [string]$_.scope.query -match 'Guest' }).Count -eq 1)"
Disconnect-OerLive
```

**Expect:** both created (201) or already there; two reviews of the one name; one scope ends in the
guest filter, the other is the transitive members of grp-a; both last values `True`.
**Failure looks like:** a 400 for the guest form -- record Graph's answer and run section 2 with
another form the export skips (direct members only), saying so.

Result:

### 2.2. Before this branch: the export writes oer-s132-twin, and applying it is refused as ambiguous

- [ ] **2.2** With the module of `a0ef3e5`, `Get-OERInventory -Include AccessReviews` writes one `oer-s132-twin` entry (the members review; the guest review is skipped), and the plan of that entry is refused (`Failed`), with nothing written. #type/subtask

```powershell
Connect-S132 -Base
$Inv0 = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s132-twin' -ErrorAction SilentlyContinue -WarningVariable W0 3>$null
$Twin = @($Inv0.accessReviews | Where-Object { [string]$_.displayName -ceq 'oer-s132-twin' })
Write-OerLiveStep "Base export: oer-s132-twin entries written: $($Twin.Count); skip warning written: $(@($W0 | Where-Object { [string]$_ -like '*skipped*access review definition(s)*' }).Count -eq 1)"
$Doc = [ordered]@{ version = '1.0'; accessReviews = $Twin } | ConvertTo-Json -Depth 10
Set-S132NoWrite $true
$null = Invoke-OERStructure -Json $Doc -WhatIf -OutVariable Rows -ErrorVariable Err 3>$null
Show-S132Row $Rows
$Own = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and [string]$_.FullyQualifiedErrorId -like '*,Invoke-OERStructure' })
Write-OerLiveStep "Base plan: rows $(@($Rows).Count); Failed: $(@($Rows | Where-Object { $_.Action -eq 'Failed' }).Count); own error ids: $((@($Own | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) | Select-Object -Unique) -join ', '); requests: $(Get-S132Count)"
Disconnect-OerLive
```

**Expect:** 1 entry written; the skip warning `True`; one `Failed` row for `oer-s132-twin` whose
record names an ambiguous name; 0 writes.
**Failure looks like:** 0 entries -- the base build already counts the skipped twin; stop and record it.

Result:

### 2.3. This branch: the export writes neither oer-s132-twin, counts the name, and the export applies Unchanged

- [ ] **2.3** `Export-OERInventory -Include AccessReviews` writes no `oer-s132-twin` entry; the skip warning counts the guest review; the shared-name warning, the bundle's incomplete reads and README name `oer-s132-twin` with 2 objects; the exported `oer-s132-` entries apply with only `Unchanged` rows, no write and no refusal. #type/subtask

```powershell
Connect-S132
$Out = Join-Path $Raw 'export-2-3'
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
$Bundle = Export-OERInventory -OutputPath $Out -Include AccessReviews -Confirm:$false -WarningVariable ExWarn -ErrorAction SilentlyContinue 3>$null
Write-OerLiveStep "Export: requests $(Get-S132Count); warnings $(@($ExWarn).Count)"
$Ex = Get-S132Export -Folder $Out
Write-OerLiveStep "oer-s132-twin entries written: $(@($Ex.Doc.accessReviews | Where-Object { [string]$_.displayName -ceq 'oer-s132-twin' }).Count)"
Write-OerLiveStep "The skip warning counts a group review in a form the module cannot write back: $(@($ExWarn | Where-Object { [string]$_ -match '(\d+) review\(s\) of a group in a form the module cannot write back' -and [int]$Matches[1] -ge 1 }).Count -eq 1)"
Write-OerLiveStep "The shared-name warning is written: $(@($ExWarn | Where-Object { [string]$_ -like '*left out of inventory.json and the per-area files every object whose name another object of its kind shares*' }).Count -eq 1)"
Write-OerLiveStep "Incomplete reads name accessReviews/oer-s132-twin: $(@($Bundle.IncompleteReads) -contains 'accessReviews/oer-s132-twin')"
$Readme = Get-Content -LiteralPath (Get-ChildItem -LiteralPath $Out -Recurse -Filter 'README.md' | Select-Object -First 1).FullName -Raw
Write-OerLiveStep "README lists oer-s132-twin with 2 objects: $($Readme.Contains('`oer-s132-twin` -- 2 objects, section `accessReviews`'))"
$Mine = @($Ex.Doc.accessReviews | Where-Object { [string]$_.displayName -like 'oer-s132-*' })
Write-OerLiveStep "Exported oer-s132- entries: $(@($Mine | ForEach-Object { $_.displayName }) -join ', ')"
$Doc = [ordered]@{ version = '1.0'; accessReviews = $Mine } | ConvertTo-Json -Depth 10
Set-S132NoWrite $true
$null = Invoke-OERStructure -Json $Doc -Confirm:$false -OutVariable Rows -ErrorVariable Err 3>$null
$Ok = $?
Show-S132Row $Rows
Write-OerLiveStep "Apply of the export: rows $(@($Rows).Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); rows for oer-s132-twin: $(@($Rows | Where-Object { [string]$_.Item -ceq 'oer-s132-twin' }).Count); `$? $Ok; error records: $(@($Err).Count); requests in total: $(Get-S132Count)"
Disconnect-OerLive
```

**Expect:** 0 `oer-s132-twin` entries; the three warning/read lines and the README line `True`; the
exported `oer-s132-` entries are `oer-s132-rev-of-guid` and `oer-s132-rev-reviewer`; two `Unchanged`
rows, 0 rows for `oer-s132-twin`, `$? True`, 0 error records, 0 writes.
**Failure looks like:** an `oer-s132-twin` entry; a `Failed` row.

Result:

## Teardown

### T.1. Remove every object with the prefix

- [ ] **T.1** The prerequisite script's teardown renames the group guid back to `oer-s132-guid`, removes the access review definitions first, then both groups; the sweep is 0 and the group guid answers 404 by its id. #type/subtask

```powershell
pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS132Prereq.ps1') -Teardown -Unattended
```

**Expect:** the rename line and `three reads by id answer oer-s132-guid: True`; `Teardown summary:
Removed` the objects, `Residue 0`; `the group guid read by its id answers 404: True`; `Teardown
complete: the sweep is 0.`
**Failure looks like:** `Residue` above 0 or `Left:` lines -- run `-Teardown` again later and record
both runs.

Result:

### T.2. The sweep is still 0 a minute later, and raw output is removed

- [ ] **T.2** A minute after T.1 the prefix sweep is still 0, a group with the mail nickname `oer-s132-guid` is not listed, and the step's raw folder is deleted. #type/subtask

```powershell
Connect-OerLive -Graph
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "Sweep a minute later: $($Left.Count) object(s) or unread kind(s) with the prefix."
$Nick = Invoke-OerLiveGraph -Uri "v1.0/groups?`$filter=mailNickname eq 'oer-s132-guid'&`$select=id"
Write-OerLiveStep "Groups with the mail nickname oer-s132-guid: $(if ($Nick.Ok) { @($Nick.Body.value).Count } else { "unread ($($Nick.Status))" })"
Disconnect-OerLive
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "Raw folder removed: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** 0; 0; `Raw folder removed: True`.
**Failure looks like:** an object listed -- run T.1 again.

Result:
