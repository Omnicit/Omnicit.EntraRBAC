# Live verification checklist -- rename administrative units, catalogs and access packages in place (feat/rename-more-object-kinds)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.** A
box with no result line filled in is not a passed check -- it is an unrun one. If a check turns out to be
impossible to run, write "cannot be verified, and therefore we do not know" on its result line and say
why; do not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** This step has no manual
check (class C).

**What this file writes to the tenant: only inside the prefix `oer-s114-`.** The prerequisite script
`Initialize-OerS114Prereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates two security groups with no member, `oer-s114-member` and `oer-s114-resgrp`; a role-assignable
group with no member and no owner, `oer-s114-rolegrp`; an administrative unit `oer-s114-au` whose member is
`oer-s114-member` and whose one scoped role is held by `oer-s114-rolegrp` (so nobody holds the role); a
catalog `oer-s114-cat-a` whose one resource is `oer-s114-resgrp`, with a hidden access package
`oer-s114-ap-a` in it whose one resource role is the Member role of `oer-s114-resgrp` and whose one
assignment policy `oer-s114-pol-a` only an administrator assigns through; and a catalog `oer-s114-cat-b`
with a hidden access package `oer-s114-ap-b` and nothing else. Section 1 renames the unit, catalog A and
both packages through `Invoke-OERStructure` -- to the same names with `-new` appended -- and changes
nothing else. Sections 2 and 3 must write nothing. Nobody is assigned anything. The teardown (T.1) deletes
the unit, then the packages, the policy, the catalogs and the groups. Documents, the ids read before the
rename and request counts are written under `raw\s114\`, which is deleted after the results are written.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401
or 403 as `oer-live-cc` is a stop.

**Permissions.** The objects need the Microsoft Graph application permissions
`AdministrativeUnit.ReadWrite.All`, `EntitlementManagement.ReadWrite.All` and `Group.ReadWrite.All`, and
the role-assignable group and the scoped role need `RoleManagement.ReadWrite.Directory`; check 0.2 reads
them and STOPS the run before anything is written when one of the first three is missing, and the
prerequisite script refuses its setup the same way (the scoped role alone becomes class B). Granting a
permission is the operator's decision, never this checklist's.

**The scoped role.** Neither of the low-risk directory roles this programme uses for live checks
(Reports Reader, Message Center Reader) can be scoped to an administrative unit (Microsoft Learn, "Roles
that can be assigned with administrative unit scope"). The prerequisite script therefore picks the first
ALREADY ACTIVATED role of a fixed list -- Attribute Assignment Reader, License Administrator, Groups
Administrator, Helpdesk Administrator, User Administrator -- and gives it, scoped to the unit, to
`oer-s114-rolegrp`, a role-assignable group with no member and no owner: nobody holds the role. It never
activates a role.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block installs
the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s114/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line, a warning and an error that
stops a script go straight to the host, so each block is run in its own process whose WHOLE output
(standard output and standard error) is written to a file under `raw\s114\`, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. One rename decision for three more kinds, and the validator** ("feat: add the shared rename
  decision for structure entries", "feat: accept previousDisplayName on administrative units, catalogs
  and access packages in the validator and schema"). `Resolve-OERStructureRename` decides what an entry
  with `previousDisplayName` means once both names are looked up: two different objects ->
  `<Kind>RenameConflict`; neither -> `<Kind>RenameNotFound`, nothing created; only the previous name -> the
  object is renamed; otherwise the entry is applied as before. `Test-OERStructure` accepts the key on
  `administrativeUnits`, `catalogs` and `accessPackages` (a non-empty string; a case-only rename is a
  Warning; the previous name counts in the duplicate check, for a package within its catalog), keeps step
  3's Error for assignment policies and access reviews, and warns on a reference to an old name.
- **B. The three handlers rename in place** ("feat: rename administrative units through
  previousDisplayName", "fix: keep a group created into a renamed unit by its previous name", "feat:
  rename catalogs through previousDisplayName", "feat: rename access packages through
  previousDisplayName", "docs: say exactly when a package in a planned catalog fails its rename"). Both
  names are looked up before anything is read or written for the entry; the rename travels in the same
  `Set-OER<Kind>` call as the entry's other changes; an object id as the previous name is looked up by id
  (a package only within its declared catalog).
- **C. References in the same run** ("feat: create a group into a unit the same run renames, through one
  rename map per document", "fix: refuse a reference whose rename the run cannot decide", "fix: refuse a
  reference when a lookup of either name fails"). One rename map per document: a group created into a
  unit, or a package in a catalog, that the same document renames reaches it by its object id, and is
  refused when that rename was refused or could not be decided in the run (its section not selected by
  `-Include`, or a lookup of one of its names failed). The `-EnsureOnly` pre-pass never creates a unit for
  an entry that declares a rename.
- **D. The texts** ("feat: teach the inventory prompt that units, catalogs and access packages rename in
  place", "docs: describe renaming of units, catalogs and access packages in the help, README, about topic
  and rationale", "docs: add the release note for renaming units, catalogs and access packages", "docs:
  describe renaming in the Invoke-OERStructure help and tie the texts to the committed rename map", "docs:
  correct the rename texts after the refusal of undecided renames and the task review", "docs: say that a
  failed lookup of either name refuses the references of a rename").

A live tenant is needed because the claim is about what the engine does against Microsoft Graph: that
the object found under its previous name is renamed IN PLACE (same object id) and keeps its members, its
scoped role, its resources, its resource role and its policy; that no second object is created; that the
same document applied again converges; and that a conflict or a name nothing carries writes nothing.

## What this file does not check, and why

- **A group created in the same run into an administrative unit the same document renames (class B).**
  The pre-pass finds the unit under its previous name and the group is created into it by id; the unit
  tests named in section B hold it. Creating a group into the unit here would add a second write path the
  step's claim does not need.
- **An ambiguous previous name, a failed rename and Microsoft Graph's lag after a rename (class B).**
  Neither can be produced on demand with the prefix alone; the unit tests hold the refusals, among them
  the rule that a reference to the new name of a unit or catalog whose previous-name lookup threw is
  refused.
- **An access review naming a package by its new name in the run that renames it (class B, Ruling R3).**
  Not translated in this step; the validator warns on a reference to the old name (unit tests).
- **The texts (class B).** Section B names the gates that hold them.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, holding the permissions above
  (0.2 reads them).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 reads that it was not).
- The **prerequisite objects**: check 0.3 runs `Initialize-OerS114Prereq.ps1 -WhatIf`, then
  `-Unattended` twice, with `OER_LIVE_REPO` set.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the
counters, the readers and the documents. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s114-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Au = 'oer-s114-au'; $AuNew = 'oer-s114-au-new'
$CatA = 'oer-s114-cat-a'; $CatANew = 'oer-s114-cat-a-new'; $CatB = 'oer-s114-cat-b'
$ApA = 'oer-s114-ap-a'; $ApANew = 'oer-s114-ap-a-new'; $ApB = 'oer-s114-ap-b'; $ApBNew = 'oer-s114-ap-b-new'
$Member = 'oer-s114-member'; $ResGroup = 'oer-s114-resgrp'; $RoleGroup = 'oer-s114-rolegrp'; $Policy = 'oer-s114-pol-a'
# The register's deliberately non-existent object id (docs/live-verification/README.md).
$NoSuchId = '00000000-0000-0000-0000-000000000099'
# The step's raw folder as OerLive fixed it (git-ignored).
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Needed = @('AdministrativeUnit.ReadWrite.All', 'EntitlementManagement.ReadWrite.All', 'Group.ReadWrite.All', 'RoleManagement.ReadWrite.Directory')

function Start-S114NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S114TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S114TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S114 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S114Count {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is
    # a GET. The Graph path of every request is recorded too (method and path, query dropped).
    $global:S114Graph = [System.Collections.Generic.List[string]]::new()
    $global:S114Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(try { ([uri][string]$Uri).AbsolutePath } catch { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S114Graph.Add((`$($Record)) + ' ' + $Path); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S114Arm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S114Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S114Sent {
    # Requests counted since Start-S114Count: totals and writes (any method but GET), with the write paths.
    $GraphWrites = @($global:S114Graph | Where-Object { -not $_.StartsWith('GET ') })
    $ArmWrites = @($global:S114Arm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S114TokenCalls; Microsoft Graph requests: $($global:S114Graph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S114Arm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" })"
}

function Get-S114GrantedRole {
    # The Microsoft Graph application permissions granted to oer-live-cc, by name. Ids are read and
    # compared here, never printed.
    $Sp = Invoke-OerLiveGraph -All -Uri ("v1.0/servicePrincipals?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("appId eq '$($Cfg.AppId)'"))
    Assert-OerLiveOk -Response $Sp -Activity "Reading oer-live-cc's service principal" | Out-Null
    $Rows = @(@($Sp.Body['value']) | Where-Object { $null -ne $_ })
    if ($Rows.Count -ne 1) { throw "STOP: the identity's app id matches $($Rows.Count) service principals, not one." }
    $A = Invoke-OerLiveGraph -All -Uri "v1.0/servicePrincipals/$([string]$Rows[0]['id'])/appRoleAssignments"
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
    , @($Names)
}

function Get-S114List {
    # A collection read raw and whole, unwrapped (the caller wraps the result in @()).
    param([Parameter(Mandatory)][string]$Uri)
    $R = Invoke-OerLiveGraph -All -Uri $Uri
    Assert-OerLiveOk -Response $R -Activity 'Reading a collection' | Out-Null
    @($R.Body['value']) | Where-Object { $null -ne $_ }
}

function Get-S114Id {
    # The ids of every object of a kind whose display name is exactly the name, read raw (never printed).
    param([Parameter(Mandatory)][ValidateSet('unit', 'catalog', 'package', 'group')][string]$Kind, [Parameter(Mandatory)][string]$Name)
    $Uri = switch ($Kind) {
        'unit' { 'v1.0/directory/administrativeUnits?$select=id,displayName' }
        'catalog' { "$Em/catalogs?`$select=id,displayName" }
        'package' { "$Em/accessPackages?`$select=id,displayName" }
        'group' { "v1.0/groups?`$filter=$([uri]::EscapeDataString("displayName eq '$Name'"))&`$select=id,displayName" }
    }
    # Unwrapped: every caller wraps the result in @() (a returned , @() would nest, and an empty result
    # would then count as one).
    @(Get-S114List -Uri $Uri) | Where-Object { [string]$_['displayName'] -ceq $Name } | ForEach-Object { ([string]$_['id']).ToLowerInvariant() }
}

function Get-S114Snapshot {
    # The step's objects read by id: their names and what they hold (ids, never printed), and every
    # prefixed object id the sweep lists. Takes the ids recorded in raw\s114\before.json.
    param([Parameter(Mandatory)][hashtable]$Ids)
    $S = [ordered]@{}
    $S.UnitName = [string](Invoke-OerLiveGraph -Uri "v1.0/directory/administrativeUnits/$($Ids.Unit)?`$select=displayName").Body['displayName']
    $S.UnitMembers = @(@(Get-S114List -Uri "v1.0/directory/administrativeUnits/$($Ids.Unit)/members?`$select=id") | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } | Sort-Object)
    $S.UnitScopedRoles = @(@(Get-S114List -Uri "v1.0/directory/administrativeUnits/$($Ids.Unit)/scopedRoleMembers") | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } | Sort-Object)
    $S.CatAName = [string](Invoke-OerLiveGraph -Uri "$Em/catalogs/$($Ids.CatA)").Body['displayName']
    $S.CatAResources = @(@(Get-S114List -Uri "$Em/catalogs/$($Ids.CatA)/resources") | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } | Sort-Object)
    $S.CatBName = [string](Invoke-OerLiveGraph -Uri "$Em/catalogs/$($Ids.CatB)").Body['displayName']
    $S.ApAName = [string](Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids.ApA)?`$select=displayName").Body['displayName']
    $S.ApABindings = @(@(Get-S114List -Uri "$Em/accessPackages/$($Ids.ApA)/resourceRoleScopes") | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } | Sort-Object)
    $S.ApAPolicies = @(@(Get-S114List -Uri ("$Em/assignmentPolicies?`$filter={0}" -f [uri]::EscapeDataString("accessPackage/id eq '$($Ids.ApA)'"))) | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } | Sort-Object)
    $S.ApBName = [string](Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids.ApB)?`$select=displayName").Body['displayName']
    $S.Prefixed = @(@(Find-OerLivePrefixed -ThrowOnUnread -Quiet) | ForEach-Object { "$($_.Kind)|$($_.Id)" } | Sort-Object)
    $S
}

function Get-S114ScopedRoleName {
    # The display name of the unit's one scoped role (the prerequisite script picked it), or $null.
    param([Parameter(Mandatory)][string]$UnitId)
    $Sr = @(Get-S114List -Uri "v1.0/directory/administrativeUnits/$UnitId/scopedRoleMembers")
    if ($Sr.Count -ne 1) { return $null }
    $Role = @(@(Get-S114List -Uri 'v1.0/directoryRoles?$select=id,displayName') | Where-Object { [string]$_['id'] -eq [string]$Sr[0]['roleId'] })
    if ($Role.Count -eq 1) { [string]$Role[0]['displayName'] } else { $null }
}

function New-S114Document {
    # A structure document (JSON) holding the given sections.
    param([hashtable]$Section)
    $Doc = [ordered]@{ version = '1.0' }
    foreach ($K in @($Section.Keys | Sort-Object)) { $Doc[$K] = @($Section[$K]) }
    $Doc | ConvertTo-Json -Depth 20
}

function New-S114RenameDocument {
    # The document of section 1: the unit, catalog A and both packages renamed in place, every collection
    # declared as it is live. Package B is named by its object id (read raw, never printed), the other
    # three by their previous names. The unit's scoped role is declared by the name the live role carries.
    param([Parameter(Mandatory)][hashtable]$Ids)
    $RoleName = Get-S114ScopedRoleName -UnitId $Ids.Unit
    $Scoped = @(if ($RoleName) { [ordered]@{ role = $RoleName; principal = $RoleGroup } })
    New-S114Document -Section @{
        administrativeUnits = @([ordered]@{ displayName = $AuNew; previousDisplayName = $Au; members = @($Member); scopedRoles = $Scoped })
        catalogs            = @(
            [ordered]@{ displayName = $CatANew; previousDisplayName = $CatA; resources = @([ordered]@{ name = $ResGroup; type = 'Group' }) }
            [ordered]@{ displayName = $CatB; resources = @() }
        )
        accessPackages      = @(
            [ordered]@{ displayName = $ApANew; previousDisplayName = $ApA; catalog = $CatANew; resourceRoles = @([ordered]@{ resource = $ResGroup; role = 'Member' }) }
            [ordered]@{ displayName = $ApBNew; previousDisplayName = $Ids.ApB; catalog = $CatB; resourceRoles = @() }
        )
    }
}

function Read-S114Ids {
    # The ids recorded by 1.1 under raw\s114 (never printed).
    $Path = Join-Path $Raw 'before.json'
    if (-not (Test-Path -LiteralPath $Path)) { throw 'STOP: raw\s114\before.json is missing; run 1.1 first.' }
    $J = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $J
}

function Write-S114Rows {
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Rows)
    # An if-statement assignment unrolls no rows to $null, and @($null).Count is 1: drop nulls first.
    $Rows = @(@($Rows) | Where-Object { $null -ne $_ })
    Write-OerLiveStep "$Label rows: $($Rows.Count)"
    foreach ($R in @($Rows)) { Write-OerLiveStep "$Label row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
}

function Write-S114Validation {
    # Test-OERStructure's verdict and every finding, by severity, path and message.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json)
    $V = Test-OERStructure -Json $Json
    Write-OerLiveStep "$Label valid: $($V.Valid); errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count); warnings: $(@($V.Errors | Where-Object Severity -eq 'Warning').Count)"
    foreach ($F in @($V.Errors)) { Write-OerLiveStep "$Label finding: $($F.Severity) | $($F.Path) | $($F.Message)" }
}

function Invoke-S114Apply {
    # One Invoke-OERStructure call -- a -WhatIf plan or a run, with or without -Prune -- counted from its
    # first request to its last. The document is kept under raw\s114. Warnings are captured on the stream
    # (3>&1), where each is written once, and printed through the redactor.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json, [switch]$Plan, [switch]$Prune)
    [System.IO.File]::WriteAllText((Join-Path $Raw ('doc-{0}.json' -f ($Label -replace '[^0-9A-Za-z.]', '_'))), $Json, [System.Text.UTF8Encoding]::new($false))
    $Params = @{ Json = $Json; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'E' }
    if ($Plan) { $Params.WhatIf = $true } else { $Params.Confirm = $false }
    if ($Prune) { $Params.Prune = $true }
    Start-S114Count
    $E = $null
    try {
        $Out = @(Invoke-OERStructure @Params 3>&1)
        $Sent = Get-S114Sent
    } finally { Stop-S114Count }
    $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
    Write-S114Rows -Label $Label -Rows @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-OerLiveStep "$Label warnings: $($Warnings.Count)"
    foreach ($T in $Warnings) { Write-OerLiveStep "$Label warning: $T" }
    $Own = @(@($E) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure', [System.StringComparison]::Ordinal) })
    foreach ($X in $Own) { Write-OerLiveStep "$Label error: $([string]$X.FullyQualifiedErrorId): $([string]$X.Exception.Message)" }
    Write-OerLiveStep "$Label errors of Invoke-OERStructure: $($Own.Count); other items in -ErrorVariable (counted, not printed): $(@($E).Count - $Own.Count)"
    Write-OerLiveStep "$Label sent: $Sent"
    , @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
}
```

### S.1. The module loads from this branch's build in the step's own worktree

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Psm1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$Has = { param($Text) [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch $Text -Quiet) }
Write-OerLiveStep "The worktree's build carries the rename decision $(& $Has 'function Resolve-OERStructureRename'); the map reader $(& $Has 'function Get-OERStructureRenameTarget'); the refusal ids $(& $Has 'RenameConflict') $(& $Has 'RenameNotFound')"
Write-OerLiveStep "The worktree's build passes the map to the handlers: $(& $Has '$ExtraParams.RenameMap')"
Write-OerLiveStep "The worktree's build refuses an undecided rename (R12): -Include $(& $Has 'is not selected by -Include'); a failed lookup $(& $Has 'one of its names could not be looked up')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree on this branch with 0 tracked changes; every mark `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone;
a `False` mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-14 08:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree is on this branch at 6d7aa62 with 0 tracked changes, and its build (built from d586400, the last commit under source/) carries every mark, the R12 refusals included. The later commit of the branch changes only this checklist.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s114] The module loads from a worktree that is not the main clone: True
[oer-s114] Main clone: branch main; HEAD 491e72e
[oer-s114] Worktree: branch feat/rename-more-object-kinds; HEAD 6d7aa62 docs: add the live checklist for renaming units, catalogs and access packages in place; tracked changes: 0
[oer-s114] The worktree's build carries the rename decision True; the map reader True; the refusal ids True True
[oer-s114] The worktree's build passes the map to the handlers: True
[oer-s114] The worktree's build refuses an undecided rename (R12): -Include True; a failed lookup True
RUNNER: check-S.1 exit code 0; started 2026-10-14T08:00:52Z; took 3 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, and `The module is the worktree's
build: True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result: 2026-10-14 08:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc (app-only, certificate); identity check passed; the module is the worktree's build (1.2.1).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] The module is the worktree's build: True; version 1.2.1
RUNNER: check-0.1 exit code 0; started 2026-10-14T08:01:04Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.2. The permissions this file needs

- [x] **0.2** `oer-live-cc` holds the four permissions; otherwise the run stops here (the role permission alone makes the scoped role class B).

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Granted = Get-S114GrantedRole
foreach ($Name in $Needed) { Write-OerLiveStep "oer-live-cc holds $($Name): $($Granted -ccontains $Name)" }
Write-OerLiveStep "oer-live-cc holds $($Granted.Count) Microsoft Graph application permissions"
$Missing = @($Needed | Where-Object { $Granted -cnotcontains $_ })
if ($Missing.Count -gt 0) { Write-OerLiveStep "Missing: $($Missing -join ', ') (G11.7: granting it is the operator's decision)." }
Disconnect-OerLive
```

**Expect:** each of the four lines `True`.
**Failure looks like:** `False` for one of the first three -- stop the run; nothing has been written.

Result: 2026-10-14 08:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. oer-live-cc holds AdministrativeUnit.ReadWrite.All, EntitlementManagement.ReadWrite.All, Group.ReadWrite.All and RoleManagement.ReadWrite.Directory (19 Microsoft Graph application permissions in all); no permission was added or removed.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] oer-live-cc holds AdministrativeUnit.ReadWrite.All: True
[oer-s114] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114] oer-live-cc holds RoleManagement.ReadWrite.Directory: True
[oer-s114] oer-live-cc holds 19 Microsoft Graph application permissions
RUNNER: check-0.2 exit code 0; started 2026-10-14T08:01:18Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.3. The prerequisite objects

- [x] **0.3** The plan writes nothing; the first run creates the objects (or brings back what an earlier run renamed); a second run writes nothing.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS114Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS114Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -NonInteractive -File $Script @Run
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run ends `WhatIf: nothing was created, removed or written.` with exit code
0; the first `-Unattended` run creates what is missing and ends `unavailable (class B): none`, exit code
0; the second finds every object, names the scoped role, and writes nothing (`written to the tenant:
False`), exit code 0.
**Failure looks like:** a `Refusing to run:` line, an `UNAVAILABLE` line, or exit code 1 -- read the
reason; nothing past a refusal was written.

