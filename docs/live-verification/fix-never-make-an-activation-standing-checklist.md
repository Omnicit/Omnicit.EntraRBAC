# Live verification checklist -- a PIM activation is never a standing membership (fix/never-make-an-activation-standing)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4, 5 and T has a written
result.** A box with no result line filled in is not a passed check -- it is an unrun one. If a check
turns out to be impossible to run, write "cannot be verified, and therefore we do not know" on its
result line and say why; do not leave it blank and do not tick it. A check that could not run for a
stated reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B)**,
and section C the one manual check (class C), which Philip makes after the merge.

**What this file writes to the tenant.** Six objects, created by the prerequisite script
`Initialize-OerS111Prereq.ps1` (beside OerLive, outside the repository): the disabled users
`oer-s111-user1` and `oer-s111-user2`; the group `oer-s111-pim` with user1 as its member and owner
(both added with `$ref`, outside PIM) and a time-bound (P30D) PIM-for-Groups member eligibility of
user2, who is not a member; the group `oer-s111-both` with user2 as its member (added with `$ref`)
and a time-bound member eligibility of the same user2; the group `oer-s111-nopim` with user1 as its
member and owner, never onboarded to PIM for Groups; and the group `oer-s111-plain`, empty. The two
eligibilities onboard their groups to PIM for Groups, which cannot be undone; every group is deleted
at teardown. Section 5 adds user1 to `oer-s111-plain` through `Invoke-OERStructure`, the one write
the module makes in this file. Sections 3 and 4 apply documents that must write nothing. The
teardown (T.1) removes every prefixed object. Bundles, documents and request logs are written under
`raw\s111\`, which is deleted after the results are written.

**Who runs it.** Every section: the dedicated certificate identity `oer-live-cc`, through the OerLive
library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in is app-only, with the certificate; nothing
here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s111/`,
which is git-ignored. Every block prints through the library's redactor, and the helpers print the
step's own object names, counts and True/False -- an id of a step object is replaced by its name before
it is printed. Each block is run in its own process whose whole output (standard output and standard
error) is written to a file under the runner's scratch folder, redacted with OerLive's redactor and a
mask for any GUID the redactor did not number, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The export** ("fix: leave PIM-held members and owners out of the export", "fix: tighten the
  export's PIM projection and its README text"). For each group it
  reads in full, `Export-OERInventory` and `Get-OERInventory` read the group's PIM-for-Groups
  assignment schedule instances once (`Read-OERGroupPimAssignment`, Graph beta through
  `Get-OERPimGroupsGraphPath`) and leave out of `members` and `owners` every principal whose access
  PIM for Groups holds: an activation, or a time-bound active assignment (`Get-OERGroupPimHeldAccess`
  owns the rule). A standing membership is written as before. When that read fails, a member or owner
  that is eligible for the same access is left out instead, and the read is named unread
  (`groups/<name>/pimAssignments`); when the eligibility was not read either, `members` is an explicit
  null. The bundle README says per group how many were left out.
- **B. The apply engine** ("fix: keep PIM-held members and owners out of standing adds and prunes").
  `Invoke-OERStructure` never adds a standing member or owner that the live group shows as eligible,
  or with a PIM-held active assignment, for the same access (Skipped, with a warning), and `-Prune`
  never removes one ("prune withheld:"). When that cannot be read, it adds and prunes none for the
  group.
- **C. Permissions** ("test: require the PIM assignment schedule scope for the new read").
  `Get-OERRequiredScope` names `PrivilegedAssignmentSchedule.Read.AzureADGroup` for the three cmdlets
  that now read it, and the required-scope gate holds the new path to that permission.
- **D. The texts** ("docs: say that a PIM activation is never written or applied as a standing
  membership"): the help of the three cmdlets, the bundle README, the prompt template, README, the
  about topic and the rationale.

What a live tenant adds: what Graph really answers for a standing membership, an ownership and an
eligibility in `assignmentScheduleInstances`, on beta and on v1.0, on a group onboarded to PIM for
Groups and on one never onboarded (1.1-1.3); an export of the step groups writing the standing
memberships, with one assignment read per group read in full (2.1, 2.2); an eligible principal
declared as a member and not added (3.1, 3.2); an eligible member withheld from a prune (4.1, 4.2);
and a plain member added as before, converging (5.1-5.3).

## What this file does not check, and why

- **A real activation.** It needs a user who activates; the identity is an app. Class C (C.1).
- **A time-bound active assignment.** `oer-live-cc` holds no PIM-for-Groups assignment write scope, so
  it cannot create one. Class B (B.2).
- **The reserve, and the partial signal, for a failed assignment read.** `oer-live-cc-noperm` cannot
  read the groups at all, and `oer-live-cc` reads the assignments (1.1 measures that it did even
  before the documented permission was granted), so no identity here reads the groups but not their
  PIM assignments. Class B (B.1).
- **The engine with an unread hold state.** Same reason. Class B (B.3).

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run.
- The **built module of this branch** in the step's own worktree (`./build.ps1 -Tasks build`), and
  the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it.
- The **prerequisite objects**, created by `Initialize-OerS111Prereq.ps1 -Unattended` (0.3 records
  the run).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration (`oer-testmiljo.psd1` and
`oer-cc-identitet.psd1`), and defines the fences, the request record, the readers and the document
writer. Nothing here signs in or writes to the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s111-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s111'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
$StepGroups = @('oer-s111-pim', 'oer-s111-both', 'oer-s111-nopim', 'oer-s111-plain')
$Upn = [ordered]@{ 'oer-s111-user1' = "oer-s111-user1@$($Cfg.UserDomain)"; 'oer-s111-user2' = "oer-s111-user2@$($Cfg.UserDomain)" }
# The ids the prerequisite recorded when it created the objects (name -> id); kept in memory, never printed.
$CreatedPath = Join-Path $Raw 'created-s111.json'
$S111Id = if (Test-Path -LiteralPath $CreatedPath) { Get-Content -LiteralPath $CreatedPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }

function Get-S111Who {
    # Replaces every step object's id and every step user's principal name by the object's name.
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $Out = [string]$Text
    foreach ($K in @($S111Id.Keys)) { $Out = $Out -ireplace [regex]::Escape([string]$S111Id[$K]), $K }
    foreach ($K in @($Upn.Keys)) { $Out = $Out -ireplace [regex]::Escape([string]$Upn[$K]), $K }
    $Out
}

function Start-S111Fence {
    # Get-AzToken forwards only a request that carries the certificate, so nothing can prompt. In the
    # module's own scope, Invoke-OERGraphRequest is wrapped once: each request's method and path are
    # recorded in memory and never printed as such.
    $global:S111Token = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Body = 'end { $global:S111Token.Add(((@($PSBoundParameters.Keys) | Sort-Object) -join '','')); if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { throw ''S111 fence: a token request without the certificate was refused; nothing prompts.'' }; AzAuth\Get-AzToken @PSBoundParameters }'
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
    $global:S111Graph = [System.Collections.Generic.List[object]]::new()
    & (Get-Module -Name Omnicit.EntraRBAC) {
        if (-not $script:S111OriginalGraph) { $script:S111OriginalGraph = (Get-Command -Name Invoke-OERGraphRequest -CommandType Function).ScriptBlock }
        $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-OERGraphRequest -CommandType Function))
        $Body = 'end { $M = if ($PSBoundParameters.ContainsKey(''Method'')) { [string]$PSBoundParameters[''Method''] } else { ''GET'' }; $global:S111Graph.Add([PSCustomObject]@{ Method = $M.ToUpperInvariant(); Uri = [string]$PSBoundParameters[''Uri''] }); & $script:S111OriginalGraph @PSBoundParameters }'
        $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
        Set-Item -Path function:script:Invoke-OERGraphRequest -Value ([scriptblock]::Create($Text))
    }
    $Seen = & (Get-Module -Name Omnicit.EntraRBAC) { '{0},{1}' -f (Get-Command Get-AzToken).CommandType, ([bool]((Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString() -match 'S111Graph')) }
    Write-OerLiveStep "fences in place (Get-AzToken is the proxy, the Graph wrapper records): $($Seen -eq 'Function,True')"
}

function Reset-S111Requests { $global:S111Token.Clear(); $global:S111Graph.Clear() }

function Write-S111Requests {
    # The module's requests since the last reset: how many, the writes (a getByIds or getMemberGroups POST
    # is a read), and how many assignment and eligibility reads each step group cost.
    param([Parameter(Mandatory)][string]$Label)
    $All = @($global:S111Graph)
    $Writes = @($All | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notmatch 'directoryObjects/(getByIds|[^/?]+/getMemberGroups)' })
    Write-OerLiveStep "$($Label): requests $($All.Count); writes $($Writes.Count); token requests $($global:S111Token.Count)"
    foreach ($W in $Writes) { Write-OerLiveStep ("$($Label): write: {0} {1}" -f $W.Method, (Get-S111Who ([uri]::UnescapeDataString($W.Uri)))) }
    foreach ($G in $StepGroups) {
        $Gid = [string]$S111Id[$G]
        $Mine = @($All | Where-Object { $Gid -and $_.Uri.IndexOf($Gid, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        $Assign = @($Mine | Where-Object { $_.Uri -match 'assignmentScheduleInstances' }).Count
        $Elig = @($Mine | Where-Object { $_.Uri -match 'eligibilityScheduleInstances' }).Count
        Write-OerLiveStep "$($Label): $($G): requests $($Mine.Count); assignment reads $Assign; eligibility reads $Elig"
    }
}

function Get-S111Relation {
    # The members or owners of one step group, by name, read with the raw SDK (each id replaced by its name).
    param([Parameter(Mandatory)][string]$Group, [Parameter(Mandatory)][ValidateSet('members', 'owners')][string]$Relation)
    $R = Invoke-OerLiveGraph -All -Uri "v1.0/groups/$($S111Id[$Group])/$($Relation)?`$select=id"
    Assert-OerLiveOk -Response $R -Activity "Reading the $Relation of $Group" | Out-Null
    @(@($R.Body['value']) | Where-Object { $null -ne $_ } | ForEach-Object { Get-S111Who ([string]$_['id']) } | Sort-Object)
}

function Write-S111Rows {
    # The apply rows, the warnings and the command's own errors, each id replaced by its name.
    param([object[]]$Rows, [object[]]$Warnings, [object[]]$Errors)
    foreach ($R in @($Rows | Where-Object { $null -ne $_ -and @($_.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.StructureResult' })) {
        Write-OerLiveStep ("row: {0} | {1} | {2} | {3}" -f $R.Section, $R.Item, $R.Action, (Get-S111Who ([string]$R.Detail)))
    }
    Write-OerLiveStep "warnings: $(@($Warnings).Count)"
    foreach ($W in @($Warnings)) { Write-OerLiveStep ('warning: ' + (Get-S111Who ([string]$W))) }
    $Own = @($Errors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure') })
    Write-OerLiveStep ("Invoke-OERStructure own errors: {0}{1}" -f $Own.Count, $(if ($Own.Count) { ' -- ' + (($Own | ForEach-Object { $_.FullyQualifiedErrorId }) -join '; ') } else { '' }))
}

function Save-S111Document {
    # One apply document under raw\s111, the groups given; members are written by user principal name.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][object[]]$Groups)
    $Path = Join-Path $Raw "$Name.json"
    $Doc = [ordered]@{ version = '1.0'; groups = @($Groups) }
    [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Doc -Depth 10), [System.Text.UTF8Encoding]::new($false))
    Write-OerLiveStep ("document {0}: {1}" -f $Name, (Get-S111Who (ConvertTo-Json -InputObject $Doc -Depth 10 -Compress)))
    $Path
}

function Invoke-S111Apply {
    # One fenced Invoke-OERStructure run of a document (-Include Groups), as a plan (-WhatIf) or a real run
    # (-Confirm:$false); the rows, the warnings, the own errors and the requests printed.
    param([Parameter(Mandatory)][string]$Path, [switch]$Prune, [switch]$Plan)
    Reset-S111Requests
    $Common = @{ Path = $Path; Include = 'Groups'; ErrorAction = 'Continue'; ErrorVariable = 'ApErr'; WarningAction = 'SilentlyContinue'; WarningVariable = 'ApWarn' }
    if ($Prune) { $Common.Prune = $true }
    $Rows = if ($Plan) { @(Invoke-OERStructure @Common -WhatIf) } else { @(Invoke-OERStructure @Common -Confirm:$false) }
    Write-S111Rows -Rows $Rows -Warnings @($ApWarn) -Errors @($ApErr)
    Write-S111Requests -Label $(if ($Plan) { 'plan' } else { 'run' })
}
```

### S.1. The module loads from this branch's build

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch; the main clone is on `main`, never switched.

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Marks = @('function Read-OERGroupPimAssignment', 'function Get-OERGroupPimHeldAccess', 'function Read-OERGroupPimHold', 'PimHeldReason')
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $Psm1) { Write-OerLiveStep 'this branch build: not found' } else {
    $Hits = @($Marks | Where-Object { Select-String -LiteralPath $Psm1.FullName -SimpleMatch $_ -Quiet }).Count
    $Ver = Import-PowerShellDataFile -LiteralPath ($Psm1.FullName -replace '\.psm1$', '.psd1')
    Write-OerLiveStep "this branch build: version $($Ver.ModuleVersion) $($Ver.PrivateData.PSData.Prerelease); marks of this branch: $Hits of $($Marks.Count)"
}
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `marks of this branch: 4 of 4`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), or fewer than 4 marks
(build it first, never while the gate runs).

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree on this branch at cf13f0a with 0 tracked changes; the build carries all 4 marks of the change. The build was made from 114d8d8's source; cf13f0a changed help and documents only. (A first run of this block, while the texts task was still committing, read 5 tracked changes; this re-run is the record.)

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s111] The module loads from a worktree that is not the main clone: True
[oer-s111] Main clone: branch main
[oer-s111] Worktree: branch fix/never-make-an-activation-standing; HEAD cf13f0a docs: state the edge cases of the PIM hold in the help, the guides and the rationale; tracked changes: 0
[oer-s111] this branch build: version 1.2.1 fix0001; marks of this branch: 4 of 4
RUNNER: check S.1 exit code 0; started 2026-10-13T12:00:25Z; took 2 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc (app-only, certificate); identity check passed; the module is the worktree's build (1.2.1).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] The module is the worktree's build: True
RUNNER: check 0.1 exit code 0; started 2026-10-13T11:55:31Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.2. The identity's PIM-for-Groups permissions, and the assignment read answers (A12)

- [x] **0.2** The Microsoft Graph application permissions of `oer-live-cc`, by name, as True/False; and one read of `assignmentScheduleInstances` per step group, through the module's own reader, answers without a 403.

```powershell
Connect-OerLive -Arm
$Sp = Invoke-OerLiveGraph -All -Uri ("v1.0/servicePrincipals?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("appId eq '$($Cfg.AppId)'"))
Assert-OerLiveOk -Response $Sp -Activity "Reading oer-live-cc's service principal" | Out-Null
$A = Invoke-OerLiveGraph -All -Uri "v1.0/servicePrincipals/$([string]@($Sp.Body['value'])[0]['id'])/appRoleAssignments"
Assert-OerLiveOk -Response $A -Activity "Reading oer-live-cc's application permissions" | Out-Null
$Names = [System.Collections.Generic.List[string]]::new()
foreach ($Resource in @(@($A.Body['value']) | Where-Object { $null -ne $_ } | Group-Object -Property { [string]$_['resourceId'] })) {
    $R = Invoke-OerLiveGraph -Uri "v1.0/servicePrincipals/$($Resource.Name)?`$select=displayName,appRoles"
    Assert-OerLiveOk -Response $R -Activity 'Reading the permissions of a resource service principal' | Out-Null
    if ([string]$R.Body['displayName'] -cne 'Microsoft Graph') { continue }
    foreach ($Assignment in $Resource.Group) {
        $Role = @(@($R.Body['appRoles']) | Where-Object { [string]$_['id'] -eq [string]$Assignment['appRoleId'] })
        if ($Role.Count -eq 1) { $Names.Add([string]$Role[0]['value']) }
    }
}
Write-OerLiveStep "oer-live-cc holds $($Names.Count) Microsoft Graph application permission(s)."
foreach ($N in 'PrivilegedAssignmentSchedule.Read.AzureADGroup', 'PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup', 'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup', 'PrivilegedAccess.Read.AzureADGroup', 'PrivilegedAccess.ReadWrite.AzureADGroup') {
    Write-OerLiveStep "oer-live-cc holds $($N): $($Names -ccontains $N)"
}
foreach ($G in $StepGroups) {
    $Read = & (Get-Module -Name Omnicit.EntraRBAC) { param($Id) Read-OERGroupPimAssignment -GroupId $Id } ([string]$S111Id[$G])
    Write-OerLiveStep "$($G): read $($Read.Read); rows $(@($Read.Value).Count); message: $(Get-S111Who ([string]$Read.Message))"
}
Disconnect-OerLive
```

**Expect:** `oer-live-cc holds PrivilegedAssignmentSchedule.Read.AzureADGroup: True` once Philip has
granted it (P-14); every step group `read True`, with `rows 2` for `oer-s111-pim` and
`oer-s111-nopim`, `rows 1` for `oer-s111-both` and `rows 0` for `oer-s111-plain`, and an empty message.
**Failure looks like:** `read False` with a 403 in the message -- STOP: the permission the step needs
is missing (decision A12; never grant it yourself).

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, with a measurement for A12. oer-live-cc does NOT yet hold PrivilegedAssignmentSchedule.Read.AzureADGroup (False; the grant of P-14 is not visible at this run), yet the module's reader read every step group's assignmentScheduleInstances with no 403 (read True; rows 2, 1, 2, 0; no message). No STOPP under A12, which stops only on a 403. Which of the identity's 18 Graph permissions allows the read is not established; Microsoft Learn names PrivilegedAssignmentSchedule.Read.AzureADGroup as the least privileged one, and the module's consent list names it.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] oer-live-cc holds 18 Microsoft Graph application permission(s).
[oer-s111] oer-live-cc holds PrivilegedAssignmentSchedule.Read.AzureADGroup: False
[oer-s111] oer-live-cc holds PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup: False
[oer-s111] oer-live-cc holds PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup: True
[oer-s111] oer-live-cc holds PrivilegedAccess.Read.AzureADGroup: False
[oer-s111] oer-live-cc holds PrivilegedAccess.ReadWrite.AzureADGroup: False
[oer-s111] oer-s111-pim: read True; rows 2; message: 
[oer-s111] oer-s111-both: read True; rows 1; message: 
[oer-s111] oer-s111-nopim: read True; rows 2; message: 
[oer-s111] oer-s111-plain: read True; rows 0; message:
RUNNER: check 0.2 exit code 0; started 2026-10-13T11:55:39Z; took 10 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.3. The prerequisite: two users, four groups, the memberships and the eligibilities

- [x] **0.3** `Initialize-OerS111Prereq.ps1` created the objects before the code was written (DEL 1, its transcript under `raw\s111\`); a plan run and a second real run now find every object and write nothing.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS111Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'))) {
    Write-OerLiveStep "prereq run: $($Run -join ' ')"
    & pwsh -NoProfile -NonInteractive -File $Script @Run 2>&1 | ForEach-Object { "$_" }
    Write-OerLiveStep "prereq exit code: $LASTEXITCODE"
}
$Log = Get-ChildItem -LiteralPath $Raw -Filter 'prereq-*.log' | Sort-Object Name | Select-Object -First 1
if ($Log) { Write-OerLiveStep "first prerequisite run: $($Log.Name)"; Get-Content -LiteralPath $Log.FullName | Where-Object { $_ -match 'Created|Added|Requested|baseline|Summary' } | ForEach-Object { Write-OerLiveStep "  $_" } }
```

**Expect:** the first run (DEL 1) wrote the baseline, created the two users (disabled) and the four
groups, added the five memberships and ownerships (204 each), and requested the two eligibilities
(201, `Provisioned`); the plan run ends `WhatIf: nothing was created, removed or written.`, exit code
0; the real run finds every object, `written to the tenant: False`, exit code 0. (`oer-s111-plain`
may hold `oer-s111-user1` once section 5 has run; the prerequisite knows that member.)
**Failure looks like:** a refusal, an exit code other than 0, or a second run that writes.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The first run (DEL 1, 10:01 UTC) wrote the baseline (users 22, groups 97), created the two disabled users and the four groups (201 each), added the five memberships and ownerships (204 each) and requested the two member eligibilities (201, Provisioned; each listed at once). Now the plan run wrote nothing (exit 0) and the real run found every object and wrote nothing (written to the tenant: False, exit 0).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s111] prereq run: -WhatIf
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s111\prereq-20261013-115618Z.log".
[oer-s111] Mode: CREATE or complete. Prefix 'oer-s111-'. Objects (fixed): oer-s111-user1, oer-s111-user2 (disabled users), oer-s111-pim, oer-s111-both, oer-s111-nopim, oer-s111-plain (plain security groups). OerLive 1.0.3.
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s111] Found: oer-s111-user1 exists: True; oer-s111-user2 exists: True; oer-s111-pim exists: True; oer-s111-both exists: True; oer-s111-nopim exists: True; oer-s111-plain exists: True
[oer-s111] The baseline exists (users 22, groups 97 when it was written).
[oer-s111] User oer-s111-user1 exists.
[oer-s111] User oer-s111-user2 exists.
[oer-s111] Group oer-s111-pim exists.
[oer-s111] Group oer-s111-both exists.
[oer-s111] Group oer-s111-nopim exists.
[oer-s111] Group oer-s111-plain exists.
[oer-s111] oer-s111-user1 is in the members of oer-s111-pim already.
[oer-s111] oer-s111-user1 is in the owners of oer-s111-pim already.
[oer-s111] oer-s111-user2 is in the members of oer-s111-both already.
[oer-s111] oer-s111-user1 is in the members of oer-s111-nopim already.
[oer-s111] oer-s111-user1 is in the owners of oer-s111-nopim already.
[oer-s111] The member eligibility of oer-s111-user2 in oer-s111-pim exists.
[oer-s111] The member eligibility of oer-s111-user2 in oer-s111-both exists.
[oer-s111] Summary: oer-s111-user1 present; oer-s111-user2 present; oer-s111-pim present; oer-s111-both present; oer-s111-nopim present; oer-s111-plain present; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s111] WhatIf: nothing was created, removed or written.
[oer-s111] Done.
[oer-s111] prereq exit code: 0
[oer-s111] prereq run: -Unattended
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s111] Transcript (redacted): raw\s111\prereq-20261013-115626Z.log; OerLive 1.0.3.
[oer-s111] Mode: CREATE or complete. Prefix 'oer-s111-'. Objects (fixed): oer-s111-user1, oer-s111-user2 (disabled users), oer-s111-pim, oer-s111-both, oer-s111-nopim, oer-s111-plain (plain security groups). OerLive 1.0.3.
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s111] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s111] Found: oer-s111-user1 exists: True; oer-s111-user2 exists: True; oer-s111-pim exists: True; oer-s111-both exists: True; oer-s111-nopim exists: True; oer-s111-plain exists: True
[oer-s111] The baseline exists (users 22, groups 97 when it was written).
[oer-s111] User oer-s111-user1 exists.
[oer-s111] User oer-s111-user2 exists.
[oer-s111] Group oer-s111-pim exists.
[oer-s111] Group oer-s111-both exists.
[oer-s111] Group oer-s111-nopim exists.
[oer-s111] Group oer-s111-plain exists.
[oer-s111] oer-s111-user1 is in the members of oer-s111-pim already.
[oer-s111] oer-s111-user1 is in the owners of oer-s111-pim already.
[oer-s111] oer-s111-user2 is in the members of oer-s111-both already.
[oer-s111] oer-s111-user1 is in the members of oer-s111-nopim already.
[oer-s111] oer-s111-user1 is in the owners of oer-s111-nopim already.
[oer-s111] The member eligibility of oer-s111-user2 in oer-s111-pim exists.
[oer-s111] The member eligibility of oer-s111-user2 in oer-s111-both exists.
[oer-s111] Summary: oer-s111-user1 present; oer-s111-user2 present; oer-s111-pim present; oer-s111-both present; oer-s111-nopim present; oer-s111-plain present; written to the tenant: False.
[oer-s111] Done.
[oer-s111] prereq exit code: 0
[oer-s111] first prerequisite run: prereq-20261013-100153Z.log
[oer-s111]   [oer-s111] No baseline yet: it is written now, before the first write to the tenant (users 22, groups 97).
[oer-s111]   [oer-s111] Wrote the baseline raw\s111\baseline-s111.json and read it back.
[oer-s111]   [oer-s111] Created user oer-s111-user1 (disabled): 201.
[oer-s111]   [oer-s111] Created user oer-s111-user2 (disabled): 201.
[oer-s111]   [oer-s111] Created group oer-s111-pim: 201.
[oer-s111]   [oer-s111] Created group oer-s111-both: 201.
[oer-s111]   [oer-s111] Created group oer-s111-nopim: 201.
[oer-s111]   [oer-s111] Created group oer-s111-plain: 201.
[oer-s111]   [oer-s111] Added oer-s111-user1 to the members of oer-s111-pim: 204.
[oer-s111]   [oer-s111] Added oer-s111-user1 to the owners of oer-s111-pim: 204.
[oer-s111]   [oer-s111] Added oer-s111-user2 to the members of oer-s111-both: 204.
[oer-s111]   [oer-s111] Added oer-s111-user1 to the members of oer-s111-nopim: 204.
[oer-s111]   [oer-s111] Added oer-s111-user1 to the owners of oer-s111-nopim: 204.
[oer-s111]   [oer-s111] Requested the member eligibility of oer-s111-user2 in oer-s111-pim: 201, status Provisioned; this onboarded the group.
[oer-s111]   [oer-s111] Requested the member eligibility of oer-s111-user2 in oer-s111-both: 201, status Provisioned; this onboarded the group.
[oer-s111]   [oer-s111] Summary: oer-s111-user1 present; oer-s111-user2 present; oer-s111-pim present; oer-s111-both present; oer-s111-nopim present; oer-s111-plain present; written to the tenant: True.
RUNNER: check 0.3 exit code 0; started 2026-10-13T11:56:15Z; took 17 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. The measurement (DEL 1, read-only)

### 1.1. What assignmentScheduleInstances answers, beta and v1.0

- [x] **1.1** For each step group, the PIM-for-Groups `assignmentScheduleInstances`, `assignmentSchedules` and `eligibilityScheduleInstances` read with the raw SDK on beta and on v1.0: the status, the rows, and for each row the principal (by name), `accessId`, `memberType`, `assignmentType`, whether `startDateTime` and `endDateTime` are set.

```powershell
Connect-OerLive -Arm
foreach ($G in $StepGroups) {
    $Filter = [uri]::EscapeDataString("groupId eq '$($S111Id[$G])'")
    foreach ($Version in 'beta', 'v1.0') {
        foreach ($Coll in 'assignmentScheduleInstances', 'assignmentSchedules', 'eligibilityScheduleInstances') {
            $R = Invoke-OerLiveGraph -All -Uri "$Version/identityGovernance/privilegedAccess/group/$($Coll)?`$filter=$Filter"
            if (-not $R.Ok) { Write-OerLiveStep "$G $Version $($Coll): HTTP $($R.Status) code '$($R.Code)'"; continue }
            $Rows = @(@($R.Body['value']) | Where-Object { $null -ne $_ })
            Write-OerLiveStep "$G $Version $($Coll): HTTP $($R.Status), $($Rows.Count) row(s)"
            foreach ($Row in $Rows) {
                Write-OerLiveStep ("  row: principal {0}; accessId {1}; memberType {2}; assignmentType {3}; startDateTime {4}; endDateTime {5}" -f (Get-S111Who ([string]$Row['principalId'])), $Row['accessId'], $Row['memberType'], $Row['assignmentType'], $(if ($Row['startDateTime']) { 'set' } else { 'null' }), $(if ($null -ne $Row['endDateTime']) { 'set' } else { 'null' }))
            }
        }
    }
}
Disconnect-OerLive
```

**Expect (measured in DEL 1, 2026-10-13):** `oer-s111-pim` and `oer-s111-nopim`: 2 assignment
instance rows, `oer-s111-user1` as `member` and as `owner`, `memberType direct`, `assignmentType
assigned`, both dates null -- a standing membership and ownership added outside PIM are listed, on a
group never onboarded too; `oer-s111-both`: 1 row, `oer-s111-user2` member, the same shape;
`oer-s111-plain`: 0 rows (1 row for `oer-s111-user1` once section 5 has added it); the eligibility of
`oer-s111-user2` in `oer-s111-pim` and `oer-s111-both` appears ONLY under
`eligibilityScheduleInstances`, with both dates set; beta and v1.0 the same rows.
**Failure looks like:** a 401 or 403 (STOP), an eligibility listed as an assignment instance, or
beta and v1.0 differing (record it: a reason to revisit the beta pin is a STOP for this step).

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (the measurement). A standing membership and ownership added with $ref are listed in assignmentScheduleInstances as accessId member/owner, memberType direct, assignmentType assigned, both dates null -- on oer-s111-nopim, never onboarded to PIM for Groups, too (200, not ResourceTypeNotSupported). The eligibility of oer-s111-user2 is listed only under eligibilityScheduleInstances, with both dates set. The empty group answers 200 with 0 rows. beta and v1.0 answer the same rows: no reason to change the beta pin.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] oer-s111-pim beta assignmentScheduleInstances: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-pim beta assignmentSchedules: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-pim beta eligibilityScheduleInstances: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType ; startDateTime set; endDateTime set
[oer-s111] oer-s111-pim v1.0 assignmentScheduleInstances: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-pim v1.0 assignmentSchedules: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-pim v1.0 eligibilityScheduleInstances: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType ; startDateTime set; endDateTime set
[oer-s111] oer-s111-both beta assignmentScheduleInstances: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-both beta assignmentSchedules: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-both beta eligibilityScheduleInstances: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType ; startDateTime set; endDateTime set
[oer-s111] oer-s111-both v1.0 assignmentScheduleInstances: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-both v1.0 assignmentSchedules: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-both v1.0 eligibilityScheduleInstances: HTTP 200, 1 row(s)
[oer-s111]   row: principal oer-s111-user2; accessId member; memberType direct; assignmentType ; startDateTime set; endDateTime set
[oer-s111] oer-s111-nopim beta assignmentScheduleInstances: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-nopim beta assignmentSchedules: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-nopim beta eligibilityScheduleInstances: HTTP 200, 0 row(s)
[oer-s111] oer-s111-nopim v1.0 assignmentScheduleInstances: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-nopim v1.0 assignmentSchedules: HTTP 200, 2 row(s)
[oer-s111]   row: principal oer-s111-user1; accessId owner; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111]   row: principal oer-s111-user1; accessId member; memberType direct; assignmentType assigned; startDateTime null; endDateTime null
[oer-s111] oer-s111-nopim v1.0 eligibilityScheduleInstances: HTTP 200, 0 row(s)
[oer-s111] oer-s111-plain beta assignmentScheduleInstances: HTTP 200, 0 row(s)
[oer-s111] oer-s111-plain beta assignmentSchedules: HTTP 200, 0 row(s)
[oer-s111] oer-s111-plain beta eligibilityScheduleInstances: HTTP 200, 0 row(s)
[oer-s111] oer-s111-plain v1.0 assignmentScheduleInstances: HTTP 200, 0 row(s)
[oer-s111] oer-s111-plain v1.0 assignmentSchedules: HTTP 200, 0 row(s)
[oer-s111] oer-s111-plain v1.0 eligibilityScheduleInstances: HTTP 200, 0 row(s)
RUNNER: check 1.1 exit code 0; started 2026-10-13T11:56:35Z; took 23 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. What the module's reader and rule make of it

- [x] **1.2** Through the module (this branch's build): `Read-OERGroupPimAssignment` reads each step group, `Get-OERGroupPimHeldAccess` finds no principal held through an activation or a time-bound assignment (every row is standing), and the engine's `Read-OERGroupPimHold` finds `oer-s111-user2` held as eligible for member access in `oer-s111-pim` and `oer-s111-both`.

```powershell
Connect-OerLive -Arm
foreach ($G in $StepGroups) {
    $Out = & (Get-Module -Name Omnicit.EntraRBAC) {
        param($Id)
        $A = Read-OERGroupPimAssignment -GroupId $Id
        $Held = @(Get-OERGroupPimHeldAccess -Assignment @($A.Value))
        $Hold = Read-OERGroupPimHold -GroupId $Id
        [PSCustomObject]@{ Read = $A.Read; Rows = @($A.Value).Count; Held = $Held; HoldRead = $Hold.Read; HoldKeys = @($Hold.Held.Keys); HoldReasons = @($Hold.Held.Values); Cause = $Hold.Cause }
    } ([string]$S111Id[$G])
    Write-OerLiveStep "$($G): assignment read $($Out.Read), rows $($Out.Rows); held through an activation or a time-bound assignment: $(@($Out.Held).Count)"
    Write-OerLiveStep ("$($G): engine hold read $($Out.HoldRead); held: {0}" -f $(if (@($Out.HoldKeys).Count) { (@(for ($I = 0; $I -lt @($Out.HoldKeys).Count; $I++) { (Get-S111Who ([string]@($Out.HoldKeys)[$I])) + ' -> ' + @($Out.HoldReasons)[$I] }) -join '; ') } else { 'none' }))
}
Disconnect-OerLive
```

**Expect:** every group `assignment read True` with the row counts of 1.1 and `held ... 0`; the engine
hold `read True`, holding `oer-s111-user2|member -> is eligible for member access in PIM for Groups`
in `oer-s111-pim` and `oer-s111-both`, and nothing in `oer-s111-nopim` and `oer-s111-plain`.
**Failure looks like:** a standing row counted as held (the rule is wrong), or a read that is not
`True`.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Through the module, the reader reads every step group (read True, the row counts of 1.1) and the rule finds nobody held through an activation or a time-bound assignment (every row is standing); the engine's hold read finds oer-s111-user2 eligible for member access in oer-s111-pim and oer-s111-both, and nobody in the two others.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] oer-s111-pim: assignment read True, rows 2; held through an activation or a time-bound assignment: 0
[oer-s111] oer-s111-pim: engine hold read True; held: oer-s111-user2|member -> is eligible for member access in PIM for Groups
[oer-s111] oer-s111-both: assignment read True, rows 1; held through an activation or a time-bound assignment: 0
[oer-s111] oer-s111-both: engine hold read True; held: oer-s111-user2|member -> is eligible for member access in PIM for Groups
[oer-s111] oer-s111-nopim: assignment read True, rows 2; held through an activation or a time-bound assignment: 0
[oer-s111] oer-s111-nopim: engine hold read True; held: none
[oer-s111] oer-s111-plain: assignment read True, rows 0; held through an activation or a time-bound assignment: 0
[oer-s111] oer-s111-plain: engine hold read True; held: none
RUNNER: check 1.2 exit code 0; started 2026-10-13T11:56:59Z; took 15 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. The export writes the standing memberships (A)

### 2.1. The default export of the step groups

- [x] **2.1** `Export-OERInventory -Include Groups -GroupFilter "startswith(displayName,'oer-s111-')"` keeps `oer-s111-pim` and `oer-s111-both` (PIM eligibility) with their standing members and owners written, says in the README that nothing was left out as PIM access, reads the PIM assignments once for each kept group and never for a group it does not keep, and is not partial.

```powershell
Connect-OerLive -Arm
Start-S111Fence
Reset-S111Requests
$Out = Export-OERInventory -OutputPath (Join-Path $Raw 'bundle-default') -Include Groups -GroupFilter "startswith(displayName,'oer-s111-')" -Force -ErrorAction Continue -ErrorVariable ExErr -WarningVariable ExWarn
Write-OerLiveStep "bundle: groups $($Out.Groups); IncompleteReads $(@($Out.IncompleteReads).Count); warnings $(@($ExWarn).Count); own errors $(@($ExErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',Export-OERInventory') }).Count)"
Write-S111Requests -Label 'export'
$Inv = Get-Content -LiteralPath (Join-Path $Out.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
foreach ($E in @($Inv.groups)) {
    $Members = if ($null -eq $E.members) { 'null' } else { (@($E.members | ForEach-Object { Get-S111Who ([string]$_) }) | Sort-Object) -join ', ' }
    $Owners = if ($E.PSObject.Properties.Name -contains 'owners') { (@($E.owners | ForEach-Object { Get-S111Who ([string]$_) }) | Sort-Object) -join ', ' } else { '(no key)' }
    $Elig = (@($E.eligibility | ForEach-Object { '{0}/{1}' -f (Get-S111Who ([string]$_.principal)), $_.accessType }) | Sort-Object) -join ', '
    Write-OerLiveStep "inventory: $($E.displayName): members [$Members]; owners [$Owners]; eligibility [$Elig]"
}
$Readme = Get-Content -LiteralPath (Join-Path $Out.BundlePath 'README.md')
$At = [array]::IndexOf($Readme, ($Readme | Where-Object { $_ -like '## Members and owners left out*' } | Select-Object -First 1))
Write-OerLiveStep "README section found: $($At -ge 0)"
if ($At -ge 0) { $Readme[$At..([Math]::Min($At + 20, $Readme.Count - 1))] | Where-Object { $_ -match '^- |^None|^Nothing|left out' } | ForEach-Object { Write-OerLiveStep "README: $(Get-S111Who $_)" } }
$Roster = Get-Content -LiteralPath (Join-Path $Out.BundlePath 'groupsRoster.json') -Raw | ConvertFrom-Json
foreach ($G in $StepGroups) { $Row = @($Roster | Where-Object { $_.displayName -eq $G }); Write-OerLiveStep "roster: $($G): memberCount $(if ($Row.Count) { if ($null -eq $Row[0].memberCount) { 'null' } else { $Row[0].memberCount } } else { 'no row' })" }
Disconnect-OerLive
```

**Expect:** `groups 2`, `IncompleteReads 0`, no own error; `inventory: oer-s111-both: members
[oer-s111-user2]; owners [(no key)]; eligibility [oer-s111-user2/member]` (a standing member who is
also eligible is written, ruling R2) and `inventory: oer-s111-pim: members [oer-s111-user1]; owners
[oer-s111-user1]; eligibility [oer-s111-user2/member]`; the README section found, saying no member or
owner was left out; `writes 0`; `assignment reads 1` for `oer-s111-pim` and `oer-s111-both`, `0` for
`oer-s111-nopim` and `oer-s111-plain` (not kept, so not read in full); the roster `memberCount` 1 for
the two kept groups and null for the two others.
**Failure looks like:** a standing member missing from `members`, an `InventoryPartial`, an
assignment read for a group not read in full, or more than one for a kept group.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The default export of the step groups keeps oer-s111-pim and oer-s111-both (PIM eligibility) with their standing members and owners written -- oer-s111-both's member is also eligible and is written (a standing membership is written as before) -- IncompleteReads 0, no own error, no write; the README section exists and says nothing was left out; one assignment read for each of the two kept groups and none for the two groups not kept (2 requests each: eligibility and the PIM-in-use criterion); the roster memberCount 1 for the kept groups and null for the others.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] bundle: groups 2; IncompleteReads 0; warnings 0; own errors 0
[oer-s111] export: requests 31; writes 0; token requests 0
[oer-s111] export: oer-s111-pim: requests 12; assignment reads 1; eligibility reads 1
[oer-s111] export: oer-s111-both: requests 12; assignment reads 1; eligibility reads 1
[oer-s111] export: oer-s111-nopim: requests 2; assignment reads 0; eligibility reads 1
[oer-s111] export: oer-s111-plain: requests 2; assignment reads 0; eligibility reads 1
[oer-s111] inventory: oer-s111-both: members [oer-s111-user2]; owners [(no key)]; eligibility [oer-s111-user2/member]
[oer-s111] inventory: oer-s111-pim: members [oer-s111-user1]; owners [oer-s111-user1]; eligibility [oer-s111-user2/member]
[oer-s111] README section found: True
[oer-s111] README: ## Members and owners left out as PIM for Groups access
[oer-s111] README: standing, such as a time-bound one -- is left out, since applying it would make access that PIM for
[oer-s111] README: for the same access was left out, and the group is listed under "What this export could not read";
[oer-s111] README: as `null`, `owners` left out -- unless they were read empty. A member or owner left out is still a
[oer-s111] README: None. This export left no member or owner out as PIM for Groups access.
[oer-s111] README: - `inventory.json` -- the canonical, round-trippable inventory, in the exact apply-document shape,
[oer-s111] README: - `groups.json`, `administrativeUnits.json`, `catalogs.json`, `accessPackages.json`,
[oer-s111] roster: oer-s111-pim: memberCount 1
[oer-s111] roster: oer-s111-both: memberCount 1
[oer-s111] roster: oer-s111-nopim: memberCount null
[oer-s111] roster: oer-s111-plain: memberCount null
RUNNER: check 2.1 exit code 0; started 2026-10-13T11:57:31Z; took 18 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.2. -AllGroupsDetailed: every step group read in full, one assignment read each with members

- [x] **2.2** The same export with `-AllGroupsDetailed` writes all four step groups; `oer-s111-nopim` carries its standing member and owner; the group with no member and no owner costs no assignment read.

```powershell
Connect-OerLive -Arm
Start-S111Fence
Reset-S111Requests
$Out = Export-OERInventory -OutputPath (Join-Path $Raw 'bundle-all') -Include Groups -GroupFilter "startswith(displayName,'oer-s111-')" -AllGroupsDetailed -Force -ErrorAction Continue -ErrorVariable ExErr -WarningVariable ExWarn
Write-OerLiveStep "bundle: groups $($Out.Groups); IncompleteReads $(@($Out.IncompleteReads).Count); warnings $(@($ExWarn).Count); own errors $(@($ExErr | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',Export-OERInventory') }).Count)"
Write-S111Requests -Label 'export'
$Inv = Get-Content -LiteralPath (Join-Path $Out.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
foreach ($E in @($Inv.groups | Sort-Object displayName)) {
    $Members = if ($null -eq $E.members) { 'null' } else { (@($E.members | ForEach-Object { Get-S111Who ([string]$_) }) | Sort-Object) -join ', ' }
    $Owners = if ($E.PSObject.Properties.Name -contains 'owners') { (@($E.owners | ForEach-Object { Get-S111Who ([string]$_) }) | Sort-Object) -join ', ' } else { '(no key)' }
    Write-OerLiveStep "inventory: $($E.displayName): members [$Members]; owners [$Owners]"
}
Disconnect-OerLive
```

**Expect:** `groups 4`, `IncompleteReads 0`, no own error; `oer-s111-nopim: members [oer-s111-user1];
owners [oer-s111-user1]`, `oer-s111-plain: members []; owners [(no key)]` (or `members
[oer-s111-user1]` once section 5 has run), the two others as in 2.1; `writes 0`; `assignment reads
1` for `oer-s111-pim`, `oer-s111-both` and `oer-s111-nopim`, and `0` for `oer-s111-plain` while it is
empty.
**Failure looks like:** any assignment read for the empty group, more than one for a group, or a
standing member missing.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With -AllGroupsDetailed all four step groups are written; oer-s111-nopim carries its standing member and owner; one assignment read for each group with members or owners, and none for the empty oer-s111-plain; IncompleteReads 0, no write.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] bundle: groups 4; IncompleteReads 0; warnings 0; own errors 0
[oer-s111] export: requests 40; writes 0; token requests 0
[oer-s111] export: oer-s111-pim: requests 12; assignment reads 1; eligibility reads 1
[oer-s111] export: oer-s111-both: requests 12; assignment reads 1; eligibility reads 1
[oer-s111] export: oer-s111-nopim: requests 7; assignment reads 1; eligibility reads 1
[oer-s111] export: oer-s111-plain: requests 6; assignment reads 0; eligibility reads 1
[oer-s111] inventory: oer-s111-both: members [oer-s111-user2]; owners [(no key)]
[oer-s111] inventory: oer-s111-nopim: members [oer-s111-user1]; owners [oer-s111-user1]
[oer-s111] inventory: oer-s111-pim: members [oer-s111-user1]; owners [oer-s111-user1]
[oer-s111] inventory: oer-s111-plain: members []; owners [(no key)]
RUNNER: check 2.2 exit code 0; started 2026-10-13T11:57:51Z; took 19 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. An eligible principal declared as a member is not added (B)

### 3.1. The plan

- [x] **3.1** A document declaring `oer-s111-user1` and `oer-s111-user2` as the members of `oer-s111-pim` (user2 is eligible, not a member): `Invoke-OERStructure -WhatIf` plans user1 `Unchanged`, user2 `Skipped` with the reason, one warning, and no write.

```powershell
Connect-OerLive -Arm
Start-S111Fence
$Doc = Save-S111Document -Name 'doc-eligible-declared' -Groups @([ordered]@{ displayName = 'oer-s111-pim'; members = @($Upn['oer-s111-user1'], $Upn['oer-s111-user2']) })
Invoke-S111Apply -Path $Doc -Plan
Write-OerLiveStep "members of oer-s111-pim: $((Get-S111Relation -Group 'oer-s111-pim' -Relation members) -join ', ')"
Disconnect-OerLive
```

**Expect:** rows `groups | oer-s111-pim | Unchanged | group properties match`, `... | Unchanged |
member 'oer-s111-user1' already present`, and `... | Skipped | member 'oer-s111-user2' not added: it
is eligible for member access in PIM for Groups, and the apply engine never adds a standing
membership for a principal PIM for Groups holds or makes eligible for the same access (our own guard,
not a Graph rejection)`; `warnings: 1`, naming `oer-s111-user2` and the group; no `What if:` line for
an add; `writes 0`; members of `oer-s111-pim`: `oer-s111-user1`.
**Failure looks like:** a `would add member` row for user2, no warning, or any write.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan for a document declaring oer-s111-user1 and the eligible non-member oer-s111-user2 as members of oer-s111-pim: user1 Unchanged, user2 Skipped with the reason, one warning naming user2 and the group, no What if line (no add was planned), no write; one assignment read and one eligibility read; members unchanged (user1).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] document doc-eligible-declared: {"version":"1.0","groups":[{"displayName":"oer-s111-pim","members":["oer-s111-user1","oer-s111-user2"]}]}
[oer-s111] row: groups | oer-s111-pim | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-pim | Unchanged | member 'oer-s111-user1' already present
[oer-s111] row: groups | oer-s111-pim | Skipped | member 'oer-s111-user2' not added: it is eligible for member access in PIM for Groups, and the apply engine never adds a standing membership for a principal PIM for Groups holds or makes eligible for the same access (our own guard, not a Graph rejection)
[oer-s111] warnings: 1
[oer-s111] warning: Sync-OERStructureGroup: member 'oer-s111-user2' is not added to group 'oer-s111-pim' as a standing member: it is eligible for member access in PIM for Groups, and the apply engine never turns that into a standing membership. Add it with Add-OERGroupMember if a standing membership is meant.
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] plan: requests 8; writes 0; token requests 0
[oer-s111] plan: oer-s111-pim: requests 5; assignment reads 1; eligibility reads 1
[oer-s111] plan: oer-s111-both: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] plan: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] plan: oer-s111-plain: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] members of oer-s111-pim: oer-s111-user1
RUNNER: check 3.1 exit code 0; started 2026-10-13T11:58:21Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. The real run: nothing added, the members unchanged

- [x] **3.2** The same document in a real run (`-Confirm:$false`) gives the same rows and warning, writes nothing, and the group's members are unchanged afterwards.

```powershell
Connect-OerLive -Arm
Start-S111Fence
$Doc = Save-S111Document -Name 'doc-eligible-declared' -Groups @([ordered]@{ displayName = 'oer-s111-pim'; members = @($Upn['oer-s111-user1'], $Upn['oer-s111-user2']) })
Invoke-S111Apply -Path $Doc
Write-OerLiveStep "members of oer-s111-pim: $((Get-S111Relation -Group 'oer-s111-pim' -Relation members) -join ', ')"
Disconnect-OerLive
```

**Expect:** the three rows of 3.1, `warnings: 1`, `writes 0`, no own error; members of
`oer-s111-pim`: `oer-s111-user1` only.
**Failure looks like:** user2 added (a POST to the group's `members/$ref`), or any other write.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The real run gives the same three rows and the same warning, writes nothing, raises no own error, and the group's members are unchanged afterwards (oer-s111-user1 only).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] document doc-eligible-declared: {"version":"1.0","groups":[{"displayName":"oer-s111-pim","members":["oer-s111-user1","oer-s111-user2"]}]}
[oer-s111] row: groups | oer-s111-pim | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-pim | Unchanged | member 'oer-s111-user1' already present
[oer-s111] row: groups | oer-s111-pim | Skipped | member 'oer-s111-user2' not added: it is eligible for member access in PIM for Groups, and the apply engine never adds a standing membership for a principal PIM for Groups holds or makes eligible for the same access (our own guard, not a Graph rejection)
[oer-s111] warnings: 1
[oer-s111] warning: Sync-OERStructureGroup: member 'oer-s111-user2' is not added to group 'oer-s111-pim' as a standing member: it is eligible for member access in PIM for Groups, and the apply engine never turns that into a standing membership. Add it with Add-OERGroupMember if a standing membership is meant.
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] run: requests 8; writes 0; token requests 0
[oer-s111] run: oer-s111-pim: requests 5; assignment reads 1; eligibility reads 1
[oer-s111] run: oer-s111-both: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-plain: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] members of oer-s111-pim: oer-s111-user1
RUNNER: check 3.2 exit code 0; started 2026-10-13T11:58:30Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 4. A member who is also eligible is withheld from the prune (B)

### 4.1. The plan with -Prune

- [x] **4.1** A document declaring `oer-s111-both` with no members (`members: []`; `oer-s111-user2` is its member and eligible): `Invoke-OERStructure -Prune -WhatIf` withholds the prune of user2 and writes nothing.

```powershell
Connect-OerLive -Arm
Start-S111Fence
$Doc = Save-S111Document -Name 'doc-prune-eligible' -Groups @([ordered]@{ displayName = 'oer-s111-both'; members = @() })
Invoke-S111Apply -Path $Doc -Prune -Plan
Write-OerLiveStep "members of oer-s111-both: $((Get-S111Relation -Group 'oer-s111-both' -Relation members) -join ', ')"
Disconnect-OerLive
```

**Expect:** rows `groups | oer-s111-both | Unchanged | group properties match` and `... | Skipped |
prune withheld: undeclared member 'oer-s111-user2' is eligible for member access in PIM for Groups,
and -Prune never removes a member or owner whose access PIM for Groups holds or makes eligible; it is
left in place (our own guard, not a Graph rejection). Manage that access in PIM for Groups if it is
meant to go.`; `warnings: 0` (no "would remove" warning); `writes 0`; members `oer-s111-user2`.
**Failure looks like:** a `would remove undeclared member` row or warning, or any write.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With -Prune -WhatIf and members [] for oer-s111-both, the member who is also eligible is withheld ("prune withheld: ... is eligible for member access in PIM for Groups ..."), no "would remove" warning, no What if line, no write; the member stays.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.1 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] document doc-prune-eligible: {"version":"1.0","groups":[{"displayName":"oer-s111-both","members":[]}]}
[oer-s111] row: groups | oer-s111-both | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-both | Skipped | prune withheld: undeclared member 'oer-s111-user2' is eligible for member access in PIM for Groups, and -Prune never removes a member or owner whose access PIM for Groups holds or makes eligible; it is left in place (our own guard, not a Graph rejection). Manage that access in PIM for Groups if it is meant to go.
[oer-s111] warnings: 0
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] plan: requests 6; writes 0; token requests 0
[oer-s111] plan: oer-s111-pim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] plan: oer-s111-both: requests 5; assignment reads 1; eligibility reads 1
[oer-s111] plan: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] plan: oer-s111-plain: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] members of oer-s111-both: oer-s111-user2
RUNNER: check 4.1 exit code 0; started 2026-10-13T11:58:40Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 4.2. The real -Prune: the member stays

- [x] **4.2** The same document in a real `-Prune` run gives the same rows, writes nothing, and `oer-s111-user2` is still the member afterwards.

```powershell
Connect-OerLive -Arm
Start-S111Fence
$Doc = Save-S111Document -Name 'doc-prune-eligible' -Groups @([ordered]@{ displayName = 'oer-s111-both'; members = @() })
Invoke-S111Apply -Path $Doc -Prune
Write-OerLiveStep "members of oer-s111-both: $((Get-S111Relation -Group 'oer-s111-both' -Relation members) -join ', ')"
Disconnect-OerLive
```

**Expect:** the two rows of 4.1, `warnings: 0`, `writes 0`, no own error; members `oer-s111-user2`.
**Failure looks like:** a DELETE of the group's `members/<id>/$ref`, or user2 gone.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The real -Prune run gives the same rows, writes nothing, and oer-s111-user2 is still the member afterwards.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.2 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] document doc-prune-eligible: {"version":"1.0","groups":[{"displayName":"oer-s111-both","members":[]}]}
[oer-s111] row: groups | oer-s111-both | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-both | Skipped | prune withheld: undeclared member 'oer-s111-user2' is eligible for member access in PIM for Groups, and -Prune never removes a member or owner whose access PIM for Groups holds or makes eligible; it is left in place (our own guard, not a Graph rejection). Manage that access in PIM for Groups if it is meant to go.
[oer-s111] warnings: 0
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] run: requests 6; writes 0; token requests 0
[oer-s111] run: oer-s111-pim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-both: requests 5; assignment reads 1; eligibility reads 1
[oer-s111] run: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-plain: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] members of oer-s111-both: oer-s111-user2
RUNNER: check 4.2 exit code 0; started 2026-10-13T11:58:50Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 5. A plain member is added as before, and the document converges (B, G8)

### 5.1. The plan

- [x] **5.1** A document declaring `oer-s111-user1` as the member of the empty `oer-s111-plain`: the plan reads the group's PIM state once (one assignment read, one eligibility read) and plans the add as before.

```powershell
Connect-OerLive -Arm
Start-S111Fence
$Doc = Save-S111Document -Name 'doc-plain-add' -Groups @([ordered]@{ displayName = 'oer-s111-plain'; members = @($Upn['oer-s111-user1']) })
Invoke-S111Apply -Path $Doc -Plan
Write-OerLiveStep "members of oer-s111-plain: $((Get-S111Relation -Group 'oer-s111-plain' -Relation members) -join ', ')"
Disconnect-OerLive
```

**Expect:** rows `... | Unchanged | group properties match` and `... | Skipped | would add member
'oer-s111-user1'`; `warnings: 0`; `writes 0`; for `oer-s111-plain` `assignment reads 1; eligibility
reads 1`; members: none.
**Failure looks like:** the add refused (the hold state of a group never onboarded read as held or
unread), a warning, or a write.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan for oer-s111-user1 as the member of the empty oer-s111-plain reads the group's PIM state once (one assignment read, one eligibility read: a group never onboarded holds nobody) and plans the add as before (Skipped "would add member", one What if line), no warning, no write.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.1 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] document doc-plain-add: {"version":"1.0","groups":[{"displayName":"oer-s111-plain","members":["oer-s111-user1"]}]}
What if: Performing the operation "Add member '00000000-0000-0000-0000-000000000001'" on target "oer-s111-plain".
[oer-s111] row: groups | oer-s111-plain | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-plain | Skipped | would add member 'oer-s111-user1'
[oer-s111] warnings: 0
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] plan: requests 7; writes 0; token requests 0
[oer-s111] plan: oer-s111-pim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] plan: oer-s111-both: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] plan: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] plan: oer-s111-plain: requests 5; assignment reads 1; eligibility reads 1
[oer-s111] members of oer-s111-plain:
RUNNER: check 5.1 exit code 0; started 2026-10-13T11:59:16Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 5.2. The real run adds the member

- [x] **5.2** The same document in a real run adds `oer-s111-user1` (one POST to the group's `members/$ref`), and the member is listed afterwards.

```powershell
Connect-OerLive -Arm
Start-S111Fence
$Doc = Save-S111Document -Name 'doc-plain-add' -Groups @([ordered]@{ displayName = 'oer-s111-plain'; members = @($Upn['oer-s111-user1']) })
Invoke-S111Apply -Path $Doc
$null = Wait-OerLiveConverged -Activity 'oer-s111-user1 is listed in the members of oer-s111-plain' -Read { , @(Get-S111Relation -Group 'oer-s111-plain' -Relation members) } -Test { @($args[0]) -contains 'oer-s111-user1' }
Write-OerLiveStep "members of oer-s111-plain: $((Get-S111Relation -Group 'oer-s111-plain' -Relation members) -join ', ')"
Disconnect-OerLive
```

**Expect:** rows `... | Unchanged | group properties match` and `... | Updated | added member
'oer-s111-user1'`; `warnings: 0`; `writes 1`, `write: POST v1.0/groups/oer-s111-plain/members/$ref`;
no own error; members `oer-s111-user1` after convergence.
**Failure looks like:** no add, a Failed row, or a write other than the one POST.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The real run adds oer-s111-user1 with one POST to the group's members/$ref (Updated "added member"), no warning, no own error; the member was listed after 3 reads (6.3 s). The members line printed right after that convergence came back empty: a read served by a lagging replica, the effect earlier steps measured; 5.3's three steady reads 25 s later show the member.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.2 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] document doc-plain-add: {"version":"1.0","groups":[{"displayName":"oer-s111-plain","members":["oer-s111-user1"]}]}
[oer-s111] row: groups | oer-s111-plain | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-plain | Updated | added member 'oer-s111-user1'
[oer-s111] warnings: 0
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] run: requests 8; writes 1; token requests 0
[oer-s111] run: write: POST v1.0/groups/oer-s111-plain/members/$ref
[oer-s111] run: oer-s111-pim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-both: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-plain: requests 6; assignment reads 1; eligibility reads 1
[oer-s111] oer-s111-user1 is listed in the members of oer-s111-plain: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s111] oer-s111-user1 is listed in the members of oer-s111-plain: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s111] oer-s111-user1 is listed in the members of oer-s111-plain: converged after 3 read(s), 6.3 s.
[oer-s111] members of oer-s111-plain:
RUNNER: check 5.2 exit code 0; started 2026-10-13T11:59:25Z; took 13 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 5.3. The same document twice more: Unchanged, no write, no PIM read (G8)

- [x] **5.3** After a settle of 30 s and three steady reads of the members, the same document run twice more gives only `Unchanged`, writes nothing, and reads no PIM state (nothing to decide).

```powershell
Connect-OerLive -Arm
Start-S111Fence
$null = Wait-OerLiveConverged -Activity 'three steady reads of the members of oer-s111-plain' -Read { Start-Sleep -Seconds 10; , @(@(1..3) | ForEach-Object { Start-Sleep -Seconds 5; (Get-S111Relation -Group 'oer-s111-plain' -Relation members) -join ',' }) } -Test { @($args[0] | Select-Object -Unique).Count -eq 1 -and @($args[0])[0] -eq 'oer-s111-user1' }
$Doc = Save-S111Document -Name 'doc-plain-add' -Groups @([ordered]@{ displayName = 'oer-s111-plain'; members = @($Upn['oer-s111-user1']) })
foreach ($Pass in 1, 2) { Write-OerLiveStep "pass $Pass"; Invoke-S111Apply -Path $Doc }
Disconnect-OerLive
```

**Expect:** in both passes rows `... | Unchanged | group properties match` and `... | Unchanged |
member 'oer-s111-user1' already present` only; `warnings: 0`; `writes 0`; `assignment reads 0;
eligibility reads 0` for `oer-s111-plain`.
**Failure looks like:** any row other than `Unchanged`, a write, or a PIM read for a converged item.

Result: 2026-10-13 12:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). After three steady reads of the members (oer-s111-user1), the same document run twice more gives only Unchanged ("group properties match", "member ... already present"), no warning, no write, and no PIM read at all for the converged item (assignment reads 0, eligibility reads 0).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.3 ===
[oer-s111] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg1\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s111] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s111] fences in place (Get-AzToken is the proxy, the Graph wrapper records): True
[oer-s111] three steady reads of the members of oer-s111-plain: converged after 1 read(s), 25.3 s.
[oer-s111] document doc-plain-add: {"version":"1.0","groups":[{"displayName":"oer-s111-plain","members":["oer-s111-user1"]}]}
[oer-s111] pass 1
[oer-s111] row: groups | oer-s111-plain | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-plain | Unchanged | member 'oer-s111-user1' already present
[oer-s111] warnings: 0
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] run: requests 5; writes 0; token requests 0
[oer-s111] run: oer-s111-pim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-both: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-plain: requests 3; assignment reads 0; eligibility reads 0
[oer-s111] pass 2
[oer-s111] row: groups | oer-s111-plain | Unchanged | group properties match
[oer-s111] row: groups | oer-s111-plain | Unchanged | member 'oer-s111-user1' already present
[oer-s111] warnings: 0
[oer-s111] Invoke-OERStructure own errors: 0
[oer-s111] run: requests 5; writes 0; token requests 0
[oer-s111] run: oer-s111-pim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-both: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-nopim: requests 0; assignment reads 0; eligibility reads 0
[oer-s111] run: oer-s111-plain: requests 3; assignment reads 0; eligibility reads 0
RUNNER: check 5.3 exit code 0; started 2026-10-13T11:59:40Z; took 31 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## B. Proved offline (class B)

Each item names the unit tests that prove it; their names are in the step's report. None can be
produced live here, for the reason given.

- **B.1 The reserve and the partial signal.** A failed assignment read leaves out a member or owner
  that is eligible for the same access, names `groups/<name>/pimAssignments` in `IncompleteReads`
  and the `InventoryPartial` message, and, when the eligibility was not read either, writes
  `members: null` and omits `owners`. No identity here reads the groups but not their PIM
  assignments: `oer-live-cc-noperm` reads neither, and `oer-live-cc` read them (1.1, 0.2). Tests: the
  `a PIM activation is never a standing membership (BL-125, A3)` context of
  `tests/Unit/Private/Get-OERInventoryGroup.Tests.ps1` and the export tests in
  `tests/Unit/Public/Export-OERInventory.Tests.ps1`. Recorded answer: 1.1.
- **B.2 An activation and a time-bound active assignment are left out of the export, and the README
  counts them.** No activation is possible for an app, and `oer-live-cc` holds no PIM-for-Groups
  assignment write scope. Tests: the same context, and `tests/Unit/Private/Get-OERGroupPimHeldAccess.Tests.ps1`
  for the rule (Microsoft Learn's documented values `activated`, `assigned` with an `endDateTime`).
- **B.3 The engine with an unread hold state, a held owner, and a currently activated principal in an
  old document.** Tests: the `a PIM activation is never a standing membership (BL-125, A3)` context of
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1`, including the runs in a runspace with no
  `try` above them.
- **B.4 `ResourceTypeNotSupported` on the assignment read** (a group PIM for Groups cannot manage): not
  measured for this endpoint -- a group never onboarded answered 200 (1.1). Test:
  `tests/Unit/Private/Read-OERGroupPimAssignment.Tests.ps1`.

## C. Manual (class C), after the merge

- **C.1 A real activation (Philip, P-15).** In an environment of his own: activate an eligible
  membership, export with `Export-OERInventory`, and see that the activated principal is not under
  the group's `members` in `inventory.json`, and that the README section "Members and owners left out
  as PIM for Groups access" counts it for that group. Not blocking.

## Teardown

### T.1. The objects removed, nothing left

- [ ] **T.1** `Initialize-OerS111Prereq.ps1 -Teardown -Unattended` removes the eligibilities and assignments, the four groups and the two users; the sweep finds nothing with the prefix and no unread collection; the counts equal the baseline.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS111Prereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -Teardown -Unattended 2>&1 | ForEach-Object { "$_" }
Write-OerLiveStep "teardown exit code: $LASTEXITCODE"
```

**Expect:** every object removed, exit code 0, the counts equal the baseline; at most residue rows
that the next read-back clears (a user DELETE refused for minutes is residue, exit code 3).
**Failure looks like:** an object left without a residue row, an unread collection, or a stop.

Result:

### T.2. Read-back once the listings have settled

- [ ] **T.2** At least a minute after T.1, the sweep lists nothing with the prefix and no unread collection, and the tenant lists as many users and groups as the baseline recorded; `raw\s111\` is deleted after the results are written.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS111Prereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -ReadBack 2>&1 | ForEach-Object { "$_" }
Write-OerLiveStep "read-back exit code: $LASTEXITCODE"
```

**Expect:** 0 objects, 0 unread collections; users and groups equal to the baseline counts; 0
residue rows of this prefix.
**Failure looks like:** a step object still listed after several minutes (read back again later
before treating it as residue).

Result:
