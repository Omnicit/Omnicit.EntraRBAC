# Live verification checklist -- the plan and a direct -WhatIf show what a real run warns about (fix/show-warnings-before-the-confirmation-gate)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant.** The prerequisite script creates a disabled user
`oer-s96-user`, a plain security group `oer-s96-pim` whose one member is that user, and an
administrative unit `oer-s96-au` with no member. Before its first write it records baselines: the
tenant's user, group and administrative-unit counts with the low-risk directory role the checklist
uses, the PIM policy of both low-risk directory roles (Message Center Reader and Reports Reader), and
the member PIM policy of `oer-s96-pim`. It then brings that member policy to the starting state:
multi-factor authentication on activation, the authentication context off, and eligible assignments
that must expire. Section 1 first requires MFA on activation for the chosen low-risk directory role
when neither role carries a pair to reconcile (1.0), then applies one document to `oer-s96-pim` and
to that role: an authentication context on both policies, which clears MFA, and a PERMANENT member
eligibility of `oer-s96-user`, which opens the group's policy for permanent eligibility. Section 2
writes nothing. Section 3 creates the group `oer-s96-new` INTO `oer-s96-au` with `Invoke-OERStructure
-Prune`. The teardown puts the directory role policy back to its baseline, removes the eligibility,
puts the group's member policy back, removes every prefixed object through OerLive's fixed order and
deletes `oer-s96-au`. No other directory role policy, and no Azure resource, is touched.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 as
`oer-live-cc` is a stop. Neither `oer-live-cc` nor `oer-live-cc-noperm` is ever a principal here.

**Sign-ins.** Every block's FIRST sign-in goes through `Connect-OerLive -Arm`, which runs
`Disconnect-OER` and `Disconnect-MgGraph` first and then checks the identity as True/False.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s96/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line and a warning go straight to
the host and cannot be redirected inside one process, so this file never reads them from a stream:
`Invoke-S96Captured` (H.1) records the host's own output in a transcript under `raw\s96\`, reads the
order of the warning and the `What if:` line from it, prints the lines redacted and deletes the
transcript. Each block is meant to run in its own process whose whole output is redacted before it
is read.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-18: sixteen cmdlets write their warning before their own confirmation** ("show destructive
  warnings before the confirmation prompt"). A warning about a deletion or widened access used to be
  written inside the `ShouldProcess` gate of sixteen cmdlets, so `-WhatIf` never showed it and a
  `-Confirm` prompt asked before it appeared. It now stands before the gate in all of them, among them
  `Remove-OERGroupEligibility`, `Set-OERAdministrativeUnit` and
  `Remove-OERActiveDirectoryRoleAssignment`. `tests/Unit/Public/WarningBeforeConfirmation.Cohort.Tests.ps1`
  holds the rule for every public cmdlet. `Remove-OERActiveDirectoryRoleAssignment` and its eligible
  twin keep refusing a piped `Get-OERGroupMember` row with `NotDirectAssignment`, with a message that
  now says what was piped.
- **B. BL-17: the apply engine's plan shows the warning a real run gives** ("show the warning a real
  run gives in the apply engine's plan", and two follow-ups). Under `-WhatIf` the engine never calls
  the cmdlets, so their warnings never reached the plan. A handler now writes the same warning before
  its own gate under `-WhatIf`: a changed administrative-unit membership type, a removed ABAC
  condition, a PIM-for-Groups policy opened for permanent eligibility, and a directory role policy
  whose MFA / authentication context pair is reconciled. For group PIM the reconciled pair is warned
  about in a real run too, since the cmdlet, given the reconciled values, never warns.
- **C. BL-07: a membership the same run created is not pruned** ("keep the unit membership a run
  creates for a group through its own prune", "check a template group's unit placement and a unit
  named by id offline"). `New-OERGroup -AdministrativeUnit` creates a new group into its unit, and the
  administrativeUnits section, dispatched after the groups, used to remove that membership under
  `-Prune` in the same run when the unit's `members` did not name the group. The engine now withholds
  that removal (`Skipped`, "prune withheld"); `Test-OERStructure` checks the placement for a
  template-named group and a unit named by id, and no longer warns falsely for a member named by
  object id.

A live tenant is needed for what the unit tests stub: the real order of the warning and the
`What if:` line on the host (sections 1 and 2); that the handler's warning and the cmdlet's are the
same text and a real run writes each once (1.1, 1.2); that a second run converges (1.3, G8); and
that the membership a real create puts into the unit survives the same run's `-Prune` and the
replication after it (3.2, 3.3).

## What this file does not check, and why

- **The Azure Resource Manager cmdlets of BL-18 and engine case 2 (class B, G9):**
  `Remove-OERRoleAssignment`, `Set-OERRoleAssignment` (the ABAC condition), `Remove-OERActiveRoleAssignment`,
  `Remove-OEREligibleRoleAssignment`, `Disable-OEREligibleRoleAssignment`, `Remove-OERResourceGroup`,
  and the engine's ABAC warning. They move the same statement as the Graph cmdlets checked live. Proved
  offline in `tests/Unit/Public/WarningBeforeConfirmation.Cohort.Tests.ps1` (part C: the warning before
  the `What if:` line and before the prompt, with no write, per cmdlet) and in
  `tests/Unit/Private/Sync-OERStructureRoleAssignment.Tests.ps1` (the plan writes it once, a real run
  through the real `Set-OERRoleAssignment` once).
- **An interactive `-Confirm` prompt (class B, G9).** Answering a prompt needs a person; the identity is
  app-only and every run here is unattended. Proved offline in the answering runspace of
  `tests/Unit/TestHelpers/OERConfirmHost.ps1`, which now records the order of warnings, prompts and
  `What if:` lines: the cohort's part C declines each of the seventeen moved warnings' prompts and
  checks that the warning came first.
- **The remaining Graph cmdlets of BL-18 (class B):** the access review, access package, catalog and
  scoped-role cmdlets. Same statement, same cohort test.
- **Engine case 1 in a real run (class B).** Converting `oer-s96-au` to dynamic would take it out of
  section 3; 1.4 shows the plan live, and
  `tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1` proves the real run through the
  real `Set-OERAdministrativeUnit` warns once.
- **Convergence (G8) for document P (section 3).** Its second apply removes the membership on purpose:
  that is the documented behaviour (3.4 shows the plan), not a convergence failure. G8 applies to the
  section 1 document (1.3).

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it.
- The **prerequisite script** `Initialize-OerS96Prereq.ps1` beside OerLive (outside the repository).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 and T.1 read that it was not).

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fence, the
capture and the documents. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s96-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s96'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
$UserUpn = "oer-s96-user@$($Cfg.UserDomain)"
$S96Base = Read-OerLiveBaseline -Name 'baseline-s96'
$Role = if ($S96Base) { [string]$S96Base['directoryRole'] } else { '' }
$RoleForm = if ($S96Base) { [string]$S96Base['directoryRoleForm'] } else { '' }

function Start-S96Fence {
    # Counts every Graph request the module sends that is not a read, through a global proxy of
    # Invoke-MgGraphRequest: the module's transport calls it unqualified, so the proxy is what it reaches.
    $global:S96Writes = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$M = if (`$PSBoundParameters.ContainsKey('Method')) { ([string]`$Method).ToUpperInvariant() } else { 'GET' }; if (`$M -ne 'GET') { `$global:S96Writes.Add(`$M) }; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
}

function Start-S96NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in
    # (it happened once in this file's first run of 0.4, when the block signed in Graph only): refuse it
    # instead of opening a prompt. A global proxy of Get-AzToken, which the module calls unqualified,
    # forwards only a request that carries -ClientCertificate.
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S96 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}
function Stop-S96Fence {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    if (Test-Path -Path function:Invoke-MgGraphRequest) { Remove-Item -Path function:Invoke-MgGraphRequest }
}

function Invoke-S96Captured {
    # Runs a call with the host's own output recorded in a transcript: a warning and a What if line go to
    # the host in the order they are written, which no stream redirection keeps. Returns the transcript's
    # lines between the markers, the output objects and the error records; the transcript file is deleted.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$Call)
    $File = Join-Path $Raw ('cap-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $Items = @()
    Start-Transcript -LiteralPath $File -UseMinimalHeader | Out-Null
    try {
        Write-Host "### BEGIN $Label"
        $Items = @(& $Call 2>&1)
        Write-Host "### END $Label"
    } finally {
        Stop-Transcript | Out-Null
    }
    $All = [System.IO.File]::ReadAllLines($File)
    [System.IO.File]::Delete($File)
    $From = [array]::IndexOf($All, "### BEGIN $Label")
    $To = [array]::IndexOf($All, "### END $Label")
    [PSCustomObject]@{
        Lines  = @(if ($From -ge 0 -and $To -gt ($From + 1)) { $All[($From + 1)..($To - 1)] | Where-Object { $_ -ne '' } })
        Output = @($Items | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        Errors = @($Items | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    }
}

function Get-S96LineIndex {
    # The index of the first captured line that starts with the given prefix and contains the text, or -1.
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Lines, [Parameter(Mandatory)][string]$Prefix, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    for ($I = 0; $I -lt $Lines.Count; $I++) { if ($Lines[$I].StartsWith($Prefix, [System.StringComparison]::Ordinal) -and $Lines[$I].Contains($Text)) { return $I } }
    -1
}

function Write-S96Capture {
    # Prints every captured line, the rows and the errors, redacted (Write-OerLiveStep redacts).
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Capture)
    foreach ($L in $Capture.Lines) { Write-OerLiveStep "$Label host: $L" }
    foreach ($O in $Capture.Output) {
        if ($O.PSObject.Properties['Action']) { Write-OerLiveStep "$Label row: $($O.Section) | $($O.Item) | $($O.Action) | $($O.Detail)" }
        else { Write-OerLiveStep "$Label object: $($O.PSObject.TypeNames[0])" }
    }
    foreach ($E in $Capture.Errors) {
        $Msg = [string]$E.Exception.Message
        if ($Msg.Length -gt 300) { $Msg = $Msg.Substring(0, 300) + ' ...' }
        Write-OerLiveStep "$Label error: $(([string]$E.FullyQualifiedErrorId -split ',')[0]) ($($E.CategoryInfo.Category)): $Msg"
    }
}

function Get-S96ContextId {
    # The first published authentication context, by claim value (only the claim value is ever printed).
    @(Get-OERAuthenticationContext -Available -ErrorAction Stop | ForEach-Object { [string]$_.AuthenticationContextId } | Sort-Object { [int]($_ -replace '^c', '') })[0]
}

function Get-S96DocumentW {
    # Section 1's document: an authentication context on oer-s96-pim's member policy, a permanent member
    # eligibility of oer-s96-user, and the chosen low-risk directory role's policy change.
    param([Parameter(Mandatory)][string]$ContextId)
    $Doc = [ordered]@{
        version = '1.0'
        groups  = @([ordered]@{
                displayName = 'oer-s96-pim'
                pimPolicy   = [ordered]@{ member = [ordered]@{ authenticationContextId = $ContextId } }
                eligibility = @([ordered]@{ principal = $UserUpn; accessType = 'member' })
            })
    }
    # 'setMfaFirst' is 'clearMfa' once 1.0 has required MFA on activation for the role.
    if ($RoleForm -in @('clearMfa', 'setMfaFirst')) { $Doc.directoryRoleManagementPolicies = @([ordered]@{ role = $Role; authenticationContextId = $ContextId }) }
    elseif ($RoleForm -eq 'disableContext') { $Doc.directoryRoleManagementPolicies = @([ordered]@{ role = $Role; requireMfaOnActivation = $true }) }
    $Doc | ConvertTo-Json -Depth 10
}

function Get-S96DocumentP {
    # Section 3's document: a new group created INTO oer-s96-au, whose members do not name it.
    [ordered]@{
        version             = '1.0'
        groups              = @([ordered]@{ displayName = 'oer-s96-new'; administrativeUnit = 'oer-s96-au'; members = @(); owners = @() })
        administrativeUnits = @([ordered]@{ displayName = 'oer-s96-au'; members = @(); scopedRoles = @() })
    } | ConvertTo-Json -Depth 10
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
$WarnAt = @(Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'Write-Warning "Deleting catalog')[0].LineNumber
$GateAt = @(Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'ShouldProcess($CatalogId, ''Delete entitlement management catalog'')')[0].LineNumber
$B = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'ConflictReason' -Quiet)
$C = [bool](Select-String -LiteralPath $Psm1.FullName -SimpleMatch 'which this run created into this unit' -Quiet)
Write-OerLiveStep "The worktree's build carries A: $($WarnAt -gt 0 -and $GateAt -gt $WarnAt); B: $B; C: $C"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main` (its HEAD recorded, and read again in T.1); the worktree at this branch's head with 0 tracked
changes; `The worktree's build carries A: True; B: True; C: True` (A: `Remove-OERCatalog`'s warning
stands before its gate in the build).
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 2026-10-07 13:5x UTC. The session's Repo is the step's own worktree, not the main clone; the main clone is on main at 6817b33, never switched; the worktree on this branch at b6ee101 with 0 tracked changes (the build is of 7ae5a98's source; every later commit changes only Markdown); the build carries A (Remove-OERCatalog's warning stands before its gate: True), B (ConflictReason: True) and C (the fifth withheld kind: True).

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s96] The module loads from a worktree that is not the main clone: True
[oer-s96] Main clone: branch main; HEAD 6817b33
[oer-s96] Worktree: branch fix/show-warnings-before-the-confirmation-gate; HEAD b6ee101 docs: add the live checklist for warnings before the confirmation gate; tracked changes: 0
[oer-s96] The worktree's build carries A: True; B: True; C: True
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, on the second run. Every identity line True for the module session as oer-live-cc (app-only certificate session, app name, test tenant, the service principal and the token's signed-in object, organization, verified domain, ARM token from the certificate, test subscription Enabled); identity check passed; the module is the worktree's build. The first run signed in with Connect-OerLive -Graph, which passes the same identity check for the Graph SDK session but does not sign the MODULE in; that is what made 0.4's first run fall back to an interactive sign-in (see 0.4). Every block now signs in with -Arm and installs the no-prompt fence.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s96] The module is the worktree's build: True
```

### 0.2. The prerequisite plan names only oer-s96- objects

- [x] **0.2** `Initialize-OerS96Prereq.ps1 -WhatIf` signs in, passes the identity check, writes nothing, and every tenant `What if:` target starts with `oer-s96-`.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96Prereq.ps1') -WhatIf 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
$Plan = @($Out | Where-Object { $_ -match 'What if: Performing the operation' })
$Targets = @($Plan | ForEach-Object { if ($_ -match 'on target "([^"]+)"') { $Matches[1] } })
# The script's own files (transcript, baselines) go to raw\s96\ in the clone; every other target is in the tenant.
$Local = @($Targets | Where-Object { $_.StartsWith('raw\s96\') })
$Tenant = @($Targets | Where-Object { -not $_.StartsWith('raw\s96\') })
Write-OerLiveStep "Planned writes: $($Plan.Count); local files under raw\s96\: $($Local.Count); tenant targets: $($Tenant.Count); every tenant target starts with oer-s96-: $(@($Tenant | Where-Object { -not $_.StartsWith('oer-s96-') }).Count -eq 0)"
```

**Expect:** the identity lines `True`; `WhatIf: nothing was created, removed or written.`; the
script's own local files under `raw\s96\` (the transcript and, on a first run, the count baseline and
the two directory role policy baselines); each low-risk directory role's MFA and authentication
context state, and the role and form the checklist will use; the tenant targets `oer-s96-user`,
`oer-s96-pim`, `oer-s96-pim: member oer-s96-user` and `oer-s96-au`, every one starting with
`oer-s96-` (`True`); a "No member-policy baseline" line, since under `-WhatIf` the group does not
exist yet.
**Failure looks like:** a target without the prefix -- STOP; any `Refusing to run` -- read the reason
before anything else is run; no role with a form -- the directory role part of section 1 is class B.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, on the second run (the first was identical except that it found no role with a form; the prereq then gained the form setMfaFirst). Identity check passed; no residue; the sweep finds nothing with the prefix; no baseline yet. Message Center Reader and Reports Reader both have MFA on activation False and the authentication context off, so the checklist uses Message Center Reader in the form setMfaFirst (1.0 requires MFA first). The plan: 4 local files under raw\s96\ (the transcript and three baselines) and 4 tenant targets, oer-s96-user, oer-s96-pim, oer-s96-pim: member oer-s96-user and oer-s96-au, every one with the prefix (True); WhatIf: nothing was created or written. Read and confirmed by the controller before 0.3.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s96] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s96] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s96] What if: Performing the operation "Start the redacted transcript" on target "raw\s96\prereq-20261007-140024Z.log".
[oer-s96] [oer-s96] Mode: CREATE or complete. Prefix 'oer-s96-'. Objects (fixed): oer-s96-user (disabled); oer-s96-pim (its one member oer-s96-user, its member PIM policy baselined and set to the starting state); oer-s96-au (assigned, no member); oer-s96-new is the checklist's own. The low-risk directory roles' policies are baselined. OerLive 1.0.3.
[oer-s96] [oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s96] [oer-s96] Residue: raw\residue.json holds no rows.
[oer-s96] [oer-s96] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s96-' is left.
[oer-s96] [oer-s96] Found: oer-s96-user exists: False; oer-s96-pim exists: False; oer-s96-au exists: False; oer-s96-new exists: False.
[oer-s96] [oer-s96] Directory role 'Message Center Reader': MFA on activation: False; authentication context enabled: False; form: none.
[oer-s96] [oer-s96] Directory role 'Reports Reader': MFA on activation: False; authentication context enabled: False; form: none.
[oer-s96] [oer-s96] No baseline yet: it is written now, before the first write to the tenant (users 23, groups 98, administrative units 1; the checklist's directory role: 'Message Center Reader', form setMfaFirst).
[oer-s96] What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s96\baseline-s96.json".
[oer-s96] [oer-s96] The policy baseline of 'Message Center Reader' is written now (rules 17).
[oer-s96] What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s96\baseline-s96-dirrole-mcr.json".
[oer-s96] [oer-s96] The policy baseline of 'Reports Reader' is written now (rules 17).
[oer-s96] What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s96\baseline-s96-dirrole-rr.json".
[oer-s96] What if: Performing the operation "Create a DISABLED test user with a random, unprinted password (Graph v1.0 POST users)" on target "oer-s96-user".
[oer-s96] What if: Performing the operation "Create a plain security group (Graph v1.0 POST groups: not role-assignable, not mail-enabled, assigned membership)" on target "oer-s96-pim".
[oer-s96] What if: Performing the operation "Add the user as a member of the group (Graph v1.0 POST groups/members/$ref)" on target "oer-s96-pim: member oer-s96-user".
[oer-s96] What if: Performing the operation "Create an administrative unit (Graph v1.0 POST directory/administrativeUnits: assigned, public, not restricted)" on target "oer-s96-au".
[oer-s96] [oer-s96] No member-policy baseline and no starting state: oer-s96-pim does not exist (WhatIf).
[oer-s96] [oer-s96] Summary: oer-s96-user absent; oer-s96-pim absent; oer-s96-au absent; oer-s96-new absent (the checklist creates it); written to the tenant: False (WhatIf: nothing was created or written).
[oer-s96] [oer-s96] WhatIf: nothing was created, removed or written.
[oer-s96] [oer-s96] Done.
[oer-s96] Planned writes: 8; local files under raw\s96\: 4; tenant targets: 4; every tenant target starts with oer-s96-: True
```

### 0.3. The prerequisite objects, the baselines and the starting state

- [x] **0.3** `Initialize-OerS96Prereq.ps1 -Unattended` writes the baselines, creates the user, the group with its one member and the unit, records the group's member-policy baseline and brings that policy to the starting state.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96Prereq.ps1') -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Setup exit code: $Code"
```

**Expect:** the identity lines `True`; the baselines written before the first write to the tenant;
`Created user oer-s96-user (disabled)`, `Created group oer-s96-pim`, `Added oer-s96-user to
oer-s96-pim`, `Created administrative unit oer-s96-au`; the member-policy baseline line and either
`already at the checklist's starting state` or the rules sent and `Member policy of oer-s96-pim at the
starting state: True ... MFA on activation: True; ... authentication context: none; eligible
assignments must expire: True`; exit code 0.
**Failure looks like:** exit code 1 -- read the `Stopped` lines; nothing outside the prefix was
written, and `-Teardown` removes what was.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The baselines were written before the first write to the tenant (users 23, groups 98, administrative units 1; Message Center Reader, form setMfaFirst; both role policies, 17 rules each). Created oer-s96-user (disabled, 201), oer-s96-pim (201), added the user as its member (204), created oer-s96-au (201). The group's member-policy baseline: MFA on activation False, Justification, no context, eligible assignments must expire True; the script sent Enablement_EndUser_Assignment (200) and the policy read at the starting state after 1 read (MFA True, no context, must expire True). Exit code 0.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s96] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s96] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s96] [oer-s96] Transcript (redacted): raw\s96\prereq-20261007-140041Z.log; OerLive 1.0.3.
[oer-s96] [oer-s96] Mode: CREATE or complete. Prefix 'oer-s96-'. Objects (fixed): oer-s96-user (disabled); oer-s96-pim (its one member oer-s96-user, its member PIM policy baselined and set to the starting state); oer-s96-au (assigned, no member); oer-s96-new is the checklist's own. The low-risk directory roles' policies are baselined. OerLive 1.0.3.
[oer-s96] [oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s96] [oer-s96] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s96] [oer-s96] Residue: raw\residue.json holds no rows.
[oer-s96] [oer-s96] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s96-' is left.
[oer-s96] [oer-s96] Found: oer-s96-user exists: False; oer-s96-pim exists: False; oer-s96-au exists: False; oer-s96-new exists: False.
[oer-s96] [oer-s96] Directory role 'Message Center Reader': MFA on activation: False; authentication context enabled: False; form: none.
[oer-s96] [oer-s96] Directory role 'Reports Reader': MFA on activation: False; authentication context enabled: False; form: none.
[oer-s96] [oer-s96] No baseline yet: it is written now, before the first write to the tenant (users 23, groups 98, administrative units 1; the checklist's directory role: 'Message Center Reader', form setMfaFirst).
[oer-s96] [oer-s96] Wrote the baseline raw\s96\baseline-s96.json and read it back.
[oer-s96] [oer-s96] The policy baseline of 'Message Center Reader' is written now (rules 17).
[oer-s96] [oer-s96] Wrote the baseline raw\s96\baseline-s96-dirrole-mcr.json and read it back.
[oer-s96] [oer-s96] The policy baseline of 'Reports Reader' is written now (rules 17).
[oer-s96] [oer-s96] Wrote the baseline raw\s96\baseline-s96-dirrole-rr.json and read it back.
[oer-s96] [oer-s96] Created user oer-s96-user (disabled): 201.
[oer-s96] [oer-s96] oer-s96-user resolves by its user principal name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s96] [oer-s96] oer-s96-user resolves by its user principal name: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s96] [oer-s96] oer-s96-user resolves by its user principal name: converged after 3 read(s), 6.2 s.
[oer-s96] [oer-s96] Created group oer-s96-pim: 201.
[oer-s96] [oer-s96] oer-s96-pim resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s96] [oer-s96] oer-s96-pim resolves by its display name: not yet (read 2, 2.1 s, likely replication delay) -- reading again in 4 s.
[oer-s96] [oer-s96] oer-s96-pim resolves by its display name: not yet (read 3, 6.2 s, likely replication delay) -- reading again in 8 s.
[oer-s96] [oer-s96] oer-s96-pim resolves by its display name: converged after 4 read(s), 14.3 s.
[oer-s96] [oer-s96] Added oer-s96-user to oer-s96-pim: 204 after 1 attempt(s).
[oer-s96] [oer-s96] oer-s96-pim lists oer-s96-user as a member: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s96] [oer-s96] oer-s96-pim lists oer-s96-user as a member: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s96] [oer-s96] oer-s96-pim lists oer-s96-user as a member: not yet (read 3, 6.4 s, likely replication delay) -- reading again in 8 s.
[oer-s96] [oer-s96] oer-s96-pim lists oer-s96-user as a member: converged after 4 read(s), 14.5 s.
[oer-s96] [oer-s96] Created administrative unit oer-s96-au: 201.
[oer-s96] [oer-s96] oer-s96-au is readable by its id: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s96] [oer-s96] oer-s96-au is readable by its id: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s96] [oer-s96] oer-s96-au is readable by its id: converged after 3 read(s), 6.2 s.
[oer-s96] [oer-s96] oer-s96-pim's member PIM policy is listed: converged after 1 read(s), 0.4 s.
[oer-s96] [oer-s96] Member policy of oer-s96-pim (baseline): MFA on activation: False; other enablement flags: Justification; authentication context: none; eligible assignments must expire: True
[oer-s96] [oer-s96] Wrote the baseline raw\s96\baseline-s96-grppolicy.json and read it back.
[oer-s96] [oer-s96] Sent rule Enablement_EndUser_Assignment of oer-s96-pim's member policy: 200.
[oer-s96] [oer-s96] oer-s96-pim's member PIM policy is listed: converged after 1 read(s), 0.4 s.
[oer-s96] [oer-s96] oer-s96-pim's member policy at the starting state: converged after 1 read(s), 2.3 s.
[oer-s96] [oer-s96] Member policy of oer-s96-pim at the starting state: True (1 read(s), 2.3 s); MFA on activation: True; other enablement flags: Justification; authentication context: none; eligible assignments must expire: True
[oer-s96] [oer-s96] Summary: oer-s96-user present; oer-s96-pim present; oer-s96-au present; oer-s96-new absent (the checklist creates it); written to the tenant: True.
[oer-s96] [oer-s96] Done.
[oer-s96] Setup exit code: 0
```

### 0.4. The starting state as the module reads it, and the authentication context

- [x] **0.4** The module reads `oer-s96-pim`'s member policy and the chosen directory role's policy in the starting state, `oer-s96-user` holds no eligibility in the group, and the tenant has a published authentication context.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
$Ctx = Get-S96ContextId
Write-OerLiveStep "Published authentication context used by this file: $Ctx; the chosen directory role: '$Role', form $RoleForm"
$Gp = Get-OERGroupPimPolicy -Group 'oer-s96-pim' -AccessType member -ErrorAction Stop
Write-OerLiveStep "oer-s96-pim member policy: MFA on activation: $(@($Gp.ActivationEnabledRules) -contains 'MultiFactorAuthentication'); authentication context: '$($Gp.AuthenticationContextId)'; permanent eligibility allowed: $($Gp.AllowPermanentEligibility)"
if ($Role) {
    $Dp = Get-OERDirectoryRoleManagementPolicy -Role $Role -ErrorAction Stop
    Write-OerLiveStep "'$Role' policy: MFA on activation: $($Dp.RequireMfaOnActivation); authentication context: '$($Dp.AuthenticationContextId)'"
}
$El = @(Get-OERGroupEligibility -Group 'oer-s96-pim' -ErrorAction Stop | Where-Object { $null -ne $_ })
Write-OerLiveStep "Eligibility schedules in oer-s96-pim: $($El.Count)"
Disconnect-OerLive
```

**Expect:** a published context (`c` and a number); `oer-s96-pim member policy: MFA on activation:
True; authentication context: ''; permanent eligibility allowed: False`; for the form `clearMfa`,
`'<role>' policy: MFA on activation: True; authentication context: ''` (for `disableContext`, a
context in place; for `setMfaFirst`, MFA `False` and no context, which 1.0 changes);
`Eligibility schedules in oer-s96-pim: 0`.
**Failure looks like:** no published context -- the authentication-context halves of section 1 are
class B; a different starting state -- re-run 0.3, or read the prereq's lines.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, on the third run. INCIDENT on the first run: the block signed in with Connect-OerLive -Graph (the Graph SDK only), so Get-OERAuthenticationContext's Initialize-OERAuth found no module session and fell back to an interactive Get-AzToken, which timed out after 120 s; nothing authenticated and nothing was written. The checklist was corrected (Connect-OerLive -Arm and a fence that refuses any token request without the certificate). The second run read an empty context id (the helper read Id; the property is AuthenticationContextId), also corrected. Third run: the published context c1; oer-s96-pim's member policy MFA True, no context, permanent eligibility not allowed; Message Center Reader MFA False and no context (form setMfaFirst, which 1.0 changes); no eligibility in oer-s96-pim.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.4 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s96] Published authentication context used by this file: c1; the chosen directory role: 'Message Center Reader', form setMfaFirst
[oer-s96] oer-s96-pim member policy: MFA on activation: True; authentication context: ''; permanent eligibility allowed: False
[oer-s96] 'Message Center Reader' policy: MFA on activation: False; authentication context: ''
[oer-s96] Eligibility schedules in oer-s96-pim: 0
```

## 1. BL-17: the plan shows the warnings a real run gives (Invoke-OERStructure)

Document W (H.1) declares an authentication context on `oer-s96-pim`'s member policy, a permanent
member eligibility of `oer-s96-user`, and the chosen directory role's policy change. In the starting
state each of the three gives one warning in a real run: the group's MFA is cleared (written by the
handler, in both modes, ruling R5), the group's policy is opened for permanent eligibility (by
`Add-OERGroupEligibility` in a real run, by the handler under `-WhatIf`), and the directory role's MFA
is cleared (by `Set-OERDirectoryRoleManagementPolicy` in a real run, by the handler under `-WhatIf`).

### 1.0. The directory role's starting state: MFA required on activation

- [x] **1.0** For the form `setMfaFirst` (neither low-risk role carried an MFA / authentication-context pair to reconcile, 0.2), a real run of a one-entry document requiring MFA on activation for the chosen role reports `Updated`, writes no warning, and the role then reads with MFA required; the teardown puts the baseline back. For any other form nothing is written.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
if ($RoleForm -eq 'setMfaFirst') {
    Start-S96Fence
    $D0 = [ordered]@{ version = '1.0'; directoryRoleManagementPolicies = @([ordered]@{ role = $Role; requireMfaOnActivation = $true }) } | ConvertTo-Json -Depth 10
    $Cap = Invoke-S96Captured -Label '1.0' -Call { Invoke-OERStructure -Json $D0 -Confirm:$false }
    Write-S96Capture -Label '1.0' -Capture $Cap
    Write-OerLiveStep "1.0 rows: $(@($Cap.Output | Where-Object { $_.PSObject.Properties['Action'] } | ForEach-Object { $_.Action }) -join ', '); warning lines: $(@($Cap.Lines | Where-Object { $_.StartsWith('WARNING: ', [System.StringComparison]::Ordinal) }).Count); errors: $($Cap.Errors.Count); Graph writes: $($global:S96Writes.Count) ($(@($global:S96Writes) -join ', '))"
    Stop-S96Fence
    $Read = { $P = Get-OERDirectoryRoleManagementPolicy -Role $Role -ErrorAction Stop; "MFA on activation $($P.RequireMfaOnActivation), context '$($P.AuthenticationContextId)'" }
    $Wait = Wait-OerLiveConverged -Activity "'$Role' requires MFA on activation" -Read { & $Read } -Test { $args[0] -eq "MFA on activation True, context ''" }
    $Steady = @(1..3 | ForEach-Object { Start-Sleep -Seconds 5; & $Read })
    Write-OerLiveStep "1.0 '$Role' after $($Wait.Attempts) read(s): $($Wait.Value); three reads 5 s apart agree: $(@($Steady | Select-Object -Unique).Count -eq 1)"
} else {
    Write-OerLiveStep "1.0 form '$RoleForm': nothing to set."
}
Disconnect-OerLive
```

**Expect:** for `setMfaFirst`: `rows: Updated`; `warning lines: 0`; `errors: 0`; one Graph write
(`PATCH`, the activation enablement rule); `MFA on activation True, context ''` and three reads that
agree (`True`).
**Failure looks like:** a warning -- the plan would then not start from a clean pair; a `Failed` row --
read its Detail; a 401/403 -- STOP (the identity holds this permission since Sprint 6).

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. A real run of a one-entry document requiring MFA on activation for Message Center Reader: rows Updated; 0 warning lines; 0 errors; 1 Graph write (PATCH); the role read with MFA on activation True and no context after 1 read, and three reads 5 s apart agree (True).

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.0 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 1.0
### END 1.0
[oer-s96] 1.0 host: ### END 1.0
[oer-s96] 1.0 host: ### BEGIN 1.0
[oer-s96] 1.0 row: directoryRoleManagementPolicies | Message Center Reader | Updated | updated directory role management policy for 'Message Center Reader' (requireMfaOnActivation=True)
[oer-s96] 1.0 rows: Updated; warning lines: 0; errors: 0; Graph writes: 1 (PATCH)
[oer-s96] 'Message Center Reader' requires MFA on activation: converged after 1 read(s), 0.7 s.
[oer-s96] 1.0 'Message Center Reader' after 1 read(s): MFA on activation True, context ''; three reads 5 s apart agree: True
```

### 1.1. -WhatIf: the three warnings, each before its own What if line, and nothing written

- [x] **1.1** `Invoke-OERStructure -Json $W -WhatIf` writes each of the three warnings exactly once and before the `What if:` line of the change it belongs to, reports the three changes `Skipped`, and sends no Graph write.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$Ctx = Get-S96ContextId
$W = Get-S96DocumentW -ContextId $Ctx
$Gp = Get-OERGroupPimPolicy -Group 'oer-s96-pim' -AccessType member -ErrorAction Stop
$Gid = [string]$Gp.GroupId
$WantGrp = "WARNING: Policy '$($Gp.PolicyId)': mfa cleared: mutually exclusive with authenticationContextId=$Ctx"
$WantElig = "WARNING: This eligibility requires opening the PIM-for-groups policy for group '$Gid' (member access) to allow PERMANENT eligible assignments"
$Dp = if ($Role) { Get-OERDirectoryRoleManagementPolicy -Role $Role -ErrorAction Stop }
$WantDir = if ($RoleForm -in @('clearMfa', 'setMfaFirst')) { "WARNING: Policy '$($Dp.PolicyId)': mfa cleared: mutually exclusive with authenticationContextId=$Ctx" } elseif ($RoleForm -eq 'disableContext') { "WARNING: Policy '$($Dp.PolicyId)': authentication context '$($Dp.AuthenticationContextId)' disabled" } else { $null }
$Cap = Invoke-S96Captured -Label '1.1' -Call { Invoke-OERStructure -Json $W -WhatIf }
Write-S96Capture -Label '1.1' -Capture $Cap
$L = $Cap.Lines
$Count = { param($Text) @($L | Where-Object { $_.StartsWith($Text, [System.StringComparison]::Ordinal) }).Count }
$IGrp = Get-S96LineIndex -Lines $L -Prefix $WantGrp -Text ''
$IElig = Get-S96LineIndex -Lines $L -Prefix $WantElig -Text ''
$IDir = if ($WantDir) { Get-S96LineIndex -Lines $L -Prefix $WantDir -Text '' } else { -2 }
$XGrp = Get-S96LineIndex -Lines $L -Prefix 'What if: ' -Text 'Set PIM policy (member)'
$XElig = Get-S96LineIndex -Lines $L -Prefix 'What if: ' -Text 'Add permanent member eligibility'
$XDir = Get-S96LineIndex -Lines $L -Prefix 'What if: ' -Text 'Update directory role management policy'
Write-OerLiveStep "1.1 group MFA warning: count $(& $Count $WantGrp), before its What if line: $($IGrp -ge 0 -and $XGrp -gt $IGrp)"
Write-OerLiveStep "1.1 permanent eligibility warning: count $(& $Count $WantElig), before its What if line: $($IElig -ge 0 -and $XElig -gt $IElig)"
Write-OerLiveStep "1.1 directory role warning: count $(if ($WantDir) { & $Count $WantDir } else { 'n/a' }), before its What if line: $(if ($WantDir) { $IDir -ge 0 -and $XDir -gt $IDir } else { 'n/a (class B)' })"
Write-OerLiveStep "1.1 rows: $(@($Cap.Output | Where-Object { $_.PSObject.Properties['Action'] } | ForEach-Object { $_.Action }) -join ', '); errors: $($Cap.Errors.Count); Graph writes: $($global:S96Writes.Count)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** each of the three warning counts `1` and `before its What if line: True`; the rows only
`Skipped` (and, for an eligibility or member Extra, nothing else written); `errors: 0`; `Graph writes:
0`.
**Failure looks like:** a count of `0` -- the plan does not show what the run warns about (the old
defect); a count of `2` -- the handler and the cmdlet both warned; `before its What if line: False` --
the warning is written after the gate; a Graph write above 0 -- STOP.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, on the second run. In the first run the runner redirected all of the child script's streams (*>), so the three warnings went to the file instead of the host and the transcript could not see their order (their texts were present); the runner now redirects the child process's output, so warnings reach the host. Second run: the group MFA warning, the permanent eligibility warning and the directory role warning each counted 1 and stood before the What if line of their own change (True, True, True); rows Unchanged and Extra (the group's undeclared member, no -Prune) and three Skipped; 0 errors; 0 Graph writes.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 1.1
WARNING: Policy 'Group_00000000-0000-0000-0000-000000000002_00000000-0000-0000-0000-000000000005': mfa cleared: mutually exclusive with authenticationContextId=c1
What if: Performing the operation "Set PIM policy (member): authenticationContextId=c1; activationEnablement=[Justification] (mfa cleared: mutually exclusive with authenticationContextId=c1)" on target "oer-s96-pim".
WARNING: This eligibility requires opening the PIM-for-groups policy for group '00000000-0000-0000-0000-000000000002' (member access) to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.
What if: Performing the operation "Add permanent member eligibility for '00000000-0000-0000-0000-000000000007'" on target "oer-s96-pim".
WARNING: Policy 'DirectoryRole_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009': mfa cleared: mutually exclusive with authenticationContextId=c1
What if: Performing the operation "Update directory role management policy" on target "Message Center Reader".
### END 1.1
[oer-s96] 1.1 host: WARNING: Policy 'Group_00000000-0000-0000-0000-000000000002_00000000-0000-0000-0000-000000000005': mfa cleared: mutually exclusive with authenticationContextId=c1
[oer-s96] 1.1 host: What if: Performing the operation "Set PIM policy (member): authenticationContextId=c1; activationEnablement=[Justification] (mfa cleared: mutually exclusive with authenticationContextId=c1)" on target "oer-s96-pim".
[oer-s96] 1.1 host: WARNING: This eligibility requires opening the PIM-for-groups policy for group '00000000-0000-0000-0000-000000000002' (member access) to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.
[oer-s96] 1.1 host: What if: Performing the operation "Add permanent member eligibility for '00000000-0000-0000-0000-000000000007'" on target "oer-s96-pim".
[oer-s96] 1.1 host: WARNING: Policy 'DirectoryRole_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009': mfa cleared: mutually exclusive with authenticationContextId=c1
[oer-s96] 1.1 host: What if: Performing the operation "Update directory role management policy" on target "Message Center Reader".
[oer-s96] 1.1 row: groups | oer-s96-pim | Unchanged | group properties match
[oer-s96] 1.1 row: groups | oer-s96-pim | Extra | undeclared member '00000000-0000-0000-0000-000000000007' (use -Prune to remove)
[oer-s96] 1.1 row: groups | oer-s96-pim | Skipped | would set pimPolicy (member): authenticationContextId=c1; activationEnablement=[Justification] (mfa cleared: mutually exclusive with authenticationContextId=c1)
[oer-s96] 1.1 row: groups | oer-s96-pim | Skipped | would set permanent member eligibility for 'oer-s96-user@example.com': permanent member eligibility is absent
[oer-s96] 1.1 row: directoryRoleManagementPolicies | Message Center Reader | Skipped | would update directory role management policy for 'Message Center Reader' (authenticationContextId=c1)
[oer-s96] 1.1 group MFA warning: count 1, before its What if line: True
[oer-s96] 1.1 permanent eligibility warning: count 1, before its What if line: True
[oer-s96] 1.1 directory role warning: count 1, before its What if line: True
[oer-s96] 1.1 rows: Unchanged, Extra, Skipped, Skipped, Skipped; errors: 0; Graph writes: 0
```

### 1.2. The same document for real: each warning once, the same texts

- [x] **1.2** `Invoke-OERStructure -Json $W -Confirm:$false` writes each of the three warnings exactly once, with the texts 1.1 planned, reports `Updated` for the group's member policy, the permanent eligibility and the directory role policy, and the policies then read in the new state.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$Ctx = Get-S96ContextId
$W = Get-S96DocumentW -ContextId $Ctx
$Gp = Get-OERGroupPimPolicy -Group 'oer-s96-pim' -AccessType member -ErrorAction Stop
$Gid = [string]$Gp.GroupId
$WantGrp = "WARNING: Policy '$($Gp.PolicyId)': mfa cleared: mutually exclusive with authenticationContextId=$Ctx"
$WantElig = "WARNING: This eligibility requires opening the PIM-for-groups policy for group '$Gid' (member access) to allow PERMANENT eligible assignments"
$Dp = if ($Role) { Get-OERDirectoryRoleManagementPolicy -Role $Role -ErrorAction Stop }
$WantDir = if ($RoleForm -in @('clearMfa', 'setMfaFirst')) { "WARNING: Policy '$($Dp.PolicyId)': mfa cleared: mutually exclusive with authenticationContextId=$Ctx" } elseif ($RoleForm -eq 'disableContext') { "WARNING: Policy '$($Dp.PolicyId)': authentication context '$($Dp.AuthenticationContextId)' disabled" } else { $null }
$Cap = Invoke-S96Captured -Label '1.2' -Call { Invoke-OERStructure -Json $W -Confirm:$false }
Write-S96Capture -Label '1.2' -Capture $Cap
$L = $Cap.Lines
$Count = { param($Text) @($L | Where-Object { $_.StartsWith($Text, [System.StringComparison]::Ordinal) }).Count }
Write-OerLiveStep "1.2 group MFA warning: count $(& $Count $WantGrp); permanent eligibility warning: count $(& $Count $WantElig); directory role warning: count $(if ($WantDir) { & $Count $WantDir } else { 'n/a' }); warning lines in all: $(@($L | Where-Object { $_.StartsWith('WARNING: ', [System.StringComparison]::Ordinal) }).Count)"
Write-OerLiveStep "1.2 rows: $(@($Cap.Output | Where-Object { $_.PSObject.Properties['Action'] } | ForEach-Object { $_.Action }) -join ', '); errors: $($Cap.Errors.Count); Graph writes: $($global:S96Writes.Count) ($(@($global:S96Writes) -join ', '))"
Stop-S96Fence
# G8 waits for a state that reads the same three times, 5 s apart (Sprint 9 step 2): the eligibility and both policies.
$UserId = [string](Invoke-OerLiveGraph -Uri "v1.0/users/$([uri]::EscapeDataString($UserUpn))?`$select=id").Body['id']
$State = { 
    $G = Get-OERGroupPimPolicy -Group 'oer-s96-pim' -AccessType member -ErrorAction Stop
    $E = @(Get-OERGroupEligibility -Group 'oer-s96-pim' -ErrorAction Stop | Where-Object { $null -ne $_ -and [string]$_.PrincipalId -eq $UserId })
    $D = if ($Role) { Get-OERDirectoryRoleManagementPolicy -Role $Role -ErrorAction Stop }
    "group MFA $(@($G.ActivationEnabledRules) -contains 'MultiFactorAuthentication'), context '$($G.AuthenticationContextId)', permanent allowed $($G.AllowPermanentEligibility); eligibility of oer-s96-user $($E.Count); role MFA $(if ($D) { $D.RequireMfaOnActivation } else { 'n/a' }), context '$(if ($D) { $D.AuthenticationContextId })'"
}
$Wait = Wait-OerLiveConverged -Activity 'the section 1 state reads as applied' -Read { & $State } -Test { $args[0] -like "group MFA False, context '$Ctx', permanent allowed True; eligibility of oer-s96-user 1;*" }
$Steady = @(1..3 | ForEach-Object { Start-Sleep -Seconds 5; & $State })
Write-OerLiveStep "1.2 state after $($Wait.Attempts) read(s): $($Wait.Value)"
Write-OerLiveStep "1.2 three reads 5 s apart agree: $(@($Steady | Select-Object -Unique).Count -eq 1)"
Disconnect-OerLive
```

**Expect:** each of the three counts `1` and `warning lines in all: 3` (a fourth only if a warning
this step does not touch fires, which the result must name); the rows `Updated` for the member policy,
the permanent eligibility and the directory role policy; `errors: 0`; Graph writes for the group's two
rules, the eligibility rule the cmdlet opens, the eligibility request and the directory role's rules;
the state `group MFA False, context '<ctx>', permanent allowed True; eligibility of oer-s96-user 1;
role MFA False, context '<ctx>'` (form `clearMfa`), and three reads that agree (`True`).
**Failure looks like:** a count of `2` -- the run warns twice (the handler did not stay silent beside
the cmdlet); a count of `0` -- the run gives no warning, and the plan in 1.1 showed one it does not
give; any `Failed` row -- read its Detail.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The real run wrote the same three warnings as 1.1, each exactly once (warning lines in all: 3): the group MFA warning from the handler (ruling R5), the permanent eligibility warning from Add-OERGroupEligibility, and the directory role warning from Set-OERDirectoryRoleManagementPolicy. Rows: Unchanged, Extra, and Updated for the member policy, the permanent eligibility and the directory role policy; 0 errors; 6 Graph writes (the group's two rules, the eligibility rule the cmdlet opened, the eligibility request, the role's two rules). The state read as applied after 1 read: group MFA False, context c1, permanent eligibility allowed; oer-s96-user's eligibility 1; Message Center Reader MFA False, context c1; three reads 5 s apart agree.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 1.2
WARNING: Policy 'Group_00000000-0000-0000-0000-000000000002_00000000-0000-0000-0000-000000000005': mfa cleared: mutually exclusive with authenticationContextId=c1
WARNING: This eligibility requires opening the PIM-for-groups policy for group '00000000-0000-0000-0000-000000000002' (member access) to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.
WARNING: Policy 'DirectoryRole_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009': mfa cleared: mutually exclusive with authenticationContextId=c1
### END 1.2
[oer-s96] 1.2 host: WARNING: Policy 'Group_00000000-0000-0000-0000-000000000002_00000000-0000-0000-0000-000000000005': mfa cleared: mutually exclusive with authenticationContextId=c1
[oer-s96] 1.2 host: WARNING: This eligibility requires opening the PIM-for-groups policy for group '00000000-0000-0000-0000-000000000002' (member access) to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.
[oer-s96] 1.2 host: WARNING: Policy 'DirectoryRole_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009': mfa cleared: mutually exclusive with authenticationContextId=c1
[oer-s96] 1.2 row: groups | oer-s96-pim | Unchanged | group properties match
[oer-s96] 1.2 row: groups | oer-s96-pim | Extra | undeclared member '00000000-0000-0000-0000-000000000007' (use -Prune to remove)
[oer-s96] 1.2 row: groups | oer-s96-pim | Updated | pimPolicy (member) set: authenticationContextId=c1; activationEnablement=[Justification] (mfa cleared: mutually exclusive with authenticationContextId=c1)
[oer-s96] 1.2 row: groups | oer-s96-pim | Updated | set permanent member eligibility for 'oer-s96-user@example.com': permanent member eligibility is absent
[oer-s96] 1.2 row: directoryRoleManagementPolicies | Message Center Reader | Updated | updated directory role management policy for 'Message Center Reader' (authenticationContextId=c1)
[oer-s96] 1.2 group MFA warning: count 1; permanent eligibility warning: count 1; directory role warning: count 1; warning lines in all: 3
[oer-s96] 1.2 rows: Unchanged, Extra, Updated, Updated, Updated; errors: 0; Graph writes: 6 (PATCH, PATCH, PATCH, POST, PATCH, PATCH)
[oer-s96] the section 1 state reads as applied: converged after 1 read(s), 1.8 s.
[oer-s96] 1.2 state after 1 read(s): group MFA False, context 'c1', permanent allowed True; eligibility of oer-s96-user 1; role MFA False, context 'c1'
[oer-s96] 1.2 three reads 5 s apart agree: True
```

### 1.3. The same document again: only Unchanged, and no warning (G8)

- [x] **1.3** A second real run of document W reports only `Unchanged`, writes no warning and sends no Graph write.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$W = Get-S96DocumentW -ContextId (Get-S96ContextId)
$Cap = Invoke-S96Captured -Label '1.3' -Call { Invoke-OERStructure -Json $W -Confirm:$false }
Write-S96Capture -Label '1.3' -Capture $Cap
Write-OerLiveStep "1.3 rows: $(@($Cap.Output | Where-Object { $_.PSObject.Properties['Action'] } | ForEach-Object { $_.Action } | Sort-Object -Unique) -join ', '); warning lines: $(@($Cap.Lines | Where-Object { $_.StartsWith('WARNING: ', [System.StringComparison]::Ordinal) }).Count); errors: $($Cap.Errors.Count); Graph writes: $($global:S96Writes.Count)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** `rows: Unchanged` (an `Extra` row for the group's undeclared member is not a change and
may appear: the document declares no members and runs without `-Prune`); `warning lines: 0`; `errors:
0`; `Graph writes: 0`.
**Failure looks like:** an `Updated` row -- the write path does not converge; a warning -- the plan
or the run warns about a change that is not made.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The second real run of document W: rows Unchanged (group, member policy, permanent eligibility, directory role policy) and the group's Extra member; 0 warning lines; 0 errors; 0 Graph writes (G8).

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 1.3
### END 1.3
[oer-s96] 1.3 row: groups | oer-s96-pim | Unchanged | group properties match
[oer-s96] 1.3 row: groups | oer-s96-pim | Extra | undeclared member '00000000-0000-0000-0000-000000000007' (use -Prune to remove)
[oer-s96] 1.3 row: groups | oer-s96-pim | Unchanged | pimPolicy (member) already matches
[oer-s96] 1.3 row: groups | oer-s96-pim | Unchanged | permanent eligibility for 'oer-s96-user@example.com' (member) already matches
[oer-s96] 1.3 row: directoryRoleManagementPolicies | Message Center Reader | Unchanged | policy already matches for 'Message Center Reader'
[oer-s96] 1.3 rows: Extra, Unchanged; warning lines: 0; errors: 0; Graph writes: 0
```

### 1.4. The plan of an administrative unit made dynamic shows the membership warning (engine case 1)

- [x] **1.4** `Invoke-OERStructure -WhatIf` with `oer-s96-au` declared `dynamic: true` writes `Set-OERAdministrativeUnit`'s membership-type warning once, before the `What if:` line of the update, and sends no Graph write; the unit stays assigned.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$Au = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-s96-au' -ErrorAction Stop
$Doc = [ordered]@{ version = '1.0'; administrativeUnits = @([ordered]@{ displayName = 'oer-s96-au'; dynamic = $true; membershipRule = '(user.department -eq "oer-s96")' }) } | ConvertTo-Json -Depth 10
$Want = "WARNING: Changing the membership type of administrative unit '$($Au.Id)' to 'Dynamic'."
$Cap = Invoke-S96Captured -Label '1.4' -Call { Invoke-OERStructure -Json $Doc -WhatIf }
Write-S96Capture -Label '1.4' -Capture $Cap
$IW = Get-S96LineIndex -Lines $Cap.Lines -Prefix $Want -Text ''
$IX = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'What if: ' -Text 'Update administrative unit properties'
$After = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-s96-au' -ErrorAction Stop
Write-OerLiveStep "1.4 warning count: $(@($Cap.Lines | Where-Object { $_.StartsWith($Want, [System.StringComparison]::Ordinal) }).Count); before its What if line: $($IW -ge 0 -and $IX -gt $IW); Graph writes: $($global:S96Writes.Count); the unit's membership type now: $($After.MembershipType)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** `warning count: 1`; `before its What if line: True`; `Graph writes: 0`; the membership
type `Assigned`.
**Failure looks like:** a count of `0` -- the plan does not show the warning; a write -- STOP.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Invoke-OERStructure -WhatIf with oer-s96-au declared dynamic: Set-OERAdministrativeUnit's membership-type warning once, before the What if line of the update (True); row Skipped; 0 Graph writes; the unit is still Assigned.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.4 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 1.4
WARNING: Changing the membership type of administrative unit '00000000-0000-0000-0000-000000000003' to 'Dynamic'. The unit's existing membership can change as a result; on a Dynamic unit the membership rule owns the membership and members can no longer be added or removed manually.
What if: Performing the operation "Update administrative unit properties (MembershipType, MembershipRule)" on target "oer-s96-au".
### END 1.4
[oer-s96] 1.4 host: WARNING: Changing the membership type of administrative unit '00000000-0000-0000-0000-000000000003' to 'Dynamic'. The unit's existing membership can change as a result; on a Dynamic unit the membership rule owns the membership and members can no longer be added or removed manually.
[oer-s96] 1.4 host: What if: Performing the operation "Update administrative unit properties (MembershipType, MembershipRule)" on target "oer-s96-au".
[oer-s96] 1.4 row: administrativeUnits | oer-s96-au | Skipped | would update administrative unit properties (MembershipType, MembershipRule)
[oer-s96] 1.4 warning count: 1; before its What if line: True; Graph writes: 0; the unit's membership type now: Assigned
```

## 2. BL-18: a direct -WhatIf shows the warning before the What if line

### 2.1. Remove-OERGroupEligibility -WhatIf

- [x] **2.1** `Remove-OERGroupEligibility -Group oer-s96-pim -User oer-s96-user -AccessType member -WhatIf` writes its warning before the `What if:` line and sends nothing; the eligibility 1.2 created is still listed.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$Cap = Invoke-S96Captured -Label '2.1' -Call { Remove-OERGroupEligibility -Group 'oer-s96-pim' -User $UserUpn -AccessType member -WhatIf }
Write-S96Capture -Label '2.1' -Capture $Cap
$IW = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'WARNING: Removing PIM member eligibility for principal ' -Text ''
$IX = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'What if: ' -Text 'Remove PIM member eligibility'
$El = @(Get-OERGroupEligibility -Group 'oer-s96-pim' -ErrorAction Stop | Where-Object { $null -ne $_ })
Write-OerLiveStep "2.1 warning before the What if line: $($IW -ge 0 -and $IX -gt $IW) (warning at $IW, What if at $IX); errors: $($Cap.Errors.Count); Graph writes: $($global:S96Writes.Count); eligibility schedules still listed: $($El.Count)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** `warning before the What if line: True`; `errors: 0`; `Graph writes: 0`; `eligibility
schedules still listed: 1`.
**Failure looks like:** `False` with the warning after the `What if:` line or missing -- the old
place inside the gate; a write -- STOP.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Remove-OERGroupEligibility -WhatIf: the warning on the host line before the What if line (warning at 0, What if at 1); 0 errors; 0 Graph writes; the eligibility from 1.2 still listed (1).

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 2.1
WARNING: Removing PIM member eligibility for principal '00000000-0000-0000-0000-000000000007' from group '00000000-0000-0000-0000-000000000002'. The principal loses the ability to activate this member access.
What if: Performing the operation "Remove PIM member eligibility from '00000000-0000-0000-0000-000000000007'" on target "00000000-0000-0000-0000-000000000002".
### END 2.1
[oer-s96] 2.1 host: WARNING: Removing PIM member eligibility for principal '00000000-0000-0000-0000-000000000007' from group '00000000-0000-0000-0000-000000000002'. The principal loses the ability to activate this member access.
[oer-s96] 2.1 host: What if: Performing the operation "Remove PIM member eligibility from '00000000-0000-0000-0000-000000000007'" on target "00000000-0000-0000-0000-000000000002".
[oer-s96] 2.1 warning before the What if line: True (warning at 0, What if at 1); errors: 0; Graph writes: 0; eligibility schedules still listed: 1
```

### 2.2. Set-OERAdministrativeUnit -MembershipType -WhatIf

- [x] **2.2** `Set-OERAdministrativeUnit -AdministrativeUnit oer-s96-au -MembershipType Dynamic -MembershipRule ... -WhatIf` writes the membership-type warning before the `What if:` line and sends nothing; the unit stays assigned.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$Cap = Invoke-S96Captured -Label '2.2' -Call { Set-OERAdministrativeUnit -AdministrativeUnit 'oer-s96-au' -MembershipType Dynamic -MembershipRule '(user.department -eq "oer-s96")' -WhatIf }
Write-S96Capture -Label '2.2' -Capture $Cap
$IW = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'WARNING: Changing the membership type of administrative unit ' -Text ''
$IX = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'What if: ' -Text 'Update administrative unit properties'
$After = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-s96-au' -ErrorAction Stop
Write-OerLiveStep "2.2 warning before the What if line: $($IW -ge 0 -and $IX -gt $IW) (warning at $IW, What if at $IX); errors: $($Cap.Errors.Count); Graph writes: $($global:S96Writes.Count); the unit's membership type now: $($After.MembershipType)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** `warning before the What if line: True`; `errors: 0`; `Graph writes: 0`; `Assigned`.
**Failure looks like:** as in 2.1.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Set-OERAdministrativeUnit -MembershipType Dynamic -WhatIf: the warning before the What if line (0, 1); 0 errors; 0 Graph writes; the unit still Assigned.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 2.2
WARNING: Changing the membership type of administrative unit '00000000-0000-0000-0000-000000000003' to 'Dynamic'. The unit's existing membership can change as a result; on a Dynamic unit the membership rule owns the membership and members can no longer be added or removed manually.
What if: Performing the operation "Update administrative unit properties" on target "00000000-0000-0000-0000-000000000003".
### END 2.2
[oer-s96] 2.2 host: WARNING: Changing the membership type of administrative unit '00000000-0000-0000-0000-000000000003' to 'Dynamic'. The unit's existing membership can change as a result; on a Dynamic unit the membership rule owns the membership and members can no longer be added or removed manually.
[oer-s96] 2.2 host: What if: Performing the operation "Update administrative unit properties" on target "00000000-0000-0000-0000-000000000003".
[oer-s96] 2.2 warning before the What if line: True (warning at 0, What if at 1); errors: 0; Graph writes: 0; the unit's membership type now: Assigned
```

### 2.3. Remove-OERActiveDirectoryRoleAssignment -WhatIf

- [x] **2.3** `Remove-OERActiveDirectoryRoleAssignment -Role <the low-risk role> -Group oer-s96-pim -WhatIf` writes its warning before the `What if:` line and sends nothing.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$R = if ($Role) { $Role } else { 'Message Center Reader' }
$Cap = Invoke-S96Captured -Label '2.3' -Call { Remove-OERActiveDirectoryRoleAssignment -Role $R -Group 'oer-s96-pim' -WhatIf }
Write-S96Capture -Label '2.3' -Capture $Cap
$IW = Get-S96LineIndex -Lines $Cap.Lines -Prefix "WARNING: Removing active directory role '$R' for principal 'oer-s96-pim'" -Text ''
$IX = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'What if: ' -Text 'Remove active directory role assignment'
Write-OerLiveStep "2.3 warning before the What if line: $($IW -ge 0 -and $IX -gt $IW) (warning at $IW, What if at $IX); errors: $($Cap.Errors.Count); Graph writes: $($global:S96Writes.Count)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** `warning before the What if line: True`; `errors: 0`; `Graph writes: 0`.
**Failure looks like:** as in 2.1.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Remove-OERActiveDirectoryRoleAssignment -Role 'Message Center Reader' -Group oer-s96-pim -WhatIf: the warning before the What if line (0, 1); 0 errors; 0 Graph writes.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.3 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 2.3
WARNING: Removing active directory role 'Message Center Reader' for principal 'oer-s96-pim' at directory scope '/'.
What if: Performing the operation "Remove active directory role assignment" on target "active directory role 'Message Center Reader' for principal 'oer-s96-pim' at directory scope '/'".
### END 2.3
[oer-s96] 2.3 host: WARNING: Removing active directory role 'Message Center Reader' for principal 'oer-s96-pim' at directory scope '/'.
[oer-s96] 2.3 host: What if: Performing the operation "Remove active directory role assignment" on target "active directory role 'Message Center Reader' for principal 'oer-s96-pim' at directory scope '/'".
[oer-s96] 2.3 warning before the What if line: True (warning at 0, What if at 1); errors: 0; Graph writes: 0
```

### 2.4. A piped Get-OERGroupMember row is refused with a message that says what was piped

- [x] **2.4** `Get-OERGroupMember -Group oer-s96-pim | Remove-OERActiveDirectoryRoleAssignment -Role <the low-risk role> -WhatIf` is refused with `NotDirectAssignment`, whose message says the piped object is a group member row from `Get-OERGroupMember`; no warning, no `What if:` line, nothing sent.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$R = if ($Role) { $Role } else { 'Message Center Reader' }
$Rows = @(Get-OERGroupMember -Group 'oer-s96-pim' -ErrorAction Stop)
$Cap = Invoke-S96Captured -Label '2.4' -Call { $Rows | Remove-OERActiveDirectoryRoleAssignment -Role $R -WhatIf }
Write-S96Capture -Label '2.4' -Capture $Cap
$E = @($Cap.Errors | Where-Object { ([string]$_.FullyQualifiedErrorId).StartsWith('NotDirectAssignment', [System.StringComparison]::Ordinal) })
Write-OerLiveStep "2.4 piped rows: $($Rows.Count); NotDirectAssignment errors: $($E.Count); the message names a group member row from Get-OERGroupMember: $(@($E | Where-Object { $_.Exception.Message -like '*is a group member row*from Get-OERGroupMember*' }).Count -eq $E.Count -and $E.Count -gt 0); warning lines: $(@($Cap.Lines | Where-Object { $_.StartsWith('WARNING: ', [System.StringComparison]::Ordinal) }).Count); What if lines: $(@($Cap.Lines | Where-Object { $_.StartsWith('What if: ', [System.StringComparison]::Ordinal) }).Count); Graph writes: $($global:S96Writes.Count)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** `piped rows: 1` (the user); `NotDirectAssignment errors: 1`; `True`; `warning lines: 0`;
`What if lines: 0`; `Graph writes: 0`.
**Failure looks like:** a message saying the assignment "is inherited through a group" -- the old text
for this input; a `What if:` line -- the refusal no longer comes first.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Get-OERGroupMember -Group oer-s96-pim piped one row (the user) into Remove-OERActiveDirectoryRoleAssignment -WhatIf: one NotDirectAssignment error whose message says the piped object is a group member row (MemberType 'Member') from Get-OERGroupMember and shows the -PrincipalId form; 0 warning lines; 0 What if lines; 0 Graph writes.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.4 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 2.4
### END 2.4
[oer-s96] 2.4 host: Remove-OERActiveDirectoryRoleAssignment: REPO\docs\live-verification\raw\s96\child-2.4.ps1:127
[oer-s96] 2.4 host: Line |
[oer-s96] 2.4 host:  127 |  … l { $Rows | Remove-OERActiveDirectoryRoleAssignment -Role $R -WhatIf  …
[oer-s96] 2.4 host:      |                ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[oer-s96] 2.4 host:      | The piped object for principal '00000000-0000-0000-0000-000000000007' is a group member row (MemberType 'Member') from Get-OERGroupMember, not an active assignment of directory role 'Message Center Reader', so nothing is removed: the request names only the role and the principal, and would remove that principal's own direct active assignment, if one exists. To remove that assignment on purpose, name the principal with -PrincipalId, for example: ... | ForEach-Object { Remove-OERActiveDirectoryRoleAssignment -Role 'Message Center Reader' -PrincipalId $_.PrincipalId }
[oer-s96] 2.4 error: NotDirectAssignment (InvalidArgument): The piped object for principal '00000000-0000-0000-0000-000000000007' is a group member row (MemberType 'Member') from Get-OERGroupMember, not an active assignment of directory role 'Message Center Reader', so nothing is removed: the request names only the role and the principal, and would remove th ...
[oer-s96] 2.4 piped rows: 1; NotDirectAssignment errors: 1; the message names a group member row from Get-OERGroupMember: True; warning lines: 0; What if lines: 0; Graph writes: 0
```

## 3. BL-07: a group created into an administrative unit is not pruned out of it in the same run

### 3.1. The validator, offline: a template name, a unit named by id, a member named by object id

- [x] **3.1** `Test-OERStructure` warns for a template-named group placed in a unit whose members omit it (naming the computed name) and for a group naming its unit by an object id it cannot match, and gives no placement warning when the unit's members name the group by an object id.

```powershell
$Docs = [ordered]@{
    'a template name' = [ordered]@{ version = '1.0'; groups = @([ordered]@{ template = 'oer-s96-{app}'; tokens = [ordered]@{ app = 'tpl' }; administrativeUnit = 'oer-s96-au'; members = @() }); administrativeUnits = @([ordered]@{ displayName = 'oer-s96-au'; members = @(); scopedRoles = @() }) }
    'a unit named by id' = [ordered]@{ version = '1.0'; groups = @([ordered]@{ displayName = 'oer-s96-idgrp'; administrativeUnit = '00000000-0000-0000-0000-000000000099'; members = @() }); administrativeUnits = @([ordered]@{ displayName = 'oer-s96-au'; members = @(); scopedRoles = @() }) }
    'a member named by object id' = [ordered]@{ version = '1.0'; groups = @([ordered]@{ displayName = 'oer-s96-idmem'; administrativeUnit = 'oer-s96-au'; members = @() }); administrativeUnits = @([ordered]@{ displayName = 'oer-s96-au'; members = @('00000000-0000-0000-0000-000000000098'); scopedRoles = @() }) }
}
# Offline: the worktree's build through OerLive's own loader (no sign-in, no tenant call).
& (Get-Module -Name OerLive) { Import-OerLiveModule }
Start-S96NoPrompt
foreach ($Key in $Docs.Keys) {
    $V = Test-OERStructure -Json ($Docs[$Key] | ConvertTo-Json -Depth 10)
    $Placement = @(@($V.Errors) | Where-Object { [string]$_.Path -like 'groups*.administrativeUnit' })
    Write-OerLiveStep "3.1 $($Key): valid $($V.Valid); placement findings: $($Placement.Count)"
    foreach ($F in $Placement) { Write-OerLiveStep "3.1 $($Key): $($F.Severity) at $($F.Path): $($F.Message)" }
}
```

**Expect:** `a template name: valid True; placement findings: 1`, a `Warning` naming `oer-s96-tpl`
(the computed name) and saying the run that creates the group withholds the prune and a later
`-Prune` removes the membership; `a unit named by id: valid True; placement findings: 1`, a
`Warning` saying the check cannot be made offline for that id; `a member named by object id: valid
True; placement findings: 0`.
**Failure looks like:** `placement findings: 0` for the template -- the old rule that skipped a
template-based group; `1` for the member named by object id -- the old false warning.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Offline, no sign-in: a template-named group placed in a unit whose members omit it gives one placement Warning naming the computed name oer-s96-tpl and saying the creating run withholds the prune and every later apply removes it; a group naming its unit by an object id no entry declares gives one Warning saying the check cannot be made offline; a unit whose members name the group by an object id gives no placement finding. All three documents valid.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] 3.1 a template name: valid True; placement findings: 1
[oer-s96] 3.1 a template name: Warning at groups[0].administrativeUnit: Group 'oer-s96-tpl' at groups[0] declares administrativeUnit 'oer-s96-au', but administrativeUnits[0].members does not list 'oer-s96-tpl'. administrativeUnit is applied only when the group is created and never round-trips: the run that creates the group withholds the prune of that membership (Skipped, "prune withheld"), but every later apply with -Prune removes it unless this document's administrativeUnits[0] entry names the group in members.
[oer-s96] 3.1 a unit named by id: valid True; placement findings: 1
[oer-s96] 3.1 a unit named by id: Warning at groups[0].administrativeUnit: Group 'oer-s96-idgrp' at groups[0] declares administrativeUnit '00000000-0000-0000-0000-000000000099', an object id that no administrativeUnits[] entry declares as its id, so this check cannot tell offline whether it names a unit whose members do not list 'oer-s96-idgrp' (administrativeUnits[0]). administrativeUnit is applied only when the group is created and never round-trips: if it names one of them, the run that creates the group withholds the prune of that membership (Skipped, "prune withheld"), and every later apply with -Prune removes it. Name the group in that unit's members, or declare the unit's id on its administrativeUnits[] entry.
[oer-s96] 3.1 a member named by object id: valid True; placement findings: 0
```

### 3.2. -Prune in the run that creates the group: Created, and the unit's prune withheld

- [x] **3.2** `Invoke-OERStructure -Json $P -Prune -Confirm:$false` creates `oer-s96-new` into `oer-s96-au` and reports the unit's prune of it `Skipped` with a Detail starting `prune withheld:`; the fence around the module's transport makes the unit's member read wait until the new group is listed, and refuses (and counts) any removal from the unit -- none is attempted.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
$Au = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-s96-au' -ErrorAction Stop
$Module = Get-Module -Name Omnicit.EntraRBAC
& $Module {
    param($AuId)
    $script:S96Real = ${function:Invoke-OERGraphRequest}
    $script:S96Au = [ordered]@{ AuId = $AuId; MemberReads = 0; Retries = 0; Listed = $false; Refused = 0; NewId = $null }
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-OERGraphRequest))
    $Body = @'
$M = if ($PSBoundParameters.ContainsKey('Method')) { ([string]$Method).ToUpperInvariant() } else { 'GET' }
$U = [string]$Uri
if ($M -eq 'DELETE' -and $U -match '^v1\.0/directory/administrativeUnits/[^/]+/members/[^/]+/\$ref$') {
    $script:S96Au.Refused++
    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('S96 fence: a removal from the administrative unit was refused.'), 'S96FenceRefused', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
}
if ($M -eq 'GET' -and $U.StartsWith("v1.0/directory/administrativeUnits/$($script:S96Au.AuId)/members", [System.StringComparison]::OrdinalIgnoreCase)) {
    $script:S96Au.MemberReads++
    $Deadline = [datetime]::UtcNow.AddSeconds(240)
    while ($true) {
        if (-not $script:S96Au.NewId) {
            $G = & $script:S96Real -Uri "v1.0/groups?`$filter=displayName eq 'oer-s96-new'&`$select=id"
            $script:S96Au.NewId = @(@($G.value) | ForEach-Object { [string]$_.id })[0]
        }
        $R = & $script:S96Real @PSBoundParameters
        if ($script:S96Au.NewId -and (@(@($R.value) | ForEach-Object { [string]$_.id }) -contains $script:S96Au.NewId)) { $script:S96Au.Listed = $true; return $R }
        if ([datetime]::UtcNow -gt $Deadline) { return $R }
        $script:S96Au.Retries++
        Start-Sleep -Seconds 10
    }
}
& $script:S96Real @PSBoundParameters
'@
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend {`n$Body`n}"
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value ([scriptblock]::Create($Text))
} $Au.Id
$P = Get-S96DocumentP
$Cap = Invoke-S96Captured -Label '3.2' -Call { Invoke-OERStructure -Json $P -Prune -Confirm:$false }
Write-S96Capture -Label '3.2' -Capture $Cap
$Fence = & $Module { $script:S96Au }
& $Module { Set-Item -Path function:script:Invoke-OERGraphRequest -Value $script:S96Real }
$Created = @($Cap.Output | Where-Object { $_.Section -eq 'groups' -and $_.Action -eq 'Created' })
$Withheld = @($Cap.Output | Where-Object { $_.Section -eq 'administrativeUnits' -and $_.Action -eq 'Skipped' -and ([string]$_.Detail).StartsWith('prune withheld: ', [System.StringComparison]::Ordinal) -and ([string]$_.Detail).Contains($Fence.NewId) })
$Removed = @($Cap.Output | Where-Object { $_.Section -eq 'administrativeUnits' -and $_.Action -eq 'Removed' })
Write-OerLiveStep "3.2 groups Created: $($Created.Count); the unit's prune of the new group withheld: $($Withheld.Count); administrativeUnits Removed: $($Removed.Count); errors: $($Cap.Errors.Count)"
Write-OerLiveStep "3.2 fence: unit member reads $($Fence.MemberReads), waits $($Fence.Retries), the new group listed when read: $($Fence.Listed), removals refused: $($Fence.Refused)"
Disconnect-OerLive
```

**Expect:** `groups Created: 1`; `the unit's prune of the new group withheld: 1`, the row's Detail
starting `prune withheld:` and naming `oer-s96-new` as created into this unit in this run;
`administrativeUnits Removed: 0`; `errors: 0`; the fence: at least one unit member read, `the new
group listed when read: True`, `removals refused: 0`. The validator's placement warning is not
printed by the run (`Invoke-OERStructure` reports only validation errors); 3.1 shows it offline.
**Failure looks like:** `removals refused: 1` -- the engine tried to remove the membership the run
created (the old defect), stopped only by the fence; `the new group listed when read: False` -- the
replication outlasted the fence's 240 s, so the guard was not reached: note it and re-run section 3
after the teardown with a fresh group, never with `-Prune` on this one.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Invoke-OERStructure -Prune -Confirm:$false created oer-s96-new into oer-s96-au (Created) and reported the unit's prune of it Skipped with a Detail starting "prune withheld:" that names the group as created into this unit in this run; administrativeUnits Removed 0; 0 errors. The fence around the module's transport: 1 unit member read, held 1 x 10 s until the new group was listed (True), and 0 removals refused -- the engine never tried to remove the membership.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 3.2
### END 3.2
[oer-s96] 3.2 row: groups | oer-s96-new | Created | created group oer-s96-new (00000000-0000-0000-0000-000000000010)
[oer-s96] 3.2 row: administrativeUnits | oer-s96-au | Unchanged | administrative unit properties match
[oer-s96] 3.2 row: administrativeUnits | oer-s96-au | Skipped | prune withheld: undeclared member '00000000-0000-0000-0000-000000000010' is group 'oer-s96-new', which this run created into this unit, and the run that creates a membership does not remove it (our own guard, not a Graph rejection). The next apply with -Prune removes it unless the unit's members name the group.
[oer-s96] 3.2 groups Created: 1; the unit's prune of the new group withheld: 1; administrativeUnits Removed: 0; errors: 0
[oer-s96] 3.2 fence: unit member reads 1, waits 1, the new group listed when read: True, removals refused: 0
```

### 3.3. The membership is still there after the replication

- [x] **3.3** `oer-s96-au`'s member list holds `oer-s96-new` in three reads 5 s apart, once it has converged.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
$Au = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-s96-au' -ErrorAction Stop
$NewId = [string]@((Invoke-OerLiveGraph -Uri "v1.0/groups?`$filter=displayName eq 'oer-s96-new'&`$select=id").Body['value'])[0]['id']
$Read = { $R = Invoke-OerLiveGraph -All -Uri "v1.0/directory/administrativeUnits/$($Au.Id)/members?`$select=id"; Assert-OerLiveOk -Response $R -Activity 'Reading the members of oer-s96-au' | Out-Null; , @(@($R.Body['value']) | ForEach-Object { [string]$_['id'] }) }
$Wait = Wait-OerLiveConverged -Activity 'oer-s96-au lists oer-s96-new' -Read $Read -Test { @($args[0]) -contains $NewId }
$Steady = @(1..3 | ForEach-Object { Start-Sleep -Seconds 5; $Ids = & $Read; @($Ids) -contains $NewId })
Write-OerLiveStep "3.3 oer-s96-au lists oer-s96-new after $($Wait.Attempts) read(s): True; three reads 5 s apart: $($Steady -join ', ')"
Disconnect-OerLive
```

**Expect:** `three reads 5 s apart: True, True, True`.
**Failure looks like:** a `False` -- the membership was removed after all; read 3.2's rows and the
fence's count.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, on the second run. The first run converged (the unit lists oer-s96-new) but printed False for the three steady reads: the block wrapped the read's already wrapped list in @() again, so -contains never matched (a checklist bug, corrected; 3.4 showed the member still listed). Second run: listed after 1 read, and three reads 5 s apart True, True, True.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.3 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s96] oer-s96-au lists oer-s96-new: converged after 1 read(s), 0.1 s.
[oer-s96] 3.3 oer-s96-au lists oer-s96-new after 1 read(s): True; three reads 5 s apart: True, True, True
```

### 3.4. The next apply with -Prune would remove it, as the validator says

- [x] **3.4** `Invoke-OERStructure -Json $P -Prune -WhatIf`, with the group now existing, plans the removal of `oer-s96-new` from `oer-s96-au` (the guard covers only the run that creates the membership) and sends nothing.

```powershell
Connect-OerLive -Arm
Start-S96NoPrompt
Start-S96Fence
$P = Get-S96DocumentP
$Cap = Invoke-S96Captured -Label '3.4' -Call { Invoke-OERStructure -Json $P -Prune -WhatIf }
Write-S96Capture -Label '3.4' -Capture $Cap
$Plan = @($Cap.Output | Where-Object { $_.Section -eq 'administrativeUnits' -and $_.Action -eq 'Skipped' -and ([string]$_.Detail).StartsWith('would remove undeclared member ', [System.StringComparison]::Ordinal) })
$IW = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared member ' -Text ''
$IX = Get-S96LineIndex -Lines $Cap.Lines -Prefix 'What if: ' -Text 'Remove undeclared member'
Write-OerLiveStep "3.4 planned removals from oer-s96-au: $($Plan.Count); the prune warning before its What if line: $($IW -ge 0 -and $IX -gt $IW); withheld rows: $(@($Cap.Output | Where-Object { ([string]$_.Detail).StartsWith('prune withheld: ', [System.StringComparison]::Ordinal) }).Count); Graph writes: $($global:S96Writes.Count)"
Stop-S96Fence
Disconnect-OerLive
```

**Expect:** `planned removals from oer-s96-au: 1`; `True`; `withheld rows: 0`; `Graph writes: 0`.
Nothing here runs this document for real: the next real apply would remove the membership, which is
what the validator's warning says.
**Failure looks like:** a withheld row -- the guard reaches beyond the creating run (a prune-semantics
change, G11.1); a write -- STOP.

Result: 2026-10-07 14:14 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The same document with -Prune -WhatIf, the group now existing: one planned removal of oer-s96-new from oer-s96-au (Skipped "would remove undeclared member"), the prune warning before its What if line (True), 0 withheld rows, 0 Graph writes. The guard covers only the creating run, as the validator's warning says; the document was not run for real again.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.4 ===
[oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s96] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
### BEGIN 3.4
WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared member '00000000-0000-0000-0000-000000000010' from unit 'oer-s96-au'.
What if: Performing the operation "Remove undeclared member '00000000-0000-0000-0000-000000000010'" on target "oer-s96-au".
### END 3.4
[oer-s96] 3.4 host: WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared member '00000000-0000-0000-0000-000000000010' from unit 'oer-s96-au'.
[oer-s96] 3.4 host: What if: Performing the operation "Remove undeclared member '00000000-0000-0000-0000-000000000010'" on target "oer-s96-au".
[oer-s96] 3.4 row: groups | oer-s96-new | Unchanged | group properties match
[oer-s96] 3.4 row: administrativeUnits | oer-s96-au | Unchanged | administrative unit properties match
[oer-s96] 3.4 row: administrativeUnits | oer-s96-au | Skipped | would remove undeclared member '00000000-0000-0000-0000-000000000010'
[oer-s96] 3.4 planned removals from oer-s96-au: 1; the prune warning before its What if line: True; withheld rows: 0; Graph writes: 0
```

## Teardown

### T.1. The policies are put back, the objects removed, nothing carries the prefix, and the main clone is untouched

- [x] **T.1** `Initialize-OerS96Prereq.ps1 -Teardown -Unattended` puts the chosen directory role's policy back to its baseline, removes `oer-s96-user`'s eligibility, puts `oer-s96-pim`'s member policy back, removes `oer-s96-new`, `oer-s96-pim` and `oer-s96-user`, and deletes `oer-s96-au`; the sweep finds nothing with the prefix; the counts equal the baseline; no session is left; the main clone is on `main` at the HEAD S.1 recorded.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96Prereq.ps1') -Teardown -Unattended 2>&1 | ForEach-Object { "$_" })
$Code = $LASTEXITCODE
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Teardown exit code: $Code"
$Module = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "A Graph SDK session is left: $([bool](Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue | ForEach-Object { Get-MgContext })); the module holds a session: $([bool]($Module -and (& $Module { $script:_OERAuthState })))"
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainHead = ([string]($List | Where-Object { $_ -like 'HEAD *' } | Select-Object -First 1)) -replace '^HEAD ', ''
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "Main clone: branch $MainBranch; HEAD $($MainHead.Substring(0, 7))"
```

**Expect:** the teardown's identity lines `True`; `Teardown A: '<role>' at its baseline: True (rules
differing before: 1 or 2: ...)` for the chosen role (the authentication context rule, and the
enablement rule unless 1.0 and 1.2 left it as it was) and `(rules differing before: 0)` for the
other;
`Teardown B: oer-s96-pim: direct eligibility schedules 1` and its removal, `oer-s96-new: ... 0`;
`Teardown C: ... restored: True`; the library's step 5 removing both groups and step 6 the user;
`Teardown E: deleted oer-s96-au`; the sweep empty; the three counts equal to the baseline (`True`);
exit code 0; no session left; the main clone on `main` at the HEAD S.1 recorded.
**Failure looks like:** exit code 1 with a `STOP` line -- a policy could not be put back: the objects
are NOT deleted, and the step stops (G11.5); exit code 3 -- residue in `raw\residue.json`, which the
next prereq run retries; report each row. An object deleted with 204 can still show in the sweep for
a minute or two: read back with T.2 before judging.

Result: 2026-10-07 14:15 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS, with one count read back in T.2. Identity check passed; no residue. Teardown A: Message Center Reader at its baseline: True (1 rule differing before: AuthenticationContext_EndUser_Assignment; the enablement rule was back as it was after 1.0 and 1.2), restored after 1 read; Reports Reader 0 differing. Teardown B: oer-s96-pim held 1 direct eligibility schedule (1.2's), removed (201 Revoked); oer-s96-new 0. Teardown C: the member policy of oer-s96-pim had another id than at the baseline (onboarding), 2 rules differing (AuthenticationContext_EndUser_Assignment, Expiration_Admin_Eligibility), both sent from the baseline (200, 200) and read back at the baseline after 1 read. The library: step 2 removed the user's direct membership (201), step 5 deleted oer-s96-new and oer-s96-pim (204, 204), step 6 deleted oer-s96-user (204); removed 4, residue 0, unreadable 0. Teardown E: deleted oer-s96-au (204). The sweep finds nothing with the prefix; groups 98 and administrative units 1 equal the baseline; users read 24 against 23 one read after the user's 204 (the listing lags a deletion), equal in T.2. Exit code 0; no session left; the main clone on main at 6817b33, the HEAD S.1 recorded.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[oer-s96] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s96] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s96] [oer-s96] Transcript (redacted): raw\s96\teardown-20261007-141232Z.log; OerLive 1.0.3.
[oer-s96] [oer-s96] Mode: REMOVE. Prefix 'oer-s96-'. Objects (fixed): oer-s96-user (disabled); oer-s96-pim (its one member oer-s96-user, its member PIM policy baselined and set to the starting state); oer-s96-au (assigned, no member); oer-s96-new is the checklist's own. The low-risk directory roles' policies are baselined. OerLive 1.0.3.
[oer-s96] [oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s96] [oer-s96] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s96] [oer-s96] Residue: raw\residue.json holds no rows.
[oer-s96] [oer-s96] Directory role 'Message Center Reader': rules differing from the baseline: 1 (AuthenticationContext_EndUser_Assignment)
[oer-s96] [oer-s96] Directory role 'Message Center Reader': sent rule AuthenticationContext_EndUser_Assignment from the baseline: 200.
[oer-s96] [oer-s96] Directory role 'Message Center Reader' back at its baseline: converged after 1 read(s), 0.7 s.
[oer-s96] [oer-s96] Directory role 'Message Center Reader': restored: True (1 read(s), 0.7 s).
[oer-s96] [oer-s96] Teardown A: 'Message Center Reader' at its baseline: True (rules differing before: 1: AuthenticationContext_EndUser_Assignment).
[oer-s96] [oer-s96] Directory role 'Reports Reader': rules differing from the baseline: 0
[oer-s96] [oer-s96] Teardown A: 'Reports Reader' at its baseline: True (rules differing before: 0).
[oer-s96] [oer-s96] Teardown B: oer-s96-new: direct eligibility schedules 0.
[oer-s96] [oer-s96] Teardown B: oer-s96-pim: direct eligibility schedules 1.
[oer-s96] [oer-s96] Teardown B: removed oer-s96-pim: member eligibility schedule (201 Revoked).
[oer-s96] [oer-s96] oer-s96-pim: no eligibility schedule listed: converged after 1 read(s), 0.4 s.
[oer-s96] [oer-s96] oer-s96-pim's member PIM policy is listed: converged after 1 read(s), 0.4 s.
[oer-s96] [oer-s96] Teardown C: the member policy of oer-s96-pim has another id than when the baseline was recorded (onboarding to PIM for Groups changes it); the baseline's rules are put back on the policy the group's scope lists now.
[oer-s96] [oer-s96] Teardown C: member policy of oer-s96-pim now: MFA on activation: False; other enablement flags: Justification; authentication context: 'c1'; eligible assignments must expire: False; rules differing from the baseline: 2 (AuthenticationContext_EndUser_Assignment, Expiration_Admin_Eligibility)
[oer-s96] [oer-s96] Teardown C: sent rule AuthenticationContext_EndUser_Assignment from the baseline: 200.
[oer-s96] [oer-s96] Teardown C: sent rule Expiration_Admin_Eligibility from the baseline: 200.
[oer-s96] [oer-s96] oer-s96-pim's member PIM policy is listed: converged after 1 read(s), 0.4 s.
[oer-s96] [oer-s96] oer-s96-pim's member policy back at its baseline: converged after 1 read(s), 1.3 s.
[oer-s96] [oer-s96] Teardown C: member policy of oer-s96-pim restored: True (1 read(s), 1.3 s); MFA on activation: False; other enablement flags: Justification; authentication context: none; eligible assignments must expire: True
[oer-s96] [oer-s96] Teardown of 'oer-s96-': users 1, groups 2, access packages 0, catalogs 0; administrative units 1 and app registrations 0 are reported only.
[oer-s96] [oer-s96] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s96] [oer-s96] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s96] [oer-s96] Removed: oer-s96-pim: PIM for Groups member assignment of a principal (201).
[oer-s96] [oer-s96] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s96] [oer-s96] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s96] [oer-s96] Teardown 5/6: the prefixed groups.
[oer-s96] [oer-s96] Deleted: group oer-s96-new (204).
[oer-s96] [oer-s96] Deleted: group oer-s96-pim (204).
[oer-s96] [oer-s96] Teardown 6/6: the prefixed users.
[oer-s96] [oer-s96] DELETE user oer-s96-user@example.com: 204  after 1 attempt(s), 0.2 s; first attempt no membership removed in this run.
[oer-s96] [oer-s96] Teardown of 'oer-s96-': removed 4, residue 0, unreadable 0.
[oer-s96] [oer-s96] Teardown E: deleted oer-s96-au (204).
[oer-s96] [oer-s96] oer-s96-au is gone: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s96] [oer-s96] oer-s96-au is gone: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s96] [oer-s96] oer-s96-au is gone: converged after 3 read(s), 6.3 s.
[oer-s96] [oer-s96] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s96-' is left.
[oer-s96] [oer-s96] Counts: users now 24, at the baseline 23; equal: False
[oer-s96] [oer-s96] Counts: groups now 98, at the baseline 98; equal: True
[oer-s96] [oer-s96] Counts: administrativeUnits now 1, at the baseline 1; equal: True
[oer-s96] [oer-s96] Done.
[oer-s96] Teardown exit code: 0
[oer-s96] A Graph SDK session is left: False; the module holds a session: False
[oer-s96] Main clone: branch main; HEAD 6817b33
```

### T.2. Read back, a few minutes later

- [x] **T.2** `Initialize-OerS96Prereq.ps1 -ReadBack` finds no prefixed object, no unread collection, the counts at the baseline, both directory role policies at their baselines, and no residue row.

```powershell
$Out = @(& pwsh -NoProfile -File (Join-Path $VaultDir 'Initialize-OerS96Prereq.ps1') -ReadBack 2>&1 | ForEach-Object { "$_" })
foreach ($Line in $Out) { Write-OerLiveStep (ConvertTo-OerLiveRedacted -Text $Line) }
Write-OerLiveStep "Read-back exit code: $LASTEXITCODE"
```

**Expect:** the sweep empty; the counts `True`; `rules differing from the baseline: 0` for both roles;
`prefixed objects left: 0; unread collections: 0; residue rows: 0`; exit code 0.
**Failure looks like:** a prefixed object or a residue row -- report it in the step's report with its
kind and name.

Result: 2026-10-07 14:15 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Read back a few minutes after T.1: the sweep finds nothing with the prefix; users 23, groups 98 and administrative units 1, each equal to the baseline (True); Message Center Reader and Reports Reader 0 rules differing from their baselines; prefixed objects left 0, unread collections 0, residue rows 0; exit code 0.

oer-testmiljo.psd1: 9 keys; oer-cc-identitet.psd1: 4 keys; worktree exists: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.2 ===
[oer-s96] [OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[oer-s96] [OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s96] [oer-s96] Transcript (redacted): raw\s96\readback-20261007-141436Z.log; OerLive 1.0.3.
[oer-s96] [oer-s96] Mode: READ BACK. Prefix 'oer-s96-'. Objects (fixed): oer-s96-user (disabled); oer-s96-pim (its one member oer-s96-user, its member PIM policy baselined and set to the starting state); oer-s96-au (assigned, no member); oer-s96-new is the checklist's own. The low-risk directory roles' policies are baselined. OerLive 1.0.3.
[oer-s96] [oer-s96] Omnicit.EntraRBAC 1.1.3 loaded from REPO\.claude\worktrees\s9-steg6\output\module\Omnicit.EntraRBAC\1.1.3.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s96] [oer-s96] Microsoft Graph sign-in as oer-live-cc: identity check passed: True
[oer-s96] [oer-s96] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s96-' is left.
[oer-s96] [oer-s96] Counts: users now 23, at the baseline 23; equal: True
[oer-s96] [oer-s96] Counts: groups now 98, at the baseline 98; equal: True
[oer-s96] [oer-s96] Counts: administrativeUnits now 1, at the baseline 1; equal: True
[oer-s96] [oer-s96] Read-back: 'Message Center Reader' rules differing from the baseline: 0
[oer-s96] [oer-s96] Read-back: 'Reports Reader' rules differing from the baseline: 0
[oer-s96] [oer-s96] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 0.
[oer-s96] [oer-s96] Done.
[oer-s96] Read-back exit code: 0
```