Result: 2026-10-14 08:10 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, on the third run of this check. Run 1 created the three groups and a unit, then stopped on a 404 reading the unit's members (replication), and its second -Unattended run created a SECOND unit oer-s114-au because the unit listing did not show the first yet; it also stopped on a script defect (a retry helper misused). Fixes to the prerequisite script, outside the repository: every created id is now recorded and read back by id when a listing lags (setup and teardown), the unit is waited on until it is listed and its members are readable, and the Member-role read is waited on with Wait-OerLiveConverged. The script's teardown then removed every oer-s114- object, both units included, and the counts were the baseline's. Run 2 created everything over two -Unattended runs (its -WhatIf run stopped on a group the sweep still listed seconds after its deletion, and its first -Unattended run on a members read that answered 404 again right after the unit read as converged). Run 3, below: the plan writes nothing; both -Unattended runs find all eight objects, the unit's member and its scoped role (License Administrator: neither low-risk role can be scoped to a unit, see the scoped-role paragraph above, and its holder oer-s114-rolegrp has no member, so nobody holds it), catalog A's resource, package A's policy and resource role, and write nothing (written to the tenant: False). unavailable (class B): none. Exit code 0 each time.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s114] === Initialize-OerS114Prereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s114\prereq-20261014-080930Z.log".
[oer-s114] Mode: CREATE or complete. Prefix 'oer-s114-'. Objects (fixed): oer-s114-member, oer-s114-resgrp (security groups, no member); oer-s114-rolegrp (role-assignable, no member, no owner); oer-s114-au (member oer-s114-member, one scoped role for oer-s114-rolegrp); oer-s114-cat-a (resource oer-s114-resgrp) with oer-s114-ap-a (hidden; resource role Member of oer-s114-resgrp; policy oer-s114-pol-a, administrator assignments only); oer-s114-cat-b with oer-s114-ap-b (hidden, nothing in it). The checklist renames oer-s114-au, oer-s114-cat-a, oer-s114-ap-a and oer-s114-ap-b to the same names with '-new' appended. OerLive 1.0.3.
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114] oer-live-cc holds AdministrativeUnit.ReadWrite.All: True
[oer-s114] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114] oer-live-cc holds RoleManagement.ReadWrite.Directory: True
[oer-s114] Found: oer-s114-member True; oer-s114-resgrp True; oer-s114-rolegrp True; oer-s114-au as oer-s114-au; oer-s114-cat-a as oer-s114-cat-a; oer-s114-cat-b True; oer-s114-ap-a as oer-s114-ap-a; oer-s114-ap-b as oer-s114-ap-b.
[oer-s114] The baseline exists (groups 97, administrative units 1, catalogs 5, access packages 6 when it was written).
[oer-s114] Group oer-s114-member exists.
[oer-s114] Group oer-s114-resgrp exists.
[oer-s114] Group oer-s114-rolegrp exists.
[oer-s114] Administrative unit oer-s114-au exists.
[oer-s114] oer-s114-member is a member of oer-s114-au.
[oer-s114] oer-s114-au has its scoped role: License Administrator for oer-s114-rolegrp.
[oer-s114] Catalog oer-s114-cat-a exists.
[oer-s114] Catalog oer-s114-cat-b exists.
[oer-s114] oer-s114-resgrp is a resource of oer-s114-cat-a.
[oer-s114] Access package oer-s114-ap-a exists.
[oer-s114] Access package oer-s114-ap-b exists.
[oer-s114] Policy oer-s114-pol-a exists.
[oer-s114] The Member role of oer-s114-resgrp is bound to oer-s114-ap-a.
[oer-s114] Summary: oer-s114-member True; oer-s114-resgrp True; oer-s114-rolegrp True; oer-s114-au True (member True, scoped role License Administrator); oer-s114-cat-a True (resource True); oer-s114-cat-b True; oer-s114-ap-a True (policy True, resource role True); oer-s114-ap-b True; unavailable (class B): none; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s114] WhatIf: nothing was created, removed or written.
[oer-s114] Done.
[oer-s114] exit code: 0
[oer-s114] === Initialize-OerS114Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114] Transcript (redacted): raw\s114\prereq-20261014-080938Z.log; OerLive 1.0.3.
[oer-s114] Mode: CREATE or complete. Prefix 'oer-s114-'. Objects (fixed): oer-s114-member, oer-s114-resgrp (security groups, no member); oer-s114-rolegrp (role-assignable, no member, no owner); oer-s114-au (member oer-s114-member, one scoped role for oer-s114-rolegrp); oer-s114-cat-a (resource oer-s114-resgrp) with oer-s114-ap-a (hidden; resource role Member of oer-s114-resgrp; policy oer-s114-pol-a, administrator assignments only); oer-s114-cat-b with oer-s114-ap-b (hidden, nothing in it). The checklist renames oer-s114-au, oer-s114-cat-a, oer-s114-ap-a and oer-s114-ap-b to the same names with '-new' appended. OerLive 1.0.3.
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s114] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114] oer-live-cc holds AdministrativeUnit.ReadWrite.All: True
[oer-s114] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114] oer-live-cc holds RoleManagement.ReadWrite.Directory: True
[oer-s114] Found: oer-s114-member True; oer-s114-resgrp True; oer-s114-rolegrp True; oer-s114-au as oer-s114-au; oer-s114-cat-a as oer-s114-cat-a; oer-s114-cat-b True; oer-s114-ap-a as oer-s114-ap-a; oer-s114-ap-b as oer-s114-ap-b.
[oer-s114] The baseline exists (groups 97, administrative units 1, catalogs 5, access packages 6 when it was written).
[oer-s114] Group oer-s114-member exists.
[oer-s114] Group oer-s114-resgrp exists.
[oer-s114] Group oer-s114-rolegrp exists.
[oer-s114] Administrative unit oer-s114-au exists.
[oer-s114] oer-s114-member is a member of oer-s114-au.
[oer-s114] oer-s114-au has its scoped role: License Administrator for oer-s114-rolegrp.
[oer-s114] Catalog oer-s114-cat-a exists.
[oer-s114] Catalog oer-s114-cat-b exists.
[oer-s114] oer-s114-resgrp is a resource of oer-s114-cat-a.
[oer-s114] Access package oer-s114-ap-a exists.
[oer-s114] Access package oer-s114-ap-b exists.
[oer-s114] Policy oer-s114-pol-a exists.
[oer-s114] The Member role of oer-s114-resgrp is bound to oer-s114-ap-a.
[oer-s114] Summary: oer-s114-member True; oer-s114-resgrp True; oer-s114-rolegrp True; oer-s114-au True (member True, scoped role License Administrator); oer-s114-cat-a True (resource True); oer-s114-cat-b True; oer-s114-ap-a True (policy True, resource role True); oer-s114-ap-b True; unavailable (class B): none; written to the tenant: False.
[oer-s114] Done.
[oer-s114] exit code: 0
[oer-s114] === Initialize-OerS114Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114] Transcript (redacted): raw\s114\prereq-20261014-080946Z.log; OerLive 1.0.3.
[oer-s114] Mode: CREATE or complete. Prefix 'oer-s114-'. Objects (fixed): oer-s114-member, oer-s114-resgrp (security groups, no member); oer-s114-rolegrp (role-assignable, no member, no owner); oer-s114-au (member oer-s114-member, one scoped role for oer-s114-rolegrp); oer-s114-cat-a (resource oer-s114-resgrp) with oer-s114-ap-a (hidden; resource role Member of oer-s114-resgrp; policy oer-s114-pol-a, administrator assignments only); oer-s114-cat-b with oer-s114-ap-b (hidden, nothing in it). The checklist renames oer-s114-au, oer-s114-cat-a, oer-s114-ap-a and oer-s114-ap-b to the same names with '-new' appended. OerLive 1.0.3.
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s114] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114] oer-live-cc holds AdministrativeUnit.ReadWrite.All: True
[oer-s114] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114] oer-live-cc holds RoleManagement.ReadWrite.Directory: True
[oer-s114] Found: oer-s114-member True; oer-s114-resgrp True; oer-s114-rolegrp True; oer-s114-au as oer-s114-au; oer-s114-cat-a as oer-s114-cat-a; oer-s114-cat-b True; oer-s114-ap-a as oer-s114-ap-a; oer-s114-ap-b as oer-s114-ap-b.
[oer-s114] The baseline exists (groups 97, administrative units 1, catalogs 5, access packages 6 when it was written).
[oer-s114] Group oer-s114-member exists.
[oer-s114] Group oer-s114-resgrp exists.
[oer-s114] Group oer-s114-rolegrp exists.
[oer-s114] Administrative unit oer-s114-au exists.
[oer-s114] oer-s114-member is a member of oer-s114-au.
[oer-s114] oer-s114-au has its scoped role: License Administrator for oer-s114-rolegrp.
[oer-s114] Catalog oer-s114-cat-a exists.
[oer-s114] Catalog oer-s114-cat-b exists.
[oer-s114] oer-s114-resgrp is a resource of oer-s114-cat-a.
[oer-s114] Access package oer-s114-ap-a exists.
[oer-s114] Access package oer-s114-ap-b exists.
[oer-s114] Policy oer-s114-pol-a exists.
[oer-s114] The Member role of oer-s114-resgrp is bound to oer-s114-ap-a.
[oer-s114] Summary: oer-s114-member True; oer-s114-resgrp True; oer-s114-rolegrp True; oer-s114-au True (member True, scoped role License Administrator); oer-s114-cat-a True (resource True); oer-s114-cat-b True; oer-s114-ap-a True (policy True, resource role True); oer-s114-ap-b True; unavailable (class B): none; written to the tenant: False.
[oer-s114] Done.
[oer-s114] exit code: 0
RUNNER: check-0.3 exit code 0; started 2026-10-14T08:09:28Z; took 25 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. The rename in place

