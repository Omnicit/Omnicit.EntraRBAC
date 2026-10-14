# Live verification checklist -- rename assignment policies and access reviews in place (feat/rename-policies-and-reviews)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4, 5 and T has a written
result.** A box with no result line filled in is not a passed check -- it is an unrun one. If a check
turns out to be impossible to run, write "cannot be verified, and therefore we do not know" on its result
line and say why; do not leave it blank and do not tick it. A check that could not run for a stated
reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).** This step
has no manual check (class C).

**What this file writes to the tenant: only inside the prefix `oer-s114b-`.** The prerequisite script
`Initialize-OerS114bPrereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates a security group with no member, `oer-s114b-grp`; a catalog `oer-s114b-cat` with no resource; a
hidden access package `oer-s114b-ap` in it with no resource role and two assignment policies through
which only the members of `oer-s114b-grp` (none) may request: `oer-s114b-pol-a`, with one optional
question and one custom extension stage, and `oer-s114b-pol-b`, with neither; the custom extension
`oer-s114b-ext`, whose endpoint is a Logic App `oer-s114b-la` that nothing calls, in a tagged resource
group `oer-s114b-rg`; an access review `oer-s114b-ar` of the package's assignments under
`oer-s114b-pol-b`; and an access review `oer-s114b-gr` of the members of `oer-s114b-grp`. Both reviews
start 14 days after the run, so no instance runs and nobody is asked anything. Section 1 renames
`oer-s114b-pol-a` and `oer-s114b-ar` through `Invoke-OERStructure`, section 3 renames the package; each
gets `-new` appended to its name, and nothing else is changed. Sections 2, 4 and 5 must write nothing.
Nobody is assigned anything. The teardown (T.1) deletes the two reviews, then the policy holding the
custom extension stage and the custom extension, then the other policy, the package, the catalog and the
group, then the resource group with the Logic App. Documents, the ids read before the renames and request
counts are written under `raw\s114b\`, which is deleted after the results are written.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401
or 403 as `oer-live-cc` is a stop.

**Permissions.** The objects need the Microsoft Graph application permissions
`EntitlementManagement.ReadWrite.All`, `AccessReview.ReadWrite.All` and `Group.ReadWrite.All`; check
0.2 reads them and STOPS the run before anything is written when one is missing, and the prerequisite
script refuses its setup the same way. The custom extension and its Logic App need the identity's
existing Azure role on the test subscription; when Azure Resource Manager or Microsoft Graph refuses
one of them, the prerequisite script says so and carries on without the stage, and the stage half of
1.5 becomes class B. Granting a permission is the operator's decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block installs
the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s114b/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line, a warning and an error that
stops a script go straight to the host, so each block is run in its own process whose WHOLE output
(standard output and standard error) is written to a file under `raw\s114b\`, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. One rename decision for two more kinds** ("feat: let the rename helpers decide assignment policies
  and access reviews"). `Resolve-OERStructureRename` decides for a policy within its package and for a
  review: two different objects -> `AssignmentPolicyRenameConflict` / `AccessReviewRenameConflict`;
  neither -> `AssignmentPolicyRenameNotFound` / `AccessReviewRenameNotFound`, nothing created; only the
  previous name -> the object is renamed; otherwise the entry is applied as before. A policy's entry in the
  run's rename map is keyed by its package's name and, once known, the package's id.
- **B. A policy renamed alone** ("feat: rename an assignment policy with -DisplayName alone (A16)", "fix:
  state when the policy name is sent and pin the A16 decision order"). `Set-OERAccessPackageAssignmentPolicy`
  sends a `-DisplayName` that differs from the live name as an update, alone too; the same name ignoring
  case with nothing else is still `NothingToUpdate`, after one read.
- **C. The handlers rename in place** ("feat: rename assignment policies in place and register package and
  policy renames in the run map", "fix: prove the empty-name mark skips and name a policy renamed by id by
  its current name", "feat: rename an access review in place through previousDisplayName", "fix: name the
  review an access review rename found, and keep its help true", "fix: stop an access review entry whose
  rename decision could not be made"). The policy is renamed in the same PUT as its other changes, carrying
  its custom extension stages and automatic settings; the review found under either name passes the step 2
  target check before it is renamed in the same update as its other changes.
- **D. References in the same run** ("feat: let an access review reach a package or policy the same run
  renames", "fix: refuse a review that names a package by id while the policy rename is undecided", "fix:
  mark a renaming policy under every package id an access package entry knows when it stops", "test: prove
  a review is refused when the package entry stops before its rename decision"). A review naming the new
  name of a package or policy the same document renames reaches it by id; a refused or undecided rename
  refuses the review.
- **E. The validator** ("feat: accept and check previousDisplayName on assignment policies and access
  reviews in the offline validator and schema", "test: prove the shape guards and null elements of the
  policy rename checks", "fix: refuse a review naming an access package two renamed entries declare").
- **F. A failed catalog read** ("fix: report a failed catalog read as itself instead of an empty fact
  (BL-144)").
- **G. The texts** ("docs: describe renaming assignment policies and access reviews, and the catalog read
  fix", "docs: state the six renameable kinds in Invoke-OERStructure and the narrowed by-id residual", "docs:
  make the policy and review rename texts exact").

A live tenant is needed because the claim is about what the engine does against Microsoft Graph: that
the policy and the review found under their previous names are renamed IN PLACE (same object id) and
keep their settings -- for the policy the custom extension stage, the question and the allowed target;
for the review its scope; that `Set-OERAccessPackageAssignmentPolicy` really sends a rename alone; that
a review naming the new name of a package renamed in the same run reaches that package; that the same
document applied again converges; and that a conflict, a name nothing carries, and a review of a group
found under a package review's previous name write nothing.

## What this file does not check, and why

- **A review naming the new name of a POLICY renamed in the same run (class B).** The package's review
  reviews `oer-s114b-pol-b`, and a review's policy cannot be changed; a second review of `oer-s114b-pol-a`
  would add a write path the step's claim does not need. The unit tests named in section B hold the
  translation, and the refusal when that rename was refused or undecided.
- **An ambiguous previous name, a failed rename, a rename the run cannot decide, and Microsoft Graph's
  lag after a rename (class B).** None can be produced on demand with the prefix alone; the unit tests
  hold the refusals.
- **A failed read of a catalog or its resources (BL-144, class B).** A read cannot be made to fail on
  demand; the unit tests hold that the entry is Failed and nothing is written.
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
- The **prerequisite objects**: check 0.3 runs `Initialize-OerS114bPrereq.ps1 -WhatIf`, then
  `-Unattended` twice, with `OER_LIVE_REPO` set.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the
counters, the readers and the documents. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s114b-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Ar = 'v1.0/identityGovernance/accessReviews/definitions'
$Group = 'oer-s114b-grp'; $Cat = 'oer-s114b-cat'
$Ap = 'oer-s114b-ap'; $ApNew = 'oer-s114b-ap-new'
$PolA = 'oer-s114b-pol-a'; $PolANew = 'oer-s114b-pol-a-new'; $PolB = 'oer-s114b-pol-b'
$Rev = 'oer-s114b-ar'; $RevNew = 'oer-s114b-ar-new'; $GroupRev = 'oer-s114b-gr'
$QuestionText = 'oer-s114b: an optional question that a rename must keep'
# The step's raw folder as OerLive fixed it (git-ignored).
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Needed = @('EntitlementManagement.ReadWrite.All', 'AccessReview.ReadWrite.All', 'Group.ReadWrite.All')

function Start-S114bNoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S114bTokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S114bTokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S114b fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S114bCount {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is
    # a GET. The path of every request is recorded too (the module's relative Graph path as it is sent,
    # the query dropped).
    $global:S114bGraph = [System.Collections.Generic.List[string]]::new()
    $global:S114bArm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(if ([uri]::IsWellFormedUriString([string]$Uri, [System.UriKind]::Absolute)) { ([uri][string]$Uri).AbsolutePath } else { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S114bGraph.Add((`$($Record)) + ' ' + $Path); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S114bArm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S114bCount {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S114bSent {
    # Requests counted since Start-S114bCount: totals and writes (any method but GET), with the write paths.
    $GraphWrites = @($global:S114bGraph | Where-Object { -not $_.StartsWith('GET ') })
    $ArmWrites = @($global:S114bArm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S114bTokenCalls; Microsoft Graph requests: $($global:S114bGraph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S114bArm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" })"
}

function Get-S114bGrantedRole {
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

function Get-S114bList {
    # A collection read raw and whole, unwrapped (the caller wraps the result in @()).
    param([Parameter(Mandatory)][string]$Uri)
    $R = Invoke-OerLiveGraph -All -Uri $Uri
    Assert-OerLiveOk -Response $R -Activity 'Reading a collection' | Out-Null
    @($R.Body['value']) | Where-Object { $null -ne $_ }
}

function Get-S114bId {
    # The ids of every object of a kind whose display name is exactly the name, read raw (never printed),
    # unwrapped: every caller wraps the result in @().
    param([Parameter(Mandatory)][ValidateSet('package', 'policy', 'review', 'group')][string]$Kind, [Parameter(Mandatory)][string]$Name, [string]$PackageId)
    $Uri = switch ($Kind) {
        'package' { "$Em/accessPackages?`$select=id,displayName" }
        'policy' { "$Em/assignmentPolicies?`$filter=$([uri]::EscapeDataString("accessPackage/id eq '$PackageId'"))" }
        'review' { $Ar }
        'group' { "v1.0/groups?`$filter=$([uri]::EscapeDataString("displayName eq '$Name'"))&`$select=id,displayName" }
    }
    @(Get-S114bList -Uri $Uri) | Where-Object { [string]$_['displayName'] -ceq $Name } | ForEach-Object { ([string]$_['id']).ToLowerInvariant() }
}

function Read-S114bPolicyFull {
    # One policy read by id with its custom extension stages expanded.
    param([Parameter(Mandatory)][string]$Id)
    $R = Invoke-OerLiveGraph -Uri "$Em/assignmentPolicies/$Id`?`$expand=customExtensionStageSettings(`$expand=customExtension)"
    Assert-OerLiveOk -Response $R -Activity 'Reading a policy with its custom extension stages' | Out-Null
    $R.Body
}

function ConvertTo-S114bCanonical {
    # A value as JSON with every dictionary's keys sorted: Microsoft Graph does not return keys in a fixed
    # order, so two reads of one unchanged object compare equal only in a canonical form.
    param([AllowNull()][object]$Value)
    $Sort = {
        param($V)
        if ($V -is [System.Collections.IDictionary]) {
            $O = [ordered]@{}
            foreach ($K in @($V.Keys | Sort-Object)) { $O[[string]$K] = & $Sort $V[$K] }
            return $O
        }
        if ($V -is [System.Collections.IEnumerable] -and $V -isnot [string]) { return , @(@($V) | ForEach-Object { & $Sort $_ }) }
        $V
    }
    ConvertTo-Json -InputObject (& $Sort $Value) -Depth 12 -Compress
}

function Get-S114bSnapshot {
    # The step's objects read by id: their names and what they hold (ids never printed), and every
    # prefixed object and access review the sweep lists. Takes the ids recorded in raw\s114b\before.json.
    param([Parameter(Mandatory)][hashtable]$Ids)
    $S = [ordered]@{}
    $S.PackageName = [string](Invoke-OerLiveGraph -Uri "$Em/accessPackages/$($Ids.Package)?`$select=displayName").Body['displayName']
    $S.PackagePolicies = @(@(Get-S114bList -Uri ("$Em/assignmentPolicies?`$filter={0}" -f [uri]::EscapeDataString("accessPackage/id eq '$($Ids.Package)'"))) | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } | Sort-Object)
    $A = Read-S114bPolicyFull -Id $Ids.PolA
    $S.PolAName = [string]$A['displayName']
    $S.PolAQuestion = @(@($A['questions']) | Where-Object { $null -ne $_ -and [string]$_['text'] -ceq $QuestionText }).Count -eq 1
    $S.PolAStages = @(@($A['customExtensionStageSettings']) | Where-Object { $null -ne $_ } | ForEach-Object { "$([string]$_['stage'])|$(([string]$_['customExtension']['id']).ToLowerInvariant())" } | Sort-Object)
    $S.PolATargets = @(@($A['specificAllowedTargets']) | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_['groupId']).ToLowerInvariant() } | Sort-Object)
    $S.PolAScope = [string]$A['allowedTargetScope']
    $B = Read-S114bPolicyFull -Id $Ids.PolB
    $S.PolBName = [string]$B['displayName']
    $S.PolBTargets = @(@($B['specificAllowedTargets']) | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_['groupId']).ToLowerInvariant() } | Sort-Object)
    $R = (Invoke-OerLiveGraph -Uri "$Ar/$($Ids.Review)").Body
    $S.ReviewName = [string]$R['displayName']
    $S.ReviewQuery = [string]$R['scope']['query']
    $S.ReviewSettings = ConvertTo-S114bCanonical -Value $R['settings']
    $G = (Invoke-OerLiveGraph -Uri "$Ar/$($Ids.GroupReview)").Body
    $S.GroupReviewName = [string]$G['displayName']
    $S.GroupReviewQuery = [string]$G['scope']['query']
    $S.Reviews = @(@(Get-S114bList -Uri $Ar) | Where-Object { ([string]$_['displayName']).StartsWith('oer-s114b-', [System.StringComparison]::Ordinal) } | ForEach-Object { ([string]$_['id']).ToLowerInvariant() } | Sort-Object)
    $S.Prefixed = @(@(Find-OerLivePrefixed -ThrowOnUnread -Quiet) | ForEach-Object { "$($_.Kind)|$($_.Id)" } | Sort-Object)
    $S
}

