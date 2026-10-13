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

function ConvertTo-S112Canonical {
    # The value with every dictionary's keys in ordinal order, recursively: Microsoft Graph's answer arrives
    # as a hashtable whose keys enumerate in no fixed order (measured: the same definition read twice gave
    # its settings in two orders), so two reads compare equal only in this form.
    param([AllowNull()][object]$Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $Keys = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [System.Array]::Sort($Keys, [System.StringComparer]::Ordinal)
        $Out = [ordered]@{}
        foreach ($K in $Keys) { $Out[$K] = ConvertTo-S112Canonical -Value $Value[$K] }
        return $Out
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return , @(foreach ($I in $Value) { ConvertTo-S112Canonical -Value $I })
    }
    $Value
}

function Compare-S112ReviewShape {
    # Prints, field by field, whether two recorded shapes are equal (settings and reviewers compared in
    # their canonical form), and returns $true only when every field is.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Before, [Parameter(Mandatory)][string]$Now)
    $B = $Before | ConvertFrom-Json -AsHashtable
    $N = $Now | ConvertFrom-Json -AsHashtable
    $All = $true
    foreach ($K in 'descriptionForAdmins', 'descriptionForReviewers', 'scopeQuery', 'reviewers', 'settings', 'lastModifiedDateTime') {
        $Equal = if ($K -in 'reviewers', 'settings') {
            (ConvertTo-Json -InputObject (ConvertTo-S112Canonical -Value ([string]$B[$K] | ConvertFrom-Json -AsHashtable)) -Depth 20 -Compress) -ceq
            (ConvertTo-Json -InputObject (ConvertTo-S112Canonical -Value ([string]$N[$K] | ConvertFrom-Json -AsHashtable)) -Depth 20 -Compress)
        } else { [string]$B[$K] -ceq [string]$N[$K] }
        Write-OerLiveStep "$Label $($K): equal $Equal"
        if (-not $Equal) { $All = $false }
    }
    $All
}
function Get-S112ReviewShape {
    # What a write would change on a definition, as one comparable string, and its readable summary.
    param([Parameter(Mandatory)][object]$Definition, [Parameter(Mandatory)][object]$Ids)
    $Shape = [ordered]@{
        descriptionForAdmins    = [string]$Definition['descriptionForAdmins']
        descriptionForReviewers = [string]$Definition['descriptionForReviewers']
        scopeQuery              = [string]$Definition['scope']['query']
        reviewers               = ConvertTo-Json -InputObject (ConvertTo-S112Canonical -Value @($Definition['reviewers'])) -Depth 20 -Compress
        settings                = ConvertTo-Json -InputObject (ConvertTo-S112Canonical -Value $Definition['settings']) -Depth 20 -Compress
        lastModifiedDateTime    = [string]$Definition['lastModifiedDateTime']
    }
    [PSCustomObject]@{
        Text            = ConvertTo-Json -InputObject $Shape -Depth 5 -Compress
        ReviewsTheGroup = ($Shape.scopeQuery -cmatch ('^(/(v1\.0|beta))?/groups/' + [regex]::Escape($Ids.GroupId) + '/transitiveMembers(/.*)?$'))
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
Write-OerLiveStep "The worktree's build carries A: root predicate $(& $Has 'function Test-OERAzureRootScope'); information tag $(& $Has "'Omnicit.EntraRBAC.RootScopeAssignment'"); README section $(& $Has '## Role assignments at the root scope (elevated access)'); URI spelling check $(& $Has 'scope.invalid')"
Write-OerLiveStep "The worktree's build carries B: target check $(& $Has 'function Get-OERAccessReviewTargetMismatch'); refusal id $(& $Has "'AccessReviewScopeMismatch'"); policy lookup $(& $Has 'function Resolve-OERAssignmentPolicyId')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; every mark `True` on the last two
lines.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last two lines -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree was on this branch at d6fb45f with 0 tracked changes, and its build (built from 9216e8b, the last commit under source/) carries every mark of A and B. The later commits of the branch change only this checklist.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s112] The module loads from a worktree that is not the main clone: True
[oer-s112] Main clone: branch main; HEAD 491e72e
[oer-s112] Worktree: branch fix/refuse-root-scope-and-foreign-review; HEAD d6fb45f docs: add the live checklist for the root scope and a review of another package; tracked changes: 0
[oer-s112] The worktree's build carries A: root predicate True; information tag True; README section True; URI spelling check True
[oer-s112] The worktree's build carries B: target check True; refusal id True; policy lookup True
RUNNER: check S.1 exit code 0; started 2026-10-13T20:05:51Z; took 3 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

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

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc (app-only, certificate); identity check passed; the module is the worktree's build (1.2.1).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] The module is the worktree's build: True; version 1.2.1
RUNNER: check 0.1 exit code 0; started 2026-10-13T20:06:03Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.2. The permissions this file needs

- [x] **0.2** `oer-live-cc` holds both Microsoft Graph permissions; otherwise the run stops here.

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

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. oer-live-cc holds AccessReview.ReadWrite.All and EntitlementManagement.ReadWrite.All; no permission was added or removed.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
RUNNER: check 0.2 exit code 0; started 2026-10-13T20:06:11Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.3. The prerequisite objects

- [x] **0.3** The plan writes nothing; the first run creates the six objects; a second run writes nothing.

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

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, after two fixes to the prerequisite script, both refusals before any write. Run 1: the plan wrote nothing; the first -Unattended run wrote the baseline and created the six objects (written to the tenant: True); the second refused, since the script expected the group review's scope query as it wrote it, while Microsoft Graph reads it back as /v1.0/groups/ + id + /transitiveMembers/microsoft.graph.user (measured in 1.1). Runs 2 and 3: the same refusal until the script and the checklist accepted the version prefix and the type cast; then a refusal for 1 role assignment exactly at oer-s112-rg, which the read-only diagnosis D.1 shows does not exist (every assignment listed there is inherited from the subscription or a management group): the script's reader returned a wrapped empty list that its caller wrapped again, so @(@()).Count read 1. Run 4, with the reader returning unwrapped rows: all three runs find the six objects and write nothing (written to the tenant: False), exit code 0. No object outside the prefix was touched.

=== Run 1 (creation; the second -Unattended run refused on the scope query) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s112] === Initialize-OerS112Prereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s112\prereq-20261013-200627Z.log".
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s112-' is left.
[oer-s112] Found: oer-s112-group False; oer-s112-catalog False; oer-s112-ap False; oer-s112-policy False; oer-s112-rg False; oer-s112-review False; prefixed access reviews: 0.
[oer-s112] No baseline yet: it is written now, before the first write to the tenant (groups 97, catalogs 5, access packages 6, access review definitions 6; oer-s112-rg exists: False).
What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s112\baseline-s112.json".
What if: Performing the operation "Create a security group with no member (Graph v1.0 POST groups: not role-assignable, not mail-enabled, assigned membership)" on target "oer-s112-group".
What if: Performing the operation "Create a catalog (Graph v1.0 POST entitlementManagement/catalogs: published, not visible to external users)" on target "oer-s112-catalog".
What if: Performing the operation "Create a hidden access package (Graph v1.0 POST entitlementManagement/accessPackages: isHidden, no resource role)" on target "oer-s112-ap".
What if: Performing the operation "Create an assignment policy through which only an administrator assigns (Graph v1.0 POST entitlementManagement/assignmentPolicies: allowedTargetScope notSpecified, no requestor, no approval, no expiration)" on target "oer-s112-policy".
What if: Performing the operation "Create the resource group in the test subscription (Azure Resource Manager PUT, location 'swedencentral', tag purpose 'Omnicit.EntraRBAC live verification (oer-s112)')" on target "oer-s112-rg".
What if: Performing the operation "Create an access review of the members of oer-s112-group (Graph v1.0 POST accessReviews/definitions: self review, quarterly from 14 days after the run, 1-day instances)" on target "oer-s112-review".
[oer-s112] Summary: oer-s112-group absent; oer-s112-catalog absent; oer-s112-ap absent; oer-s112-policy absent; oer-s112-rg absent; oer-s112-review absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s112] WhatIf: nothing was created, removed or written.
[oer-s112] Done.
[oer-s112] exit code: 0
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-200634Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s112-' is left.
[oer-s112] Found: oer-s112-group False; oer-s112-catalog False; oer-s112-ap False; oer-s112-policy False; oer-s112-rg False; oer-s112-review False; prefixed access reviews: 0.
[oer-s112] No baseline yet: it is written now, before the first write to the tenant (groups 97, catalogs 5, access packages 6, access review definitions 6; oer-s112-rg exists: False).
[oer-s112] Wrote the baseline raw\s112\baseline-s112.json and read it back.
[oer-s112] Created group oer-s112-group: 201.
[oer-s112] Recorded the id of oer-s112-group under raw\s112 (not printed).
[oer-s112] oer-s112-group resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s112] oer-s112-group resolves by its display name: converged after 2 read(s), 2.2 s.
[oer-s112] Created catalog oer-s112-catalog: 201.
[oer-s112] oer-s112-catalog is readable by its id: converged after 1 read(s), 0.1 s.
[oer-s112] Created access package oer-s112-ap: 201 after 1 attempt(s).
[oer-s112] oer-s112-ap is readable by its id: converged after 1 read(s), 0.1 s.
[oer-s112] Created policy oer-s112-policy: 201 after 1 attempt(s).
[oer-s112] oer-s112-policy is listed on oer-s112-ap: converged after 1 read(s), 0.1 s.
[oer-s112] Created resource group oer-s112-rg.
[oer-s112] Recorded the id of oer-s112-review under raw\s112 (not printed).
[oer-s112] Created access review oer-s112-review: 201 after 1 attempt(s).
[oer-s112] oer-s112-review is listed: converged after 1 read(s), 0.5 s.
[oer-s112] Summary: oer-s112-group present; oer-s112-catalog present; oer-s112-ap present; oer-s112-policy present; oer-s112-rg present; oer-s112-review present; written to the tenant: True.
[oer-s112] Done.
[oer-s112] exit code: 0
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-200647Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Refusing to run: oer-s112-review exists but does not review the members of oer-s112-group. Nothing was written.
[oer-s112] exit code: 1
RUNNER: check 0.3 exit code 0; started 2026-10-13T20:06:24Z; took 29 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Run 2 (version prefix accepted; refused on the type cast) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s112] === Initialize-OerS112Prereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s112\prereq-20261013-200815Z.log".
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Refusing to run: oer-s112-review exists but does not review the members of oer-s112-group. Nothing was written.
[oer-s112] exit code: 1
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-200822Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Refusing to run: oer-s112-review exists but does not review the members of oer-s112-group. Nothing was written.
[oer-s112] exit code: 1
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-200831Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Refusing to run: oer-s112-review exists but does not review the members of oer-s112-group. Nothing was written.
[oer-s112] exit code: 1
RUNNER: check 0.3 exit code 0; started 2026-10-13T20:08:13Z; took 24 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Run 3 (type cast accepted; refused on the wrapped empty list) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s112] === Initialize-OerS112Prereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s112\prereq-20261013-200919Z.log".
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Found: oer-s112-group True; oer-s112-catalog True; oer-s112-ap True; oer-s112-policy True; oer-s112-rg True; oer-s112-review True; prefixed access reviews: 1.
[oer-s112] Refusing to run: 1 role assignment(s) exist exactly at oer-s112-rg (an earlier run's leftovers, or not this step's); run -Teardown first. Nothing was written.
[oer-s112] exit code: 1
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-200926Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Found: oer-s112-group True; oer-s112-catalog True; oer-s112-ap True; oer-s112-policy True; oer-s112-rg True; oer-s112-review True; prefixed access reviews: 1.
[oer-s112] Refusing to run: 1 role assignment(s) exist exactly at oer-s112-rg (an earlier run's leftovers, or not this step's); run -Teardown first. Nothing was written.
[oer-s112] exit code: 1
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-200933Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Found: oer-s112-group True; oer-s112-catalog True; oer-s112-ap True; oer-s112-policy True; oer-s112-rg True; oer-s112-review True; prefixed access reviews: 1.
[oer-s112] Refusing to run: 1 role assignment(s) exist exactly at oer-s112-rg (an earlier run's leftovers, or not this step's); run -Teardown first. Nothing was written.
[oer-s112] exit code: 1
RUNNER: check 0.3 exit code 0; started 2026-10-13T20:09:17Z; took 22 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Diagnosis D.1 (read only): the role assignments listed at oer-s112-rg ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK D.1 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 2; role: Reader; principalType: Group; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 06/22/2026 20:55:27; description: TEst
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 2; role: Storage Blob Data Contributor; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 08/12/2026 07:27:35; description: probe
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 2; role: Owner; principalType: ServicePrincipal; principal is oer-live-cc: True; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 09/28/2026 07:56:52; description: Omnicit.EntraRBAC live verification: Claude Code identity (Initialize-OerCcIdentity.ps1)
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 2; role: Owner; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 12/13/2019 13:09:25; description: 
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 2; role: Owner; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 12/13/2019 13:09:25; description: 
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 2; role: Reader; principalType: ServicePrincipal; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 10/15/2019 08:25:03; description: 
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 4; role: Owner; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 05/29/2020 06:22:37; description: 
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 4; role: Owner; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 05/29/2020 06:24:05; description: 
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 4; role: User Access Administrator; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 05/29/2020 06:21:43; description: pr 7 live test
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 4; role: User Access Administrator; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 05/29/2020 06:21:43; description: 
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 4; role: User Access Administrator; principalType: User; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 05/29/2020 06:21:42; description: 
[oer-s112] D.1 assignment: exactly at the resource group: False; scope depth: 4; role: Log Analytics Contributor; principalType: ServicePrincipal; principal is oer-live-cc: False; principal is oer-s112-group: False; created by oer-live-cc: False; createdOn: 05/15/2026 18:47:59; description:
RUNNER: check D.1 exit code 0; started 2026-10-13T20:10:06Z; took 10 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Run 4 (pass) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s112] === Initialize-OerS112Prereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s112\prereq-20261013-201044Z.log".
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Found: oer-s112-group True; oer-s112-catalog True; oer-s112-ap True; oer-s112-policy True; oer-s112-rg True; oer-s112-review True; prefixed access reviews: 1.
[oer-s112] The baseline exists (groups 97, catalogs 5, access packages 6, access review definitions 6 when it was written).
[oer-s112] Group oer-s112-group exists.
[oer-s112] Catalog oer-s112-catalog exists.
[oer-s112] Access package oer-s112-ap exists.
[oer-s112] Policy oer-s112-policy exists.
[oer-s112] Resource group oer-s112-rg exists.
[oer-s112] Access review oer-s112-review (a group review of oer-s112-group) exists.
[oer-s112] Summary: oer-s112-group present; oer-s112-catalog present; oer-s112-ap present; oer-s112-policy present; oer-s112-rg present; oer-s112-review present; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s112] WhatIf: nothing was created, removed or written.
[oer-s112] Done.
[oer-s112] exit code: 0
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-201050Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Found: oer-s112-group True; oer-s112-catalog True; oer-s112-ap True; oer-s112-policy True; oer-s112-rg True; oer-s112-review True; prefixed access reviews: 1.
[oer-s112] The baseline exists (groups 97, catalogs 5, access packages 6, access review definitions 6 when it was written).
[oer-s112] Group oer-s112-group exists.
[oer-s112] Catalog oer-s112-catalog exists.
[oer-s112] Access package oer-s112-ap exists.
[oer-s112] Policy oer-s112-policy exists.
[oer-s112] Resource group oer-s112-rg exists.
[oer-s112] Access review oer-s112-review (a group review of oer-s112-group) exists.
[oer-s112] Summary: oer-s112-group present; oer-s112-catalog present; oer-s112-ap present; oer-s112-policy present; oer-s112-rg present; oer-s112-review present; written to the tenant: False.
[oer-s112] Done.
[oer-s112] exit code: 0
[oer-s112] === Initialize-OerS112Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\prereq-20261013-201057Z.log; OerLive 1.0.3.
[oer-s112] Mode: CREATE or complete. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] Found: oer-s112-group True; oer-s112-catalog True; oer-s112-ap True; oer-s112-policy True; oer-s112-rg True; oer-s112-review True; prefixed access reviews: 1.
[oer-s112] The baseline exists (groups 97, catalogs 5, access packages 6, access review definitions 6 when it was written).
[oer-s112] Group oer-s112-group exists.
[oer-s112] Catalog oer-s112-catalog exists.
[oer-s112] Access package oer-s112-ap exists.
[oer-s112] Policy oer-s112-policy exists.
[oer-s112] Resource group oer-s112-rg exists.
[oer-s112] Access review oer-s112-review (a group review of oer-s112-group) exists.
[oer-s112] Summary: oer-s112-group present; oer-s112-catalog present; oer-s112-ap present; oer-s112-policy present; oer-s112-rg present; oer-s112-review present; written to the tenant: False.
[oer-s112] Done.
[oer-s112] exit code: 0
RUNNER: check 0.3 exit code 0; started 2026-10-13T20:10:41Z; took 21 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. A group review that carries a package review's name is refused

### 1.1. The group review before

- [x] **1.1** `oer-s112-review` exists and reviews the members of `oer-s112-group`; its state is recorded.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$D = Get-S112Definition -Name $Review
$S = Get-S112ReviewShape -Definition $D -Ids $Ids
[System.IO.File]::WriteAllText((Join-Path $Raw 'review-before.json'), $S.Text, [System.Text.UTF8Encoding]::new($false))
Write-OerLiveStep "1.1 $Review exists: $($null -ne $D); reviews the members of $($GroupName): $($S.ReviewsTheGroup); reviews $($Package): $($S.ReviewsPackage)"
Write-OerLiveStep "1.1 scope query as Microsoft Graph reads it back: $([string]$D['scope']['query'])"
Write-OerLiveStep "1.1 description: $($S.Description)"
Write-OerLiveStep "1.1 state recorded under raw\s112 (lastModifiedDateTime present: $([bool]$S.LastModified))"
Disconnect-OerLive
```

**Expect:** `exists: True; reviews the members of oer-s112-group: True; reviews oer-s112-ap: False`.
**Failure looks like:** `False` on the first two -- run 0.3 again.

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. oer-s112-review exists, reviews the members of oer-s112-group and not oer-s112-ap; Microsoft Graph reads its scope query back as /v1.0/groups/ + the group's id + /transitiveMembers/microsoft.graph.user; its state was recorded under raw\s112 before 1.2. (A first read-only run, tagged diag, printed 'reviews the members of oer-s112-group: False' before the checklist accepted that form; it wrote nothing to the tenant, and this run's record replaced its own.)

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 1.1 oer-s112-review exists: True; reviews the members of oer-s112-group: True; reviews oer-s112-ap: False
[oer-s112] 1.1 scope query as Microsoft Graph reads it back: /v1.0/groups/00000000-0000-0000-0000-000000000001/transitiveMembers/microsoft.graph.user
[oer-s112] 1.1 description: Omnicit.EntraRBAC live verification (oer-s112-): a group review that carries the display name of a package review in the checklist's document.
[oer-s112] 1.1 state recorded under raw\s112 (lastModifiedDateTime present: True)
RUNNER: check 1.1 exit code 0; started 2026-10-13T20:11:11Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. The plan refuses it

- [x] **1.2** A document declaring a PACKAGE review named `oer-s112-review` plans `Failed` with `AccessReviewScopeMismatch`, and sends no write.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $Review -AccessPackage $Package -AssignmentPolicy $Policy -Description 'Written by the s112 document: it must never reach the group review.')
Invoke-S112Apply -Label '1.2 plan' -Json $Doc -Plan
Disconnect-OerLive
```

**Expect:** one row `accessReviews | oer-s112-review | Failed | Access review 'oer-s112-review' in the
tenant does not review an access package (its scope is '` + the group's member query as 1.1 printed
it + `'), so it is not the review this entry declares for access package 'oer-s112-ap'
and assignment policy 'oer-s112-policy'. Nothing was written. Access review display names are not
unique: give the entry or the review in the tenant another display name.`; `1.2 plan error:
AccessReviewScopeMismatch,Invoke-OERStructure:` with the same message; `errors of
Invoke-OERStructure: 1`; `Microsoft Graph requests: N, writes: 0`; no `What if:` line.
**Failure looks like:** `Skipped | would update access review` -- the branch's check did not run; or
any Graph write.

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan reports one Failed row with the refusal text, the error AccessReviewScopeMismatch,Invoke-OERStructure, no What if line and no warning; one Microsoft Graph request (the definition listing) and no write -- the group review is refused before any package, policy or reviewer lookup.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 1.2 plan rows: 1
[oer-s112] 1.2 plan row: accessReviews | oer-s112-review | Failed | Access review 'oer-s112-review' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000001/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s112-ap' and assignment policy 'oer-s112-policy'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s112] 1.2 plan warnings: 0
[oer-s112] 1.2 plan error: AccessReviewScopeMismatch,Invoke-OERStructure: Access review 'oer-s112-review' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000001/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s112-ap' and assignment policy 'oer-s112-policy'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s112] 1.2 plan errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 1.2 plan sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
RUNNER: check 1.2 exit code 0; started 2026-10-13T20:11:18Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.3. The run refuses it and writes nothing

- [x] **1.3** The same document, applied, is `Failed` with `AccessReviewScopeMismatch`, and sends no write.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Doc = New-S112Document -Reviews @(New-S112PackageReview -Name $Review -AccessPackage $Package -AssignmentPolicy $Policy -Description 'Written by the s112 document: it must never reach the group review.')
Invoke-S112Apply -Label '1.3 run' -Json $Doc
Disconnect-OerLive
```

**Expect:** the same row and error as 1.2; `writes: 0` for Microsoft Graph.
**Failure looks like:** `Updated`, or a `PUT` among the writes -- the defect this branch fixes (BL-127).

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The run gives the same Failed row and error as the plan, one Microsoft Graph request and no write.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 1.3 run rows: 1
[oer-s112] 1.3 run row: accessReviews | oer-s112-review | Failed | Access review 'oer-s112-review' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000001/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s112-ap' and assignment policy 'oer-s112-policy'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s112] 1.3 run warnings: 0
[oer-s112] 1.3 run error: AccessReviewScopeMismatch,Invoke-OERStructure: Access review 'oer-s112-review' in the tenant does not review an access package (its scope is '/v1.0/groups/00000000-0000-0000-0000-000000000001/transitiveMembers/microsoft.graph.user'), so it is not the review this entry declares for access package 'oer-s112-ap' and assignment policy 'oer-s112-policy'. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s112] 1.3 run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 1.3 run sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
RUNNER: check 1.3 exit code 0; started 2026-10-13T20:11:25Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.4. The group review is unchanged

- [x] **1.4** Read back, `oer-s112-review` is exactly as 1.1 recorded it.

```powershell
Connect-OerLive -Arm
Start-S112NoPrompt
$Ids = Get-S112Ids
$S = Get-S112ReviewShape -Definition (Get-S112Definition -Name $Review) -Ids $Ids
$Before = [System.IO.File]::ReadAllText((Join-Path $Raw 'review-before.json'))
Write-OerLiveStep "1.4 reviews the members of $($GroupName): $($S.ReviewsTheGroup); description: $($S.Description)"
$Same = Compare-S112ReviewShape -Label '1.4' -Before $Before -Now $S.Text
Write-OerLiveStep "1.4 descriptions, scope, reviewers, settings and lastModifiedDateTime equal to 1.1: $Same"
Disconnect-OerLive
```

**Expect:** `reviews the members of oer-s112-group: True`, the description of 1.1, every field `equal True` (settings and reviewers compared with their keys in one order) and `equal to 1.1: True`.
**Failure looks like:** `False` -- a write reached the group review.

Result: 2026-10-13 20:16 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, after a fix to the checklist's comparison. The first run reported 'equal to 1.1: False' with no write in 1.2 and 1.3; the read-only diagnosis D.2 showed every field equal, lastModifiedDateTime unchanged, and the settings holding the same values with their keys in another order: Microsoft Graph's answer is a hashtable whose keys enumerate in no fixed order. The checklist now compares field by field, settings and reviewers with their keys in one order, against 1.1's own record (not recorded again): every field equal, the group review unchanged.

=== Run 1 (whole-string comparison) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.4 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 1.4 reviews the members of oer-s112-group: True; description: Omnicit.EntraRBAC live verification (oer-s112-): a group review that carries the display name of a package review in the checklist's document.
[oer-s112] 1.4 descriptions, scope, reviewers, settings and lastModifiedDateTime equal to 1.1: False
RUNNER: check 1.4 exit code 0; started 2026-10-13T20:11:32Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Diagnosis D.2 (read only): which field differs ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK D.2 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] D.2 descriptionForAdmins: equal True
[oer-s112] D.2 descriptionForReviewers: equal True
[oer-s112] D.2 scopeQuery: equal True
[oer-s112] D.2 reviewers: equal True
[oer-s112] D.2 settings: equal False
[oer-s112] D.2 lastModifiedDateTime: equal True
[oer-s112] D.2 lastModifiedDateTime at 1.1: 10/13/2026 20:06:46; now: 10/13/2026 20:06:46
[oer-s112] D.2 settings at 1.1: {"decisionHistoriesForReviewersEnabled":false,"recurrence":{"pattern":{"dayOfMonth":0,"index":"first","daysOfWeek":[],"interval":3,"firstDayOfWeek":"sunday","month":0,"type":"absoluteMonthly"},"range":{"numberOfOccurrences":0,"recurrenceTimeZone":null,"startDate":"2026-10-27","type":"noEnd","endDate":"9999-12-31"}},"justificationRequiredOnApproval":false,"mailNotificationsEnabled":false,"recommendationsEnabled":false,"instanceDurationInDays":1,"reminderNotificationsEnabled":false,"autoApplyDecisionsEnabled":false,"defaultDecisionEnabled":false,"recommendationInsightSettings":[],"applyActions":[{"@odata.type":"#microsoft.graph.removeAccessApplyAction"}],"recommendationLookBackDuration":null,"defaultDecision":"None"}
[oer-s112] D.2 settings now: {"defaultDecisionEnabled":false,"applyActions":[{"@odata.type":"#microsoft.graph.removeAccessApplyAction"}],"justificationRequiredOnApproval":false,"recommendationInsightSettings":[],"defaultDecision":"None","autoApplyDecisionsEnabled":false,"recurrence":{"range":{"type":"noEnd","endDate":"9999-12-31","recurrenceTimeZone":null,"startDate":"2026-10-27","numberOfOccurrences":0},"pattern":{"daysOfWeek":[],"type":"absoluteMonthly","index":"first","month":0,"interval":3,"dayOfMonth":0,"firstDayOfWeek":"sunday"}},"recommendationLookBackDuration":null,"mailNotificationsEnabled":false,"recommendationsEnabled":false,"instanceDurationInDays":1,"reminderNotificationsEnabled":false,"decisionHistoriesForReviewersEnabled":false}
RUNNER: check D.2 exit code 0; started 2026-10-13T20:11:56Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Run 2 (field by field, keys in one order) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.4 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 1.4 reviews the members of oer-s112-group: True; description: Omnicit.EntraRBAC live verification (oer-s112-): a group review that carries the display name of a package review in the checklist's document.
[oer-s112] 1.4 descriptionForAdmins: equal True
[oer-s112] 1.4 descriptionForReviewers: equal True
[oer-s112] 1.4 scopeQuery: equal True
[oer-s112] 1.4 reviewers: equal True
[oer-s112] 1.4 settings: equal True
[oer-s112] 1.4 lastModifiedDateTime: equal True
[oer-s112] 1.4 descriptions, scope, reviewers, settings and lastModifiedDateTime equal to 1.1: True
RUNNER: check 1.4 exit code 0; started 2026-10-13T20:12:59Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. A package review with the right package is updated as before

### 2.1. The package review is created through the document

- [x] **2.1** A document declaring `oer-s112-review-pkg` for `oer-s112-ap` and `oer-s112-policy` creates it: `Created`, one POST.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Created, with one Microsoft Graph POST; the new review reviews oer-s112-ap and oer-s112-policy; description version 1.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 2.1 run rows: 1
[oer-s112] 2.1 run row: accessReviews | oer-s112-review-pkg | Created | created access review 'oer-s112-review-pkg' (recurrence: Quarterly)
[oer-s112] 2.1 run warnings: 0
[oer-s112] 2.1 run errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 2.1 run sent: token requests: 0; Microsoft Graph requests: 5, writes: 1 (POST); Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
[oer-s112] oer-s112-review-pkg is listed: converged after 1 read(s), 0.5 s.
[oer-s112] 2.1 oer-s112-review-pkg reviews oer-s112-ap and oer-s112-policy: True; description: Omnicit.EntraRBAC live verification (oer-s112-): version 1.
RUNNER: check 2.1 exit code 0; started 2026-10-13T20:13:14Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.2. A change of description, by name: planned, then Updated

- [x] **2.2** With the package and policy given by NAME, a changed description plans an update (no write) and the run updates it (one PUT).

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With the package and policy given by name, the plan reports Skipped 'would update ... (descriptionForAdmins=... version 2.)' with no write, and the run Updated with one PUT; read back, the description is version 2. Updated as before for the review of the declared package and policy.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Update access review definition" on target "oer-s112-review-pkg".
[oer-s112] 2.2 plan rows: 1
[oer-s112] 2.2 plan row: accessReviews | oer-s112-review-pkg | Skipped | would update access review 'oer-s112-review-pkg' (descriptionForAdmins=Omnicit.EntraRBAC live verification (oer-s112-): version 2.)
[oer-s112] 2.2 plan warnings: 0
[oer-s112] 2.2 plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 2.2 plan sent: token requests: 0; Microsoft Graph requests: 3, writes: 0; Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
[oer-s112] 2.2 run rows: 1
[oer-s112] 2.2 run row: accessReviews | oer-s112-review-pkg | Updated | updated access review 'oer-s112-review-pkg' (descriptionForAdmins=Omnicit.EntraRBAC live verification (oer-s112-): version 2.)
[oer-s112] 2.2 run warnings: 0
[oer-s112] 2.2 run errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 2.2 run sent: token requests: 0; Microsoft Graph requests: 6, writes: 1 (PUT); Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
[oer-s112] oer-s112-review-pkg carries version 2: converged after 1 read(s), 0.8 s.
[oer-s112] 2.2 after the run: description: Omnicit.EntraRBAC live verification (oer-s112-): version 2.
RUNNER: check 2.2 exit code 0; started 2026-10-13T20:13:23Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.3. The same document twice more: only Unchanged (G8)

- [x] **2.3** Two more runs of 2.2's document report `Unchanged` and write nothing.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). Two more runs: Unchanged, no write each.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.3 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 2.3 run 1 rows: 1
[oer-s112] 2.3 run 1 row: accessReviews | oer-s112-review-pkg | Unchanged | access review 'oer-s112-review-pkg' already matches
[oer-s112] 2.3 run 1 warnings: 0
[oer-s112] 2.3 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 2.3 run 1 sent: token requests: 0; Microsoft Graph requests: 3, writes: 0; Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
[oer-s112] 2.3 run 2 rows: 1
[oer-s112] 2.3 run 2 row: accessReviews | oer-s112-review-pkg | Unchanged | access review 'oer-s112-review-pkg' already matches
[oer-s112] 2.3 run 2 warnings: 0
[oer-s112] 2.3 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 2.3 run 2 sent: token requests: 0; Microsoft Graph requests: 3, writes: 0; Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
RUNNER: check 2.3 exit code 0; started 2026-10-13T20:13:33Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.4. The package and the policy by their ids: Unchanged

- [x] **2.4** The same entry with `accessPackage` and `assignmentPolicy` given as their GUIDs is `Unchanged`, with no write.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With the package and policy given as their GUIDs: Unchanged, no write, and one Microsoft Graph request (the listing) -- an id is compared as written, with no lookup.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.4 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 2.4 run rows: 1
[oer-s112] 2.4 run row: accessReviews | oer-s112-review-pkg | Unchanged | access review 'oer-s112-review-pkg' already matches
[oer-s112] 2.4 run warnings: 0
[oer-s112] 2.4 run errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 2.4 run sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
RUNNER: check 2.4 exit code 0; started 2026-10-13T20:13:41Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.5. Another package by GUID: refused, nothing written

- [x] **2.5** The same entry naming a package id that is not the review's (the register's non-existent `...099`) is `Failed` with `AccessReviewScopeMismatch`, and the description stays.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Naming the register's non-existent package id (...099): Failed with AccessReviewScopeMismatch naming both package ids, one Microsoft Graph request (no lookup of the id) and no write; the description is still version 2.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.5 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 2.5 run rows: 1
[oer-s112] 2.5 run row: accessReviews | oer-s112-review-pkg | Failed | Access review 'oer-s112-review-pkg' in the tenant reviews access package '00000000-0000-0000-0000-000000000002', not the access package '00000000-0000-0000-0000-000000000099' this entry declares, so it is not the review this entry declares. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s112] 2.5 run warnings: 0
[oer-s112] 2.5 run error: AccessReviewScopeMismatch,Invoke-OERStructure: Access review 'oer-s112-review-pkg' in the tenant reviews access package '00000000-0000-0000-0000-000000000002', not the access package '00000000-0000-0000-0000-000000000099' this entry declares, so it is not the review this entry declares. Nothing was written. Access review display names are not unique: give the entry or the review in the tenant another display name.
[oer-s112] 2.5 run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 2.5 run sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0, at the root scope: 0
[oer-s112] 2.5 after the run: description: Omnicit.EntraRBAC live verification (oer-s112-): version 2.
RUNNER: check 2.5 exit code 0; started 2026-10-13T20:13:48Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. A role assignment at the root scope is never read, written or pruned

### 3.1. The validator flags it

- [x] **3.1** `Test-OERStructure` reports the entries at `/` and `/.` as Warnings at `roleAssignments[0].scope` and `roleAssignments[1].scope`; the document stays valid.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. valid: True with two Warnings, one at roleAssignments[0].scope for / and one at roleAssignments[1].scope for /., with the text the checklist expects; no Error.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 3.1 valid: True; findings: 2
[oer-s112] 3.1 finding: Warning | roleAssignments[0].scope | 'scope' at roleAssignments[0] is the root scope '/', which grants access over every management group and subscription in the tenant (elevated access). Invoke-OERStructure never creates or removes a role assignment there: the entry is reported Skipped and the root scope is never pruned. Remove the entry and manage elevated access outside the document.
[oer-s112] 3.1 finding: Warning | roleAssignments[1].scope | 'scope' at roleAssignments[1] is the root scope '/', which grants access over every management group and subscription in the tenant (elevated access). Invoke-OERStructure never creates or removes a role assignment there: the entry is reported Skipped and the root scope is never pruned. Remove the entry and manage elevated access outside the document.
RUNNER: check 3.1 exit code 0; started 2026-10-13T20:14:03Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. The plan with -Prune: Skipped, and no request at the root scope

- [x] **3.2** `Invoke-OERStructure -Prune -WhatIf` reports the two root entries (`/` and `/.`) `Skipped` with their reason and sends no Azure Resource Manager request at the root, while it plans the resource group's assignment.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. -Prune -WhatIf: both root entries (/ and /.) Skipped with the reason and one warning each; the resource group's entry 'would create' (the one What if line); 3 Azure Resource Manager requests, all under the resource group, no write and 0 at the root scope (each path read after the URI normalisation).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create role assignment 'Reader' for 'oer-s112-group'" on target "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg".
[oer-s112] 3.2 plan rows: 3
[oer-s112] 3.2 plan row: roleAssignments | Reader -> oer-s112-group @ / | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.2 plan row: roleAssignments | Reader -> oer-s112-group @ /. | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.2 plan row: roleAssignments | Reader -> oer-s112-group @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg | Skipped | would create role assignment 'Reader' for 'oer-s112-group' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg'
[oer-s112] 3.2 plan warnings: 2
[oer-s112] 3.2 plan warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.2 plan warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.2 plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 3.2 plan sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 3, writes: 0, at the root scope: 0
RUNNER: check 3.2 exit code 0; started 2026-10-13T20:14:09Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.3. The run with -Prune: Skipped at the root, Created at the resource group

- [x] **3.3** The same document, applied with `-Prune`, skips the two root entries and creates the resource group's assignment, with no request at the root.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. -Prune: both root entries Skipped; the resource group's assignment Created with one PUT; 0 requests at the root scope; no Removed row.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.3 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 3.3 run rows: 3
[oer-s112] 3.3 run row: roleAssignments | Reader -> oer-s112-group @ / | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.3 run row: roleAssignments | Reader -> oer-s112-group @ /. | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.3 run row: roleAssignments | Reader -> oer-s112-group @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg | Created | created role assignment 'Reader' for 'oer-s112-group' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg'
[oer-s112] 3.3 run warnings: 2
[oer-s112] 3.3 run warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.3 run warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.3 run errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 3.3 run sent: token requests: 0; Microsoft Graph requests: 3, writes: 0; Azure Resource Manager requests: 5, writes: 1 (PUT), at the root scope: 0
RUNNER: check 3.3 exit code 0; started 2026-10-13T20:14:17Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.4. Twice more, with and without -Prune: only Skipped and Unchanged (G8)

- [x] **3.4** Two more runs (`-Prune`, then without) report the two root entries `Skipped` and the resource group's `Unchanged`, with no write and no request at the root.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). With -Prune and without: both root entries Skipped, the resource group's Unchanged, no write, 0 requests at the root scope, no Extra and no Removed row.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.4 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 3.4 run 1 (-Prune) rows: 3
[oer-s112] 3.4 run 1 (-Prune) row: roleAssignments | Reader -> oer-s112-group @ / | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.4 run 1 (-Prune) row: roleAssignments | Reader -> oer-s112-group @ /. | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.4 run 1 (-Prune) row: roleAssignments | Reader -> oer-s112-group @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg'
[oer-s112] 3.4 run 1 (-Prune) warnings: 2
[oer-s112] 3.4 run 1 (-Prune) warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.4 run 1 (-Prune) warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.4 run 1 (-Prune) errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 3.4 run 1 (-Prune) sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 3, writes: 0, at the root scope: 0
[oer-s112] 3.4 run 2 rows: 3
[oer-s112] 3.4 run 2 row: roleAssignments | Reader -> oer-s112-group @ / | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.4 run 2 row: roleAssignments | Reader -> oer-s112-group @ /. | Skipped | the root scope '/' grants access over every management group and subscription in the tenant (elevated access), and the apply engine never creates or removes a role assignment there, and never prunes it. Nothing was read or written for this entry
[oer-s112] 3.4 run 2 row: roleAssignments | Reader -> oer-s112-group @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg | Unchanged | role assignment already exists at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s112-rg'
[oer-s112] 3.4 run 2 warnings: 2
[oer-s112] 3.4 run 2 warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.4 run 2 warning: Sync-OERStructureRoleAssignment: 'Reader' for 'oer-s112-group' names the root scope '/' (elevated access); the apply engine never creates or removes a role assignment there. Nothing was read or written for this entry.
[oer-s112] 3.4 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s112] 3.4 run 2 sent: token requests: 0; Microsoft Graph requests: 2, writes: 0; Azure Resource Manager requests: 3, writes: 0, at the root scope: 0
RUNNER: check 3.4 exit code 0; started 2026-10-13T20:14:26Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 4. An export of the test subscription carries no row at the root scope

### 4.1. Get-OERInventory at the subscription

- [x] **4.1** The document holds no role assignment at `/`; any read at `/` is named in one warning and handed on the information stream.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS for what the test tenant holds. Get-OERInventory at the test subscription: 14 role assignments, none at the root scope; no root-scope notice and no root-scope warning, since the read lists no assignment at / (D.1 shows the same: every assignment above the resource group sits at the subscription or a management group). The finding half -- a row at / named in a warning and handed on the information stream -- is therefore class B (section B). The two Microsoft Graph POSTs are the directoryObjects/getByIds name lookups (Resolve-OERPrincipalName), reads sent as POST; nothing was written.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.1 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 4.1 role assignments in the document: 14; at the root scope: 0
[oer-s112] 4.1 root-scope notices on the information stream: 0; role assignments at the root scope they name: 0
[oer-s112] 4.1 warnings: 0; about the root scope: 0
[oer-s112] 4.1 errors: 0
[oer-s112] 4.1 sent: token requests: 0; Microsoft Graph requests: 2, writes: 2 (POST, POST); Azure Resource Manager requests: 7, writes: 0, at the root scope: 0
RUNNER: check 4.1 exit code 0; started 2026-10-13T20:14:43Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 4.2. Export-OERInventory of the subscription

- [x] **4.2** `inventory.json` and `roleAssignments.json` hold no row at `/`; the README has the section "Role assignments at the root scope (elevated access)", listing what 4.1 named or saying none; Export shows at most one root warning, its own.

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

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS for what the test tenant holds. inventory.json and roleAssignments.json each hold 14 rows, none at the root scope; the README has the section 'Role assignments at the root scope (elevated access)', which says None; no warning was shown, and no Get-OERInventory root-scope warning; no error. The listing of named rows is class B, as in 4.1. The two Microsoft Graph POSTs are the getByIds name lookups.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.2 ===
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] 4.2 inventory.json role assignments: 14, at the root scope: 0; roleAssignments.json rows: 14, at the root scope: 0
[oer-s112] 4.2 README has the section: True
[oer-s112] 4.2 README: None. No role assignment this export read is at the root scope `/`. Role assignments are read only
[oer-s112] 4.2 warnings shown: 0; Export's root-scope warning: 0; Get-OERInventory's root-scope warning: 0
[oer-s112] 4.2 errors: 0
[oer-s112] 4.2 sent: token requests: 0; Microsoft Graph requests: 2, writes: 2 (POST, POST); Azure Resource Manager requests: 8, writes: 0, at the root scope: 0
RUNNER: check 4.2 exit code 0; started 2026-10-13T20:14:51Z; took 8 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## T. Teardown

### T.1. Remove every oer-s112- object

- [x] **T.1** The teardown deletes the two reviews, the role assignment at the resource group, the policy, the package, the catalog, the group and the resource group; the sweep finds nothing; the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS112Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `Teardown A: deleted access review oer-s112-review` and `... oer-s112-review-pkg`;
`Teardown B: DELETE of a role assignment at oer-s112-rg for oer-s112-group: 200`; the library's
removal of the policy, the package, the catalog and the group; `Teardown D: deleted oer-s112-rg.`;
`Access reviews with the prefix after the teardown: 0`; every `Counts:` line `equal: True`; exit code 0.
**Failure looks like:** a `RESIDUE` line or exit code 3 -- record each residue row here.

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Both access reviews deleted and read gone; the role assignment at oer-s112-rg deleted (200); the policy, the package, the catalog and the group removed by the library (removed 4, residue 0, unreadable 0); oer-s112-rg deleted; the sweep finds nothing; every count equal to the baseline; exit code 0.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\teardown-20261013-201517Z.log; OerLive 1.0.3.
[oer-s112] Mode: REMOVE. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s112] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s112] oer-s112-review-pkg is gone: converged after 1 read(s), 0.6 s.
[oer-s112] Teardown A: deleted access review oer-s112-review-pkg.
[oer-s112] oer-s112-review is gone: converged after 1 read(s), 0.4 s.
[oer-s112] Teardown A: deleted access review oer-s112-review.
[oer-s112] Teardown B: DELETE of a role assignment at oer-s112-rg for oer-s112-group: 200 .
[oer-s112] no role assignment of oer-s112-group is listed at oer-s112-rg: converged after 1 read(s), 0.4 s.
[oer-s112] Teardown of 'oer-s112-': users 0, groups 1, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s112] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s112] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s112] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s112] Deleted: oer-s112-ap: assignment policy 'oer-s112-policy' (204).
[oer-s112] Deleted: access package oer-s112-ap (204, 1 attempt(s)).
[oer-s112] Deleted: catalog oer-s112-catalog (204, 1 attempt(s)).
[oer-s112] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s112] Teardown 5/6: the prefixed groups.
[oer-s112] Deleted: group oer-s112-group (204).
[oer-s112] Teardown 6/6: the prefixed users.
[oer-s112] Teardown of 'oer-s112-': removed 4, residue 0, unreadable 0.
[oer-s112] oer-s112-rg is gone: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s112] oer-s112-rg is gone: converged after 2 read(s), 2.7 s.
[oer-s112] Teardown D: deleted oer-s112-rg.
[oer-s112] no 'oer-s112-' object is listed: not yet (read 1, 0.5 s, likely replication delay) -- reading again in 2 s.
[oer-s112] no 'oer-s112-' object is listed: not yet (read 2, 2.9 s, likely replication delay) -- reading again in 4 s.
[oer-s112] no 'oer-s112-' object is listed: not yet (read 3, 7.2 s, likely replication delay) -- reading again in 8 s.
[oer-s112] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s112-' is left.
[oer-s112] no 'oer-s112-' object is listed: converged after 4 read(s), 15.6 s.
[oer-s112] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s112-' is left.
[oer-s112] Access reviews with the prefix after the teardown: 0
[oer-s112] Resource group oer-s112-rg exists after the teardown: False
[oer-s112] Counts: groups now 97, at the baseline 97; equal: True
[oer-s112] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s112] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s112] Counts: accessReviewDefinitions now 6, at the baseline 6; equal: True
[oer-s112] Removed the recorded ids.
[oer-s112] Done.
[oer-s112] exit code: 0
RUNNER: check T.1 exit code 0; started 2026-10-13T20:15:15Z; took 37 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### T.2. Read back

- [x] **T.2** Nothing with the prefix is left, and the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS112Prereq.ps1') -ReadBack
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `access reviews with the prefix: 0`; `resource group oer-s112-rg exists: False`; every
`Counts:` line `equal: True`; `prefixed objects left: 0; unread collections: 0`; no residue row with
this step's prefix.
**Failure looks like:** anything left with the prefix.

Result: 2026-10-13 20:17 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. No access review and no object with the prefix, no resource group, every count equal to the baseline, no unread collection; raw\residue.json holds 5 rows of other prefixes (opim-s1-, opim-s2-), none of this step's, untouched.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.2 ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s112] Transcript (redacted): raw\s112\readback-20261013-201602Z.log; OerLive 1.0.3.
[oer-s112] Mode: READ BACK. Prefix 'oer-s112-'. Objects (fixed): oer-s112-group (security group, no member); oer-s112-catalog (catalog, no resource); oer-s112-ap (hidden access package, no resource role); oer-s112-policy (administrator assignments only); oer-s112-rg (tagged, empty); oer-s112-review (a self review of the members of oer-s112-group, quarterly from 14 days after the run, 1-day instances). The checklist's own objects: the package review oer-s112-review-pkg and a role assignment at oer-s112-rg for oer-s112-group. OerLive 1.0.3.
[oer-s112] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg2\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s112] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s112] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s112] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s112-' is left.
[oer-s112] Read-back: access reviews with the prefix: 0
[oer-s112] Read-back: resource group oer-s112-rg exists: False
[oer-s112] Counts: groups now 97, at the baseline 97; equal: True
[oer-s112] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s112] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s112] Counts: accessReviewDefinitions now 6, at the baseline 6; equal: True
[oer-s112] Read-back: residue row: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:09Z, attempts 3: 404 SubjectNotFound The subject is not found.; read back: still listed -- OerLive: Residue: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal': read back after the 'does not exist' answer -- not converged within budget (180 s, 10 reads).
[oer-s112] Read-back: residue row: PIM for Groups assignment 'opim-s1-grp: PIM for Groups owner assignment of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:12Z, attempts 3: 403 UnauthorizedAccessException {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup,PrivilegedAccess.ReadWrite.AzureADGroup,PrivilegedAssignmentSchedule.Remove.AzureADGroup.","instanceAnnotations":[]}
[oer-s112] Read-back: residue row: PIM for Groups eligibility 'opim-s2-grp: PIM for Groups member eligibility of a principal' (prefix opim-s2-), first refused 2026-10-10T23:39:01Z, attempts 1: 400 BadRequest {"error":{"code":"Request_BadRequest","message":"The source resource object or one of the objects being referenced do not exist.","innerError":{"date":"2026-10-10T23:39:01","request-id":"00000000-0000-0000-0000-000000000004","client-request-id":"00000000-0000-0000-0000-000000000005"}}}
[oer-s112] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-10T23:39:02Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s112] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-11T14:55:13Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s112] Read-back: prefixed objects left: 0; unread collections: 0; access reviews with the prefix: 0; residue rows: 5, of them with this step's prefix: 0.
[oer-s112] Done.
[oer-s112] exit code: 0
RUNNER: check T.2 exit code 0; started 2026-10-13T20:16:00Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

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
