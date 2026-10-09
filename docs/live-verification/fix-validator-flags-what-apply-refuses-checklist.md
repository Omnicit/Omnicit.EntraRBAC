# Live verification checklist -- the validator and the plan say what an apply run does (fix/validator-flags-what-apply-refuses)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**What this file writes to the tenant: only inside the prefix `oer-s105-`.** The prerequisite script
`Initialize-OerS105Prereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates a security group `oer-s105-approver` with no member and an empty, tagged resource group
`oer-s105-rg` in the test subscription, and records the Reader role's policy at `oer-s105-rg` as a
baseline before anything writes to it. Check 2.1 writes that policy once, through
`Set-OERRoleManagementPolicy` (approval required, `oer-s105-approver` the only approver). Every other
check in section 2 is meant to write NOTHING, and counts the requests the module sends to prove it.
The teardown puts the policy back from the baseline before the group and the resource group are
deleted. Check 1.1 signs in nowhere; check 1.2 signs in and is refused before it sends anything.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only; nothing here signs in as a person. A 401 or 403 as
`oer-live-cc` is a stop.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block installs
the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s105/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** A `What if:` line, a warning and an error that
stops a script go straight to the host, so each block is run in its own process whose WHOLE output
(standard output and standard error) is written to a file under `raw\s105\`, redacted with OerLive's
redactor before anyone reads it, and then deleted.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. BL-97 (F1): approvers that name nobody fail in the plan too** ("fix: report approvers that
  name nobody as Failed in the plan too"). For an Azure role policy entry whose approvers, with any
  side the document leaves out kept from the live policy, would name nobody, the `-WhatIf` plan of
  `Invoke-OERStructure` said "would update" while every run reported `Failed`, since
  `Set-OERRoleManagementPolicy` refuses that change with `ApproverRequired`. The diff now flags it and
  the handler reports `Failed` with `ApproverRequired` before its confirmation, in the plan and in
  the run alike, and sends nothing.
- **B. BL-101: `Test-OERGuid` refuses a value ending in a line break** ("fix: refuse a GUID that ends
  in a line break"). Its pattern ended in `$`, which in .NET also matches before a last line feed, so
  a GUID followed by one line feed passed, while an ECMA-262 validator of the schema's pattern refuses
  it (PowerShell's own `Test-Json`, whose regular expressions are .NET's, accepts it too).
- **C. BL-101: the validator refuses a `tenantId` that is not a string** ("fix: refuse a tenantId
  that is not a string in the validator"). A one-GUID array passed Rule 1b, since its string cast is
  the GUID, while the schema's `"type": "string"` refuses it.
- **D. BL-100: three texts** ("fix: correct three texts the validator and apply engine show"): the
  schema's `administrativeUnit` description, the withheld prune of a group the run created or found
  already existing, and the `NotDirectAssignment` example for a role name with an apostrophe.
- **E. BL-104 F5: the `Remove-OERGroupMember` help agrees with itself** ("fix: align the
  Remove-OERGroupMember help and note the step in the release notes").

A live tenant is needed for A: a real Reader policy at a real scope that requires approval by a real
approver, read by the real `Get-OERRoleManagementPolicy`, and the real `Invoke-OERStructure` plan and
run against it, with Azure Resource Manager's own answer about the policy afterwards. The validator
half of B and C needs no tenant at all (1.1 runs it offline against the worktree's build) and is here
because the step's prompt asks for it. 1.2 shows the module-wide half of B in a real session:
`Test-OERGuid` decides whether a `-TenantId` is a tenant ID or a name to look up, so a tenant ID
followed by a line feed now goes to the tenant lookup and is refused there, where before it was taken
for the tenant's ID.

## What this file does not check, and why

- **D and E, the texts (class B, G9).** They change what a message or the help says, not what is
  sent. Section 3 names the unit tests that hold each text.
- **The same divergence for a directory role or a group PIM policy.** Unchanged by this branch:
  `Set-OERDirectoryRoleManagementPolicy` and `Set-OERGroupPimPolicy` still refuse a change that
  leaves no approver at run time, from the live rule, while their apply handlers plan "would update".
  It fails safe (nothing is written) and is reported as a finding outside this step's scope.
- **G8 (convergence).** This branch adds no write path. The refused document is run twice in real
  mode (2.3) and leaves the policy as it was, and the two documents that match the live policy are
  run twice each in real mode (2.5) and stay `Unchanged`.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run. This file adds no
  permission to it: it needs Owner on the test subscription and its Graph group permissions, as
  every earlier step did.
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 reads that it was not).
- The **prerequisite objects**: run `Initialize-OerS105Prereq.ps1 -WhatIf`, then
  `Initialize-OerS105Prereq.ps1 -Unattended`, with `OER_LIVE_REPO` set, before section 2.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the
counters and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s105-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$RgScope = "/subscriptions/$($Cfg.SubscriptionId)/resourceGroups/oer-s105-rg"
$Approver = 'oer-s105-approver'
# The Detail and the message the handler writes for approvers that name nobody (BL-97, F1).
$ExpectedDetail = 'approval would be required with no approver (ApproverRequired): the declared approvers, with any side the document does not declare kept from the live policy, name nobody; the policy was not changed'
$ExpectedMessageEnd = 'Name at least one approver, or declare requireApproval false. The policy was not changed.'
# A fixture GUID for section 1 (a placeholder, never a tenant value).
$FixtureGuid = '00000000-0000-0000-0000-000000000040'

function Import-S105Module {
    # The worktree's build, for the block that signs in nowhere (1.1).
    $Psd1 = Get-ChildItem -Path (Join-Path $Cfg.Repo 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $Required = Join-Path $Cfg.Repo 'output\RequiredModules'
    if (Test-Path -LiteralPath $Required) { $env:PSModulePath = $Required + [System.IO.Path]::PathSeparator + $env:PSModulePath }
    Import-Module -Name $Psd1.FullName -Force -Global -ErrorAction Stop
    Write-OerLiveStep "The module is the worktree's build: $((Get-Module -Name Omnicit.EntraRBAC).ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
}

function Start-S105NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S105TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S105TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S105 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S105Count {
    # Counts every request the module sends, by method: Azure Resource Manager through a global proxy of
    # Invoke-WebRequest, Microsoft Graph through one of Invoke-MgGraphRequest. The module's transports
    # call both unqualified, so the proxies are what they reach. A request without -Method is a GET.
    $global:S105Arm = [System.Collections.Generic.List[string]]::new()
    $global:S105Graph = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S105Arm.Add(`$($Record)); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S105Graph.Add(`$($Record)); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    # The tenant lookup (OpenID discovery of a tenant named by anything but a GUID) is the module's one
    # Invoke-RestMethod call: counted, never its address.
    $global:S105Lookup = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-RestMethod -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S105Lookup++; Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-RestMethod -Value ([scriptblock]::Create($Text))
}

function Stop-S105Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-WebRequest', 'Invoke-MgGraphRequest', 'Invoke-RestMethod') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S105Sent {
    # Requests counted since Start-S105Count, and how many of them were writes (any method but GET).
    $ArmWrites = @($global:S105Arm | Where-Object { $_ -ne 'GET' })
    $GraphWrites = @($global:S105Graph | Where-Object { $_ -ne 'GET' })
    "token requests: $global:S105TokenCalls; tenant lookups: $global:S105Lookup; Azure Resource Manager requests: $($global:S105Arm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" }); Microsoft Graph requests: $($global:S105Graph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" })"
}

function Get-S105ApproverId {
    # The approver group's object id, read once by its exact name (never printed unredacted).
    $Hits = @(Find-OerLivePrefixed -ThrowOnUnread -Quiet | Where-Object { $_.Kind -eq 'group' -and $_.Name -ceq $Approver })
    if ($Hits.Count -ne 1) { throw "STOP: $Approver matches $($Hits.Count) groups; run the prerequisite script first." }
    [string]$Hits[0].Id
}

function Get-S105Policy {
    # The Reader policy at oer-s105-rg as the module reads it, and its rules and last change as Azure
    # Resource Manager reports them.
    param([Parameter(Mandatory)][string]$ApproverId)
    $P = Get-OERRoleManagementPolicy -Role 'Reader' -Scope $RgScope -ErrorAction Stop
    $Raw = Invoke-OerLiveArm -Path "$($P.PolicyId)?api-version=2020-10-01"
    Assert-OerLiveOk -Response $Raw -Activity 'Reading the Reader policy at oer-s105-rg' | Out-Null
    $Rules = @(@($Raw.Body.properties.rules) | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 50 -Compress | ConvertFrom-Json -AsHashtable })
    $All = @($P.Approvers | Where-Object { $null -ne $_ })
    [PSCustomObject]@{
        RequireApproval     = [bool]$P.RequireApproval
        UserApprovers       = @($All | Where-Object { [string]$_.UserType -eq 'User' }).Count
        GroupApprovers      = @($All | Where-Object { [string]$_.UserType -eq 'Group' }).Count
        OnlyTheTestApprover = ($All.Count -eq 1 -and [string]$All[0].Id -ieq $ApproverId)
        LastModified        = [string]$Raw.Body.properties.lastModifiedDateTime
        Rules               = $Rules
    }
}

function Write-S105Policy {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Policy)
    Write-OerLiveStep "$Label policy: approval required: $($Policy.RequireApproval); user approvers: $($Policy.UserApprovers); group approvers: $($Policy.GroupApprovers); the only approver is $($Approver): $($Policy.OnlyTheTestApprover); last change reported: $(if ($Policy.LastModified) { 'yes' } else { 'no' })"
}

function Compare-S105Policy {
    # Whether the policy is as it was: no rule differs, and Azure Resource Manager reports the same last change.
    param([Parameter(Mandatory)][object]$Before, [Parameter(Mandatory)][object]$After)
    $Differing = @(Compare-OerLivePolicyRule -Live $After.Rules -Baseline $Before.Rules)
    Write-OerLiveStep "The policy as it was: rules differing: $($Differing.Count)$(if ($Differing.Count) { " ($($Differing -join ', '))" }); the same last change: $($After.LastModified -ceq $Before.LastModified)"
}

function New-S105Document {
    # A structure document with one roleManagementPolicies entry for Reader at oer-s105-rg.
    param([Parameter(Mandatory)][string]$Approvers)
    '{ "version": "1.0", "roleManagementPolicies": [ { "scope": "' + $RgScope + '", "role": "Reader", "approvers": ' + $Approvers + ' } ] }'
}

function Write-S105Rows {
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Rows)
    Write-OerLiveStep "$Label rows: $(@($Rows).Count)"
    foreach ($R in @($Rows)) {
        Write-OerLiveStep "$Label row: $($R.Section) | $($R.Action) | $($R.Detail)"
        if ([string]$R.Action -eq 'Failed') { Write-OerLiveStep "$Label row Detail is the expected text: $([string]$R.Detail -ceq $ExpectedDetail)" }
    }
}

function Write-S105Errors {
    # Prints the records of the given ids in full and only counts the rest: an inner layer's record can
    # carry a raw request as its target, which is never printed here.
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Errors, [Parameter(Mandatory)][string[]]$Ids)
    $Own = @($Errors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and (([string]$_.FullyQualifiedErrorId) -split ',')[0] -in $Ids })
    $I = 0
    foreach ($E in $Own) {
        $I++
        Write-OerLiveStep "$Label error [$I]: $([string]$E.FullyQualifiedErrorId) ($($E.CategoryInfo.Category)): $([string]$E.Exception.Message)"
        if ((([string]$E.FullyQualifiedErrorId) -split ',')[0] -eq 'ApproverRequired') {
            Write-OerLiveStep "$Label error [$I] ends with the expected advice: $(([string]$E.Exception.Message).EndsWith($ExpectedMessageEnd, [System.StringComparison]::Ordinal))"
        }
    }
    Write-OerLiveStep "$Label records with the ids $($Ids -join ', '): $($Own.Count); other items in -ErrorVariable (counted, not printed): $(@($Errors).Count - $Own.Count)"
}

function Invoke-S105Apply {
    # One Invoke-OERStructure call -- a -WhatIf plan or a run -- counted from its first request to its last.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json, [switch]$Plan)
    Start-S105Count
    $E = $null
    try {
        $Rows = if ($Plan) {
            @(Invoke-OERStructure -Json $Json -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E)
        } else {
            @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable E)
        }
        $Sent = Get-S105Sent
    } finally { Stop-S105Count }
    Write-S105Rows -Label $Label -Rows $Rows
    Write-S105Errors -Label $Label -Errors @($E) -Ids @('ApproverRequired')
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
Write-OerLiveStep "The worktree's build carries A: $(& $Has 'approval would be required with no approver (ApproverRequired)'); B: $(& $Has '{12}\z'); C: $(& $Has 'found a value that is not a string'); D: $(& $Has 'EscapeSingleQuotedStringContent'); E: $(& $Has 'service principal display name or object id')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `The worktree's build carries A:
True; B: True; C: True; D: True; E: True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main
clone; a `False` on the last line -- build the worktree first (`./build.ps1 -Tasks build`), never
while the gate runs.

Result: not run yet.

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S105NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not enabled
for this run; never sign in another way.

Result: not run yet.

## 1. A value that ends in a line feed, or is not a string (B and C)

### 1.1. A tenantId that ends in a line feed, or is a one-GUID array, is refused; the plain GUID passes

- [ ] **1.1** `Test-OERStructure` refuses a `tenantId` whose string ends in a line feed and a `tenantId` that is an array holding one GUID, each with exactly one Error at `tenantId`, and accepts the same GUID as a plain string.

```powershell
Import-S105Module
$Cases = @(
    @{ Label = 'a GUID string ending in a line feed (JSON \n)'; Fragment = '"' + $FixtureGuid + '\n"' }
    @{ Label = 'an array holding one GUID'; Fragment = '["' + $FixtureGuid + '"]' }
    @{ Label = 'the same GUID as a plain string'; Fragment = '"' + $FixtureGuid + '"' }
)
foreach ($Case in $Cases) {
    $V = Test-OERStructure -Json ('{ "version": "1.0", "tenantId": ' + $Case.Fragment + ' }')
    $Hit = @($V.Errors | Where-Object { $_.Path -eq 'tenantId' })
    Write-OerLiveStep "$($Case.Label): Valid $($V.Valid); findings $(@($V.Errors).Count); at tenantId $($Hit.Count)$(if ($Hit.Count) { "; severity $($Hit[0].Severity); message: $($Hit[0].Message)" })"
}
Write-OerLiveStep "Signed in: $([bool](& (Get-Module -Name Omnicit.EntraRBAC) { $script:_OERAuthState }))"
```

**Expect:** the line-feed case `Valid False; findings 1; at tenantId 1; severity Error`, with a
message that starts `'tenantId' must be` and quotes the value; the array case the same, with a
message that says `a value that is not a string (Object[])`; the plain string `Valid True; findings
0; at tenantId 0`; `Signed in: False`.
**Failure looks like:** `Valid True` for either of the first two -- the old predicate or the old
Rule 1b is in the build; a finding for the plain string -- the fix refuses too much.

Result: not run yet.

### 1.2. A tenant id followed by a line feed is no tenant ID: refused before any token request

- [ ] **1.2** In a session signed in as `oer-live-cc`, a command that names the test tenant's ID followed by a line feed as `-TenantId` is no longer taken for a GUID (B): `Initialize-OERAuth` looks it up as a name, the lookup fails, and the command is refused with `TenantResolutionFailed` before any token request, sending nothing.

```powershell
Connect-OerLive -Arm
Start-S105NoPrompt
$TokenBefore = $global:S105TokenCalls
Start-S105Count
$E = $null
$Caught = $null
try {
    $Rows = @(Get-OERGroup -Group $Approver -TenantId ($Cfg.TenantId + "`n") -ErrorAction SilentlyContinue -ErrorVariable E)
} catch { $Caught = $PSItem }
$Sent = Get-S105Sent
Stop-S105Count
Write-OerLiveStep "rows: $(@($Rows).Count); caught a terminating error: $([bool]$Caught)$(if ($Caught) { " ($(([string]$Caught.FullyQualifiedErrorId) -split ',' | Select-Object -First 1))" })"
Write-S105Errors -Label 'line feed' -Errors (@($E) + @($Caught | Where-Object { $_ })) -Ids @('TenantResolutionFailed', 'SignInRefused')
Write-OerLiveStep "token requests during the command: $($global:S105TokenCalls - $TokenBefore); $Sent"
Disconnect-OerLive
```

**Expect:** `rows: 0`; at least one `TenantResolutionFailed` record (and any `SignInRefused` the
latched command's own request draws); `token requests during the command: 0`; `tenant lookups: 1`;
no Azure Resource Manager or Microsoft Graph request.
**Failure looks like:** a token request, or a row -- the value was still taken for the tenant's ID;
a `TenantMismatch` -- a token was requested and compared.

Result: not run yet.

## 2. Approvers that name nobody: the plan and the run agree (A)

### 2.1. The Reader policy at oer-s105-rg requires approval by oer-s105-approver

- [ ] **2.1** After the prerequisite script, `Set-OERRoleManagementPolicy` makes the Reader policy at `oer-s105-rg` require approval with `oer-s105-approver` as its only approver, and the policy reads back that way. This is the one write section 2 makes on purpose.

```powershell
Connect-OerLive -Arm
Start-S105NoPrompt
$ApproverId = Get-S105ApproverId
$Before = Get-S105Policy -ApproverId $ApproverId
Write-S105Policy -Label 'Before' -Policy $Before
$Set = Set-OERRoleManagementPolicy -Role 'Reader' -Scope $RgScope -RequireApproval $true -ApproverGroup $Approver -Confirm:$false -ErrorAction Stop
Write-OerLiveStep "Set-OERRoleManagementPolicy changed rules: $(@($Set.ChangedRuleIds) -join ', ')"
$Wait = Wait-OerLiveConverged -Activity 'The Reader policy at oer-s105-rg requires approval by oer-s105-approver' -Read { Get-S105Policy -ApproverId $ApproverId } -Test { $args[0].RequireApproval -and $args[0].OnlyTheTestApprover }
Write-S105Policy -Label 'After' -Policy $Wait.Value
Disconnect-OerLive
```

**Expect:** `After policy: approval required: True; user approvers: 0; group approvers: 1; the only
approver is oer-s105-approver: True`, and `Set-OERRoleManagementPolicy changed rules` naming
`Approval_EndUser_Assignment`.
**Failure looks like:** a refused PATCH (a 403 is a stop); the policy not converging -- the rest of
section 2 cannot run, since the live policy would not have the approver it needs.

Result: not run yet.

### 2.2. The plan of a document whose approvers name nobody: Failed with ApproverRequired, nothing written

- [ ] **2.2** `Invoke-OERStructure -WhatIf` with `"approvers": { "users": [], "groups": [] }` reports exactly one `roleManagementPolicies` row, `Failed`, whose Detail is the `ApproverRequired` text, writes one `ApproverRequired` error, sends no write, and leaves the policy as it was.

```powershell
Connect-OerLive -Arm
Start-S105NoPrompt
$ApproverId = Get-S105ApproverId
$Before = Get-S105Policy -ApproverId $ApproverId
Write-S105Policy -Label 'Live' -Policy $Before
Invoke-S105Apply -Label 'plan' -Plan -Json (New-S105Document -Approvers '{ "users": [], "groups": [] }')
Compare-S105Policy -Before $Before -After (Get-S105Policy -ApproverId $ApproverId)
Disconnect-OerLive
```

**Expect:** the live policy as 2.1 left it; `plan rows: 1`, a `roleManagementPolicies | Failed`
row whose `Detail is the expected text: True`; `plan records with the ids ApproverRequired: 1`, its
message ending with the expected advice `True`; `writes: 0` for Azure Resource Manager and Microsoft
Graph, and token requests 0; `rules differing: 0; the same last change: True`.
**Failure looks like:** a `Skipped` row saying "would update" -- the plan still disagrees with the run
(BL-97 not fixed in the build); any write.

Result: not run yet.

### 2.3. The run of the same document, twice: the same row, nothing written, the policy as it was

- [ ] **2.3** The same document without `-WhatIf`, run twice, reports the same `Failed` row with the same Detail and one `ApproverRequired` error each time, sends no write, and leaves the policy as it was.

```powershell
Connect-OerLive -Arm
Start-S105NoPrompt
$ApproverId = Get-S105ApproverId
$Before = Get-S105Policy -ApproverId $ApproverId
Write-S105Policy -Label 'Live' -Policy $Before
$Json = New-S105Document -Approvers '{ "users": [], "groups": [] }'
Invoke-S105Apply -Label 'run 1' -Json $Json
Invoke-S105Apply -Label 'run 2' -Json $Json
Compare-S105Policy -Before $Before -After (Get-S105Policy -ApproverId $ApproverId)
Disconnect-OerLive
```

**Expect:** for each run, `rows: 1`, a `roleManagementPolicies | Failed` row whose `Detail is the
expected text: True`, one `ApproverRequired` record ending with the expected advice, and `writes: 0`
for both transports; `rules differing: 0; the same last change: True`.
**Failure looks like:** a Detail that starts `failed to update role management policy:` -- the run
reached `Set-OERRoleManagementPolicy` (the old path; it still sends nothing, but the plan and the run
differ); any write.

Result: not run yet.

### 2.4. Through the side the document leaves out: only groups declared empty, while the live approver is a group

- [ ] **2.4** With `"approvers": { "groups": [] }` the user side is kept from the live policy, which has no user approver, so the approvers again name nobody: the plan and the run both report the same `Failed` row with `ApproverRequired`, nothing is written, and the policy is as it was.

```powershell
Connect-OerLive -Arm
Start-S105NoPrompt
$ApproverId = Get-S105ApproverId
$Before = Get-S105Policy -ApproverId $ApproverId
Write-S105Policy -Label 'Live' -Policy $Before
$Json = New-S105Document -Approvers '{ "groups": [] }'
Invoke-S105Apply -Label 'plan' -Plan -Json $Json
Invoke-S105Apply -Label 'run' -Json $Json
Compare-S105Policy -Before $Before -After (Get-S105Policy -ApproverId $ApproverId)
Disconnect-OerLive
```

**Expect:** `user approvers: 0; group approvers: 1` live; for the plan and the run, `rows: 1`, a
`Failed` row whose `Detail is the expected text: True`, one `ApproverRequired` record, `writes: 0`;
`rules differing: 0; the same last change: True`.
**Failure looks like:** a `Skipped` plan row or an `Updated` run row -- the flag does not see the side
kept from the live policy.

Result: not run yet.

### 2.5. No over-fire: documents that match the live approvers stay Unchanged, twice

- [ ] **2.5** `"approvers": { "users": [] }` (the live user side is already empty, the group side is kept) and `"approvers": { "groups": [ "oer-s105-approver" ] }` (the live group side, by name) are each `Unchanged` in the plan and in two runs: no `ApproverRequired`, nothing written, the policy as it was.

```powershell
Connect-OerLive -Arm
Start-S105NoPrompt
$ApproverId = Get-S105ApproverId
$Before = Get-S105Policy -ApproverId $ApproverId
Write-S105Policy -Label 'Live' -Policy $Before
foreach ($Doc in @(
        @{ Label = 'users empty'; Approvers = '{ "users": [] }' }
        @{ Label = 'the approver group'; Approvers = '{ "groups": [ "' + $Approver + '" ] }' }
    )) {
    $Json = New-S105Document -Approvers $Doc.Approvers
    Invoke-S105Apply -Label "$($Doc.Label), plan" -Plan -Json $Json
    Invoke-S105Apply -Label "$($Doc.Label), run 1" -Json $Json
    Invoke-S105Apply -Label "$($Doc.Label), run 2" -Json $Json
}
Compare-S105Policy -Before $Before -After (Get-S105Policy -ApproverId $ApproverId)
Disconnect-OerLive
```

**Expect:** for each document, the plan and both runs `rows: 1` with a `roleManagementPolicies |
Unchanged` row, `records with the ids ApproverRequired: 0`, and `writes: 0`; `rules differing: 0;
the same last change: True`.
**Failure looks like:** a `Failed` row with `ApproverRequired` -- the flag fires where the run would
not refuse; an `Updated` row -- the documents do not converge.

Result: not run yet.

## 3. The texts (class B)

### 3.1. The three BL-100 texts and the BL-104 help are held by unit tests

- [ ] **3.1** Each text is proved by a unit test in this branch, run by the gate on every runner; none needs a tenant.

- **The schema's `administrativeUnit` description** (`Get-OERStructureSchemaJson`): `tests/Unit/Private/Get-OERStructureSchemaJson.Tests.ps1` asserts it says a GUID-shaped value is compared as a GUID and no longer says "matches this value (ignoring case)".
- **The withheld prune of a group the run created or found already existing** (`ConvertTo-OERPruneWithheldResult`): `tests/Unit/Private/ConvertTo-OERPruneWithheldResult.Tests.ps1`, `tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1` and `tests/Unit/Public/Invoke-OERStructure.Tests.ps1` pin the new Detail exactly, and one assertion holds that it no longer claims "which this run created into this unit".
- **The `NotDirectAssignment` example**: `tests/Unit/Public/Remove-OERActiveDirectoryRoleAssignment.Tests.ps1` and `tests/Unit/Public/Remove-OEREligibleDirectoryRoleAssignment.Tests.ps1` parse the example for a role name holding each of the five PowerShell single-quote characters and assert that it parses with no error and gives back the role name exactly.
- **The `Remove-OERGroupMember` help**: `tests/Unit/Public/Remove-OERGroupMember.Tests.ps1` asserts the description names a display name or object id for `-User`, `-GroupPrincipal` and `-ServicePrincipal`.

Result: not run yet.

## Teardown

### T.1. The Reader policy back at its baseline, nothing left with the prefix

- [ ] **T.1** `Initialize-OerS105Prereq.ps1 -Teardown -Unattended` puts the Reader policy at `oer-s105-rg` back to its baseline before anything is deleted, removes `oer-s105-approver`, deletes `oer-s105-rg`, and the sweep finds nothing with the prefix; the group count equals the baseline's.

```powershell
& pwsh -NoProfile -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS105Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "Teardown exit code: $LASTEXITCODE"
Connect-OerLive -Arm
Start-S105NoPrompt
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
$Rg = Invoke-OerLiveArm -Path "$RgScope`?api-version=2021-04-01"
Write-OerLiveStep "oer-s105-rg exists: $([bool]$Rg.Ok)"
Disconnect-OerLive
```

**Expect:** the teardown's `Reader policy at oer-s105-rg at its baseline: True`, `deleted
oer-s105-rg`, `equal: True` for the group count, exit code 0; then objects with the prefix 0,
unread collections 0, `oer-s105-rg exists: False`.
**Failure looks like:** `STOP: the Reader policy ... was not put back` -- nothing is deleted, and the
policy is restored by hand from the baseline before anything else; a residue line; an object with
the prefix left.

Result: not run yet.
