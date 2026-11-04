# Live verification checklist -- a failed read is published as itself (fix/failed-reads-reported-as-themselves)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** Nothing. Every check reads: resource groups and their role
assignments, Azure role management policies, and Microsoft Entra directory role management policies.
There is no prerequisite script and no test object; the teardown only proves that nothing carries the
prefix `oer-s123-` and that no session is left.

**Who runs it.** The dedicated certificate identities `oer-live-cc` and `oer-live-cc-noperm`, through
the OerLive library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in is app-only; nothing here signs in as a
person. Section 1 runs as `oer-live-cc-noperm` on purpose: its refusals are what this branch reports.
A 401 or 403 as `oer-live-cc` in section 2 is a stop.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s123/`, which
is git-ignored. Every block prints through the library's redactor. **No credential, token,
application id, tenant id, subscription id, resource group name, account or certificate thumbprint is
ever printed** -- identities are printed as True or False, records as their error id and a count --
and **no error record is ever rendered**.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. Role assignments, stages and decisions** ("publish a failed role assignment, stage or decision
  read as an error and leave it null"). `Get-OERResource` and `Get-OERResourceGroup`
  `-IncludeRoleAssignments` leave `RoleAssignments` `$null` and write the read's own error record when
  the role assignment read fails; `Get-OERAccessReviewInstance` does the same for `Stages` and
  `Decisions`. The object is still written, before the record.
- **B. Directory role names** ("publish a failed directory role names read as an error and keep the
  inventory's policies"). `Get-OERDirectoryRoleManagementPolicy -All` writes every policy with
  `RoleName` `$null`, then the names read's own record, when the role definition names cannot be
  read. `Get-OERInventory` still exports those policies, naming each role by its id.
- **C. Role and policy lookups** ("publish a failed role or policy lookup as itself"). In
  `Get-OERRoleManagementPolicy` and `Set-OERRoleManagementPolicy` a failed role definition or policy
  read is published with its own error id; `RoleDefinitionNotFound` and `PolicyNotFound` stay for a
  lookup that succeeded and found nothing. With `-CommonRoles` a failed read is one error record per
  role, never a warning; a role that does not exist at the scope is still skipped with a warning.
- **D. An answer without a value** ("read a PIM for Groups assignment answer without a value as
  unread"). Proven offline only: Microsoft Graph cannot be made to answer without `value`.

A live tenant is needed for what the unit tests stub: the real refusal Azure Resource Manager and
Microsoft Graph send an identity without permissions, and the real output for an identity with them.

## What this file does not check, and why

- **A failed stage or decision read** (A for `Get-OERAccessReviewInstance`, class B): an identity that
  can read a review's instances can read its stages and decisions, and the test tenant cannot refuse
  one without the other. The unit tests drive the refusal.
- **A failed names read after a successful policy read** (B, class B, unless 1.3 shows it): an
  identity refused the names is normally refused the policies first. Check 1.3 measures which read is
  refused.
- **A Graph answer without `value`** (D, class B): the shape is not measured on any endpoint.
- **`Set-OERRoleManagementPolicy`** (C): this file writes nothing. Its lookups are the same calls as
  `Get-OERRoleManagementPolicy -Role`, held by the unit tests.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.1.0** in the same folder; `$VaultDir` below is that folder (the environment variable
  `OER_LIVE_DIR`).
- The **dedicated certificate identities** `oer-live-cc` and `oer-live-cc-noperm` enabled for the run.
  This file adds no permission to either.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree.

**Run every numbered block in its OWN PowerShell process.**

### S.1. The module loads from this branch's build in the step's own worktree

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is never switched. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s123-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s123'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Psm1 = Join-Path $Psd1.DirectoryName 'Omnicit.EntraRBAC.psm1'
$A = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch 'Get-OERRoleAssignment @RaParams -ErrorAction Stop' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch 'function Test-OERRoleLookupUnresolved' -Quiet)
$D = [bool](Select-String -LiteralPath $Psm1 -SimpleMatch '-RequireValue' -Quiet)
Write-OerLiveStep "The worktree's build carries A (role assignments read with Stop): $A; C (the unresolved-lookup predicate): $C; D (the value requirement): $D"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `A ...: True; C ...: True; D ...:
True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; any other `False` -- build the worktree first (`./build.ps1 -Tasks build`), never while the
gate runs.

Result:

## 1. As oer-live-cc-noperm: every refused read is an error record, never an empty value

### 1.1. Get-OERResourceGroup -IncludeRoleAssignments, Get-OERRoleManagementPolicy -CommonRoles and Get-OERDirectoryRoleManagementPolicy -All

