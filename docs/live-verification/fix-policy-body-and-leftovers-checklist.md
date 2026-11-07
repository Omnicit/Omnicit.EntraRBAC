# Live verification checklist -- the policy body carries what it read, and the leftovers (fix/policy-body-and-leftovers)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Only objects of the prefix `oer-s133-`: the prerequisite
script's security group `oer-s133-pim` (no member), catalog `oer-s133-cat`, access package
`oer-s133-ap`, its direct-assignment policy `oer-s133-pol` and, when the test subscription allows it,
the resource group `oer-s133-rg`. The checks change the policy's description, the PIM for Groups
member policy of `oer-s133-pim` and the tags of `oer-s133-rg`, and nothing else. Every check runs
with a request fence in the module's scope that refuses a write whose target is not one of the
recorded prefixed objects, and the checks that expect no write run with a fence that refuses every
write.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The assignment policy body carries every value the read has** (BL-169a). A read-modify-write
  update (`Set-OERAccessPackageAssignmentPolicy`, and `Invoke-OERStructure` through the same builder)
  carried a value from the live policy only when it was truthy, so an empty string, `false` or an
  empty list fell to the builder default -- a live `questions: []` was dropped from the update. Every
  value the read has is now carried as it is, and the default is written only for a key the read does
  not have and the call does not name.
- **B. An assignment policy's fixed expiration date-time is exported in ISO 8601 UTC round-trip
  form** (BL-161c), so applying an export on a machine in another time zone keeps the instant.
- **C. A PIM for Groups permanence whose live value is unknown is never read as false** (BL-161d).
- **D. `Get-OERRoleDefinition -Role` reads its list with the transport's value check** (BL-172): an
  empty Azure answer is a failed read, never `RoleDefinitionNotFound`.
- **E. `Set-OERResourceGroup` refuses a read without a location** (BL-161a) with
  `ResourceGroupValueUnknown`, before anything is sent.
- **F. A catalog whose display name has the form of an object id** (BL-173): the export writes an
  access package's catalog reference to such a catalog by its id and leaves the catalog's own entry
  out, named as unread; the validator warns on a hand-written `groups`, `catalogs` or
  `accessPackages` entry whose display name has that form. An access review is looked up by its name
  only, so a review of that name is exported as before and not warned about (ruling R-7).
- **G. Azure eligibility deduplication tests the schedule id for white space** (BL-161e).

## What this file does not check, and why

- **E, the refusal itself** (class B): Azure Resource Manager always returns a resource group's
  location, so a read without one cannot be produced; the unit tests (an empty answer, an answer
  without the key, a blank location, and the no-try runspace) hold it. Check 4.1 shows the update path
  still sends the location it read.
- **C, the unknown permanence** (class B): Microsoft Graph returns `isExpirationRequired` on every
  expiration rule of a group's policy; the unit tests hold both pairs. Check 2.1 shows the diff
  converges on a live policy.
- **D, the empty answer** (class B): Azure Resource Manager answers a role definition list with a
  `value` list; the unit tests hold the transport switch. Check 3.1 shows a role that exists and one
  that does not.
- **F, the export side** (class B, ruling R-4): an object whose display name has the form of an object
  id cannot carry the prefix in its name. Decision A11 admits that form only with the conditions the
  group of step 2 met (the prefix in its alias and its description), and a catalog has no alias. The
  unit tests hold the reference, the left-out entry and the read not sent. Check 5.1 runs the
  validator half offline.
- **G** (class B): Azure Resource Manager always sends the schedule id; the unit test holds it.

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
- The prerequisite script `Initialize-OerS133Prereq.ps1` beside OerLive: run it once with `-WhatIf`,
  then with `-Unattended`; every `Read back` line must be `True` (the resource group line may be
  `False` when the subscription refused it, which makes check 4.1 class B).

**Run every numbered block in its OWN PowerShell process, started with `-NonInteractive`, after the
helpers block H.1** (the runner prepends H.1 to every block).

### H.1. The helpers every check uses

- [ ] **H.1** The helpers load; nothing is printed and nothing is sent. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s133-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s133'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$EmBase = 'v1.0/identityGovernance/entitlementManagement'
$IdFile = Join-Path $Raw 'known-ids.json'
$Ids0 = if (Test-Path -LiteralPath $IdFile) { Get-Content -LiteralPath $IdFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
$PimId = [string]$Ids0['pim'].Id; $CatId = [string]$Ids0['cat'].Id; $ApId = [string]$Ids0['ap'].Id
$PolId = [string]$Ids0['pol'].Id; $Expiry = [string]$Ids0['pol'].Expiry
$RgCreated = [bool]($Ids0.ContainsKey('rg') -and $Ids0['rg'].Created)
$Allowed = @($PimId, $CatId, $ApId, $PolId) | Where-Object { $_ }
function Connect-S133 {
    Connect-OerLive -Arm
    $script:S133Module = Get-Module -Name Omnicit.EntraRBAC
    Write-OerLiveStep "The module is the worktree's build: $($script:S133Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
    function global:Get-AzToken { throw 'S133 fence: no token request is expected after the sign-in.' }
    Write-OerLiveStep "Token fence in place: $((& $script:S133Module { Get-Command Get-AzToken }).CommandType -eq 'Function')"
    & $script:S133Module {
        param($AllowedIds)
        $script:S133Allowed = @($AllowedIds)
        $script:S133Log = [System.Collections.Generic.List[string]]::new()
        $script:S133Bodies = [System.Collections.Generic.List[object]]::new()
        $script:S133NoWrite = $false
        $script:S133RealGraph = ${function:Invoke-OERGraphRequest}
        $script:S133RealArm = ${function:Invoke-OERArmRequest}
        function script:Invoke-OERGraphRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Uri, [hashtable]$Body, [switch]$All, [string[]]$ExpectedErrorCode, [switch]$RequireValue)
            $Read = ($Method -eq 'GET') -or ($Uri -match 'getByIds|getMemberGroups|checkMember')
            $script:S133Log.Add($(if ($Read) { 'read' } else { "write $Method" }))
            if (-not $Read) {
                if ($script:S133NoWrite) { throw "S133 fence: a $Method request was refused; this check expects no write." }
                if (-not @($script:S133Allowed | Where-Object { $Uri -match [regex]::Escape($_) }).Count) { throw "S133 fence: a $Method of an object that is not a recorded prefixed object was refused." }
                $script:S133Bodies.Add($Body)
            }
            & $script:S133RealGraph @PSBoundParameters
        }
        function script:Invoke-OERArmRequest {
            [CmdletBinding()]
            param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Path, [object]$Body, [switch]$All, [switch]$RequireValue)
            $script:S133Log.Add($(if ($Method -eq 'GET') { 'read' } else { "write $Method" }))
            if ($Method -ne 'GET') {
                if ($script:S133NoWrite) { throw "S133 fence: an ARM $Method request was refused; this check expects no write." }
                if ($Path -notmatch '/resourceGroups/oer-s133-rg(\?|$)') { throw "S133 fence: an ARM $Method outside oer-s133-rg was refused." }
                $script:S133Bodies.Add($Body)
            }
            & $script:S133RealArm @PSBoundParameters
        }
    } $Allowed
    Write-OerLiveStep "Request fences in place: $((& $script:S133Module { (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S133 fence' -and (Get-Command Invoke-OERArmRequest).ScriptBlock.ToString() -match 'S133 fence' }))"
}
function Set-S133NoWrite { param([bool]$On) & $script:S133Module { param($V) $script:S133NoWrite = $V } $On }
function Get-S133Count { & $script:S133Module { '{0} read(s), {1} write(s)' -f @($script:S133Log | Where-Object { $_ -eq 'read' }).Count, @($script:S133Log | Where-Object { $_ -ne 'read' }).Count } }
function Get-S133Bodies { & $script:S133Module { , $script:S133Bodies.ToArray() } }
function Show-S133Row { param($Rows) foreach ($R in @($Rows)) { Write-OerLiveStep ("row: {0} | {1} | {2} | record: {3}" -f $R.Section, $R.Item, $R.Action, $(if ($R.Error) { ([string]$R.Error.FullyQualifiedErrorId -split ',')[0] } else { 'none' })) } }
function Read-S133Policy {
    # The policy read raw through the module's own transport, as the cmdlets read it.
    & $script:S133Module { param($Id) Invoke-OERGraphRequest -Uri "v1.0/identityGovernance/entitlementManagement/assignmentPolicies/$Id`?`$expand=accessPackage" } $PolId
}
function ConvertTo-S133Json {
    # A value as compact JSON with every dictionary's keys sorted, so two reads compare by content.
    param($Value)
    function Sort-S133 { param($V)
        if ($V -is [System.Collections.IDictionary]) { $O = [ordered]@{}; foreach ($K in @($V.Keys | Sort-Object)) { $O[$K] = Sort-S133 $V[$K] }; return $O }
        if ($V -is [System.Collections.IEnumerable] -and $V -isnot [string]) { return , @(foreach ($I in $V) { Sort-S133 $I }) }
        $V }
    ConvertTo-Json -InputObject (Sort-S133 $Value) -Depth 30 -Compress
}
function Get-S133ChangedKey {
    # The top-level keys whose content differs between two raw reads, apart from the ones named.
    param($Before, $After, [string[]]$Except)
    @(@($Before.Keys) + @($After.Keys) | Sort-Object -Unique | Where-Object { $_ -notin $Except -and (ConvertTo-S133Json $Before[$_]) -cne (ConvertTo-S133Json $After[$_]) })
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
        , @('A', 'BL-169a')
        , @('B', 'yyyy-MM-ddTHH:mm:ss.fffffffZ')
        , @('C', 'isExpirationRequired) is unknown: the read returned no value for it')
        , @('E', 'ResourceGroupValueUnknown')
        , @('F (export)', 'so the catalog cannot be declared by its name')
        , @('F (validator)', 'Add-GuidDisplayNameWarning'))) {
    Write-OerLiveStep "The build carries $($Marker[0]): $($Psm1.Contains($Marker[1]))"
}
Write-OerLiveStep "Recorded: group $([bool]$PimId), catalog $([bool]$CatId), package $([bool]$ApId), policy $([bool]$PolId), expiry $([bool]$Expiry), resource group created $RgCreated"
```

**Expect:** every line `True` (the resource group may be `False`, see Setup); the HEAD is this
branch's tip; 0 tracked changes.
**Failure looks like:** `False` on a marker (rebuild the worktree), or the main clone named.

Result:

## 1. The assignment policy (A, B)

### 1.1. How Microsoft Graph gives a fixed expiration date-time, and how the module writes it

- [ ] **1.1** The raw read's `endDateTime` type and kind are printed, and `Get-OERAccessPackageAssignmentPolicy` writes the same instant as an ISO 8601 UTC round-trip string. #type/subtask

```powershell
Connect-S133
Set-S133NoWrite $true
$Raw1 = Read-S133Policy
$End = $Raw1.expiration.endDateTime
$Written = [datetimeoffset]::Parse($Expiry, [cultureinfo]::InvariantCulture)
Write-OerLiveStep "Raw endDateTime: type $($End.GetType().Name); kind $(if ($End -is [datetime]) { $End.Kind } else { 'n/a' })"
$Instant = if ($End -is [datetime]) { [datetimeoffset][datetime]::SpecifyKind($End, $(if ($End.Kind -eq 'Unspecified') { 'Utc' } else { $End.Kind })) } elseif ($End -is [datetimeoffset]) { $End } else { [datetimeoffset]::Parse([string]$End, [cultureinfo]::InvariantCulture) }
Write-OerLiveStep "Raw endDateTime is the instant the prereq wrote (UTC): $($Instant.UtcDateTime -eq $Written.UtcDateTime)"
$P = Get-OERAccessPackageAssignmentPolicy -Id $PolId -ErrorAction Stop
Write-OerLiveStep "ExpirationDateTime is an ISO 8601 UTC round-trip string: $([string]$P.ExpirationDateTime -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$')"
Write-OerLiveStep "ExpirationDateTime is the written instant: $([datetimeoffset]::Parse([string]$P.ExpirationDateTime, [cultureinfo]::InvariantCulture).UtcDateTime -eq $Written.UtcDateTime)"
Write-OerLiveStep "Requests: $(Get-S133Count)"
```

**Expect:** a type and a kind are printed (the measurement); every other line `True`; 0 writes.
**Failure looks like:** `False` on the instant (the module moved the time), or a string that is not
the round-trip form.

Result:

### 1.2. The export round-trips the fixed expiration date-time: apply reports only Unchanged

- [ ] **1.2** `Get-OERInventory` of the prefix catalog writes `expirationDateTime` in round-trip form, and `Invoke-OERStructure` of that document reports every row Unchanged with no write. #type/subtask

```powershell
Connect-S133
Set-S133NoWrite $true
$Doc = Get-OERInventory -Include Catalogs, AccessPackages -Catalog $CatId -ErrorAction Stop -WarningAction SilentlyContinue
$Pol = @(@($Doc.accessPackages | Where-Object { $_.displayName -ceq 'oer-s133-ap' })[0].assignmentPolicies | Where-Object { $_.displayName -ceq 'oer-s133-pol' })[0]
Write-OerLiveStep "The export holds the policy: $([bool]$Pol)"
Write-OerLiveStep "expirationDateTime in the export is the round-trip string of the written instant: $([string]$Pol.expirationDateTime -ceq [datetimeoffset]::Parse($Expiry, [cultureinfo]::InvariantCulture).UtcDateTime.ToString('o', [cultureinfo]::InvariantCulture))"
$Json = $Doc | ConvertTo-Json -Depth 30
Set-Content -LiteralPath (Join-Path $Raw 'export-1.2.json') -Value $Json -Encoding utf8NoBOM
$Rows = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Continue)
Show-S133Row $Rows
Write-OerLiveStep "Every row Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0) ($($Rows.Count) row(s))"
Write-OerLiveStep "Requests: $(Get-S133Count)"
```

**Expect:** `True` on every line; the rows of the catalog, the package and the policy, all
`Unchanged`; 0 writes.
**Failure looks like:** an `Updated` policy row (the expiration did not round-trip) or a fence
refusal.

Result:

### 1.3. An apply that changes the description keeps every false and empty setting (G8)

- [ ] **1.3** The export of 1.2 with a new policy description is applied twice: the first run updates the policy and the update carries the settings the read had (an empty `questions` list included); the second run reports only Unchanged. #type/subtask

```powershell
Connect-S133
$Before = Read-S133Policy
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'export-1.2.json') -Raw | ConvertFrom-Json
$Pol = @(@($Doc.accessPackages | Where-Object { $_.displayName -ceq 'oer-s133-ap' })[0].assignmentPolicies | Where-Object { $_.displayName -ceq 'oer-s133-pol' })[0]
$Pol.description = 'oer-s133- policy description changed by check 1.3'
$Json = $Doc | ConvertTo-Json -Depth 30
$Rows1 = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Continue)
Show-S133Row $Rows1
$Bodies = @(Get-S133Bodies)
Write-OerLiveStep "Run 1: one write: $($Bodies.Count -eq 1)"
$B = $Bodies[0]
Write-OerLiveStep "The update sends questions as an empty list: $($B.ContainsKey('questions') -and @($B.questions).Count -eq 0)"
Write-OerLiveStep "The update keeps notifications disabled: $($B.notificationSettings.isAssignmentNotificationDisabled -eq $true)"
Write-OerLiveStep "The update keeps every requestor setting false: $(@($B.requestorSettings.Keys | Where-Object { $_ -ne 'onBehalfRequestors' -and $B.requestorSettings[$_] -ne $false }).Count -eq 0)"
$After = Wait-OerLiveConverged -Activity 'read the policy after run 1' -Read { Read-S133Policy } -Test { param($V) [string]$V.description -ceq 'oer-s133- policy description changed by check 1.3' }
$Diff = Get-S133ChangedKey -Before $Before -After $After.Value -Except 'modifiedDateTime', 'description', '@odata.context'
Write-OerLiveStep "Read raw before and after: only the description changed: $($Diff.Count -eq 0)$(if ($Diff.Count) { ' (' + ($Diff -join ', ') + ')' })"
Write-OerLiveStep "questions before and after: $(@($Before.questions).Count) and $(@($After.Value.questions).Count)"
Start-Sleep -Seconds 30
$Rows2 = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Continue)
Show-S133Row $Rows2
Write-OerLiveStep "Run 2: every row Unchanged: $(@($Rows2 | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0); writes in total: $(@(Get-S133Bodies).Count)"
```

**Expect:** run 1: the policy row `Updated`, exactly one write; every `True`; questions `0 and 0`;
run 2: every row `Unchanged`, writes in total `1`.
**Failure looks like:** a key other than the description that changed, a body without `questions`,
or an `Updated` row in run 2.

Result:

### 1.4. Set-OERAccessPackageAssignmentPolicy changes the description and keeps the rest

- [ ] **1.4** The cmdlet's own read-modify-write puts the description back and keeps every other key as it read it. #type/subtask

```powershell
Connect-S133
$Before = Read-S133Policy
$Out = Set-OERAccessPackageAssignmentPolicy -Id $PolId -Description 'Sprint 13 step 3 live check (oer-s133-)' -Confirm:$false -ErrorAction Stop
$B = @(Get-S133Bodies)[0]
Write-OerLiveStep "One write, which sends questions as an empty list: $(@(Get-S133Bodies).Count -eq 1 -and $B.ContainsKey('questions') -and @($B.questions).Count -eq 0)"
$After = Wait-OerLiveConverged -Activity 'read the policy after the update' -Read { Read-S133Policy } -Test { param($V) [string]$V.description -ceq 'Sprint 13 step 3 live check (oer-s133-)' }
$Diff = Get-S133ChangedKey -Before $Before -After $After.Value -Except 'modifiedDateTime', 'description', '@odata.context'
Write-OerLiveStep "Read raw before and after: only the description changed: $($Diff.Count -eq 0)$(if ($Diff.Count) { ' (' + ($Diff -join ', ') + ')' })"
Write-OerLiveStep "The output's ExpirationDateTime is the round-trip string: $([string]$Out.ExpirationDateTime -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$')"
```

**Expect:** every line `True`.
**Failure looks like:** a changed key besides the description.

Result:

## 2. The PIM for Groups policy diff (C, G8)

### 2.1. A declared eligible expiration converges

- [ ] **2.1** A document declaring the member policy's eligible expiration of `oer-s133-pim` is applied twice (run 1 Updated, run 2 Unchanged), and a document declaring only the permanence over the known live value changes nothing. #type/subtask

```powershell
Connect-S133
$Both = @{ version = '1.0'; groups = @(@{ displayName = 'oer-s133-pim'; pimPolicy = @{ member = @{ allowPermanentEligibility = $false; eligibleDurationDays = 90 } } }) } | ConvertTo-Json -Depth 10
$Rows1 = @(Invoke-OERStructure -Json $Both -Include Groups -Confirm:$false -ErrorAction Continue)
Show-S133Row $Rows1
Write-OerLiveStep "Run 1: writes $(@(Get-S133Bodies).Count)"
Start-Sleep -Seconds 30
$Rows2 = @(Invoke-OERStructure -Json $Both -Include Groups -Confirm:$false -ErrorAction Continue)
Show-S133Row $Rows2
Write-OerLiveStep "Run 2: every row Unchanged: $(@($Rows2 | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0)"
$PermOnly = @{ version = '1.0'; groups = @(@{ displayName = 'oer-s133-pim'; pimPolicy = @{ member = @{ allowPermanentEligibility = $false } } }) } | ConvertTo-Json -Depth 10
$Rows3 = @(Invoke-OERStructure -Json $PermOnly -Include Groups -Confirm:$false -ErrorAction Continue)
Show-S133Row $Rows3
Write-OerLiveStep "Permanence only, over the known live value: every row Unchanged: $(@($Rows3 | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0); writes in total: $(@(Get-S133Bodies).Count)"
$Live = Get-OERGroupPimPolicy -Group $PimId -AccessType member -ErrorAction Stop
Write-OerLiveStep "Live member policy: permanent eligibility $($Live.AllowPermanentEligibility), eligible days $($Live.EligibleDurationDays)"
```

**Expect:** run 1 the group row `Updated` with at least one write; run 2 and the permanence-only run
every row `Unchanged` and no further write; the live policy `False` and `90`.
**Failure looks like:** an `Updated` row in run 2, or a `PimRuleValueUnknown` refusal (the live
value is known here).

Result:

## 3. Get-OERRoleDefinition -Role (D)

### 3.1. A role that exists and a role that does not

- [ ] **3.1** `-Role Reader` at the test subscription returns the role; a role name that does not exist gives `RoleDefinitionNotFound`; nothing is written. #type/subtask

```powershell
Connect-S133
Set-S133NoWrite $true
$R = @(Get-OERRoleDefinition -Role 'Reader' -Subscription $Cfg.SubscriptionId -ErrorAction Stop)
Write-OerLiveStep "Reader: $($R.Count) role(s), named Reader: $(@($R | Where-Object { $_.RoleName -ceq 'Reader' }).Count -eq 1)"
$Ev = $null
$N = @(Get-OERRoleDefinition -Role 'oer-s133-no-such-role' -Subscription $Cfg.SubscriptionId -ErrorAction SilentlyContinue -ErrorVariable Ev)
$Own = @($Ev | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERRoleDefinition') })
Write-OerLiveStep "No such role: $($N.Count) object(s); own record(s): $(@($Own | ForEach-Object { ([string]$_.FullyQualifiedErrorId -split ',')[0] }) -join ', ')"
Write-OerLiveStep "Requests: $(Get-S133Count)"
```

**Expect:** `1 role(s), named Reader: True`; `0 object(s); own record(s): RoleDefinitionNotFound`;
0 writes.
**Failure looks like:** `ArmPagingIncomplete` for a real empty list, or a write.

Result:

## 4. Set-OERResourceGroup (E)

### 4.1. An update sends the location it read

- [ ] **4.1** `Set-OERResourceGroup` on `oer-s133-rg` sends the location the read returned and the given tags, twice. #type/subtask

```powershell
if (-not $RgCreated) { Write-OerLiveStep 'The subscription refused the resource group in the prereq: class B.'; return }
Connect-S133
$Before = Get-OERResourceGroup -Subscription $Cfg.SubscriptionId -Name 'oer-s133-rg' -ErrorAction Stop
foreach ($Run in 1, 2) {
    $Out = Set-OERResourceGroup -Subscription $Cfg.SubscriptionId -Name 'oer-s133-rg' -Tag @{ step = 'oer-s133-'; check = '4.1' } -Confirm:$false -ErrorAction Stop
    $B = @(Get-S133Bodies)[-1]
    Write-OerLiveStep "Run ${Run}: the PUT sends the location read: $([string]$B.location -ceq [string]$Before.Location -and -not [string]::IsNullOrWhiteSpace([string]$B.location)); output location unchanged: $([string]$Out.Location -ceq [string]$Before.Location); tags: $((@($Out.Tags.Keys | Sort-Object) -join ','))"
}
Write-OerLiveStep "Writes in total: $(@(Get-S133Bodies).Count)"
```

**Expect:** both runs `True; True; tags: check,step`; writes in total `2` (the cmdlet replaces the
tags on every call; it compares nothing).
**Failure looks like:** an empty location in the body, or `ResourceGroupValueUnknown` on a resource
group that has a location.

Result:

## 5. The validator (F)

### 5.1. A hand-written displayName in the form of an object id is a Warning in three sections

- [ ] **5.1** `Test-OERStructure` warns, and does not refuse, for a `groups`, `catalogs` and `accessPackages` entry whose display name has the form of an object id, and not for an `accessReviews` entry. Offline: no sign-in. #type/subtask

```powershell
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:PSModulePath = (Join-Path $Cfg.Repo 'output\RequiredModules') + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module $Psd1.FullName -Force
function global:Get-AzToken { throw 'S133 fence: 5.1 signs in to nothing.' }
$G = '{0}-{1}-{2}-{3}-{4}' -f 'aaaaaaaa', 'bbbb', 'cccc', 'dddd', 'eeeeeeeeeeee'   # a made-up display name in the form of an object id
$Doc = @{
    version       = '1.0'
    groups        = @(@{ displayName = $G })
    catalogs      = @(@{ displayName = $G })
    accessPackages = @(@{ displayName = $G; catalog = 'oer-s133-cat' })
    accessReviews = @(@{ displayName = $G; group = 'oer-s133-pim'; reviewers = @('self'); recurrence = 'quarterly' })
} | ConvertTo-Json -Depth 10
$T = Test-OERStructure -Json $Doc
$Guid = @($T.Errors | Where-Object { $_.Path -match '\.displayName$' -and $_.Message -match [regex]::Escape($G) })
foreach ($F in $Guid) { Write-OerLiveStep ("finding: {0} | {1}" -f $F.Severity, $F.Path) }
Write-OerLiveStep "Three Warnings at the groups, catalogs and accessPackages displayName paths, none for accessReviews, no Error among them: $($Guid.Count -eq 3 -and @($Guid | Where-Object { $_.Path -like 'accessReviews*' }).Count -eq 0 -and @($Guid | Where-Object { $_.Severity -ne 'Warning' }).Count -eq 0)"
```

**Expect:** three `Warning` lines at `groups[0].displayName`, `catalogs[0].displayName` and
`accessPackages[0].displayName`, and `True`.
**Failure looks like:** another count, a finding at `accessReviews[0].displayName`, or an `Error`.

Result:

## Teardown

### T.1. The prerequisite objects are removed

- [ ] **T.1** `Initialize-OerS133Prereq.ps1 -Teardown -Unattended` removes the resource group and every prefixed object, and the sweep is 0. #type/subtask

```powershell
pwsh -NoProfile -NonInteractive -File (Join-Path $VaultDir 'Initialize-OerS133Prereq.ps1') -Teardown -Unattended
```

**Expect:** `the resource group reads 404: True` (when created), `Teardown complete: the sweep is 0.`
**Failure looks like:** `Teardown NOT complete` -- run it again later and write the residue here.

Result:

### T.2. A read-back a minute later is clean

- [ ] **T.2** A sweep a minute after T.1 lists nothing with the prefix, and the step's raw folder is deleted. #type/subtask

```powershell
Connect-OerLive -Graph
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "Sweep: $($Left.Count) object(s) or unread kind(s) with the prefix."
if ($Left.Count -eq 0) { Remove-Item -LiteralPath $Raw -Recurse -Force -ErrorAction SilentlyContinue; Write-OerLiveStep "raw\s133 deleted: $(-not (Test-Path -LiteralPath $Raw))" }
```

**Expect:** `Sweep: 0`, `raw\s133 deleted: True`.
**Failure looks like:** a listed object -- write it here as residue.

Result:
