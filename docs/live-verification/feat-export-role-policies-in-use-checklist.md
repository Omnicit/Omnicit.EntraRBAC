# Live verification checklist -- the export keeps only the Azure role policies in use (feat/export-role-policies-in-use)

**This branch does not merge until every box in sections S, 0, 1, 2, 3 and T has a written result.**
A box with no result line filled in is not a passed check -- it is an unrun one. If a check turns
out to be impossible to run, write "cannot be verified, and therefore we do not know" on its result
line and say why; do not leave it blank and do not tick it. A check that could not run for a stated
reason is marked `[~]`, never `[x]`. **Section B lists what is proved offline only (class B).**
Nothing here is class C.

**What this file writes to the tenant.** The prerequisite script `Initialize-OerS109Prereq.ps1`
(beside OerLive, outside the repository) creates the security group `oer-s109-principal` with no
member, the resource group `oer-s109-rg` in the test subscription (tagged, empty) and, at that
resource group, for that group: a role assignment of the built-in role Reader and a time-bound (P7D)
eligibility of the built-in role Monitoring Reader. It records the baseline of the Log Analytics
Reader policy at `oer-s109-rg` before check 2.3 changes it once (activation maximum PT4H). Nothing
outside the prefix is written: section 3 applies a document holding only `oer-s109-rg`'s policies,
and only plans (`-WhatIf`) the subscription's. The teardown (T.1) puts the policy back from the
baseline, removes the two grants, the group and the resource group. The bundles, the request logs and
the kept build of `944976f` are written under `raw\s109\`, which the teardown deletes.

**Who runs it.** Every section: the dedicated certificate identity `oer-live-cc`, through the OerLive
library, which lives beside the operator's copy of this file outside the repository
([README.md](README.md), first paragraph). Every sign-in is app-only, with the certificate; nothing
here signs in as a person.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s109/`,
which is git-ignored. Every block prints through the library's redactor, and the helpers print
counts, True/False and the names of Microsoft's built-in roles only -- never a principal, never an
id. Each block is run in its own process whose whole output (standard output and standard error) is
written to a file, redacted with OerLive's redactor and a mask for any GUID the redactor did not
number, checked for every configuration value, and only then read.

## What changed and why this needs a live tenant

Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main`
before it merges.

- **A. The selection.** Without `-AllRolePolicies`, `Export-OERInventory -Include RoleManagementPolicies`
  keeps a role's policy at a scope only when the role has a role assignment or an eligibility listed
  EXACTLY at that scope, or the policy has been changed: the list row's
  `policyAssignmentProperties.policy` carries a `lastModifiedDateTime`, or a `lastModifiedBy` with an
  `id` or a `displayName` (measured before the code, below). The policies are still read with the one
  paged policy-assignment list per scope; the selection adds one paged role assignment list
  (`atScope()`) per scope and no request per policy. A policy that cannot be judged because a read
  failed is kept and named in `IncompleteReads` as `roleManagementPolicies/role selection at` followed
  by the scope.
- **B. `-AllRolePolicies`.** Keeps every policy, through exactly the per-scope call the export made
  before this branch.

What a live tenant adds: the real list answers the rule reads (0.3), an export of the test
subscription with the `944976f` build and with this branch giving the policies of the roles in use
or changed and nothing else, each entry identical to the old one (1.1, 1.2), `-AllRolePolicies`
giving the old file exactly (1.3), the same at the test resource group, where the grants are this
step's own (2.1, 2.2, 2.5), a change to a policy there turning the rule on for it (2.3, 2.4), and the
exported document converging (3.1, G8).

### The measurement this branch rests on (read-only, before the code, 2026-10-10)

Read as `oer-live-cc` on the test subscription, from the policy-assignment list the export reads:
967 rows, every one a built-in role at the subscription itself, every one carrying
`policyAssignmentProperties.policy`. 965 rows carry no `lastModifiedDateTime` key and an EMPTY
`lastModifiedBy` object, and all 965 share one identical effective rule set. 2 rows carry a
`lastModifiedDateTime` (a date) and a `lastModifiedBy` with a `displayName` only, and their rule sets
differ from the 965's. The policies list agrees row for row; `isOrganizationDefault` is `false` on
all 967, so it is no signal. Exactly at the subscription: 6 role assignments over 3 roles, no
eligibility. The rule keeps 4 of 967.

## What this file does not check, and why

- **A read the selection needs that fails.** `oer-live-cc` can read every list here, so no policy is
  kept unjudged live; that path is class B.
- **A management group scope.** `oer-live-cc` is refused the management group listing (measured in
  step 7), so the walk reads the subscription only; an assignment or eligibility at a management
  group is class B.
- **A change that leaves no record.** Not producible on purpose; the measurement found none (every
  row without a record carries the one default rule set).
- **Philip's tenant.** The count there (18 366 policies on 19 scopes before this branch) is his run
  after the merge.

## Setup, once

**You need:**

- The **test tenant** -- never a customer tenant -- and the two configuration files OerLive reads
  beside it (tenant values live there and nowhere else).
- **OerLive 1.0.3** in the same folder; the environment variable `OER_LIVE_DIR` names that folder.
- The **dedicated certificate identity** `oer-live-cc` enabled for the run.
- The **built module of this branch** in the step's own worktree (`./build.ps1 -Tasks build`), and
  the environment variable `OER_LIVE_REPO` naming that worktree. H.1 sets the session's `Repo` to it.
- The **build of `origin/main` at `944976f`** (the commit this branch starts from), copied to
  `raw\s109\before-944976f\output\module\Omnicit.EntraRBAC\` before this branch's first build.
  Sections 1.1 and 2.1 load it; it uses the worktree's `output\RequiredModules`.

**Run every numbered block in its OWN PowerShell process, after H.1 in the same process.**

### H.1. Shared helpers

Run first in every process. It loads OerLive and the configuration (`oer-testmiljo.psd1` and
`oer-cc-identitet.psd1`), and defines the fences, the request log and the readers. Nothing here signs
in or writes to the tenant.

```powershell
$VaultDir = $env:OER_LIVE_DIR
Import-Module (Join-Path $VaultDir 'OerLive\OerLive.psm1') -Force
$Cfg = Import-OerLiveConfig -Prefix 'oer-s109-' -ConfigDirectory $VaultDir
$Raw = Join-Path $Cfg.Repo 'docs\live-verification\raw\s109'
$Before = Join-Path $Raw 'before-944976f'
if ($env:OER_LIVE_REPO) { $Cfg.Repo = $env:OER_LIVE_REPO }
New-Item -ItemType Directory -Force -Path $Raw | Out-Null
$SubScope = "/subscriptions/$($Cfg.SubscriptionId)"
$RgScope = "$SubScope/resourceGroups/oer-s109-rg"
$Assign = 'Reader'
$Elig = 'Monitoring Reader'
$Change = 'Log Analytics Reader'
$Untouched = 'Storage Blob Data Reader'
$StepRoles = @($Assign, $Elig, $Change, $Untouched, 'Owner')

function Import-S109Before {
    # The kept 944976f build, loaded before any sign-in so OerLive does not load this branch's build.
    $Mod = Get-ChildItem -Path (Join-Path $Before 'output\module\Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psd1') | Select-Object -First 1
    $Req = Join-Path $Cfg.Repo 'output\RequiredModules'
    $env:PSModulePath = (Resolve-Path $Req).Path + [System.IO.Path]::PathSeparator + $env:PSModulePath
    Import-Module -Name $Mod.FullName -Force -Global
    Write-OerLiveStep "module loaded from the kept 944976f build: $((Get-Module -Name Omnicit.EntraRBAC).ModuleBase.StartsWith($Before, [System.StringComparison]::OrdinalIgnoreCase))"
}

function Start-S109Fence {
    # Get-AzToken forwards only a request that carries the certificate, so nothing can prompt. In the
    # module's own scope, Invoke-OERArmRequest is wrapped once: each request's method and path are
    # recorded in memory, for the request log, and never printed.
    $global:S109Token = [System.Collections.Generic.List[string]]::new()
    $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Get-AzToken -CommandType Cmdlet))
    $Body = 'end { $global:S109Token.Add(((@($PSBoundParameters.Keys) | Sort-Object) -join '','')); if (-not $PSBoundParameters.ContainsKey(''ClientCertificate'')) { throw ''S109 fence: a token request without the certificate was refused; nothing prompts.'' }; AzAuth\Get-AzToken @PSBoundParameters }'
    $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
    Set-Item -Path function:global:Get-AzToken -Value ([scriptblock]::Create($Text))
    $global:S109Arm = [System.Collections.Generic.List[object]]::new()
    & (Get-Module -Name Omnicit.EntraRBAC) {
        if (-not $script:S109OriginalArm) { $script:S109OriginalArm = (Get-Command -Name Invoke-OERArmRequest -CommandType Function).ScriptBlock }
        $Meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Name Invoke-OERArmRequest -CommandType Function))
        $Body = 'end { $M = if ($PSBoundParameters.ContainsKey(''Method'')) { [string]$PSBoundParameters[''Method''] } else { ''GET'' }; $global:S109Arm.Add([PSCustomObject]@{ Method = $M.ToUpperInvariant(); Path = [string]$PSBoundParameters[''Path''] }); & $script:S109OriginalArm @PSBoundParameters }'
        $Text = "$([System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($Meta))`nparam($([System.Management.Automation.ProxyCommand]::GetParamBlock($Meta)))`n$Body"
        Set-Item -Path function:script:Invoke-OERArmRequest -Value ([scriptblock]::Create($Text))
    }
    $Seen = & (Get-Module -Name Omnicit.EntraRBAC) { '{0},{1}' -f (Get-Command Get-AzToken).CommandType, ([bool]((Get-Command Invoke-OERArmRequest).ScriptBlock.ToString() -match 'S109Arm')) }
    Write-OerLiveStep "fences in place (Get-AzToken is the proxy, the ARM wrapper records): $($Seen -eq 'Function,True')"
}

function Reset-S109Requests { $global:S109Token.Clear(); $global:S109Arm.Clear() }

function Save-S109RequestLog {
    # The request log of one run: one line per ARM request the module made, "METHOD path", every id
    # replaced by its placeholder through OerLive's redactor.
    param([Parameter(Mandatory)][string]$Name)
    $Path = Join-Path $Raw "requests-$Name.log"
    $Lines = @($global:S109Arm | ForEach-Object { ConvertTo-OerLiveRedacted -Text ('{0} {1}' -f $_.Method, [uri]::UnescapeDataString($_.Path)) })
    [System.IO.File]::WriteAllLines($Path, [string[]]$Lines, [System.Text.UTF8Encoding]::new($false))
    Write-OerLiveStep "request log: $($Lines.Count) ARM request(s) written to raw\s109\requests-$Name.log; token requests: $($global:S109Token.Count)"
}

function Write-S109ArmCount {
    # The ARM requests of the in-memory log by kind (a paged list is ONE call: the wrapper pages it), and
    # the writes. A single-policy read is a request for one roleManagementPolicies resource.
    param([Parameter(Mandatory)][string]$Label)
    $L = @($global:S109Arm)
    $Kind = {
        param($P)
        switch -Regex ($P) {
            'roleManagementPolicyAssignments' { 'policy list'; break }
            '/roleManagementPolicies/[^/?]+' { 'single policy'; break }
            'roleAssignments\?.*atScope' { 'role assignments atScope'; break }
            'roleAssignments' { 'role assignments'; break }
            'roleEligibilitySchedules' { 'eligibility'; break }
            'roleDefinitions' { 'role definition'; break }
            'managementGroups|getEntities' { 'management groups'; break }
            '^/subscriptions\?' { 'subscriptions'; break }
            default { 'other' }
        }
    }
    $Groups = @($L | Group-Object { & $Kind ([uri]::UnescapeDataString($_.Path)) } | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" })
    Write-OerLiveStep "$($Label): ARM requests $($L.Count) ($($Groups -join '; ')); writes $(@($L | Where-Object { $_.Method -ne 'GET' }).Count)"
}

function Write-S109Own {
    # A command's OWN records in an -ErrorVariable (the id ends in a comma and the command's name), as ids only.
    param([object[]]$Records, [string]$Command)
    $Own = @($Records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and ([string]$_.FullyQualifiedErrorId).EndsWith(",$Command") })
    Write-OerLiveStep ("{0} own errors: {1}{2}" -f $Command, $Own.Count, $(if ($Own.Count) { ' -- ' + (($Own | ForEach-Object { $_.FullyQualifiedErrorId }) -join '; ') } else { '' }))
}

function Get-S109Live {
    # An independent read of one scope through OerLive's transport, not through the code under test: the
    # policy-assignment list (each role's name, whether it is built in, its role definition guid, and
    # whether its policy carries a lastModifiedDateTime, a lastModifiedBy.id or a lastModifiedBy.displayName),
    # and the role assignments and eligibility schedules listed EXACTLY at the scope and above it.
    param([Parameter(Mandatory)][string]$Scope)
    $Guid = { param($Id) (([string]$Id).TrimEnd('/') -split '/')[-1].ToLowerInvariant() }
    $L = Invoke-OerLiveArm -All -Path "$Scope/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01"
    Assert-OerLiveOk -Response $L -Activity 'Listing the policy assignments' | Out-Null
    $Policies = @(@($L.Body.value) | Where-Object { $null -ne $_ } | ForEach-Object {
            $P = $_.properties.policyAssignmentProperties.policy
            [PSCustomObject]@{
                Role        = [string]$_.properties.policyAssignmentProperties.roleDefinition.displayName
                BuiltIn     = ([string]$_.properties.policyAssignmentProperties.roleDefinition.type -eq 'BuiltInRole')
                Guid        = & $Guid $_.properties.roleDefinitionId
                HasMetadata = ($null -ne $P)
                Changed     = [bool]($null -ne $P -and ("$($P.lastModifiedDateTime)".Trim() -or "$($P.lastModifiedBy.id)".Trim() -or "$($P.lastModifiedBy.displayName)".Trim()))
            }
        })
    $IsHere = { param($Row) [string]::Equals(([string]$Row.properties.scope).TrimEnd('/'), $Scope, [System.StringComparison]::OrdinalIgnoreCase) }
    $Ra = Invoke-OerLiveArm -All -Path "$Scope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
    Assert-OerLiveOk -Response $Ra -Activity 'Listing the role assignments' | Out-Null
    $El = Invoke-OerLiveArm -All -Path "$Scope/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01&`$filter=atScope()"
    Assert-OerLiveOk -Response $El -Activity 'Listing the eligibility schedules' | Out-Null
    $RaRows = @(@($Ra.Body.value) | Where-Object { $null -ne $_ })
    $ElRows = @(@($El.Body.value) | Where-Object { $null -ne $_ })
    [PSCustomObject]@{
        Policies      = $Policies
        Assigned      = @($RaRows | Where-Object { & $IsHere $_ } | ForEach-Object { & $Guid $_.properties.roleDefinitionId } | Select-Object -Unique)
        AssignedAbove = @($RaRows | Where-Object { -not (& $IsHere $_) } | ForEach-Object { & $Guid $_.properties.roleDefinitionId } | Select-Object -Unique)
        Eligible      = @($ElRows | Where-Object { & $IsHere $_ } | ForEach-Object { & $Guid $_.properties.roleDefinitionId } | Select-Object -Unique)
    }
}

function Write-S109Live {
    # Counts of one live read, the policies the rule keeps there (built-in role names only), and each
    # step role's facts. Returns the policies the rule keeps.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][object]$Live)
    $InUse = @(@($Live.Assigned) + @($Live.Eligible) | Select-Object -Unique)
    $Kept = @($Live.Policies | Where-Object { $InUse -contains $_.Guid -or $_.Changed -or -not $_.HasMetadata })
    Write-OerLiveStep ("{0}: policies listed {1} (built in {2}); changed {3}; without a policy record {4}; roles assigned exactly here {5}; eligible exactly here {6}" -f $Label, @($Live.Policies).Count, @($Live.Policies | Where-Object BuiltIn).Count, @($Live.Policies | Where-Object Changed).Count, @($Live.Policies | Where-Object { -not $_.HasMetadata }).Count, @($Live.Assigned).Count, @($Live.Eligible).Count)
    Write-OerLiveStep ("{0}: the rule keeps {1}: {2}" -f $Label, $Kept.Count, (($Kept | Sort-Object Role | ForEach-Object { if ($_.BuiltIn) { $_.Role } else { 'a custom role' } }) -join ', '))
    foreach ($R in $StepRoles) {
        $P = @($Live.Policies | Where-Object { $_.Role -ceq $R })
        if ($P.Count -ne 1) { Write-OerLiveStep "$($Label): $R listed $($P.Count) time(s)"; continue }
        Write-OerLiveStep ("{0}: {1}: assigned here {2}; eligible here {3}; assigned above {4}; changed {5}" -f $Label, $R, ($Live.Assigned -contains $P[0].Guid), ($Live.Eligible -contains $P[0].Guid), ($Live.AssignedAbove -contains $P[0].Guid), $P[0].Changed)
    }
    $Kept
}

function Invoke-S109Export {
    # One export into a folder of raw\s109 named after it, fenced; the request log written; the bundle
    # summary, the warnings and the export's own errors printed (redacted).
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Include, [hashtable]$Extra = @{})
    Reset-S109Requests
    $Out = Export-OERInventory -OutputPath (Join-Path $Raw "bundle-$Name") -Include $Include -Force -ErrorAction Continue -ErrorVariable ExErr -WarningVariable ExWarn -WarningAction SilentlyContinue @Extra
    Save-S109RequestLog -Name $Name
    Write-OerLiveStep ("bundle {0}: roleManagementPolicies {1}; roleAssignments {2}; scopes read {3} of {4}; skipped scopes {5}{6}; IncompleteReads {7}{8}; warnings {9}" -f $Name, $Out.RoleManagementPolicies, $Out.RoleAssignments, $Out.ScopeCount, $Out.ScopesEnumerated, @($Out.SkippedScopes).Count, $(if (@($Out.SkippedScopes).Count) { ' (' + (@($Out.SkippedScopes) -join '; ') + ')' }), @($Out.IncompleteReads).Count, $(if (@($Out.IncompleteReads).Count) { ' (' + (@($Out.IncompleteReads) -join '; ') + ')' }), @($ExWarn).Count)
    foreach ($W in @($ExWarn)) { Write-OerLiveStep "warning: $W" }
    Write-S109Own -Records $ExErr -Command 'Export-OERInventory'
    Copy-Item -LiteralPath $Out.BundlePath -Destination (Join-Path $Raw $Name) -Recurse -Force
    $Out
}

function Get-S109Policies {
    # The entries of a kept bundle's roleManagementPolicies.json, in file order.
    param([Parameter(Mandatory)][string]$Name)
    @(Get-Content -LiteralPath (Join-Path $Raw "$Name\roleManagementPolicies.json") -Raw | ConvertFrom-Json -NoEnumerate | ForEach-Object { $_ } | Where-Object { $null -ne $_ })
}

function Get-S109At {
    # The entries at one scope as role name -> compact JSON (built-in role names are unique per scope).
    param([object[]]$Entries, [Parameter(Mandatory)][string]$Scope)
    $T = [ordered]@{}
    foreach ($E in @($Entries | Where-Object { [string]::Equals(([string]$_.scope).TrimEnd('/'), $Scope, [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object role)) {
        $T[[string]$E.role] = ConvertTo-Json -InputObject $E -Depth 30 -Compress
    }
    $T
}

function Compare-S109At {
    # Two scope tables: how many roles only on one side, and which roles on both sides differ in content.
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Left, [Parameter(Mandatory)][System.Collections.IDictionary]$Right, [Parameter(Mandatory)][string]$Label)
    $OnlyL = @($Left.Keys | Where-Object { -not $Right.Contains($_) })
    $OnlyR = @($Right.Keys | Where-Object { -not $Left.Contains($_) })
    $Diff = @($Left.Keys | Where-Object { $Right.Contains($_) -and $Left[$_] -cne $Right[$_] })
    Write-OerLiveStep ("{0}: left {1}, right {2}; only left {3}; only right {4}; same role, different content {5}{6}" -f $Label, $Left.Count, $Right.Count, $OnlyL.Count, $OnlyR.Count, $Diff.Count, $(if ($Diff.Count) { ': ' + ($Diff -join ', ') }))
}

function Write-S109Kept {
    # What an export kept at a scope against what the independent rule keeps, and each step role.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][System.Collections.IDictionary]$At, [object[]]$Expected)
    $Want = @($Expected | ForEach-Object { $_.Role } | Sort-Object)
    $Got = @($At.Keys | Sort-Object)
    Write-OerLiveStep ("{0}: kept {1}; the independent rule keeps {2}; the same roles: {3}" -f $Label, $Got.Count, $Want.Count, (($Got -join '|') -ceq ($Want -join '|')))
    foreach ($R in $StepRoles) { Write-OerLiveStep "$($Label): $R kept: $($At.Contains($R))" }
}
```

### S.1. The module loads from this branch's build, and the 944976f build is kept

- [ ] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch; the main clone is on `main`, never switched; the kept `944976f` build carries none of this branch's changes.

```powershell
$List = @(git -C $Cfg.Repo worktree list --porcelain)
$MainPath = [System.IO.Path]::GetFullPath(($List[0] -replace '^worktree ', '')).TrimEnd('\', '/')
$MainBranch = ([string]($List | Where-Object { $_ -like 'branch *' -or $_ -eq 'detached' } | Select-Object -First 1)) -replace '^branch refs/heads/', ''
Write-OerLiveStep "The module loads from a worktree that is not the main clone: $([System.IO.Path]::GetFullPath($Cfg.Repo).TrimEnd('\', '/') -ne $MainPath)"
Write-OerLiveStep "Main clone: branch $MainBranch"
Write-OerLiveStep "Worktree: branch $(git -C $Cfg.Repo branch --show-current); HEAD $(git -C $Cfg.Repo log -1 --format='%h %s'); tracked changes: $(@(git -C $Cfg.Repo status --porcelain --untracked-files=no).Count)"
$Marks = @('function Select-OERInventoryRolePolicy', 'function Test-OERRolePolicyModified', 'function Get-OERInventoryRolePolicy', '[switch]$AllRolePolicies')
foreach ($Side in @(@('this branch', (Join-Path $Cfg.Repo 'output\module')), @('944976f', (Join-Path $Before 'output\module')))) {
    $Psm1 = Get-ChildItem -Path (Join-Path $Side[1] 'Omnicit.EntraRBAC\*\Omnicit.EntraRBAC.psm1') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $Psm1) { Write-OerLiveStep "$($Side[0]) build: not found"; continue }
    $Hits = @($Marks | Where-Object { Select-String -LiteralPath $Psm1.FullName -SimpleMatch $_ -Quiet }).Count
    $Ver = (Import-PowerShellDataFile -LiteralPath ($Psm1.FullName -replace '\.psm1$', '.psd1'))
    Write-OerLiveStep "$($Side[0]) build: version $($Ver.ModuleVersion) $($Ver.PrivateData.PSData.Prerelease); marks of this branch: $Hits of $($Marks.Count)"
}
```

**Expect:** `The module loads from a worktree that is not the main clone: True`; the main clone on
`main`; the worktree at this branch's head with 0 tracked changes; `this branch build: ... marks of
this branch: 4 of 4`; `944976f build: ... marks of this branch: 0 of 4`.
**Failure looks like:** `False` on the first line (`OER_LIVE_REPO` unset), fewer than 4 marks in this
branch's build (build it first, never while the gate runs), or any mark in the `944976f` build.

Result: not run yet.

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [ ] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

```powershell
Connect-OerLive -Arm
$M = Get-Module -Name Omnicit.EntraRBAC
Write-OerLiveStep "The module is the worktree's build: $($M.ModuleBase.StartsWith((Join-Path $Cfg.Repo 'output\module'), [System.StringComparison]::OrdinalIgnoreCase))"
Disconnect-OerLive
```

**Expect:** every identity line `True`, `identity check passed: True`, and `The module is the
worktree's build: True`.
**Failure looks like:** any `False`, or `application is disabled` -- STOP: the identity is not
enabled for this run; never sign in another way.

Result: not run yet.

### 0.2. The prerequisite: the group, the resource group and the two grants, after a plan

- [ ] **0.2** `Initialize-OerS109Prereq.ps1 -WhatIf` writes nothing and plans every object; the real run writes the baseline, creates the group and the resource group, records the Log Analytics Reader policy baseline, and creates the role assignment and the eligibility; a second run finds every object and writes nothing.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS109Prereq.ps1'
foreach ($Run in @(@('-WhatIf'), @('-Unattended'), @('-Unattended'))) {
    Write-OerLiveStep "prereq run: $($Run -join ' ')"
    & pwsh -NoProfile -NonInteractive -File $Script @Run 2>&1 | ForEach-Object { "$_" }
    Write-OerLiveStep "prereq exit code: $LASTEXITCODE"
}
```

**Expect:** the plan run ends `WhatIf: nothing was created, removed or written.` with exit code 0;
the first real run writes the baseline, creates `oer-s109-principal` and `oer-s109-rg`, records the
policy baseline, creates the role assignment and requests the eligibility, each awaited until it is
listed, exit code 0; the second real run finds every object and both grants, `written to the tenant:
False`, exit code 0.
**Failure looks like:** a refusal, an exit code other than 0, or a second run that writes.

Result: not run yet.

### 0.3. What the lists say, read independently of the code under test

- [ ] **0.3** Read through OerLive's transport: at the subscription, the policies listed, how many are changed, the roles assigned or eligible exactly there, and the policies the rule keeps; at `oer-s109-rg`, the same, with Reader assigned and Monitoring Reader eligible exactly there, Owner assigned above it only, and no policy changed yet.

```powershell
Connect-OerLive -Arm
$null = Write-S109Live -Label 'subscription' -Live (Get-S109Live -Scope $SubScope)
$null = Write-S109Live -Label 'oer-s109-rg' -Live (Get-S109Live -Scope $RgScope)
Disconnect-OerLive
```

**Expect:** at the subscription the counts of the measurement above (967 listed, 2 changed, the rule
keeps 4) unless the tenant changed since; Monitoring Reader and Storage Blob Data Reader neither
assigned nor eligible there and not changed. At `oer-s109-rg`: no policy changed; Reader `assigned
here True`; Monitoring Reader `eligible here True`; Owner `assigned here False; assigned above True`;
Log Analytics Reader and Storage Blob Data Reader not assigned, not eligible, not changed; the rule
keeps exactly Monitoring Reader and Reader.
**Failure looks like:** a grant not listed (replication: read again a minute later), a policy at
`oer-s109-rg` already changed, or a step role listed other than once.

Result: not run yet.

## 1. The test subscription: before and after (A, B)

### 1.1. Export with the 944976f build (the reference)

- [ ] **1.1** `Export-OERInventory -Include RoleAssignments, RoleManagementPolicies` with the kept `944976f` build writes a bundle under `raw\s109\before-sub\` holding every policy at the subscription, and a request log.

```powershell
Import-S109Before
Connect-OerLive -Arm
Start-S109Fence
$null = Invoke-S109Export -Name 'before-sub' -Include RoleAssignments, RoleManagementPolicies
Write-S109ArmCount -Label 'before-sub'
$E = Get-S109Policies -Name 'before-sub'
Write-OerLiveStep "before-sub: entries at the subscription $((Get-S109At -Entries $E -Scope $SubScope).Count); entries in all $($E.Count)"
Disconnect-OerLive
```

**Expect:** `module loaded from the kept 944976f build: True`; the management group listing refused
(one skipped scope, the level of management groups) and the subscription read; every policy 0.3
listed at the subscription is in the file; `policy list 1`, no `single policy`, writes 0.
**Failure looks like:** the module loaded from another build, a scope other than the management group
level skipped, or a policy count other than 0.3's.

Result: not run yet.

### 1.2. Export with this branch: only the policies in use or changed, each the same as before

- [ ] **1.2** The same export with this branch keeps at the subscription exactly the policies the independent rule keeps (0.3), each entry identical to 1.1's; Monitoring Reader (eligible only at `oer-s109-rg`) and Storage Blob Data Reader (untouched) are left out; the policies are still read with one list for the scope, plus one `atScope()` role assignment list, and nothing per policy; `IncompleteReads` names no role selection.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$Expected = Write-S109Live -Label 'subscription' -Live (Get-S109Live -Scope $SubScope)
$null = Invoke-S109Export -Name 'after-sub' -Include RoleAssignments, RoleManagementPolicies
Write-S109ArmCount -Label 'after-sub'
$After = Get-S109At -Entries (Get-S109Policies -Name 'after-sub') -Scope $SubScope
Write-S109Kept -Label 'after-sub' -At $After -Expected $Expected
$BeforeAt = Get-S109At -Entries (Get-S109Policies -Name 'before-sub') -Scope $SubScope
$Same = @($After.Keys | Where-Object { $BeforeAt.Contains($_) -and $BeforeAt[$_] -ceq $After[$_] }).Count
Write-OerLiveStep "after-sub: kept entries identical to the same role's entry in before-sub: $Same of $($After.Count)"
$Ra = @{ before = (Get-Content -LiteralPath (Join-Path $Raw 'before-sub\roleAssignments.json') -Raw); after = (Get-Content -LiteralPath (Join-Path $Raw 'after-sub\roleAssignments.json') -Raw) }
Write-OerLiveStep "roleAssignments.json identical to before-sub: $($Ra.before -ceq $Ra.after)"
Disconnect-OerLive
```

**Expect:** `the same roles: True`, with the count 0.3 printed for the subscription (4 at the
measurement); Monitoring Reader, Log Analytics Reader and Storage Blob Data Reader `kept: False`;
every kept entry identical to 1.1's; `roleAssignments.json identical to before-sub: True`;
`policy list 1`, `role assignments atScope 1`, no `single policy`, writes 0; `IncompleteReads` as in
1.1 (no `roleManagementPolicies/` entry).
**Failure looks like:** a role kept that the rule does not keep or the reverse, an entry that differs
from 1.1's, a `single policy` request, or a role selection entry.

Result: not run yet.

### 1.3. -AllRolePolicies writes what the 944976f build wrote

- [ ] **1.3** `-AllRolePolicies` with this branch writes `roleManagementPolicies.json` identical to 1.1's, in order and content, with the same count, and makes no `atScope()` role assignment request.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$null = Invoke-S109Export -Name 'all-sub' -Include RoleAssignments, RoleManagementPolicies -Extra @{ AllRolePolicies = $true }
Write-S109ArmCount -Label 'all-sub'
$L = Get-S109Policies -Name 'before-sub'
$R = Get-S109Policies -Name 'all-sub'
Write-OerLiveStep "all-sub: entries $($R.Count); before-sub: $($L.Count); the same count: $($R.Count -eq $L.Count)"
Compare-S109At -Left (Get-S109At -Entries $L -Scope $SubScope) -Right (Get-S109At -Entries $R -Scope $SubScope) -Label 'before-sub against all-sub'
$Text = @{ before = (Get-Content -LiteralPath (Join-Path $Raw 'before-sub\roleManagementPolicies.json') -Raw); all = (Get-Content -LiteralPath (Join-Path $Raw 'all-sub\roleManagementPolicies.json') -Raw) }
Write-OerLiveStep "roleManagementPolicies.json identical to before-sub, byte for byte: $($Text.before -ceq $Text.all)"
Disconnect-OerLive
```

**Expect:** the same count as 1.1; `only left 0; only right 0; same role, different content 0`;
`identical to before-sub, byte for byte: True`; no `role assignments atScope` request.
**Failure looks like:** any difference from 1.1.

Result: not run yet.

## 2. The test resource group: the grants and the change are this step's own

### 2.1. Export of oer-s109-rg with the 944976f build (the reference)

- [ ] **2.1** `Export-OERInventory -Scope` (the resource group) `-Include RoleManagementPolicies` with the kept `944976f` build writes every policy listed at `oer-s109-rg`.

```powershell
Import-S109Before
Connect-OerLive -Arm
Start-S109Fence
$null = Invoke-S109Export -Name 'before-rg' -Include RoleManagementPolicies -Extra @{ Scope = $RgScope }
Write-S109ArmCount -Label 'before-rg'
Write-OerLiveStep "before-rg: entries at oer-s109-rg $((Get-S109At -Entries (Get-S109Policies -Name 'before-rg') -Scope $RgScope).Count)"
Disconnect-OerLive
```

**Expect:** one scope read, none skipped; as many entries as 0.3 listed at `oer-s109-rg`;
`policy list 1`, writes 0.
**Failure looks like:** a skipped scope, or another count than 0.3's.

Result: not run yet.

### 2.2. This branch at oer-s109-rg before the change: the assigned role and the eligible role only

- [ ] **2.2** This branch keeps at `oer-s109-rg` exactly Reader (assigned there) and Monitoring Reader (eligible there), each identical to 2.1's entry; Owner, assigned only above the resource group, and the untouched Log Analytics Reader and Storage Blob Data Reader are left out.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$Expected = Write-S109Live -Label 'oer-s109-rg' -Live (Get-S109Live -Scope $RgScope)
$null = Invoke-S109Export -Name 'after-rg' -Include RoleManagementPolicies -Extra @{ Scope = $RgScope }
Write-S109ArmCount -Label 'after-rg'
$After = Get-S109At -Entries (Get-S109Policies -Name 'after-rg') -Scope $RgScope
Write-S109Kept -Label 'after-rg' -At $After -Expected $Expected
$BeforeAt = Get-S109At -Entries (Get-S109Policies -Name 'before-rg') -Scope $RgScope
Write-OerLiveStep "after-rg: kept entries identical to the same role's entry in before-rg: $(@($After.Keys | Where-Object { $BeforeAt.Contains($_) -and $BeforeAt[$_] -ceq $After[$_] }).Count) of $($After.Count)"
Disconnect-OerLive
```

**Expect:** `kept 2; the independent rule keeps 2; the same roles: True`; Reader and Monitoring
Reader `kept: True`; Log Analytics Reader, Storage Blob Data Reader and Owner `kept: False`; both
entries identical to 2.1's; `policy list 1`, `role assignments atScope 1`, no `single policy`,
writes 0.
**Failure looks like:** Owner kept (an assignment above the scope counted), Monitoring Reader left out
(the eligibility not counted), or any other role kept.

Result: not run yet.

### 2.3. The Log Analytics Reader policy at oer-s109-rg is changed once, and the list says so

- [ ] **2.3** `Set-OERRoleManagementPolicy -Role 'Log Analytics Reader' -Scope` (the resource group) `-ActivationMaxHours 4` changes one rule; the policy-assignment list then shows that policy changed, and no other policy at `oer-s109-rg`.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$Live = Get-S109Live -Scope $RgScope
Write-OerLiveStep "before the change: $Change changed: $(@($Live.Policies | Where-Object { $_.Role -ceq $Change })[0].Changed); policies changed at oer-s109-rg: $(@($Live.Policies | Where-Object Changed).Count)"
Reset-S109Requests
$Set = Set-OERRoleManagementPolicy -Role $Change -Scope $RgScope -ActivationMaxHours 4 -Confirm:$false -ErrorAction Continue -ErrorVariable SetErr
Write-OerLiveStep "Set-OERRoleManagementPolicy: changed rules $(@($Set.ChangedRuleIds) -join ', '); activation maximum hours $($Set.ActivationMaxHours)"
Write-S109Own -Records $SetErr -Command 'Set-OERRoleManagementPolicy'
Write-S109ArmCount -Label 'set'
$Wait = Wait-OerLiveConverged -Activity "$Change shows the change at oer-s109-rg" -BudgetSeconds 180 -Read { Get-S109Live -Scope $RgScope } -Test { [bool]@($args[0].Policies | Where-Object { $_.Role -ceq $Change })[0].Changed }
$Live = $Wait.Value
Write-OerLiveStep "after the change: $Change changed: $(@($Live.Policies | Where-Object { $_.Role -ceq $Change })[0].Changed); policies changed at oer-s109-rg: $(@($Live.Policies | Where-Object Changed).Count)"
Disconnect-OerLive
```

**Expect:** `before the change: Log Analytics Reader changed: False; policies changed at
oer-s109-rg: 0`; one changed rule (`Expiration_EndUser_Assignment`), activation maximum 4; one ARM
write; `after the change: Log Analytics Reader changed: True; policies changed at oer-s109-rg: 1`.
**Failure looks like:** an error from the cmdlet, more than one write, or the list not showing the
change within the budget (then the rule cannot see a change, and the result says so).

Result: not run yet.

### 2.4. This branch at oer-s109-rg after the change: the changed policy is kept too

- [ ] **2.4** After 2.3, this branch keeps at `oer-s109-rg` Reader, Monitoring Reader and Log Analytics Reader, exactly what the independent rule keeps.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$Expected = Write-S109Live -Label 'oer-s109-rg' -Live (Get-S109Live -Scope $RgScope)
$null = Invoke-S109Export -Name 'after-rg-changed' -Include RoleManagementPolicies -Extra @{ Scope = $RgScope }
Write-S109ArmCount -Label 'after-rg-changed'
$At = Get-S109At -Entries (Get-S109Policies -Name 'after-rg-changed') -Scope $RgScope
Write-S109Kept -Label 'after-rg-changed' -At $At -Expected $Expected
Write-OerLiveStep "after-rg-changed: $Change activationMaxHours: $((Get-S109Policies -Name 'after-rg-changed' | Where-Object { $_.role -ceq $Change }).activationMaxHours)"
Disconnect-OerLive
```

**Expect:** `kept 3; the independent rule keeps 3; the same roles: True`; Log Analytics Reader
`kept: True` with `activationMaxHours: 4`; Storage Blob Data Reader and Owner `kept: False`.
**Failure looks like:** the changed policy left out, or anything else kept.

Result: not run yet.

### 2.5. -AllRolePolicies at oer-s109-rg: every policy, as the 944976f build reads it

- [ ] **2.5** `-AllRolePolicies` at `oer-s109-rg` writes as many entries as 2.1, and every entry is identical to 2.1's except Log Analytics Reader's, which 2.3 changed.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$null = Invoke-S109Export -Name 'all-rg' -Include RoleManagementPolicies -Extra @{ Scope = $RgScope; AllRolePolicies = $true }
Write-S109ArmCount -Label 'all-rg'
Compare-S109At -Left (Get-S109At -Entries (Get-S109Policies -Name 'before-rg') -Scope $RgScope) -Right (Get-S109At -Entries (Get-S109Policies -Name 'all-rg') -Scope $RgScope) -Label 'before-rg against all-rg'
Disconnect-OerLive
```

**Expect:** `only left 0; only right 0; same role, different content 1: Log Analytics Reader`; no
`role assignments atScope` request.
**Failure looks like:** a count other than 2.1's, or another role that differs.

Result: not run yet.

## 3. The exported document converges (G8)

### 3.1. oer-s109-rg's document from 2.4: Unchanged twice

- [ ] **3.1** 2.4's `inventory.json` (its `roleManagementPolicies`, all at `oer-s109-rg`, with its `tenantId`) passes `Test-OERStructure`, and `Invoke-OERStructure -Include RoleManagementPolicies` applied twice gives only `Unchanged`, with no write.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$Inv = Get-Content -LiteralPath (Join-Path $Raw 'after-rg-changed\inventory.json') -Raw | ConvertFrom-Json
$Doc = [PSCustomObject]@{ version = $Inv.version; tenantId = $Inv.tenantId; roleManagementPolicies = @($Inv.roleManagementPolicies) }
Write-OerLiveStep "document: roleManagementPolicies $(@($Doc.roleManagementPolicies).Count), every one at oer-s109-rg: $(@($Doc.roleManagementPolicies | Where-Object { -not [string]::Equals(([string]$_.scope).TrimEnd('/'), $RgScope, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0); carries tenantId: $([bool]$Doc.tenantId)"
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'doc-3.1.json') -Encoding utf8
$V = Test-OERStructure -Path (Join-Path $Raw 'doc-3.1.json')
Write-OerLiveStep "Test-OERStructure: valid $($V.Valid); errors $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
foreach ($Pass in 1, 2) {
    Reset-S109Requests
    $Rows = @(Invoke-OERStructure -Path (Join-Path $Raw 'doc-3.1.json') -Include RoleManagementPolicies -Confirm:$false -ErrorAction Continue -ErrorVariable ApErr -WarningVariable ApWarn -WarningAction SilentlyContinue)
    Write-OerLiveStep "run $($Pass):"
    foreach ($Row in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3}" -f $Row.Section, $Row.Item, $Row.Action, $Row.Detail) }
    Write-OerLiveStep "rows: $($Rows.Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); warnings: $(@($ApWarn).Count)"
    Write-S109Own -Records $ApErr -Command 'Invoke-OERStructure'
    Write-S109ArmCount -Label "apply run $Pass"
}
Disconnect-OerLive
```

**Expect:** 3 entries, every one at `oer-s109-rg`, `carries tenantId: True`; `valid True; errors 0`;
in each run 3 rows, `not Unchanged: 0`, no own error, writes 0.
**Failure looks like:** a row other than `Unchanged`, a write, or an error.

Result: not run yet.

### 3.2. The subscription's document from 1.2: a plan of Unchanged only (read-only)

- [ ] **3.2** 1.2's `roleManagementPolicies` (the subscription's policies in use or changed) pass `Test-OERStructure`, and `Invoke-OERStructure -Include RoleManagementPolicies -WhatIf` plans only `Unchanged`, with no write. Nothing outside the prefix is written: this is a plan only.

```powershell
Connect-OerLive -Arm
Start-S109Fence
$Inv = Get-Content -LiteralPath (Join-Path $Raw 'after-sub\inventory.json') -Raw | ConvertFrom-Json
$Doc = [PSCustomObject]@{ version = $Inv.version; tenantId = $Inv.tenantId; roleManagementPolicies = @($Inv.roleManagementPolicies) }
Write-OerLiveStep "document: roleManagementPolicies $(@($Doc.roleManagementPolicies).Count); carries tenantId: $([bool]$Doc.tenantId)"
$Doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Raw 'doc-3.2.json') -Encoding utf8
$V = Test-OERStructure -Path (Join-Path $Raw 'doc-3.2.json')
Write-OerLiveStep "Test-OERStructure: valid $($V.Valid); errors $(@($V.Errors | Where-Object Severity -eq 'Error').Count)"
Reset-S109Requests
$Rows = @(Invoke-OERStructure -Path (Join-Path $Raw 'doc-3.2.json') -Include RoleManagementPolicies -WhatIf -ErrorAction Continue -ErrorVariable ApErr -WarningVariable ApWarn -WarningAction SilentlyContinue)
foreach ($Row in $Rows) { Write-OerLiveStep ("row: {0} | {1} | {2} | {3}" -f $Row.Section, $Row.Item, $Row.Action, $Row.Detail) }
Write-OerLiveStep "rows: $($Rows.Count); not Unchanged: $(@($Rows | Where-Object { $_.Action -ne 'Unchanged' }).Count); warnings: $(@($ApWarn).Count)"
Write-S109Own -Records $ApErr -Command 'Invoke-OERStructure'
Write-S109ArmCount -Label 'plan'
Disconnect-OerLive
```

**Expect:** as many entries as 1.2 kept; `valid True; errors 0`; every planned row `Unchanged`; no
own error; writes 0.
**Failure looks like:** a write (STOP), or a planned row other than `Unchanged`. A planned change on a
policy this step did not change would be an export round-trip gap of the entry itself -- the same
entry `-AllRolePolicies` and the `944976f` build write -- reported as a finding, not fixed here.

Result: not run yet.

## B. Proved offline (class B)

- **A role assignment read that fails.** `tests/Unit/Public/Export-OERInventory.Tests.ps1`: every
  unchanged, unused policy at that scope kept, one warning, the scope NOT skipped, the entry
  `roleManagementPolicies/role selection at` followed by the scope, last in `IncompleteReads`, one
  `InventoryPartial` naming it, and the bundle README listing it under the Azure label.
- **An eligibility read that fails for a scope.** The same file: the same, for that scope.
- **A list row without a policy record, or without a role definition id.**
  `tests/Unit/Private/Select-OERInventoryRolePolicy.Tests.ps1`: kept and named.
- **A management group scope.** `tests/Unit/Private/Select-OERInventoryRolePolicy.Tests.ps1`: an
  assignment or eligibility at the parent management group does not keep a subscription's policy,
  and one exactly at the management group keeps the management group's.
- **One list per scope and no request per policy, against the real lister.**
  `tests/Unit/Private/Get-OERInventoryRolePolicy.Tests.ps1`, beside its equivalence with
  `Get-OERInventory -AllRolesAtScope`.
- **Apply touches only declared policies.** `tests/Unit/Public/Invoke-OERStructure.Tests.ps1` (or the
  role policy handler's suite): a document with one policy, with and without `-Prune`, reads and
  writes only that one.

## Teardown

### T.1. The policy put back, the objects removed, nothing left, raw\s109 deleted

- [ ] **T.1** `Initialize-OerS109Prereq.ps1 -Teardown -Unattended` puts the Log Analytics Reader policy at `oer-s109-rg` back to its baseline, removes the eligibility and the role assignment, the group and the resource group; the sweep finds nothing with the prefix and no unread collection; the group count equals the baseline; no module or Graph SDK session remains; `raw\s109\` is deleted after the results are written.

```powershell
$Script = Join-Path $VaultDir 'Initialize-OerS109Prereq.ps1'
& pwsh -NoProfile -NonInteractive -File $Script -Teardown -Unattended 2>&1 | ForEach-Object { "$_" }
Write-OerLiveStep "teardown exit code: $LASTEXITCODE"
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
$Rg = Invoke-OerLiveArm -Path "$RgScope`?api-version=2021-04-01"
Write-OerLiveStep "oer-s109-rg found: $($Rg.Ok)"
Disconnect-OerLive
$State = & (Get-Module -Name Omnicit.EntraRBAC) { $null -eq $script:_OERAuthState }
Write-OerLiveStep "module session cleared: $State; Graph SDK session left: $([bool](Get-MgContext))"
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "raw\s109 deleted: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** `Teardown A: Log Analytics Reader policy at oer-s109-rg at its baseline: True (rules
differing before: 1: Expiration_EndUser_Assignment)`; the eligibility and the role assignment removed
and no longer listed; the group removed; the resource group deleted; exit code 0; 0 objects, 0 unread
collections, `oer-s109-rg found: False`; `module session cleared: True; Graph SDK session left:
False`; `raw\s109 deleted: True`.
**Failure looks like:** a policy not put back (STOP: nothing is removed), residue (exit code 3), an
object or the resource group left, a session left, or the folder still there. The listings can lag a
deletion: T.2 reads back once they have settled.

Result: not run yet.

### T.2. Read-back once the listings have settled

- [ ] **T.2** At least a minute after T.1, the sweep lists nothing with the prefix and no unread collection, the resource group is not found, and the tenant lists as many groups as the baseline of 0.2 recorded; `raw\s109\` (which H.1 creates again) is deleted afterwards.

```powershell
Connect-OerLive -Arm
$Found = @(Find-OerLivePrefixed)
Write-OerLiveStep "objects with the prefix: $(@($Found | Where-Object { $_.Kind -ne 'unread' }).Count); unread collections: $(@($Found | Where-Object { $_.Kind -eq 'unread' }).Count)"
$Rg = Invoke-OerLiveArm -Path "$RgScope`?api-version=2021-04-01"
Write-OerLiveStep "oer-s109-rg found: $($Rg.Ok)"
$Groups = Invoke-OerLiveGraph -All -Uri 'v1.0/groups?$select=id'
Write-OerLiveStep "groups listed: $(@(@($Groups.Body['value']) | Where-Object { $null -ne $_ }).Count)"
Disconnect-OerLive
if (Test-Path -LiteralPath $Raw) { Remove-Item -LiteralPath $Raw -Recurse -Force }
Write-OerLiveStep "raw\s109 deleted: $(-not (Test-Path -LiteralPath $Raw))"
```

**Expect:** 0 objects, 0 unread collections; `oer-s109-rg found: False`; groups equal to the baseline
count 0.2 printed; `raw\s109 deleted: True`.
**Failure looks like:** a step object still listed after several minutes (read back again later
before calling it residue), another count than the baseline, or the folder still there.

Result: not run yet.