### 1.1. The ids before the rename

- [x] **1.1** Every object is found exactly once under its own name; the ids, and what each object holds, are recorded under `raw\s114\` (never printed).

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Ids = [ordered]@{}
foreach ($Spec in @(@('Unit', 'unit', $Au), @('CatA', 'catalog', $CatA), @('CatB', 'catalog', $CatB), @('ApA', 'package', $ApA), @('ApB', 'package', $ApB))) {
    $Hit = @(Get-S114Id -Kind $Spec[1] -Name $Spec[2])
    Write-OerLiveStep "$($Spec[2]) is found exactly once under its own name: $($Hit.Count -eq 1)"
    if ($Hit.Count -ne 1) { throw "STOP: $($Spec[2]) matches $($Hit.Count) objects." }
    $Ids[$Spec[0]] = $Hit[0]
}
foreach ($Spec in @(@('unit', $AuNew), @('catalog', $CatANew), @('package', $ApANew), @('package', $ApBNew))) {
    Write-OerLiveStep "No object carries the new name $($Spec[1]) yet: $(@(Get-S114Id -Kind $Spec[0] -Name $Spec[1]).Count -eq 0)"
}
$Before = Get-S114Snapshot -Ids $Ids
Write-OerLiveStep "Before: unit member(s) $($Before.UnitMembers.Count); scoped role(s) $($Before.UnitScopedRoles.Count) ($(Get-S114ScopedRoleName -UnitId $Ids.Unit)); catalog A resource(s) $($Before.CatAResources.Count); package A resource role(s) $($Before.ApABindings.Count), policy(ies) $($Before.ApAPolicies.Count); prefixed objects $($Before.Prefixed.Count)"
$Record = [ordered]@{ Ids = $Ids; Before = $Before }
[System.IO.File]::WriteAllText((Join-Path $Raw 'before.json'), (ConvertTo-Json -InputObject $Record -Depth 6), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep 'Recorded the ids and the snapshot under raw\s114\before.json (not printed).'
Disconnect-OerLive
```

**Expect:** five `found exactly once` lines and four `No object carries the new name` lines, all
`True`; `Before:` one unit member, one scoped role (its name), one catalog A resource, one package A
resource role and one policy; the number of prefixed objects (three groups, one unit, two catalogs, two
packages: 8).
**Failure looks like:** a `STOP` or a `False` -- run 0.3 again (it renames back what an earlier run
renamed).

Result: 2026-10-14 08:11 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (second run; the first ran with a helper that returned its ids wrapped once too often, so its lines were not valid -- fixed in the checklist commit that returns the ids unwrapped). Each of the five objects is found exactly once under its own name and no object carries any of the four new names; before the rename the unit holds one member and one scoped role (License Administrator), catalog A one resource, package A one resource role and one policy, and the sweep lists 8 prefixed objects. The ids and the snapshot are under raw\s114\before.json, not printed.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] oer-s114-au is found exactly once under its own name: True
[oer-s114] oer-s114-cat-a is found exactly once under its own name: True
[oer-s114] oer-s114-cat-b is found exactly once under its own name: True
[oer-s114] oer-s114-ap-a is found exactly once under its own name: True
[oer-s114] oer-s114-ap-b is found exactly once under its own name: True
[oer-s114] No object carries the new name oer-s114-au-new yet: True
[oer-s114] No object carries the new name oer-s114-cat-a-new yet: True
[oer-s114] No object carries the new name oer-s114-ap-a-new yet: True
[oer-s114] No object carries the new name oer-s114-ap-b-new yet: True
[oer-s114] Before: unit member(s) 1; scoped role(s) 1 (License Administrator); catalog A resource(s) 1; package A resource role(s) 1, policy(ies) 1; prefixed objects 8
[oer-s114] Recorded the ids and the snapshot under raw\s114\before.json (not printed).
RUNNER: check-1.1 exit code 0; started 2026-10-14T08:11:28Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. The validator accepts the rename document

- [x] **1.2** `Test-OERStructure` reports the document valid, with no Error.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Ids = (Read-S114Ids)['Ids']
$Json = New-S114RenameDocument -Ids $Ids
Write-S114Validation -Label '1.2' -Json $Json
Disconnect-OerLive
```

**Expect:** `1.2 valid: True; errors: 0`, and no finding at a `previousDisplayName` path.
**Failure looks like:** an Error at `administrativeUnits[0].previousDisplayName`,
`catalogs[0].previousDisplayName` or `accessPackages[n].previousDisplayName` -- the step 3 refusal is
still in force for that kind.

Result: 2026-10-14 08:12 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Test-OERStructure reports the rename document valid with no Error and no Warning: previousDisplayName is accepted on the unit, catalog A and both packages (package B's as its object id), and no finding stands at a previousDisplayName path.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] 1.2 valid: True; errors: 0; warnings: 0
RUNNER: check-1.2 exit code 0; started 2026-10-14T08:11:46Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.3. The plan renames in place and writes nothing

- [x] **1.3** Under `-WhatIf` each of the four objects is reported `would rename` from its previous name to its new name, its collections are planned against the object found under its previous name (Unchanged), and nothing is written.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Ids = (Read-S114Ids)['Ids']
$Json = New-S114RenameDocument -Ids $Ids
$null = Invoke-S114Apply -Label '1.3' -Json $Json -Plan
Disconnect-OerLive
```

**Expect:** four Skipped rows `would rename administrative unit 'oer-s114-au' to 'oer-s114-au-new'`,
`would rename catalog 'oer-s114-cat-a' to 'oer-s114-cat-a-new'`, `would rename access package
'oer-s114-ap-a' to 'oer-s114-ap-a-new'` and `would rename access package` from package B's object id to
`oer-s114-ap-b-new`; Unchanged rows for the unit's member and scoped role, catalog A's resource,
package A's resource role and catalog B's properties; no Created, Failed or Removed row; `errors of
Invoke-OERStructure: 0`; `writes: 0` for Microsoft Graph and Azure Resource Manager.
**Failure looks like:** a `would create` row (the engine would create a second object), a Failed row for
package A (its catalog's new name did not reach the catalog through the run's rename map), or any write.

Result: 2026-10-14 08:12 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Under -WhatIf the four objects are reported Skipped 'would rename ... to ...': the unit, catalog A, package A (whose catalog is renamed in the same plan and was reached by its id through the run's rename map) and package B (named by its object id). The unit's member and scoped role, catalog A's resource, package A's resource role and catalog B's properties are Unchanged against the objects found under their previous names. No Created, Failed or Removed row; no error; 29 Microsoft Graph requests, 0 writes; 0 Azure Resource Manager requests; 0 token requests.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Rename administrative unit 'oer-s114-au' to 'oer-s114-au-new'" on target "oer-s114-au-new".
What if: Performing the operation "Rename catalog 'oer-s114-cat-a' to 'oer-s114-cat-a-new'" on target "oer-s114-cat-a-new".
What if: Performing the operation "Rename access package 'oer-s114-ap-a' to 'oer-s114-ap-a-new'" on target "oer-s114-ap-a-new".
What if: Performing the operation "Rename access package '00000000-0000-0000-0000-000000000001' to 'oer-s114-ap-b-new'" on target "oer-s114-ap-b-new".
[oer-s114] 1.3 rows: 9
[oer-s114] 1.3 row: administrativeUnits | oer-s114-au-new | Skipped | would rename administrative unit 'oer-s114-au' to 'oer-s114-au-new'
[oer-s114] 1.3 row: administrativeUnits | oer-s114-au-new | Unchanged | member 'oer-s114-member' already present
[oer-s114] 1.3 row: administrativeUnits | oer-s114-au-new | Unchanged | scopedRole 'License Administrator' for 'oer-s114-rolegrp' already present
[oer-s114] 1.3 row: catalogs | oer-s114-cat-a-new | Skipped | would rename catalog 'oer-s114-cat-a' to 'oer-s114-cat-a-new'
[oer-s114] 1.3 row: catalogs | oer-s114-cat-a-new | Unchanged | resource 'oer-s114-resgrp' already present
[oer-s114] 1.3 row: catalogs | oer-s114-cat-b | Unchanged | catalog properties match
[oer-s114] 1.3 row: accessPackages | oer-s114-ap-a-new | Skipped | would rename access package 'oer-s114-ap-a' to 'oer-s114-ap-a-new'
[oer-s114] 1.3 row: accessPackages | oer-s114-ap-a-new | Unchanged | resourceRole 'Member' on 'oer-s114-resgrp' already bound
[oer-s114] 1.3 row: accessPackages | oer-s114-ap-b-new | Skipped | would rename access package '00000000-0000-0000-0000-000000000001' to 'oer-s114-ap-b-new'
[oer-s114] 1.3 warnings: 0
[oer-s114] 1.3 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 1.3 sent: token requests: 0; Microsoft Graph requests: 29, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check-1.3 exit code 0; started 2026-10-14T08:12:00Z; took 9 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.4. The run renames in place

- [x] **1.4** The run renames the four objects, each in one PATCH, and writes nothing else.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Ids = (Read-S114Ids)['Ids']
$Json = New-S114RenameDocument -Ids $Ids
$null = Invoke-S114Apply -Label '1.4' -Json $Json
Disconnect-OerLive
```

**Expect:** four Updated rows `renamed administrative unit 'oer-s114-au' to 'oer-s114-au-new'` and the
same for the catalog and both packages; the collection rows Unchanged as in 1.3; no Created, Failed or
Removed row; `errors of Invoke-OERStructure: 0`; Microsoft Graph `writes: 4`, each a PATCH: the unit,
catalog A and the two packages, by object id.
**Failure looks like:** a POST (an object was created), a fifth write, or a Failed row.

Result: 2026-10-14 08:13 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Four Updated rows 'renamed ... to ...' (the unit, catalog A, package A in the renamed catalog, package B named by its object id); the collection rows Unchanged as in 1.3; no Created, Failed or Removed row; no error. Microsoft Graph: 34 requests, exactly 4 writes, all PATCH, no POST and no DELETE (the counter's path column prints empty for the module's relative request paths -- a limit of this checklist's counter; 1.5 reads the four objects back by id). 0 Azure Resource Manager requests, 0 token requests.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.4 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] 1.4 rows: 9
[oer-s114] 1.4 row: administrativeUnits | oer-s114-au-new | Updated | renamed administrative unit 'oer-s114-au' to 'oer-s114-au-new'
[oer-s114] 1.4 row: administrativeUnits | oer-s114-au-new | Unchanged | member 'oer-s114-member' already present
[oer-s114] 1.4 row: administrativeUnits | oer-s114-au-new | Unchanged | scopedRole 'License Administrator' for 'oer-s114-rolegrp' already present
[oer-s114] 1.4 row: catalogs | oer-s114-cat-a-new | Updated | renamed catalog 'oer-s114-cat-a' to 'oer-s114-cat-a-new'
[oer-s114] 1.4 row: catalogs | oer-s114-cat-a-new | Unchanged | resource 'oer-s114-resgrp' already present
[oer-s114] 1.4 row: catalogs | oer-s114-cat-b | Unchanged | catalog properties match
[oer-s114] 1.4 row: accessPackages | oer-s114-ap-a-new | Updated | renamed access package 'oer-s114-ap-a' to 'oer-s114-ap-a-new'
[oer-s114] 1.4 row: accessPackages | oer-s114-ap-a-new | Unchanged | resourceRole 'Member' on 'oer-s114-resgrp' already bound
[oer-s114] 1.4 row: accessPackages | oer-s114-ap-b-new | Updated | renamed access package '00000000-0000-0000-0000-000000000001' to 'oer-s114-ap-b-new'
[oer-s114] 1.4 warnings: 0
[oer-s114] 1.4 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 1.4 sent: token requests: 0; Microsoft Graph requests: 34, writes: 4 (PATCH , PATCH , PATCH , PATCH ); Azure Resource Manager requests: 0, writes: 0
RUNNER: check-1.4 exit code 0; started 2026-10-14T08:12:26Z; took 16 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.5. Read back by id: the same objects, the new names, nothing lost, nothing created

- [x] **1.5** Each object read by the id recorded in 1.1 carries its new name; its members, scoped role, resources, resource role and policy are the same ones; the sweep lists the same prefixed objects as before the rename.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Rec = Read-S114Ids
$Ids = $Rec['Ids']; $B = $Rec['Before']
$After = Get-S114Snapshot -Ids $Ids
Write-OerLiveStep "Unit: name is $AuNew $($After.UnitName -ceq $AuNew); same members $((@($After.UnitMembers) -join ',') -ceq (@($B['UnitMembers']) -join ',')); same scoped role(s) $((@($After.UnitScopedRoles) -join ',') -ceq (@($B['UnitScopedRoles']) -join ','))"
Write-OerLiveStep "Catalog A: name is $CatANew $($After.CatAName -ceq $CatANew); same resource(s) $((@($After.CatAResources) -join ',') -ceq (@($B['CatAResources']) -join ','))"
Write-OerLiveStep "Catalog B: name is unchanged $($After.CatBName -ceq $CatB)"
Write-OerLiveStep "Package A: name is $ApANew $($After.ApAName -ceq $ApANew); same resource role(s) $((@($After.ApABindings) -join ',') -ceq (@($B['ApABindings']) -join ',')); same policy(ies) $((@($After.ApAPolicies) -join ',') -ceq (@($B['ApAPolicies']) -join ','))"
Write-OerLiveStep "Package B: name is $ApBNew $($After.ApBName -ceq $ApBNew)"
Write-OerLiveStep "The sweep lists the same prefixed objects as before the rename (no object created, none lost): $((@($After.Prefixed) -join ',') -ceq (@($B['Prefixed']) -join ',')) ($($After.Prefixed.Count) now, $(@($B['Prefixed']).Count) before)"
Disconnect-OerLive
```

**Expect:** every line `True`; 8 prefixed objects now and before.
**Failure looks like:** a `False` -- a name not changed, a collection changed, or an object added or
lost (a lagging read: wait a minute and run the block again; it writes nothing).

Result: 2026-10-14 08:13 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Read by the ids recorded in 1.1: the unit, catalog A and both packages carry their new names (catalog B its own); the unit has the same member and the same scoped role membership (same ids), catalog A the same resource, package A the same resource role binding and the same policy; the sweep lists the same 8 prefixed objects (kind and id) as before the rename -- nothing created, nothing lost.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.5 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Unit: name is oer-s114-au-new True; same members True; same scoped role(s) True
[oer-s114] Catalog A: name is oer-s114-cat-a-new True; same resource(s) True
[oer-s114] Catalog B: name is unchanged True
[oer-s114] Package A: name is oer-s114-ap-a-new True; same resource role(s) True; same policy(ies) True
[oer-s114] Package B: name is oer-s114-ap-b-new True
[oer-s114] The sweep lists the same prefixed objects as before the rename (no object created, none lost): True (8 now, 8 before)
RUNNER: check-1.5 exit code 0; started 2026-10-14T08:13:02Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. The same document again converges (G8)

### 2.1. The new names resolve

- [x] **2.1** Microsoft Graph's name lookup finds each object under its new name, three times in a row, before the convergence runs.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Ids = (Read-S114Ids)['Ids']
$Wanted = @(@('unit', $AuNew, $Ids.Unit), @('catalog', $CatANew, $Ids.CatA), @('package', $ApANew, $Ids.ApA), @('package', $ApBNew, $Ids.ApB))
$Steady = 0; $Reads = 0
while ($Steady -lt 3 -and $Reads -lt 40) {
    $Reads++
    $Ok = @($Wanted | Where-Object { $Hit = @(Get-S114Id -Kind $_[0] -Name $_[1]); $Hit.Count -eq 1 -and $Hit[0] -eq $_[2] }).Count -eq $Wanted.Count
    $Steady = if ($Ok) { $Steady + 1 } else { 0 }
    if ($Steady -lt 3) { Start-Sleep -Seconds 10 }
}
Write-OerLiveStep "Every new name resolves to the recorded id, three reads in a row: $($Steady -ge 3) ($Reads read(s))"
Disconnect-OerLive
```

**Expect:** `True`.
**Failure looks like:** `False` after 40 reads -- the name lookup has not caught up; run the block again.

Result: 2026-10-14 08:13 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Each of the four new names resolves to the id recorded in 1.1, three reads in a row (3 reads, 10 s apart).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Every new name resolves to the recorded id, three reads in a row: True (3 read(s))
RUNNER: check-2.1 exit code 0; started 2026-10-14T08:13:20Z; took 25 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.2. The same document twice more: only Unchanged

- [x] **2.2** Two runs of the 1.4 document report only Unchanged rows and write nothing.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Ids = (Read-S114Ids)['Ids']
$Json = New-S114RenameDocument -Ids $Ids
foreach ($Run in 1, 2) {
    $Rows = Invoke-S114Apply -Label "2.2 run $Run" -Json $Json
    Write-OerLiveStep "2.2 run $($Run): only Unchanged rows: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count -eq 0)"
}
Disconnect-OerLive
```

**Expect:** for each run `only Unchanged rows: True`, `errors of Invoke-OERStructure: 0`, `writes: 0`.
**Failure looks like:** a `renamed` row (the new name did not resolve), an Updated row, or any write.

Result: 2026-10-14 08:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The 1.4 document (previousDisplayName still declared) run twice more: each run reports 9 rows, all Unchanged -- the four objects are found under their new names and 'properties match', every collection 'already present' or 'already bound'; no error; 31 Microsoft Graph requests and 0 writes each time (G8).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] 2.2 run 1 rows: 9
[oer-s114] 2.2 run 1 row: administrativeUnits | oer-s114-au-new | Unchanged | administrative unit properties match
[oer-s114] 2.2 run 1 row: administrativeUnits | oer-s114-au-new | Unchanged | member 'oer-s114-member' already present
[oer-s114] 2.2 run 1 row: administrativeUnits | oer-s114-au-new | Unchanged | scopedRole 'License Administrator' for 'oer-s114-rolegrp' already present
[oer-s114] 2.2 run 1 row: catalogs | oer-s114-cat-a-new | Unchanged | catalog properties match
[oer-s114] 2.2 run 1 row: catalogs | oer-s114-cat-a-new | Unchanged | resource 'oer-s114-resgrp' already present
[oer-s114] 2.2 run 1 row: catalogs | oer-s114-cat-b | Unchanged | catalog properties match
[oer-s114] 2.2 run 1 row: accessPackages | oer-s114-ap-a-new | Unchanged | access package properties match
[oer-s114] 2.2 run 1 row: accessPackages | oer-s114-ap-a-new | Unchanged | resourceRole 'Member' on 'oer-s114-resgrp' already bound
[oer-s114] 2.2 run 1 row: accessPackages | oer-s114-ap-b-new | Unchanged | access package properties match
[oer-s114] 2.2 run 1 warnings: 0
[oer-s114] 2.2 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 2.2 run 1 sent: token requests: 0; Microsoft Graph requests: 31, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] 2.2 run 1: only Unchanged rows: True
[oer-s114] 2.2 run 2 rows: 9
[oer-s114] 2.2 run 2 row: administrativeUnits | oer-s114-au-new | Unchanged | administrative unit properties match
[oer-s114] 2.2 run 2 row: administrativeUnits | oer-s114-au-new | Unchanged | member 'oer-s114-member' already present
[oer-s114] 2.2 run 2 row: administrativeUnits | oer-s114-au-new | Unchanged | scopedRole 'License Administrator' for 'oer-s114-rolegrp' already present
[oer-s114] 2.2 run 2 row: catalogs | oer-s114-cat-a-new | Unchanged | catalog properties match
[oer-s114] 2.2 run 2 row: catalogs | oer-s114-cat-a-new | Unchanged | resource 'oer-s114-resgrp' already present
[oer-s114] 2.2 run 2 row: catalogs | oer-s114-cat-b | Unchanged | catalog properties match
[oer-s114] 2.2 run 2 row: accessPackages | oer-s114-ap-a-new | Unchanged | access package properties match
[oer-s114] 2.2 run 2 row: accessPackages | oer-s114-ap-a-new | Unchanged | resourceRole 'Member' on 'oer-s114-resgrp' already bound
[oer-s114] 2.2 run 2 row: accessPackages | oer-s114-ap-b-new | Unchanged | access package properties match
[oer-s114] 2.2 run 2 warnings: 0
[oer-s114] 2.2 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 2.2 run 2 sent: token requests: 0; Microsoft Graph requests: 31, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] 2.2 run 2: only Unchanged rows: True
RUNNER: check-2.2 exit code 0; started 2026-10-14T08:13:56Z; took 13 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.3. With -Prune, the plan removes nothing

