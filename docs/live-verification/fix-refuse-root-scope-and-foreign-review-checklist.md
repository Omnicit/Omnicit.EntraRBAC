# Live verification checklist -- the root scope and a review of another package (fix/refuse-root-scope-and-foreign-review)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4 and T has a written
result.** A box with no result line filled in is not a passed check -- it is an unrun one. If a check
turns out to be impossible to run, write "cannot be verified, and therefore we do not know" on its
result line and say why; do not leave it blank and do not tick it. A check that could not run for a
stated reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).**
This step has no manual check (class C).

**What this file writes to the tenant: only inside the prefix `oer-s112-`.** The prerequisite script
`Initialize-OerS112Prereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates a security group `oer-s112-group` with no member, a catalog `oer-s112-catalog`, a hidden access
package `oer-s112-ap` in it with no resource, an assignment policy `oer-s112-policy` on the package that
only an administrator can assign through, a tagged empty resource group `oer-s112-rg` in the test
subscription, and -- raw, through Microsoft Graph -- an access review `oer-s112-review` of the MEMBERS
OF `oer-s112-group`: a group review, quarterly, first instance 14 days after the run, each instance 1
day long. Section 1 applies a document that declares a PACKAGE review with that same display name; it
must write nothing. Section 2 creates the package review `oer-s112-review-pkg` through
`Invoke-OERStructure` and changes its description once. Section 3 creates one role assignment, Reader
at `oer-s112-rg` for `oer-s112-group`, through `Invoke-OERStructure`, and declares one more at the
root scope `/` that must never be read or written. Section 4 reads only. No review instance starts
during the run and nobody is asked to review anything. The teardown (T.1) deletes the two reviews,
the role assignment, the policy, the package, the catalog, the group and the resource group. Bundles,
documents and request counts are written under `raw\s112\`, which is deleted after the results are
written.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401
or 403 as `oer-live-cc` is a stop.

**Permission.** The access reviews need the Microsoft Graph application permission
`AccessReview.ReadWrite.All`, the package objects `EntitlementManagement.ReadWrite.All`; check 0.2
reads both and STOPS the run before anything is written when one is missing, and the prerequisite
script refuses its setup the same way. The role assignment at the resource group needs the right to
write role assignments there, which `oer-live-cc` used in Sprint 10 step 9. A role assignment AT the
root scope `/` needs elevated access, which `oer-live-cc` does not hold and must not be given: that
half is class B (section B). Granting a permission is the operator's decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block installs
the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s112/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line, a warning and an error that
stops a script go straight to the host, so each block is run in its own process whose WHOLE output
(standard output and standard error) is written to a file under `raw\s112\`, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The root scope is never exported, applied or pruned** ("fix: never export, apply or prune a
  role assignment at the root scope", and "fix: treat every spelling the ARM transport sends to the
  root as the root scope", which also covers a scope such as `/.` that the request's URI resolves to
  the root). `Get-OERInventory` leaves a role assignment at the Azure root
  scope `/` out of the document, with one warning, and hands the rows to its caller on the
  information stream; `Export-OERInventory` leaves them out of `inventory.json` and
  `roleAssignments.json`, warns once and names them in the bundle README under "Role assignments at
  the root scope (elevated access)"; the validator reports a `roleAssignments` entry at `/` as a
  Warning; and `Invoke-OERStructure` reports such an entry Skipped before any lookup or request, never
  creates a role assignment there and never prunes the root scope.
- **B. A review of another package is refused** ("fix: update an access review only when it reviews the
  declared package and policy"). An access review found by display name is updated only when it
  reviews the access package and assignment policy the document entry declares (a GUID compared as
  it is, a name resolved the way creation resolves it). A review of a group or a role, another
  package or another policy makes the entry Failed with `AccessReviewScopeMismatch`, and nothing is
  written, in the plan and in the run. A package or policy name that is not unique is refused as
  ambiguous, so such an entry names it by id.
- **C. The texts** ("docs: say that the root scope is never applied and a review of another package is refused" and "docs: say that a shared package or policy name must be an id and how the root scope is recognised"): the help, the bundle README, the prompt template, README, the
  about topic, the rationale and the release note.

A live tenant is needed for B because the claim is about what is sent to a real definition that
Microsoft Graph lists by name: that a real group review carrying the package review's name is left
exactly as it was, and that a real package review still converges. A is needed live for what the
test tenant can carry: that the engine sends no request at all for an entry at `/` while it applies
and prunes another scope of the same document, and that an export of the test subscription carries no
row at `/`.

## What this file does not check, and why

- **A role assignment that really exists at the root scope (class B, unless the tenant has one).**
  Creating one needs an elevated identity, which `oer-live-cc` is not and must not become. Section 4
  reads the test subscription: when the tenant does hold one, the read shows it and the export names
  it as a finding; when it holds none, the export's handling of such a row is proved by the unit tests
  named in section B.
- **Whether Azure Resource Manager accepts the path `//providers/...` that the module built for `/`
  before this branch.** The branch never sends it any more; measuring it needs an elevated identity.
- **C, the texts (class B).** They change what the help says, not what is sent. Section B names the
  gates that hold them.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, holding
  `AccessReview.ReadWrite.All` and `EntitlementManagement.ReadWrite.All` (0.2 reads both).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 reads that it was not).
- The **prerequisite objects**: check 0.3 runs `Initialize-OerS112Prereq.ps1 -WhatIf`, then
  `-Unattended` twice, with `OER_LIVE_REPO` set.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the
counters and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s112-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ar = 'v1.0/identityGovernance/accessReviews/definitions'
$Em = 'v1.0/identityGovernance/entitlementManagement'
$GroupName = 'oer-s112-group'
$Package = 'oer-s112-ap'
$Policy = 'oer-s112-policy'
$RgName = 'oer-s112-rg'
$Review = 'oer-s112-review'
$PkgReview = 'oer-s112-review-pkg'
# Tenant values come from the configuration and are never printed: every line goes through the redactor.
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
$RgScope = "$SubScope/resourceGroups/$RgName"
# The package review's first instance starts two weeks after the run (UTC midnight), so no instance starts during it.
$Start = [datetime]::UtcNow.Date.AddDays(14)
$StartText = $Start.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
# The step's raw folder as OerLive fixed it (git-ignored).
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Needed = @('AccessReview.ReadWrite.All', 'EntitlementManagement.ReadWrite.All')
# The deliberately non-existent object id of the placeholder register (...099), built here so no id is typed.
$Missing099 = [guid]::Empty.ToString().Substring(0, 34) + '99'

function Start-S112NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S112TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S112TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S112 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S112Count {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is
    # a GET. An Azure Resource Manager request whose path starts with one or more '/' followed by
    # providers/Microsoft.Authorization/ is a request AT THE ROOT SCOPE '/', and is counted as such.
    $global:S112Graph = [System.Collections.Generic.List[string]]::new()
    $global:S112Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Root = '$(try { $P = ([uri][string]$Uri).AbsolutePath } catch { $P = [string]$Uri }; if ($P -match ''^/+providers/Microsoft\.Authorization/'') { ''|root'' } else { '''' })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S112Graph.Add(`$($Record)); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S112Arm.Add((`$($Record)) + $Root); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S112Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S112Sent {
    # Requests counted since Start-S112Count: writes (any method but GET), and ARM requests at the root scope.
    $GraphWrites = @($global:S112Graph | Where-Object { $_ -ne 'GET' })
    $ArmMethods = @($global:S112Arm | ForEach-Object { ($_ -split '\|')[0] })
    $ArmWrites = @($ArmMethods | Where-Object { $_ -ne 'GET' })
    $ArmRoot = @($global:S112Arm | Where-Object { $_ -like '*|root' })
    "token requests: $global:S112TokenCalls; Microsoft Graph requests: $($global:S112Graph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S112Arm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" }), at the root scope: $($ArmRoot.Count)"
}

function Get-S112GrantedRole {
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

function Get-S112Definition {
    # One access review definition by its exact display name, read raw from Microsoft Graph (every
    # definition is listed and matched here: the endpoint ignores startswith filters). $null when absent.
    param([Parameter(Mandatory)][string]$Name)
    $L = Invoke-OerLiveGraph -All -Uri $Ar
    Assert-OerLiveOk -Response $L -Activity 'Listing the access review definitions' | Out-Null
    $Hits = @(@($L.Body['value']) | Where-Object { $null -ne $_ -and [string]$_['displayName'] -ceq $Name })
    if ($Hits.Count -gt 1) { throw "STOP: $Name matches $($Hits.Count) access review definitions." }
    if ($Hits.Count -eq 0) { return $null }
    $One = Invoke-OerLiveGraph -Uri "$Ar/$([string]$Hits[0]['id'])"
    Assert-OerLiveOk -Response $One -Activity "Reading $Name" | Out-Null
    $One.Body
}

function Get-S112Ids {
    # The ids of the group, the package and the policy, read raw (compared and written into documents,
    # never printed).
    $G = Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq '$GroupName'"))
    Assert-OerLiveOk -Response $G -Activity "Reading $GroupName" | Out-Null
    $P = Invoke-OerLiveGraph -All -Uri ("$Em/accessPackages?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq '$Package'"))
    Assert-OerLiveOk -Response $P -Activity "Reading $Package" | Out-Null
    $Gs = @(@($G.Body['value']) | Where-Object { $null -ne $_ }); $Ps = @(@($P.Body['value']) | Where-Object { $null -ne $_ })
    if ($Gs.Count -ne 1 -or $Ps.Count -ne 1) { throw "STOP: $GroupName matches $($Gs.Count) groups and $Package $($Ps.Count) packages, not one each." }
    $PackageId = ([string]$Ps[0]['id']).ToLowerInvariant()
    $L = Invoke-OerLiveGraph -All -Uri ("$Em/assignmentPolicies?`$filter={0}" -f [uri]::EscapeDataString("accessPackage/id eq '$PackageId'"))
    Assert-OerLiveOk -Response $L -Activity "Reading the policies of $Package" | Out-Null
    $Pol = @(@($L.Body['value']) | Where-Object { $null -ne $_ -and [string]$_['displayName'] -ceq $Policy })
    if ($Pol.Count -ne 1) { throw "STOP: $Policy matches $($Pol.Count) policies of $Package, not one." }
    [PSCustomObject]@{ GroupId = ([string]$Gs[0]['id']).ToLowerInvariant(); PackageId = $PackageId; PolicyId = ([string]$Pol[0]['id']).ToLowerInvariant() }
}

function Get-S112ReviewShape {
    # What a write would change on a definition, as one comparable string, and its readable summary.
    param([Parameter(Mandatory)][object]$Definition, [Parameter(Mandatory)][object]$Ids)
    $Shape = [ordered]@{
        descriptionForAdmins    = [string]$Definition['descriptionForAdmins']
        descriptionForReviewers = [string]$Definition['descriptionForReviewers']
        scopeQuery              = [string]$Definition['scope']['query']
        reviewers               = ConvertTo-Json -InputObject @($Definition['reviewers']) -Depth 10 -Compress
        settings                = ConvertTo-Json -InputObject $Definition['settings'] -Depth 10 -Compress
        lastModifiedDateTime    = [string]$Definition['lastModifiedDateTime']
    }
    [PSCustomObject]@{
        Text            = ConvertTo-Json -InputObject $Shape -Depth 5 -Compress
        ReviewsTheGroup = ($Shape.scopeQuery -ceq "/groups/$($Ids.GroupId)/transitiveMembers")
        ReviewsPackage  = ($Shape.scopeQuery -match [regex]::Escape($Ids.PackageId)) -and ($Shape.scopeQuery -match [regex]::Escape($Ids.PolicyId))
        Description     = $Shape.descriptionForAdmins
        LastModified    = $Shape.lastModifiedDateTime
    }
}

function New-S112Document {
    # A structure document holding the given access review or role assignment entries.
    param([object[]]$Reviews, [object[]]$RoleAssignments)
    $Doc = [ordered]@{ version = '1.0' }
    if ($PSBoundParameters.ContainsKey('Reviews')) { $Doc.accessReviews = @($Reviews) }
    if ($PSBoundParameters.ContainsKey('RoleAssignments')) { $Doc.roleAssignments = @($RoleAssignments) }
    $Doc | ConvertTo-Json -Depth 20
}

function New-S112PackageReview {
    # The access review entry this file's documents declare: a self review, quarterly from two weeks ahead.
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$AccessPackage, [Parameter(Mandatory)][string]$AssignmentPolicy, [Parameter(Mandatory)][string]$Description)
    [ordered]@{
        displayName = $Name; accessPackage = $AccessPackage; assignmentPolicy = $AssignmentPolicy
        descriptionForAdmins = $Description; descriptionForReviewers = 'Omnicit.EntraRBAC live verification: there is nothing to review.'
        reviewers = @(); recurrence = 'Quarterly'; startDate = $StartText; durationInDays = 14
    }
}

function Write-S112Rows {
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Rows)
    # An if-statement assignment unrolls no rows to $null, and @($null).Count is 1: drop nulls first.
    $Rows = @(@($Rows) | Where-Object { $null -ne $_ })
    Write-OerLiveStep "$Label rows: $($Rows.Count)"
    foreach ($R in @($Rows)) { Write-OerLiveStep "$Label row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
}

function Invoke-S112Apply {
    # One Invoke-OERStructure call -- a -WhatIf plan or a run, with or without -Prune -- counted from its
    # first request to its last. The document is kept under raw\s112. Warnings are captured on the stream
    # (3>&1), where each is written once, and printed through the redactor.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json, [switch]$Plan, [switch]$Prune)
    [System.IO.File]::WriteAllText((Join-Path $Raw ('doc-{0}.json' -f ($Label -replace '[^0-9A-Za-z.]', '_'))), $Json, [System.Text.UTF8Encoding]::new($false))
    $Params = @{ Json = $Json; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'E' }
    if ($Plan) { $Params.WhatIf = $true } else { $Params.Confirm = $false }
    if ($Prune) { $Params.Prune = $true }
    Start-S112Count
    $E = $null
    try {
        $Out = @(Invoke-OERStructure @Params 3>&1)
        $Sent = Get-S112Sent
    } finally { Stop-S112Count }
    $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
    Write-S112Rows -Label $Label -Rows @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-OerLiveStep "$Label warnings: $($Warnings.Count)"
    foreach ($T in $Warnings) { Write-OerLiveStep "$Label warning: $T" }
    $Own = @(@($E) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure', [System.StringComparison]::Ordinal) })
    foreach ($X in $Own) { Write-OerLiveStep "$Label error: $([string]$X.FullyQualifiedErrorId): $([string]$X.Exception.Message)" }
    Write-OerLiveStep "$Label errors of Invoke-OERStructure: $($Own.Count); other items in -ErrorVariable (counted, not printed): $(@($E).Count - $Own.Count)"
    Write-OerLiveStep "$Label sent: $Sent"
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
Write-OerLiveStep "The worktree's build carries A: root predicate $(& $Has 'function Test-OERAzureRootScope'); information tag $(& $Has "'Omnicit.EntraRBAC.RootScopeAssignment'"); README section $(& $Has '## Role assignments at the root scope (elevated access)'); URI spelling check $(& $Has 'scope.invalid')"
Write-OerLiveStep "The worktree's build carries B: target check $(& $Has 'function Get-OERAccessReviewTargetMismatch'); refusal id $(& $Has "'AccessReviewScopeMismatch'"); policy lookup $(& $Has 'function Resolve-OERAssignmentPolicyId')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; every mark `True` on the last two
lines.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last two lines -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result:

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, and `The module is the worktree's
build: True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result:

### 0.2. The permissions this file needs

- [ ] **0.2** `oer-live-cc` holds both Microsoft Graph permissions; otherwise the run stops here.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Granted = Get-S112GrantedRole
foreach ($Name in $Needed) { Write-OerLiveStep "oer-live-cc holds $($Name): $($Granted -ccontains $Name)" }
$Missing = @($Needed | Where-Object { $Granted -cnotcontains $_ })
if ($Missing.Count -gt 0) { Write-OerLiveStep "STOP: missing $($Missing -join ', ') (G11.7: granting it is the operator's decision)." }
Disconnect-OerLive
```

**Expect:** `oer-live-cc holds AccessReview.ReadWrite.All: True` and `... EntitlementManagement.ReadWrite.All: True`.
**Failure looks like:** a `False` and the STOP line -- stop the run; nothing has been written.

Result:

### 0.3. The prerequisite objects

- [ ] **0.3** The plan writes nothing; the first run creates the six objects; a second run writes nothing.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS112Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS112Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -NonInteractive -File $Script @Run
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run ends `WhatIf: nothing was created, removed or written.` with exit code
0; the first `-Unattended` run writes the baseline and creates the group, the catalog, the package,
the policy, the resource group and the review (`written to the tenant: True`), exit code 0; the
second finds all six (`... present`) and writes nothing (`written to the tenant: False`), exit code 0.
**Failure looks like:** a `Refusing to run:` line or exit code 1 -- read the reason; nothing past it
was written.

Result:

## 1. A group review that carries a package review's name is refused

### 1.1. The group review before

- [ ] **1.1** `oer-s112-review` exists and reviews the members of `oer-s112-group`; its state is recorded.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$D = Get-S112Definition -Name $Review
$S = Get-S112ReviewShape -Definition $D -Ids $Ids
[System.IO.File]::WriteAllText((Join-Path $Raw 'review-before.json'), $S.Text, [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "1.1 $Review exists: $($null -ne $D); reviews the members of $($GroupName): $($S.ReviewsTheGroup); reviews $($Package): $($S.ReviewsPackage)"
Write-OerLiveStep "1.1 description: $($S.Description)"
Write-OerLiveStep "1.1 state recorded under raw\s112 (lastModifiedDateTime present: $([bool]$S.LastModified))"
Disconnect-OerLive
```

**Expect:** `exists: True; reviews the members of oer-s112-group: True; reviews oer-s112-ap: False`.
**Failure looks like:** `False` on the first two -- run 0.3 again.

Result:

### 1.2. The plan refuses it

- [ ] **1.2** A document declaring a PACKAGE review named `oer-s112-review` plans `Failed` with `AccessReviewScopeMismatch`, and sends no write.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $Review -AccessPackage $Package -AssignmentPolicy $Policy -Description 'Written by the s112 document: it must never reach the group review.')
Invoke-S112Apply -Label '1.2 plan' -Json $Doc -Plan
Disconnect-OerLive
```

**Expect:** one row `accessReviews | oer-s112-review | Failed | Access review 'oer-s112-review' in the
tenant does not review an access package (its scope is '/groups/` + the group's id +
`/transitiveMembers'), so it is not the review this entry declares for access package 'oer-s112-ap'
and assignment policy 'oer-s112-policy'. Nothing was written. Access review display names are not
unique: give the entry or the review in the tenant another display name.`; `1.2 plan error:
AccessReviewScopeMismatch,Invoke-OERStructure:` with the same message; `errors of
Invoke-OERStructure: 1`; `Microsoft Graph requests: N, writes: 0`; no `What if:` line.
**Failure looks like:** `Skipped | would update access review` -- the branch's check did not run; or
any Graph write.

Result:

### 1.3. The run refuses it and writes nothing

- [ ] **1.3** The same document, applied, is `Failed` with `AccessReviewScopeMismatch`, and sends no write.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $Review -AccessPackage $Package -AssignmentPolicy $Policy -Description 'Written by the s112 document: it must never reach the group review.')
Invoke-S112Apply -Label '1.3 run' -Json $Doc
Disconnect-OerLive
```

**Expect:** the same row and error as 1.2; `writes: 0` for Microsoft Graph.
**Failure looks like:** `Updated`, or a `PUT` among the writes -- the defect this branch fixes (BL-127).

Result:

### 1.4. The group review is unchanged

- [ ] **1.4** Read back, `oer-s112-review` is exactly as 1.1 recorded it.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$S = Get-S112ReviewShape -Definition (Get-S112Definition -Name $Review) -Ids $Ids
$Before = [System.IO.File]::ReadAllText((Join-Path $Raw 'review-before.json'))
Write-OerLiveStep "1.4 reviews the members of $($GroupName): $($S.ReviewsTheGroup); description: $($S.Description)"
Write-OerLiveStep "1.4 descriptions, scope, reviewers, settings and lastModifiedDateTime equal to 1.1: $($S.Text -ceq $Before)"
Disconnect-OerLive
```

**Expect:** `reviews the members of oer-s112-group: True`, the description of 1.1, and `equal to 1.1: True`.
**Failure looks like:** `False` -- a write reached the group review.

Result:

## 2. A package review with the right package is updated as before

### 2.1. The package review is created through the document

- [ ] **2.1** A document declaring `oer-s112-review-pkg` for `oer-s112-ap` and `oer-s112-policy` creates it: `Created`, one POST.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $PkgReview -AccessPackage $Package -AssignmentPolicy $Policy -Description 'Omnicit.EntraRBAC live verification (oer-s112-): version 1.')
Invoke-S112Apply -Label '2.1 run' -Json $Doc
$W = Wait-OerLiveConverged -Activity "$PkgReview is listed" -Read { Get-S112Definition -Name $PkgReview } -Test { $null -ne $args[0] }
$S = Get-S112ReviewShape -Definition $W.Value -Ids $Ids
Write-OerLiveStep "2.1 $PkgReview reviews $Package and $($Policy): $($S.ReviewsPackage); description: $($S.Description)"
Disconnect-OerLive
```

**Expect:** `accessReviews | oer-s112-review-pkg | Created`; Graph writes 1 (`POST`); `reviews oer-s112-ap and oer-s112-policy: True`.
**Failure looks like:** `Failed` -- read the Detail.

Result:

### 2.2. A change of description, by name: planned, then Updated

- [ ] **2.2** With the package and policy given by NAME, a changed description plans an update (no write) and the run updates it (one PUT).

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $PkgReview -AccessPackage $Package -AssignmentPolicy $Policy -Description 'Omnicit.EntraRBAC live verification (oer-s112-): version 2.')
Invoke-S112Apply -Label '2.2 plan' -Json $Doc -Plan
Invoke-S112Apply -Label '2.2 run' -Json $Doc
$W = Wait-OerLiveConverged -Activity "$PkgReview carries version 2" -Read { Get-S112Definition -Name $PkgReview } -Test { [string]$args[0]['descriptionForAdmins'] -like '*version 2.' }
Write-OerLiveStep "2.2 after the run: description: $([string]$W.Value['descriptionForAdmins'])"
Disconnect-OerLive
```

**Expect:** the plan `Skipped | would update access review 'oer-s112-review-pkg'
(descriptionForAdmins=Omnicit.EntraRBAC live verification (oer-s112-): version 2.)` with writes 0; the
run `Updated | updated access review 'oer-s112-review-pkg' (descriptionForAdmins=...)` with one Graph
`PUT`; the description ends `version 2.`.
**Failure looks like:** `Failed` with `AccessReviewScopeMismatch` -- the check refused the review it should
accept.

Result:

### 2.3. The same document twice more: only Unchanged (G8)

- [ ] **2.3** Two more runs of 2.2's document report `Unchanged` and write nothing.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $PkgReview -AccessPackage $Package -AssignmentPolicy $Policy -Description 'Omnicit.EntraRBAC live verification (oer-s112-): version 2.')
Invoke-S112Apply -Label '2.3 run 1' -Json $Doc
Invoke-S112Apply -Label '2.3 run 2' -Json $Doc
Disconnect-OerLive
```

**Expect:** each run one row `Unchanged | access review 'oer-s112-review-pkg' already matches`, writes 0.
**Failure looks like:** `Updated` on a run -- no convergence.

Result:

### 2.4. The package and the policy by their ids: Unchanged

- [ ] **2.4** The same entry with `accessPackage` and `assignmentPolicy` given as their GUIDs is `Unchanged`, with no write.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $PkgReview -AccessPackage $Ids.PackageId -AssignmentPolicy $Ids.PolicyId -Description 'Omnicit.EntraRBAC live verification (oer-s112-): version 2.')
Invoke-S112Apply -Label '2.4 run' -Json $Doc
Disconnect-OerLive
```

**Expect:** one row `Unchanged`, writes 0.
**Failure looks like:** `Failed` -- the GUID comparison does not match the live ids.

Result:

### 2.5. Another package by GUID: refused, nothing written

- [ ] **2.5** The same entry naming a package id that is not the review's (the register's non-existent `...099`) is `Failed` with `AccessReviewScopeMismatch`, and the description stays.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $PkgReview -AccessPackage $Missing099 -AssignmentPolicy $Ids.PolicyId -Description 'Written by the s112 document: it must never be stored.')
Invoke-S112Apply -Label '2.5 run' -Json $Doc
$D = Get-S112Definition -Name $PkgReview
Write-OerLiveStep "2.5 after the run: description: $([string]$D['descriptionForAdmins'])"
Disconnect-OerLive
```

**Expect:** one row `Failed | Access review 'oer-s112-review-pkg' in the tenant reviews access package`
+ the package's id + `, not the access package` + the `...099` id + `this entry declares, so it is not
the review this entry declares. Nothing was written. Access review display names are not unique: give
the entry or the review in the tenant another display name.`; the error
`AccessReviewScopeMismatch,Invoke-OERStructure`; writes 0, and no lookup of the package (the id is
compared as written); the description still ends `version 2.`.
**Failure looks like:** `Updated`, or a `PUT` -- before this branch, a different GUID was only noted while
the other changes were written.

Result:

## 3. A role assignment at the root scope is never read, written or pruned

### 3.1. The validator flags it

- [ ] **3.1** `Test-OERStructure` reports the entries at `/` and `/.` as Warnings at `roleAssignments[0].scope` and `roleAssignments[1].scope`; the document stays valid.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -RoleAssignments @(
    [ordered]@{ scope = '/'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = '/.'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = $RgScope; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
)
$V = Test-OERStructure -Json $Doc
Write-OerLiveStep "3.1 valid: $($V.Valid); findings: $(@($V.Errors).Count)"
foreach ($F in @($V.Errors)) { Write-OerLiveStep "3.1 finding: $($F.Severity) | $($F.Path) | $($F.Message)" }
Disconnect-OerLive
```

**Expect:** `valid: True; findings: 2`: `Warning | roleAssignments[0].scope | 'scope' at
roleAssignments[0] is the root scope '/', which grants access over every management group and
subscription in the tenant (elevated access). Invoke-OERStructure never creates or removes a role
assignment there: the entry is reported Skipped and the root scope is never pruned. Remove the entry
and manage elevated access outside the document.`, and the same Warning at `roleAssignments[1]` for
`/.`, a spelling the Azure Resource Manager request sends to the root too.
**Failure looks like:** no finding for one of the two (the validator accepted `/` silently before the
branch, and `/.` before its final fix), or an `Error`.

Result:

### 3.2. The plan with -Prune: Skipped, and no request at the root scope

- [ ] **3.2** `Invoke-OERStructure -Prune -WhatIf` reports the two root entries (`/` and `/.`) `Skipped` with their reason and sends no Azure Resource Manager request at the root, while it plans the resource group's assignment.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -RoleAssignments @(
    [ordered]@{ scope = '/'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = '/.'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = $RgScope; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
)
Invoke-S112Apply -Label '3.2 plan' -Json $Doc -Plan -Prune
Disconnect-OerLive
```

**Expect:** `roleAssignments | Reader -> oer-s112-group @ / | Skipped | the root scope '/' grants access
over every management group and subscription in the tenant (elevated access), and the apply engine
never creates or removes a role assignment there, and never prunes it. Nothing was read or written for
this entry`, and the same for `Reader -> oer-s112-group @ /.`; the resource group's row `Skipped |
would create role assignment 'Reader' for 'oer-s112-group' at ...`; two warnings
`Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated
access); the apply engine never creates or removes a role assignment there. Nothing was read or
written for this entry.`; `Azure Resource Manager requests: N` with N above 0, `writes: 0`, `at the
root scope: 0` (the counter reads each request's path after the URI normalisation, so `/./providers/...`
counts as the root).
**Failure looks like:** `at the root scope:` above 0 -- a lookup or read at the root was sent; or a row
`would create ... at '/'` or `at '/.'`.

Result:

### 3.3. The run with -Prune: Skipped at the root, Created at the resource group

- [ ] **3.3** The same document, applied with `-Prune`, skips the two root entries and creates the resource group's assignment, with no request at the root.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -RoleAssignments @(
    [ordered]@{ scope = '/'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = '/.'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = $RgScope; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
)
Invoke-S112Apply -Label '3.3 run' -Json $Doc -Prune
Disconnect-OerLive
```

**Expect:** the two root rows `Skipped` as in 3.2, the resource group's row `Created | created role
assignment 'Reader' for 'oer-s112-group' at ...`, ARM `writes: 1 (PUT)`, `at the root scope: 0`.
**Failure looks like:** `at the root scope:` above 0, or the resource group's entry `Failed`
(`PrincipalNotFound` right after the group was created: run 3.3 again).

Result:

### 3.4. Twice more, with and without -Prune: only Skipped and Unchanged (G8)

- [ ] **3.4** Two more runs (`-Prune`, then without) report the two root entries `Skipped` and the resource group's `Unchanged`, with no write and no request at the root.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -RoleAssignments @(
    [ordered]@{ scope = '/'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = '/.'; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
    [ordered]@{ scope = $RgScope; role = 'Reader'; principal = $GroupName; principalType = 'Group' }
)
Invoke-S112Apply -Label '3.4 run 1 (-Prune)' -Json $Doc -Prune
Invoke-S112Apply -Label '3.4 run 2' -Json $Doc
Disconnect-OerLive
```

**Expect:** each run the two root rows `Skipped` and `Unchanged | role assignment already exists at ...`
for the resource group; ARM `writes: 0`, `at the root scope: 0`; no `Extra` and no `Removed` row.
**Failure looks like:** a write, a request at the root scope, or a `Removed` row.

Result:

## 4. An export of the test subscription carries no row at the root scope

### 4.1. Get-OERInventory at the subscription

- [ ] **4.1** The document holds no role assignment at `/`; any read at `/` is named in one warning and handed on the information stream.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$I = $null
Start-S112Count
try {
    $Out = @(Get-OERInventory -Include RoleAssignments -Subscription $Cfg.SubscriptionId -IncludeARM -InformationVariable I -ErrorAction SilentlyContinue -ErrorVariable E 3>&1)
    $Sent = Get-S112Sent
} finally { Stop-S112Count }
$Inv = @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
$Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
$Rows = @(@($Inv.roleAssignments) | Where-Object { $null -ne $_ })
$Notices = @(@($I) | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.RootScopeAssignment' } | ForEach-Object { $_.MessageData })
$Named = @($Notices | ForEach-Object { @($_.Assignments) })
Write-OerLiveStep "4.1 role assignments in the document: $($Rows.Count); at the root scope: $(@($Rows | Where-Object { [string]$_.scope -eq '/' }).Count)"
Write-OerLiveStep "4.1 root-scope notices on the information stream: $($Notices.Count); role assignments at the root scope they name: $($Named.Count)"
foreach ($N in $Named) { Write-OerLiveStep "4.1 at the root scope: role '$($N.Role)' for '$($N.Principal)' ($($N.PrincipalType))" }
Write-OerLiveStep "4.1 warnings: $($Warnings.Count); about the root scope: $(@($Warnings | Where-Object { $_.StartsWith('Get-OERInventory: left out') }).Count)"
foreach ($T in @($Warnings | Where-Object { $_.StartsWith('Get-OERInventory: left out') })) { Write-OerLiveStep "4.1 warning: $T" }
Write-OerLiveStep "4.1 errors: $(@($E).Count)$(if (@($E).Count) { ' (' + ((@($E) | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ', ') + ')' })"
Write-OerLiveStep "4.1 sent: $Sent"
Disconnect-OerLive
```

**Expect:** `at the root scope: 0` in the document. When the tenant holds a role assignment at `/`
that this read lists: one notice, the rows named with role and principal, and one warning starting
`Get-OERInventory: left out N role assignment(s) at the root scope '/'`. When it holds none: 0
notices and no such warning, and the finding half is class B (section B).
**Failure looks like:** a row at `/` in the document; a notice without its warning, or the reverse.

Result:

### 4.2. Export-OERInventory of the subscription

- [ ] **4.2** `inventory.json` and `roleAssignments.json` hold no row at `/`; the README has the section "Role assignments at the root scope (elevated access)", listing what 4.1 named or saying none; Export shows at most one root warning, its own.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Dir = Join-Path $Raw 'export'
$null = New-Item -ItemType Directory -Force -Path $Dir
Start-S112Count
try {
    $Out = @(Export-OERInventory -OutputPath $Dir -Include RoleAssignments -Scope $SubScope -ErrorAction SilentlyContinue -ErrorVariable E 3>&1)
    $Sent = Get-S112Sent
} finally { Stop-S112Count }
$Bundle = @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
$Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
$Inv = Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
$Ra = @(Get-Content -LiteralPath (Join-Path $Bundle.BundlePath 'roleAssignments.json') -Raw | ConvertFrom-Json)
$Readme = [System.IO.File]::ReadAllText((Join-Path $Bundle.BundlePath 'README.md'))
$Section = [regex]::Match($Readme, '(?ms)^## Role assignments at the root scope \(elevated access\)\s*$(.*?)(?=^## )').Groups[1].Value
Write-OerLiveStep "4.2 inventory.json role assignments: $(@($Inv.roleAssignments).Count), at the root scope: $(@(@($Inv.roleAssignments) | Where-Object { [string]$_.scope -eq '/' }).Count); roleAssignments.json rows: $($Ra.Count), at the root scope: $(@($Ra | Where-Object { [string]$_.scope -eq '/' }).Count)"
Write-OerLiveStep "4.2 README has the section: $($Readme.Contains('## Role assignments at the root scope (elevated access)'))"
foreach ($L in @($Section -split "`n" | Where-Object { $_ -match '^(- |None\.|This export read )' })) { Write-OerLiveStep "4.2 README: $($L.TrimEnd())" }
Write-OerLiveStep "4.2 warnings shown: $($Warnings.Count); Export's root-scope warning: $(@($Warnings | Where-Object { $_.StartsWith('Export-OERInventory: left out') }).Count); Get-OERInventory's root-scope warning: $(@($Warnings | Where-Object { $_.StartsWith('Get-OERInventory: left out') }).Count)"
foreach ($T in @($Warnings | Where-Object { $_.StartsWith('Export-OERInventory: left out') })) { Write-OerLiveStep "4.2 warning: $T" }
Write-OerLiveStep "4.2 errors: $(@($E).Count)$(if (@($E).Count) { ' (' + ((@($E) | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ', ') + ')' })"
Write-OerLiveStep "4.2 sent: $Sent"
Disconnect-OerLive
```

**Expect:** `at the root scope: 0` in both files; `README has the section: True`; the README lines
list exactly the rows 4.1 named (`This export read N role assignment(s) at the root scope:` and one
bullet each), or `None. No role assignment this export read is at the root scope ...`; `Export's
root-scope warning: 1` when 4.1 named rows and 0 otherwise; `Get-OERInventory's root-scope warning: 0`.
An `InventoryPartial` error for a scope whose eligibility could not be read is unrelated to this
branch and is reported, not failed.
**Failure looks like:** a row at `/` in either file; no section; a `Get-OERInventory: left out` warning
shown by the export.

Result:

## T. Teardown

### T.1. Remove every oer-s112- object

- [ ] **T.1** The teardown deletes the two reviews, the role assignment at the resource group, the policy, the package, the catalog, the group and the resource group; the sweep finds nothing; the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS112Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `Teardown A: deleted access review oer-s112-review` and `... oer-s112-review-pkg`;
`Teardown B: DELETE of a role assignment at oer-s112-rg for oer-s112-group: 200`; the library's
removal of the policy, the package, the catalog and the group; `Teardown D: deleted oer-s112-rg.`;
`Access reviews with the prefix after the teardown: 0`; every `Counts:` line `equal: True`; exit code 0.
**Failure looks like:** a `RESIDUE` line or exit code 3 -- record each residue row here.

Result:

### T.2. Read back

- [ ] **T.2** Nothing with the prefix is left, and the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS112Prereq.ps1') -ReadBack
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `access reviews with the prefix: 0`; `resource group oer-s112-rg exists: False`; every
`Counts:` line `equal: True`; `prefixed objects left: 0; unread collections: 0`; no residue row with
this step's prefix.
**Failure looks like:** anything left with the prefix.

Result:

## B. Proved offline only (class B)

- **A role assignment at the root scope in an export** (when the test tenant holds none): the unit
  tests in `tests/Unit/Public/Get-OERInventory.Tests.ps1` (Context "a role assignment at the root scope
  is left out (BL-126)": a row at `/` read through a management group and through a subscription is
  left out, warned about once and handed on the information stream) and
  `tests/Unit/Public/Export-OERInventory.Tests.ps1` (Describe "role assignments at the root scope,
  BL-126", including the end-to-end test through the real `Get-OERInventory`).
- **An entry at the root scope never reaches Azure Resource Manager**: `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`
  records every ARM path of the real engine and handler, with and without `-Prune` and under `-WhatIf`,
  and a runspace with no `try` proves the same through the public cmdlet.
- **A review of a group, another package or another policy is refused, and an unresolvable package is
  Failed with its own error**: `tests/Unit/Private/Get-OERAccessReviewTargetMismatch.Tests.ps1` and the
  BL-127 Describe of `tests/Unit/Private/Sync-OERStructureAccessReview.Tests.ps1`, plus the no-try
  runspace proof.
- **The texts**: `tests/QA/docsync.tests.ps1`, `tests/QA/about.tests.ps1`, `tests/QA/dochygiene.tests.ps1`
  and `tests/Unit/Private/Get-OERInventoryPromptTemplate.Tests.ps1`.
