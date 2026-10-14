# Live verification checklist -- refuse unsupported renames and keep policy settings on update (fix/guard-renames-and-policy-updates)

**This branch does not merge until every box in sections S, 0, 1, 2, 3, 4, 5, 6, 7 and T has a
written result.** A box with no result line filled in is not a passed check -- it is an unrun one. If a
check turns out to be impossible to run, write "cannot be verified, and therefore we do not know" on its
result line and say why; do not leave it blank and do not tick it. A check that could not run for a
stated reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).**
This step has no manual check (class C): the custom extension and the automatic assignment policy the
step needed could both be created in the test tenant.

**What this file writes to the tenant: only inside the prefix `oer-s113-`.** The prerequisite script
`Initialize-OerS113Prereq.ps1`, kept beside the operator's copy of this file outside the repository,
creates a security group `oer-s113-grp-old` with no member (mailNickname `oer-s113-grp-old`), a catalog
`oer-s113-catalog`, a hidden access package `oer-s113-ap` in it with no resource, a tagged resource group
`oer-s113-rg` in the test subscription holding one Consumption Logic App `oer-s113-la` (an HTTP request
trigger and no action, with an authorization policy for this tenant's issuer; nothing calls it), a custom
extension `oer-s113-ext` in the catalog whose endpoint is that Logic App, an assignment policy
`oer-s113-policy` on the package that only the members of `oer-s113-grp-old` (none) may request through,
with one optional text question and one custom extension stage, and an automatic assignment policy
`oer-s113-autopolicy` whose attribute rule matches no user. Section 1 records the measurement made before
any code of this branch existed: it changed the description of both policies, removed the policy's custom
extension stage (that is what it measured) and changed the group's mail alias and put it back. Check 0.3
puts the policy back to its full state. Section 2 changes both policies' descriptions through the module.
Section 3 creates a catalog `oer-s113-newcat`, a hidden package `oer-s113-newap` and a policy
`oer-s113-newpol` through `Invoke-OERStructure`, requestable only by the members of `oer-s113-grp-old`.
Sections 4 to 7 must write nothing. Nobody is assigned anything. The teardown (T.1) deletes the policy
holding the custom extension stage and the custom extension, then the policies, the packages, the
catalogs and the group, then the resource group with the Logic App. Documents and request counts are
written under `raw\s113\`, which is deleted after the results are written.

**Who runs it.** The dedicated certificate identity `oer-live-cc`, through the OerLive library, which
lives beside the operator's copy of this file outside the repository ([README.md](README.md), first
paragraph). Every sign-in is app-only, with the certificate; nothing here signs in as a person. A 401
or 403 as `oer-live-cc` is a stop, except where a check measures exactly that.

**Permission.** The package objects and the custom extension need the Microsoft Graph application
permission `EntitlementManagement.ReadWrite.All`; check 0.2 reads it and STOPS the run before anything
is written when it is missing, and the prerequisite script refuses its setup the same way. The group and
the resource group with its Logic App use the rights `oer-live-cc` used in Sprint 11 step 2 (a group and
a tagged resource group). Granting a permission is the operator's decision, never this checklist's.

**Sign-ins.** Every block's sign-in goes through `Connect-OerLive -Arm`, which runs `Disconnect-OER`
and `Disconnect-MgGraph` first and then checks the identity as True/False, and every block installs
the no-prompt fence (H.1) right after it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s113/`, which
is git-ignored. Every block prints through the library's redactor, so its lines are already redacted
per [README.md](README.md). **No credential, token, application id, tenant id, subscription id,
account or certificate thumbprint is ever printed.** The Logic App's trigger URL carries a signature:
it is read only inside the prerequisite script, without the signature, and never printed; every
printed policy has each `url` value replaced by `(url not printed)` (H.1, `ConvertTo-S113Safe`). A
`What if:` line, a warning and an error that stops a script go straight to the host, so each block is
run in its own process whose WHOLE output (standard output and standard error) is written to a file
under `raw\s113\`, redacted with OerLive's redactor before anyone reads it, and then deleted. A
response key that joins a property name and the OData context annotation (the name, an at sign,
then `odata.context`) is read by the redactor as an address and printed as `person1@example.com`; it is not one.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. Renames the engine cannot do are refused, and the plan for a new catalog is honest** ("fix:
  refuse previousDisplayName where renaming is unsupported and plan packages in a new catalog").
  `Test-OERStructure` reports `previousDisplayName` in `administrativeUnits`, `catalogs`,
  `accessPackages`, their `assignmentPolicies` and `accessReviews` as an `Error`: only groups can be
  renamed through the document, and the engine would otherwise create a new object beside the old one.
  A `-WhatIf` plan for an access package in a catalog the same document creates says `would create` for
  the package and its policies instead of `Failed ... NOT created`; a real run is unchanged.
- **B. A policy update keeps what Microsoft Graph would drop** ("fix: keep custom extension stages and
  automatic assignment settings on a policy update"). Section 1 measured that a description-only
  update through `Set-OERAccessPackageAssignmentPolicy` removed a policy's custom extension stage, and
  that an automatic assignment policy could not be updated at all. The cmdlet now reads the stages with
  their custom extension and sends them back, and sends an automatic policy's
  `automaticRequestSettings` back while `-RequestorScope` is not passed.
- **C. `mailNickname` is validated, and an alias that cannot be derived is refused** ("fix: validate
  mailNickname and refuse a mail alias that cannot be derived"). The validator refuses an alias Microsoft
  Graph refuses (measured in section 1) and warns when a renamed group keeps the alias derived from its
  old name or declares none; `New-OERGroup` refuses to derive an empty alias or one longer than 64
  characters (`DerivedMailNicknameInvalid`).
- **D. A scope with a dot segment, a `%` escape or white space is refused** ("fix: refuse a scope
  spelled with a dot segment, a percent escape or white space"), in `roleAssignments` and
  `roleManagementPolicies`; the `mg:`, `sub:` and `subscription:` forms are not affected.
- **E. The texts** ("docs: say that only groups rename and how aliases, scopes and policy updates
  behave", "docs: say which mailNickname values Microsoft Graph was measured to refuse",
  "fix: say what the validator refuses in a mail alias and a scope, and word the rename refusal
  exactly" and "docs: record that a resource name with a space cannot be declared in a scope"). The last two
  also give the scope's white-space Error a way out: a resource whose name holds white space -- some
  Azure resource types allow one inside a name -- cannot be declared in a document, so such an entry is
  removed.

A live tenant is needed for B because the claim is about what Microsoft Graph does with a PUT: what it
removes, what it refuses and what it keeps. It is needed for A, C and D to show, against the real
engine and the real tenant, that a refused document writes nothing and that the plan and the run say
what the step claims.

## What this file does not check, and why

- **`-RequestorScope` on an automatic assignment policy (class B).** The cmdlet then sends no
  `automaticRequestSettings`; what Microsoft Graph does with such an update (refuse it, or turn the
  policy into a request-based one) is not measured, since the second outcome would leave the test
  policy changed in a way the teardown does not need to undo and nothing in this step depends on it.
  The unit tests named in section B hold what is sent.
- **A custom extension stage whose extension id was not read (class B).** The read always returned it;
  the refusal is proved offline.
- **An alias derived as the empty string (class B).** Every name this file may create carries the prefix,
  which derives a non-empty alias; the empty case is proved offline.
- **E, the texts (class B).** Section B names the gates that hold them.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run, holding
  `EntitlementManagement.ReadWrite.All` (0.2 reads it).
- The **built module of this branch** in the step's own worktree, built there with
  `./build.ps1 -Tasks build`, and the environment variable `OER_LIVE_REPO` naming that worktree. H.1
  sets the session's `Repo` to it, so the module loads from the worktree's build; the main clone is
  never checked out on another commit or branch (S.1 reads that it was not). Section 1 ran before any
  code of this branch existed, against the worktree's build of `main`.
- The **prerequisite objects**: check 0.3 runs `Initialize-OerS113Prereq.ps1 -WhatIf`, then
  `-Unattended` twice, with `OER_LIVE_REPO` set.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration, and defines the fences, the
counters and the readers. Nothing here signs in or writes.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s113-' -ConfigDirectory $VaultDir
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
$Em = 'v1.0/identityGovernance/entitlementManagement'
$Catalog = 'oer-s113-catalog'
$Package = 'oer-s113-ap'
$Policy = 'oer-s113-policy'
$AutoPolicy = 'oer-s113-autopolicy'
# Tenant values come from the configuration and are never printed: every line goes through the redactor.
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
# The step's raw folder as OerLive fixed it (git-ignored).
$Raw = & (Get-Module -Name OerLive) { $script:OerLive.RawFolder }
$Needed = @('EntitlementManagement.ReadWrite.All')

function Start-S113NoPrompt {
    # A token request that does not carry the certificate would be an interactive or device-code sign-in:
    # refuse it instead of opening a prompt, and count every request. A global proxy of Get-AzToken,
    # which the module calls unqualified, forwards only a request that carries -ClientCertificate.
    $global:S113TokenCalls = 0
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`nend { `$global:S113TokenCalls++; if (-not `$PSBoundParameters.ContainsKey('ClientCertificate')) { throw 'S113 fence: a token request without the certificate was refused; nothing prompts.' }; AzAuth\Get-AzToken @PSBoundParameters }"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
}

function Start-S113Count {
    # Counts every request the module sends, by method: Microsoft Graph through a global proxy of
    # Invoke-MgGraphRequest, Azure Resource Manager through one of Invoke-WebRequest. The module's
    # transports call both unqualified, so the proxies are what they reach. A request without -Method is
    # a GET. The Graph path of every request is recorded too (method and path, query dropped).
    $global:S113Graph = [System.Collections.Generic.List[string]]::new()
    $global:S113Arm = [System.Collections.Generic.List[string]]::new()
    $Record = 'if ($PSBoundParameters.ContainsKey(''Method'')) { ([string]$Method).ToUpperInvariant() } else { ''GET'' }'
    $Path = '$(try { ([uri][string]$Uri).AbsolutePath } catch { ([string]$Uri -replace ''\?.*$'', '''') })'
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S113Graph.Add((`$($Record)) + ' ' + $Path); Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { `$global:S113Arm.Add((`$($Record)) + ' ' + $Path); Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-WebRequest -Value ([scriptblock]::Create($Text))
}

function Stop-S113Count {
    # Unqualified on purpose: a scope-qualified function:global: path removes nothing (CLAUDE.md, Testing Conventions).
    foreach ($Name in 'Invoke-MgGraphRequest', 'Invoke-WebRequest') { if (Test-Path -Path "function:$Name") { Remove-Item -Path "function:$Name" } }
}

function Get-S113Sent {
    # Requests counted since Start-S113Count: totals and writes (any method but GET), with the write paths.
    $GraphWrites = @($global:S113Graph | Where-Object { -not $_.StartsWith('GET ') })
    $ArmWrites = @($global:S113Arm | Where-Object { -not $_.StartsWith('GET ') })
    "token requests: $global:S113TokenCalls; Microsoft Graph requests: $($global:S113Graph.Count), writes: $($GraphWrites.Count)$(if ($GraphWrites.Count) { " ($($GraphWrites -join ', '))" }); Azure Resource Manager requests: $($global:S113Arm.Count), writes: $($ArmWrites.Count)$(if ($ArmWrites.Count) { " ($($ArmWrites -join ', '))" })"
}

function Get-S113GrantedRole {
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

function ConvertTo-S113Canonical {
    # The value with every dictionary's keys in ordinal order, recursively: Microsoft Graph's answer arrives
    # as a hashtable whose keys enumerate in no fixed order, so two reads compare equal only in this form.
    param([AllowNull()][object]$Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $Keys = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [System.Array]::Sort($Keys, [System.StringComparer]::Ordinal)
        $Out = [ordered]@{}
        foreach ($K in $Keys) { $Out[$K] = ConvertTo-S113Canonical -Value $Value[$K] }
        return $Out
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return , @(foreach ($I in $Value) { ConvertTo-S113Canonical -Value $I })
    }
    $Value
}

function ConvertTo-S113Safe {
    # The value with every 'url' entry replaced: a Logic App trigger URL carries a signature and is never
    # printed. The redactor then handles the ids.
    param([AllowNull()][object]$Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $Out = [ordered]@{}
        foreach ($K in @($Value.Keys)) { $Out[[string]$K] = if ([string]$K -ieq 'url') { '(url not printed)' } else { ConvertTo-S113Safe -Value $Value[$K] } }
        return $Out
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return , @(foreach ($I in $Value) { ConvertTo-S113Safe -Value $I })
    }
    $Value
}

function ConvertTo-S113Json {
    param([AllowNull()][object]$Value)
    ConvertTo-Json -InputObject (ConvertTo-S113Canonical -Value (ConvertTo-S113Safe -Value $Value)) -Depth 30 -Compress
}

function Get-S113Package {
    # The id of the prefixed access package, read raw (never printed).
    param([string]$Name = $Package)
    $P = Invoke-OerLiveGraph -All -Uri ("$Em/accessPackages?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq '$Name'"))
    Assert-OerLiveOk -Response $P -Activity "Reading $Name" | Out-Null
    $Ps = @(@($P.Body['value']) | Where-Object { $null -ne $_ })
    if ($Ps.Count -ne 1) { throw "STOP: $Name matches $($Ps.Count) access packages, not one." }
    ([string]$Ps[0]['id']).ToLowerInvariant()
}

function Get-S113PolicyId {
    # The id of one prefixed policy of the package, by its exact display name (never printed).
    param([Parameter(Mandatory)][string]$PackageId, [Parameter(Mandatory)][string]$Name)
    $L = Invoke-OerLiveGraph -All -Uri ("$Em/assignmentPolicies?`$filter={0}" -f [uri]::EscapeDataString("accessPackage/id eq '$PackageId'"))
    Assert-OerLiveOk -Response $L -Activity "Reading the policies of $Package" | Out-Null
    $Pol = @(@($L.Body['value']) | Where-Object { $null -ne $_ -and [string]$_['displayName'] -ceq $Name })
    if ($Pol.Count -gt 1) { throw "STOP: $Name matches $($Pol.Count) policies, not one." }
    if ($Pol.Count -eq 0) { return $null }
    ([string]$Pol[0]['id']).ToLowerInvariant()
}

function Read-S113Policy {
    # One policy read raw, with the given query (or none); returns the body hashtable.
    param([Parameter(Mandatory)][string]$Id, [string]$Query)
    $Uri = "$Em/assignmentPolicies/$Id$(if ($Query) { "?$Query" })"
    $R = Invoke-OerLiveGraph -Uri $Uri
    Assert-OerLiveOk -Response $R -Activity "Reading a policy ($(if ($Query) { $Query } else { 'no query' }))" | Out-Null
    $R.Body
}

function New-S113Document {
    # A structure document (JSON) holding the given sections.
    param([hashtable]$Section)
    $Doc = [ordered]@{ version = '1.0' }
    foreach ($K in @($Section.Keys | Sort-Object)) { $Doc[$K] = @($Section[$K]) }
    $Doc | ConvertTo-Json -Depth 20
}

function Write-S113Rows {
    param([Parameter(Mandatory)][string]$Label, [AllowEmptyCollection()][object[]]$Rows)
    # An if-statement assignment unrolls no rows to $null, and @($null).Count is 1: drop nulls first.
    $Rows = @(@($Rows) | Where-Object { $null -ne $_ })
    Write-OerLiveStep "$Label rows: $($Rows.Count)"
    foreach ($R in @($Rows)) { Write-OerLiveStep "$Label row: $($R.Section) | $($R.Item) | $($R.Action) | $($R.Detail)" }
}

function Write-S113Validation {
    # Test-OERStructure's verdict and every finding, by severity, path and message.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json)
    $V = Test-OERStructure -Json $Json
    Write-OerLiveStep "$Label valid: $($V.Valid); errors: $(@($V.Errors | Where-Object Severity -eq 'Error').Count); warnings: $(@($V.Errors | Where-Object Severity -eq 'Warning').Count)"
    foreach ($F in @($V.Errors)) { Write-OerLiveStep "$Label finding: $($F.Severity) | $($F.Path) | $($F.Message)" }
}

function Invoke-S113Apply {
    # One Invoke-OERStructure call -- a -WhatIf plan or a run, with or without -Prune -- counted from its
    # first request to its last. The document is kept under raw\s113. Warnings are captured on the stream
    # (3>&1), where each is written once, and printed through the redactor.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Json, [switch]$Plan, [switch]$Prune)
    [System.IO.File]::WriteAllText((Join-Path $Raw ('doc-{0}.json' -f ($Label -replace '[^0-9A-Za-z.]', '_'))), $Json, [System.Text.UTF8Encoding]::new($false))
    $Params = @{ Json = $Json; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'E' }
    if ($Plan) { $Params.WhatIf = $true } else { $Params.Confirm = $false }
    if ($Prune) { $Params.Prune = $true }
    Start-S113Count
    $E = $null
    try {
        $Out = @(Invoke-OERStructure @Params 3>&1)
        $Sent = Get-S113Sent
    } finally { Stop-S113Count }
    $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
    Write-S113Rows -Label $Label -Rows @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-OerLiveStep "$Label warnings: $($Warnings.Count)"
    foreach ($T in $Warnings) { Write-OerLiveStep "$Label warning: $T" }
    $Own = @(@($E) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',Invoke-OERStructure', [System.StringComparison]::Ordinal) })
    foreach ($X in $Own) { Write-OerLiveStep "$Label error: $([string]$X.FullyQualifiedErrorId): $([string]$X.Exception.Message)" }
    Write-OerLiveStep "$Label errors of Invoke-OERStructure: $($Own.Count); other items in -ErrorVariable (counted, not printed): $(@($E).Count - $Own.Count)"
    Write-OerLiveStep "$Label sent: $Sent"
}

function Write-S113Keys {
    # The top-level keys a read returned, sorted, and how each relevant field reads.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Body)
    $Keys = [string[]]@($Body.Keys | ForEach-Object { [string]$_ })
    [System.Array]::Sort($Keys, [System.StringComparer]::Ordinal)
    Write-OerLiveStep "$Label keys ($($Keys.Count)): $($Keys -join ', ')"
    foreach ($K in 'automaticRequestSettings', 'customExtensionStageSettings', 'questions', 'reviewSettings', 'notificationSettings', 'accessPackageNotificationSettings', 'allowedTargetScope', 'specificAllowedTargets') {
        $State = if (-not $Body.ContainsKey($K)) { 'absent' } elseif ($null -eq $Body[$K]) { 'null' } else { ConvertTo-S113Json -Value $Body[$K] }
        Write-OerLiveStep "$Label $($K): $State"
    }
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
Write-OerLiveStep "The worktree's build carries A: rename refusal $(& $Has 'function Add-UnsupportedRenameFinding'); planned catalogs $(& $Has 'PlannedCatalog')"
Write-OerLiveStep "The worktree's build carries B: the expanded read $(& $Has 'customExtensionStageSettings(`$expand=customExtension)'); the automatic settings carry $(& $Has 'automaticRequestSettings')"
Write-OerLiveStep "The worktree's build carries C: alias owner $(& $Has 'function Get-OERDerivedMailNickname'); refusal id $(& $Has "'DerivedMailNicknameInvalid'")"
Write-OerLiveStep "The worktree's build carries D: scope spelling rule $(& $Has 'function Add-ScopeSegmentFinding')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree on this branch with 0 tracked changes; every mark `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone;
a `False` mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: (not run yet)

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase)); version $($M.Version)"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed`, and `The module is the worktree's
build: True`.
**Failure looks like:** "application is disabled" (STOP: the identity is disabled), or `False`.

Result: (not run yet)

### 0.2. The permission this file needs

- [ ] **0.2** `oer-live-cc` holds `EntitlementManagement.ReadWrite.All`; otherwise the run stops here.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Granted = Get-S113GrantedRole
foreach ($Name in $Needed) { Write-OerLiveStep "oer-live-cc holds $($Name): $($Granted -ccontains $Name)" }
Write-OerLiveStep "oer-live-cc holds $($Granted.Count) Microsoft Graph application permissions"
$Missing = @($Needed | Where-Object { $Granted -cnotcontains $_ })
if ($Missing.Count -gt 0) { Write-OerLiveStep "STOP: missing $($Missing -join ', ') (G11.7: granting it is the operator's decision)." }
Disconnect-OerLive
```

**Expect:** `oer-live-cc holds EntitlementManagement.ReadWrite.All: True`.
**Failure looks like:** `False` and the STOP line -- stop the run; nothing has been written.

Result: (not run yet)

### 0.3. The prerequisite objects

- [ ] **0.3** The plan writes nothing; the first run brings `oer-s113-policy` back to its full state (section 1 removed its custom extension stage) and creates whatever is missing; a second run writes nothing.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS113Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS113Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -NonInteractive -File $Script @Run
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the `-WhatIf` run ends `WhatIf: nothing was created, removed or written.` with exit code
0; the first `-Unattended` run prints `oer-s113-policy: the question is there: True; the custom
extension stage is there: False`, then `Brought oer-s113-policy back to its full state: 200.` and
`unavailable (class B): none`, exit code 0; the second finds all eight objects (`... present`), both
policies in their full state, and writes nothing (`written to the tenant: False`), exit code 0.
**Failure looks like:** a `Refusing to run:` line, an `UNAVAILABLE` line, or exit code 1 -- read the
reason; nothing past a refusal was written.

Result: (not run yet)

## 1. The measurement, before the change (DEL 1)

Run on 2026-10-13 before any code of this branch existed: the worktree's build was `main` at the
branch point (module 1.2.1), so `Set-OERAccessPackageAssignmentPolicy` is the version this branch
changes. The prerequisite script was refined three times during this section, each time on a refusal
before a write or on a measured answer (1.0); its final form is the one 0.3 runs.

### 1.0. What creating the measured objects took

- [ ] **1.0** The measured objects exist: the automatic assignment policy is accepted, and the custom extension needs the Logic App's trigger URL and an authorization policy on the Logic App.

```powershell
$Script = Join-Path $env:OER_LIVE_DIR 'Initialize-OerS113Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "=== Initialize-OerS113Prereq.ps1 $($Run -join ' ') ==="
    & pwsh -NoProfile -NonInteractive -File $Script @Run
    Write-OerLiveStep "exit code: $LASTEXITCODE"
}
```

**Expect:** the objects are created; any refusal is recorded with Microsoft Graph's answer.
**Failure looks like:** a refusal this file cannot work around without another permission (then the
case is class B).

Result: (not run yet)

### 1.1. What a read of a policy returns, with and without `$expand`

- [ ] **1.1** The reads return `automaticRequestSettings`, `questions` and `customExtensionStageSettings` without a query; `$expand=questions` is refused.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$PackageId = Get-S113Package
foreach ($Name in $Policy, $AutoPolicy) {
    $Id = Get-S113PolicyId -PackageId $PackageId -Name $Name
    if (-not $Id) { Write-OerLiveStep "$($Name): not present"; continue }
    foreach ($Query in @('', '$expand=accessPackage', '$select=id,questions', '$expand=customExtensionStageSettings', '$expand=customExtensionStageSettings($expand=customExtension)', '$expand=catalog', '$expand=accessPackage,customExtensionStageSettings')) {
        $Label = "$Name [$(if ($Query) { $Query } else { 'no query' })]"
        $R = Invoke-OerLiveGraph -Uri "$Em/assignmentPolicies/$Id$(if ($Query) { "?$Query" })"
        if (-not $R.Ok) { Write-OerLiveStep "$Label answered $($R.Status) $($R.Code) -- $($R.Message)"; continue }
        Write-S113Keys -Label $Label -Body $R.Body
    }
}
Write-OerLiveStep "token requests: $global:S113TokenCalls"
Disconnect-OerLive
```

**Expect:** for every query but `$select=id,questions`: `automaticRequestSettings: null` on the request
policy, `questions` with the one question, `customExtensionStageSettings` present; `$expand=questions`
is not a query this block sends (see the result of 1.0); `notificationSettings` present and no
`accessPackageNotificationSettings`.
**Failure looks like:** a field missing from the module's own read (`$expand=accessPackage`).

Result: (not run yet)

### 1.2. A description-only update through the module, before the change

- [ ] **1.2** The update of the request policy removes its custom extension stage; the update of the automatic policy is refused.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$PackageId = Get-S113Package
$Fields = @('allowedTargetScope', 'specificAllowedTargets', 'automaticRequestSettings', 'customExtensionStageSettings', 'questions', 'requestorSettings', 'requestApprovalSettings', 'expiration', 'reviewSettings', 'notificationSettings', 'description', 'displayName')
$Stamp = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
foreach ($Name in $Policy, $AutoPolicy) {
    $Id = Get-S113PolicyId -PackageId $PackageId -Name $Name
    if (-not $Id) { Write-OerLiveStep "$($Name): not present"; continue }
    $Expand = '$expand=customExtensionStageSettings($expand=customExtension)'
    $Before = Read-S113Policy -Id $Id -Query $Expand
    $Plain = Read-S113Policy -Id $Id
    Write-OerLiveStep "$Name before, read without a query: customExtensionStageSettings $(ConvertTo-S113Json -Value $Plain['customExtensionStageSettings'])"
    Write-OerLiveStep "$Name before, read with the module's own query (`$expand=accessPackage): customExtensionStageSettings $(ConvertTo-S113Json -Value (Read-S113Policy -Id $Id -Query '$expand=accessPackage')['customExtensionStageSettings'])"
    foreach ($F in $Fields) { Write-OerLiveStep "$Name before $($F): $(if ($Before.ContainsKey($F)) { ConvertTo-S113Json -Value $Before[$F] } else { 'absent' })" }

    # The update: Set-OERAccessPackageAssignmentPolicy changing only the description. The body the module
    # sends is recorded by key (never printed whole: it carries ids, which the redactor would number anyway).
    $global:S113PutKeys = $null
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { if ([string]`$Method -eq 'PUT') { `$B = if (`$Body -is [string]) { `$Body | ConvertFrom-Json -AsHashtable } else { `$Body }; `$global:S113PutKeys = @(`$B.Keys | ForEach-Object { [string]`$_ } | Sort-Object) }; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $E = $null
    try {
        $Out = Set-OERAccessPackageAssignmentPolicy -Id $Id -DisplayName $Name -Description "Updated by the step 3 measurement at $Stamp" -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable E
    } finally { if (Test-Path -Path 'function:Invoke-MgGraphRequest') { Remove-Item -Path 'function:Invoke-MgGraphRequest' } }
    Write-OerLiveStep "$Name update: output objects $(@($Out).Count); errors $(@($E).Count)$(if (@($E).Count) { " -- $(@($E)[0].FullyQualifiedErrorId): $(@($E)[0].Exception.Message)" })"
    Write-OerLiveStep "$Name update: the PUT body the module sent has the keys: $(@($global:S113PutKeys) -join ', ')"
    Start-Sleep -Seconds 5
    $After = Read-S113Policy -Id $Id -Query $Expand
    foreach ($F in $Fields) {
        $B = if ($Before.ContainsKey($F)) { ConvertTo-S113Json -Value $Before[$F] } else { 'absent' }
        $A = if ($After.ContainsKey($F)) { ConvertTo-S113Json -Value $After[$F] } else { 'absent' }
        Write-OerLiveStep "$Name after $($F): $A$(if ($A -ceq $B) { ' (unchanged)' } else { ' (CHANGED)' })"
    }
}
Write-OerLiveStep "token requests: $global:S113TokenCalls"
Disconnect-OerLive
```

**Expect:** a measurement, not a pass mark: what the PUT body carried, and for each field whether it
read back unchanged.
**Failure looks like:** an error that is not Microsoft Graph's answer to the PUT.

Result: (not run yet)

### 1.3. Why the automatic policy's update was refused

- [ ] **1.3** Microsoft Graph's answer to the automatic policy's update, as the module records it.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$PackageId = Get-S113Package
$Id = Get-S113PolicyId -PackageId $PackageId -Name $AutoPolicy
$Stamp = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
$E = $null
$Out = Set-OERAccessPackageAssignmentPolicy -Id $Id -DisplayName $AutoPolicy -Description "Updated by the step 3 measurement at $Stamp" -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable E
Write-OerLiveStep "$AutoPolicy update: output objects $(@($Out).Count); records in -ErrorVariable: $(@($E).Count)"
$I = 0
foreach ($X in @($E)) {
    $I++
    $Fq = if ($X -is [System.Management.Automation.ErrorRecord]) { [string]$X.FullyQualifiedErrorId } else { "(not an ErrorRecord: $($X.GetType().FullName))" }
    $Msg = if ($X -is [System.Management.Automation.ErrorRecord]) { [string]$X.Exception.Message } else { [string]$X }
    $Det = if ($X -is [System.Management.Automation.ErrorRecord] -and $X.ErrorDetails) { [string]$X.ErrorDetails.Message } else { '' }
    Write-OerLiveStep "record $I`: $Fq -- $Msg$(if ($Det) { " -- details: $Det" })"
}
Write-OerLiveStep "token requests: $global:S113TokenCalls"
Disconnect-OerLive
```

**Expect:** Microsoft Graph's error code and message.
**Failure looks like:** no record.

Result: (not run yet)

### 1.4. The same body with the automatic settings carried, sent raw

- [ ] **1.4** The combined `$expand` read is accepted, and the body the module builds plus `automaticRequestSettings` is accepted and keeps them.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$PackageId = Get-S113Package
$PolId = Get-S113PolicyId -PackageId $PackageId -Name $Policy
$AutoId = Get-S113PolicyId -PackageId $PackageId -Name $AutoPolicy
# 1. The combined query the module would read with.
$Q = '$expand=accessPackage,customExtensionStageSettings($expand=customExtension)'
$R = Invoke-OerLiveGraph -Uri "$Em/assignmentPolicies/$PolId`?$Q"
Write-OerLiveStep "Combined query on $Policy answered $($R.Status) $($R.Code); accessPackage id present: $([bool]($R.Ok -and $R.Body['accessPackage'] -and $R.Body['accessPackage']['id'])); stages: $(if ($R.Ok) { @($R.Body['customExtensionStageSettings']).Count } else { 'unread' }); every stage names its custom extension's id and type: $(if ($R.Ok) { @(@($R.Body['customExtensionStageSettings']) | Where-Object { -not ($_['customExtension'] -and $_['customExtension']['id'] -and $_['customExtension']['@odata.type']) }).Count -eq 0 } else { 'unread' })"
# 2. The body the module builds today for a description-only update of the automatic policy, plus the
# live automaticRequestSettings, sent raw: does Microsoft Graph accept it and keep the settings?
$Existing = Read-S113Policy -Id $AutoId -Query '$expand=accessPackage'
$Stamp = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
$Body = & (Get-Module -Name Omnicit.EntraRBAC) { param($E, $P, $N, $D) ConvertTo-OERPolicyBody -DisplayName $N -AccessPackageId $P -Existing $E -Description $D } $Existing $PackageId $AutoPolicy "Updated by the step 3 measurement M.3 at $Stamp"
$Body.id = $AutoId
$Body.automaticRequestSettings = $Existing['automaticRequestSettings']
Write-OerLiveStep "M.3 body keys: $(@($Body.Keys | ForEach-Object { [string]$_ } | Sort-Object) -join ', ')"
$P = Invoke-OerLiveGraph -Method PUT -Uri "$Em/assignmentPolicies/$AutoId" -Body $Body
Write-OerLiveStep "M.3 PUT of $AutoPolicy with automaticRequestSettings carried answered $($P.Status) $($P.Code)$(if ($P.Message) { " -- $($P.Message)" })"
Start-Sleep -Seconds 5
$After = Read-S113Policy -Id $AutoId
foreach ($F in 'automaticRequestSettings', 'specificAllowedTargets', 'allowedTargetScope', 'description') {
    Write-OerLiveStep "M.3 $AutoPolicy after $($F): $(ConvertTo-S113Json -Value $After[$F])$(if ((ConvertTo-S113Json -Value $After[$F]) -ceq (ConvertTo-S113Json -Value $Existing[$F])) { ' (unchanged)' } else { ' (CHANGED)' })"
}
Write-OerLiveStep "token requests: $global:S113TokenCalls"
Disconnect-OerLive
```

**Expect:** a measurement: the read's status, the PUT's status and each field read back.
**Failure looks like:** a refusal of the read or the PUT.

Result: (not run yet)

### 1.5. Which mailNickname values Microsoft Graph accepts

- [ ] **1.5** One PATCH per character, 64 and 65 characters and the empty string on `oer-s113-grp-old`, then the alias is put back.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$GroupName = 'oer-s113-grp-old'
$G = Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id,mailNickname" -f [uri]::EscapeDataString("displayName eq '$GroupName'"))
Assert-OerLiveOk -Response $G -Activity "Reading $GroupName" | Out-Null
$Rows = @(@($G.Body['value']) | Where-Object { $null -ne $_ })
if ($Rows.Count -ne 1) { throw "STOP: $GroupName matches $($Rows.Count) groups." }
$GroupId = [string]$Rows[0]['id']
Write-OerLiveStep "$GroupName mailNickname before: $([string]$Rows[0]['mailNickname'])"
$Candidates = [System.Collections.Generic.List[object]]::new()
foreach ($C in @('.', '-', '_', '/', "'", '@', '(', ')', '\', '[', ']', '"', ';', ':', '<', '>', ',', ' ', '~', '!', '#', '$', '%', '&', '*', '+', '=', '?', '^', '`', '{', '|', '}')) {
    $Candidates.Add([PSCustomObject]@{ Label = "character '$C' (U+$(([int][char]$C).ToString('X4')))"; Value = "oer-s113-x$($C)y" })
}
$Candidates.Add([PSCustomObject]@{ Label = 'character U+00E5 (a with ring, not ASCII)'; Value = "oer-s113-x$([char]0x00E5)y" })
$Candidates.Add([PSCustomObject]@{ Label = 'character U+0009 (tab, an ASCII control character)'; Value = "oer-s113-x$([char]0x0009)y" })
$Candidates.Add([PSCustomObject]@{ Label = 'length 64'; Value = 'oer-s113-' + ('a' * 55) })
$Candidates.Add([PSCustomObject]@{ Label = 'length 65'; Value = 'oer-s113-' + ('a' * 56) })
$Candidates.Add([PSCustomObject]@{ Label = 'the empty string'; Value = '' })
foreach ($Cand in $Candidates) {
    $R = Invoke-OerLiveGraph -Method PATCH -Uri "v1.0/groups/$GroupId" -Body @{ mailNickname = $Cand.Value }
    Write-OerLiveStep "mailNickname with $($Cand.Label) (length $($Cand.Value.Length)): $($R.Status)$(if (-not $R.Ok) { " $($R.Code) -- $($R.Message)" })"
}
$Back = Invoke-OerLiveGraph -Method PATCH -Uri "v1.0/groups/$GroupId" -Body @{ mailNickname = $GroupName }
Write-OerLiveStep "Restored the mailNickname to $($GroupName): $($Back.Status)"
$null = Wait-OerLiveConverged -Activity "$GroupName mailNickname reads $GroupName again" -Read { [string](Invoke-OerLiveGraph -Uri "v1.0/groups/$GroupId`?`$select=mailNickname").Body['mailNickname'] } -Test { $args[0] -ceq $GroupName }
Write-OerLiveStep "token requests: $global:S113TokenCalls"
Disconnect-OerLive
```

**Expect:** a measurement: the status of each PATCH, and `Restored the mailNickname to
oer-s113-grp-old: 204`.
**Failure looks like:** the alias not put back.

Result: (not run yet)

## 2. A policy update keeps what Microsoft Graph would drop

### 2.1. A description-only update through the module keeps the stage and the automatic settings

- [ ] **2.1** The request policy's update sends its custom extension stage and keeps it; the automatic policy's update is accepted and keeps `automaticRequestSettings`.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$PackageId = Get-S113Package
$Fields = @('allowedTargetScope', 'specificAllowedTargets', 'automaticRequestSettings', 'customExtensionStageSettings', 'questions', 'requestorSettings', 'requestApprovalSettings', 'expiration', 'reviewSettings', 'notificationSettings', 'description', 'displayName')
$Stamp = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
foreach ($Name in $Policy, $AutoPolicy) {
    $Id = Get-S113PolicyId -PackageId $PackageId -Name $Name
    if (-not $Id) { Write-OerLiveStep "$($Name): not present"; continue }
    $Expand = '$expand=customExtensionStageSettings($expand=customExtension)'
    $Before = Read-S113Policy -Id $Id -Query $Expand
    $Plain = Read-S113Policy -Id $Id
    Write-OerLiveStep "$Name before, read without a query: customExtensionStageSettings $(ConvertTo-S113Json -Value $Plain['customExtensionStageSettings'])"
    Write-OerLiveStep "$Name before, read with the module's own query (`$expand=accessPackage): customExtensionStageSettings $(ConvertTo-S113Json -Value (Read-S113Policy -Id $Id -Query '$expand=accessPackage')['customExtensionStageSettings'])"
    foreach ($F in $Fields) { Write-OerLiveStep "$Name before $($F): $(if ($Before.ContainsKey($F)) { ConvertTo-S113Json -Value $Before[$F] } else { 'absent' })" }

    # The update: Set-OERAccessPackageAssignmentPolicy changing only the description. The body the module
    # sends is recorded by key (never printed whole: it carries ids, which the redactor would number anyway).
    $global:S113PutKeys = $null
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-MgGraphRequest -CommandType Cmdlet))
    $Text = [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta) + "`nparam(" + [System.Management.Automation.ProxyCommand]::GetParamBlock($Meta) + ")`nend { if ([string]`$Method -eq 'PUT') { `$B = if (`$Body -is [string]) { `$Body | ConvertFrom-Json -AsHashtable } else { `$Body }; `$global:S113PutKeys = @(`$B.Keys | ForEach-Object { [string]`$_ } | Sort-Object) }; Microsoft.Graph.Authentication\Invoke-MgGraphRequest @PSBoundParameters }"
    Set-Item -Path function:global:Invoke-MgGraphRequest -Value ([scriptblock]::Create($Text))
    $E = $null
    try {
        $Out = Set-OERAccessPackageAssignmentPolicy -Id $Id -DisplayName $Name -Description "Updated by the step 3 measurement at $Stamp" -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable E
    } finally { if (Test-Path -Path 'function:Invoke-MgGraphRequest') { Remove-Item -Path 'function:Invoke-MgGraphRequest' } }
    Write-OerLiveStep "$Name update: output objects $(@($Out).Count); errors $(@($E).Count)$(if (@($E).Count) { " -- $(@($E)[0].FullyQualifiedErrorId): $(@($E)[0].Exception.Message)" })"
    Write-OerLiveStep "$Name update: the PUT body the module sent has the keys: $(@($global:S113PutKeys) -join ', ')"
    Start-Sleep -Seconds 5
    $After = Read-S113Policy -Id $Id -Query $Expand
    foreach ($F in $Fields) {
        $B = if ($Before.ContainsKey($F)) { ConvertTo-S113Json -Value $Before[$F] } else { 'absent' }
        $A = if ($After.ContainsKey($F)) { ConvertTo-S113Json -Value $After[$F] } else { 'absent' }
        Write-OerLiveStep "$Name after $($F): $A$(if ($A -ceq $B) { ' (unchanged)' } else { ' (CHANGED)' })"
    }
}
Write-OerLiveStep "token requests: $global:S113TokenCalls"
Disconnect-OerLive
```

**Expect:** for `oer-s113-policy`: `update: output objects 1; errors 0`, the PUT body's keys include
`customExtensionStageSettings` (and not `automaticRequestSettings`, which is null on a request policy),
`after customExtensionStageSettings: ... (unchanged)` naming `oer-s113-ext`, `after questions: ...
(unchanged)`, and only `description` `(CHANGED)`. For `oer-s113-autopolicy`: `update: output objects
1; errors 0`, the PUT body's keys include `automaticRequestSettings`, `after automaticRequestSettings:
... (unchanged)`, `after specificAllowedTargets: ... (unchanged)`, and only `description` `(CHANGED)`.
**Failure looks like:** `after customExtensionStageSettings: [] (CHANGED)` (the stage removed again), or
an error `InvalidSpecificAllowedTargets` for the automatic policy (1.2 and 1.3, before the change).

Result: (not run yet)

### 2.2. The same through the document, three times (G8)

- [ ] **2.2** A document changing both policies' descriptions updates them once and keeps the stage and the automatic settings; the second and third runs report only `Unchanged` and write nothing.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$PackageId = Get-S113Package
$PolId = Get-S113PolicyId -PackageId $PackageId -Name $Policy
$AutoId = Get-S113PolicyId -PackageId $PackageId -Name $AutoPolicy
$Expand = '$expand=customExtensionStageSettings($expand=customExtension)'
$Before = @{ policy = Read-S113Policy -Id $PolId -Query $Expand; auto = Read-S113Policy -Id $AutoId }
$Text = 'Updated through the document by check 2.2'
$Doc = New-S113Document -Section @{ accessPackages = @([ordered]@{
            displayName = $Package; catalog = $Catalog; hidden = $true
            assignmentPolicies = @([ordered]@{ displayName = $Policy; description = $Text }, [ordered]@{ displayName = $AutoPolicy; description = $Text })
        }) }
foreach ($Run in 1..3) {
    Invoke-S113Apply -Label "2.2 run $Run" -Json $Doc
    Start-Sleep -Seconds 15
}
$After = @{ policy = Read-S113Policy -Id $PolId -Query $Expand; auto = Read-S113Policy -Id $AutoId }
foreach ($Pair in @(@('policy', 'customExtensionStageSettings'), @('policy', 'questions'), @('auto', 'automaticRequestSettings'), @('auto', 'specificAllowedTargets'), @('policy', 'description'), @('auto', 'description'))) {
    $B = ConvertTo-S113Json -Value $Before[$Pair[0]][$Pair[1]]
    $A = ConvertTo-S113Json -Value $After[$Pair[0]][$Pair[1]]
    Write-OerLiveStep "2.2 $($Pair[0]) $($Pair[1]) after the three runs: $A$(if ($A -ceq $B) { ' (unchanged)' } else { ' (CHANGED)' })"
}
Write-OerLiveStep "token requests: $global:S113TokenCalls"
Disconnect-OerLive
```

**Expect:** run 1: `accessPackages | oer-s113-ap | Updated | ...` for each of the two policies (and the
package itself `Unchanged`), `writes: 2` (two PUT); runs 2 and 3: only `Unchanged` rows and `writes: 0`.
Afterwards the stage, the question, the automatic settings and the targets `(unchanged)`, the two
descriptions `(CHANGED)` to the document's text.
**Failure looks like:** a write in run 2 or 3 (the document does not converge), or the stage or the
automatic settings `(CHANGED)`.

Result: (not run yet)

## 3. An access package in a catalog the same document creates

### 3.1. The validator accepts the document

- [ ] **3.1** `Test-OERStructure` reports the document valid.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = New-S113Document -Section @{
    catalogs       = @([ordered]@{ displayName = 'oer-s113-newcat'; description = 'Omnicit.EntraRBAC live verification (oer-s113-): a catalog the document creates.' })
    accessPackages = @([ordered]@{
            displayName = 'oer-s113-newap'; catalog = 'oer-s113-newcat'; hidden = $true
            description = 'Omnicit.EntraRBAC live verification (oer-s113-): a package in a catalog the same document creates.'
            assignmentPolicies = @([ordered]@{
                    displayName = 'oer-s113-newpol'; description = 'Omnicit.EntraRBAC live verification (oer-s113-): only the members of oer-s113-grp-old (none) may request.'
                    requestorScope = [ordered]@{ scope = 'SpecificDirectoryUsers'; groups = @('oer-s113-grp-old') }
                })
        })
}
[System.IO.File]::WriteAllText((Join-Path $Raw 'doc-section3.json'), $Doc, [System.Text.UTF8Encoding]::new($false))
Write-S113Validation -Label '3.1' -Json $Doc
Disconnect-OerLive
```

**Expect:** `3.1 valid: True; errors: 0`.
**Failure looks like:** an `Error` finding.

Result: (not run yet)

### 3.2. The plan says "would create" for the catalog, the package and the policy

- [ ] **3.2** `Invoke-OERStructure -WhatIf` plans the catalog, the package and its policy as created, with no `Failed` row and no write.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section3.json') -Raw
Invoke-S113Apply -Label '3.2 plan' -Json $Doc -Plan
Disconnect-OerLive
```

**Expect:** `catalogs | oer-s113-newcat | Skipped | would create catalog oer-s113-newcat`,
`accessPackages | oer-s113-newap | Skipped | would create access package oer-s113-newap` and
`accessPackages | oer-s113-newap | Skipped | would create assignmentPolicy 'oer-s113-newpol' after
access package is created`; no `Failed` row; `errors of Invoke-OERStructure: 0`; `writes: 0`.
**Failure looks like:** `Failed | failed to look up access packages in catalog 'oer-s113-newcat': ...
the access package was NOT created` (the plan before this branch).

Result: (not run yet)

### 3.3. The run creates them

- [ ] **3.3** The same document, applied, creates the catalog, the package and the policy.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section3.json') -Raw
Invoke-S113Apply -Label '3.3 run' -Json $Doc
Disconnect-OerLive
```

**Expect:** `catalogs | oer-s113-newcat | Created | ...`, `accessPackages | oer-s113-newap | Created |
...` and a `Created` row for `oer-s113-newpol`; no `Failed` row; writes 3 or more (the catalog, the
package and the policy POST).
**Failure looks like:** a `Failed` row -- a catalog lookup right after its creation can lag (record the
answer; a rerun of 3.3 is then the convergence check).

Result: (not run yet)

### 3.4. The same document twice more: only Unchanged (G8)

- [ ] **3.4** Two more runs report only `Unchanged` and write nothing.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section3.json') -Raw
Start-Sleep -Seconds 30
Invoke-S113Apply -Label '3.4 run 2' -Json $Doc
Start-Sleep -Seconds 15
Invoke-S113Apply -Label '3.4 run 3' -Json $Doc
Disconnect-OerLive
```

**Expect:** both runs: only `Unchanged` rows (the catalog, the package and the policy), `writes: 0`.
**Failure looks like:** a write in either run.

Result: (not run yet)

## 4. previousDisplayName on an administrative unit is refused

### 4.1. The validator refuses it

- [ ] **4.1** `Test-OERStructure` reports `previousDisplayName` on an administrative unit as an `Error`.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = New-S113Document -Section @{ administrativeUnits = @([ordered]@{ displayName = 'oer-s113-au-new'; previousDisplayName = 'oer-s113-au-old'; description = 'Omnicit.EntraRBAC live verification (oer-s113-): must never be created.' }) }
[System.IO.File]::WriteAllText((Join-Path $Raw 'doc-section4.json'), $Doc, [System.Text.UTF8Encoding]::new($false))
Write-S113Validation -Label '4.1' -Json $Doc
Disconnect-OerLive
```

**Expect:** `4.1 valid: False; errors: 1`, the finding `Error | administrativeUnits[0].previousDisplayName
| 'previousDisplayName' at administrativeUnits[0] is not supported for an administrative unit yet: ...`
saying that only groups can be renamed and that the engine would create a new administrative unit.
**Failure looks like:** `valid: True` (the key was ignored before this branch).

Result: (not run yet)

### 4.2. Invoke-OERStructure writes nothing, planned or applied

- [ ] **4.2** `Invoke-OERStructure`, with `-WhatIf` and without, refuses the document before it signs in, and no administrative unit with the prefix exists afterwards.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section4.json') -Raw
Invoke-S113Apply -Label '4.2 plan' -Json $Doc -Plan
Invoke-S113Apply -Label '4.2 run' -Json $Doc
$null = @(Find-OerLivePrefixed)
Disconnect-OerLive
```

**Expect:** both: rows 0, `error: StructureValidationFailed,Invoke-OERStructure: ...` naming the
finding, `token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests:
0, writes: 0`; the sweep lists no administrative unit with the prefix.
**Failure looks like:** a request, or a `Created` row for `oer-s113-au-new`.

Result: (not run yet)

## 5. A renamed group and its mail alias

### 5.1. The validator: a renamed group's alias

- [ ] **5.1** A rename with no `mailNickname`, or with the alias derived from the old name, is a `Warning`; a new alias is not; an alias Microsoft Graph refuses is an `Error`.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Base = [ordered]@{ displayName = 'oer-s113-grp-new'; previousDisplayName = 'oer-s113-grp-old' }
$Cases = [ordered]@{
    'a no mailNickname'         = $Base
    'b the old derived alias'   = [ordered]@{ displayName = 'oer-s113-grp-new'; previousDisplayName = 'oer-s113-grp-old'; mailNickname = 'oer-s113-grp-old' }
    'c a new alias'             = [ordered]@{ displayName = 'oer-s113-grp-new'; previousDisplayName = 'oer-s113-grp-old'; mailNickname = 'oer-s113-grp-new' }
    'd an alias Graph refuses'  = [ordered]@{ displayName = 'oer-s113-grp-new'; previousDisplayName = 'oer-s113-grp-old'; mailNickname = 'oer-s113 grp(new)' }
}
foreach ($Key in $Cases.Keys) {
    $Doc = New-S113Document -Section @{ groups = @($Cases[$Key]) }
    if ($Key -like 'a *') { [System.IO.File]::WriteAllText((Join-Path $Raw 'doc-section5.json'), $Doc, [System.Text.UTF8Encoding]::new($false)) }
    Write-S113Validation -Label "5.1 $Key" -Json $Doc
}
Disconnect-OerLive
```

**Expect:** a: `valid: True; errors: 0; warnings: 1`, the Warning at `groups[0].mailNickname` saying the
group declares no mailNickname and that the alias does not follow a rename; b: the same with the
Warning that `'oer-s113-grp-old'` is the alias derived from the old name; c: `warnings: 0`; d:
`valid: False`, an `Error` at `groups[0].mailNickname` naming the space and the parentheses.
**Failure looks like:** no Warning for a or b, or `valid: True` for d.

Result: (not run yet)

### 5.2. The plan renames the group and writes nothing

- [ ] **5.2** `Invoke-OERStructure -WhatIf` with document a plans the rename, writes nothing, and the group still carries its old name and alias.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section5.json') -Raw
Invoke-S113Apply -Label '5.2 plan' -Json $Doc -Plan
$G = Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=displayName,mailNickname" -f [uri]::EscapeDataString("startswith(displayName,'oer-s113-grp-')"))
Assert-OerLiveOk -Response $G -Activity 'Reading the prefixed groups' | Out-Null
foreach ($Row in @($G.Body['value'])) { Write-OerLiveStep "5.2 after: group $([string]$Row['displayName']) mailNickname $([string]$Row['mailNickname'])" }
Disconnect-OerLive
```

**Expect:** a row `groups | oer-s113-grp-new | Skipped | would rename ...` (the planned rename), the
validator's Warning about the alias among the warnings, `writes: 0`; afterwards exactly one group,
`oer-s113-grp-old`, with mailNickname `oer-s113-grp-old`.
**Failure looks like:** a write, or the group renamed.

Result: (not run yet)

## 6. A scope with a dot segment is refused

### 6.1. The validator refuses the spelling and accepts the plain path

- [ ] **6.1** A scope with a `..` or `.` segment, a `%` escape or white space is an `Error` in `roleAssignments` and in `roleManagementPolicies`; the same scope written plainly is valid.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Rg = "$SubScope/resourceGroups/oer-s113-rg"
$Bad = New-S113Document -Section @{
    roleAssignments        = @(
        [ordered]@{ scope = "$SubScope/resourceGroups/oer-s113-x/../oer-s113-rg"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
        [ordered]@{ scope = "$Rg/%2e"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
        [ordered]@{ scope = "$SubScope/resourceGroups/oer-s113 rg"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
    )
    roleManagementPolicies = @([ordered]@{ scope = "$SubScope/./resourceGroups/oer-s113-rg"; role = 'Reader' })
}
[System.IO.File]::WriteAllText((Join-Path $Raw 'doc-section6.json'), $Bad, [System.Text.UTF8Encoding]::new($false))
Write-S113Validation -Label '6.1 spelled' -Json $Bad
$Good = New-S113Document -Section @{ roleAssignments = @([ordered]@{ scope = $Rg; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }) }
Write-S113Validation -Label '6.1 plain' -Json $Good
Disconnect-OerLive
```

**Expect:** spelled: `valid: False`, an `Error` at `roleAssignments[0].scope` (a `'.' or '..'
segment`), at `roleAssignments[1].scope` (a `'%' escape`), at `roleAssignments[2].scope` (`white
space`) and at `roleManagementPolicies[0].scope` (a segment); plain: `valid: True; errors: 0`.
**Failure looks like:** `valid: True` for the spelled document (before this branch only a trailing or
doubled `/` was refused).

Result: (not run yet)

### 6.2. Invoke-OERStructure writes nothing, with -Prune, planned or applied

- [ ] **6.2** `Invoke-OERStructure -Prune`, with `-WhatIf` and without, refuses the document before it signs in and sends no request, and no role assignment exists at `oer-s113-rg` afterwards.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section6.json') -Raw
Invoke-S113Apply -Label '6.2 plan' -Json $Doc -Plan -Prune
Invoke-S113Apply -Label '6.2 run' -Json $Doc -Prune
$Ra = Invoke-OerLiveArm -All -Path "$SubScope/resourceGroups/oer-s113-rg/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
Assert-OerLiveOk -Response $Ra -Activity 'Listing the role assignments at oer-s113-rg' | Out-Null
$At = @(@($Ra.Body.value) | Where-Object { $null -ne $_ -and [string]::Equals(([string]$_.properties.scope).TrimEnd('/'), "$SubScope/resourceGroups/oer-s113-rg", [System.StringComparison]::OrdinalIgnoreCase) })
Write-OerLiveStep "6.2 role assignments exactly at oer-s113-rg afterwards: $($At.Count)"
Disconnect-OerLive
```

**Expect:** both: rows 0, `error: StructureValidationFailed,Invoke-OERStructure: ...`, `token requests:
0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0`; then `role
assignments exactly at oer-s113-rg afterwards: 0`.
**Failure looks like:** any request, or a role assignment at the resource group.

Result: (not run yet)

## 7. New-OERGroup refuses an alias it cannot derive

### 7.1. A name whose derived alias is too long

- [ ] **7.1** `New-OERGroup` with a 69-character prefixed name and no `-MailNickname` writes `DerivedMailNicknameInvalid` and creates nothing; only the existence lookup is sent.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$LongName = 'oer-s113-' + ('g' * 60)
Assert-OerLivePrefix -Name $LongName
Start-S113Count
$E = $null
try { $Out = New-OERGroup -DisplayName $LongName -ErrorAction SilentlyContinue -ErrorVariable E } finally { $Sent = Get-S113Sent; Stop-S113Count }
$Own = @(@($E) | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(',New-OERGroup', [System.StringComparison]::Ordinal) })
Write-OerLiveStep "7.1 output objects: $(@($Out).Count); errors of New-OERGroup: $($Own.Count)"
foreach ($X in $Own) { Write-OerLiveStep "7.1 error: $([string]$X.FullyQualifiedErrorId): $([string]$X.Exception.Message)" }
Write-OerLiveStep "7.1 sent: $Sent"
Write-OerLiveStep "7.1 Graph requests: $(@($global:S113Graph) -join ', ')"
$G = Invoke-OerLiveGraph -All -Uri ("v1.0/groups?`$filter={0}&`$select=id" -f [uri]::EscapeDataString("displayName eq '$LongName'"))
Assert-OerLiveOk -Response $G -Activity 'Reading the long-named group' | Out-Null
Write-OerLiveStep "7.1 groups named so afterwards: $(@(@($G.Body['value']) | Where-Object { $null -ne $_ }).Count)"
Disconnect-OerLive
```

**Expect:** `output objects: 0; errors of New-OERGroup: 1`, the error `DerivedMailNicknameInvalid,New-OERGroup:
The mail alias derived from the group name '...' is 69 characters long; Microsoft Graph accepts 1 to 64
characters. Nothing was sent. ...`; `Microsoft Graph requests: 1, writes: 0` (the existence lookup, a
GET); `groups named so afterwards: 0`.
**Failure looks like:** a POST, or Microsoft Graph's own refusal (`Request_BadRequest`), which is what
the module sent before this branch.

Result: (not run yet)

## T. Teardown

### T.1. Remove every oer-s113- object

- [ ] **T.1** The teardown deletes the policy holding the custom extension stage and the custom extension, then the policies, the packages, the catalogs and the group, then the resource group with the Logic App; the sweep finds nothing; the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS113Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `Teardown A: deleted oer-s113-ap: assignment policy 'oer-s113-policy' (it holds a custom
extension stage)` and `Teardown A: deleted custom extension oer-s113-ext`; the library's removal of the
other policies, the two packages, the two catalogs and the group with residue 0; `Teardown C: deleted
oer-s113-rg and oer-s113-la.`; every `Counts:` line `equal: True`; exit code 0.
**Failure looks like:** a `RESIDUE` line or exit code 3 -- record each residue row here.

Result: (not run yet)

### T.2. Read back

- [ ] **T.2** Nothing with the prefix is left, and the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS113Prereq.ps1') -ReadBack
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `resource group oer-s113-rg exists: False`; every `Counts:` line `equal: True`;
`prefixed objects left: 0; unread collections: 0`; no residue row with this step's prefix.
**Failure looks like:** anything left with the prefix.

Result: (not run yet)

## B. Proved offline only (class B)

- **previousDisplayName in each of the five sections, and none for groups; an explicit null is not
  reported**: the Context "previousDisplayName outside groups (BL-128, A5)" in
  `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1`.
- **The plan for a package in a new catalog, a missing catalog the document does not declare still
  Failed, a declined `-Confirm` on the catalog**: `tests/Unit/Private/Sync-OERStructureCatalog.Tests.ps1`,
  `tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1` and the engine tests in
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`.
- **What the policy update sends**: `tests/Unit/Private/ConvertTo-OERPolicyBody.Tests.ps1` (the stage in
  its update shape, no key for no stage, a stage without an extension id refused, `automaticRequestSettings`
  carried only without `-RequestorScope`) and `tests/Unit/Public/Set-OERAccessPackageAssignmentPolicy.Tests.ps1`
  (the expanded read, the PUT body, the refusal before any PUT, also under `-WhatIf` and in a runspace
  with no `try`).
- **mailNickname rules and the alias warning**: the Context on mailNickname in
  `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1`; the derivation in
  `tests/Unit/Private/Get-OERDerivedMailNickname.Tests.ps1`; `New-OERGroup`'s refusal of an empty and a
  too long derived alias, an explicit `-MailNickname` sent as given and an existing group still returned,
  in `tests/Unit/Public/New-OERGroup.Tests.ps1`, including a runspace with no `try`.
- **The scope spelling rule in both sections, the friendly forms exempt, the root interplay**: the A13
  tests in `tests/Unit/Private/Test-OERStructureSchema.Tests.ps1` and the validator-refusal test in
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`.
- **The texts**: `tests/QA/docsync.tests.ps1`, `tests/QA/about.tests.ps1`, `tests/QA/dochygiene.tests.ps1`,
  `tests/Unit/Private/Get-OERStructureSchemaJson.Tests.ps1` and
  `tests/Unit/Private/Get-OERInventoryPromptTemplate.Tests.ps1`.