- [x] **2.3** `-Prune -WhatIf` on the same document plans no removal and writes nothing.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Ids = (Read-S114Ids)['Ids']
$Json = New-S114RenameDocument -Ids $Ids
$Rows = Invoke-S114Apply -Label '2.3' -Json $Json -Plan -Prune
Write-OerLiveStep "2.3 rows that remove or would remove: $(@($Rows | Where-Object { $_.Action -eq 'Removed' -or ($_.Detail -match 'would remove') }).Count)"
Disconnect-OerLive
```

**Expect:** `2.3 rows that remove or would remove: 0`, only Unchanged rows, `warnings: 0`, `writes: 0`.
**Failure looks like:** a `would remove` row or a warning naming an omitted collection.

Result: 2026-10-14 08:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. -Prune -WhatIf on the same document: 9 rows, all Unchanged, 0 rows that remove or would remove, no warning (every collection the prune reconciles is declared), no error, 31 Microsoft Graph requests and 0 writes.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.3 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] 2.3 rows: 9
[oer-s114] 2.3 row: administrativeUnits | oer-s114-au-new | Unchanged | administrative unit properties match
[oer-s114] 2.3 row: administrativeUnits | oer-s114-au-new | Unchanged | member 'oer-s114-member' already present
[oer-s114] 2.3 row: administrativeUnits | oer-s114-au-new | Unchanged | scopedRole 'License Administrator' for 'oer-s114-rolegrp' already present
[oer-s114] 2.3 row: catalogs | oer-s114-cat-a-new | Unchanged | catalog properties match
[oer-s114] 2.3 row: catalogs | oer-s114-cat-a-new | Unchanged | resource 'oer-s114-resgrp' already present
[oer-s114] 2.3 row: catalogs | oer-s114-cat-b | Unchanged | catalog properties match
[oer-s114] 2.3 row: accessPackages | oer-s114-ap-a-new | Unchanged | access package properties match
[oer-s114] 2.3 row: accessPackages | oer-s114-ap-a-new | Unchanged | resourceRole 'Member' on 'oer-s114-resgrp' already bound
[oer-s114] 2.3 row: accessPackages | oer-s114-ap-b-new | Unchanged | access package properties match
[oer-s114] 2.3 warnings: 0
[oer-s114] 2.3 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 2.3 sent: token requests: 0; Microsoft Graph requests: 31, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] 2.3 rows that remove or would remove: 0
RUNNER: check-2.3 exit code 0; started 2026-10-14T08:14:21Z; took 10 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. A conflict, and names nothing carries, write nothing

### 3.1. Two different catalogs under the two names

- [x] **3.1** A catalog entry whose new name is `oer-s114-cat-b` and whose previous name is `oer-s114-cat-a-new` (two different catalogs) fails with `CatalogRenameConflict`, and a package entry in `oer-s114-cat-b` is not created: planned or run, nothing is written.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Json = New-S114Document -Section @{
    catalogs       = @([ordered]@{ displayName = $CatB; previousDisplayName = $CatANew; resources = @() })
    accessPackages = @([ordered]@{ displayName = 'oer-s114-ap-x'; catalog = $CatB; resourceRoles = @() })
}
Write-S114Validation -Label '3.1' -Json $Json
$null = Invoke-S114Apply -Label '3.1 plan' -Json $Json -Plan
$null = Invoke-S114Apply -Label '3.1 run' -Json $Json
Write-OerLiveStep "oer-s114-ap-x exists: $(@(Get-S114Id -Kind 'package' -Name 'oer-s114-ap-x').Count -gt 0)"
Disconnect-OerLive
```

**Expect:** `3.1 valid: True`; in the plan and in the run one Failed row for `oer-s114-cat-b` naming both
names and saying the document never merges two catalogs, with the error `CatalogRenameConflict`, and one
Failed row for `oer-s114-ap-x` saying the catalog's rename was refused (`CatalogRenameConflict`) and
nothing was created, read or written for it; `writes: 0` both times; `oer-s114-ap-x exists: False`.
**Failure looks like:** any write, or `oer-s114-ap-x exists: True` (the package was created in the other
catalog).

Result: 2026-10-14 08:15 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The validator accepts the document. In the plan and in the run: one Failed row for oer-s114-cat-b (both names exist as different catalogs; the document never merges two catalogs) with the error CatalogRenameConflict,Invoke-OERStructure, and one Failed row for oer-s114-ap-x (its catalog's rename was refused, CatalogRenameConflict; nothing created, read or written for it) with no error record of its own; 2 Microsoft Graph requests (the two name lookups), 0 writes, both times; oer-s114-ap-x does not exist -- the package was not created in the other catalog that carries the new name.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] 3.1 valid: True; errors: 0; warnings: 0
[oer-s114] 3.1 plan rows: 2
[oer-s114] 3.1 plan row: catalogs | oer-s114-cat-b | Failed | both 'oer-s114-cat-b' and its previousDisplayName 'oer-s114-cat-a-new' exist as different catalogs; the document never merges two catalogs, so nothing was changed -- rename or delete one of them, or remove previousDisplayName
[oer-s114] 3.1 plan row: accessPackages | oer-s114-ap-x | Failed | catalog 'oer-s114-cat-b' was not reconciled in this run: its rename from 'oer-s114-cat-a-new' was refused (CatalogRenameConflict), so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it
[oer-s114] 3.1 plan warnings: 0
[oer-s114] 3.1 plan error: CatalogRenameConflict,Invoke-OERStructure: Catalog 'oer-s114-cat-b' (00000000-0000-0000-0000-000000000002) and its previousDisplayName 'oer-s114-cat-a-new' (00000000-0000-0000-0000-000000000003) are different catalogs. The document never merges two catalogs, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName.
[oer-s114] 3.1 plan errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 3.1 plan sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] 3.1 run rows: 2
[oer-s114] 3.1 run row: catalogs | oer-s114-cat-b | Failed | both 'oer-s114-cat-b' and its previousDisplayName 'oer-s114-cat-a-new' exist as different catalogs; the document never merges two catalogs, so nothing was changed -- rename or delete one of them, or remove previousDisplayName
[oer-s114] 3.1 run row: accessPackages | oer-s114-ap-x | Failed | catalog 'oer-s114-cat-b' was not reconciled in this run: its rename from 'oer-s114-cat-a-new' was refused (CatalogRenameConflict), so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it
[oer-s114] 3.1 run warnings: 0
[oer-s114] 3.1 run error: CatalogRenameConflict,Invoke-OERStructure: Catalog 'oer-s114-cat-b' (00000000-0000-0000-0000-000000000002) and its previousDisplayName 'oer-s114-cat-a-new' (00000000-0000-0000-0000-000000000003) are different catalogs. The document never merges two catalogs, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName.
[oer-s114] 3.1 run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 3.1 run sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] oer-s114-ap-x exists: False
RUNNER: check-3.1 exit code 0; started 2026-10-14T08:14:42Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. Neither name matches: nothing is created

