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

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch, and the main clone is on `main`, never switched.

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

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

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

Result:

### 0.2. The permissions this file needs

- [ ] **0.2** `oer-live-cc` holds the four permissions; otherwise the run stops here (the role permission alone makes the scoped role class B).

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

Result:

### 0.3. The prerequisite objects

- [ ] **0.3** The plan writes nothing; the first run creates the objects (or brings back what an earlier run renamed); a second run writes nothing.

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

Result:

## 1. The rename in place

### 1.1. The ids before the rename

- [ ] **1.1** Every object is found exactly once under its own name; the ids, and what each object holds, are recorded under `raw\s114\` (never printed).

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

Result:

### 1.2. The validator accepts the rename document

- [ ] **1.2** `Test-OERStructure` reports the document valid, with no Error.

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

Result:

### 1.3. The plan renames in place and writes nothing

- [ ] **1.3** Under `-WhatIf` each of the four objects is reported `would rename` from its previous name to its new name, its collections are planned against the object found under its previous name (Unchanged), and nothing is written.

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

Result:

### 1.4. The run renames in place

- [ ] **1.4** The run renames the four objects, each in one PATCH, and writes nothing else.

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

Result:

### 1.5. Read back by id: the same objects, the new names, nothing lost, nothing created

- [ ] **1.5** Each object read by the id recorded in 1.1 carries its new name; its members, scoped role, resources, resource role and policy are the same ones; the sweep lists the same prefixed objects as before the rename.

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

Result:

## 2. The same document again converges (G8)

### 2.1. The new names resolve

- [ ] **2.1** Microsoft Graph's name lookup finds each object under its new name, three times in a row, before the convergence runs.

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

Result:

### 2.2. The same document twice more: only Unchanged

- [ ] **2.2** Two runs of the 1.4 document report only Unchanged rows and write nothing.

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

Result:

### 2.3. With -Prune, the plan removes nothing

- [ ] **2.3** `-Prune -WhatIf` on the same document plans no removal and writes nothing.

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

Result:

## 3. A conflict, and names nothing carries, write nothing

### 3.1. Two different catalogs under the two names

- [ ] **3.1** A catalog entry whose new name is `oer-s114-cat-b` and whose previous name is `oer-s114-cat-a-new` (two different catalogs) fails with `CatalogRenameConflict`, and a package entry in `oer-s114-cat-b` is not created: planned or run, nothing is written.

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

Result:

### 3.2. Neither name matches: nothing is created

- [ ] **3.2** A unit and a catalog whose previous name is an object id nothing carries, and a package whose two names nothing in its catalog carries, each fail with `<Kind>RenameNotFound`; planned or run, nothing is created or written.

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

Result:

### 3.3. With the catalogs section left out, the package is refused as well

- [ ] **3.3** The 3.1 document applied with `-Include AccessPackages` (the catalog's rename is not reconciled in this run) reports `oer-s114-ap-x` Failed and writes nothing, planned or run.

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

Result:

## T. Teardown

### T.1. Remove every oer-s114- object

- [ ] **T.1** The teardown deletes the administrative unit, then the packages, the policy, the catalogs and the groups; the sweep is clean and the counts are the baseline's.

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

Result:

### T.2. Read back

- [ ] **T.2** A read-back a minute later finds no prefixed object, the baseline's counts and no residue row of this step.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS114Prereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -ReadBack
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `prefixed objects left: 0`, every count equal, `of them with this step's prefix: 0`.
**Failure looks like:** a prefixed object (a listing that lags: run again a minute later) or a residue row.

Result:

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