function Write-S114bCompare {
    # Compares two snapshots field by field: names are printed, ids only as True/False.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][System.Collections.IDictionary]$Before, [Parameter(Mandatory)][System.Collections.IDictionary]$After, [string[]]$Renamed)
    foreach ($K in @($Before.Keys)) {
        $B = $Before[$K]; $A = $After[$K]
        $Same = (ConvertTo-S114bCanonical -Value $B) -ceq (ConvertTo-S114bCanonical -Value $A)
        if ($K -like '*Name') { Write-OerLiveStep "$Label $($K): before '$B', now '$A'; unchanged: $Same" }
        else { Write-OerLiveStep "$Label $($K): unchanged: $Same$(if ($B -is [array]) { " ($(@($B).Count) item(s) before, $(@($A).Count) now)" })" }
    }
}

function New-S114bDocument {
    # A structure document (JSON) holding the given sections.
    param([hashtable]$Section)
    $Doc = [ordered]@{ version = '1.0' }
    foreach ($K in @($Section.Keys | Sort-Object)) { $Doc[$K] = @($Section[$K]) }
    $Doc | ConvertTo-Json -Depth 20
}

function New-S114bPackageEntry {
    # The package entry: its catalog, no resource role, and the given policy entries.
    param([Parameter(Mandatory)][string]$Name, [string]$Previous, [Parameter(Mandatory)][object[]]$Policies)
    $E = [ordered]@{ displayName = $Name }
    if ($Previous) { $E.previousDisplayName = $Previous }
    $E.catalog = $Cat
    $E.resourceRoles = @()
    $E.assignmentPolicies = @($Policies)
    $E
}

function New-S114bReviewEntry {
    # A review entry of the package's assignments under policy B, a self review (as the live one is).
    param([Parameter(Mandatory)][string]$Name, [string]$Previous, [Parameter(Mandatory)][string]$Package)
    $E = [ordered]@{ displayName = $Name }
    if ($Previous) { $E.previousDisplayName = $Previous }
    $E.accessPackage = $Package
    $E.assignmentPolicy = $PolB
    $E.reviewers = @()
    $E
}

function New-S114bDocument1 {
    # Section 1: policy A and the package review renamed in place; the package keeps its name.
    New-S114bDocument -Section @{
        catalogs       = @([ordered]@{ displayName = $Cat; resources = @() })
        accessPackages = @(New-S114bPackageEntry -Name $Ap -Policies @([ordered]@{ displayName = $PolANew; previousDisplayName = $PolA }, [ordered]@{ displayName = $PolB }))
        accessReviews  = @(New-S114bReviewEntry -Name $RevNew -Previous $Rev -Package $Ap)
    }
}

function New-S114bDocument3 {
    # Section 3: the package renamed in place, and the review naming the package's NEW name in the same run.
    New-S114bDocument -Section @{
        catalogs       = @([ordered]@{ displayName = $Cat; resources = @() })
        accessPackages = @(New-S114bPackageEntry -Name $ApNew -Previous $Ap -Policies @([ordered]@{ displayName = $PolANew; previousDisplayName = $PolA }, [ordered]@{ displayName = $PolB }))
        accessReviews  = @(New-S114bReviewEntry -Name $RevNew -Previous $Rev -Package $ApNew)
    }
}

function Read-S114bIds {
    # The ids recorded by 1.1 under raw\s114b (never printed).
    $Path = Join-Path $Raw 'before.json'
    if (-not (Test-Path -LiteralPath $Path)) { throw 'STOP: raw\s114b\before.json is missing; run 1.1 first.' }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Wait-S114bNames {
    # Microsoft Graph's listings name each object under the wanted name, three reads in a row, 10 s apart.
    param([Parameter(Mandatory)][object[]]$Wanted)
    $Steady = 0; $Reads = 0
    while ($Steady -lt 3 -and $Reads -lt 40) {
        $Reads++
        $Ok = @($Wanted | Where-Object { $Hit = @(Get-S114bId -Kind $_[0] -Name $_[1] -PackageId $_[3]); $Hit.Count -eq 1 -and $Hit[0] -eq $_[2] }).Count -eq $Wanted.Count
        $Steady = if ($Ok) { $Steady + 1 } else { 0 }
        if ($Steady -lt 3) { Start-Sleep -Seconds 10 }
    }
    Write-OerLiveStep "Every wanted name resolves to the recorded id, three reads in a row: $($Steady -ge 3) ($Reads read(s))"
}

function Write-S114bRows {
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Rows)
    # An if-statement assignment unrolls no rows to $null, and @($null).Count is 1: drop nulls first.
    $Rows = @(@($Rows) | Where-Object { $null -ne $_ })
    Write-OerLiveStep "$Label rows: $($Rows.Count)"
    foreach ($R in @($Rows)) { Write-OerLiveStep "$Label row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
}

function Write-S114bValidation {
    # Test-OERStructure's verdict and every finding, by severity, path and message.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json)
    $V = Test-OERStructure -Json $Json
    Write-OerLiveStep "$Label valid: $($V.Valid); errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count); warnings: $(@($V.Errors | Where-Object Severity -eq 'Warning').Count)"
    foreach ($F in @($V.Errors)) { Write-OerLiveStep "$Label finding: $($F.Severity) | $($F.Path) | $($F.Message)" }
}

function Invoke-S114bApply {
    # One Invoke-OERStructure call -- a -WhatIf plan or a run, with or without -Prune -- counted from its
    # first request to its last. The document is kept under raw\s114b. Warnings are captured on the stream
    # (3>&1), where each is written once, and printed through the redactor.
    # -NoCount runs without the counting proxies. A proxy is a global function: when the module's
    # transport calls Invoke-MgGraphRequest with -StatusCodeVariable (its -ExpectedErrorCode path), the
    # real cmdlet sets that variable in the PROXY's scope, so the transport cannot read the status and an
    # answer with an empty error code is not matched (measured in 4.3: 404 with an empty code reads as
    # GraphError under the proxy, as NotFound without it). A check that needs that path counts otherwise.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json, [switch]$Plan, [switch]$Prune, [switch]$NoCount)
    [System.IO.File]::WriteAllText((Join-Path $Raw ('doc-{0}.json' -f ($Label -replace '[^0-9A-Za-z.]', '_'))), $Json, [System.Text.UTF8Encoding]::new($false))
    $Params = @{ Json = $Json; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'E' }
    if ($Plan) { $Params.WhatIf = $true } else { $Params.Confirm = $false }
    if ($Prune) { $Params.Prune = $true }
    if (-not $NoCount) { Start-S114bCount }
    $E = $null
    try {
        $Out = @(Invoke-OERStructure @Params 3>&1)
        $Sent = if ($NoCount) { "not counted (-NoCount); token requests: $global:S114bTokenCalls" } else { Get-S114bSent }
    } finally { if (-not $NoCount) { Stop-S114bCount } }
    $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
    Write-S114bRows -Label $Label -Rows @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
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
Write-OerLiveStep "The worktree's build decides policy and review renames: $(& $Has "Prefix = 'AssignmentPolicy'") $(& $Has "Prefix = 'AccessReview'")"
Write-OerLiveStep "The worktree's build lets a review read the rename map: $(& $Has "Get-OERStructureRenameTarget -Section 'assignmentPolicies' -Name `$PolicyRef")"
Write-OerLiveStep "The worktree's build marks a renaming policy under every known package id: $(& $Has 'function Register-OERPolicyUndecidedMark')"
Write-OerLiveStep "The worktree's build sends a policy rename alone (A16): $(& $Has '[string]$Existing.displayName -ieq $DisplayName')"
Write-OerLiveStep "The worktree's build probes a review id with the declared not-found codes: $(& $Has "-ExpectedErrorCode 'NotFound', 'ResourceNotFound', 'Request_ResourceNotFound'")"
Write-OerLiveStep "The worktree's build refuses a review naming a shared renamed package name (Rule 15): $(& $Has 'so the run cannot tell which access package the review means')"
Write-OerLiveStep "The worktree's build reads a catalog with -ErrorAction Stop (BL-144): $(& $Has '$Cur = Get-OERCatalog -Id $CatId -ErrorAction Stop')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree on this branch with 0 tracked changes; every mark `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone;
a `False` mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-14 13:48 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree is on this branch at 6dde335 with 0 tracked changes, and its build (built from 0c04b89, the last commit under source/; 6dde335 adds only this checklist) carries every mark.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s114b] The module loads from a worktree that is not the main clone: True
[oer-s114b] Main clone: branch main; HEAD 491e72e
[oer-s114b] Worktree: branch feat/rename-policies-and-reviews; HEAD 6dde335 docs: add the live checklist for renaming assignment policies and access reviews in place; tracked changes: 0
[oer-s114b] The worktree's build decides policy and review renames: True True
[oer-s114b] The worktree's build lets a review read the rename map: True
[oer-s114b] The worktree's build marks a renaming policy under every known package id: True
[oer-s114b] The worktree's build sends a policy rename alone (A16): True
[oer-s114b] The worktree's build probes a review id with the declared not-found codes: True
[oer-s114b] The worktree's build refuses a review naming a shared renamed package name (Rule 15): True
[oer-s114b] The worktree's build reads a catalog with -ErrorAction Stop (BL-144): True
RUNNER: check-S.1 exit code 0; started 2026-10-14T13:48:47Z; took 3 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, and `The module is the worktree's
build: True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result: 2026-10-14 13:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc (app-only, certificate); identity check passed; the module is the worktree's build (1.2.1).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] The module is the worktree's build: True; version 1.2.1
RUNNER: check-0.1 exit code 0; started 2026-10-14T13:49:28Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.2. The permissions this file needs

- [x] **0.2** `oer-live-cc` holds the three permissions; otherwise the run stops here.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Granted = Get-S114bGrantedRole
foreach ($Name in $Needed) { Write-OerLiveStep "oer-live-cc holds $($Name): $($Granted -ccontains $Name)" }
Write-OerLiveStep "oer-live-cc holds $($Granted.Count) Microsoft Graph application permissions"
$Missing = @($Needed | Where-Object { $Granted -cnotcontains $_ })
if ($Missing.Count -gt 0) { Write-OerLiveStep "Missing: $($Missing -join ', ') (G11.7: granting it is the operator's decision)." }
Disconnect-OerLive
```

**Expect:** each of the three lines `True`.
**Failure looks like:** `False` -- stop the run; nothing has been written.

Result: 2026-10-14 13:49 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. oer-live-cc holds EntitlementManagement.ReadWrite.All, AccessReview.ReadWrite.All and Group.ReadWrite.All (19 Microsoft Graph application permissions in all); no permission was added or removed.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114b] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s114b] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114b] oer-live-cc holds 19 Microsoft Graph application permissions
RUNNER: check-0.2 exit code 0; started 2026-10-14T13:49:40Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.3. The prerequisite objects

- [x] **0.3** The plan writes nothing; the first run creates the objects; a second run writes nothing.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS114bPrereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS114bPrereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -NonInteractive -File $Script @Run
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run ends `WhatIf: nothing was created, removed or written.` with exit code
0; the first `-Unattended` run creates what is missing and ends `unavailable (class B): none`, exit code
0; the second finds every object and writes nothing (`written to the tenant: False`), exit code 0.
**Failure looks like:** a `Refusing to run:` line, an `UNAVAILABLE` line (the stage half of 1.5 is then
class B), or exit code 1 -- read the reason; nothing past a refusal was written.

Result: 2026-10-14 13:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, on the second run of this check. Run 1: the plan wrote nothing; the first -Unattended run wrote the baseline (groups 97, catalogs 5, access packages 6, access review definitions 6) and created every object -- the group, the catalog, the hidden package, the resource group with the Logic App and its authorization policy, the custom extension, policy A with its question and custom extension stage, policy B, the package review and the group review -- with unavailable (class B): none; the second -Unattended run stopped on a script defect in its read-only part before anything was written (a comma binds tighter than + in a name list), fixed in the prerequisite script outside the repository. Run 2, below: the plan and both -Unattended runs find all ten objects, policy A in its full state, and write nothing (written to the tenant: False). Exit code 0 each time.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s114b] === Initialize-OerS114bPrereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s114b\prereq-20261014-135119Z.log".
[oer-s114b] Mode: CREATE or complete. Prefix 'oer-s114b-'. Objects (fixed): oer-s114b-grp (security group, no member); oer-s114b-cat (catalog, no resource); oer-s114b-ap (hidden access package, no resource role); oer-s114b-rg (tagged) with oer-s114b-la (Logic App, nothing calls it); oer-s114b-ext (custom extension); oer-s114b-pol-a (requestable by the members of oer-s114b-grp only, one question, the custom extension stage); oer-s114b-pol-b (requestable by the members of oer-s114b-grp only); oer-s114b-ar (a review of oer-s114b-ap under oer-s114b-pol-b); oer-s114b-gr (a review of the members of oer-s114b-grp). The names the checklist renames to: oer-s114b-ap-new, oer-s114b-pol-a-new, oer-s114b-ar-new. OerLive 1.0.3.
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114b] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114b] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s114b] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114b] Found: oer-s114b-grp True; oer-s114b-cat True; oer-s114b-ap True; oer-s114b-pol-a True; oer-s114b-pol-b True; oer-s114b-rg True; oer-s114b-la True; oer-s114b-ext True; oer-s114b-ar True; oer-s114b-gr True.
[oer-s114b] The baseline exists (groups 97, catalogs 5, access packages 6, access review definitions 6 when it was written).
[oer-s114b] Group oer-s114b-grp exists.
[oer-s114b] Catalog oer-s114b-cat exists.
[oer-s114b] Access package oer-s114b-ap (or its new name) exists.
[oer-s114b] Resource group oer-s114b-rg exists.
[oer-s114b] Logic App oer-s114b-la exists; its AADPOP authorization policy is there: True
[oer-s114b] Custom extension oer-s114b-ext exists.
[oer-s114b] oer-s114b-pol-a: the question is there: True; the custom extension stage is there: True
[oer-s114b] Policy oer-s114b-pol-a (or its new name) exists in its full state.
[oer-s114b] Policy oer-s114b-pol-b exists.
[oer-s114b] Access review oer-s114b-ar (or its new name, a review of oer-s114b-ap) exists.
[oer-s114b] Access review oer-s114b-gr (a group review of oer-s114b-grp) exists.
[oer-s114b] Summary: oer-s114b-grp present; oer-s114b-cat present; oer-s114b-ap present; oer-s114b-rg present; oer-s114b-la present; oer-s114b-ext present; oer-s114b-pol-a present; oer-s114b-pol-b present; oer-s114b-ar present; oer-s114b-gr present; unavailable (class B): none; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s114b] WhatIf: nothing was created, removed or written.
[oer-s114b] Done.
[oer-s114b] exit code: 0
[oer-s114b] === Initialize-OerS114bPrereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114b] Transcript (redacted): raw\s114b\prereq-20261014-135127Z.log; OerLive 1.0.3.
[oer-s114b] Mode: CREATE or complete. Prefix 'oer-s114b-'. Objects (fixed): oer-s114b-grp (security group, no member); oer-s114b-cat (catalog, no resource); oer-s114b-ap (hidden access package, no resource role); oer-s114b-rg (tagged) with oer-s114b-la (Logic App, nothing calls it); oer-s114b-ext (custom extension); oer-s114b-pol-a (requestable by the members of oer-s114b-grp only, one question, the custom extension stage); oer-s114b-pol-b (requestable by the members of oer-s114b-grp only); oer-s114b-ar (a review of oer-s114b-ap under oer-s114b-pol-b); oer-s114b-gr (a review of the members of oer-s114b-grp). The names the checklist renames to: oer-s114b-ap-new, oer-s114b-pol-a-new, oer-s114b-ar-new. OerLive 1.0.3.
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s114b] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114b] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114b] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s114b] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114b] Found: oer-s114b-grp True; oer-s114b-cat True; oer-s114b-ap True; oer-s114b-pol-a True; oer-s114b-pol-b True; oer-s114b-rg True; oer-s114b-la True; oer-s114b-ext True; oer-s114b-ar True; oer-s114b-gr True.
[oer-s114b] The baseline exists (groups 97, catalogs 5, access packages 6, access review definitions 6 when it was written).
[oer-s114b] Group oer-s114b-grp exists.
[oer-s114b] Catalog oer-s114b-cat exists.
[oer-s114b] Access package oer-s114b-ap (or its new name) exists.
[oer-s114b] Resource group oer-s114b-rg exists.
[oer-s114b] Logic App oer-s114b-la exists; its AADPOP authorization policy is there: True
[oer-s114b] Custom extension oer-s114b-ext exists.
[oer-s114b] oer-s114b-pol-a: the question is there: True; the custom extension stage is there: True
[oer-s114b] Policy oer-s114b-pol-a (or its new name) exists in its full state.
[oer-s114b] Policy oer-s114b-pol-b exists.
[oer-s114b] Access review oer-s114b-ar (or its new name, a review of oer-s114b-ap) exists.
[oer-s114b] Access review oer-s114b-gr (a group review of oer-s114b-grp) exists.
[oer-s114b] Summary: oer-s114b-grp present; oer-s114b-cat present; oer-s114b-ap present; oer-s114b-rg present; oer-s114b-la present; oer-s114b-ext present; oer-s114b-pol-a present; oer-s114b-pol-b present; oer-s114b-ar present; oer-s114b-gr present; unavailable (class B): none; written to the tenant: False.
[oer-s114b] Done.
[oer-s114b] exit code: 0
[oer-s114b] === Initialize-OerS114bPrereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114b] Transcript (redacted): raw\s114b\prereq-20261014-135135Z.log; OerLive 1.0.3.
[oer-s114b] Mode: CREATE or complete. Prefix 'oer-s114b-'. Objects (fixed): oer-s114b-grp (security group, no member); oer-s114b-cat (catalog, no resource); oer-s114b-ap (hidden access package, no resource role); oer-s114b-rg (tagged) with oer-s114b-la (Logic App, nothing calls it); oer-s114b-ext (custom extension); oer-s114b-pol-a (requestable by the members of oer-s114b-grp only, one question, the custom extension stage); oer-s114b-pol-b (requestable by the members of oer-s114b-grp only); oer-s114b-ar (a review of oer-s114b-ap under oer-s114b-pol-b); oer-s114b-gr (a review of the members of oer-s114b-grp). The names the checklist renames to: oer-s114b-ap-new, oer-s114b-pol-a-new, oer-s114b-ar-new. OerLive 1.0.3.
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s114b] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114b] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s114b] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s114b] oer-live-cc holds Group.ReadWrite.All: True
[oer-s114b] Found: oer-s114b-grp True; oer-s114b-cat True; oer-s114b-ap True; oer-s114b-pol-a True; oer-s114b-pol-b True; oer-s114b-rg True; oer-s114b-la True; oer-s114b-ext True; oer-s114b-ar True; oer-s114b-gr True.
[oer-s114b] The baseline exists (groups 97, catalogs 5, access packages 6, access review definitions 6 when it was written).
[oer-s114b] Group oer-s114b-grp exists.
[oer-s114b] Catalog oer-s114b-cat exists.
[oer-s114b] Access package oer-s114b-ap (or its new name) exists.
[oer-s114b] Resource group oer-s114b-rg exists.
[oer-s114b] Logic App oer-s114b-la exists; its AADPOP authorization policy is there: True
[oer-s114b] Custom extension oer-s114b-ext exists.
[oer-s114b] oer-s114b-pol-a: the question is there: True; the custom extension stage is there: True
[oer-s114b] Policy oer-s114b-pol-a (or its new name) exists in its full state.
[oer-s114b] Policy oer-s114b-pol-b exists.
[oer-s114b] Access review oer-s114b-ar (or its new name, a review of oer-s114b-ap) exists.
[oer-s114b] Access review oer-s114b-gr (a group review of oer-s114b-grp) exists.
[oer-s114b] Summary: oer-s114b-grp present; oer-s114b-cat present; oer-s114b-ap present; oer-s114b-rg present; oer-s114b-la present; oer-s114b-ext present; oer-s114b-pol-a present; oer-s114b-pol-b present; oer-s114b-ar present; oer-s114b-gr present; unavailable (class B): none; written to the tenant: False.
[oer-s114b] Done.
[oer-s114b] exit code: 0
RUNNER: check-0.3 exit code 0; started 2026-10-14T13:51:16Z; took 25 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. A policy and a review renamed in place

### 1.1. The ids before the rename

- [x] **1.1** Every object is found exactly once under its own name; the ids, and what each object holds, are recorded under `raw\s114b\` (never printed).

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Ids = [ordered]@{}
$Hit = @(Get-S114bId -Kind package -Name $Ap)
Write-OerLiveStep "$Ap is found exactly once under its own name: $($Hit.Count -eq 1)"
if ($Hit.Count -ne 1) { throw "STOP: $Ap matches $($Hit.Count) objects." }
$Ids.Package = $Hit[0]
foreach ($Spec in @(@('PolA', 'policy', $PolA), @('PolB', 'policy', $PolB), @('Review', 'review', $Rev), @('GroupReview', 'review', $GroupRev))) {
    $Hit = @(Get-S114bId -Kind $Spec[1] -Name $Spec[2] -PackageId $Ids.Package)
    Write-OerLiveStep "$($Spec[2]) is found exactly once under its own name: $($Hit.Count -eq 1)"
    if ($Hit.Count -ne 1) { throw "STOP: $($Spec[2]) matches $($Hit.Count) objects." }
    $Ids[$Spec[0]] = $Hit[0]
}
$Ids.Group = @(Get-S114bId -Kind group -Name $Group)[0]
Write-OerLiveStep "No policy carries the new name $PolANew yet: $(@(Get-S114bId -Kind policy -Name $PolANew -PackageId $Ids.Package).Count -eq 0)"
Write-OerLiveStep "No review carries the new name $RevNew yet: $(@(Get-S114bId -Kind review -Name $RevNew).Count -eq 0)"
Write-OerLiveStep "No package carries the new name $ApNew yet: $(@(Get-S114bId -Kind package -Name $ApNew).Count -eq 0)"
$Before = Get-S114bSnapshot -Ids $Ids
Write-OerLiveStep "Before: package policies $($Before.PackagePolicies.Count); $PolA question $($Before.PolAQuestion), custom extension stage(s) $($Before.PolAStages.Count), allowed target is the group $(@($Before.PolATargets) -ccontains $Ids.Group); $PolB allowed target is the group $(@($Before.PolBTargets) -ccontains $Ids.Group); $Rev reviews the package and policy B $($Before.ReviewQuery -match [regex]::Escape($Ids.Package) -and $Before.ReviewQuery -match [regex]::Escape($Ids.PolB)); $GroupRev reviews the group $($Before.GroupReviewQuery -match [regex]::Escape($Ids.Group)); prefixed access reviews $($Before.Reviews.Count); prefixed objects $($Before.Prefixed.Count)"
$Record = [ordered]@{ Ids = $Ids; Before = $Before }
[System.IO.File]::WriteAllText((Join-Path $Raw 'before.json'), (ConvertTo-Json -InputObject $Record -Depth 8), [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep 'Recorded the ids and the snapshot under raw\s114b\before.json (not printed).'
Disconnect-OerLive
```

**Expect:** five `found exactly once` lines and three `No ... carries the new name` lines, all `True`;
`Before:` two package policies; policy A's question `True` and one custom extension stage (none when
0.3 reported the extension unavailable); both allowed targets the group `True`; the package review
reviews the package and policy B `True`; the group review reviews the group `True`; two prefixed access
reviews; three prefixed objects (the group, the catalog, the package).
**Failure looks like:** a `STOP` or a `False` -- run 0.3 again.

Result: 2026-10-14 13:52 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The package, both policies and both reviews are each found exactly once under their own names, and no object carries any of the three new names. Before the rename the package holds two policies; policy A holds its question and one custom extension stage, and both policies allow the group's members only; the package review reviews the package under policy B; the group review reviews the group; two prefixed access reviews and three prefixed objects. The ids and the snapshot are under raw\s114b\before.json, not printed.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] oer-s114b-ap is found exactly once under its own name: True
[oer-s114b] oer-s114b-pol-a is found exactly once under its own name: True
[oer-s114b] oer-s114b-pol-b is found exactly once under its own name: True
[oer-s114b] oer-s114b-ar is found exactly once under its own name: True
[oer-s114b] oer-s114b-gr is found exactly once under its own name: True
[oer-s114b] No policy carries the new name oer-s114b-pol-a-new yet: True
[oer-s114b] No review carries the new name oer-s114b-ar-new yet: True
[oer-s114b] No package carries the new name oer-s114b-ap-new yet: True
[oer-s114b] Before: package policies 2; oer-s114b-pol-a question True, custom extension stage(s) 1, allowed target is the group True; oer-s114b-pol-b allowed target is the group True; oer-s114b-ar reviews the package and policy B True; oer-s114b-gr reviews the group True; prefixed access reviews 2; prefixed objects 3
[oer-s114b] Recorded the ids and the snapshot under raw\s114b\before.json (not printed).
RUNNER: check-1.1 exit code 0; started 2026-10-14T13:51:52Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. The validator accepts the rename document

- [x] **1.2** `Test-OERStructure` reports the document valid, with no Error and no Warning.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
Write-S114bValidation -Label '1.2' -Json (New-S114bDocument1)
Disconnect-OerLive
```

**Expect:** `1.2 valid: True; errors: 0; warnings: 0`.
**Failure looks like:** an Error at `accessPackages[0].assignmentPolicies[0].previousDisplayName` or
`accessReviews[0].previousDisplayName` -- step 3's refusal is still in force.

Result: 2026-10-14 13:52 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Test-OERStructure reports the rename document valid with no Error and no Warning: previousDisplayName is accepted on the policy and on the review.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 1.2 valid: True; errors: 0; warnings: 0
RUNNER: check-1.2 exit code 0; started 2026-10-14T13:52:09Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.3. The plan renames in place and writes nothing

- [x] **1.3** Under `-WhatIf` the policy and the review are each reported `would rename` from the previous name to the new name, and nothing is written.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$null = Invoke-S114bApply -Label '1.3' -Json (New-S114bDocument1) -Plan
Disconnect-OerLive
```

**Expect:** a Skipped row `would rename assignmentPolicy 'oer-s114b-pol-a' to 'oer-s114b-pol-a-new'` on
the package and a Skipped row `would rename access review 'oer-s114b-ar' to 'oer-s114b-ar-new'`;
Unchanged rows for the catalog, the package and policy B; no Created, Failed, Extra or Removed row;
`errors of Invoke-OERStructure: 0`; `writes: 0` for Microsoft Graph and Azure Resource Manager.
**Failure looks like:** a `would create` row (the engine would create a second policy or review), an
`Extra` row for `oer-s114b-pol-a`, or any write.

Result: 2026-10-14 13:52 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Under -WhatIf the policy is reported Skipped 'would rename assignmentPolicy 'oer-s114b-pol-a' to 'oer-s114b-pol-a-new'' on the package and the review Skipped 'would rename access review 'oer-s114b-ar' to 'oer-s114b-ar-new''; the catalog, the package and policy B are Unchanged; no Created, Failed, Extra or Removed row; no error; 13 Microsoft Graph requests, 0 writes; 0 Azure Resource Manager requests; 0 token requests.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Rename assignmentPolicy 'oer-s114b-pol-a' to 'oer-s114b-pol-a-new'" on target "oer-s114b-ap".
What if: Performing the operation "Rename access review definition 'oer-s114b-ar' to 'oer-s114b-ar-new'" on target "oer-s114b-ar-new".
[oer-s114b] 1.3 rows: 5
[oer-s114b] 1.3 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 1.3 row: accessPackages | oer-s114b-ap | Unchanged | access package properties match
[oer-s114b] 1.3 row: accessPackages | oer-s114b-ap | Skipped | would rename assignmentPolicy 'oer-s114b-pol-a' to 'oer-s114b-pol-a-new'
[oer-s114b] 1.3 row: accessPackages | oer-s114b-ap | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 1.3 row: accessReviews | oer-s114b-ar-new | Skipped | would rename access review 'oer-s114b-ar' to 'oer-s114b-ar-new'
[oer-s114b] 1.3 warnings: 0
[oer-s114b] 1.3 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 1.3 sent: token requests: 0; Microsoft Graph requests: 13, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check-1.3 exit code 0; started 2026-10-14T13:52:23Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.4. The run renames in place

- [x] **1.4** The run renames the policy in one PUT and the review in one PUT, and writes nothing else.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$null = Invoke-S114bApply -Label '1.4' -Json (New-S114bDocument1)
Disconnect-OerLive
```

**Expect:** an Updated row `renamed assignmentPolicy 'oer-s114b-pol-a' to 'oer-s114b-pol-a-new'` and an
Updated row `renamed access review 'oer-s114b-ar' to 'oer-s114b-ar-new'`; the other rows Unchanged; no
error; exactly two Microsoft Graph writes, a PUT of the policy and a PUT of the review definition;
no Azure Resource Manager request.
**Failure looks like:** a `NothingToUpdate` error (the policy's rename alone was refused), a Created row,
or a write other than the two PUTs.

Result: 2026-10-14 13:52 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The run renames the policy and the review: Updated 'renamed assignmentPolicy 'oer-s114b-pol-a' to 'oer-s114b-pol-a-new'' and Updated 'renamed access review 'oer-s114b-ar' to 'oer-s114b-ar-new''; the catalog, the package and policy B Unchanged; no error. 18 Microsoft Graph requests, exactly 2 writes: one PUT of the policy (Set-OERAccessPackageAssignmentPolicy sent the rename alone, A16) and one PUT of the review definition; no Azure Resource Manager request.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.4 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 1.4 rows: 5
[oer-s114b] 1.4 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 1.4 row: accessPackages | oer-s114b-ap | Unchanged | access package properties match
[oer-s114b] 1.4 row: accessPackages | oer-s114b-ap | Updated | renamed assignmentPolicy 'oer-s114b-pol-a' to 'oer-s114b-pol-a-new'
[oer-s114b] 1.4 row: accessPackages | oer-s114b-ap | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 1.4 row: accessReviews | oer-s114b-ar-new | Updated | renamed access review 'oer-s114b-ar' to 'oer-s114b-ar-new'
[oer-s114b] 1.4 warnings: 0
[oer-s114b] 1.4 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 1.4 sent: token requests: 0; Microsoft Graph requests: 18, writes: 2 (PUT v1.0/identityGovernance/entitlementManagement/assignmentPolicies/00000000-0000-0000-0000-000000000001, PUT v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000002); Azure Resource Manager requests: 0, writes: 0
RUNNER: check-1.4 exit code 0; started 2026-10-14T13:52:41Z; took 9 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.5. Read back by id: the same objects, the new names, nothing lost

- [x] **1.5** The policy and the review keep their ids and carry the new names; the policy keeps its question, its custom extension stage and its allowed target; the review keeps its scope and settings; nothing else changed and nothing was created.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Rec = Read-S114bIds
$Ids = $Rec['Ids']
$null = Wait-OerLiveConverged -Activity 'the policy and the review read back under their new names' -Read { Get-S114bSnapshot -Ids $Ids } -Test { $args[0].PolAName -ceq $PolANew -and $args[0].ReviewName -ceq $RevNew }
$After = Get-S114bSnapshot -Ids $Ids
Write-S114bCompare -Label '1.5' -Before $Rec['Before'] -After $After
Disconnect-OerLive
```

**Expect:** `PolAName` before `oer-s114b-pol-a`, now `oer-s114b-pol-a-new`, and `ReviewName` before
`oer-s114b-ar`, now `oer-s114b-ar-new` (unchanged: False for those two only); every other line
`unchanged: True` -- the package name and its two policies (same ids), policy A's question, custom
extension stage(s), allowed targets and scope, policy B, the review's scope query and settings, the
group review, the prefixed reviews (same two ids) and the prefixed objects.
**Failure looks like:** `unchanged: False` on any other line -- the custom extension stage or the
question dropped (step 3's carry-forward did not hold for a rename), a third review or policy, or a new id.

Result: 2026-10-14 13:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Read back by id, the policy and the review keep their ids and carry their new names (oer-s114b-pol-a-new, oer-s114b-ar-new); every other field is unchanged: the package's name and its same two policies; policy A's question, its one custom extension stage, its allowed target and scope (the rename carried them forward); policy B; the review's scope query and settings; the group review; the same two prefixed reviews and the same three prefixed objects -- nothing was created.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.5 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] the policy and the review read back under their new names: converged after 1 read(s), 2.2 s.
[oer-s114b] 1.5 PackageName: before 'oer-s114b-ap', now 'oer-s114b-ap'; unchanged: True
[oer-s114b] 1.5 PackagePolicies: unchanged: True (2 item(s) before, 2 now)
[oer-s114b] 1.5 PolAName: before 'oer-s114b-pol-a', now 'oer-s114b-pol-a-new'; unchanged: False
[oer-s114b] 1.5 PolAQuestion: unchanged: True
[oer-s114b] 1.5 PolAStages: unchanged: True (1 item(s) before, 1 now)
[oer-s114b] 1.5 PolATargets: unchanged: True (1 item(s) before, 1 now)
[oer-s114b] 1.5 PolAScope: unchanged: True
[oer-s114b] 1.5 PolBName: before 'oer-s114b-pol-b', now 'oer-s114b-pol-b'; unchanged: True
[oer-s114b] 1.5 PolBTargets: unchanged: True (1 item(s) before, 1 now)
[oer-s114b] 1.5 ReviewName: before 'oer-s114b-ar', now 'oer-s114b-ar-new'; unchanged: False
[oer-s114b] 1.5 ReviewQuery: unchanged: True
[oer-s114b] 1.5 ReviewSettings: unchanged: True
[oer-s114b] 1.5 GroupReviewName: before 'oer-s114b-gr', now 'oer-s114b-gr'; unchanged: True
[oer-s114b] 1.5 GroupReviewQuery: unchanged: True
[oer-s114b] 1.5 Reviews: unchanged: True (2 item(s) before, 2 now)
[oer-s114b] 1.5 Prefixed: unchanged: True (3 item(s) before, 3 now)
RUNNER: check-1.5 exit code 0; started 2026-10-14T13:53:01Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. The same document again converges (G8)

### 2.1. The new names resolve

- [x] **2.1** Microsoft Graph's listings find the policy and the review under their new names, three times in a row, before the convergence runs.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Ids = (Read-S114bIds)['Ids']
Wait-S114bNames -Wanted @(@('policy', $PolANew, $Ids.PolA, $Ids.Package), @('review', $RevNew, $Ids.Review, $null))
Disconnect-OerLive
```

**Expect:** `True`.
**Failure looks like:** `False` after 40 reads -- the listing has not caught up; run the block again.

Result: 2026-10-14 13:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The package's policy listing finds the policy, and the review listing the review, under their new names at the ids recorded in 1.1, three reads in a row (3 reads, 10 s apart).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] Every wanted name resolves to the recorded id, three reads in a row: True (3 read(s))
RUNNER: check-2.1 exit code 0; started 2026-10-14T13:53:19Z; took 25 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.2. The same document twice more: only Unchanged

- [x] **2.2** Two runs of the 1.4 document report only Unchanged rows and write nothing.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
foreach ($N in 1, 2) { $null = Invoke-S114bApply -Label "2.2 run $N" -Json (New-S114bDocument1) }
Disconnect-OerLive
```

**Expect:** each run: only Unchanged rows (the catalog, the package, both policies, the review), no
warning, no error, `writes: 0`.
**Failure looks like:** an Updated row (the rename was sent again), a Failed row with
`AssignmentPolicyRenameNotFound` or `AccessReviewRenameNotFound`, or any write.

Result: 2026-10-14 13:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Two more runs of the 1.4 document: each reports only Unchanged rows (the catalog, the package, both policies and the review 'already matches'), no warning, no error, 13 Microsoft Graph requests and 0 writes.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 2.2 run 1 rows: 5
[oer-s114b] 2.2 run 1 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 2.2 run 1 row: accessPackages | oer-s114b-ap | Unchanged | access package properties match
[oer-s114b] 2.2 run 1 row: accessPackages | oer-s114b-ap | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 2.2 run 1 row: accessPackages | oer-s114b-ap | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 2.2 run 1 row: accessReviews | oer-s114b-ar-new | Unchanged | access review 'oer-s114b-ar-new' already matches
[oer-s114b] 2.2 run 1 warnings: 0
[oer-s114b] 2.2 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 2.2 run 1 sent: token requests: 0; Microsoft Graph requests: 13, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 2.2 run 2 rows: 5
[oer-s114b] 2.2 run 2 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 2.2 run 2 row: accessPackages | oer-s114b-ap | Unchanged | access package properties match
[oer-s114b] 2.2 run 2 row: accessPackages | oer-s114b-ap | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 2.2 run 2 row: accessPackages | oer-s114b-ap | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 2.2 run 2 row: accessReviews | oer-s114b-ar-new | Unchanged | access review 'oer-s114b-ar-new' already matches
[oer-s114b] 2.2 run 2 warnings: 0
[oer-s114b] 2.2 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 2.2 run 2 sent: token requests: 0; Microsoft Graph requests: 13, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check-2.2 exit code 0; started 2026-10-14T13:53:53Z; took 9 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. A package renamed in the same run as the review naming its new name

### 3.1. The validator accepts the document

- [x] **3.1** `Test-OERStructure` reports the document valid, with no Error and no Warning.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
Write-S114bValidation -Label '3.1' -Json (New-S114bDocument3)
Disconnect-OerLive
```

**Expect:** `3.1 valid: True; errors: 0; warnings: 0`.
**Failure looks like:** a Warning at `accessReviews[0].accessPackage` -- the review names an old name.

Result: 2026-10-14 13:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Test-OERStructure reports the package rename document valid with no Error and no Warning (the review names the package's new name).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 3.1 valid: True; errors: 0; warnings: 0
RUNNER: check-3.1 exit code 0; started 2026-10-14T13:54:12Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. The plan renames the package, and the review reaches it

- [x] **3.2** Under `-WhatIf` the package is reported `would rename`, the review that names the package's new name is Unchanged (it reaches the package through the run's rename map), and nothing is written.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$null = Invoke-S114bApply -Label '3.2' -Json (New-S114bDocument3) -Plan
Disconnect-OerLive
```

**Expect:** a Skipped row `would rename access package 'oer-s114b-ap' to 'oer-s114b-ap-new'`; Unchanged
rows for the catalog, both policies and the review `oer-s114b-ar-new`; no Failed row; no error;
`writes: 0`.
**Failure looks like:** a Failed row for the review naming `AccessPackageNotFound` (the review looked the
new name up in Microsoft Graph, which does not carry it yet), or any write.

Result: 2026-10-14 13:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Under -WhatIf the package is reported Skipped 'would rename access package 'oer-s114b-ap' to 'oer-s114b-ap-new''; the review that names the package's NEW name is Unchanged ('already matches'): it reached the package found under its previous name through the run's rename map, while Microsoft Graph does not carry the new name yet; the catalog and both policies Unchanged; no Failed row; no error; 12 Microsoft Graph requests, 0 writes.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Rename access package 'oer-s114b-ap' to 'oer-s114b-ap-new'" on target "oer-s114b-ap-new".
[oer-s114b] 3.2 rows: 5
[oer-s114b] 3.2 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 3.2 row: accessPackages | oer-s114b-ap-new | Skipped | would rename access package 'oer-s114b-ap' to 'oer-s114b-ap-new'
[oer-s114b] 3.2 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 3.2 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 3.2 row: accessReviews | oer-s114b-ar-new | Unchanged | access review 'oer-s114b-ar-new' already matches
[oer-s114b] 3.2 warnings: 0
[oer-s114b] 3.2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 3.2 sent: token requests: 0; Microsoft Graph requests: 12, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check-3.2 exit code 0; started 2026-10-14T13:54:17Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.3. The run renames the package, and the review reaches it

- [x] **3.3** The run renames the package in one PATCH; the review is Unchanged; nothing else is written.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$null = Invoke-S114bApply -Label '3.3' -Json (New-S114bDocument3)
Disconnect-OerLive
```

**Expect:** an Updated row `renamed access package 'oer-s114b-ap' to 'oer-s114b-ap-new'`; the review
Unchanged; no error; exactly one Microsoft Graph write, a PATCH of the access package.
**Failure looks like:** a Failed row for the review, or another write.

Result: 2026-10-14 13:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The run renames the package (Updated 'renamed access package 'oer-s114b-ap' to 'oer-s114b-ap-new''); the review naming its new name is Unchanged in the same run; both policies and the catalog Unchanged; no error; 13 Microsoft Graph requests, exactly 1 write, the PATCH of the access package.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.3 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 3.3 rows: 5
[oer-s114b] 3.3 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 3.3 row: accessPackages | oer-s114b-ap-new | Updated | renamed access package 'oer-s114b-ap' to 'oer-s114b-ap-new'
[oer-s114b] 3.3 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 3.3 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 3.3 row: accessReviews | oer-s114b-ar-new | Unchanged | access review 'oer-s114b-ar-new' already matches
[oer-s114b] 3.3 warnings: 0
[oer-s114b] 3.3 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 3.3 sent: token requests: 0; Microsoft Graph requests: 13, writes: 1 (PATCH v1.0/identityGovernance/entitlementManagement/accessPackages/00000000-0000-0000-0000-000000000003); Azure Resource Manager requests: 0, writes: 0
RUNNER: check-3.3 exit code 0; started 2026-10-14T13:54:39Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.4. Read back, and the new package name resolves

- [x] **3.4** The package keeps its id and carries its new name; everything it holds, and the review, are as before; the new name resolves three times in a row.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Rec = Read-S114bIds
$Ids = $Rec['Ids']
$After = Get-S114bSnapshot -Ids $Ids
Write-OerLiveStep "3.4 package name now '$($After.PackageName)'; policies unchanged: $((ConvertTo-Json @($After.PackagePolicies) -Compress) -ceq (ConvertTo-Json @($Rec['Before']['PackagePolicies']) -Compress)); review query unchanged: $($After.ReviewQuery -ceq $Rec['Before']['ReviewQuery']); review settings unchanged: $($After.ReviewSettings -ceq $Rec['Before']['ReviewSettings']); policy A stage(s) $($After.PolAStages.Count), question $($After.PolAQuestion); prefixed objects unchanged: $((ConvertTo-Json @($After.Prefixed) -Compress) -ceq (ConvertTo-Json @($Rec['Before']['Prefixed']) -Compress))"
# One pair: the leading comma keeps it a pair inside the list instead of four loose values.
Wait-S114bNames -Wanted @(, @('package', $ApNew, $Ids.Package, ''))
Disconnect-OerLive
```

**Expect:** the package name `oer-s114b-ap-new`; every `unchanged` `True`; policy A's stage(s) and
question as in 1.1; `Every wanted name resolves ...: True`.
**Failure looks like:** `False` -- record which.

Result: 2026-10-14 13:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (second run; the first stopped after its read-back line on a checklist defect -- a one-pair list was flattened before -Wanted -- fixed in the next checklist commit and applied to this note by hand). The package keeps its id and carries 'oer-s114b-ap-new'; its two policies, the review's scope query and settings, policy A's stage and question and the prefixed objects are unchanged; the new package name resolves to the recorded id three reads in a row.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.4 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 3.4 package name now 'oer-s114b-ap-new'; policies unchanged: True; review query unchanged: True; review settings unchanged: True; policy A stage(s) 1, question True; prefixed objects unchanged: True
[oer-s114b] Every wanted name resolves to the recorded id, three reads in a row: True (3 read(s))
RUNNER: check-3.4 exit code 0; started 2026-10-14T13:55:24Z; took 26 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.5. The same document twice more: only Unchanged, and -Prune plans no removal

- [x] **3.5** Two runs of the 3.3 document report only Unchanged rows and write nothing; the same document with `-Prune -WhatIf` plans no removal.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
foreach ($N in 1, 2) { $null = Invoke-S114bApply -Label "3.5 run $N" -Json (New-S114bDocument3) }
$null = Invoke-S114bApply -Label '3.5 prune plan' -Json (New-S114bDocument3) -Plan -Prune
Disconnect-OerLive
```

**Expect:** each run only Unchanged rows, `writes: 0`; the `-Prune` plan only Unchanged rows, no
Removed or `would remove` row, `writes: 0`.
**Failure looks like:** any Updated, Failed or removal row, or a write.

Result: 2026-10-14 13:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Two more runs of the 3.3 document each report only Unchanged rows and write nothing (13 Microsoft Graph requests, 0 writes); the same document with -Prune -WhatIf plans only Unchanged rows, no removal, no warning, 0 writes.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.5 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 3.5 run 1 rows: 5
[oer-s114b] 3.5 run 1 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 3.5 run 1 row: accessPackages | oer-s114b-ap-new | Unchanged | access package properties match
[oer-s114b] 3.5 run 1 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 3.5 run 1 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 3.5 run 1 row: accessReviews | oer-s114b-ar-new | Unchanged | access review 'oer-s114b-ar-new' already matches
[oer-s114b] 3.5 run 1 warnings: 0
[oer-s114b] 3.5 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 3.5 run 1 sent: token requests: 0; Microsoft Graph requests: 13, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 3.5 run 2 rows: 5
[oer-s114b] 3.5 run 2 row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 3.5 run 2 row: accessPackages | oer-s114b-ap-new | Unchanged | access package properties match
[oer-s114b] 3.5 run 2 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 3.5 run 2 row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 3.5 run 2 row: accessReviews | oer-s114b-ar-new | Unchanged | access review 'oer-s114b-ar-new' already matches
[oer-s114b] 3.5 run 2 warnings: 0
[oer-s114b] 3.5 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 3.5 run 2 sent: token requests: 0; Microsoft Graph requests: 13, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 3.5 prune plan rows: 5
[oer-s114b] 3.5 prune plan row: catalogs | oer-s114b-cat | Unchanged | catalog properties match
[oer-s114b] 3.5 prune plan row: accessPackages | oer-s114b-ap-new | Unchanged | access package properties match
[oer-s114b] 3.5 prune plan row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 3.5 prune plan row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 3.5 prune plan row: accessReviews | oer-s114b-ar-new | Unchanged | access review 'oer-s114b-ar-new' already matches
[oer-s114b] 3.5 prune plan warnings: 0
[oer-s114b] 3.5 prune plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 3.5 prune plan sent: token requests: 0; Microsoft Graph requests: 13, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check-3.5 exit code 0; started 2026-10-14T13:55:59Z; took 11 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 4. A conflict, and names nothing carries, write nothing

### 4.1. Both names find different objects

- [x] **4.1** A policy whose new and previous names are two different policies, and a review whose new and previous names are two different reviews, are each refused with their conflict error, in the plan and in the run, and nothing is written.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Ids = (Read-S114bIds)['Ids']
# Document A: the policy conflict, and a review of the package that names the conflicting policy's new name
# (its policy rename is refused, so the review is refused through the run's rename map, R12).
$Json = New-S114bDocument -Section @{
    accessPackages = @(New-S114bPackageEntry -Name $ApNew -Policies @([ordered]@{ displayName = $PolB; previousDisplayName = $PolANew }))
    accessReviews  = @(New-S114bReviewEntry -Name $RevNew -Previous $GroupRev -Package $ApNew)
}
$null = Invoke-S114bApply -Label '4.1 A plan' -Json $Json -Plan
$null = Invoke-S114bApply -Label '4.1 A run' -Json $Json
# Document B: the review conflict alone (its new name and its previous name are two different reviews).
$Json = New-S114bDocument -Section @{ accessReviews = @(New-S114bReviewEntry -Name $RevNew -Previous $GroupRev -Package $ApNew) }
$null = Invoke-S114bApply -Label '4.1 B plan' -Json $Json -Plan
$null = Invoke-S114bApply -Label '4.1 B run' -Json $Json
$S = Get-S114bSnapshot -Ids $Ids
Write-OerLiveStep "4.1 names after: $($S.PolAName), $($S.PolBName), $($S.ReviewName), $($S.GroupReviewName); package policies $($S.PackagePolicies.Count); prefixed reviews $($S.Reviews.Count)"
Disconnect-OerLive
```

**Expect:** document A, in the plan and in the run: a Failed row with error
`AssignmentPolicyRenameConflict` for the policy entry, and the review naming that policy refused with a
Failed row that names the refused rename (no error record of its own); the package Unchanged; no Extra row
(the engine never removes a policy either way). Document B, in the plan and in the run: one Failed row with
error `AccessReviewRenameConflict`. `writes: 0` each time; the names after are `oer-s114b-pol-a-new`,
`oer-s114b-pol-b`, `oer-s114b-ar-new`, `oer-s114b-gr`, two package policies and two prefixed reviews.
**Failure looks like:** any write, or a changed name.

Result: 2026-10-14 13:57 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (second run; the first ran one combined document, in which the review was already refused through the run's rename map because the policy it names had its rename refused, so the review conflict was never reached -- the checklist now runs it as a second document; the first run wrote nothing either). Document A, plan and run: the policy entry Failed with AssignmentPolicyRenameConflict (both names found as different policies of the package), and the package review naming that policy Failed through the rename map ('its rename from ... was refused (AssignmentPolicyRenameConflict)'), with no error record of its own; the package Unchanged; no Extra row. Document B, plan and run: one Failed row with AccessReviewRenameConflict (the package review and the group review). 0 writes in all four; the names and counts after are unchanged.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.1 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 4.1 A plan rows: 3
[oer-s114b] 4.1 A plan row: accessPackages | oer-s114b-ap-new | Unchanged | access package properties match
[oer-s114b] 4.1 A plan row: accessPackages | oer-s114b-ap-new | Failed | assignmentPolicy 'oer-s114b-pol-b': both 'oer-s114b-pol-b' and its previousDisplayName 'oer-s114b-pol-a-new' exist in access package 'oer-s114b-ap-new' as different assignment policies; the document never merges two assignment policies, so nothing was changed -- rename or delete one of them, or remove previousDisplayName
[oer-s114b] 4.1 A plan row: accessReviews | oer-s114b-ar-new | Failed | assignment policy 'oer-s114b-pol-b' of access package 'oer-s114b-ap-new' was not reconciled in this run: its rename from 'oer-s114b-pol-a-new' was refused (AssignmentPolicyRenameConflict), so the assignment policy this access review reviews cannot be identified; nothing was created, read or written for it
[oer-s114b] 4.1 A plan warnings: 0
[oer-s114b] 4.1 A plan error: AssignmentPolicyRenameConflict,Invoke-OERStructure: Assignment policy 'oer-s114b-pol-b' (00000000-0000-0000-0000-000000000004) and its previousDisplayName 'oer-s114b-pol-a-new' (00000000-0000-0000-0000-000000000001) in access package 'oer-s114b-ap-new' are different assignment policies. The document never merges two assignment policies, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName.
[oer-s114b] 4.1 A plan errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 4.1 A plan sent: token requests: 0; Microsoft Graph requests: 6, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 4.1 A run rows: 3
[oer-s114b] 4.1 A run row: accessPackages | oer-s114b-ap-new | Unchanged | access package properties match
[oer-s114b] 4.1 A run row: accessPackages | oer-s114b-ap-new | Failed | assignmentPolicy 'oer-s114b-pol-b': both 'oer-s114b-pol-b' and its previousDisplayName 'oer-s114b-pol-a-new' exist in access package 'oer-s114b-ap-new' as different assignment policies; the document never merges two assignment policies, so nothing was changed -- rename or delete one of them, or remove previousDisplayName
[oer-s114b] 4.1 A run row: accessReviews | oer-s114b-ar-new | Failed | assignment policy 'oer-s114b-pol-b' of access package 'oer-s114b-ap-new' was not reconciled in this run: its rename from 'oer-s114b-pol-a-new' was refused (AssignmentPolicyRenameConflict), so the assignment policy this access review reviews cannot be identified; nothing was created, read or written for it
[oer-s114b] 4.1 A run warnings: 0
[oer-s114b] 4.1 A run error: AssignmentPolicyRenameConflict,Invoke-OERStructure: Assignment policy 'oer-s114b-pol-b' (00000000-0000-0000-0000-000000000004) and its previousDisplayName 'oer-s114b-pol-a-new' (00000000-0000-0000-0000-000000000001) in access package 'oer-s114b-ap-new' are different assignment policies. The document never merges two assignment policies, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName.
[oer-s114b] 4.1 A run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 4.1 A run sent: token requests: 0; Microsoft Graph requests: 6, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 4.1 B plan rows: 1
[oer-s114b] 4.1 B plan row: accessReviews | oer-s114b-ar-new | Failed | both 'oer-s114b-ar-new' and its previousDisplayName 'oer-s114b-gr' exist as different access reviews; the document never merges two access reviews, so nothing was changed -- rename or delete one of them, or remove previousDisplayName
[oer-s114b] 4.1 B plan warnings: 0
[oer-s114b] 4.1 B plan error: AccessReviewRenameConflict,Invoke-OERStructure: Access review 'oer-s114b-ar-new' (00000000-0000-0000-0000-000000000002) and its previousDisplayName 'oer-s114b-gr' (00000000-0000-0000-0000-000000000005) are different access reviews. The document never merges two access reviews, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName.
[oer-s114b] 4.1 B plan errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 4.1 B plan sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 4.1 B run rows: 1
[oer-s114b] 4.1 B run row: accessReviews | oer-s114b-ar-new | Failed | both 'oer-s114b-ar-new' and its previousDisplayName 'oer-s114b-gr' exist as different access reviews; the document never merges two access reviews, so nothing was changed -- rename or delete one of them, or remove previousDisplayName
[oer-s114b] 4.1 B run warnings: 0
[oer-s114b] 4.1 B run error: AccessReviewRenameConflict,Invoke-OERStructure: Access review 'oer-s114b-ar-new' (00000000-0000-0000-0000-000000000002) and its previousDisplayName 'oer-s114b-gr' (00000000-0000-0000-0000-000000000005) are different access reviews. The document never merges two access reviews, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName.
[oer-s114b] 4.1 B run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 4.1 B run sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 4.1 names after: oer-s114b-pol-a-new, oer-s114b-pol-b, oer-s114b-ar-new, oer-s114b-gr; package policies 2; prefixed reviews 2
RUNNER: check-4.1 exit code 0; started 2026-10-14T13:57:03Z; took 9 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 4.2. Neither name matches: nothing is created

- [x] **4.2** A policy and a review whose new and previous names match nothing are each refused with their not-found error, in the plan and in the run, and nothing is created.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Ids = (Read-S114bIds)['Ids']
$Json = New-S114bDocument -Section @{
    accessPackages = @(New-S114bPackageEntry -Name $ApNew -Policies @([ordered]@{ displayName = $PolANew }, [ordered]@{ displayName = $PolB }, [ordered]@{ displayName = 'oer-s114b-pol-zz'; previousDisplayName = 'oer-s114b-pol-yy' }))
    accessReviews  = @(New-S114bReviewEntry -Name 'oer-s114b-ar-zz' -Previous 'oer-s114b-ar-yy' -Package $ApNew)
}
$null = Invoke-S114bApply -Label '4.2 plan' -Json $Json -Plan
$null = Invoke-S114bApply -Label '4.2 run' -Json $Json
$S = Get-S114bSnapshot -Ids $Ids
Write-OerLiveStep "4.2 after: package policies $($S.PackagePolicies.Count); prefixed reviews $($S.Reviews.Count)"
Disconnect-OerLive
```

**Expect:** in the plan and in the run: a Failed row with error `AssignmentPolicyRenameNotFound` and a
Failed row with error `AccessReviewRenameNotFound`; no Created or `would create` row; `writes: 0` each
time; still two package policies and two prefixed reviews.
**Failure looks like:** a Created row or any write -- the engine created an object for a rename.

Result: 2026-10-14 13:58 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Plan and run: the policy entry Failed with AssignmentPolicyRenameNotFound and the review entry Failed with AccessReviewRenameNotFound, each with its error; the other policies and the package Unchanged; no Created or 'would create' row; 8 Microsoft Graph requests and 0 writes each time; still two package policies and two prefixed reviews.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.2 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 4.2 plan rows: 5
[oer-s114b] 4.2 plan row: accessPackages | oer-s114b-ap-new | Unchanged | access package properties match
[oer-s114b] 4.2 plan row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 4.2 plan row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 4.2 plan row: accessPackages | oer-s114b-ap-new | Failed | assignmentPolicy 'oer-s114b-pol-zz': neither 'oer-s114b-pol-zz' nor its previousDisplayName 'oer-s114b-pol-yy' matches an assignment policy in access package 'oer-s114b-ap-new', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new assignment policy, remove previousDisplayName
[oer-s114b] 4.2 plan row: accessReviews | oer-s114b-ar-zz | Failed | neither 'oer-s114b-ar-zz' nor its previousDisplayName 'oer-s114b-ar-yy' matches an access review, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new access review, remove previousDisplayName
[oer-s114b] 4.2 plan warnings: 0
[oer-s114b] 4.2 plan error: AssignmentPolicyRenameNotFound,Invoke-OERStructure: Neither 'oer-s114b-pol-zz' nor its previousDisplayName 'oer-s114b-pol-yy' matches an assignment policy in access package 'oer-s114b-ap-new', so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new assignment policy, remove previousDisplayName.
[oer-s114b] 4.2 plan error: AccessReviewRenameNotFound,Invoke-OERStructure: Neither 'oer-s114b-ar-zz' nor its previousDisplayName 'oer-s114b-ar-yy' matches an access review, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new access review, remove previousDisplayName.
[oer-s114b] 4.2 plan errors of Invoke-OERStructure: 2; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 4.2 plan sent: token requests: 0; Microsoft Graph requests: 8, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 4.2 run rows: 5
[oer-s114b] 4.2 run row: accessPackages | oer-s114b-ap-new | Unchanged | access package properties match
[oer-s114b] 4.2 run row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-a-new' matches
[oer-s114b] 4.2 run row: accessPackages | oer-s114b-ap-new | Unchanged | assignmentPolicy 'oer-s114b-pol-b' matches
[oer-s114b] 4.2 run row: accessPackages | oer-s114b-ap-new | Failed | assignmentPolicy 'oer-s114b-pol-zz': neither 'oer-s114b-pol-zz' nor its previousDisplayName 'oer-s114b-pol-yy' matches an assignment policy in access package 'oer-s114b-ap-new', so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new assignment policy, remove previousDisplayName
[oer-s114b] 4.2 run row: accessReviews | oer-s114b-ar-zz | Failed | neither 'oer-s114b-ar-zz' nor its previousDisplayName 'oer-s114b-ar-yy' matches an access review, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new access review, remove previousDisplayName
[oer-s114b] 4.2 run warnings: 0
[oer-s114b] 4.2 run error: AssignmentPolicyRenameNotFound,Invoke-OERStructure: Neither 'oer-s114b-pol-zz' nor its previousDisplayName 'oer-s114b-pol-yy' matches an assignment policy in access package 'oer-s114b-ap-new', so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new assignment policy, remove previousDisplayName.
[oer-s114b] 4.2 run error: AccessReviewRenameNotFound,Invoke-OERStructure: Neither 'oer-s114b-ar-zz' nor its previousDisplayName 'oer-s114b-ar-yy' matches an access review, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new access review, remove previousDisplayName.
[oer-s114b] 4.2 run errors of Invoke-OERStructure: 2; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 4.2 run sent: token requests: 0; Microsoft Graph requests: 8, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 4.2 after: package policies 2; prefixed reviews 2
RUNNER: check-4.2 exit code 0; started 2026-10-14T13:57:23Z; took 50 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 4.3. An object id as the previous name of a review that does not exist

- [x] **4.3** Microsoft Graph's answer to a review definition id that names nothing is one of the codes the handler declares, so a review entry naming such an id is refused with `AccessReviewRenameNotFound` and nothing is written.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Ids = (Read-S114bIds)['Ids']
$NoSuch = [guid]::NewGuid().ToString()
$Probe = Invoke-OerLiveGraph -Uri "$Ar/$NoSuch"
Write-OerLiveStep "4.3 Microsoft Graph's answer to a review id that names nothing: status $($Probe.Status); body parsed by OerLive: $($null -ne $Probe.Body)"
# The module's own transport, as the handler calls it, without the counting proxies.
$Marker = & (Get-Module -Name Omnicit.EntraRBAC) { param($U) Invoke-OERGraphRequest -Uri $U -ExpectedErrorCode 'NotFound', 'ResourceNotFound', 'Request_ResourceNotFound' } "$Ar/$NoSuch"
Write-OerLiveStep "4.3 the transport's answer: not-found marker $(@($Marker.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError'); declared code matched '$($Marker.ExpectedErrorCode)'; status $($Marker.StatusCode); message '$($Marker.Message)'"
$Before = Get-S114bSnapshot -Ids $Ids
$Json = New-S114bDocument -Section @{ accessReviews = @(New-S114bReviewEntry -Name 'oer-s114b-ar-zz' -Previous $NoSuch -Package $ApNew) }
$null = Invoke-S114bApply -Label '4.3 run' -Json $Json -NoCount
$After = Get-S114bSnapshot -Ids $Ids
Write-OerLiveStep "4.3 nothing written: prefixed reviews $($Before.Reviews.Count) before, $($After.Reviews.Count) after, the same ids: $((ConvertTo-S114bCanonical -Value $Before.Reviews) -ceq (ConvertTo-S114bCanonical -Value $After.Reviews)); review names unchanged: $($Before.ReviewName -ceq $After.ReviewName -and $Before.GroupReviewName -ceq $After.GroupReviewName); review settings unchanged: $($Before.ReviewSettings -ceq $After.ReviewSettings)"
Disconnect-OerLive
```

**Expect:** the probe answers 404; the transport turns it into the not-found marker with a declared code
(`NotFound`, `ResourceNotFound` or `Request_ResourceNotFound`); the run, without the counting proxies: one
Failed row with error `AccessReviewRenameNotFound`; nothing written -- the same two prefixed reviews, their
names and the package review's settings unchanged.
**Failure looks like:** a Failed row carrying Microsoft Graph's own error instead (the code is not
declared: the safe direction, nothing written -- a rule for the handler's declared codes, G11 round).
Run this check WITHOUT the counting proxies (see `Invoke-S114bApply -NoCount` in H.1): under them an answer
with an empty error code reads as `GraphError` (measured in the first run of this check).

Result: 2026-10-14 14:01 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (second run). Measured: Microsoft Graph answers a review definition id that names nothing with 404, an EMPTY error code and the message 'Fusion batch response 0 returned not found for review' plus the id; the transport reads it as the status-derived NotFound, which the handler declares, and returns the not-found marker (ResourceNotFound and Request_ResourceNotFound are not what Graph sends). The run: one Failed row with AccessReviewRenameNotFound; nothing written -- the same two prefixed reviews, their names and the package review's settings unchanged. The first run of this check went through the checklist's counting proxy of Invoke-MgGraphRequest: a global function receives the transport's -StatusCodeVariable and the cmdlet sets it in the proxy's own scope, so the transport could not read the status, and the same answer read as GraphError -- a Failed row with Graph's error as itself, nothing written (writes: 0), the safe direction. The checklist now runs this check without the proxies (Invoke-S114bApply -NoCount); a measurement artefact, not a module defect.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.3 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 4.3 Microsoft Graph's answer to a review id that names nothing: status 404; body parsed by OerLive: False
[oer-s114b] 4.3 the transport's answer: not-found marker True; declared code matched 'NotFound'; status 404; message 'NotFound: Fusion batch response 0 returned not found for review 00000000-0000-0000-0000-000000000006.'
[oer-s114b] 4.3 run rows: 1
[oer-s114b] 4.3 run row: accessReviews | oer-s114b-ar-zz | Failed | neither 'oer-s114b-ar-zz' nor its previousDisplayName '00000000-0000-0000-0000-000000000006' matches an access review, so nothing was created -- right after a rename Microsoft Graph can take a while to resolve the new name, so wait and re-run; to create a new access review, remove previousDisplayName
[oer-s114b] 4.3 run warnings: 0
[oer-s114b] 4.3 run error: AccessReviewRenameNotFound,Invoke-OERStructure: Neither 'oer-s114b-ar-zz' nor its previousDisplayName '00000000-0000-0000-0000-000000000006' matches an access review, so nothing was created or renamed for this entry. Right after a rename Microsoft Graph can take a while to resolve the new name: wait and re-run. To create a new access review, remove previousDisplayName.
[oer-s114b] 4.3 run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 4.3 run sent: not counted (-NoCount); token requests: 0
[oer-s114b] 4.3 nothing written: prefixed reviews 2 before, 2 after, the same ids: True; review names unchanged: True; review settings unchanged: True
RUNNER: check-4.3 exit code 0; started 2026-10-14T14:01:23Z; took 10 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 5. A review of a group under a package review's previous name

### 5.1. Refused, and never renamed

- [x] **5.1** A review entry whose previous name finds only the group review is refused with `AccessReviewScopeMismatch` (the step 2 target check), in the plan and in the run; the group review keeps its name and its scope.

```powershell
Connect-OerLive -Arm
Start-S114bNoPrompt
$Rec = Read-S114bIds
$Ids = $Rec['Ids']
$Json = New-S114bDocument -Section @{ accessReviews = @(New-S114bReviewEntry -Name 'oer-s114b-ar-x' -Previous $GroupRev -Package $ApNew) }
$null = Invoke-S114bApply -Label '5.1 plan' -Json $Json -Plan
$null = Invoke-S114bApply -Label '5.1 run' -Json $Json
$S = Get-S114bSnapshot -Ids $Ids
Write-OerLiveStep "5.1 group review after: name '$($S.GroupReviewName)'; scope unchanged: $($S.GroupReviewQuery -ceq $Rec['Before']['GroupReviewQuery']); prefixed reviews $($S.Reviews.Count)"
Disconnect-OerLive
```

**Expect:** in the plan and in the run: one Failed row with error `AccessReviewScopeMismatch` whose text
says the review in the tenant does not review an access package; `writes: 0` each time; the group
review still `oer-s114b-gr`, its scope unchanged, two prefixed reviews.
**Failure looks like:** a `would rename` or `renamed` row, or any write -- the rename reached a review
of another target.

Result: 2026-10-14 14:02 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. A review entry whose previous name finds only the group review is refused with AccessReviewScopeMismatch in the plan and in the run (the step 2 target check, on the review found under its previous name): the row says the review in the tenant does not review an access package, and that it was found under its previousDisplayName 'oer-s114b-gr'; 2 Microsoft Graph requests and 0 writes each time; read back, the group review is still 'oer-s114b-gr' with its scope unchanged, and there are still two prefixed reviews.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.1 ===
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] 5.1 plan rows: 1
[oer-s114b] 5.1 plan row: accessReviews | oer-s114b-ar-x | Failed | Access review 'oer-s114b-ar-x' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000007/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s114b-ap-new' and assignment policy 'oer-s114b-pol-b'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name. (found under its previousDisplayName 'oer-s114b-gr', id 00000000-0000-0000-0000-000000000005)
[oer-s114b] 5.1 plan warnings: 0
[oer-s114b] 5.1 plan error: AccessReviewScopeMismatch,Invoke-OERStructure: Access review 'oer-s114b-ar-x' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000007/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s114b-ap-new' and assignment policy 'oer-s114b-pol-b'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s114b] 5.1 plan errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 5.1 plan sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 5.1 run rows: 1
[oer-s114b] 5.1 run row: accessReviews | oer-s114b-ar-x | Failed | Access review 'oer-s114b-ar-x' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000007/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s114b-ap-new' and assignment policy 'oer-s114b-pol-b'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name. (found under its previousDisplayName 'oer-s114b-gr', id 00000000-0000-0000-0000-000000000005)
[oer-s114b] 5.1 run warnings: 0
[oer-s114b] 5.1 run error: AccessReviewScopeMismatch,Invoke-OERStructure: Access review 'oer-s114b-ar-x' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000007/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s114b-ap-new' and assignment policy 'oer-s114b-pol-b'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s114b] 5.1 run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s114b] 5.1 run sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s114b] 5.1 group review after: name 'oer-s114b-gr'; scope unchanged: True; prefixed reviews 2
RUNNER: check-5.1 exit code 0; started 2026-10-14T14:01:49Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## T. Teardown

### T.1. Remove every oer-s114b- object

- [x] **T.1** The teardown deletes the two reviews, the policy holding the custom extension stage and the extension, then the other policy, the package, the catalog and the group, then the resource group; the sweep is clean and the counts are the baseline's.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS114bPrereq.ps1'
foreach ($Run in @(@('-Teardown', '-WhatIf'), @('-Teardown', '-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS114bPrereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -NonInteractive -File $Script @Run
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the plan removes nothing; the run deletes both reviews (Teardown A), the policy with the
custom extension stage and the custom extension (Teardown B), then OerLive's teardown removes the other
policy, the package, the catalog and the group with no residue, then the resource group (Teardown D);
the sweep reports no prefixed object and no prefixed review; every count equals the baseline's; exit
code 0.
**Failure looks like:** a `RESIDUE` line or exit code 3 -- the row is in `raw\residue.json`; record it.

Result: 2026-10-14 14:03 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan removes nothing. The run: Teardown A deletes both access reviews (oer-s114b-gr, oer-s114b-ar-new); Teardown B deletes the policy holding the custom extension stage (oer-s114b-pol-a-new, 204) and the custom extension (204); OerLive's teardown removes policy B, the package, the catalog and the group (removed 4, residue 0, unreadable 0); Teardown D deletes the resource group with the Logic App. The sweep reports no prefixed object and no prefixed access review; the resource group no longer exists; every count equals the baseline's (groups 97, catalogs 5, access packages 6, access review definitions 6). Exit code 0; 90 s.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[oer-s114b] === Initialize-OerS114bPrereq.ps1 -Teardown -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s114b\teardown-20261014-140211Z.log".
[oer-s114b] Mode: REMOVE. Prefix 'oer-s114b-'. Objects (fixed): oer-s114b-grp (security group, no member); oer-s114b-cat (catalog, no resource); oer-s114b-ap (hidden access package, no resource role); oer-s114b-rg (tagged) with oer-s114b-la (Logic App, nothing calls it); oer-s114b-ext (custom extension); oer-s114b-pol-a (requestable by the members of oer-s114b-grp only, one question, the custom extension stage); oer-s114b-pol-b (requestable by the members of oer-s114b-grp only); oer-s114b-ar (a review of oer-s114b-ap under oer-s114b-pol-b); oer-s114b-gr (a review of the members of oer-s114b-grp). The names the checklist renames to: oer-s114b-ap-new, oer-s114b-pol-a-new, oer-s114b-ar-new. OerLive 1.0.3.
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
What if: Performing the operation "Delete the access review definition (Graph v1.0 DELETE accessReviews/definitions)" on target "oer-s114b-gr".
What if: Performing the operation "Delete the access review definition (Graph v1.0 DELETE accessReviews/definitions)" on target "oer-s114b-ar-new".
What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s114b-ap-new: assignment policy 'oer-s114b-pol-a-new' (it holds a custom extension stage)".
What if: Performing the operation "Delete (Graph v1.0 DELETE catalogs/customWorkflowExtensions)" on target "oer-s114b-cat: custom extension oer-s114b-ext".
[oer-s114b] Teardown of 'oer-s114b-': users 0, groups 1, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s114b] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s114b] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s114b] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s114b-ap-new: assignment policy 'oer-s114b-pol-b'".
What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s114b-ap-new: assignment policy 'oer-s114b-pol-a-new'".
What if: Performing the operation "Delete the access package (Graph v1.0 DELETE accessPackages)" on target "oer-s114b-ap-new".
What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s114b-cat".
[oer-s114b] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s114b] Teardown 5/6: the prefixed groups.
What if: Performing the operation "Delete the group (Graph v1.0 DELETE groups)" on target "oer-s114b-grp".
[oer-s114b] Teardown 6/6: the prefixed users.
[oer-s114b] Teardown of 'oer-s114b-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
What if: Performing the operation "Delete the resource group and oer-s114b-la in it (Azure Resource Manager DELETE)" on target "oer-s114b-rg".
[oer-s114b] WhatIf: nothing was created, removed or written.
[oer-s114b] Done.
[oer-s114b] exit code: 0
[oer-s114b] === Initialize-OerS114bPrereq.ps1 -Teardown -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114b] Transcript (redacted): raw\s114b\teardown-20261014-140221Z.log; OerLive 1.0.3.
[oer-s114b] Mode: REMOVE. Prefix 'oer-s114b-'. Objects (fixed): oer-s114b-grp (security group, no member); oer-s114b-cat (catalog, no resource); oer-s114b-ap (hidden access package, no resource role); oer-s114b-rg (tagged) with oer-s114b-la (Logic App, nothing calls it); oer-s114b-ext (custom extension); oer-s114b-pol-a (requestable by the members of oer-s114b-grp only, one question, the custom extension stage); oer-s114b-pol-b (requestable by the members of oer-s114b-grp only); oer-s114b-ar (a review of oer-s114b-ap under oer-s114b-pol-b); oer-s114b-gr (a review of the members of oer-s114b-grp). The names the checklist renames to: oer-s114b-ap-new, oer-s114b-pol-a-new, oer-s114b-ar-new. OerLive 1.0.3.
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s114b] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114b] oer-s114b-gr is gone: converged after 1 read(s), 0.4 s.
[oer-s114b] Teardown A: deleted access review oer-s114b-gr.
[oer-s114b] oer-s114b-ar-new is gone: converged after 1 read(s), 0.3 s.
[oer-s114b] Teardown A: deleted access review oer-s114b-ar-new.
[oer-s114b] Teardown B: deleted oer-s114b-ap-new: assignment policy 'oer-s114b-pol-a-new' (it holds a custom extension stage) (204).
[oer-s114b] Teardown B: deleted custom extension oer-s114b-ext (204, 1 attempt(s)).
[oer-s114b] Teardown of 'oer-s114b-': users 0, groups 1, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s114b] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s114b] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s114b] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s114b] Deleted: oer-s114b-ap-new: assignment policy 'oer-s114b-pol-b' (204).
[oer-s114b] Deleted: access package oer-s114b-ap-new (204, 1 attempt(s)).
[oer-s114b] Deleted: catalog oer-s114b-cat (204, 1 attempt(s)).
[oer-s114b] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s114b] Teardown 5/6: the prefixed groups.
[oer-s114b] Deleted: group oer-s114b-grp (204).
[oer-s114b] Teardown 6/6: the prefixed users.
[oer-s114b] Teardown of 'oer-s114b-': removed 4, residue 0, unreadable 0.
[oer-s114b] oer-s114b-rg is gone: not yet (read 1, 0.4 s, likely replication delay) -- reading again in 2 s.
[oer-s114b] oer-s114b-rg is gone: not yet (read 2, 2.9 s, likely replication delay) -- reading again in 4 s.
[oer-s114b] oer-s114b-rg is gone: not yet (read 3, 7.2 s, likely replication delay) -- reading again in 8 s.
[oer-s114b] oer-s114b-rg is gone: not yet (read 4, 15.3 s, likely replication delay) -- reading again in 16 s.
[oer-s114b] oer-s114b-rg is gone: not yet (read 5, 31.7 s, likely replication delay) -- reading again in 30 s.
[oer-s114b] oer-s114b-rg is gone: converged after 6 read(s), 62.1 s.
[oer-s114b] Teardown D: deleted oer-s114b-rg and oer-s114b-la.
[oer-s114b] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s114b-' is left.
[oer-s114b] no 'oer-s114b-' object is listed: converged after 1 read(s), 0.4 s.
[oer-s114b] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s114b-' is left.
[oer-s114b] Access reviews with the prefix after the teardown: 0
[oer-s114b] Resource group oer-s114b-rg exists after the teardown: False
[oer-s114b] Counts: groups now 97, at the baseline 97; equal: True
[oer-s114b] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s114b] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s114b] Counts: accessReviewDefinitions now 6, at the baseline 6; equal: True
[oer-s114b] Removed the recorded ids.
[oer-s114b] Done.
[oer-s114b] exit code: 0
RUNNER: check-T.1 exit code 0; started 2026-10-14T14:02:09Z; took 90 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### T.2. Read back

- [x] **T.2** A read-back a minute later finds no prefixed object or review, no resource group, the baseline's counts and no residue row of this step.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS114bPrereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -ReadBack
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `access reviews with the prefix: 0`, `resource group ... exists: False`, `prefixed objects
left: 0`, every count equal, `of them with this step's prefix: 0`.
**Failure looks like:** a prefixed object (a listing that lags: run again a minute later) or a residue row.

Result: 2026-10-14 14:04 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. A read-back after the teardown: no prefixed object and no prefixed access review is left, the resource group does not exist, every count equals the baseline's, and raw\residue.json holds 5 rows of other projects and none of this step's.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.2 ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s114b] Transcript (redacted): raw\s114b\readback-20261014-140354Z.log; OerLive 1.0.3.
[oer-s114b] Mode: READ BACK. Prefix 'oer-s114b-'. Objects (fixed): oer-s114b-grp (security group, no member); oer-s114b-cat (catalog, no resource); oer-s114b-ap (hidden access package, no resource role); oer-s114b-rg (tagged) with oer-s114b-la (Logic App, nothing calls it); oer-s114b-ext (custom extension); oer-s114b-pol-a (requestable by the members of oer-s114b-grp only, one question, the custom extension stage); oer-s114b-pol-b (requestable by the members of oer-s114b-grp only); oer-s114b-ar (a review of oer-s114b-ap under oer-s114b-pol-b); oer-s114b-gr (a review of the members of oer-s114b-grp). The names the checklist renames to: oer-s114b-ap-new, oer-s114b-pol-a-new, oer-s114b-ar-new. OerLive 1.0.3.
[oer-s114b] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg4b\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s114b] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s114b] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s114b] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s114b-' is left.
[oer-s114b] Read-back: access reviews with the prefix: 0
[oer-s114b] Read-back: resource group oer-s114b-rg exists: False
[oer-s114b] Counts: groups now 97, at the baseline 97; equal: True
[oer-s114b] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s114b] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s114b] Counts: accessReviewDefinitions now 6, at the baseline 6; equal: True
[oer-s114b] Read-back: residue row: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:09Z, attempts 3: 404 SubjectNotFound The subject is not found.; read back: still listed -- OerLive: Residue: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal': read back after the 'does not exist' answer -- not converged within budget (180 s, 10 reads).
[oer-s114b] Read-back: residue row: PIM for Groups assignment 'opim-s1-grp: PIM for Groups owner assignment of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:12Z, attempts 3: 403 UnauthorizedAccessException {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup,PrivilegedAccess.ReadWrite.AzureADGroup,PrivilegedAssignmentSchedule.Remove.AzureADGroup.","instanceAnnotations":[]}
[oer-s114b] Read-back: residue row: PIM for Groups eligibility 'opim-s2-grp: PIM for Groups member eligibility of a principal' (prefix opim-s2-), first refused 2026-10-10T23:39:01Z, attempts 1: 400 BadRequest {"error":{"code":"Request_BadRequest","message":"The source resource object or one of the objects being referenced do not exist.","innerError":{"date":"2026-10-10T23:39:01","request-id":"00000000-0000-0000-0000-000000000008","client-request-id":"00000000-0000-0000-0000-000000000009"}}}
[oer-s114b] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-10T23:39:02Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s114b] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-11T14:55:13Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s114b] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 5, of them with this step's prefix: 0.
[oer-s114b] Done.
[oer-s114b] exit code: 0
RUNNER: check-T.2 exit code 0; started 2026-10-14T14:03:52Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## B. Proved offline only (class B)

These are held by unit tests that run in CI (the gate), not by this file:

- **A review naming the new name of a POLICY renamed in the same run, and the refusal of a review whose
  package or policy rename was refused or left undecided** (a lookup that failed, `-Include` leaving the
  access packages out, an entry that stopped early -- marked under every package id it knew):
  `tests/Unit/Private/Sync-OERStructureAccessReview.Tests.ps1`, Describe 'Sync-OERStructureAccessReview
  reaches an access package or assignment policy the run renames through the rename map (BL-128 part 2)';
  `tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1`, Context 'the run''s rename map';
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`, Describe 'Invoke-OERStructure: an access review reaches
  an access package or assignment policy the same document renames (BL-128 part 2)', its runs in a script
  with no `try`.
- **An ambiguous previous name, a failed rename, an object id as a policy's previous name, a rename in a
  package the run creates, a read-back that does not carry the new name**: the Context 'renaming an
  assignment policy in place, within its package' of the package handler tests, and the Describe
  'Sync-OERStructureAccessReview renames a review through previousDisplayName (BL-128)';
  `tests/Unit/Private/Resolve-OERStructureRename.Tests.ps1`.
- **A16 in the cmdlet** (a rename alone sends one GET and one PUT carrying the stages and the automatic
  settings; the same name ignoring case is `NothingToUpdate`; a failed read is itself):
  `tests/Unit/Public/Set-OERAccessPackageAssignmentPolicy.Tests.ps1`, the two A16 Describes, and
  `tests/Unit/Public/NothingToUpdate.Cohort.Tests.ps1`. Section 1 runs the rename alone live.
- **A failed read of a catalog or its resources (BL-144)**: `tests/Unit/Private/Sync-OERStructureCatalog.Tests.ps1`,
  Context 'a failed read of the live catalog or its resources (BL-144, D7)'.
- **The validator** (the key on both kinds, the case-only Warning, the duplicate claims inside a package, the
  Warning for a review naming a policy by its previous name, Rule 15):
  `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1`, Describe 'Test-OERStructureSchema renames of
  assignment policies (BL-128, Sprint 11 step 4b)' and Describe 'Test-OERStructureSchema refuses a review
  naming an access package that several entries declare while one renames it (Rule 15, Sprint 11 step 4b)';
  the schema in `tests/Unit/Private/Get-OERStructureSchemaJson.Tests.ps1`.
- **The texts**: `tests/QA/about.tests.ps1`, `tests/QA/docsync.tests.ps1`, `tests/QA/dochygiene.tests.ps1`,
  `tests/QA/module.tests.ps1` (help and the release note), and
  `tests/Unit/Private/Get-OERInventoryPromptTemplate.Tests.ps1`.