- [x] **3.2** A unit and a catalog whose previous name is an object id nothing carries, and a package whose two names nothing in its catalog carries, each fail with `<Kind>RenameNotFound`; planned or run, nothing is created or written.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Json = New-S114Document -Section @{
    administrativeUnits = @([ordered]@{ displayName = 'oer-s114-au-none'; previousDisplayName = $NoSuchId; members = @(); scopedRoles = @() })
    catalogs            = @([ordered]@{ displayName = 'oer-s114-cat-none'; previousDisplayName = $NoSuchId; resources = @() })
    accessPackages      = @([ordered]@{ displayName = 'oer-s114-ap-none'; previousDisplayName = 'oer-s114-ap-ghost'; catalog = $CatB; resourceRoles = @() })
}
Write-S114Validation -Label '3.2' -Json $Json
$null = Invoke-S114Apply -Label '3.2 plan' -Json $Json -Plan
$null = Invoke-S114Apply -Label '3.2 run' -Json $Json
foreach ($Spec in @(@('unit', 'oer-s114-au-none'), @('catalog', 'oer-s114-cat-none'), @('package', 'oer-s114-ap-none'))) {
    Write-OerLiveStep "$($Spec[1]) exists: $(@(Get-S114Id -Kind $Spec[0] -Name $Spec[1]).Count -gt 0)"
}
Disconnect-OerLive
```

**Expect:** `3.2 valid: True`; in the plan and in the run three Failed rows -- the unit with
`AdministrativeUnitRenameNotFound`, the catalog with `CatalogRenameNotFound` (both previous names are
the register's non-existent id, looked up by id: the not-found answer is the expected one, not an
error of its own) and the package with `AccessPackageRenameNotFound` naming `oer-s114-cat-b` -- each
saying nothing was created; `writes: 0` both times; the three `exists` lines `False`.
**Failure looks like:** a `would create` or Created row, a write, an `exists: True`, or a `handler error`
row (the by-id lookup answered with a not-found code the module does not declare).

Result: 2026-10-14 08:15 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The validator accepts the document (one Warning, Rule 11's 'Catalog oer-s114-cat-b is not declared in this document', expected: the document declares no catalogs entry for it). In the plan and in the run: three Failed rows and three errors -- AdministrativeUnitRenameNotFound and CatalogRenameNotFound (both previous names are the register's non-existent id ...099, looked up by id: the not-found answers of the unit probe and the catalog probe were the codes the module declares, so Ruling R6 holds live -- an undeclared code would have been a handler error) and AccessPackageRenameNotFound naming oer-s114-cat-b; each says nothing was created; 6 Microsoft Graph requests, 0 writes, both times; oer-s114-au-none, oer-s114-cat-none and oer-s114-ap-none do not exist.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] 3.2 valid: True; errors: 0; warnings: 1
[oer-s114] 3.2 finding: Warning | accessPackages[0].catalog | Catalog 'oer-s114-cat-b' is not declared in this document. It may already exist in the tenant.
[oer-s114] 3.2 plan rows: 3
[oer-s114] 3.2 plan row: administrativeUnits | oer-s114-au-none | Failed | neither 'oer-s114-au-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches an administrative unit, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new administrative unit, remove previousDisplayName
[oer-s114] 3.2 plan row: catalogs | oer-s114-cat-none | Failed | neither 'oer-s114-cat-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches a catalog, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new catalog, remove previousDisplayName
[oer-s114] 3.2 plan row: accessPackages | oer-s114-ap-none | Failed | neither 'oer-s114-ap-none' nor its previousDisplayName 'oer-s114-ap-ghost' matches an access package in catalog 'oer-s114-cat-b', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new access package, remove previousDisplayName
[oer-s114] 3.2 plan warnings: 0
[oer-s114] 3.2 plan error: AdministrativeUnitRenameNotFound,Invoke-OERStructure: Neither 'oer-s114-au-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches an administrative unit, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new administrative unit, remove previousDisplayName.
[oer-s114] 3.2 plan error: CatalogRenameNotFound,Invoke-OERStructure: Neither 'oer-s114-cat-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches a catalog, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new catalog, remove previousDisplayName.
[oer-s114] 3.2 plan error: AccessPackageRenameNotFound,Invoke-OERStructure: Neither 'oer-s114-ap-none' nor its previousDisplayName 'oer-s114-ap-ghost' matches an access package in catalog 'oer-s114-cat-b', so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new access package, remove previousDisplayName.
[oer-s114] 3.2 plan errors of Invoke-OERStructure: 3; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 3.2 plan sent: token requests: 0; Microsoft Graph requests: 6, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] 3.2 run rows: 3
[oer-s114] 3.2 run row: administrativeUnits | oer-s114-au-none | Failed | neither 'oer-s114-au-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches an administrative unit, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new administrative unit, remove previousDisplayName
[oer-s114] 3.2 run row: catalogs | oer-s114-cat-none | Failed | neither 'oer-s114-cat-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches a catalog, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new catalog, remove previousDisplayName
[oer-s114] 3.2 run row: accessPackages | oer-s114-ap-none | Failed | neither 'oer-s114-ap-none' nor its previousDisplayName 'oer-s114-ap-ghost' matches an access package in catalog 'oer-s114-cat-b', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new access package, remove previousDisplayName
[oer-s114] 3.2 run warnings: 0
[oer-s114] 3.2 run error: AdministrativeUnitRenameNotFound,Invoke-OERStructure: Neither 'oer-s114-au-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches an administrative unit, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new administrative unit, remove previousDisplayName.
[oer-s114] 3.2 run error: CatalogRenameNotFound,Invoke-OERStructure: Neither 'oer-s114-cat-none' nor its previousDisplayName '00000000-0000-0000-0000-000000000099' matches a catalog, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new catalog, remove previousDisplayName.
[oer-s114] 3.2 run error: AccessPackageRenameNotFound,Invoke-OERStructure: Neither 'oer-s114-ap-none' nor its previousDisplayName 'oer-s114-ap-ghost' matches an access package in catalog 'oer-s114-cat-b', so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new access package, remove previousDisplayName.
[oer-s114] 3.2 run errors of Invoke-OERStructure: 3; other items in -ErrorVariable (counted, not printed): 0
[oer-s114] 3.2 run sent: token requests: 0; Microsoft Graph requests: 6, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] oer-s114-au-none exists: False
[oer-s114] oer-s114-cat-none exists: False
[oer-s114] oer-s114-ap-none exists: False
RUNNER: check-3.2 exit code 0; started 2026-10-14T08:15:01Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.3. With the catalogs section left out, the package is refused as well

- [x] **3.3** The 3.1 document applied with `-Include AccessPackages` (the catalog's rename is not reconciled in this run) reports `oer-s114-ap-x` Failed and writes nothing, planned or run.

```powershell
Connect-OerLive -Arm
Start-S114NoPrompt
$Json = New-S114Document -Section @{
    catalogs       = @([ordered]@{ displayName = $CatB; previousDisplayName = $CatANew; resources = @() })
    accessPackages = @([ordered]@{ displayName = 'oer-s114-ap-x'; catalog = $CatB; resourceRoles = @() })
}
foreach ($Mode in 'plan', 'run') {
    [System.IO.File]::WriteAllText((Join-Path $Raw "doc-3.3-$Mode.json"), $Json, [System.Text.UTF8Encoding]::new($false))
    $Params = @{ Json = $Json; Include = 'AccessPackages'; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'E' }
    if ($Mode -eq 'plan') { $Params.WhatIf = $true } else { $Params.Confirm = $false }
    Start-S114Count
    try { $Out = @(Invoke-OERStructure @Params 3>&1); $Sent = Get-S114Sent } finally { Stop-S114Count }
    Write-S114Rows -Label "3.3 $Mode" -Rows @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-OerLiveStep "3.3 $Mode sent: $Sent"
}
Write-OerLiveStep "oer-s114-ap-x exists: $(@(Get-S114Id -Kind 'package' -Name 'oer-s114-ap-x').Count -gt 0)"
Disconnect-OerLive
```

**Expect:** in the plan and in the run exactly one row, Failed for `oer-s114-ap-x`, saying the catalog's
rename is not reconciled in this run because the catalogs section is not selected by `-Include`;
`writes: 0` both times; `oer-s114-ap-x exists: False`.
**Failure looks like:** a `would create` or Created row, a write, or `exists: True`.

Result: 2026-10-14 08:15 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The 3.1 document with -Include AccessPackages, planned and run: exactly one row, Failed for oer-s114-ap-x -- its catalog's rename is not reconciled in this run because the catalogs section is not selected by -Include (Ruling R12); nothing created, read or written for it; 0 Microsoft Graph requests at all, 0 writes, 0 token requests, both times; oer-s114-ap-x does not exist.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.3 ===
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] 3.3 plan rows: 1
[oer-s114] 3.3 plan row: accessPackages | oer-s114-ap-x | Failed | catalog 'oer-s114-cat-b' was not reconciled in this run: its rename from 'oer-s114-cat-a-new' was refused (the catalogs section is not selected by -Include, so its rename is not reconciled in this run), so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it
[oer-s114] 3.3 plan sent: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] 3.3 run rows: 1
[oer-s114] 3.3 run row: accessPackages | oer-s114-ap-x | Failed | catalog 'oer-s114-cat-b' was not reconciled in this run: its rename from 'oer-s114-cat-a-new' was refused (the catalogs section is not selected by -Include, so its rename is not reconciled in this run), so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it
[oer-s114] 3.3 run sent: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114] oer-s114-ap-x exists: False
RUNNER: check-3.3 exit code 0; started 2026-10-14T08:15:23Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## T. Teardown

### T.1. Remove every oer-s114- object

- [x] **T.1** The teardown deletes the administrative unit, then the packages, the policy, the catalogs and the groups; the sweep is clean and the counts are the baseline's.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS114Prereq.ps1'
foreach ($Run in @(@('-Teardown', '-WhatIf'), @('-Teardown', '-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS114Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -NonInteractive -File $Script @Run
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the plan writes nothing; the run removes the scoped role membership and the unit (Teardown
A), then OerLive's teardown removes the resource role, the policy, both packages, the catalog resource,
both catalogs and the three groups with no residue; the sweep reports no prefixed object; every count
equals the baseline's; exit code 0.
**Failure looks like:** a `RESIDUE` line or exit code 3 -- the row is in `raw\residue.json`; record it.

Result: 2026-10-14 08:21 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan removes nothing. The run: Teardown A removes the unit's scoped role membership (204) and deletes oer-s114-au-new (204); OerLive's teardown then still lists oer-s114-rolegrp's unit-scoped License Administrator assignment, waits out its five-minute rule, and its removal answers 404 and reads back as no longer listed (counted removed); it removes the resource role binding, the policy, both packages, the catalog resource and both catalogs, and deletes the three groups: removed 11, residue 0, unreadable 0. The sweep reports no prefixed object, and every count equals the baseline's (groups 97, administrative units 1, catalogs 5, access packages 6). Exit code 0; took 363 s (the five-minute rule).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[oer-s114] === Initialize-OerS114Prereq.ps1 -Teardown -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s114\teardown-20261014-081542Z.log".
[oer-s114] Mode: REMOVE. Prefix 'oer-s114-'. Objects (fixed): oer-s114-member, oer-s114-resgrp (security groups, no member); oer-s114-rolegrp (role-assignable, no member, no owner); oer-s114-au (member oer-s114-member, one scoped role for oer-s114-rolegrp); oer-s114-cat-a (resource oer-s114-resgrp) with oer-s114-ap-a (hidden; resource role Member of oer-s114-resgrp; policy oer-s114-pol-a, administrator assignments only); oer-s114-cat-b with oer-s114-ap-b (hidden, nothing in it). The checklist renames oer-s114-au, oer-s114-cat-a, oer-s114-ap-a and oer-s114-ap-b to the same names with '-new' appended. OerLive 1.0.3.
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
What if: Performing the operation "Remove (Graph v1.0 DELETE directory/administrativeUnits/scopedRoleMembers)" on target "oer-s114-au-new: scoped role membership of oer-s114-rolegrp".
What if: Performing the operation "Delete the administrative unit (Graph v1.0 DELETE directory/administrativeUnits)" on target "oer-s114-au-new".
[oer-s114] Teardown of 'oer-s114-': users 0, groups 3, access packages 2, catalogs 2; administrative units 1 and app registrations 0 are reported only.
[oer-s114] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s114] oer-s114-rolegrp: active 'License Administrator' assignment at directory scope '/administrativeUnits/00000000-0000-0000-0000-000000000004': would wait 305 s: Microsoft Graph refuses to change or remove a principal's directory role assignments until its active assignment of that role has run for five minutes.
What if: Performing the operation "Remove (Graph v1.0 schedule request, adminRemove)" on target "oer-s114-rolegrp: active 'License Administrator' assignment at directory scope '/administrativeUnits/00000000-0000-0000-0000-000000000004'".
[oer-s114] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s114] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
What if: Performing the operation "Delete the access package (Graph v1.0 DELETE accessPackages)" on target "oer-s114-ap-b-new".
What if: Performing the operation "Remove (Graph v1.0 DELETE resourceRoleScopes)" on target "oer-s114-ap-a-new: resource role binding 'Member'".
What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s114-ap-a-new: assignment policy 'oer-s114-pol-a'".
What if: Performing the operation "Delete the access package (Graph v1.0 DELETE accessPackages)" on target "oer-s114-ap-a-new".
What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s114-cat-b".
What if: Performing the operation "Remove (Graph v1.0 resourceRequests, adminRemove)" on target "oer-s114-cat-a-new: resource 'oer-s114-resgrp'".
What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s114-cat-a-new".
[oer-s114] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s114] Teardown 5/6: the prefixed groups.
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s114-member".
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s114-resgrp".
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s114-rolegrp".
[oer-s114] Teardown 6/6: the prefixed users.
[oer-s114] Teardown of 'oer-s114-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
[oer-s114] WhatIf: nothing was created, removed or written.
[oer-s114] Done.
[oer-s114] exit code: 0
[oer-s114] === Initialize-OerS114Prereq.ps1 -Teardown -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114] Transcript (redacted): raw\s114\teardown-20261014-081556Z.log; OerLive 1.0.3.
[oer-s114] Mode: REMOVE. Prefix 'oer-s114-'. Objects (fixed): oer-s114-member, oer-s114-resgrp (security groups, no member); oer-s114-rolegrp (role-assignable, no member, no owner); oer-s114-au (member oer-s114-member, one scoped role for oer-s114-rolegrp); oer-s114-cat-a (resource oer-s114-resgrp) with oer-s114-ap-a (hidden; resource role Member of oer-s114-resgrp; policy oer-s114-pol-a, administrator assignments only); oer-s114-cat-b with oer-s114-ap-b (hidden, nothing in it). The checklist renames oer-s114-au, oer-s114-cat-a, oer-s114-ap-a and oer-s114-ap-b to the same names with '-new' appended. OerLive 1.0.3.
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s114] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114] Teardown A: removed oer-s114-au-new: scoped role membership of oer-s114-rolegrp (204).
[oer-s114] Teardown A: deleted administrative unit oer-s114-au-new (204).
[oer-s114] Teardown of 'oer-s114-': users 0, groups 3, access packages 2, catalogs 2; administrative units 1 and app registrations 0 are reported only.
[oer-s114] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s114] oer-s114-rolegrp: active 'License Administrator' assignment at directory scope '/administrativeUnits/00000000-0000-0000-0000-000000000004': waiting 305 s: Microsoft Graph refuses to change or remove a principal's directory role assignments until its active assignment of that role has run for five minutes.
[oer-s114] oer-s114-rolegrp: active 'License Administrator' assignment at directory scope '/administrativeUnits/00000000-0000-0000-0000-000000000004' answered 404 ResourceNotFound -- The resource is not found.; reading back before it counts as removed.
[oer-s114] oer-s114-rolegrp: active 'License Administrator' assignment at directory scope '/administrativeUnits/00000000-0000-0000-0000-000000000004': read back after the 'does not exist' answer: converged after 1 read(s), 1.5 s.
[oer-s114] Removed: oer-s114-rolegrp: active 'License Administrator' assignment at directory scope '/administrativeUnits/00000000-0000-0000-0000-000000000004' (404; read back: no longer listed after 1 read(s), 1.5 s).
[oer-s114] oer-s114-rolegrp: no direct directory role schedule listed: converged after 1 read(s), 1 s.
[oer-s114] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s114] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s114] Deleted: access package oer-s114-ap-b-new (204, 1 attempt(s)).
[oer-s114] Removed: oer-s114-ap-a-new: resource role binding 'Member' (200).
[oer-s114] Deleted: oer-s114-ap-a-new: assignment policy 'oer-s114-pol-a' (204).
[oer-s114] Deleted: access package oer-s114-ap-a-new (204, 1 attempt(s)).
[oer-s114] Deleted: catalog oer-s114-cat-b (204, 1 attempt(s)).
[oer-s114] Removed: oer-s114-cat-a-new: resource 'oer-s114-resgrp' (201).
[oer-s114] Deleted: catalog oer-s114-cat-a-new (204, 1 attempt(s)).
[oer-s114] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s114] Teardown 5/6: the prefixed groups.
[oer-s114] Deleted: group oer-s114-member (204).
[oer-s114] Deleted: group oer-s114-resgrp (204).
[oer-s114] Deleted: group oer-s114-rolegrp (204).
[oer-s114] Teardown 6/6: the prefixed users.
[oer-s114] Teardown of 'oer-s114-': removed 11, residue 0, unreadable 0.
[oer-s114] no 'oer-s114-' object is listed: not yet (read 1, 0.4 s, likely replication delay) -- reading again in 2 s.
[oer-s114] no 'oer-s114-' object is listed: not yet (read 2, 2.8 s, likely replication delay) -- reading again in 4 s.
[oer-s114] no 'oer-s114-' object is listed: not yet (read 3, 7.2 s, likely replication delay) -- reading again in 8 s.
[oer-s114] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s114-' is left.
[oer-s114] no 'oer-s114-' object is listed: converged after 4 read(s), 15.7 s.
[oer-s114] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s114-' is left.
[oer-s114] Counts: groups now 97, at the baseline 97; equal: True
[oer-s114] Counts: administrativeUnits now 1, at the baseline 1; equal: True
[oer-s114] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s114] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s114] Removed the recorded ids.
[oer-s114] Done.
[oer-s114] exit code: 0
RUNNER: check-T.1 exit code 0; started 2026-10-14T08:15:40Z; took 363 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### T.2. Read back

- [x] **T.2** A read-back a minute later finds no prefixed object, the baseline's counts and no residue row of this step.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS114Prereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -ReadBack
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `prefixed objects left: 0`, every count equal, `of them with this step's prefix: 0`.
**Failure looks like:** a prefixed object (a listing that lags: run again a minute later) or a residue row.

Result: 2026-10-14 08:23 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. A read-back about a minute after the teardown: no prefixed object is left, every count equals the baseline's, and raw\residue.json holds 5 rows of other projects and none of this step's.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.2 ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114] Transcript (redacted): raw\s114\readback-20261014-082308Z.log; OerLive 1.0.3.
[oer-s114] Mode: READ BACK. Prefix 'oer-s114-'. Objects (fixed): oer-s114-member, oer-s114-resgrp (security groups, no member); oer-s114-rolegrp (role-assignable, no member, no owner); oer-s114-au (member oer-s114-member, one scoped role for oer-s114-rolegrp); oer-s114-cat-a (resource oer-s114-resgrp) with oer-s114-ap-a (hidden; resource role Member of oer-s114-resgrp; policy oer-s114-pol-a, administrator assignments only); oer-s114-cat-b with oer-s114-ap-b (hidden, nothing in it). The checklist renames oer-s114-au, oer-s114-cat-a, oer-s114-ap-a and oer-s114-ap-b to the same names with '-new' appended. OerLive 1.0.3.
[oer-s114] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s114-' is left.
[oer-s114] Counts: groups now 97, at the baseline 97; equal: True
[oer-s114] Counts: administrativeUnits now 1, at the baseline 1; equal: True
[oer-s114] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s114] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s114] Read-back: residue row: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:09Z, attempts 3: 404 SubjectNotFound The subject is not found.; read back: still listed -- OerLive: Residue: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal': read back after the 'does not exist' answer -- not converged within budget (180 s, 10 reads).
[oer-s114] Read-back: residue row: PIM for Groups assignment 'opim-s1-grp: PIM for Groups owner assignment of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:12Z, attempts 3: 403 UnauthorizedAccessException {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup,PrivilegedAccess.ReadWrite.AzureADGroup,PrivilegedAssignmentSchedule.Remove.AzureADGroup.","instanceAnnotations":[]}
[oer-s114] Read-back: residue row: PIM for Groups eligibility 'opim-s2-grp: PIM for Groups member eligibility of a principal' (prefix opim-s2-), first refused 2026-10-10T23:39:01Z, attempts 1: 400 BadRequest {"error":{"code":"Request_BadRequest","message":"The source resource object or one of the objects being referenced do not exist.","innerError":{"date":"2026-10-10T23:39:01","request-id":"00000000-0000-0000-0000-000000000005","client-request-id":"00000000-0000-0000-0000-000000000006"}}}
[oer-s114] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-10T23:39:02Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s114] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-11T14:55:13Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s114] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 5, of them with this step's prefix: 0.
[oer-s114] Done.
[oer-s114] exit code: 0
RUNNER: check-T.2 exit code 0; started 2026-10-14T08:23:06Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## B. Proved offline only (class B)

These are held by unit tests that run in CI (the gate), not by this file:

- **A group created in the same run into a unit the same document renames**, by the unit's new name (the
  pre-pass finds the unit under its previous name and the group is created into it by id), and the
  BL-07 withhold of that membership under `-Prune`, by its new or its previous name:
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`, Describe 'Invoke-OERStructure renames an
  administrative unit, a catalog and an access package in one run (BL-128, A5)';
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1`, Context 'a group created into an administrative
  unit the run renames (BL-128, A5)'; `tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1`,
  Context 'previousDisplayName (BL-128)'.
- **A rename the run cannot decide** (a lookup of one of its names throws, also transiently; its section
  left out by `-Include` -- the latter also live in 3.3): the Contexts 'a rename this run cannot decide
  (R12)' in the administrative unit and catalog handler tests, and the engine Describe above.
- **An ambiguous previous name, a failed rename (the item stops), an object id in another letter case, a
  case-only rename**: the Contexts 'previousDisplayName (BL-128)' of the administrative unit and catalog
  handler tests, the Describe 'Sync-OERStructureAccessPackage -previousDisplayName and the rename map
  (BL-128, A5)', and `tests/Unit/Private/Resolve-OERStructureRename.Tests.ps1`.
- **The validator** (the non-empty string, the case-only Warning, the duplicate claim, the old-name
  reference Warnings, step 3's Error kept for policies and reviews):
  `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1`, Describe 'Test-OERStructureSchema renames of
  administrative units, catalogs and access packages (BL-128, A5)' and Context 'previousDisplayName on
  assignment policies and access reviews (BL-128, A5)'; the schema in
  `tests/Unit/Private/Get-OERStructureSchemaJson.Tests.ps1`.
- **The texts**: `tests/QA/about.tests.ps1`, `tests/QA/docsync.tests.ps1`, `tests/QA/dochygiene.tests.ps1`,
  `tests/QA/module.tests.ps1` (help and the release note), and
  `tests/Unit/Private/Get-OERInventoryPromptTemplate.Tests.ps1`.
