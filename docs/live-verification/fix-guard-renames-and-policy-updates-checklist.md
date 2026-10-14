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
- **F. Round 1: the scope rule is narrowed to what a resource name cannot hold, and `\`, `?` and `#`
  are refused** ("fix: accept a space inside a resource name in a scope and refuse a backslash, a
  question mark and a hash"). Decision A13 was changed on 2026-10-14: one or more spaces between other
  characters of a segment are accepted, since an Azure resource name can hold them and an export with a
  role assignment at such a resource must stay appliable; white space at the start or end of the scope
  or of a segment, white space other than a space and a control character stay refused; a `\` (read as
  `/` by the request URI), a `?` and a `#` (either ends the path) are refused; the `%` message no longer
  says every escape is decoded. Section 6 is run again for it (6.1 and 6.2, and the new 6.3 and 6.4).
- **E. The texts** ("docs: say that only groups rename and how aliases, scopes and policy updates
  behave", "docs: say which mailNickname values Microsoft Graph was measured to refuse",
  "fix: say what the validator refuses in a mail alias and a scope, and word the rename refusal
  exactly" and "docs: record that a resource name with a space cannot be declared in a scope"). The last two
  also give the scope's white-space Error a way out: a resource whose name holds white space -- some
  Azure resource types allow one inside a name -- cannot be declared in a document, so such an entry is
  removed. Round 1 (F) lifts that limit for a space between other characters of a segment.

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
Write-OerLiveStep "The worktree's build carries A: rename refusal $(& $Has 'function Add-UnsupportedRenameFinding'); planned catalogs $(& $Has 'PlannedCatalog')"
Write-OerLiveStep "The worktree's build carries B: the expanded read $(& $Has 'customExtensionStageSettings(`$expand=customExtension)'); the automatic settings carry $(& $Has 'automaticRequestSettings')"
Write-OerLiveStep "The worktree's build carries C: alias owner $(& $Has 'function Get-OERDerivedMailNickname'); refusal id $(& $Has "'DerivedMailNicknameInvalid'")"
Write-OerLiveStep "The worktree's build carries D: scope spelling rule $(& $Has 'function Add-ScopeSegmentFinding')"
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree on this branch with 0 tracked changes; every mark `True`.
**Failure looks like:** `False` on the first line -- `OER_LIVE_REPO` is unset or names the main clone;
a `False` mark -- build the worktree first (`./build.ps1 -Tasks build`), never while the gate runs.

Result: 2026-10-14 01:36 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree is on this branch at 0afad90 with 0 tracked changes, and its build (built from 4e268a5, the last commit under source/) carries every mark of A to D. The later commit of the branch changes only this checklist.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s113] The module loads from a worktree that is not the main clone: True
[oer-s113] Main clone: branch main; HEAD 491e72e
[oer-s113] Worktree: branch fix/guard-renames-and-policy-updates; HEAD 0afad90 docs: add the live checklist for refusing unsupported renames and keeping policy settings; tracked changes: 0
[oer-s113] The worktree's build carries A: rename refusal True; planned catalogs True
[oer-s113] The worktree's build carries B: the expanded read True; the automatic settings carry True
[oer-s113] The worktree's build carries C: alias owner True; refusal id True
[oer-s113] The worktree's build carries D: scope spelling rule True
RUNNER: check-S.1 exit code 0; started 2026-10-14T01:36:24Z; took 3 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, and the module is this branch's build.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc (app-only, certificate); identity check passed; the module is the worktree's build (1.2.1).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] The module is the worktree's build: True; version 1.2.1
RUNNER: check-0.1 exit code 0; started 2026-10-14T01:36:27Z; took 6 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.2. The permission this file needs

- [x] **0.2** `oer-live-cc` holds `EntitlementManagement.ReadWrite.All`; otherwise the run stops here.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. oer-live-cc holds EntitlementManagement.ReadWrite.All (19 Microsoft Graph application permissions in all); no permission was added or removed.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] oer-live-cc holds 19 Microsoft Graph application permissions
RUNNER: check-0.2 exit code 0; started 2026-10-14T01:36:33Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.3. The prerequisite objects

- [x] **0.3** The plan writes nothing; the first run brings `oer-s113-policy` back to its full state (section 1 removed its custom extension stage) and creates whatever is missing; a second run writes nothing.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan wrote nothing (it planned to bring oer-s113-policy back: section 1 had removed its custom extension stage); the first -Unattended run put the stage back (PUT 200, converged on the first read) and found every other object present (unavailable: none); the second found all eight objects in their full state and wrote nothing (written to the tenant: False). Exit code 0 each time.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s113] === Initialize-OerS113Prereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s113\prereq-20261014-013703Z.log".
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Found: oer-s113-grp-old True; oer-s113-catalog True; oer-s113-ap True; oer-s113-policy True; oer-s113-autopolicy True; oer-s113-rg True; oer-s113-la True; oer-s113-ext True.
[oer-s113] The baseline exists (groups 97, catalogs 5, access packages 6 when it was written).
[oer-s113] Group oer-s113-grp-old exists.
[oer-s113] Catalog oer-s113-catalog exists.
[oer-s113] Access package oer-s113-ap exists.
[oer-s113] Resource group oer-s113-rg exists.
[oer-s113] Logic App oer-s113-la exists; its AADPOP authorization policy is there: True
[oer-s113] Custom extension oer-s113-ext exists.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: False
What if: Performing the operation "Bring the policy back to its full state (Graph v1.0 PUT assignmentPolicies: the question and the custom extension stage)" on target "oer-s113-policy".
[oer-s113] oer-s113-autopolicy: automaticRequestSettings with requestAccessForAllowedTargets true: True
[oer-s113] Policy oer-s113-autopolicy exists in its full state.
[oer-s113] Summary: oer-s113-grp-old present; oer-s113-catalog present; oer-s113-ap present; oer-s113-rg present; oer-s113-la present; oer-s113-ext present; oer-s113-policy present; oer-s113-autopolicy present; unavailable (class B): none; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s113] WhatIf: nothing was created, removed or written.
[oer-s113] Done.
[oer-s113] exit code: 0
[oer-s113] === Initialize-OerS113Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\prereq-20261014-013710Z.log; OerLive 1.0.3.
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Found: oer-s113-grp-old True; oer-s113-catalog True; oer-s113-ap True; oer-s113-policy True; oer-s113-autopolicy True; oer-s113-rg True; oer-s113-la True; oer-s113-ext True.
[oer-s113] The baseline exists (groups 97, catalogs 5, access packages 6 when it was written).
[oer-s113] Group oer-s113-grp-old exists.
[oer-s113] Catalog oer-s113-catalog exists.
[oer-s113] Access package oer-s113-ap exists.
[oer-s113] Resource group oer-s113-rg exists.
[oer-s113] Logic App oer-s113-la exists; its AADPOP authorization policy is there: True
[oer-s113] Custom extension oer-s113-ext exists.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: False
[oer-s113] Brought oer-s113-policy back to its full state: 200.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: True
[oer-s113] oer-s113-policy holds its full state: converged after 1 read(s), 0.2 s.
[oer-s113] oer-s113-autopolicy: automaticRequestSettings with requestAccessForAllowedTargets true: True
[oer-s113] Policy oer-s113-autopolicy exists in its full state.
[oer-s113] Summary: oer-s113-grp-old present; oer-s113-catalog present; oer-s113-ap present; oer-s113-rg present; oer-s113-la present; oer-s113-ext present; oer-s113-policy present; oer-s113-autopolicy present; unavailable (class B): none; written to the tenant: True.
[oer-s113] Done.
[oer-s113] exit code: 0
[oer-s113] === Initialize-OerS113Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\prereq-20261014-013719Z.log; OerLive 1.0.3.
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Found: oer-s113-grp-old True; oer-s113-catalog True; oer-s113-ap True; oer-s113-policy True; oer-s113-autopolicy True; oer-s113-rg True; oer-s113-la True; oer-s113-ext True.
[oer-s113] The baseline exists (groups 97, catalogs 5, access packages 6 when it was written).
[oer-s113] Group oer-s113-grp-old exists.
[oer-s113] Catalog oer-s113-catalog exists.
[oer-s113] Access package oer-s113-ap exists.
[oer-s113] Resource group oer-s113-rg exists.
[oer-s113] Logic App oer-s113-la exists; its AADPOP authorization policy is there: True
[oer-s113] Custom extension oer-s113-ext exists.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: True
[oer-s113] Policy oer-s113-policy exists in its full state.
[oer-s113] oer-s113-autopolicy: automaticRequestSettings with requestAccessForAllowedTargets true: True
[oer-s113] Policy oer-s113-autopolicy exists in its full state.
[oer-s113] Summary: oer-s113-grp-old present; oer-s113-catalog present; oer-s113-ap present; oer-s113-rg present; oer-s113-la present; oer-s113-ext present; oer-s113-policy present; oer-s113-autopolicy present; unavailable (class B): none; written to the tenant: False.
[oer-s113] Done.
[oer-s113] exit code: 0
RUNNER: check-0.3 exit code 0; started 2026-10-14T01:37:00Z; took 25 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. The measurement, before the change (DEL 1)

Run on 2026-10-13 before any code of this branch existed: the worktree's build was `main` at the
branch point (module 1.2.1), so `Set-OERAccessPackageAssignmentPolicy` is the version this branch
changes. The prerequisite script was refined three times during this section, each time on a refusal
before a write or on a measured answer (1.0); its final form is the one 0.3 runs.

### 1.0. What creating the measured objects took

- [x] **1.0** The measured objects exist: the automatic assignment policy is accepted, and the custom extension needs the Logic App's trigger URL and an authorization policy on the Logic App.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: MEASURED (the objects exist; each refusal recorded). Run 1 created the group, the catalog, the package, the resource group, the Logic App and the request policy (its question accepted), then stopped on a read: Microsoft Graph refuses $expand=questions with 400 InvalidFilter ('not a navigation property or complex property'), and the custom extension was refused with 400 MissingParameters: an app-only caller must give the Logic App trigger's URL. Run 2 (the URL read from Azure Resource Manager, without its signature, never printed): the custom extension was refused with 400 WorkFlowExtensionValidationError, the Logic App answering OAuthAccessPolicyNotFound ('Authorization header is not allowed'); the automatic assignment policy was created (the tenant supports it). Run 3, with an AADPOP authorization policy on the Logic App (issuer of this tenant, method, host and the workflow's path): the custom extension was created (201) and the request policy was brought to its full state with the stage (PUT 200). So the step needs no class C check: both measured settings could be created as oer-live-cc.

=== The plan (2026-10-13 22:07 UTC) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== PREREQ -WhatIf ===
[oer-s113] === Initialize-OerS113Prereq.ps1 -WhatIf ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s113\prereq-20261013-220719Z.log".
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s113-' is left.
[oer-s113] Found: oer-s113-grp-old False; oer-s113-catalog False; oer-s113-ap False; oer-s113-policy False; oer-s113-autopolicy False; oer-s113-rg False; oer-s113-la False; oer-s113-ext False.
[oer-s113] No baseline yet: it is written now, before the first write to the tenant (groups 97, catalogs 5, access packages 6; oer-s113-rg exists: False).
What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s113\baseline-s113.json".
What if: Performing the operation "Create a security group with no member (Graph v1.0 POST groups: not role-assignable, not mail-enabled, assigned membership, mailNickname 'oer-s113-grp-old')" on target "oer-s113-grp-old".
What if: Performing the operation "Create a catalog (Graph v1.0 POST entitlementManagement/catalogs: published, not visible to external users)" on target "oer-s113-catalog".
What if: Performing the operation "Create a hidden access package (Graph v1.0 POST entitlementManagement/accessPackages: isHidden, no resource role)" on target "oer-s113-ap".
What if: Performing the operation "Create the resource group in the test subscription (Azure Resource Manager PUT, location 'swedencentral', tag purpose 'Omnicit.EntraRBAC live verification (oer-s113)')" on target "oer-s113-rg".
What if: Performing the operation "Create an assignment policy only the members of oer-s113-grp-old (none) may request through (Graph v1.0 POST assignmentPolicies: no approval, no expiration, one optional question, the custom extension stage when it exists)" on target "oer-s113-policy".
What if: Performing the operation "Create an automatic assignment policy whose rule matches no user (Graph v1.0 POST assignmentPolicies: attributeRuleMembers '(user.department -eq "oer-s113-no-such-department")', automaticRequestSettings)" on target "oer-s113-autopolicy".
[oer-s113] Summary: oer-s113-grp-old absent; oer-s113-catalog absent; oer-s113-ap absent; oer-s113-rg absent; oer-s113-la absent; oer-s113-ext absent; oer-s113-policy absent; oer-s113-autopolicy absent; unavailable (class B): none; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s113] WhatIf: nothing was created, removed or written.
[oer-s113] Done.
[oer-s113] exit code: 0
RUNNER: prereq-whatif exit code 0; started 2026-10-13T22:07:17Z; took 9 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Run 1: two -Unattended runs (refusals before a write: the questions expand, then the URL) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== PREREQ -Unattended x2 ===
[oer-s113] === Initialize-OerS113Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\prereq-20261013-220736Z.log; OerLive 1.0.3.
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s113-' is left.
[oer-s113] Found: oer-s113-grp-old False; oer-s113-catalog False; oer-s113-ap False; oer-s113-policy False; oer-s113-autopolicy False; oer-s113-rg False; oer-s113-la False; oer-s113-ext False.
[oer-s113] No baseline yet: it is written now, before the first write to the tenant (groups 97, catalogs 5, access packages 6; oer-s113-rg exists: False).
[oer-s113] Wrote the baseline raw\s113\baseline-s113.json and read it back.
[oer-s113] Created group oer-s113-grp-old: 201.
[oer-s113] Recorded the id of oer-s113-grp-old under raw\s113 (not printed).
[oer-s113] oer-s113-grp-old resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s113] oer-s113-grp-old resolves by its display name: not yet (read 2, 2.2 s, likely replication delay) -- reading again in 4 s.
[oer-s113] oer-s113-grp-old resolves by its display name: converged after 3 read(s), 6.3 s.
[oer-s113] Created catalog oer-s113-catalog: 201.
[oer-s113] oer-s113-catalog is readable by its id: converged after 1 read(s), 0.1 s.
[oer-s113] Created access package oer-s113-ap: 201 after 1 attempt(s).
[oer-s113] oer-s113-ap is readable by its id: converged after 1 read(s), 0.1 s.
[oer-s113] Created resource group oer-s113-rg.
[oer-s113] Created Logic App oer-s113-la.
[oer-s113] UNAVAILABLE (class B): the custom extension oer-s113-ext -- answered 400 MissingParameters -- The following required parameters are missing: Url. The run carries on without it; nothing else is tried.
[oer-s113] Created policy oer-s113-policy: 201 after 1 attempt(s).
[oer-s113] Stopped after this run had written to the tenant (see the lines above): Reading a policy with its custom extension stages and questions failed: GET v1.0/identityGovernance/entitlementManagement/assignmentPolicies/00000000-0000-0000-0000-000000000001 answered 400 InvalidFilter -- OData query is invalid: Property 'questions' on type 'Microsoft.IGAELM.EC.FrontEnd.ExternalModel.accessPackageAssignmentPolicy' is not a navigation property or complex property. Only navigation properties can be expanded..
[oer-s113] Stopped at: at Assert-OerLiveOk, VAULT\OerLive\OerLive.psm1: line 673 <- at Read-S113PolicyFull, VAULT\Initialize-OerS113Prereq.ps1: line 223 <- at <ScriptBlock>, VAULT\Initialize-OerS113Prereq.ps1: line 598
[oer-s113] Setup changes nothing outside the prefix, so nothing is restored here; the test objects are removed by -Teardown.
[oer-s113] exit code: 1
[oer-s113] === Initialize-OerS113Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\prereq-20261013-220752Z.log; OerLive 1.0.3.
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Found: oer-s113-grp-old True; oer-s113-catalog True; oer-s113-ap True; oer-s113-policy True; oer-s113-autopolicy False; oer-s113-rg True; oer-s113-la True; oer-s113-ext False.
[oer-s113] The baseline exists (groups 97, catalogs 5, access packages 6 when it was written).
[oer-s113] Group oer-s113-grp-old exists.
[oer-s113] Catalog oer-s113-catalog exists.
[oer-s113] Access package oer-s113-ap exists.
[oer-s113] Resource group oer-s113-rg exists.
[oer-s113] Logic App oer-s113-la exists.
[oer-s113] UNAVAILABLE (class B): the custom extension oer-s113-ext -- answered 400 MissingParameters -- The following required parameters are missing: Url. The run carries on without it; nothing else is tried.
[oer-s113] Stopped after this run had written to the tenant (see the lines above): Reading a policy with its custom extension stages and questions failed: GET v1.0/identityGovernance/entitlementManagement/assignmentPolicies/00000000-0000-0000-0000-000000000001 answered 400 InvalidFilter -- OData query is invalid: Property 'questions' on type 'Microsoft.IGAELM.EC.FrontEnd.ExternalModel.accessPackageAssignmentPolicy' is not a navigation property or complex property. Only navigation properties can be expanded..
[oer-s113] Stopped at: at Assert-OerLiveOk, VAULT\OerLive\OerLive.psm1: line 673 <- at Read-S113PolicyFull, VAULT\Initialize-OerS113Prereq.ps1: line 223 <- at Invoke-S113Setup, VAULT\Initialize-OerS113Prereq.ps1: line 579
[oer-s113] Setup changes nothing outside the prefix, so nothing is restored here; the test objects are removed by -Teardown.
[oer-s113] exit code: 1
RUNNER: prereq-run1 exit code 0; started 2026-10-13T22:07:34Z; took 24 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Run 2: two -Unattended runs, the trigger URL given (the Logic App had no authorization policy) ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== PREREQ -Unattended x2 (run 2) ===
[oer-s113] === Initialize-OerS113Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\prereq-20261013-220915Z.log; OerLive 1.0.3.
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Found: oer-s113-grp-old True; oer-s113-catalog True; oer-s113-ap True; oer-s113-policy True; oer-s113-autopolicy False; oer-s113-rg True; oer-s113-la True; oer-s113-ext False.
[oer-s113] The baseline exists (groups 97, catalogs 5, access packages 6 when it was written).
[oer-s113] Group oer-s113-grp-old exists.
[oer-s113] Catalog oer-s113-catalog exists.
[oer-s113] Access package oer-s113-ap exists.
[oer-s113] Resource group oer-s113-rg exists.
[oer-s113] Logic App oer-s113-la exists.
[oer-s113] Read the trigger URL of oer-s113-la (not printed): True
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 2 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 3 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 4 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 5 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] UNAVAILABLE (class B): the custom extension oer-s113-ext -- answered 400 WorkFlowExtensionValidationError -- {"error":{"code":"Unauthorized","message":"Unauthorized","details":"{\"error\":{\"code\":\"OAuthAccessPolicyNotFound\",\"message\":\"'Authorization' header is not allowed, The OAuth authentication policy is not enabled for the workflow.\"}}"}}. The run carries on without it; nothing else is tried.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: no extension
[oer-s113] Policy oer-s113-policy exists in its full state.
[oer-s113] Created policy oer-s113-autopolicy: 201 after 1 attempt(s).
[oer-s113] oer-s113-autopolicy is listed on oer-s113-ap: converged after 1 read(s), 0.2 s.
[oer-s113] Summary: oer-s113-grp-old present; oer-s113-catalog present; oer-s113-ap present; oer-s113-rg present; oer-s113-la present; oer-s113-ext absent; oer-s113-policy present; oer-s113-autopolicy present; unavailable (class B): the custom extension oer-s113-ext; written to the tenant: True.
[oer-s113] Done.
[oer-s113] exit code: 0
[oer-s113] === Initialize-OerS113Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\prereq-20261013-220954Z.log; OerLive 1.0.3.
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Found: oer-s113-grp-old True; oer-s113-catalog True; oer-s113-ap True; oer-s113-policy True; oer-s113-autopolicy True; oer-s113-rg True; oer-s113-la True; oer-s113-ext False.
[oer-s113] The baseline exists (groups 97, catalogs 5, access packages 6 when it was written).
[oer-s113] Group oer-s113-grp-old exists.
[oer-s113] Catalog oer-s113-catalog exists.
[oer-s113] Access package oer-s113-ap exists.
[oer-s113] Resource group oer-s113-rg exists.
[oer-s113] Logic App oer-s113-la exists.
[oer-s113] Read the trigger URL of oer-s113-la (not printed): True
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 1 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 2 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 3 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 4 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] Creating custom extension oer-s113-ext answered 400 WorkFlowExtensionValidationError (attempt 5 of 6, likely replication delay) -- trying again in 5 s.
[oer-s113] UNAVAILABLE (class B): the custom extension oer-s113-ext -- answered 400 WorkFlowExtensionValidationError -- {"error":{"code":"Unauthorized","message":"Unauthorized","details":"{\"error\":{\"code\":\"OAuthAccessPolicyNotFound\",\"message\":\"'Authorization' header is not allowed, The OAuth authentication policy is not enabled for the workflow.\"}}"}}. The run carries on without it; nothing else is tried.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: no extension
[oer-s113] Policy oer-s113-policy exists in its full state.
[oer-s113] oer-s113-autopolicy: automaticRequestSettings with requestAccessForAllowedTargets true: True
[oer-s113] Policy oer-s113-autopolicy exists in its full state.
[oer-s113] Summary: oer-s113-grp-old present; oer-s113-catalog present; oer-s113-ap present; oer-s113-rg present; oer-s113-la present; oer-s113-ext absent; oer-s113-policy present; oer-s113-autopolicy present; unavailable (class B): the custom extension oer-s113-ext; written to the tenant: True.
[oer-s113] Done.
[oer-s113] exit code: 0
RUNNER: prereq-run2 exit code 0; started 2026-10-13T22:09:13Z; took 75 s.
LEAK CHECK: psd1 values surviving redaction: 0

=== Run 3: one -Unattended run with the AADPOP policy on the Logic App ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== PREREQ -Unattended (run 3) ===
[oer-s113] === Initialize-OerS113Prereq.ps1 -Unattended ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\prereq-20261013-221132Z.log; OerLive 1.0.3.
[oer-s113] Mode: CREATE or complete. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] oer-live-cc holds EntitlementManagement.ReadWrite.All: True
[oer-s113] Found: oer-s113-grp-old True; oer-s113-catalog True; oer-s113-ap True; oer-s113-policy True; oer-s113-autopolicy True; oer-s113-rg True; oer-s113-la True; oer-s113-ext False.
[oer-s113] The baseline exists (groups 97, catalogs 5, access packages 6 when it was written).
[oer-s113] Group oer-s113-grp-old exists.
[oer-s113] Catalog oer-s113-catalog exists.
[oer-s113] Access package oer-s113-ap exists.
[oer-s113] Resource group oer-s113-rg exists.
[oer-s113] Logic App oer-s113-la exists; its AADPOP authorization policy is there: False
[oer-s113] Wrote Logic App oer-s113-la with its authorization policy.
[oer-s113] Read the trigger URL of oer-s113-la (not printed): True
[oer-s113] Recorded the id of oer-s113-ext under raw\s113 (not printed).
[oer-s113] Created custom extension oer-s113-ext: 201 after 1 attempt(s).
[oer-s113] oer-s113-ext is listed in oer-s113-catalog: converged after 1 read(s), 0.1 s.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: False
[oer-s113] Brought oer-s113-policy back to its full state: 200.
[oer-s113] oer-s113-policy: the question is there: True; the custom extension stage is there: True
[oer-s113] oer-s113-policy holds its full state: converged after 1 read(s), 0.1 s.
[oer-s113] oer-s113-autopolicy: automaticRequestSettings with requestAccessForAllowedTargets true: True
[oer-s113] Policy oer-s113-autopolicy exists in its full state.
[oer-s113] Summary: oer-s113-grp-old present; oer-s113-catalog present; oer-s113-ap present; oer-s113-rg present; oer-s113-la present; oer-s113-ext present; oer-s113-policy present; oer-s113-autopolicy present; unavailable (class B): none; written to the tenant: True.
[oer-s113] Done.
[oer-s113] exit code: 0
RUNNER: prereq-run3 exit code 0; started 2026-10-13T22:11:30Z; took 11 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.1. What a read of a policy returns, with and without `$expand`

- [x] **1.1** The reads return `automaticRequestSettings`, `questions` and `customExtensionStageSettings` without a query; `$expand=questions` is refused.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: MEASURED. Without a query, with the module's own $expand=accessPackage, with $expand=customExtensionStageSettings (also nested with customExtension) and with $expand=catalog, Microsoft Graph returns automaticRequestSettings (null on this request policy), questions in full, and customExtensionStageSettings; notificationSettings is present and accessPackageNotificationSettings is not. $select=id,questions returned neither questions nor the other fields. (This read ran before the custom extension existed, so the stage list was empty; 1.2 shows the stage read without and with the nested expand.)

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== M.1 reads (before the extension) ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] oer-s113-policy [no query] keys (17): @odata.context, allowedTargetScope, automaticRequestSettings, createdDateTime, customExtensionStageSettings, description, displayName, expiration, id, modifiedDateTime, notificationSettings, questions, person1@example.com, requestApprovalSettings, requestorSettings, reviewSettings, specificAllowedTargets
[oer-s113] oer-s113-policy [no query] automaticRequestSettings: null
[oer-s113] oer-s113-policy [no query] customExtensionStageSettings: []
[oer-s113] oer-s113-policy [no query] questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000002","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy [no query] reviewSettings: null
[oer-s113] oer-s113-policy [no query] notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy [no query] accessPackageNotificationSettings: absent
[oer-s113] oer-s113-policy [no query] allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy [no query] specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-policy [$expand=accessPackage] keys (18): @odata.context, accessPackage, allowedTargetScope, automaticRequestSettings, createdDateTime, customExtensionStageSettings, description, displayName, expiration, id, modifiedDateTime, notificationSettings, questions, person1@example.com, requestApprovalSettings, requestorSettings, reviewSettings, specificAllowedTargets
[oer-s113] oer-s113-policy [$expand=accessPackage] automaticRequestSettings: null
[oer-s113] oer-s113-policy [$expand=accessPackage] customExtensionStageSettings: []
[oer-s113] oer-s113-policy [$expand=accessPackage] questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000002","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy [$expand=accessPackage] reviewSettings: null
[oer-s113] oer-s113-policy [$expand=accessPackage] notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy [$expand=accessPackage] accessPackageNotificationSettings: absent
[oer-s113] oer-s113-policy [$expand=accessPackage] allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy [$expand=accessPackage] specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-policy [$select=id,questions] keys (4): @odata.context, customExtensionStageSettings, id, requestApprovalSettings
[oer-s113] oer-s113-policy [$select=id,questions] automaticRequestSettings: absent
[oer-s113] oer-s113-policy [$select=id,questions] customExtensionStageSettings: []
[oer-s113] oer-s113-policy [$select=id,questions] questions: absent
[oer-s113] oer-s113-policy [$select=id,questions] reviewSettings: absent
[oer-s113] oer-s113-policy [$select=id,questions] notificationSettings: absent
[oer-s113] oer-s113-policy [$select=id,questions] accessPackageNotificationSettings: absent
[oer-s113] oer-s113-policy [$select=id,questions] allowedTargetScope: absent
[oer-s113] oer-s113-policy [$select=id,questions] specificAllowedTargets: absent
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] keys (17): @odata.context, allowedTargetScope, automaticRequestSettings, createdDateTime, customExtensionStageSettings, description, displayName, expiration, id, modifiedDateTime, notificationSettings, questions, person1@example.com, requestApprovalSettings, requestorSettings, reviewSettings, specificAllowedTargets
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] automaticRequestSettings: null
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] customExtensionStageSettings: []
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000002","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] reviewSettings: null
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] accessPackageNotificationSettings: absent
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings] specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] keys (17): @odata.context, allowedTargetScope, automaticRequestSettings, createdDateTime, customExtensionStageSettings, description, displayName, expiration, id, modifiedDateTime, notificationSettings, questions, person1@example.com, requestApprovalSettings, requestorSettings, reviewSettings, specificAllowedTargets
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] automaticRequestSettings: null
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] customExtensionStageSettings: []
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000002","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] reviewSettings: null
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] accessPackageNotificationSettings: absent
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy [$expand=customExtensionStageSettings($expand=customExtension)] specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-policy [$expand=catalog] keys (18): @odata.context, allowedTargetScope, automaticRequestSettings, catalog, createdDateTime, customExtensionStageSettings, description, displayName, expiration, id, modifiedDateTime, notificationSettings, questions, person1@example.com, requestApprovalSettings, requestorSettings, reviewSettings, specificAllowedTargets
[oer-s113] oer-s113-policy [$expand=catalog] automaticRequestSettings: null
[oer-s113] oer-s113-policy [$expand=catalog] customExtensionStageSettings: []
[oer-s113] oer-s113-policy [$expand=catalog] questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000002","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy [$expand=catalog] reviewSettings: null
[oer-s113] oer-s113-policy [$expand=catalog] notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy [$expand=catalog] accessPackageNotificationSettings: absent
[oer-s113] oer-s113-policy [$expand=catalog] allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy [$expand=catalog] specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] keys (18): @odata.context, accessPackage, allowedTargetScope, automaticRequestSettings, createdDateTime, customExtensionStageSettings, description, displayName, expiration, id, modifiedDateTime, notificationSettings, questions, person1@example.com, requestApprovalSettings, requestorSettings, reviewSettings, specificAllowedTargets
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] automaticRequestSettings: null
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] customExtensionStageSettings: []
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000002","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] reviewSettings: null
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] accessPackageNotificationSettings: absent
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy [$expand=accessPackage,customExtensionStageSettings] specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-autopolicy: not present
[oer-s113] token requests: 0
RUNNER: m1-reads-a exit code 0; started 2026-10-13T22:08:47Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. A description-only update through the module, before the change

- [x] **1.2** The update of the request policy removes its custom extension stage; the update of the automatic policy is refused.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: MEASURED, before the change. The request policy's description-only update through Set-OERAccessPackageAssignmentPolicy sent a body WITHOUT customExtensionStageSettings, and afterwards the stage was gone ('customExtensionStageSettings: [] (CHANGED)'); the question and every other field were unchanged. A read without a query, and the module's own read, return the stage as id and stage only; the custom extension's id needs the nested expand. The automatic policy's update was refused (output objects 0; errors) and nothing changed (1.3).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== M.2 PUT through the module at d9a13cc ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] oer-s113-policy before, read without a query: customExtensionStageSettings [{"id":"00000000-0000-0000-0000-000000000004","stage":"assignmentRequestCreated"}]
[oer-s113] oer-s113-policy before, read with the module's own query ($expand=accessPackage): customExtensionStageSettings [{"id":"00000000-0000-0000-0000-000000000004","stage":"assignmentRequestCreated"}]
[oer-s113] oer-s113-policy before allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy before specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-policy before automaticRequestSettings: null
[oer-s113] oer-s113-policy before customExtensionStageSettings: [{"customExtension":{"@odata.type":"#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension","authenticationConfiguration":{"@odata.type":"#microsoft.graph.azureAdPopTokenAuthentication"},"callbackConfiguration":null,"clientConfiguration":null,"createdDateTime":"2026-10-13T22:11:39.893Z","description":"Omnicit.EntraRBAC live verification (oer-s113-): the custom extension an update must keep.","displayName":"oer-s113-ext","endpointConfiguration":{"@odata.type":"#microsoft.graph.logicAppTriggerEndpointConfiguration","logicAppWorkflowName":"oer-s113-la","resourceGroupName":"oer-s113-rg","subscriptionId":"00000000-0000-0000-0000-000000000005","url":"(url not printed)"},"id":"00000000-0000-0000-0000-000000000006","lastModifiedDateTime":"2026-10-13T22:11:39.893Z"},"id":"00000000-0000-0000-0000-000000000004","stage":"assignmentRequestCreated"}]
[oer-s113] oer-s113-policy before questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000007","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy before requestorSettings: {"allowCustomAssignmentSchedule":false,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":true,"enableTargetsToSelfRemoveAccess":true,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]}
[oer-s113] oer-s113-policy before requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]}
[oer-s113] oer-s113-policy before expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"}
[oer-s113] oer-s113-policy before reviewSettings: null
[oer-s113] oer-s113-policy before notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy before description: "Omnicit.EntraRBAC live verification (oer-s113-): only the members of oer-s113-grp-old (none) may request."
[oer-s113] oer-s113-policy before displayName: "oer-s113-policy"
[oer-s113] oer-s113-policy update: output objects 1; errors 0
[oer-s113] oer-s113-policy update: the PUT body the module sent has the keys: accessPackage, allowedTargetScope, description, displayName, expiration, id, notificationSettings, questions, requestApprovalSettings, requestorSettings, specificAllowedTargets
[oer-s113] oer-s113-policy after allowedTargetScope: "specificDirectoryUsers" (unchanged)
[oer-s113] oer-s113-policy after specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}] (unchanged)
[oer-s113] oer-s113-policy after automaticRequestSettings: null (unchanged)
[oer-s113] oer-s113-policy after customExtensionStageSettings: [] (CHANGED)
[oer-s113] oer-s113-policy after questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000007","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}] (unchanged)
[oer-s113] oer-s113-policy after requestorSettings: {"allowCustomAssignmentSchedule":false,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":true,"enableTargetsToSelfRemoveAccess":true,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]} (unchanged)
[oer-s113] oer-s113-policy after requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]} (unchanged)
[oer-s113] oer-s113-policy after expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"} (unchanged)
[oer-s113] oer-s113-policy after reviewSettings: null (unchanged)
[oer-s113] oer-s113-policy after notificationSettings: {"isAssignmentNotificationDisabled":false} (unchanged)
[oer-s113] oer-s113-policy after description: "Updated by the step 3 measurement at 2026-10-13T22:12:16Z" (CHANGED)
[oer-s113] oer-s113-policy after displayName: "oer-s113-policy" (unchanged)
[oer-s113] oer-s113-autopolicy before, read without a query: customExtensionStageSettings []
[oer-s113] oer-s113-autopolicy before, read with the module's own query ($expand=accessPackage): customExtensionStageSettings []
[oer-s113] oer-s113-autopolicy before allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-autopolicy before specificAllowedTargets: [{"@odata.type":"#microsoft.graph.attributeRuleMembers","description":"oer-s113: no user","membershipRule":"(user.department -eq \"oer-s113-no-such-department\")"}]
[oer-s113] oer-s113-autopolicy before automaticRequestSettings: {"gracePeriodBeforeAccessRemoval":"P7D","removeAccessWhenTargetLeavesAllowedTargets":true,"requestAccessForAllowedTargets":true}
[oer-s113] oer-s113-autopolicy before customExtensionStageSettings: []
[oer-s113] oer-s113-autopolicy before questions: []
[oer-s113] oer-s113-autopolicy before requestorSettings: {"allowCustomAssignmentSchedule":true,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":false,"enableTargetsToSelfRemoveAccess":false,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]}
[oer-s113] oer-s113-autopolicy before requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]}
[oer-s113] oer-s113-autopolicy before expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"}
[oer-s113] oer-s113-autopolicy before reviewSettings: null
[oer-s113] oer-s113-autopolicy before notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-autopolicy before description: "Omnicit.EntraRBAC live verification (oer-s113-): an automatic assignment policy whose rule matches no user."
[oer-s113] oer-s113-autopolicy before displayName: "oer-s113-autopolicy"
[oer-s113] oer-s113-autopolicy update: output objects 0; errors 11 -- : 
[oer-s113] oer-s113-autopolicy update: the PUT body the module sent has the keys: accessPackage, allowedTargetScope, description, displayName, expiration, id, notificationSettings, requestApprovalSettings, requestorSettings, specificAllowedTargets
[oer-s113] oer-s113-autopolicy after allowedTargetScope: "specificDirectoryUsers" (unchanged)
[oer-s113] oer-s113-autopolicy after specificAllowedTargets: [{"@odata.type":"#microsoft.graph.attributeRuleMembers","description":"oer-s113: no user","membershipRule":"(user.department -eq \"oer-s113-no-such-department\")"}] (unchanged)
[oer-s113] oer-s113-autopolicy after automaticRequestSettings: {"gracePeriodBeforeAccessRemoval":"P7D","removeAccessWhenTargetLeavesAllowedTargets":true,"requestAccessForAllowedTargets":true} (unchanged)
[oer-s113] oer-s113-autopolicy after customExtensionStageSettings: [] (unchanged)
[oer-s113] oer-s113-autopolicy after questions: [] (unchanged)
[oer-s113] oer-s113-autopolicy after requestorSettings: {"allowCustomAssignmentSchedule":true,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":false,"enableTargetsToSelfRemoveAccess":false,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]} (unchanged)
[oer-s113] oer-s113-autopolicy after requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]} (unchanged)
[oer-s113] oer-s113-autopolicy after expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"} (unchanged)
[oer-s113] oer-s113-autopolicy after reviewSettings: null (unchanged)
[oer-s113] oer-s113-autopolicy after notificationSettings: {"isAssignmentNotificationDisabled":false} (unchanged)
[oer-s113] oer-s113-autopolicy after description: "Omnicit.EntraRBAC live verification (oer-s113-): an automatic assignment policy whose rule matches no user." (unchanged)
[oer-s113] oer-s113-autopolicy after displayName: "oer-s113-autopolicy" (unchanged)
[oer-s113] token requests: 0
RUNNER: m2-put-before exit code 0; started 2026-10-13T22:12:11Z; took 18 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.3. Why the automatic policy's update was refused

- [x] **1.3** Microsoft Graph's answer to the automatic policy's update, as the module records it.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: MEASURED, before the change. Microsoft Graph refused the automatic policy's update with 400 InvalidSpecificAllowedTargets: 'If the allowed target scope is set to specific targets, at least one valid target must be provided.' The module sent the policy's own attributeRuleMembers target; the body lacked automaticRequestSettings (1.4 shows that with them the same body is accepted). The -ErrorVariable holds the inner records too; the cmdlet's own record is the last one.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== M.2b the automatic policy update at d9a13cc ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] oer-s113-autopolicy update: output objects 0; records in -ErrorVariable: 9
[oer-s113] record 1: (not an ErrorRecord: System.Management.Automation.CmdletInvocationException) -- System.Management.Automation.CmdletInvocationException: PUT https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies/00000000-0000-0000-0000-000000000008
HTTP/1.1 400 Bad Request
Transfer-Encoding: chunked
Vary: Accept-Encoding
Strict-Transport-Security: max-age=31536000
request-id: 00000000-0000-0000-0000-000000000009
client-request-id: 00000000-0000-0000-0000-000000000010
x-ms-ags-diagnostic: {"ServerInfo":{"DataCenter":"Sweden Central","Slice":"E","Ring":"3","ScaleUnit":"000","RoleInstance":"GVX0EPF0007417E"}}
Date: Tue, 13 Oct 2026 22:12:53 GMT
Content-Type: application/json

{"error":{"code":"InvalidSpecificAllowedTargets","message":"If the allowed target scope is set to specific targets, at least one valid target must be provided.","details":[],"innerError":{"date":"2026-10-13T22:12:54","request-id":"00000000-0000-0000-0000-000000000009","client-request-id":"00000000-0000-0000-0000-000000000010"}}}
 ---> Microsoft.Graph.PowerShell.Authentication.Helpers.HttpResponseException: Response status code does not indicate success: BadRequest (Bad Request).
   at System.Management.Automation.MshCommandRuntime.ThrowTerminatingError(ErrorRecord errorRecord)
   --- End of inner exception stack trace ---
   at System.Management.Automation.ExceptionHandlingOps.CheckActionPreference(FunctionContext funcContext, Exception exception)
   at System.Management.Automation.Interpreter.ActionCallInstruction`2.Run(InterpretedFrame frame)
   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)
   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)
[oer-s113] record 2: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: BadRequest (Bad Request). -- details: PUT https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies/00000000-0000-0000-0000-000000000008
HTTP/1.1 400 Bad Request
Transfer-Encoding: chunked
Vary: Accept-Encoding
Strict-Transport-Security: max-age=31536000
request-id: 00000000-0000-0000-0000-000000000009
client-request-id: 00000000-0000-0000-0000-000000000010
x-ms-ags-diagnostic: {"ServerInfo":{"DataCenter":"Sweden Central","Slice":"E","Ring":"3","ScaleUnit":"000","RoleInstance":"GVX0EPF0007417E"}}
Date: Tue, 13 Oct 2026 22:12:53 GMT
Content-Type: application/json

{"error":{"code":"InvalidSpecificAllowedTargets","message":"If the allowed target scope is set to specific targets, at least one valid target must be provided.","details":[],"innerError":{"date":"2026-10-13T22:12:54","request-id":"00000000-0000-0000-0000-000000000009","client-request-id":"00000000-0000-0000-0000-000000000010"}}}
[oer-s113] record 3: InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest -- Response status code does not indicate success: BadRequest (Bad Request). -- details: PUT https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies/00000000-0000-0000-0000-000000000008
HTTP/1.1 400 Bad Request
Transfer-Encoding: chunked
Vary: Accept-Encoding
Strict-Transport-Security: max-age=31536000
request-id: 00000000-0000-0000-0000-000000000009
client-request-id: 00000000-0000-0000-0000-000000000010
x-ms-ags-diagnostic: {"ServerInfo":{"DataCenter":"Sweden Central","Slice":"E","Ring":"3","ScaleUnit":"000","RoleInstance":"GVX0EPF0007417E"}}
Date: Tue, 13 Oct 2026 22:12:53 GMT
Content-Type: application/json

{"error":{"code":"InvalidSpecificAllowedTargets","message":"If the allowed target scope is set to specific targets, at least one valid target must be provided.","details":[],"innerError":{"date":"2026-10-13T22:12:54","request-id":"00000000-0000-0000-0000-000000000009","client-request-id":"00000000-0000-0000-0000-000000000010"}}}
[oer-s113] record 4: InvalidSpecificAllowedTargets -- InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided. -- details: InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided.
[oer-s113] record 5: InvalidSpecificAllowedTargets -- InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided. -- details: InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided.
[oer-s113] record 6: InvalidSpecificAllowedTargets -- InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided. -- details: InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided.
[oer-s113] record 7: (not an ErrorRecord: System.Management.Automation.RuntimeException) -- System.Management.Automation.RuntimeException: InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided.
 ---> System.Exception: InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided.
   --- End of inner exception stack trace ---
   at System.Management.Automation.ExceptionHandlingOps.CheckActionPreference(FunctionContext funcContext, Exception exception)
   at System.Management.Automation.Interpreter.ActionCallInstruction`2.Run(InterpretedFrame frame)
   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)
   at System.Management.Automation.Interpreter.EnterTryCatchFinallyInstruction.Run(InterpretedFrame frame)
[oer-s113] record 8: InvalidSpecificAllowedTargets -- InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided. -- details: InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided.
[oer-s113] record 9: InvalidSpecificAllowedTargets,Set-OERAccessPackageAssignmentPolicy -- InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided. -- details: InvalidSpecificAllowedTargets: If the allowed target scope is set to specific targets, at least one valid target must be provided.
[oer-s113] token requests: 0
RUNNER: m2b-auto-error exit code 0; started 2026-10-13T22:12:49Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.4. The same body with the automatic settings carried, sent raw

- [x] **1.4** The combined `$expand` read is accepted, and the body the module builds plus `automaticRequestSettings` is accepted and keeps them.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: MEASURED. The combined read $expand=accessPackage,customExtensionStageSettings($expand=customExtension) answered 200 with the package id. The body ConvertTo-OERPolicyBody builds for a description-only update, plus the live automaticRequestSettings, sent raw, answered 200: automaticRequestSettings, specificAllowedTargets and allowedTargetScope unchanged, the description changed. This is the shape the branch now sends.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== M.3 carrying automaticRequestSettings, raw ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Combined query on oer-s113-policy answered 200 ; accessPackage id present: True; stages: 0; every stage names its custom extension's id and type: True
[oer-s113] M.3 body keys: accessPackage, allowedTargetScope, automaticRequestSettings, description, displayName, expiration, id, notificationSettings, requestApprovalSettings, requestorSettings, specificAllowedTargets
[oer-s113] M.3 PUT of oer-s113-autopolicy with automaticRequestSettings carried answered 200 
[oer-s113] M.3 oer-s113-autopolicy after automaticRequestSettings: {"gracePeriodBeforeAccessRemoval":"P7D","removeAccessWhenTargetLeavesAllowedTargets":true,"requestAccessForAllowedTargets":true} (unchanged)
[oer-s113] M.3 oer-s113-autopolicy after specificAllowedTargets: [{"@odata.type":"#microsoft.graph.attributeRuleMembers","description":"oer-s113: no user","membershipRule":"(user.department -eq \"oer-s113-no-such-department\")"}] (unchanged)
[oer-s113] M.3 oer-s113-autopolicy after allowedTargetScope: "specificDirectoryUsers" (unchanged)
[oer-s113] M.3 oer-s113-autopolicy after description: "Updated by the step 3 measurement M.3 at 2026-10-13T22:14:29Z" (CHANGED)
[oer-s113] token requests: 0
RUNNER: m3-carry-probe exit code 0; started 2026-10-13T22:14:25Z; took 11 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.5. Which mailNickname values Microsoft Graph accepts

- [x] **1.5** One PATCH per character, 64 and 65 characters and the empty string on `oer-s113-grp-old`, then the alias is put back.

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

Result: 2026-10-14 01:37 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: MEASURED (PATCH on a security group, app-only). Refused with 400 Request_BadRequest: each of @ ( ) \ [ ] " ; : < > , a space, a tab, 65 characters and the empty string. Accepted with 204: . - _ / ' ~ ! # $ % & * + = ? ^ ` { | }, the non-ASCII letter U+00E5 and 64 characters. The alias was put back to oer-s113-grp-old (204, read back).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== M.4 which mailNickname values Graph accepts ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] oer-s113-grp-old mailNickname before: oer-s113-grp-old
[oer-s113] mailNickname with character '.' (U+002E) (length 12): 204
[oer-s113] mailNickname with character '-' (U+002D) (length 12): 204
[oer-s113] mailNickname with character '_' (U+005F) (length 12): 204
[oer-s113] mailNickname with character '/' (U+002F) (length 12): 204
[oer-s113] mailNickname with character ''' (U+0027) (length 12): 204
[oer-s113] mailNickname with character '@' (U+0040) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character '(' (U+0028) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character ')' (U+0029) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character '\' (U+005C) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character '[' (U+005B) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character ']' (U+005D) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character '"' (U+0022) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character ';' (U+003B) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character ':' (U+003A) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character '<' (U+003C) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character '>' (U+003E) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character ',' (U+002C) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character ' ' (U+0020) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with character '~' (U+007E) (length 12): 204
[oer-s113] mailNickname with character '!' (U+0021) (length 12): 204
[oer-s113] mailNickname with character '#' (U+0023) (length 12): 204
[oer-s113] mailNickname with character '$' (U+0024) (length 12): 204
[oer-s113] mailNickname with character '%' (U+0025) (length 12): 204
[oer-s113] mailNickname with character '&' (U+0026) (length 12): 204
[oer-s113] mailNickname with character '*' (U+002A) (length 12): 204
[oer-s113] mailNickname with character '+' (U+002B) (length 12): 204
[oer-s113] mailNickname with character '=' (U+003D) (length 12): 204
[oer-s113] mailNickname with character '?' (U+003F) (length 12): 204
[oer-s113] mailNickname with character '^' (U+005E) (length 12): 204
[oer-s113] mailNickname with character '`' (U+0060) (length 12): 204
[oer-s113] mailNickname with character '{' (U+007B) (length 12): 204
[oer-s113] mailNickname with character '|' (U+007C) (length 12): 204
[oer-s113] mailNickname with character '}' (U+007D) (length 12): 204
[oer-s113] mailNickname with character U+00E5 (a with ring, not ASCII) (length 12): 204
[oer-s113] mailNickname with character U+0009 (tab, an ASCII control character) (length 12): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with length 64 (length 64): 204
[oer-s113] mailNickname with length 65 (length 65): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] mailNickname with the empty string (length 0): 400 Request_BadRequest -- Invalid value specified for property 'mailNickname' of resource 'Group'.
[oer-s113] Restored the mailNickname to oer-s113-grp-old: 204
[oer-s113] oer-s113-grp-old mailNickname reads oer-s113-grp-old again: converged after 1 read(s), 0.1 s.
[oer-s113] token requests: 0
RUNNER: m4-mailnickname exit code 0; started 2026-10-13T22:16:11Z; took 9 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. A policy update keeps what Microsoft Graph would drop

### 2.1. A description-only update through the module keeps the stage and the automatic settings

- [x] **2.1** The request policy's update sends its custom extension stage and keeps it; the automatic policy's update is accepted and keeps `automaticRequestSettings`.

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

Result: 2026-10-14 01:38 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. oer-s113-policy: output 1, errors 0; the PUT body now carries customExtensionStageSettings; afterwards the stage (oer-s113-ext, the same stage id) and the question are unchanged and only the description changed -- where 1.2 showed the stage removed. oer-s113-autopolicy: output 1, errors 0; the PUT body carries automaticRequestSettings; afterwards automaticRequestSettings, specificAllowedTargets and allowedTargetScope are unchanged and only the description changed -- where 1.3 showed the update refused.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] oer-s113-policy before, read without a query: customExtensionStageSettings [{"id":"00000000-0000-0000-0000-000000000011","stage":"assignmentRequestCreated"}]
[oer-s113] oer-s113-policy before, read with the module's own query ($expand=accessPackage): customExtensionStageSettings [{"id":"00000000-0000-0000-0000-000000000011","stage":"assignmentRequestCreated"}]
[oer-s113] oer-s113-policy before allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-policy before specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}]
[oer-s113] oer-s113-policy before automaticRequestSettings: null
[oer-s113] oer-s113-policy before customExtensionStageSettings: [{"customExtension":{"@odata.type":"#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension","authenticationConfiguration":{"@odata.type":"#microsoft.graph.azureAdPopTokenAuthentication"},"callbackConfiguration":null,"clientConfiguration":null,"createdDateTime":"2026-10-13T22:11:39.893Z","description":"Omnicit.EntraRBAC live verification (oer-s113-): the custom extension an update must keep.","displayName":"oer-s113-ext","endpointConfiguration":{"@odata.type":"#microsoft.graph.logicAppTriggerEndpointConfiguration","logicAppWorkflowName":"oer-s113-la","resourceGroupName":"oer-s113-rg","subscriptionId":"00000000-0000-0000-0000-000000000005","url":"(url not printed)"},"id":"00000000-0000-0000-0000-000000000006","lastModifiedDateTime":"2026-10-13T22:11:39.893Z"},"id":"00000000-0000-0000-0000-000000000011","stage":"assignmentRequestCreated"}]
[oer-s113] oer-s113-policy before questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000012","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}]
[oer-s113] oer-s113-policy before requestorSettings: {"allowCustomAssignmentSchedule":false,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":true,"enableTargetsToSelfRemoveAccess":true,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]}
[oer-s113] oer-s113-policy before requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]}
[oer-s113] oer-s113-policy before expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"}
[oer-s113] oer-s113-policy before reviewSettings: null
[oer-s113] oer-s113-policy before notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-policy before description: "Omnicit.EntraRBAC live verification (oer-s113-): only the members of oer-s113-grp-old (none) may request."
[oer-s113] oer-s113-policy before displayName: "oer-s113-policy"
[oer-s113] oer-s113-policy update: output objects 1; errors 0
[oer-s113] oer-s113-policy update: the PUT body the module sent has the keys: accessPackage, allowedTargetScope, customExtensionStageSettings, description, displayName, expiration, id, notificationSettings, questions, requestApprovalSettings, requestorSettings, specificAllowedTargets
[oer-s113] oer-s113-policy after allowedTargetScope: "specificDirectoryUsers" (unchanged)
[oer-s113] oer-s113-policy after specificAllowedTargets: [{"@odata.type":"#microsoft.graph.groupMembers","description":"oer-s113-grp-old","groupId":"00000000-0000-0000-0000-000000000003"}] (unchanged)
[oer-s113] oer-s113-policy after automaticRequestSettings: null (unchanged)
[oer-s113] oer-s113-policy after customExtensionStageSettings: [{"customExtension":{"@odata.type":"#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension","authenticationConfiguration":{"@odata.type":"#microsoft.graph.azureAdPopTokenAuthentication"},"callbackConfiguration":null,"clientConfiguration":null,"createdDateTime":"2026-10-13T22:11:39.893Z","description":"Omnicit.EntraRBAC live verification (oer-s113-): the custom extension an update must keep.","displayName":"oer-s113-ext","endpointConfiguration":{"@odata.type":"#microsoft.graph.logicAppTriggerEndpointConfiguration","logicAppWorkflowName":"oer-s113-la","resourceGroupName":"oer-s113-rg","subscriptionId":"00000000-0000-0000-0000-000000000005","url":"(url not printed)"},"id":"00000000-0000-0000-0000-000000000006","lastModifiedDateTime":"2026-10-13T22:11:39.893Z"},"id":"00000000-0000-0000-0000-000000000011","stage":"assignmentRequestCreated"}] (unchanged)
[oer-s113] oer-s113-policy after questions: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000012","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}] (unchanged)
[oer-s113] oer-s113-policy after requestorSettings: {"allowCustomAssignmentSchedule":false,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":true,"enableTargetsToSelfRemoveAccess":true,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]} (unchanged)
[oer-s113] oer-s113-policy after requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]} (unchanged)
[oer-s113] oer-s113-policy after expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"} (unchanged)
[oer-s113] oer-s113-policy after reviewSettings: null (unchanged)
[oer-s113] oer-s113-policy after notificationSettings: {"isAssignmentNotificationDisabled":false} (unchanged)
[oer-s113] oer-s113-policy after description: "Updated by the step 3 measurement at 2026-10-14T01:38:03Z" (CHANGED)
[oer-s113] oer-s113-policy after displayName: "oer-s113-policy" (unchanged)
[oer-s113] oer-s113-autopolicy before, read without a query: customExtensionStageSettings []
[oer-s113] oer-s113-autopolicy before, read with the module's own query ($expand=accessPackage): customExtensionStageSettings []
[oer-s113] oer-s113-autopolicy before allowedTargetScope: "specificDirectoryUsers"
[oer-s113] oer-s113-autopolicy before specificAllowedTargets: [{"@odata.type":"#microsoft.graph.attributeRuleMembers","description":"oer-s113: no user","membershipRule":"(user.department -eq \"oer-s113-no-such-department\")"}]
[oer-s113] oer-s113-autopolicy before automaticRequestSettings: {"gracePeriodBeforeAccessRemoval":"P7D","removeAccessWhenTargetLeavesAllowedTargets":true,"requestAccessForAllowedTargets":true}
[oer-s113] oer-s113-autopolicy before customExtensionStageSettings: []
[oer-s113] oer-s113-autopolicy before questions: []
[oer-s113] oer-s113-autopolicy before requestorSettings: {"allowCustomAssignmentSchedule":true,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":false,"enableTargetsToSelfRemoveAccess":false,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]}
[oer-s113] oer-s113-autopolicy before requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]}
[oer-s113] oer-s113-autopolicy before expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"}
[oer-s113] oer-s113-autopolicy before reviewSettings: null
[oer-s113] oer-s113-autopolicy before notificationSettings: {"isAssignmentNotificationDisabled":false}
[oer-s113] oer-s113-autopolicy before description: "Updated by the step 3 measurement M.3 at 2026-10-13T22:14:29Z"
[oer-s113] oer-s113-autopolicy before displayName: "oer-s113-autopolicy"
[oer-s113] oer-s113-autopolicy update: output objects 1; errors 0
[oer-s113] oer-s113-autopolicy update: the PUT body the module sent has the keys: accessPackage, allowedTargetScope, automaticRequestSettings, description, displayName, expiration, id, notificationSettings, requestApprovalSettings, requestorSettings, specificAllowedTargets
[oer-s113] oer-s113-autopolicy after allowedTargetScope: "specificDirectoryUsers" (unchanged)
[oer-s113] oer-s113-autopolicy after specificAllowedTargets: [{"@odata.type":"#microsoft.graph.attributeRuleMembers","description":"oer-s113: no user","membershipRule":"(user.department -eq \"oer-s113-no-such-department\")"}] (unchanged)
[oer-s113] oer-s113-autopolicy after automaticRequestSettings: {"gracePeriodBeforeAccessRemoval":"P7D","removeAccessWhenTargetLeavesAllowedTargets":true,"requestAccessForAllowedTargets":true} (unchanged)
[oer-s113] oer-s113-autopolicy after customExtensionStageSettings: [] (unchanged)
[oer-s113] oer-s113-autopolicy after questions: [] (unchanged)
[oer-s113] oer-s113-autopolicy after requestorSettings: {"allowCustomAssignmentSchedule":true,"enableOnBehalfRequestorsToAddAccess":false,"enableOnBehalfRequestorsToRemoveAccess":false,"enableOnBehalfRequestorsToUpdateAccess":false,"enableTargetsToSelfAddAccess":false,"enableTargetsToSelfRemoveAccess":false,"enableTargetsToSelfUpdateAccess":false,"onBehalfRequestors":[]} (unchanged)
[oer-s113] oer-s113-autopolicy after requestApprovalSettings: {"isApprovalRequiredForAdd":false,"isApprovalRequiredForUpdate":false,"isRequestorJustificationRequired":false,"stages":[]} (unchanged)
[oer-s113] oer-s113-autopolicy after expiration: {"duration":null,"endDateTime":null,"type":"noExpiration"} (unchanged)
[oer-s113] oer-s113-autopolicy after reviewSettings: null (unchanged)
[oer-s113] oer-s113-autopolicy after notificationSettings: {"isAssignmentNotificationDisabled":false} (unchanged)
[oer-s113] oer-s113-autopolicy after description: "Updated by the step 3 measurement at 2026-10-14T01:38:03Z" (CHANGED)
[oer-s113] oer-s113-autopolicy after displayName: "oer-s113-autopolicy" (unchanged)
[oer-s113] token requests: 0
RUNNER: check-2.1 exit code 0; started 2026-10-14T01:37:59Z; took 17 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.2. The same through the document, three times (G8)

- [x] **2.2** A document changing both policies' descriptions updates them once and keeps the stage and the automatic settings; the second and third runs report only `Unchanged` and write nothing.

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

Result: 2026-10-14 01:39 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Run 1: the package Unchanged and both policies Updated (description), 2 writes (two PUT; the counter prints the method only for a relative Graph path); runs 2 and 3: only Unchanged rows, 0 writes (G8). Afterwards the custom extension stage, the question, the automatic settings and the attribute rule target are unchanged; only the two descriptions changed, to the document's text.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 2.2 run 1 rows: 3
[oer-s113] 2.2 run 1 row: accessPackages | oer-s113-ap | Unchanged | access package properties match
[oer-s113] 2.2 run 1 row: accessPackages | oer-s113-ap | Updated | updated assignmentPolicy 'oer-s113-policy' (description)
[oer-s113] 2.2 run 1 row: accessPackages | oer-s113-ap | Updated | updated assignmentPolicy 'oer-s113-autopolicy' (description)
[oer-s113] 2.2 run 1 warnings: 0
[oer-s113] 2.2 run 1 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 2.2 run 1 sent: token requests: 0; Microsoft Graph requests: 10, writes: 2 (PUT , PUT ); Azure Resource Manager requests: 0, writes: 0
[oer-s113] 2.2 run 2 rows: 3
[oer-s113] 2.2 run 2 row: accessPackages | oer-s113-ap | Unchanged | access package properties match
[oer-s113] 2.2 run 2 row: accessPackages | oer-s113-ap | Unchanged | assignmentPolicy 'oer-s113-policy' matches
[oer-s113] 2.2 run 2 row: accessPackages | oer-s113-ap | Unchanged | assignmentPolicy 'oer-s113-autopolicy' matches
[oer-s113] 2.2 run 2 warnings: 0
[oer-s113] 2.2 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 2.2 run 2 sent: token requests: 0; Microsoft Graph requests: 6, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 2.2 run 3 rows: 3
[oer-s113] 2.2 run 3 row: accessPackages | oer-s113-ap | Unchanged | access package properties match
[oer-s113] 2.2 run 3 row: accessPackages | oer-s113-ap | Unchanged | assignmentPolicy 'oer-s113-policy' matches
[oer-s113] 2.2 run 3 row: accessPackages | oer-s113-ap | Unchanged | assignmentPolicy 'oer-s113-autopolicy' matches
[oer-s113] 2.2 run 3 warnings: 0
[oer-s113] 2.2 run 3 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 2.2 run 3 sent: token requests: 0; Microsoft Graph requests: 6, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 2.2 policy customExtensionStageSettings after the three runs: [{"customExtension":{"@odata.type":"#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension","authenticationConfiguration":{"@odata.type":"#microsoft.graph.azureAdPopTokenAuthentication"},"callbackConfiguration":null,"clientConfiguration":null,"createdDateTime":"2026-10-13T22:11:39.893Z","description":"Omnicit.EntraRBAC live verification (oer-s113-): the custom extension an update must keep.","displayName":"oer-s113-ext","endpointConfiguration":{"@odata.type":"#microsoft.graph.logicAppTriggerEndpointConfiguration","logicAppWorkflowName":"oer-s113-la","resourceGroupName":"oer-s113-rg","subscriptionId":"00000000-0000-0000-0000-000000000005","url":"(url not printed)"},"id":"00000000-0000-0000-0000-000000000006","lastModifiedDateTime":"2026-10-13T22:11:39.893Z"},"id":"00000000-0000-0000-0000-000000000011","stage":"assignmentRequestCreated"}] (unchanged)
[oer-s113] 2.2 policy questions after the three runs: [{"@odata.type":"#microsoft.graph.accessPackageTextInputQuestion","id":"00000000-0000-0000-0000-000000000012","isAnswerEditable":true,"isRequired":false,"isSingleLineQuestion":true,"localizations":[],"regexPattern":null,"sequence":1,"text":"oer-s113: an optional question that an update must keep"}] (unchanged)
[oer-s113] 2.2 auto automaticRequestSettings after the three runs: {"gracePeriodBeforeAccessRemoval":"P7D","removeAccessWhenTargetLeavesAllowedTargets":true,"requestAccessForAllowedTargets":true} (unchanged)
[oer-s113] 2.2 auto specificAllowedTargets after the three runs: [{"@odata.type":"#microsoft.graph.attributeRuleMembers","description":"oer-s113: no user","membershipRule":"(user.department -eq \"oer-s113-no-such-department\")"}] (unchanged)
[oer-s113] 2.2 policy description after the three runs: "Updated through the document by check 2.2" (CHANGED)
[oer-s113] 2.2 auto description after the three runs: "Updated through the document by check 2.2" (CHANGED)
[oer-s113] token requests: 0
RUNNER: check-2.2 exit code 0; started 2026-10-14T01:38:26Z; took 55 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. An access package in a catalog the same document creates

### 3.1. The validator accepts the document

- [x] **3.1** `Test-OERStructure` reports the document valid.

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

Result: 2026-10-14 01:39 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. valid: True, errors: 0. The two Warnings are the existing rule on omitted collection keys (catalogs[0].resources and accessPackages[0].resourceRoles are reconciled under -Prune when omitted); this file never runs the document with -Prune.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 3.1 valid: True; errors: 0; warnings: 2
[oer-s113] 3.1 finding: Warning | catalogs[0].resources | 'resources' is omitted at catalogs[0]. An omitted resources key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
[oer-s113] 3.1 finding: Warning | accessPackages[0].resourceRoles | 'resourceRoles' is omitted at accessPackages[0]. An omitted resourceRoles key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
RUNNER: check-3.1 exit code 0; started 2026-10-14T01:39:32Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. The plan says "would create" for the catalog, the package and the policy

- [x] **3.2** `Invoke-OERStructure -WhatIf` plans the catalog, the package and its policy as created, with no `Failed` row and no write.

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

Result: 2026-10-14 01:39 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan reports 'would create catalog oer-s113-newcat', 'would create access package oer-s113-newap' and 'would create assignmentPolicy 'oer-s113-newpol' after access package is created'; no Failed row, no error; one Microsoft Graph read (the catalog lookup) and 0 writes. Before this branch the package row was Failed, NOT created.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Create catalog" on target "oer-s113-newcat".
What if: Performing the operation "Create access package" on target "oer-s113-newap".
[oer-s113] 3.2 plan rows: 3
[oer-s113] 3.2 plan row: catalogs | oer-s113-newcat | Skipped | would create catalog oer-s113-newcat
[oer-s113] 3.2 plan row: accessPackages | oer-s113-newap | Skipped | would create access package oer-s113-newap
[oer-s113] 3.2 plan row: accessPackages | oer-s113-newap | Skipped | would create assignmentPolicy 'oer-s113-newpol' after access package is created
[oer-s113] 3.2 plan warnings: 0
[oer-s113] 3.2 plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 3.2 plan sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check-3.2 exit code 0; started 2026-10-14T01:39:36Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.3. The run creates them

- [x] **3.3** The same document, applied, creates the catalog, the package and the policy.

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

Result: 2026-10-14 01:40 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The run created oer-s113-newcat, oer-s113-newap and the policy oer-s113-newpol (three Created rows, no Failed row, no error), with 3 writes (three POST). The real run is the same as before this branch.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.3 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 3.3 run rows: 3
[oer-s113] 3.3 run row: catalogs | oer-s113-newcat | Created | created catalog oer-s113-newcat (00000000-0000-0000-0000-000000000013)
[oer-s113] 3.3 run row: accessPackages | oer-s113-newap | Created | created access package oer-s113-newap (00000000-0000-0000-0000-000000000014)
[oer-s113] 3.3 run row: accessPackages | oer-s113-newap | Created | created assignmentPolicy 'oer-s113-newpol'
[oer-s113] 3.3 run warnings: 0
[oer-s113] 3.3 run errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 3.3 run sent: token requests: 0; Microsoft Graph requests: 12, writes: 3 (POST , POST , POST ); Azure Resource Manager requests: 0, writes: 0
RUNNER: check-3.3 exit code 0; started 2026-10-14T01:39:52Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.4. The same document twice more: only Unchanged (G8)

- [x] **3.4** Two more runs report only `Unchanged` and write nothing.

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

Result: 2026-10-14 01:41 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Runs 2 and 3, 30 and 15 seconds apart: only Unchanged rows (the catalog, the package and the policy), 0 writes each (G8).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.4 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 3.4 run 2 rows: 3
[oer-s113] 3.4 run 2 row: catalogs | oer-s113-newcat | Unchanged | catalog properties match
[oer-s113] 3.4 run 2 row: accessPackages | oer-s113-newap | Unchanged | access package properties match
[oer-s113] 3.4 run 2 row: accessPackages | oer-s113-newap | Unchanged | assignmentPolicy 'oer-s113-newpol' matches
[oer-s113] 3.4 run 2 warnings: 0
[oer-s113] 3.4 run 2 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 3.4 run 2 sent: token requests: 0; Microsoft Graph requests: 10, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 3.4 run 3 rows: 3
[oer-s113] 3.4 run 3 row: catalogs | oer-s113-newcat | Unchanged | catalog properties match
[oer-s113] 3.4 run 3 row: accessPackages | oer-s113-newap | Unchanged | access package properties match
[oer-s113] 3.4 run 3 row: accessPackages | oer-s113-newap | Unchanged | assignmentPolicy 'oer-s113-newpol' matches
[oer-s113] 3.4 run 3 warnings: 0
[oer-s113] 3.4 run 3 errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 3.4 run 3 sent: token requests: 0; Microsoft Graph requests: 10, writes: 0; Azure Resource Manager requests: 0, writes: 0
RUNNER: check-3.4 exit code 0; started 2026-10-14T01:40:08Z; took 52 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 4. previousDisplayName on an administrative unit is refused

### 4.1. The validator refuses it

- [x] **4.1** `Test-OERStructure` reports `previousDisplayName` on an administrative unit as an `Error`.

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

Result: 2026-10-14 01:41 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. valid: False with one Error at administrativeUnits[0].previousDisplayName: not supported for an administrative unit yet, only groups can be renamed, and the engine would create a new administrative unit beside the existing one. The two Warnings are the existing rule on omitted collection keys.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.1 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 4.1 valid: False; errors: 1; warnings: 2
[oer-s113] 4.1 finding: Error | administrativeUnits[0].previousDisplayName | 'previousDisplayName' at administrativeUnits[0] is not supported for an administrative unit yet: only groups can be renamed through the document. Invoke-OERStructure does not read previousDisplayName for an administrative unit, so it would create a new administrative unit named by displayName beside the existing one instead of renaming it. Remove previousDisplayName, and rename the existing object outside the document first.
[oer-s113] 4.1 finding: Warning | administrativeUnits[0].members | 'members' is omitted at administrativeUnits[0]. An omitted members key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
[oer-s113] 4.1 finding: Warning | administrativeUnits[0].scopedRoles | 'scopedRoles' is omitted at administrativeUnits[0]. An omitted scopedRoles key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
RUNNER: check-4.1 exit code 0; started 2026-10-14T01:41:08Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 4.2. Invoke-OERStructure writes nothing, planned or applied

- [x] **4.2** `Invoke-OERStructure`, with `-WhatIf` and without, refuses the document before it signs in, and no administrative unit with the prefix exists afterwards.

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

Result: 2026-10-14 01:41 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan and the run each wrote one StructureValidationFailed error naming the finding and no row, with 0 token requests, 0 Microsoft Graph and 0 Azure Resource Manager requests: refused before the sign-in. The sweep lists no administrative unit with the prefix (only the group, the two catalogs and the two packages this file created).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 4.2 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 4.2 plan rows: 0
[oer-s113] 4.2 plan warnings: 0
[oer-s113] 4.2 plan error: StructureValidationFailed,Invoke-OERStructure: Structure document failed validation: administrativeUnits[0].previousDisplayName: 'previousDisplayName' at administrativeUnits[0] is not supported for an administrative unit yet: only groups can be renamed through the document. Invoke-OERStructure does not read previousDisplayName for an administrative unit, so it would create a new administrative unit named by displayName beside the existing one instead of renaming it. Remove previousDisplayName, and rename the existing object outside the document first.
[oer-s113] 4.2 plan errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 4.2 plan sent: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 4.2 run rows: 0
[oer-s113] 4.2 run warnings: 0
[oer-s113] 4.2 run error: StructureValidationFailed,Invoke-OERStructure: Structure document failed validation: administrativeUnits[0].previousDisplayName: 'previousDisplayName' at administrativeUnits[0] is not supported for an administrative unit yet: only groups can be renamed through the document. Invoke-OERStructure does not read previousDisplayName for an administrative unit, so it would create a new administrative unit named by displayName beside the existing one instead of renaming it. Remove previousDisplayName, and rename the existing object outside the document first.
[oer-s113] 4.2 run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 4.2 run sent: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] Sweep: group 'oer-s113-grp-old' (00000000-0000-0000-0000-000000000003) carries the prefix.
[oer-s113] Sweep: catalog 'oer-s113-newcat' (00000000-0000-0000-0000-000000000013) carries the prefix.
[oer-s113] Sweep: catalog 'oer-s113-catalog' (00000000-0000-0000-0000-000000000015) carries the prefix.
[oer-s113] Sweep: access package 'oer-s113-newap' (00000000-0000-0000-0000-000000000014) carries the prefix.
[oer-s113] Sweep: access package 'oer-s113-ap' (00000000-0000-0000-0000-000000000016) carries the prefix.
RUNNER: check-4.2 exit code 0; started 2026-10-14T01:41:12Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 5. A renamed group and its mail alias

### 5.1. The validator: a renamed group's alias

- [x] **5.1** A rename with no `mailNickname`, or with the alias derived from the old name, is a `Warning`; a new alias is not; an alias Microsoft Graph refuses is an `Error`.

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

**Expect:** a: `valid: True; errors: 0`, the Warning at `groups[0].mailNickname` saying the group declares
no mailNickname and that the alias does not follow a rename; b: the same with the Warning that
`'oer-s113-grp-old'` is the alias derived from the old name; c: no Warning at `groups[0].mailNickname`;
d: `valid: False`, an `Error` at `groups[0].mailNickname` naming the space and the parentheses. Each
document also carries the existing Warning for its omitted `members` key (corrected after the run:
the first version of this line counted only the alias Warning).
**Failure looks like:** no Warning for a or b, or `valid: True` for d.

Result: 2026-10-14 01:42 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. a: valid, the Warning at groups[0].mailNickname that the renamed group declares no mailNickname and keeps its alias; b: valid, the Warning that 'oer-s113-grp-old' is the alias derived from the old name; c: valid, no alias Warning; d: invalid, one Error naming U+0020, '(' and ')' with the measured set. Each document also carries the existing Warning for its omitted members key, which the first version of the Expect did not count (corrected).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.1 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 5.1 a no mailNickname valid: True; errors: 0; warnings: 2
[oer-s113] 5.1 a no mailNickname finding: Warning | groups[0].mailNickname | Group at groups[0] is renamed from 'oer-s113-grp-old' and declares no mailNickname, so it keeps its current mail alias: the alias does not follow a rename. If that alias was derived from the old name, declare mailNickname with the alias the new name should carry.
[oer-s113] 5.1 a no mailNickname finding: Warning | groups[0].members | 'members' is omitted at groups[0]. An omitted members key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
[oer-s113] 5.1 b the old derived alias valid: True; errors: 0; warnings: 2
[oer-s113] 5.1 b the old derived alias finding: Warning | groups[0].mailNickname | Group at groups[0] is renamed from 'oer-s113-grp-old' but its mailNickname 'oer-s113-grp-old' is the alias derived from the old name: the alias does not follow a rename. Declare the alias the new name should carry, or keep this one on purpose.
[oer-s113] 5.1 b the old derived alias finding: Warning | groups[0].members | 'members' is omitted at groups[0]. An omitted members key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
[oer-s113] 5.1 c a new alias valid: True; errors: 0; warnings: 1
[oer-s113] 5.1 c a new alias finding: Warning | groups[0].members | 'members' is omitted at groups[0]. An omitted members key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
[oer-s113] 5.1 d an alias Graph refuses valid: False; errors: 1; warnings: 1
[oer-s113] 5.1 d an alias Graph refuses finding: Error | groups[0].mailNickname | 'mailNickname' at groups[0] contains U+0020, '(', ')', which the validator refuses in a mail alias (Microsoft Graph was measured to refuse @ ( ) \ [ ] " ; : < > , a space and a tab; other white space and control characters are refused too).
[oer-s113] 5.1 d an alias Graph refuses finding: Warning | groups[0].members | 'members' is omitted at groups[0]. An omitted members key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched.
RUNNER: check-5.1 exit code 0; started 2026-10-14T01:41:29Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 5.2. The plan renames the group and writes nothing

- [x] **5.2** `Invoke-OERStructure -WhatIf` with document a plans the rename, writes nothing, and the group still carries its old name and alias.

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

**Expect:** a row `groups | oer-s113-grp-new | Skipped | would rename ...` (the planned rename), `writes:
0`; afterwards exactly one group, `oer-s113-grp-old`, with mailNickname `oer-s113-grp-old`.
`Invoke-OERStructure` stops on a validator `Error` but does not print the validator's Warnings, so the
alias Warning is `Test-OERStructure`'s (5.1), not this plan's (corrected after the run: the first
version of this line expected it among the plan's warnings).
**Failure looks like:** a write, or the group renamed.

Result: 2026-10-14 01:42 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS on the corrected Expect. The plan has one row, 'would rename group 'oer-s113-grp-old' to 'oer-s113-grp-new'' (and its What if line), 5 Microsoft Graph reads, 0 writes; afterwards the one group is still oer-s113-grp-old with mailNickname oer-s113-grp-old. The plan prints no warning: Invoke-OERStructure stops on a validator Error but has never printed the validator's Warnings, so the alias Warning is Test-OERStructure's (5.1). The first version of the Expect expected it among the plan's warnings; that was the checklist's mistake, not the module's, and every text of the branch says the validator (Test-OERStructure) warns.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 5.2 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
What if: Performing the operation "Rename group 'oer-s113-grp-old' to 'oer-s113-grp-new'" on target "oer-s113-grp-new".
[oer-s113] 5.2 plan rows: 1
[oer-s113] 5.2 plan row: groups | oer-s113-grp-new | Skipped | would rename group 'oer-s113-grp-old' to 'oer-s113-grp-new'
[oer-s113] 5.2 plan warnings: 0
[oer-s113] 5.2 plan errors of Invoke-OERStructure: 0; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 5.2 plan sent: token requests: 0; Microsoft Graph requests: 5, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 5.2 after: group oer-s113-grp-old mailNickname oer-s113-grp-old
RUNNER: check-5.2 exit code 0; started 2026-10-14T01:41:33Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 6. A scope spelled as another scope is refused, and a space inside a name is not

Round 1 ran 6.1 and 6.2 again on its own build and added 6.3 and 6.4 (F). The resource group
`oer-s113-rg` was deleted by the step's teardown before round 1, and section 6 needs no object: the
validator reads no tenant, and a refused document is refused before any sign-in or request.

### 6.1. The validator refuses the spelling and accepts the plain path

- [x] **6.1** A scope with a `..` or `.` segment or a `%` is an `Error` in `roleAssignments` and in `roleManagementPolicies`, and, since round 1, a space between other characters of a segment is not; the same scope written plainly is valid.

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

**Expect:** spelled: `valid: False; errors: 3`, an `Error` at `roleAssignments[0].scope` (a `'.' or
'..' segment`), at `roleAssignments[1].scope` (a `'%'`) and at `roleManagementPolicies[0].scope` (a
segment); no finding at `roleAssignments[2].scope` since round 1: its resource group name holds a space
between other characters, which Azure does not allow in a resource group name, but the validator does
not know resource types and the request would name that one scope; plain: `valid: True; errors: 0`.
**Failure looks like:** `valid: True` for the spelled document (before this branch only a trailing or
doubled `/` was refused), or a white space `Error` at `roleAssignments[2].scope` (the rule before
round 1).

Result: 2026-10-14 01:42 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The spelled document is invalid with four Errors: a '..' segment at roleAssignments[0], a '%' escape at roleAssignments[1], white space at roleAssignments[2] (with the way out: such a resource cannot be declared; remove the entry) and a '.' segment at roleManagementPolicies[0]. The same resource group written plainly is valid with no finding.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 6.1 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 6.1 spelled valid: False; errors: 4; warnings: 0
[oer-s113] 6.1 spelled finding: Error | roleAssignments[0].scope | 'scope' at roleAssignments[0] must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113-x/../oer-s113-rg'.
[oer-s113] 6.1 spelled finding: Error | roleAssignments[1].scope | 'scope' at roleAssignments[1] must be written without a '%' escape: the request would decode it and name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113-rg/%2e'.
[oer-s113] 6.1 spelled finding: Error | roleAssignments[2].scope | 'scope' at roleAssignments[2] must be written without white space. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113 rg'. An Azure resource whose name holds white space cannot be declared in a document; remove the entry.
[oer-s113] 6.1 spelled finding: Error | roleManagementPolicies[0].scope | 'scope' at roleManagementPolicies[0] must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/./resourceGroups/oer-s113-rg'.
[oer-s113] 6.1 plain valid: True; errors: 0; warnings: 0
RUNNER: check-6.1 exit code 0; started 2026-10-14T01:42:31Z; took 4 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 6.2. Invoke-OERStructure writes nothing, with -Prune, planned or applied

- [x] **6.2** `Invoke-OERStructure -Prune`, with `-WhatIf` and without, refuses the document before it signs in and sends no request, and no role assignment exists at `oer-s113-rg` afterwards.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section6.json') -Raw
Invoke-S113Apply -Label '6.2 plan' -Json $Doc -Plan -Prune
Invoke-S113Apply -Label '6.2 run' -Json $Doc -Prune
# The step's teardown deleted oer-s113-rg before round 1; a role assignment cannot exist at a scope that does not.
$RgRead = Invoke-OerLiveArm -Path "$SubScope/resourceGroups/oer-s113-rg?api-version=2021-04-01"
if ($RgRead.Status -eq 404) {
    Write-OerLiveStep "6.2 resource group oer-s113-rg exists afterwards: False ($($RgRead.Code)), so no role assignment exists at it"
} else {
    Assert-OerLiveOk -Response $RgRead -Activity 'Reading oer-s113-rg' | Out-Null
    $Ra = Invoke-OerLiveArm -All -Path "$SubScope/resourceGroups/oer-s113-rg/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
    Assert-OerLiveOk -Response $Ra -Activity 'Listing the role assignments at oer-s113-rg' | Out-Null
    $At = @(@($Ra.Body.value) | Where-Object { $null -ne $_ -and [string]::Equals(([string]$_.properties.scope).TrimEnd('/'), "$SubScope/resourceGroups/oer-s113-rg", [System.StringComparison]::OrdinalIgnoreCase) })
    Write-OerLiveStep "6.2 role assignments exactly at oer-s113-rg afterwards: $($At.Count)"
}
Disconnect-OerLive
```

**Expect:** both: rows 0, `error: StructureValidationFailed,Invoke-OERStructure: ...` naming the three
findings of 6.1, `token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager
requests: 0, writes: 0`; then `resource group oer-s113-rg exists afterwards: False (ResourceGroupNotFound)`
in round 1 (the teardown deleted it), or `role assignments exactly at oer-s113-rg afterwards: 0` while
it exists.
**Failure looks like:** any request, or a role assignment at the resource group.

Result: 2026-10-14 01:42 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With -Prune, the plan and the run each wrote one StructureValidationFailed error naming the four findings and no row, with 0 token, 0 Microsoft Graph and 0 Azure Resource Manager requests; afterwards no role assignment exists exactly at oer-s113-rg.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 6.2 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 6.2 plan rows: 0
[oer-s113] 6.2 plan warnings: 0
[oer-s113] 6.2 plan error: StructureValidationFailed,Invoke-OERStructure: Structure document failed validation: roleAssignments[0].scope: 'scope' at roleAssignments[0] must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113-x/../oer-s113-rg'.; roleAssignments[1].scope: 'scope' at roleAssignments[1] must be written without a '%' escape: the request would decode it and name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113-rg/%2e'.; roleAssignments[2].scope: 'scope' at roleAssignments[2] must be written without white space. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113 rg'. An Azure resource whose name holds white space cannot be declared in a document; remove the entry.; roleManagementPolicies[0].scope: 'scope' at roleManagementPolicies[0] must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/./resourceGroups/oer-s113-rg'.
[oer-s113] 6.2 plan errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 6.2 plan sent: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 6.2 run rows: 0
[oer-s113] 6.2 run warnings: 0
[oer-s113] 6.2 run error: StructureValidationFailed,Invoke-OERStructure: Structure document failed validation: roleAssignments[0].scope: 'scope' at roleAssignments[0] must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113-x/../oer-s113-rg'.; roleAssignments[1].scope: 'scope' at roleAssignments[1] must be written without a '%' escape: the request would decode it and name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113-rg/%2e'.; roleAssignments[2].scope: 'scope' at roleAssignments[2] must be written without white space. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/resourceGroups/oer-s113 rg'. An Azure resource whose name holds white space cannot be declared in a document; remove the entry.; roleManagementPolicies[0].scope: 'scope' at roleManagementPolicies[0] must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '/subscriptions/00000000-0000-0000-0000-000000000005/./resourceGroups/oer-s113-rg'.
[oer-s113] 6.2 run errors of Invoke-OERStructure: 1; other items in -ErrorVariable (counted, not printed): 0
[oer-s113] 6.2 run sent: token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 6.2 role assignments exactly at oer-s113-rg afterwards: 0
RUNNER: check-6.2 exit code 0; started 2026-10-14T01:42:36Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 6.3. A space inside a resource name is accepted; a trailing space, a tab, a backslash, '?' and '#' are refused

- [ ] **6.3** Since round 1, a scope with spaces between other characters of a resource name is valid in `roleAssignments` and in `roleManagementPolicies`, and a scope with a trailing space, a tab, a `\`, a `?` or a `#` is one `Error` each. No resource named here exists or needs to.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Sql = "$SubScope/resourceGroups/oer-s113-rg/providers/Microsoft.Sql/servers/oer-s113-sql/databases"
$Spaced = New-S113Document -Section @{
    roleAssignments        = @(
        [ordered]@{ scope = "$Sql/oer-s113 sales data"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
        [ordered]@{ scope = "$SubScope/resourceGroups/oer-s113-rg/providers/Microsoft.Insights/components/oer-s113 web  app"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
    )
    roleManagementPolicies = @([ordered]@{ scope = "$Sql/oer-s113 sales data"; role = 'Reader' })
}
Write-S113Validation -Label '6.3 spaced' -Json $Spaced
$Refused = New-S113Document -Section @{
    roleAssignments = @(
        [ordered]@{ scope = "$Sql/oer-s113-db "; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
        [ordered]@{ scope = "$Sql/oer-s113`tdb"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
        [ordered]@{ scope = "$SubScope/resourceGroups\oer-s113-rg"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
        [ordered]@{ scope = "$Sql/oer-s113-db?x"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
        [ordered]@{ scope = "$Sql/oer-s113-db#1"; role = 'Reader'; principal = 'oer-s113-grp-old'; principalType = 'Group' }
    )
}
[System.IO.File]::WriteAllText((Join-Path $Raw 'doc-section6-round1.json'), $Refused, [System.Text.UTF8Encoding]::new($false))
Write-S113Validation -Label '6.3 refused' -Json $Refused
Disconnect-OerLive
```

**Expect:** spaced: `valid: True; errors: 0; warnings: 0`. Refused: `valid: False; errors: 5`, one
`Error` at each `roleAssignments[N].scope`: N=0 white space at the end of a segment (no code point
named), N=1 white space `It contains U+0009.`, N=2 a `'\'`, N=3 and N=4 a `'?' or '#'`; each message
ends with `A resource whose name holds ... cannot be declared in a document; remove the entry.`
**Failure looks like:** an `Error` in the spaced document (the rule before round 1), or a refused
scope with no finding (`\`, `?` and `#` were accepted before round 1).

Result:

### 6.4. Invoke-OERStructure -WhatIf for the refused document sends nothing

- [ ] **6.4** `Invoke-OERStructure -WhatIf -Prune` refuses the document of 6.3 before it signs in and sends no request.

```powershell
Connect-OerLive -Arm
Start-S113NoPrompt
$Doc = Get-Content -LiteralPath (Join-Path $Raw 'doc-section6-round1.json') -Raw
Invoke-S113Apply -Label '6.4 plan' -Json $Doc -Plan -Prune
Disconnect-OerLive
```

**Expect:** rows 0, warnings 0, one `error: StructureValidationFailed,Invoke-OERStructure: ...` naming
the five findings of 6.3, `token requests: 0; Microsoft Graph requests: 0, writes: 0; Azure Resource
Manager requests: 0, writes: 0`.
**Failure looks like:** any request, or a plan row.

Result:

## 7. New-OERGroup refuses an alias it cannot derive

### 7.1. A name whose derived alias is too long

- [x] **7.1** `New-OERGroup` with a 69-character prefixed name and no `-MailNickname` writes `DerivedMailNicknameInvalid` and creates nothing; only the existence lookup is sent.

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

Result: 2026-10-14 01:43 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. New-OERGroup returned nothing and wrote one DerivedMailNicknameInvalid error: the alias derived from the 69-character name is 69 characters long, Microsoft Graph accepts 1 to 64, nothing was sent. One Microsoft Graph request, a GET (the existence lookup New-OERGroup makes first, since it returns an existing group of that name), no write; no group of that name exists afterwards. Before this branch the alias was sent and Microsoft Graph refused it (1.5: 65 characters, 400 Request_BadRequest).

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 7.1 ===
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] 7.1 output objects: 0; errors of New-OERGroup: 1
[oer-s113] 7.1 error: DerivedMailNicknameInvalid,New-OERGroup: The mail alias derived from the group name 'oer-s113-gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg' is 69 characters long; Microsoft Graph accepts 1 to 64 characters. Nothing was sent. Pass -MailNickname with the alias the group should carry.
[oer-s113] 7.1 sent: token requests: 0; Microsoft Graph requests: 1, writes: 0; Azure Resource Manager requests: 0, writes: 0
[oer-s113] 7.1 Graph requests: GET 
[oer-s113] 7.1 groups named so afterwards: 0
RUNNER: check-7.1 exit code 0; started 2026-10-14T01:42:51Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## T. Teardown

### T.1. Remove every oer-s113- object

- [x] **T.1** The teardown deletes the policy holding the custom extension stage and the custom extension, then the policies, the packages, the catalogs and the group, then the resource group with the Logic App; the sweep finds nothing; the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS113Prereq.ps1') -Teardown -Unattended
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `Teardown A: deleted oer-s113-ap: assignment policy 'oer-s113-policy' (it holds a custom
extension stage)` and `Teardown A: deleted custom extension oer-s113-ext`; the library's removal of the
other policies, the two packages, the two catalogs and the group with residue 0; `Teardown C: deleted
oer-s113-rg and oer-s113-la.`; every `Counts:` line `equal: True`; exit code 0.
**Failure looks like:** a `RESIDUE` line or exit code 3 -- record each residue row here.

Result: 2026-10-14 01:44 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Teardown A deleted oer-s113-policy (it held the custom extension stage) and the custom extension oer-s113-ext (204 each); the library removed the two other policies, the two packages, the two catalogs and the group (removed 7, residue 0, unreadable 0); Teardown C deleted oer-s113-rg and the Logic App oer-s113-la in it (read gone after 62 s). The sweep finds nothing with the prefix and every count equals the baseline; exit code 0.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\teardown-20261014-014308Z.log; OerLive 1.0.3.
[oer-s113] Mode: REMOVE. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] Teardown A: deleted oer-s113-ap: assignment policy 'oer-s113-policy' (it holds a custom extension stage) (204).
[oer-s113] Teardown A: deleted custom extension oer-s113-ext (204, 1 attempt(s)).
[oer-s113] Teardown of 'oer-s113-': users 0, groups 1, access packages 2, catalogs 2; administrative units 0 and app registrations 0 are reported only.
[oer-s113] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s113] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s113] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s113] Deleted: oer-s113-newap: assignment policy 'oer-s113-newpol' (204).
[oer-s113] Deleted: access package oer-s113-newap (204, 1 attempt(s)).
[oer-s113] Deleted: oer-s113-ap: assignment policy 'oer-s113-autopolicy' (204).
[oer-s113] Deleted: access package oer-s113-ap (204, 1 attempt(s)).
[oer-s113] Deleted: catalog oer-s113-newcat (204, 1 attempt(s)).
[oer-s113] Deleted: catalog oer-s113-catalog (204, 1 attempt(s)).
[oer-s113] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s113] Teardown 5/6: the prefixed groups.
[oer-s113] Deleted: group oer-s113-grp-old (204).
[oer-s113] Teardown 6/6: the prefixed users.
[oer-s113] Teardown of 'oer-s113-': removed 7, residue 0, unreadable 0.
[oer-s113] oer-s113-rg is gone: not yet (read 1, 0.5 s, likely replication delay) -- reading again in 2 s.
[oer-s113] oer-s113-rg is gone: not yet (read 2, 2.9 s, likely replication delay) -- reading again in 4 s.
[oer-s113] oer-s113-rg is gone: not yet (read 3, 6.9 s, likely replication delay) -- reading again in 8 s.
[oer-s113] oer-s113-rg is gone: not yet (read 4, 15.1 s, likely replication delay) -- reading again in 16 s.
[oer-s113] oer-s113-rg is gone: not yet (read 5, 31.5 s, likely replication delay) -- reading again in 30 s.
[oer-s113] oer-s113-rg is gone: converged after 6 read(s), 62 s.
[oer-s113] Teardown C: deleted oer-s113-rg and oer-s113-la.
[oer-s113] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s113-' is left.
[oer-s113] no 'oer-s113-' object is listed: converged after 1 read(s), 0.6 s.
[oer-s113] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s113-' is left.
[oer-s113] Resource group oer-s113-rg exists after the teardown: False
[oer-s113] Counts: groups now 97, at the baseline 97; equal: True
[oer-s113] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s113] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s113] Removed the recorded ids.
[oer-s113] Done.
[oer-s113] exit code: 0
RUNNER: check-T.1 exit code 0; started 2026-10-14T01:43:06Z; took 79 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### T.2. Read back

- [x] **T.2** Nothing with the prefix is left, and the counts equal the baseline.

```powershell
& pwsh -NoProfile -NonInteractive -File (Join-Path $env:OER_LIVE_DIR 'Initialize-OerS113Prereq.ps1') -ReadBack
Write-OerLiveStep "exit code: $LASTEXITCODE"
```

**Expect:** `resource group oer-s113-rg exists: False`; every `Counts:` line `equal: True`;
`prefixed objects left: 0; unread collections: 0`; no residue row with this step's prefix.
**Failure looks like:** anything left with the prefix.

Result: 2026-10-14 01:44 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Nothing with the prefix is left, no resource group oer-s113-rg, every count equal to the baseline, no unread collection; raw\residue.json holds 5 rows of other prefixes (opim-s1-, opim-s2-), none of this step's, untouched.

=== Run ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.2 ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s113] Transcript (redacted): raw\s113\readback-20261014-014427Z.log; OerLive 1.0.3.
[oer-s113] Mode: READ BACK. Prefix 'oer-s113-'. Objects (fixed): oer-s113-grp-old (security group, no member); oer-s113-catalog (catalog, no resource); oer-s113-ap (hidden access package, no resource role); oer-s113-rg (tagged) with oer-s113-la (Logic App, nothing calls it); oer-s113-ext (custom extension); oer-s113-policy (requestable by the members of oer-s113-grp-old only, one question, the custom extension stage); oer-s113-autopolicy (automatic, its rule matches no user). The checklist's own objects: oer-s113-newcat, oer-s113-newap and its policy. OerLive 1.0.3.
[oer-s113] Omnicit.EntraRBAC 1.2.1 loaded from REPO\.claude\worktrees\s11-steg3\output\module\Omnicit.EntraRBAC\1.2.1.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s113] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s113] Residue: raw\residue.json holds 5 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s113] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s113-' is left.
[oer-s113] Read-back: resource group oer-s113-rg exists: False
[oer-s113] Counts: groups now 97, at the baseline 97; equal: True
[oer-s113] Counts: catalogs now 5, at the baseline 5; equal: True
[oer-s113] Counts: accessPackages now 6, at the baseline 6; equal: True
[oer-s113] Read-back: residue row: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:09Z, attempts 3: 404 SubjectNotFound The subject is not found.; read back: still listed -- OerLive: Residue: PIM for Groups eligibility 'opim-s1-grp: PIM for Groups owner eligibility of a principal': read back after the 'does not exist' answer -- not converged within budget (180 s, 10 reads).
[oer-s113] Read-back: residue row: PIM for Groups assignment 'opim-s1-grp: PIM for Groups owner assignment of a principal' (prefix opim-s1-), first refused 2026-10-08T18:43:12Z, attempts 3: 403 UnauthorizedAccessException {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup,PrivilegedAccess.ReadWrite.AzureADGroup,PrivilegedAssignmentSchedule.Remove.AzureADGroup.","instanceAnnotations":[]}
[oer-s113] Read-back: residue row: PIM for Groups eligibility 'opim-s2-grp: PIM for Groups member eligibility of a principal' (prefix opim-s2-), first refused 2026-10-10T23:39:01Z, attempts 1: 400 BadRequest {"error":{"code":"Request_BadRequest","message":"The source resource object or one of the objects being referenced do not exist.","innerError":{"date":"2026-10-10T23:39:01","request-id":"00000000-0000-0000-0000-000000000007","client-request-id":"00000000-0000-0000-0000-000000000009"}}}
[oer-s113] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-10T23:39:02Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s113] Read-back: residue row: user 'opim-s2-live-user@example.com' (prefix opim-s2-), first refused 2026-10-11T14:55:13Z, attempts 1: 403 Authorization_RequestDenied Insufficient privileges to complete the operation.
[oer-s113] Read-back: prefixed objects left: 0; unread collections: 0; residue rows: 5, of them with this step's prefix: 0.
[oer-s113] Done.
[oer-s113] exit code: 0
RUNNER: check-T.2 exit code 0; started 2026-10-14T01:44:25Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

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
  `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`. Round 1 (F): every white space case, a no-break
  space, an em space and a control character by code point, `\`, `?` and `#` in the same Describe; an
  export with a role assignment at a resource whose name holds spaces is valid, and one whose name holds
  a `#` is refused, in `tests/Unit/Public/Get-OERInventory.Tests.ps1` and in the self-check of
  `tests/Unit/Public/Export-OERInventory.Tests.ps1` (no test tenant role assignment is at such a
  resource).
- **The texts**: `tests/QA/docsync.tests.ps1`, `tests/QA/about.tests.ps1`, `tests/QA/dochygiene.tests.ps1`,
  `tests/Unit/Private/Get-OERStructureSchemaJson.Tests.ps1` and
  `tests/Unit/Private/Get-OERInventoryPromptTemplate.Tests.ps1`.