- [ ] **1.1** As `oer-live-cc-noperm`: the resource group read either lists groups (then each carries `RoleAssignments` `$null` and one record each when the assignments are refused) or is itself refused (then the check is skipped with that reason); `-CommonRoles` writes one record per refused role and no warning for them; `-All` writes the refusal of whichever directory read is refused, and `RoleName` is `$null` on every policy if it is the names read; `Get-OERInventory -CommonRoles` names the section unread. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s123-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s123'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm -NoPerm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Get-S123Id { param($Records) @($Records | ForEach-Object { [string]$_.FullyQualifiedErrorId }) }
# 1.1a: resource groups.
$Out = @(Get-OERResourceGroup -Subscription $Cfg.SubscriptionId -IncludeRoleAssignments -ErrorAction SilentlyContinue -ErrorVariable RgErr -WarningVariable RgWarn 3>$null)
$Own = @($RgErr | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERResourceGroup', [System.StringComparison]::Ordinal) })
$Groups = @($Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.ResourceGroup' })
Write-OerLiveStep ("1.1a resource groups returned: {0}; with RoleAssignments null: {1}; with RoleAssignments read: {2}; own records: {3}; own record ids: {4}; warnings: {5}" -f
    $Groups.Count, @($Groups | Where-Object { $null -eq $_.RoleAssignments }).Count, @($Groups | Where-Object { $null -ne $_.RoleAssignments }).Count,
    $Own.Count, ((Get-S123Id $Own | Sort-Object -Unique) -join ', '), @($RgWarn).Count)
# 1.1b: -CommonRoles at the test subscription.
$Pol = @(Get-OERRoleManagementPolicy -CommonRoles -Subscription $Cfg.SubscriptionId -ErrorAction SilentlyContinue -ErrorVariable RmpErr -WarningVariable RmpWarn 3>$null)
$OwnRmp = @($RmpErr | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERRoleManagementPolicy', [System.StringComparison]::Ordinal) })
Write-OerLiveStep ("1.1b policies returned: {0}; own records: {1}; own record ids: {2}; RoleDefinitionNotFound or PolicyNotFound among them: {3}; warnings: {4}; first own message: {5}" -f
    $Pol.Count, $OwnRmp.Count, ((Get-S123Id $OwnRmp | Sort-Object -Unique) -join ', '),
    [bool](@(Get-S123Id $OwnRmp) -match '^(RoleDefinitionNotFound|PolicyNotFound),'), @($RmpWarn).Count,
    $(if ($OwnRmp) { ConvertTo-OerLiveRedacted -Text ([string]$OwnRmp[0].Exception.Message) } else { '-' }))
# 1.1c: directory role management policies.
$Dir = @(Get-OERDirectoryRoleManagementPolicy -All -ErrorAction SilentlyContinue -ErrorVariable DirErr -WarningVariable DirWarn 3>$null)
$OwnDir = @($DirErr | Where-Object { ([string]$_.FullyQualifiedErrorId).EndsWith(',Get-OERDirectoryRoleManagementPolicy', [System.StringComparison]::Ordinal) })
Write-OerLiveStep ("1.1c policies returned: {0}; with RoleName null: {1}; own records: {2}; own record ids: {3}; warnings: {4}" -f
    $Dir.Count, @($Dir | Where-Object { $null -eq $_.RoleName }).Count, $OwnDir.Count, ((Get-S123Id $OwnDir | Sort-Object -Unique) -join ', '), @($DirWarn).Count)
# 1.1d: the inventory's -CommonRoles section.
$InvAll = @(Get-OERInventory -Include RoleManagementPolicies -CommonRoles -Subscription $Cfg.SubscriptionId -ErrorAction Continue -WarningVariable InvWarn 3>$null 2>&1)
$Inv = @($InvAll | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })[0]
$InvRec = @($InvAll | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
Write-OerLiveStep ("1.1d inventory returned: {0}; roleManagementPolicies entries: {1}; records on the stream: {2}; record ids: {3}; a record names roleManagementPolicies: {4}; warnings: {5}" -f
    [bool]$Inv, @($Inv.RoleManagementPolicies).Count, $InvRec.Count, ((Get-S123Id $InvRec | Sort-Object -Unique) -join ', '),
    [bool]@($InvRec | Where-Object { [string]$_.TargetObject -eq 'roleManagementPolicies' -or ([string]$_.Exception.Message).Contains('roleManagementPolicies') }), @($InvWarn).Count)
Disconnect-OerLive
```

**Expect:** the module is the build `True`. 1.1a: either `resource groups returned: 0` with one own
record (the list refused; the RoleAssignments half is then skipped, with that reason), or every
returned group with `RoleAssignments null` and one own record per group, `warnings: 0`. 1.1b:
`policies returned: 0`, `own records: 5` (one per curated role), ids that are the refusal's own
(for example `AuthorizationFailed`), `RoleDefinitionNotFound or PolicyNotFound among them: False`,
`warnings: 0`. If Azure Resource Manager instead answers the role definition lookup with 200 and an
empty list, the code legitimately reads each curated role as missing at the scope: `own records: 0`
and `warnings: 5` (`Skipping role`), which is then the measured answer, not the old shape. 1.1c:
`policies returned: 0` and one `PolicyReadFailed` record when the assignment read is refused first; or
every policy with `RoleName null` and one record if only the names read is refused; `warnings: 0`
either way. 1.1d (only when 1.1b wrote records): `inventory returned: True; roleManagementPolicies
entries: 0`, one `InventoryPartial` record that names `roleManagementPolicies`, `warnings: 0`.
**Failure looks like:** a warning in 1.1b beside a refused read, or `RoleDefinitionNotFound`/
`PolicyNotFound` for a refused read -- the old shape; a group whose `RoleAssignments` is an empty list
beside a record -- a failed read stated as an empty fact; in 1.1d, entries above 0 or no
`InventoryPartial` after 1.1b wrote records -- a subset written as the whole.

Result:

## 2. As oer-live-cc: the same reads write no record, and a second run gives the same output

### 2.1. The three reads twice, compared

- [ ] **2.1** As `oer-live-cc`: the three reads of 1.1 write no error record and no warning, every returned group carries a read `RoleAssignments` (never `$null`), every directory policy a non-null `RoleName`, and a second run gives the same output (convergence). #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s123-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s123'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($Module.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
function Invoke-S123Read {
    $E = @(); $W = @()
    $Rg = @(Get-OERResourceGroup -Subscription $Cfg.SubscriptionId -IncludeRoleAssignments -ErrorAction SilentlyContinue -ErrorVariable +E -WarningVariable +W 3>$null)
    $Rmp = @(Get-OERRoleManagementPolicy -CommonRoles -Subscription $Cfg.SubscriptionId -ErrorAction SilentlyContinue -ErrorVariable +E -WarningVariable +W 3>$null)
    $Dir = @(Get-OERDirectoryRoleManagementPolicy -All -ErrorAction SilentlyContinue -ErrorVariable +E -WarningVariable +W 3>$null)
    [PSCustomObject]@{
        Records  = @($E).Count
        Warnings = @($W).Count
        Groups   = $Rg.Count
        NullRa   = @($Rg | Where-Object { $null -eq $_.RoleAssignments }).Count
        Policies = $Rmp.Count
        DirPol   = $Dir.Count
        NullName = @($Dir | Where-Object { $null -eq $_.RoleName }).Count
        Shape    = (@(
                @($Rg | ForEach-Object { '{0}|{1}' -f $_.ResourceId, ((@($_.RoleAssignments | ForEach-Object { [string]$_.RoleAssignmentId }) | Sort-Object) -join ';') }) +
                @($Rmp | ForEach-Object { '{0}|{1}' -f $_.PolicyId, $_.RoleName }) +
                @($Dir | ForEach-Object { '{0}|{1}' -f $_.PolicyId, $_.RoleName })) | Sort-Object) -join "`n"
    }
}
$First = Invoke-S123Read
$Second = Invoke-S123Read
foreach ($Pair in @(@('first', $First), @('second', $Second))) {
    $R = $Pair[1]
    Write-OerLiveStep ("2.1 {0} run: records: {1}; warnings: {2}; resource groups: {3}, with RoleAssignments null: {4}; common role policies: {5}; directory policies: {6}, with RoleName null: {7}" -f
        $Pair[0], $R.Records, $R.Warnings, $R.Groups, $R.NullRa, $R.Policies, $R.DirPol, $R.NullName)
}
Write-OerLiveStep "2.1 the second run's output equals the first: $($First.Shape -ceq $Second.Shape)"
Disconnect-OerLive
```

**Expect:** the module is the build `True`; both runs `records: 0; warnings: 0`, at least one
resource group with `RoleAssignments null: 0`, `common role policies: 5`, directory policies above 0
with `RoleName null: 0`; `the second run's output equals the first: True`.
**Failure looks like:** a record or a warning as `oer-live-cc` -- STOP (G6: a 403 on the app path is a
missing permission); `False` on the comparison -- something changed between two reads with nothing
written: read the raw output.

Result:

## Teardown

### T.1. Nothing carries the prefix, no session is left, the main clone was never switched

- [ ] **T.1** No object carries `oer-s123-`, the module holds no session, and the raw folder for the step is deleted after the results are copied. #type/subtask

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s123-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s123'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
Connect-OerLive -Arm
$Module = Get-Module -Name Omnicit.EntraRBAC
$Left = @(Find-OerLivePrefixed -Quiet)
Write-OerLiveStep "T.1 objects carrying the prefix: $(@($Left | Where-Object { $_.Kind -ne 'unread' }).Count); collections that could not be read: $(@($Left | Where-Object { $_.Kind -eq 'unread' }).Count)"
Disconnect-OerLive
Write-OerLiveStep "T.1 the module holds a session after Disconnect-OerLive: $([bool](& $Module { $script:_OERAuthState }))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
Write-OerLiveStep "T.1 main clone: branch $(([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', '')"
```

**Expect:** `objects carrying the prefix: 0; collections that could not be read: 0`; `the module holds
a session after Disconnect-OerLive: False`; the main clone on `main`.
**Failure looks like:** a count above 0 -- this file creates nothing, so an object with the prefix is
not this run's: STOP.

Result:
