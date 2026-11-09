# Live verification checklist -- GUID-named packages and absent PIM rules (fix/guid-named-packages-and-absent-rules)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Only objects of the prefix `oer-s142-`. The prerequisite
script creates the catalog `oer-s142-cat`, the access package `oer-s142-ap` with its direct-assignment
policy `oer-s142-pol` and the review `oer-s142-rv` (the control), an access package and a policy
created as `oer-s142-ap-guid` and `oer-s142-pol-guid` and then renamed to a GUID generated in the run,
the review `oer-s142-rv-guid` of those two, and the security group `oer-s142-pim` with no member.
Each renamed object is recorded by id, keeps the prefix in its description, is written to only through
that id, and gets its prefixed name back before the teardown removes it. The generated names stay in
the local `raw` folder and appear here only as placeholders. Every review is a self-review, one-time,
starts seven days ahead and sends no mail. Check 2.1 writes one PIM rule of `oer-s142-pim`, which
onboards it to PIM for Groups. Every check runs with a request fence in the module's scope that
refuses every write except the one rule of check 2.1.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A review names a GUID-shaped package or policy by id** (`fix: write a GUID-named access package
  or policy of a review as its id`): the engine reads such a name as an object id.
- **B. A package with a GUID-shaped name is left out of `accessPackages`** and named unread (`fix:
  leave out an access package named like an object id and name it unread`), as a catalog with such a
  name is. Unit tests show no handler removes a package absent from the document.
- **C. A PIM rule the read did not return is unknown** (`fix: treat a PIM rule the read did not return
  as unknown, not as off or empty`).

## What this file does not check, and why

- **A rule that is really absent from the policy read** (class B unless check 2.1 finds one): the
  check records which rules Microsoft Graph returns for an onboarded group. The refusal is held by the
  unit tests, with this recorded answer beside them.
- **A catalog with a GUID-shaped name** was checked in an earlier sprint and is not changed here.

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
- The prerequisite script `Initialize-OerS142Prereq.ps1` beside OerLive: run it once with `-WhatIf`,
  then with `-Unattended`; every `Read back` line must be `True`.

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block).

### H.1. The helpers every check uses

- [ ] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s142-' -ConfigDirectory $VaultDir
$Raw = Join-Path (& (Get-Module OerLive) { $script:OerLive.RawRoot }) 's142'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$EmBase = 'v1.0/identityGovernance/entitlementManagement'
$ArBase = 'v1.0/identityGovernance/accessReviews/definitions'
$Ids0 = Get-Content -LiteralPath (Join-Path $Raw 'known-ids.json') -Raw | ConvertFrom-Json -AsHashtable
$DocFile = Join-Path $Raw 'export.json'
function Connect-S142 {
    Connect-OerLive -Arm
    $script:S142Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S142Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S142 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S142Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S142Module {
        $script:S142Log = [System.Collections.Generic.List[string]]::new()
        $script:S142Allow = $null
        $script:S142RealGraph = ${function:Invoke-OERGraphRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
            $script:S142Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
            if (-not $Read -and -not ($script:S142Allow -and $Uri -match $script:S142Allow)) { throw "S142 fence: a $Method request was refused." }
            & $script:S142RealGraph @PSBoundParameters
        }
    }
    Write-OerLiveStep "Request fence in place: $((& $script:S142Module { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S142 fence' }))"
}
function Set-S142Allow { param([string]$Pattern) & $script:S142Module { param($V) $script:S142Allow = $V } $Pattern }
function Get-S142Count { & $script:S142Module { '{0} read(s), {1} write(s)' -f @($script:S142Log | Where-Object { $_ -eq 'read' }).Count, @($script:S142Log | Where-Object { $_ -ne 'read' }).Count } }
function Show-S142Row { param($Rows) foreach ($R in @($Rows)) { Write-OerLiveStep ('row: {0} | {1} | {2} | record: {3}' -f $R.Section, $R.Item, $R.Action, $(if ($R.Error) { ([string]$R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })) } }
function Get-S142OnlyUnchanged { param($Rows) (@($Rows).Count -gt 0) -and (@($Rows | Where-Object { [string]$_.Action -ne 'Unchanged' }).Count -eq 0) }
function Get-S142Export {
    $Err = @(); $Warn = @()
    $Doc = Get-OERInventory -Include Catalogs, AccessPackages, AccessReviews -Catalog 'oer-s142-cat' -AccessReviewFilter 'oer-s142-*' -ErrorAction SilentlyContinue -ErrorVariable +Err -WarningVariable +Warn -WarningAction SilentlyContinue
    [PSCustomObject]@{ Doc = $Doc; Errors = $Err; Warnings = $Warn }
}
function Test-S142RenamedStill {
    # The two renamed objects by recorded id: their name, description and policy are what the prerequisite left.
    $Ap = Invoke-OerLiveGraph -Uri "$EmBase/accessPackages/$($Ids0['gap'].Id)"
    $Pol = Invoke-OerLiveGraph -Uri "$EmBase/assignmentPolicies/$($Ids0['gpol'].Id)"
    $Pols = Invoke-OerLiveGraph -Uri "$EmBase/assignmentPolicies?`$filter=accessPackage/id eq '$($Ids0['gap'].Id)'"
    Write-OerLiveStep "The package still carries its GUID name: $([string]$Ap.Body.displayName -ceq [string]$Ids0['gap'].GuidName)"
    Write-OerLiveStep "The package keeps the prefix in its description: $(([string]$Ap.Body.description).Contains('oer-s142-'))"
    Write-OerLiveStep "The policy still carries its GUID name: $([string]$Pol.Body.displayName -ceq [string]$Ids0['gpol'].GuidName)"
    Write-OerLiveStep "The package still has exactly one policy: $(@($Pols.Body.value).Count -eq 1)"
    Write-OerLiveStep "The review of the two still exists: $((Invoke-OerLiveGraph -Uri "$ArBase/$($Ids0['rvg'].Id)").Ok)"
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
        , @('A', 'if (Test-OERGuid -Value $Name) { return $Id }')
        , @('B', 'function Add-GuidNamedEntryLeftOut')
        , @('C', 'AuthenticationContext_EndUser_Assignment) is unknown: the read returned no such rule'))) {
    Write-OerLiveStep "The build carries $($Marker[0]): $($Psm1.Contains($Marker[1]))"
}
Write-OerLiveStep ('Recorded: cat {0}, ap {1}, pol {2}, rv {3}, gap {4} (GUID name {5}), gpol {6} (GUID name {7}), rvg {8}, pim {9}' -f [bool]$Ids0['cat'].Id, [bool]$Ids0['ap'].Id, [bool]$Ids0['pol'].Id, [bool]$Ids0['rv'].Id, [bool]$Ids0['gap'].Id, [bool]$Ids0['gap'].GuidName, [bool]$Ids0['gpol'].Id, [bool]$Ids0['gpol'].GuidName, [bool]$Ids0['rvg'].Id, [bool]$Ids0['pim'].Id)
```

**Expect:** every line `True`; the HEAD is this branch's tip; 0 tracked changes.
**Failure looks like:** `False` on a marker (rebuild the worktree), or the main clone named.

Result:

## 1. An access review and an access package with a GUID-shaped name (A, B)

### 1.1. The export names the review's targets by id and leaves the package out, named unread

- [ ] **1.1** `Get-OERInventory` writes the review of the renamed package and policy with their ids, the control with its names, no `accessPackages` entry for the renamed package and no GUID-shaped name anywhere; the package is named unread and the cause is the shared text. #type/subtask

```powershell
Connect-S142
$E = Get-S142Export
$Rv = @($E.Doc.accessReviews | Where-Object { [string]$_.displayName -ceq 'oer-s142-rv-guid' })
$Ctl = @($E.Doc.accessReviews | Where-Object { [string]$_.displayName -ceq 'oer-s142-rv' })
Write-OerLiveStep "Reviews written: rv-guid $($Rv.Count -eq 1), rv $($Ctl.Count -eq 1)"
Write-OerLiveStep "The review's accessPackage is the recorded package id: $([string]$Rv[0].accessPackage -ieq [string]$Ids0['gap'].Id)"
Write-OerLiveStep "The review's assignmentPolicy is the recorded policy id: $([string]$Rv[0].assignmentPolicy -ieq [string]$Ids0['gpol'].Id)"
Write-OerLiveStep "The control names its package and policy: $([string]$Ctl[0].accessPackage -ceq 'oer-s142-ap' -and [string]$Ctl[0].assignmentPolicy -ceq 'oer-s142-pol')"
$Names = @($E.Doc.accessPackages | ForEach-Object { [string]$_.displayName })
Write-OerLiveStep "Access package entries: $($Names.Count); the control is one: $($Names -ccontains 'oer-s142-ap'); the renamed one is written: $($Names -ccontains [string]$Ids0['gap'].GuidName)"
$Json = $E.Doc | ConvertTo-Json -Depth 30
Write-OerLiveStep "The GUID names appear in the document: package $($Json.Contains([string]$Ids0['gap'].GuidName)), policy $($Json.Contains([string]$Ids0['gpol'].GuidName))"
$Partial = @($E.Errors | Where-Object { ([string]$_.FullyQualifiedErrorId).StartsWith('InventoryPartial') })
$Text = ($Partial | ForEach-Object { [string]$_.Exception.Message }) -join ' '
Write-OerLiveStep "InventoryPartial reported: $($Partial.Count -gt 0)"
Write-OerLiveStep "The package is named unread: $($Text.Contains("accessPackages/$($Ids0['gap'].GuidName)"))"
Write-OerLiveStep "The cause is the shared text: $($Text.Contains('was left out: its display name has the form of an object id, which Invoke-OERStructure reads as an object id and not as a name, so the access package cannot be declared by its name'))"
Write-OerLiveStep "Export: $(Get-S142Count)"
Set-Content -LiteralPath $DocFile -Value $Json -Encoding utf8NoBOM
```

**Expect:** both reviews written; the review carries the two recorded ids and the control its names;
one package entry (the control), the renamed one not written; neither GUID name appears in the
document; `InventoryPartial` names the package with the shared cause; 0 writes.
**Failure looks like:** a GUID name in the document, or the review naming a GUID.

Result:

### 1.2. The same document applies back with only Unchanged, twice (G8)

- [ ] **1.2** The export of 1.1 applied through `Invoke-OERStructure` gives only `Unchanged` rows, twice, with no write, and the renamed objects are untouched. #type/subtask

```powershell
Connect-S142
$Json = Get-Content -LiteralPath $DocFile -Raw
$Run1 = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Continue -WarningAction SilentlyContinue)
Show-S142Row $Run1
Write-OerLiveStep "Run 1 only Unchanged: $(Get-S142OnlyUnchanged $Run1); rows $($Run1.Count); $(Get-S142Count)"
$Run2 = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Continue -WarningAction SilentlyContinue)
Write-OerLiveStep "Run 2 only Unchanged: $(Get-S142OnlyUnchanged $Run2); rows $($Run2.Count); $(Get-S142Count)"
Test-S142RenamedStill
```

**Expect:** both runs only `Unchanged`, 0 writes; every renamed-object line `True`.
**Failure looks like:** any `Updated`, `Created` or `Failed` row, or a fence refusal.

Result:

### 1.3. -Prune does not touch the package left out

- [ ] **1.3** The same document with `-Prune` gives only `Unchanged` rows and no write; the package left out and its policy and review are untouched. #type/subtask

```powershell
Connect-S142
$Json = Get-Content -LiteralPath $DocFile -Raw
$Run = @(Invoke-OERStructure -Json $Json -Prune -Confirm:$false -ErrorAction Continue -WarningAction SilentlyContinue)
Show-S142Row $Run
Write-OerLiveStep "With -Prune only Unchanged: $(Get-S142OnlyUnchanged $Run); rows $($Run.Count); $(Get-S142Count)"
Test-S142RenamedStill
```

**Expect:** only `Unchanged`, 0 writes; every renamed-object line `True`.
**Failure looks like:** a row for the renamed package, any write, or the package changed.

Result:

## 2. The PIM rule read (C)

### 2.1. Which rules Microsoft Graph returns for an onboarded group

- [ ] **2.1** The first policy write onboards `oer-s142-pim`; for member and owner, each of the rules the module reads is reported present or missing, and the module's lists and authentication context are read back. #type/subtask

```powershell
Connect-S142
$Gid = [string]$Ids0['pim'].Id
Set-S142Allow '^beta/policies/roleManagementPolicies/[^/]+/rules/Expiration_EndUser_Assignment$'
$Listed = Wait-OerLiveConverged -Activity 'the group has a listed policy' -Read { @(Get-OERGroupPimPolicy -Group $Gid -AccessType member -ErrorAction SilentlyContinue) } -Test { param($V) @($V).Count -eq 1 }
Write-OerLiveStep "The group's policy is listed before the write: $(@($Listed.Value).Count -eq 1)"
$null = Set-OERGroupPimPolicy -Group $Gid -ActivationMaxHours 4 -Confirm:$false -ErrorAction Continue -WarningAction SilentlyContinue
Set-S142Allow $null
Write-OerLiveStep "After the onboarding write: $(Get-S142Count)"
Start-Sleep -Seconds 30
$RuleIds = 'Expiration_EndUser_Assignment', 'Enablement_EndUser_Assignment', 'AuthenticationContext_EndUser_Assignment', 'Approval_EndUser_Assignment', 'Expiration_Admin_Eligibility', 'Expiration_Admin_Assignment', 'Enablement_Admin_Assignment', 'Notification_Admin_Admin_Eligibility', 'Notification_Admin_Admin_Assignment', 'Notification_Admin_EndUser_Assignment'
foreach ($Access in 'member', 'owner') {
    $P = @(Get-OERGroupPimPolicy -Group $Gid -AccessType $Access -ErrorAction Continue)[0]
    $InAnswer = @($P.Rules | ForEach-Object { [string]$_.id })
    Write-OerLiveStep "$Access rules in the answer: $($InAnswer.Count)"
    foreach ($R in $RuleIds) { Write-OerLiveStep "$Access rule ${R}: present $($InAnswer -ccontains $R)" }
    Write-OerLiveStep "$Access ActivationEnabledRules is null: $($null -eq $P.ActivationEnabledRules); count $(@($P.ActivationEnabledRules | Where-Object { $null -ne $_ }).Count)"
    Write-OerLiveStep "$Access ActiveEnabledRules is null: $($null -eq $P.ActiveEnabledRules); count $(@($P.ActiveEnabledRules | Where-Object { $null -ne $_ }).Count)"
    Write-OerLiveStep "$Access AuthenticationContextId is null: $($null -eq $P.AuthenticationContextId)"
    $Ctx = @($P.Rules | Where-Object { [string]$_.id -ceq 'AuthenticationContext_EndUser_Assignment' })
    Write-OerLiveStep "$Access authentication context rule isEnabled: $(if ($Ctx.Count) { [bool]$Ctx[0].isEnabled } else { 'no such rule' })"
}
Write-OerLiveStep "After the reads: $(Get-S142Count)"
```

**Expect:** one write (the rule PATCH) and every rule named above present for both access types, or the
missing ones listed; the two lists are not null where the rule is present; the authentication context
is null with the rule present and off. A rule reported absent is the live form of BL-174c.
**Failure looks like:** a refused or failed write, or no policy listed.

Result:

### 2.2. A declared empty form over a rule the read returns stays Unchanged (G8)

- [ ] **2.2** A document declaring `authenticationContextId: ""` and the two lists as the live values gives `Unchanged` twice with no write, so the rule read is not mistaken for an absent one. #type/subtask

```powershell
Connect-S142
$Gid = [string]$Ids0['pim'].Id
$P = @(Get-OERGroupPimPolicy -Group $Gid -AccessType member -ErrorAction Stop)[0]
$Doc = [ordered]@{ version = '1.0'; groups = @([ordered]@{ displayName = 'oer-s142-pim'; pimPolicy = [ordered]@{ member = [ordered]@{ authenticationContextId = ''; activationEnablement = @($P.ActivationEnabledRules); activeEnablement = @($P.ActiveEnabledRules) } } }) } | ConvertTo-Json -Depth 10
$Run1 = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue -WarningAction SilentlyContinue)
Show-S142Row $Run1
Write-OerLiveStep "Run 1 only Unchanged: $(Get-S142OnlyUnchanged $Run1); $(Get-S142Count)"
$Run2 = @(Invoke-OERStructure -Json $Doc -Confirm:$false -ErrorAction Continue -WarningAction SilentlyContinue)
Write-OerLiveStep "Run 2 only Unchanged: $(Get-S142OnlyUnchanged $Run2); $(Get-S142Count)"
Write-OerLiveStep "No PimRuleValueUnknown in either run: $(@($Run1 + $Run2 | Where-Object { ([string]$_.Detail).Contains('PimRuleValueUnknown') }).Count -eq 0)"
```

**Expect:** both runs only `Unchanged`, 0 writes, no `PimRuleValueUnknown`.
**Failure looks like:** a refusal (the diff read a returned rule as absent), or `Updated`.

Result:

## Teardown

### T.1. The renamed objects get their names back and the prefix is swept

- [ ] **T.1** `Initialize-OerS142Prereq.ps1 -Teardown -Unattended` renames both objects back, removes everything of the prefix, and the sweep is 0; the local `raw` folder of the step is deleted after the read-back. #type/subtask

```powershell
pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS142Prereq.ps1') -Teardown -Unattended 2>&1 | Where-Object { $_ -match 'Renamed back|Teardown|Sweep|Left:' }
```

**Expect:** two `Renamed back` lines, `Teardown complete: the sweep is 0.`, no `Left:` line.
**Failure looks like:** a rename stop, `Teardown NOT complete`, or a `Left:` line.

Result:
