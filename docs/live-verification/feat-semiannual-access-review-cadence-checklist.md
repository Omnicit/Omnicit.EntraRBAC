# Live verification checklist -- a semi-annual access review cadence (feat/semiannual-access-review-cadence)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant: only inside the prefix `oer-s106-`.** The prerequisite script
`Initialize-OerS106Prereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates a catalog `oer-s106-catalog`, a hidden access package `oer-s106-ap` in it with no resource,
and an assignment policy `oer-s106-policy` on the package that only an administrator can assign
through (no requestor, no approval, no expiration). Check 1.1 creates the access review
`oer-s106-review` on that package and policy with `New-OERAccessReviewDefinition`, check 2.3 applies
a document to it that must write nothing, and section 3
changes its cadence with `Set-OERAccessReviewDefinition` and with `Invoke-OERStructure`. Check 4.1
creates a second review, `oer-s106-review-doc`, through `Invoke-OERStructure`. Checks 5.1 and 5.2
each write one raw pattern the module cannot express onto `oer-s106-review`. Both reviews start two weeks after
the run and review a package with no assignment, so no review instance starts and nobody is asked
to review anything. The teardown deletes the two reviews first, then the policy, the package and the
catalog. No other object, policy or role is touched.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 as
`oer-live-cc` is a stop.

**Permission.** Creating, changing and deleting an access review definition needs the Microsoft
Graph application permission `AccessReview.ReadWrite.All` (`Get-OERRequiredScope` names it for
`New-`, `Set-` and `Remove-OERAccessReviewDefinition`). Check 0.2 reads which permissions
`oer-live-cc` holds and STOPS the run before anything is written when that one is missing. The
prerequisite script refuses its setup the same way. Granting a permission is the operator's
decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block installs
the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s106/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line, a warning and an error that
stops a script go straight to the host, so each block is run in its own process whose WHOLE output
(standard output and standard error) is written to a file under `raw\s106\`, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. A new cadence, `SemiAnnually`** ("feat: add the SemiAnnually access review cadence"). It means a Graph `absoluteMonthly` pattern
  with interval 6. It is accepted by `-Recurrence` on `New-OERAccessReviewDefinition` and
  `Set-OERAccessReviewDefinition` and by `"recurrence"` in a structure document (schema, validator,
  casing); `Get-OERInventory` exports a live absoluteMonthly interval 6 as `SemiAnnually` without a
  warning, where it exported `Monthly` with a warning before; and the apply engine compares and
  writes it like the other cadences, where it refused to rewrite such a review before.
- **B. The texts** ("docs: name the semi-annual cadence in the help, rationale and release notes",
  "docs: correct the access review cadence rationale" and "docs: tighten the access review cadence
  rationale"): the help of the cmdlets and helpers that list the cadences, the rationale section
  `access-review-cadence` and the release note.
- **C. An older export never makes a semi-annual review monthly** (round 1, decision A19: "fix: leave
  a semi-annual access review untouched when an older export says Monthly" and "docs: say that an
  older export leaves a semi-annual review untouched"). Every export before 1.1.4 wrote a live
  absoluteMonthly interval 6 as `Monthly`. Applying such a document does not make the review
  monthly: `Resolve-OERAccessReviewChange` leaves the recurrence, start date and range untouched and
  reports why, and `Invoke-OERStructure` shows it as one `Skipped` row with that reason, in the plan
  and in the run alike, with nothing written for the recurrence.

A live tenant is needed for A because the claim is about what Microsoft Graph stores and returns:
that `-Recurrence SemiAnnually` creates a definition whose live pattern is absoluteMonthly interval 6,
that the module reads that live pattern back as `SemiAnnually`, and that the round trip through
`Invoke-OERStructure` converges on a real definition. Checks 5.1 and 5.2 try to write a pattern the
module still cannot express raw; in round 1 Microsoft Graph refused both writes (400), so neither
pattern could be produced live. C needs it because the claim is that nothing is sent to a real
definition: 2.3 applies the document an older export would have written and reads the live pattern
afterwards.

## What this file does not check, and why

- **B, the texts (class B, G9).** They change what the help says, not what is sent. Section 6 names
  the gates and unit tests that hold them.
- **A review with instances.** Both reviews start two weeks after the run, so no instance exists and
  no reviewer is asked anything. The cadence is a property of the definition; an instance would add
  nothing this step changed.
- **A pattern the module cannot express (class B).** Measured in round 1 (5.1 and 5.2): Microsoft
  Graph v1.0 refuses a definition write of weekly interval 2 ("Only 1 is supported") and of
  absoluteMonthly interval 2 ("Only 1,3,6 and 12 are supported"), so no such pattern could be
  produced live. The unit tests named in 5.1 hold the export warning and the refusal.

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
- The **prerequisite objects**: run `Initialize-OerS106Prereq.ps1 -WhatIf`, then
  `Initialize-OerS106Prereq.ps1 -Unattended`, with `OER_LIVE_REPO` set, before section 1.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the
counters and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s106-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Ar = 'v1.0/identityGovernance/accessReviews/definitions'
$Package = 'oer-s106-ap'
$Policy = 'oer-s106-policy'
$Review = 'oer-s106-review'
$DocReview = 'oer-s106-review-doc'
# The first instance starts two weeks after the run (UTC midnight), so no instance starts during it.
$Start = [datetime]::UtcNow.Date.AddDays(14)
$StartText = $Start.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
# The Microsoft Graph application permissions this file needs.
$Needed = @('AccessReview.ReadWrite.All', 'EntitlementManagement.ReadWrite.All')
# The warning Get-OERInventory writes for a pattern outside the cadence vocabulary (unchanged by this branch).
$UnrepresentableWarning = "that the module's cadence vocabulary cannot represent; exporting the nearest coarser cadence instead of the true interval."

function Start-S106NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S106TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S106TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S106 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S106Count {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is
    # a GET.
    $global:S106Graph = [System.Collections.Generic.List[string]]::new()
    $global:S106Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S106Graph.Add(`$($Record)); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S106Arm.Add(`$($Record)); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S106Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S106Sent {
    # Requests counted since Start-S106Count, and how many of them were writes (any method but GET).
    $GraphWrites = @($global:S106Graph | Where-Object { $_ -ne 'GET' })
    $ArmWrites = @($global:S106Arm | Where-Object { $_ -ne 'GET' })
    "token requests: $global:S106TokenCalls; Microsoft Graph requests: $($global:S106Graph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S106Arm.Count), writes: $($ArmWrites.Count)"
}

function Get-S106GrantedRole {
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

function Get-S106Definition {
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

function Write-S106Pattern {
    # The live recurrence of a definition as Microsoft Graph stores it.
    param([Parameter(Mandatory)][string]$Label, [AllowNull()][object]$Definition)
    if ($null -eq $Definition) { Write-OerLiveStep "$Label definition: absent"; return }
    $Rec = $Definition['settings']['recurrence']
    if ($null -eq $Rec) { Write-OerLiveStep "$Label definition: no recurrence object (a one-time review)"; return }
    $P = $Rec['pattern']; $G = $Rec['range']
    Write-OerLiveStep "$Label live pattern: type $([string]$P['type']); interval $([string]$P['interval']); dayOfMonth $([string]$P['dayOfMonth']); range $([string]$G['type']); start $([string]$G['startDate'])"
}

function Wait-S106Pattern {
    # Reads the definition until its pattern is the expected one (replicas can lag a PUT).
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Type, [Parameter(Mandatory)][int]$Interval)
    $W = Wait-OerLiveConverged -Activity "$Name carries $Type interval $Interval" -Read { Get-S106Definition -Name $Name } -Test {
        $null -ne $args[0] -and $null -ne $args[0]['settings']['recurrence'] -and
        [string]$args[0]['settings']['recurrence']['pattern']['type'] -ceq $Type -and
        [int]$args[0]['settings']['recurrence']['pattern']['interval'] -eq $Interval
    }
    $W.Value
}

function Get-S106Export {
    # The access review section of Get-OERInventory for the prefixed reviews, and the warnings it wrote.
    $W = $null
    $Inv = Get-OERInventory -Include AccessReviews -AccessReviewFilter 'oer-s106-*' -WarningVariable W -WarningAction SilentlyContinue -ErrorAction Stop
    [PSCustomObject]@{ Reviews = @(@($Inv.AccessReviews) | Where-Object { $null -ne $_ }); Warnings = @(@($W) | ForEach-Object { [string]$_ }) }
}

function Write-S106Export {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Export)
    Write-OerLiveStep "$Label exported reviews: $($Export.Reviews.Count)"
    foreach ($R in $Export.Reviews) { Write-OerLiveStep "$Label exported: $($R.displayName) | recurrence $($R.recurrence) | startDate $($R.startDate)" }
    $Cadence = @($Export.Warnings | Where-Object { $_.Contains($UnrepresentableWarning) })
    Write-OerLiveStep "$Label warnings: $($Export.Warnings.Count); of them about a pattern the vocabulary cannot represent: $($Cadence.Count)"
    foreach ($T in $Cadence) { Write-OerLiveStep "$Label warning: $T" }
}

function New-S106Document {
    # A structure document holding the given exported (or hand-built) access review entries.
    param([Parameter(Mandatory)][object[]]$Reviews)
    [ordered]@{ version = '1.0'; accessReviews = @($Reviews) } | ConvertTo-Json -Depth 20
}

function Write-S106Rows {
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Rows)
    # An if-statement assignment unrolls no rows to $null, and @($null).Count is 1: drop nulls first.
    $Rows = @(@($Rows) | Where-Object { $null -ne $_ })
    Write-OerLiveStep "$Label rows: $($Rows.Count)"
    foreach ($R in @($Rows)) { Write-OerLiveStep "$Label row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
}

function Invoke-S106Apply {
    # One Invoke-OERStructure call -- a -WhatIf plan or a run -- counted from its first request to its last.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json, [switch]$Plan)
    Start-S106Count
    $E = $null
    try {
        $Rows = if ($Plan) {
            @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E)
        } else {
            @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable E)
        }
        $Sent = Get-S106Sent
    } finally { Stop-S106Count }
    Write-S106Rows -Label $Label -Rows $Rows
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
Write-OerLiveStep "The worktree's build carries A: ValidateSet $(& $Has "'Quarterly', 'SemiAnnually', 'Annually'"); interval 6 $(& $Has "'SemiAnnually' { 6 }"); read back $(& $Has "6 { 'SemiAnnually' }")"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `The worktree's build carries A:
ValidateSet True; interval 6 True; read back True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (round 1). The session's Repo is round 1's own worktree, not the main clone; the main clone is on main, never switched by this round; the worktree is on its local branch s10-steg6-r1 (tracking feat/semiannual-access-review-cadence) at 7e6efb8 with no tracked change, and its build carries A.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s106] The module loads from a worktree that is not the main clone: True
[oer-s106] Main clone: branch main; HEAD 6817b33
[oer-s106] Worktree: branch s10-steg6-r1; HEAD 7e6efb8 fix: leave a semi-annual access review untouched when an older export says Monthly; tracked changes: 0
[oer-s106] The worktree's build carries A: ValidateSet True; interval 6 True; read back True
RUNNER: check S.1 exit code 0; started 2026-10-09T10:23:57Z; took 3 s.
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (round 1). Every identity line True for the module session as oer-live-cc; identity check passed; the module is round 1's worktree build (1.1.4, built at 7e6efb8).

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] The module is the worktree's build: True
RUNNER: check 0.1 exit code 0; started 2026-10-09T10:24:01Z; took 6 s.
```

### 0.2. oer-live-cc holds the permissions this file needs

- [x] **0.2** `oer-live-cc` holds `AccessReview.ReadWrite.All` and `EntitlementManagement.ReadWrite.All`.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
$Granted = Get-S106GrantedRole
Write-OerLiveStep "Microsoft Graph application permissions granted to oer-live-cc: $($Granted.Count)"
foreach ($Name in @($Needed + 'AccessReview.Read.All')) { Write-OerLiveStep "Holds $($Name): $($Granted -ccontains $Name)" }
$Missing = @($Needed | Where-Object { $Granted -cnotcontains $_ })
Write-OerLiveStep "Every permission this file needs is granted: $($Missing.Count -eq 0)$(if ($Missing.Count) { " (missing: $($Missing -join ', '))" })"
Write-OerLiveStep "Token requests: $global:S106TokenCalls"
Disconnect-OerLive
```

**Expect:** `Holds AccessReview.ReadWrite.All: True`, `Holds EntitlementManagement.ReadWrite.All:
True` and `Every permission this file needs is granted: True`.
**Failure looks like:** `Holds AccessReview.ReadWrite.All: False` -- STOP before anything is written
(G11.7): the step needs a permission `oer-live-cc` does not hold, and granting it is the operator's
decision. Do not run the prerequisite script's setup, and never sign in another way. Every check
after this one is then marked `[~]` with "cannot be verified, and therefore we do not know".

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (round 1). oer-live-cc now holds 18 Microsoft Graph application permissions, among them AccessReview.ReadWrite.All and EntitlementManagement.ReadWrite.All (granted by the operator after step 6 stopped here; this round changed no permission). 0 token requests beyond the sign-in. The run went on from 1.1.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] Microsoft Graph application permissions granted to oer-live-cc: 18
[oer-s106] Holds AccessReview.ReadWrite.All: True
[oer-s106] Holds EntitlementManagement.ReadWrite.All: True
[oer-s106] Holds AccessReview.Read.All: True
[oer-s106] Every permission this file needs is granted: True
[oer-s106] Token requests: 0
RUNNER: check 0.2 exit code 0; started 2026-10-09T10:24:09Z; took 5 s.
```

## 1. Created as SemiAnnually

### 1.1. New-OERAccessReviewDefinition -Recurrence SemiAnnually stores absoluteMonthly interval 6

- [~] **1.1** The review is created, and Microsoft Graph stores its pattern as absoluteMonthly interval 6 with the start date's day of month.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
if (Get-S106Definition -Name $Review) { throw "STOP: $Review exists already; run the teardown first." }
Start-S106Count
try {
    $New = New-OERAccessReviewDefinition -DisplayName $Review -DescriptionForAdmins 'Omnicit.EntraRBAC live verification (oer-s106-)' `
        -DescriptionForReviewers 'Test review; no instance starts during the run.' -AccessPackage $Package -AssignmentPolicy $Policy `
        -SelfReview -Recurrence SemiAnnually -StartDate $Start -DurationInDays 14 -Confirm:$false -ErrorAction Stop
    $Sent = Get-S106Sent
} finally { Stop-S106Count }
Write-OerLiveStep "Created: $([bool]$New); sent: $Sent"
$Def = Wait-S106Pattern -Name $Review -Type 'absoluteMonthly' -Interval 6
Write-S106Pattern -Label '1.1' -Definition $Def
Write-OerLiveStep "dayOfMonth is the start date's day ($($Start.Day)): $([int]$Def['settings']['recurrence']['pattern']['dayOfMonth'] -eq $Start.Day)"
Disconnect-OerLive
```

**Expect:** `Created: True`, one Microsoft Graph write (`POST`); `1.1 live pattern: type
absoluteMonthly; interval 6; dayOfMonth` the start date's day; `range noEnd`; and `dayOfMonth is the
start date's day: True`.
**Failure looks like:** an error naming `-Recurrence` (the build lacks the value), a pattern with
another interval, or `type weekly`.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PARTIAL. The claim of A holds: the review was created with one POST, and Microsoft Graph stores its pattern as absoluteMonthly interval 6, range noEnd, start 2026-10-23. The sub-expectation that Graph keeps the start date's day as dayOfMonth did NOT hold: Graph returns dayOfMonth 0, while the module sends the start date's day (23; held by New-OERAccessReviewRecurrence.Tests.ps1 'builds a semi-annual recurrence as absoluteMonthly interval 6 with dayOfMonth from the start date'). The module never compares or exports dayOfMonth, so no later check depends on it; every later read in this file, after Set, Invoke-OERStructure and the document create alike, shows dayOfMonth 0 too. Reported as a finding.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] Created: True; sent: token requests: 0; Microsoft Graph requests: 4, writes: 1 (POST); Azure Resource Manager requests: 0, writes: 0
[oer-s106] oer-s106-review carries absoluteMonthly interval 6: converged after 1 read(s), 0.7 s.
[oer-s106] 1.1 live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] dayOfMonth is the start date's day (23): False
RUNNER: check 1.1 exit code 0; started 2026-10-09T10:24:24Z; took 8 s.
```

## 2. Exported as SemiAnnually, and unchanged when applied again

### 2.1. Get-OERInventory exports the live review as SemiAnnually, with no warning about its cadence

- [x] **2.1** The export carries `recurrence` `SemiAnnually` for `oer-s106-review` and writes no warning about a pattern it cannot represent.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
Write-S106Pattern -Label '2.1 before' -Definition (Get-S106Definition -Name $Review)
$X = Get-S106Export
Write-S106Export -Label '2.1' -Export $X
$Row = @($X.Reviews | Where-Object { $_.displayName -ceq $Review })
Write-OerLiveStep "2.1 the export reached $($Review): $($Row.Count -eq 1); its recurrence is SemiAnnually: $(@($Row | Where-Object { $_.recurrence -ceq 'SemiAnnually' }).Count -eq 1)"
Disconnect-OerLive
```

**Expect:** `2.1 exported: oer-s106-review | recurrence SemiAnnually | startDate` the start date;
`of them about a pattern the vocabulary cannot represent: 0`; `the export reached oer-s106-review:
True; its recurrence is SemiAnnually: True`.
**Failure looks like:** `recurrence Monthly` with a warning naming `absoluteMonthly interval 6` --
the behaviour before this branch.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The export carries recurrence SemiAnnually and startDate 2026-10-23 for oer-s106-review, and writes no warning at all (0 about a pattern the vocabulary cannot represent).

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] 2.1 before live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] 2.1 exported reviews: 1
[oer-s106] 2.1 exported: oer-s106-review | recurrence SemiAnnually | startDate 2026-10-23
[oer-s106] 2.1 warnings: 0; of them about a pattern the vocabulary cannot represent: 0
[oer-s106] 2.1 the export reached oer-s106-review: True; its recurrence is SemiAnnually: True
RUNNER: check 2.1 exit code 0; started 2026-10-09T10:25:26Z; took 7 s.
```

### 2.2. The exported document through Invoke-OERStructure: Unchanged in the plan and in two runs, nothing written (G8)

- [x] **2.2** The plan and both runs report `Unchanged` for `oer-s106-review`, with 0 writes, and the live pattern is still absoluteMonthly interval 6.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
$X = Get-S106Export
$Doc = New-S106Document -Reviews @($X.Reviews | Where-Object { $_.displayName -ceq $Review })
Write-OerLiveStep "2.2 the document declares recurrence SemiAnnually: $($Doc.Contains('"recurrence": "SemiAnnually"'))"
Invoke-S106Apply -Label '2.2 plan' -Json $Doc -Plan
Invoke-S106Apply -Label '2.2 run 1' -Json $Doc
Invoke-S106Apply -Label '2.2 run 2' -Json $Doc
Write-S106Pattern -Label '2.2 after' -Definition (Get-S106Definition -Name $Review)
Disconnect-OerLive
```

**Expect:** `the document declares recurrence SemiAnnually: True`; in the plan and in both runs one
`accessReviews | oer-s106-review | Unchanged` row, `errors of Invoke-OERStructure: 0` and `writes:
0`; `2.2 after live pattern: type absoluteMonthly; interval 6`.
**Failure looks like:** `Updated` or a `NotApplied` detail naming the pattern -- the comparison does
not read interval 6 as `SemiAnnually`; or any write.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). The plan and both runs report one Unchanged row for oer-s106-review, errors 0 and writes 0 (one Graph GET each); the live pattern is still absoluteMonthly interval 6, start 2026-10-23.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] 2.2 the document declares recurrence SemiAnnually: True
[oer-s106] 2.2 plan rows: 1
[oer-s106] 2.2 plan row: accessReviews | oer-s106-review | Unchanged | access review 'oer-s106-review' already matches
[oer-s106] 2.2 plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 2.2 plan sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s106] 2.2 run 1 rows: 1
[oer-s106] 2.2 run 1 row: accessReviews | oer-s106-review | Unchanged | access review 'oer-s106-review' already matches
[oer-s106] 2.2 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 2.2 run 1 sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s106] 2.2 run 2 rows: 1
[oer-s106] 2.2 run 2 row: accessReviews | oer-s106-review | Unchanged | access review 'oer-s106-review' already matches
[oer-s106] 2.2 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 2.2 run 2 sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s106] 2.2 after live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
RUNNER: check 2.2 exit code 0; started 2026-10-09T10:25:34Z; took 8 s.
```

### 2.3. A document declaring Monthly for the semi-annual review (what an export before 1.1.4 wrote): Skipped with the reason in the plan and in the runs, nothing written (A19)

- [x] **2.3** With the live review at absoluteMonthly interval 6, a document declaring `Monthly` for it gives one `Skipped` row with the A19 reason in the plan and in two runs, 0 writes, and the live pattern is still absoluteMonthly interval 6 with the same start date.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
Write-S106Pattern -Label '2.3 before' -Definition (Wait-S106Pattern -Name $Review -Type 'absoluteMonthly' -Interval 6)
$Entry = @((Get-S106Export).Reviews | Where-Object { $_.displayName -ceq $Review })[0]
# What every export before 1.1.4 wrote for a live absoluteMonthly interval 6.
$Entry.recurrence = 'Monthly'
$Doc = New-S106Document -Reviews @($Entry)
Write-OerLiveStep "2.3 the document declares recurrence Monthly: $($Doc.Contains('"recurrence": "Monthly"'))"
Invoke-S106Apply -Label '2.3 plan' -Json $Doc -Plan
Invoke-S106Apply -Label '2.3 run 1' -Json $Doc
Invoke-S106Apply -Label '2.3 run 2' -Json $Doc
Write-S106Pattern -Label '2.3 after' -Definition (Get-S106Definition -Name $Review)
Disconnect-OerLive
```

**Expect:** `2.3 before live pattern: type absoluteMonthly; interval 6`; `the document declares
recurrence Monthly: True`; in the plan and in both runs exactly one row,
`accessReviews | oer-s106-review | Skipped | the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose`,
with the same text in a warning before it, `errors of Invoke-OERStructure: 0` and `writes: 0`; `2.3
after live pattern: type absoluteMonthly; interval 6`, with the start date of `2.3 before`.
**Failure looks like:** the plan's row `Skipped` with a detail naming `recurrence=Monthly`, or a run
`Updated` with one write (`PUT`) and `2.3 after` interval 1 -- the branch before round 1 (R4 of step
6), which made the review monthly.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (A19). With the live review at absoluteMonthly interval 6, the exported entry with recurrence Monthly (what an export before 1.1.4 wrote) gives, in the plan and in both runs, exactly one row, Skipped, whose detail is the A19 reason word for word, preceded by the same text as a warning; errors 0, writes 0 (one Graph GET each). The live pattern afterwards is still absoluteMonthly interval 6, start 2026-10-23. Before round 1 the same document planned 'would update ... recurrence=Monthly' and the run made the review monthly (R4 of step 6).

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.3 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] oer-s106-review carries absoluteMonthly interval 6: converged after 1 read(s), 0.8 s.
[oer-s106] 2.3 before live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] 2.3 the document declares recurrence Monthly: True
WARNING: Sync-OERStructureAccessReview: access review 'oer-s106-review' -- the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose.
[oer-s106] 2.3 plan rows: 1
[oer-s106] 2.3 plan row: accessReviews | oer-s106-review | Skipped | the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose
[oer-s106] 2.3 plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 2.3 plan sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
WARNING: Sync-OERStructureAccessReview: access review 'oer-s106-review' -- the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose.
[oer-s106] 2.3 run 1 rows: 1
[oer-s106] 2.3 run 1 row: accessReviews | oer-s106-review | Skipped | the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose
[oer-s106] 2.3 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 2.3 run 1 sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
WARNING: Sync-OERStructureAccessReview: access review 'oer-s106-review' -- the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose.
[oer-s106] 2.3 run 2 rows: 1
[oer-s106] 2.3 run 2 row: accessReviews | oer-s106-review | Skipped | the live review is semi-annual (absoluteMonthly interval 6), which an export made before 1.1.4 wrote as 'Monthly'; the recurrence, start date and range were left untouched so the review is not made monthly. Declare 'SemiAnnually' to keep it, or run Set-OERAccessReviewDefinition with -Recurrence Monthly and a -StartDate to make it monthly on purpose
[oer-s106] 2.3 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 2.3 run 2 sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s106] 2.3 after live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
RUNNER: check 2.3 exit code 0; started 2026-10-09T10:25:49Z; took 9 s.
```

## 3. Changing the cadence

### 3.1. Set-OERAccessReviewDefinition from SemiAnnually to Quarterly sends interval 3

- [x] **3.1** After `-Recurrence Quarterly`, the live pattern is absoluteMonthly interval 3, and the export says `Quarterly` with no cadence warning.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
Start-S106Count
try { $Set = Set-OERAccessReviewDefinition -Id $Review -Recurrence Quarterly -StartDate $Start -Confirm:$false -ErrorAction Stop; $Sent = Get-S106Sent } finally { Stop-S106Count }
Write-OerLiveStep "3.1 Set returned the definition: $([bool]$Set); sent: $Sent"
Write-S106Pattern -Label '3.1' -Definition (Wait-S106Pattern -Name $Review -Type 'absoluteMonthly' -Interval 3)
Write-S106Export -Label '3.1' -Export (Get-S106Export)
Disconnect-OerLive
```

**Expect:** one write (`PUT`); `3.1 live pattern: type absoluteMonthly; interval 3`; `3.1 exported:
oer-s106-review | recurrence Quarterly`; no cadence warning.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Set-OERAccessReviewDefinition -Recurrence Quarterly sent one PUT; the live pattern is absoluteMonthly interval 3; the export says Quarterly with no warning.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] 3.1 Set returned the definition: True; sent: token requests: 0; Microsoft Graph requests: 4, writes: 1 (PUT); Azure Resource Manager requests: 0, writes: 0
[oer-s106] oer-s106-review carries absoluteMonthly interval 3: converged after 1 read(s), 0.8 s.
[oer-s106] 3.1 live pattern: type absoluteMonthly; interval 3; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] 3.1 exported reviews: 1
[oer-s106] 3.1 exported: oer-s106-review | recurrence Quarterly | startDate 2026-10-23
[oer-s106] 3.1 warnings: 0; of them about a pattern the vocabulary cannot represent: 0
RUNNER: check 3.1 exit code 0; started 2026-10-09T10:26:08Z; took 8 s.
```

### 3.2. Set-OERAccessReviewDefinition from Quarterly to SemiAnnually sends interval 6

- [x] **3.2** After `-Recurrence SemiAnnually`, the live pattern is absoluteMonthly interval 6 again, and the export says `SemiAnnually` with no cadence warning.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
Write-S106Pattern -Label '3.2 before' -Definition (Get-S106Definition -Name $Review)
Start-S106Count
try { $Set = Set-OERAccessReviewDefinition -Id $Review -Recurrence SemiAnnually -StartDate $Start -Confirm:$false -ErrorAction Stop; $Sent = Get-S106Sent } finally { Stop-S106Count }
Write-OerLiveStep "3.2 Set returned the definition: $([bool]$Set); sent: $Sent"
Write-S106Pattern -Label '3.2' -Definition (Wait-S106Pattern -Name $Review -Type 'absoluteMonthly' -Interval 6)
Write-S106Export -Label '3.2' -Export (Get-S106Export)
Disconnect-OerLive
```

**Expect:** `3.2 before live pattern: ... interval 3`; one write (`PUT`); `3.2 live pattern: type
absoluteMonthly; interval 6`; `3.2 exported: oer-s106-review | recurrence SemiAnnually`; no cadence
warning.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. From interval 3, Set-OERAccessReviewDefinition -Recurrence SemiAnnually sent one PUT; the live pattern is absoluteMonthly interval 6 again; the export says SemiAnnually with no warning.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] 3.2 before live pattern: type absoluteMonthly; interval 3; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] 3.2 Set returned the definition: True; sent: token requests: 0; Microsoft Graph requests: 4, writes: 1 (PUT); Azure Resource Manager requests: 0, writes: 0
[oer-s106] oer-s106-review carries absoluteMonthly interval 6: converged after 1 read(s), 0.4 s.
[oer-s106] 3.2 live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] 3.2 exported reviews: 1
[oer-s106] 3.2 exported: oer-s106-review | recurrence SemiAnnually | startDate 2026-10-23
[oer-s106] 3.2 warnings: 0; of them about a pattern the vocabulary cannot represent: 0
RUNNER: check 3.2 exit code 0; started 2026-10-09T10:26:17Z; took 7 s.
```

### 3.3. Invoke-OERStructure from Quarterly to SemiAnnually: Updated once, then Unchanged (G8)

- [x] **3.3** With the live review back at Quarterly, a document declaring `SemiAnnually` plans an update, the first run updates it (one write, live interval 6), and the second run is `Unchanged` with 0 writes.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
$null = Set-OERAccessReviewDefinition -Id $Review -Recurrence Quarterly -StartDate $Start -Confirm:$false -ErrorAction Stop
Write-S106Pattern -Label '3.3 before' -Definition (Wait-S106Pattern -Name $Review -Type 'absoluteMonthly' -Interval 3)
$Entry = @((Get-S106Export).Reviews | Where-Object { $_.displayName -ceq $Review })[0]
$Entry.recurrence = 'SemiAnnually'
$Doc = New-S106Document -Reviews @($Entry)
Invoke-S106Apply -Label '3.3 plan' -Json $Doc -Plan
Invoke-S106Apply -Label '3.3 run 1' -Json $Doc
Write-S106Pattern -Label '3.3 after run 1' -Definition (Wait-S106Pattern -Name $Review -Type 'absoluteMonthly' -Interval 6)
Invoke-S106Apply -Label '3.3 run 2' -Json $Doc
Write-S106Pattern -Label '3.3 after run 2' -Definition (Get-S106Definition -Name $Review)
Disconnect-OerLive
```

**Expect:** `3.3 before live pattern: ... interval 3`; the plan's row `Skipped` with a detail naming
`recurrence=SemiAnnually` and `writes: 0`; run 1 `Updated` with `recurrence=SemiAnnually` and one
write (`PUT`); `3.3 after run 1 live pattern: type absoluteMonthly; interval 6`; run 2 `Unchanged`
with `writes: 0`.
**Failure looks like:** run 1 `Skipped` with a detail saying the live pattern cannot be expressed --
the refusal before this branch; or run 2 `Updated` (no convergence).

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). With the live review back at Quarterly, the plan's row is Skipped 'would update ... (recurrence=SemiAnnually startDate=2026-10-23)' with 0 writes; run 1 is Updated with one PUT and the live pattern becomes absoluteMonthly interval 6; run 2 is Unchanged with 0 writes.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.3 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] oer-s106-review carries absoluteMonthly interval 3: converged after 1 read(s), 0.6 s.
[oer-s106] 3.3 before live pattern: type absoluteMonthly; interval 3; dayOfMonth 0; range noEnd; start 2026-10-23
What if: Performing the operation "Update access review definition" on target "oer-s106-review".
[oer-s106] 3.3 plan rows: 1
[oer-s106] 3.3 plan row: accessReviews | oer-s106-review | Skipped | would update access review 'oer-s106-review' (recurrence=SemiAnnually startDate=2026-10-23)
[oer-s106] 3.3 plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 3.3 plan sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s106] 3.3 run 1 rows: 1
[oer-s106] 3.3 run 1 row: accessReviews | oer-s106-review | Updated | updated access review 'oer-s106-review' (recurrence=SemiAnnually startDate=2026-10-23)
[oer-s106] 3.3 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 3.3 run 1 sent: token requests: 0; Microsoft Graph requests: 4, writes: 1 (PUT); Azure Resource Manager requests: 0, writes: 0
[oer-s106] oer-s106-review carries absoluteMonthly interval 6: converged after 1 read(s), 0.3 s.
[oer-s106] 3.3 after run 1 live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] 3.3 run 2 rows: 1
[oer-s106] 3.3 run 2 row: accessReviews | oer-s106-review | Unchanged | access review 'oer-s106-review' already matches
[oer-s106] 3.3 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 3.3 run 2 sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s106] 3.3 after run 2 live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
RUNNER: check 3.3 exit code 0; started 2026-10-09T10:26:25Z; took 11 s.
```

## 4. Created by a document

### 4.1. A document creating a SemiAnnually review: Created, then Unchanged (G8)

- [x] **4.1** A document declaring `oer-s106-review-doc` with `"recurrence": "semiannually"` (any casing) creates it with absoluteMonthly interval 6, and the second run is `Unchanged` with 0 writes.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
if (Get-S106Definition -Name $DocReview) { throw "STOP: $DocReview exists already; run the teardown first." }
$Doc = New-S106Document -Reviews @([ordered]@{
        displayName = $DocReview; accessPackage = $Package; assignmentPolicy = $Policy; reviewers = @()
        recurrence = 'semiannually'; startDate = $StartText; durationInDays = 14
        descriptionForAdmins = 'Omnicit.EntraRBAC live verification (oer-s106-)'; descriptionForReviewers = 'Test review; no instance starts during the run.'
    })
$V = Test-OERStructure -Json $Doc
# Errors holds every finding, each with a Severity of Error or Warning.
$Findings = @(@($V.Errors) | Where-Object { $null -ne $_ })
Write-OerLiveStep "4.1 Test-OERStructure valid: $($V.Valid); errors: $(@($Findings | Where-Object { [string]$_.Severity -eq 'Error' }).Count); casing warnings naming SemiAnnually: $(@($Findings | Where-Object { [string]$_.Severity -eq 'Warning' -and [string]$_.Message -match 'SemiAnnually' }).Count)"
Invoke-S106Apply -Label '4.1 run 1' -Json $Doc
Write-S106Pattern -Label '4.1 after run 1' -Definition (Wait-S106Pattern -Name $DocReview -Type 'absoluteMonthly' -Interval 6)
Invoke-S106Apply -Label '4.1 run 2' -Json $Doc
Disconnect-OerLive
```

**Expect:** `Test-OERStructure valid: True; errors: 0`, one casing warning naming `SemiAnnually`;
run 1 `Created` with `(recurrence: SemiAnnually)` and one write (`POST`); `4.1 after run 1 live
pattern: type absoluteMonthly; interval 6`; run 2 `Unchanged` with `writes: 0`.
**Failure looks like:** a validation error naming `recurrence`, `Failed` with "unrecognised
recurrence value", or run 2 `Updated`.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). Test-OERStructure: valid, 0 errors, one casing warning naming SemiAnnually for 'semiannually'; run 1 Created oer-s106-review-doc (recurrence: SemiAnnually) with one POST, live absoluteMonthly interval 6; run 2 Unchanged with 0 writes.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.1 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] 4.1 Test-OERStructure valid: True; errors: 0; casing warnings naming SemiAnnually: 1
[oer-s106] 4.1 run 1 rows: 1
[oer-s106] 4.1 run 1 row: accessReviews | oer-s106-review-doc | Created | created access review 'oer-s106-review-doc' (recurrence: SemiAnnually)
[oer-s106] 4.1 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 4.1 run 1 sent: token requests: 0; Microsoft Graph requests: 5, writes: 1 (POST); Azure Resource Manager requests: 0, writes: 0
[oer-s106] oer-s106-review-doc carries absoluteMonthly interval 6: converged after 1 read(s), 0.2 s.
[oer-s106] 4.1 after run 1 live pattern: type absoluteMonthly; interval 6; dayOfMonth 0; range noEnd; start 2026-10-23
[oer-s106] 4.1 run 2 rows: 1
[oer-s106] 4.1 run 2 row: accessReviews | oer-s106-review-doc | Unchanged | access review 'oer-s106-review-doc' already matches
[oer-s106] 4.1 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s106] 4.1 run 2 sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check 4.1 exit code 0; started 2026-10-09T10:26:44Z; took 8 s.
```

## 5. A pattern the module still cannot express

### 5.1. A live weekly interval 2: exported with the same warning, and refused on apply (A, or B when it cannot run)

- [~] **5.1** A raw write makes `oer-s106-review` weekly interval 2; the export says `Weekly` with the unchanged warning naming `weekly interval 2`; a document declaring `SemiAnnually` is refused for it in the plan and in the run with 0 writes, and the live pattern stays weekly interval 2.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
# A raw full-object PUT, built the way Set-OERAccessReviewDefinition builds it, with only the pattern changed.
$Cur = Get-S106Definition -Name $Review
$Settings = @{}; foreach ($K in $Cur['settings'].Keys) { $Settings[$K] = $Cur['settings'][$K] }
$Settings['recurrence'] = @{ pattern = @{ type = 'weekly'; interval = 2 }; range = $Cur['settings']['recurrence']['range'] }
$Body = @{ displayName = $Cur['displayName']; descriptionForAdmins = $Cur['descriptionForAdmins']; descriptionForReviewers = $Cur['descriptionForReviewers']; scope = $Cur['scope']; settings = $Settings; reviewers = @($Cur['reviewers']) }
foreach ($K in 'fallbackReviewers', 'instanceEnumerationScope', 'additionalNotificationRecipients') { if ($null -ne $Cur[$K]) { $Body[$K] = $Cur[$K] } }
Assert-OerLivePrefix -Name $Cur['displayName']
$Put = Invoke-OerLiveGraph -Method PUT -Uri "$Ar/$([string]$Cur['id'])" -Body $Body
Assert-OerLiveOk -Response $Put -Activity "Writing weekly interval 2 onto $Review" | Out-Null
Write-S106Pattern -Label '5.1 raw' -Definition (Wait-S106Pattern -Name $Review -Type 'weekly' -Interval 2)
$X = Get-S106Export
Write-S106Export -Label '5.1' -Export $X
$Entry = @($X.Reviews | Where-Object { $_.displayName -ceq $Review })[0]
$Entry.recurrence = 'SemiAnnually'
$Doc = New-S106Document -Reviews @($Entry)
Invoke-S106Apply -Label '5.1 plan' -Json $Doc -Plan
Invoke-S106Apply -Label '5.1 run' -Json $Doc
Write-S106Pattern -Label '5.1 after' -Definition (Get-S106Definition -Name $Review)
Disconnect-OerLive
```

**Expect:** `5.1 raw live pattern: type weekly; interval 2`; `5.1 exported: oer-s106-review |
recurrence Weekly`, and one cadence warning naming `weekly interval 2`; in the plan and in the run
exactly one row for `oer-s106-review`, `Skipped`, whose detail says `the live recurrence pattern
(weekly interval 2) cannot be expressed by the module's cadence vocabulary`, and `writes: 0`; `5.1
after live pattern: type weekly; interval 2`.
**Class B when this cannot run** (no `AccessReview.ReadWrite.All`, or, as measured in round 1,
Microsoft Graph refuses the raw write): the unit tests "does not rewrite
an unrepresentable live interval when another field changes" and "reports an unrepresentable weekly
interval as not applied" in `tests/Unit/Private/Resolve-OERAccessReviewChange.Tests.ps1`, and "warns
rather than silently collapsing an unrepresentable recurrence interval" in
`tests/Unit/Public/Get-OERInventory.Tests.ps1`, hold the refusal and the warning for absoluteMonthly
interval 2 and weekly interval 2.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: class B, as this check provides. Not runnable as written: Microsoft Graph refused the raw PUT of weekly interval 2 with 400 'Invalid interval passed for recurrence pattern type weekly. Only 1 is supported', so nothing was written and the plan and the run never started. A weekly interval other than 1 cannot be written to an access review definition through Graph v1.0 (measured here). The module's refusal of such a live pattern is held by Resolve-OERAccessReviewChange.Tests.ps1 'reports an unrepresentable weekly interval as not applied', and the export's warning by Get-OERInventory.Tests.ps1 'warns rather than silently collapsing an unrepresentable recurrence interval'.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.1 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
Writing weekly interval 2 onto oer-s106-review failed: PUT v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000007 answered 400  -- Invalid interval passed for recurrence pattern type weekly. Only 1 is supported
At VAULT\OerLive\OerLive.psm1:673 char:5
+     throw $Text
+     ~~~~~~~~~~~
+ CategoryInfo          : OperationStopped: (Writing weekly inte…Only 1 is supported:String) [], RuntimeException
+ FullyQualifiedErrorId : Writing weekly interval 2 onto oer-s106-review failed: PUT v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000007 answered 400  -- Invalid interval passed for recurrence pattern type weekly. Only 1 is supported
RUNNER: check 5.1 exit code 1; started 2026-10-09T10:26:53Z; took 6 s.
```

### 5.2. A live absoluteMonthly interval 2: exported with the same warning, and refused on apply

- [~] **5.2** A raw write makes `oer-s106-review` absoluteMonthly interval 2; the export says `Monthly` with the unchanged warning naming `absoluteMonthly interval 2`; a document declaring `SemiAnnually` is refused for it in the plan and in the run with 0 writes, and the live pattern stays absoluteMonthly interval 2.

Added in round 1, after 5.1 measured that Microsoft Graph refuses a weekly interval other than 1 on
an access review definition. An absoluteMonthly interval other than 1, 3, 6 or 12 is the other shape
outside the vocabulary, and the one the unit tests use first. Round 1 measured that Graph refuses
this write too (400, "Only 1,3,6 and 12 are supported"), so 5.2 is class B like 5.1 unless Graph
starts to accept it.

```powershell
Connect-OerLive -Arm
Start-S106NoPrompt
# A raw full-object PUT, built the way Set-OERAccessReviewDefinition builds it, with only the pattern changed.
$Cur = Get-S106Definition -Name $Review
$Settings = @{}; foreach ($K in $Cur['settings'].Keys) { $Settings[$K] = $Cur['settings'][$K] }
$Settings['recurrence'] = @{ pattern = @{ type = 'absoluteMonthly'; interval = 2; dayOfMonth = $Start.Day }; range = $Cur['settings']['recurrence']['range'] }
$Body = @{ displayName = $Cur['displayName']; descriptionForAdmins = $Cur['descriptionForAdmins']; descriptionForReviewers = $Cur['descriptionForReviewers']; scope = $Cur['scope']; settings = $Settings; reviewers = @($Cur['reviewers']) }
foreach ($K in 'fallbackReviewers', 'instanceEnumerationScope', 'additionalNotificationRecipients') { if ($null -ne $Cur[$K]) { $Body[$K] = $Cur[$K] } }
Assert-OerLivePrefix -Name $Cur['displayName']
$Put = Invoke-OerLiveGraph -Method PUT -Uri "$Ar/$([string]$Cur['id'])" -Body $Body
Assert-OerLiveOk -Response $Put -Activity "Writing absoluteMonthly interval 2 onto $Review" | Out-Null
Write-S106Pattern -Label '5.2 raw' -Definition (Wait-S106Pattern -Name $Review -Type 'absoluteMonthly' -Interval 2)
$X = Get-S106Export
Write-S106Export -Label '5.2' -Export $X
$Entry = @($X.Reviews | Where-Object { $_.displayName -ceq $Review })[0]
$Entry.recurrence = 'SemiAnnually'
$Doc = New-S106Document -Reviews @($Entry)
Invoke-S106Apply -Label '5.2 plan' -Json $Doc -Plan
Invoke-S106Apply -Label '5.2 run' -Json $Doc
Write-S106Pattern -Label '5.2 after' -Definition (Get-S106Definition -Name $Review)
Disconnect-OerLive
```

**Expect:** `5.2 raw live pattern: type absoluteMonthly; interval 2`; `5.2 exported: oer-s106-review
| recurrence Monthly`, and one cadence warning naming `absoluteMonthly interval 2`; in the plan and
in the run exactly one row for `oer-s106-review`, `Skipped`, whose detail says `the live recurrence
pattern (absoluteMonthly interval 2) cannot be expressed by the module's cadence vocabulary`, and
`writes: 0`; `5.2 after live pattern: type absoluteMonthly; interval 2`.
**Failure looks like:** a run `Updated` with one write (`PUT`) and `5.2 after` interval 6 -- the
module rewrote a pattern it cannot reproduce. If Microsoft Graph refuses the raw write as it refused
5.1's, the check is class B like 5.1.

Result: 2026-10-09 10:29 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: class B. Microsoft Graph refused the raw PUT of absoluteMonthly interval 2 too, with 400 'Invalid interval passed for recurrence pattern type absoluteMonthly. Only 1,3,6 and 12 are supported'; nothing was written. Measured with 5.1: on a definition write Graph v1.0 accepts exactly weekly interval 1 and absoluteMonthly interval 1, 3, 6 and 12 -- the module's cadences, SemiAnnually included -- so no pattern outside the vocabulary could be produced here. The refusal of one is held by Resolve-OERAccessReviewChange.Tests.ps1 'does not rewrite an unrepresentable live interval when another field changes' (absoluteMonthly interval 2) and the export warning by Get-OERInventory.Tests.ps1 'warns rather than silently collapsing an unrepresentable recurrence interval'.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.2 ===
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
Writing absoluteMonthly interval 2 onto oer-s106-review failed: PUT v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000007 answered 400  -- Invalid interval passed for recurrence pattern type absoluteMonthly. Only 1,3,6 and 12 are supported
At VAULT\OerLive\OerLive.psm1:673 char:5
+     throw $Text
+     ~~~~~~~~~~~
+ CategoryInfo          : OperationStopped: (Writing absoluteMon…nd 12 are supported:String) [], RuntimeException
+ FullyQualifiedErrorId : Writing absoluteMonthly interval 2 onto oer-s106-review failed: PUT v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000007 answered 400  -- Invalid interval passed for recurrence pattern type absoluteMonthly. Only 1,3,6 and 12 are supported
RUNNER: check 5.2 exit code 1; started 2026-10-09T10:28:06Z; took 6 s.
```

## 6. The texts (class B)

### 6.1. The help, the schema, the prompt template, the rationale and the release note are held by gates and tests

- [x] **6.1** Each text is held by a gate or a unit test of the branch's gate run.

The help of `New-OERAccessReviewRecurrence`, `New-OERAccessReviewDefinition`,
`Set-OERAccessReviewDefinition`, `Get-OERInventory`, `Resolve-OERAccessReviewChange` and
`Sync-OERStructureAccessReview` names `SemiAnnually` (the `module.tests.ps1` help gate parses each);
the schema's enum and the prompt template's list are held by `Get-OERStructureSchemaJson.Tests.ps1`
and by the cohort test in `Resolve-OERStructureEnumCasing.Tests.ps1`; `rationale.md` and
`CHANGELOG.md` by `dochygiene.tests.ps1` and the changelog gates of `module.tests.ps1`.

**Expect:** the branch's gate run green with 0 failures.

Result: 2026-10-09 11:38 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (class B, round 1). The help of Resolve-OERAccessReviewChange, Sync-OERStructureAccessReview and Get-OERInventory (A19), the step's cadence help, the schema enum, the prompt template list, the rationale section access-review-cadence (A19, the measured Graph v1.0 write limits, the dayOfMonth read back as 0) and the [Unreleased] paragraph (405 characters; RawData 1,950) are held by round 1's gate run on 95bca2b (./build.ps1 -Tasks build, then -Tasks test, after -ResolveDependency -UseModuleFast): 8,933 passed, 0 failed, 0 skipped, coverage 94.98% of 18,713 commands -- the module.tests.ps1 help and changelog gates, dochygiene.tests.ps1 and the cohort in Resolve-OERStructureEnumCasing.Tests.ps1.
```

## Teardown

### T.1. Nothing left with the prefix

- [x] **T.1** The prerequisite script's teardown deletes both reviews, the policy, the package and the catalog, and the sweep finds nothing with `oer-s106-`.

```powershell
# Run from the folder that holds the prerequisite script, in its own process:
#   pwsh -NoProfile -File ./Initialize-OerS106Prereq.ps1 -Teardown -WhatIf
#   pwsh -NoProfile -File ./Initialize-OerS106Prereq.ps1 -Teardown -Unattended
#   pwsh -NoProfile -File ./Initialize-OerS106Prereq.ps1 -ReadBack
```

**Expect:** the teardown deletes `oer-s106-review` and `oer-s106-review-doc` first, then the policy,
the package and the catalog; exit code 0; the read-back lists no prefixed object, no unread
collection and no residue row of this prefix, and the counts equal the baseline.

Result: 2026-10-09 10:43 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (round 1). The prerequisite setup created oer-s106-catalog, oer-s106-ap and oer-s106-policy after writing the baseline (catalogs 5, access packages 6, access review definitions 6). The teardown deleted oer-s106-review-doc and oer-s106-review first (each read until gone), then the policy, the package and the catalog (removed 3, residue 0, unreadable 0); the sweep finds nothing with oer-s106-, no access review with the prefix is left, and every count equals the baseline. The read-back agrees. The two residue rows belong to another project's prefix (opim-s1-) and were not touched; Clear-OerLiveResidue was never called. No policy was changed, so nothing needed restoring.

--- Initialize-OerS106Prereq.ps1 -WhatIf (plan; nothing written) ---
[oer-s106] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s106] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s106] oer-live-cc holds AccessReview.Read.All: True
[oer-s106] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s106-' is left.
[oer-s106] Found: oer-s106-catalog exists: False; oer-s106-ap exists: False; oer-s106-policy exists: False; prefixed access reviews: 0.
[oer-s106] No baseline yet: it is written now, before the first write to the tenant (catalogs 5, access packages 6, access review definitions 6).
What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s106\baseline-s106.json".
What if: Performing the operation "Create a catalog (Graph v1.0 POST entitlementManagement/catalogs: published, not visible to external users)" on target "oer-s106-catalog".
What if: Performing the operation "Create a hidden access package (Graph v1.0 POST entitlementManagement/accessPackages: isHidden, no resource role)" on target "oer-s106-ap".
What if: Performing the operation "Create an assignment policy through which only an administrator assigns (Graph v1.0 POST entitlementManagement/assignmentPolicies: allowedTargetScope notSpecified, no requestor, no approval, no expiration)" on target "oer-s106-policy".
[oer-s106] WhatIf: nothing was created, removed or written.
RUNNER: prereq -WhatIf exit code 0; started 2026-10-09T10:11:31Z; took 7 s.

--- Initialize-OerS106Prereq.ps1 -Unattended (setup) ---
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s106] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s106] No baseline yet: it is written now, before the first write to the tenant (catalogs 5, access packages 6, access review definitions 6).
[oer-s106] Wrote the baseline raw\s106\baseline-s106.json and read it back.
[oer-s106] Created catalog oer-s106-catalog: 201.
[oer-s106] oer-s106-catalog is readable by its id: converged after 1 read(s), 0.2 s.
[oer-s106] Created access package oer-s106-ap: 201 after 1 attempt(s).
[oer-s106] oer-s106-ap is readable by its id: converged after 1 read(s), 0.1 s.
[oer-s106] Created policy oer-s106-policy: 201 after 1 attempt(s).
[oer-s106] oer-s106-policy is listed on oer-s106-ap: converged after 1 read(s), 0.1 s.
[oer-s106] Summary: oer-s106-catalog present; oer-s106-ap present; oer-s106-policy present; written to the tenant: True.
RUNNER: prereq -Unattended exit code 0; started 2026-10-09T10:11:45Z; took 8 s.


--- Initialize-OerS106Prereq.ps1 -Teardown -WhatIf ---
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s106\teardown-20261009-104235Z.log".
[oer-s106] Mode: REMOVE. Prefix 'oer-s106-'. Objects (fixed): oer-s106-catalog (catalog, no resource); oer-s106-ap (hidden access package, no resource role); oer-s106-policy (administrator assignments only). The checklist's access reviews: oer-s106-review, oer-s106-review-doc. OerLive 1.0.3.
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s106] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s106] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s106] oer-live-cc holds AccessReview.Read.All: True
What if: Performing the operation "Delete the access review definition (Graph v1.0 DELETE accessReviews/definitions)" on target "oer-s106-review-doc".
What if: Performing the operation "Delete the access review definition (Graph v1.0 DELETE accessReviews/definitions)" on target "oer-s106-review".
[oer-s106] Teardown of 'oer-s106-': users 0, groups 0, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s106] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s106] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s106] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
What if: Performing the operation "Delete (Graph v1.0 DELETE assignmentPolicies)" on target "oer-s106-ap: assignment policy 'oer-s106-policy'".
What if: Performing the operation "Delete the access package (Graph v1.0 DELETE accessPackages)" on target "oer-s106-ap".
What if: Performing the operation "Delete the catalog (Graph v1.0 DELETE catalogs)" on target "oer-s106-catalog".
[oer-s106] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s106] Teardown 5/6: the prefixed groups.
[oer-s106] Teardown 6/6: the prefixed users.
[oer-s106] Teardown of 'oer-s106-': removed 0, residue 0, unreadable 0 (WhatIf: nothing was removed).
[oer-s106] WhatIf: nothing was created, removed or written.
[oer-s106] Done.
RUNNER: prereq -Teardown -WhatIf exit code 0; started 2026-10-09T10:42:33Z; took 7 s.

--- Initialize-OerS106Prereq.ps1 -Teardown -Unattended ---
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s106] Transcript (redacted): raw\s106\teardown-20261009-104250Z.log; OerLive 1.0.3.
[oer-s106] Mode: REMOVE. Prefix 'oer-s106-'. Objects (fixed): oer-s106-catalog (catalog, no resource); oer-s106-ap (hidden access package, no resource role); oer-s106-policy (administrator assignments only). The checklist's access reviews: oer-s106-review, oer-s106-review-doc. OerLive 1.0.3.
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s106] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s106] oer-live-cc holds AccessReview.ReadWrite.All: True
[oer-s106] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s106] oer-live-cc holds AccessReview.Read.All: True
[oer-s106] oer-s106-review-doc is gone: converged after 1 read(s), 0.4 s.
[oer-s106] Teardown A: deleted access review oer-s106-review-doc.
[oer-s106] oer-s106-review is gone: converged after 1 read(s), 0.2 s.
[oer-s106] Teardown A: deleted access review oer-s106-review.
[oer-s106] Teardown of 'oer-s106-': users 0, groups 0, access packages 1, catalogs 1; administrative units 0 and app registrations 0 are reported only.
[oer-s106] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s106] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s106] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s106] Deleted: oer-s106-ap: assignment policy 'oer-s106-policy' (204).
[oer-s106] Deleted: access package oer-s106-ap (204, 1 attempt(s)).
[oer-s106] Deleted: catalog oer-s106-catalog (204, 1 attempt(s)).
[oer-s106] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s106] Teardown 5/6: the prefixed groups.
[oer-s106] Teardown 6/6: the prefixed users.
[oer-s106] Teardown of 'oer-s106-': removed 3, residue 0, unreadable 0.
[oer-s106] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s106-' is left.
[oer-s106] Access reviews with the prefix after the teardown: 0
[oer-s106] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s106] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s106] Counts: accessReviewDefinitions now 6, at the baseline 6; equal: True
[oer-s106] Done.
RUNNER: prereq -Teardown -Unattended exit code 0; started 2026-10-09T10:42:49Z; took 11 s.

--- Initialize-OerS106Prereq.ps1 -ReadBack ---
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s106] Transcript (redacted): raw\s106\readback-20261009-104310Z.log; OerLive 1.0.3.
[oer-s106] Mode: READ BACK. Prefix 'oer-s106-'. Objects (fixed): oer-s106-catalog (catalog, no resource); oer-s106-ap (hidden access package, no resource role); oer-s106-policy (administrator assignments only). The checklist's access reviews: oer-s106-review, oer-s106-review-doc. OerLive 1.0.3.
[oer-s106] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg6-r1\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s106] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s106] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s106] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s106-' is left.
[oer-s106] Read-back: access reviews with the prefix: 0
[oer-s106] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s106] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s106] Counts: accessReviewDefinitions now 6, at the baseline 6; equal: True
[oer-s106] Read-back: residue row: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:09Z, attempts 3: 404 SubjectNotFound The subject is not found.; read back: still listed -- OerLive: Residue: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal': read back after the 'does not exist' answer -- not converged within budget (180 s, 10 reads).
[oer-s106] Read-back: residue row: PIM for Groups assignment 'opim-s1-grp: PIM for Groups owner assignment of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:12Z, attempts 3: 403 UnauthorizedAccessException {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup,PrivilegedAccess.ReadWrite.AzureADGroup,PrivilegedAssignmentSchedule.Remove.AzureADGroup.","instanceAnnotations":[]}
[oer-s106] Read-back: prefixed objects left: 0; unread collections: 0; access reviews with the prefix: 0; residue rows: 2, of them with this step's prefix: 0.
[oer-s106] Done.
RUNNER: prereq -ReadBack exit code 0; started 2026-10-09T10:43:09Z; took 7 s.
```
