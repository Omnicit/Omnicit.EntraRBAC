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

- [x] **S.1** The session's `Repo` is the step's worktree, whose build carries this branch; the main clone is on `main`, never switched; the kept `944976f` build carries none of this branch's changes.

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

Result: 2026-10-10 18:50 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The session's Repo is the step's own worktree, not the main clone; the main clone is on main, never switched; the worktree on this branch at 31f4f80 with 0 tracked changes; this branch's build carries all 4 marks of the change, the kept build of 944976f none of them (it was built in this worktree from 944976f's source before the branch's first commit).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK S.1 ===
[oer-s109] The module loads from a worktree that is not the main clone: True
[oer-s109] Main clone: branch main
[oer-s109] Worktree: branch feat/export-role-policies-in-use; HEAD 31f4f80 fix: prove the per-scope role selection guards and correct their texts; tracked changes: 0
[oer-s109] this branch build: version 1.1.4 feat; marks of this branch: 4 of 4
[oer-s109] 944976f build: version 1.1.4 feat; marks of this branch: 0 of 4
RUNNER: check S.1 exit code 0; started 2026-10-10T18:49:56Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 0. Preparation

### 0.1. Identity check as oer-live-cc, the module session

- [x] **0.1** The module session passes the identity check, is app-only, and the module is this branch's build.

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

Result: 2026-10-10 10:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Every identity line True for the module session as oer-live-cc (app-only, certificate); identity check passed; the module is the worktree's build (1.1.4).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.1 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] The module is the worktree's build: True
RUNNER: check 0.1 exit code 0; started 2026-10-10T10:53:52Z; took 7 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.2. The prerequisite: the group, the resource group and the two grants, after a plan

- [x] **0.2** `Initialize-OerS109Prereq.ps1 -WhatIf` writes nothing and plans every object; the real run writes the baseline, creates the group and the resource group, records the Log Analytics Reader policy baseline, and creates the role assignment and the eligibility; a second run finds every object and writes nothing.

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

Result: 2026-10-10 10:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The plan run wrote nothing (exit 0); the first real run wrote the baseline (groups 98), created oer-s109-principal (201, awaited until it resolved by name) and oer-s109-rg, recorded the Log Analytics Reader policy baseline at oer-s109-rg (17 rules, activation maximum PT8H; the policy the resource group lists is its own), created the Reader role assignment for the group (200 after one PrincipalNotFound answer, a replication delay, retried after 5 s) and requested the Monitoring Reader eligibility (200, Provisioned), each listed at once, exit 0; the second real run found every object and both grants and wrote nothing (written to the tenant: False), exit 0.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.2 ===
[oer-s109] prereq run: -WhatIf
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
What if: Performing the operation "Start the redacted transcript" on target "raw\s109\prereq-20261010-105432Z.log".
[oer-s109] Mode: CREATE or complete. Prefix 'oer-s109-'. Objects (fixed): oer-s109-principal (security group, no member); oer-s109-rg (tagged, empty); at oer-s109-rg: Reader assigned and Monitoring Reader eligible (P7D) for oer-s109-principal; the Log Analytics Reader policy there baselined. OerLive 1.0.3.
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s109] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s109-' is left.
[oer-s109] Found: oer-s109-principal exists: False; oer-s109-rg exists: False.
[oer-s109] No baseline yet: it is written now, before the first write to the tenant (groups 98; oer-s109-rg exists: False).
What if: Performing the operation "Write the baseline (JSON, no BOM)" on target "raw\s109\baseline-s109.json".
What if: Performing the operation "Create a security group with no member (Graph v1.0 POST groups: not role-assignable, not mail-enabled, assigned membership)" on target "oer-s109-principal".
What if: Performing the operation "Create the resource group in the test subscription (Azure Resource Manager PUT, location 'swedencentral', tag purpose 'Omnicit.EntraRBAC live verification (oer-s109)')" on target "oer-s109-rg".
[oer-s109] No policy baseline: oer-s109-rg does not exist (WhatIf).
[oer-s109] No role assignment or eligibility: the group or the resource group does not exist (WhatIf).
[oer-s109] Summary: oer-s109-principal absent; oer-s109-rg absent; written to the tenant: False (WhatIf: nothing was created or written).
[oer-s109] WhatIf: nothing was created, removed or written.
[oer-s109] Done.
[oer-s109] prereq exit code: 0
[oer-s109] prereq run: -Unattended
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s109] Transcript (redacted): raw\s109\prereq-20261010-105439Z.log; OerLive 1.0.3.
[oer-s109] Mode: CREATE or complete. Prefix 'oer-s109-'. Objects (fixed): oer-s109-principal (security group, no member); oer-s109-rg (tagged, empty); at oer-s109-rg: Reader assigned and Monitoring Reader eligible (P7D) for oer-s109-principal; the Log Analytics Reader policy there baselined. OerLive 1.0.3.
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s109] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s109] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s109-' is left.
[oer-s109] Found: oer-s109-principal exists: False; oer-s109-rg exists: False.
[oer-s109] No baseline yet: it is written now, before the first write to the tenant (groups 98; oer-s109-rg exists: False).
[oer-s109] Wrote the baseline raw\s109\baseline-s109.json and read it back.
[oer-s109] Created group oer-s109-principal: 201.
[oer-s109] Recorded the id of oer-s109-principal under raw\s109 (not printed).
[oer-s109] oer-s109-principal resolves by its display name: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s109] oer-s109-principal resolves by its display name: converged after 2 read(s), 2.2 s.
[oer-s109] Created resource group oer-s109-rg.
[oer-s109] The scope lists its role management policy: converged after 1 read(s), 4.2 s.
[oer-s109] The policy listed at the scope is the scope's own: True
[oer-s109] Log Analytics Reader policy at oer-s109-rg: rules 17; activation maximum: PT8H
[oer-s109] Wrote the baseline raw\s109\baseline-s109-rgpolicy.json and read it back.
[oer-s109] Creating the role assignment of Reader: the principal is not known to Azure Resource Manager yet (PrincipalNotFound, likely replication delay) -- sending again in 5 s.
[oer-s109] Recorded the id of roleAssignment under raw\s109 (not printed).
[oer-s109] Created the role assignment of Reader at oer-s109-rg for oer-s109-principal: 200.
[oer-s109] the role assignment is listed at oer-s109-rg: converged after 1 read(s), 3.1 s.
[oer-s109] Recorded the id of eligibilityRequest under raw\s109 (not printed).
[oer-s109] Requested the eligibility of Monitoring Reader at oer-s109-rg for oer-s109-principal: 200, status Provisioned.
[oer-s109] the eligibility is listed at oer-s109-rg: converged after 1 read(s), 1.9 s.
[oer-s109] Summary: oer-s109-principal present; oer-s109-rg present; written to the tenant: True.
[oer-s109] Done.
[oer-s109] prereq exit code: 0
[oer-s109] prereq run: -Unattended
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s109] Transcript (redacted): raw\s109\prereq-20261010-105517Z.log; OerLive 1.0.3.
[oer-s109] Mode: CREATE or complete. Prefix 'oer-s109-'. Objects (fixed): oer-s109-principal (security group, no member); oer-s109-rg (tagged, empty); at oer-s109-rg: Reader assigned and Monitoring Reader eligible (P7D) for oer-s109-principal; the Log Analytics Reader policy there baselined. OerLive 1.0.3.
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s109] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s109] Found: oer-s109-principal exists: True; oer-s109-rg exists: True.
[oer-s109] Grants exactly at oer-s109-rg: role assignment of Reader for oer-s109-principal: True; eligibility of Monitoring Reader for oer-s109-principal: True
[oer-s109] The baseline exists (groups 98 when it was written).
[oer-s109] Group oer-s109-principal exists.
[oer-s109] Resource group oer-s109-rg exists.
[oer-s109] The Log Analytics Reader policy baseline at oer-s109-rg exists.
[oer-s109] The role assignment of Reader at oer-s109-rg for oer-s109-principal exists.
[oer-s109] The eligibility of Monitoring Reader at oer-s109-rg for oer-s109-principal exists.
[oer-s109] Summary: oer-s109-principal present; oer-s109-rg present; written to the tenant: False.
[oer-s109] Done.
[oer-s109] prereq exit code: 0
RUNNER: check 0.2 exit code 0; started 2026-10-10T10:54:30Z; took 54 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 0.3. What the lists say, read independently of the code under test

- [x] **0.3** Read through OerLive's transport: at the subscription, the policies listed, how many are changed, the roles assigned or eligible exactly there, and the policies the rule keeps; at `oer-s109-rg`, the same, with Reader assigned and Monitoring Reader eligible exactly there, Owner assigned above it only, and no policy changed yet.

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

Result: 2026-10-10 10:56 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Read through OerLive's transport, independently of the code under test. The subscription: 967 policies listed (all built in), 2 changed, none without a policy record; 3 roles assigned exactly there, none eligible there; the rule keeps 4 (Contributor, Owner, Reader, Storage Blob Data Contributor) -- the counts of the measurement. Monitoring Reader, Log Analytics Reader and Storage Blob Data Reader are neither assigned nor eligible there and not changed. oer-s109-rg: 965 policies listed, none changed; Reader assigned there (and above it), Monitoring Reader eligible there, Owner assigned above only; Log Analytics Reader and Storage Blob Data Reader untouched; the rule keeps exactly Monitoring Reader and Reader.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 0.3 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] subscription: policies listed 967 (built in 967); changed 2; without a policy record 0; roles assigned exactly here 3; eligible exactly here 0
[oer-s109] subscription: the rule keeps 4: Contributor, Owner, Reader, Storage Blob Data Contributor
[oer-s109] subscription: Reader: assigned here True; eligible here False; assigned above False; changed True
[oer-s109] subscription: Monitoring Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] subscription: Log Analytics Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] subscription: Storage Blob Data Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] subscription: Owner: assigned here True; eligible here False; assigned above True; changed False
[oer-s109] oer-s109-rg: policies listed 965 (built in 965); changed 0; without a policy record 0; roles assigned exactly here 1; eligible exactly here 1
[oer-s109] oer-s109-rg: the rule keeps 2: Monitoring Reader, Reader
[oer-s109] oer-s109-rg: Reader: assigned here True; eligible here False; assigned above True; changed False
[oer-s109] oer-s109-rg: Monitoring Reader: assigned here False; eligible here True; assigned above False; changed False
[oer-s109] oer-s109-rg: Log Analytics Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] oer-s109-rg: Storage Blob Data Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] oer-s109-rg: Owner: assigned here False; eligible here False; assigned above True; changed False
RUNNER: check 0.3 exit code 0; started 2026-10-10T10:55:44Z; took 16 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 1. The test subscription: before and after (A, B)

### 1.1. Export with the 944976f build (the reference)

- [x] **1.1** `Export-OERInventory -Include RoleAssignments, RoleManagementPolicies` with the kept `944976f` build writes a bundle under `raw\s109\before-sub\` holding every policy at the subscription, and a request log.

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

Result: 2026-10-10 10:57 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. The kept 944976f build is the module; the management group listing was refused (AuthorizationFailed, as measured in step 7), so that level is the one skipped scope and the run ends InventoryPartial for it; the subscription was read (1 of 1). roleManagementPolicies.json holds 967 entries, all at the subscription -- every policy 0.3 listed. ARM requests 11: one policy list, one role assignment list (unfiltered, with 6 role definition reads for the names), one eligibility list, the subscription and management group listings; no single-policy request, no write, no token request through the fence.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.1 ===
[oer-s109] module loaded from the kept 944976f build: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
Export-OERInventory: SCRATCH\run-1.1.ps1:143
Line |
 143 |      $Out = Export-OERInventory -OutputPath (Join-Path $Raw "bundle-$N ...
     |             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | This inventory bundle is PARTIAL: 1 level(s) of the Azure scope tree could not be listed, so none of their
     | scopes was walked, and the missing data is absent from roleAssignments.json and roleManagementPolicies.json.
     | Skipped: <management groups: the listing failed>. 1 level(s) of the Azure scope tree could not be listed, so
     | none of their scopes was walked for azurePimEligibility.json, and their eligible assignments are absent from it.
     | Skipped: <management groups: the listing failed>. Do not treat it as a full tenant snapshot.
[oer-s109] request log: 11 ARM request(s) written to raw\s109\requests-before-sub.log; token requests: 0
[oer-s109] bundle before-sub: roleManagementPolicies 967; roleAssignments 14; scopes read 1 of 1; skipped scopes 1 (<management groups: the listing failed>); IncompleteReads 0; warnings 1
[oer-s109] warning: Could not list the management groups, so no management group is walked: AuthorizationFailed: The client '00000000-0000-0000-0000-000000000001' with object id '00000000-0000-0000-0000-000000000002' does not have authorization to perform action 'Microsoft.Management/managementGroups/read' over scope '/providers/Microsoft.Management' or the scope is invalid. If access was recently granted, please refresh your credentials.
[oer-s109] Export-OERInventory own errors: 1 -- InventoryPartial,Export-OERInventory
[oer-s109] before-sub: ARM requests 11 (eligibility 1; management groups 1; policy list 1; role assignments 1; role definition 6; subscriptions 1); writes 0
[oer-s109] before-sub: entries at the subscription 967; entries in all 967
RUNNER: check 1.1 exit code 0; started 2026-10-10T10:56:19Z; took 17 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.2. Export with this branch: only the policies in use or changed, each the same as before

- [x] **1.2** The same export with this branch keeps at the subscription exactly the policies the independent rule keeps (0.3), each entry identical to 1.1's; Monitoring Reader (eligible only at `oer-s109-rg`) and Storage Blob Data Reader (untouched) are left out; the policies are still read with one list for the scope, plus one `atScope()` role assignment list, and nothing per policy; `IncompleteReads` names no role selection.

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

Result: 2026-10-10 18:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. This branch kept 4 policies at the subscription -- exactly the roles the independent rule keeps (Contributor, Owner, Reader, Storage Blob Data Contributor: three assigned there, two changed, Reader both) -- and each entry is identical to 1.1's for the same role. Monitoring Reader (eligible only at oer-s109-rg), Log Analytics Reader and Storage Blob Data Reader (untouched) are left out; roleAssignments.json is identical to 1.1's. The policies were read with the one policy list for the scope, plus one atScope() role assignment list; no single-policy request, no write. IncompleteReads 0 (no role selection entry); the run ends InventoryPartial only for the refused management group listing, as 1.1 does. 967 entries before, 4 after.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.2 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] subscription: policies listed 967 (built in 967); changed 2; without a policy record 0; roles assigned exactly here 3; eligible exactly here 0
[oer-s109] subscription: the rule keeps 4: Contributor, Owner, Reader, Storage Blob Data Contributor
[oer-s109] subscription: Reader: assigned here True; eligible here False; assigned above False; changed True
[oer-s109] subscription: Monitoring Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] subscription: Log Analytics Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] subscription: Storage Blob Data Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] subscription: Owner: assigned here True; eligible here False; assigned above True; changed False
Export-OERInventory: SCRATCH\run-1.2.ps1:143
Line |
 143 |      $Out = Export-OERInventory -OutputPath (Join-Path $Raw "bundle-$N ...
     |             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | This inventory bundle is PARTIAL: 1 level(s) of the Azure scope tree could not be listed, so none of their
     | scopes was walked, and the missing data is absent from roleAssignments.json and roleManagementPolicies.json.
     | Skipped: <management groups: the listing failed>. 1 level(s) of the Azure scope tree could not be listed, so
     | none of their scopes was walked for azurePimEligibility.json, and their eligible assignments are absent from it.
     | Skipped: <management groups: the listing failed>. Do not treat it as a full tenant snapshot.
[oer-s109] request log: 12 ARM request(s) written to raw\s109\requests-after-sub.log; token requests: 0
[oer-s109] bundle after-sub: roleManagementPolicies 4; roleAssignments 14; scopes read 1 of 1; skipped scopes 1 (<management groups: the listing failed>); IncompleteReads 0; warnings 1
[oer-s109] warning: Could not list the management groups, so no management group is walked: AuthorizationFailed: The client '00000000-0000-0000-0000-000000000001' with object id '00000000-0000-0000-0000-000000000002' does not have authorization to perform action 'Microsoft.Management/managementGroups/read' over scope '/providers/Microsoft.Management' or the scope is invalid. If access was recently granted, please refresh your credentials.
[oer-s109] Export-OERInventory own errors: 1 -- InventoryPartial,Export-OERInventory
[oer-s109] after-sub: ARM requests 12 (eligibility 1; management groups 1; policy list 1; role assignments 1; role assignments atScope 1; role definition 6; subscriptions 1); writes 0
[oer-s109] after-sub: kept 4; the independent rule keeps 4; the same roles: True
[oer-s109] after-sub: Reader kept: True
[oer-s109] after-sub: Monitoring Reader kept: False
[oer-s109] after-sub: Log Analytics Reader kept: False
[oer-s109] after-sub: Storage Blob Data Reader kept: False
[oer-s109] after-sub: Owner kept: True
[oer-s109] after-sub: kept entries identical to the same role's entry in before-sub: 4 of 4
[oer-s109] roleAssignments.json identical to before-sub: True
RUNNER: check 1.2 exit code 0; started 2026-10-10T18:50:13Z; took 23 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 1.3. -AllRolePolicies writes what the 944976f build wrote

- [x] **1.3** `-AllRolePolicies` with this branch writes `roleManagementPolicies.json` identical to 1.1's, in order and content, with the same count, and makes no `atScope()` role assignment request.

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

Result: 2026-10-10 18:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With -AllRolePolicies this branch wrote 967 entries, the same count as 1.1; no role only on one side and none different; roleManagementPolicies.json identical to 1.1's byte for byte. The requests are 1.1's exactly (11: one policy list, no atScope() role assignment list, no single-policy request), no write.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 1.3 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
Export-OERInventory: SCRATCH\run-1.3.ps1:143
Line |
 143 |      $Out = Export-OERInventory -OutputPath (Join-Path $Raw "bundle-$N ...
     |             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | This inventory bundle is PARTIAL: 1 level(s) of the Azure scope tree could not be listed, so none of their
     | scopes was walked, and the missing data is absent from roleAssignments.json and roleManagementPolicies.json.
     | Skipped: <management groups: the listing failed>. 1 level(s) of the Azure scope tree could not be listed, so
     | none of their scopes was walked for azurePimEligibility.json, and their eligible assignments are absent from it.
     | Skipped: <management groups: the listing failed>. Do not treat it as a full tenant snapshot.
[oer-s109] request log: 11 ARM request(s) written to raw\s109\requests-all-sub.log; token requests: 0
[oer-s109] bundle all-sub: roleManagementPolicies 967; roleAssignments 14; scopes read 1 of 1; skipped scopes 1 (<management groups: the listing failed>); IncompleteReads 0; warnings 1
[oer-s109] warning: Could not list the management groups, so no management group is walked: AuthorizationFailed: The client '00000000-0000-0000-0000-000000000001' with object id '00000000-0000-0000-0000-000000000002' does not have authorization to perform action 'Microsoft.Management/managementGroups/read' over scope '/providers/Microsoft.Management' or the scope is invalid. If access was recently granted, please refresh your credentials.
[oer-s109] Export-OERInventory own errors: 1 -- InventoryPartial,Export-OERInventory
[oer-s109] all-sub: ARM requests 11 (eligibility 1; management groups 1; policy list 1; role assignments 1; role definition 6; subscriptions 1); writes 0
[oer-s109] all-sub: entries 967; before-sub: 967; the same count: True
[oer-s109] before-sub against all-sub: left 967, right 967; only left 0; only right 0; same role, different content 0
[oer-s109] roleManagementPolicies.json identical to before-sub, byte for byte: True
RUNNER: check 1.3 exit code 0; started 2026-10-10T18:51:01Z; took 16 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 2. The test resource group: the grants and the change are this step's own

### 2.1. Export of oer-s109-rg with the 944976f build (the reference)

- [x] **2.1** `Export-OERInventory -Scope` (the resource group) `-Include RoleManagementPolicies` with the kept `944976f` build writes every policy listed at `oer-s109-rg`.

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

Result: 2026-10-10 10:57 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With the kept 944976f build, the export of oer-s109-rg alone (-Scope) read one scope, skipped none, and wrote 965 entries -- every policy 0.3 listed there; 2 ARM requests (one policy list, one eligibility list), no write, no error.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.1 ===
[oer-s109] module loaded from the kept 944976f build: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] request log: 2 ARM request(s) written to raw\s109\requests-before-rg.log; token requests: 0
[oer-s109] bundle before-rg: roleManagementPolicies 965; roleAssignments 0; scopes read 1 of 1; skipped scopes 0; IncompleteReads 0; warnings 0
[oer-s109] Export-OERInventory own errors: 0
[oer-s109] before-rg: ARM requests 2 (eligibility 1; policy list 1); writes 0
[oer-s109] before-rg: entries at oer-s109-rg 965
RUNNER: check 2.1 exit code 0; started 2026-10-10T10:57:10Z; took 13 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.2. This branch at oer-s109-rg before the change: the assigned role and the eligible role only

- [x] **2.2** This branch keeps at `oer-s109-rg` exactly Reader (assigned there) and Monitoring Reader (eligible there), each identical to 2.1's entry; Owner, assigned only above the resource group, and the untouched Log Analytics Reader and Storage Blob Data Reader are left out.

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

Result: 2026-10-10 18:51 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. At oer-s109-rg, before the change, this branch kept exactly Reader (assigned there) and Monitoring Reader (eligible there) -- the independent rule's two -- each identical to 2.1's entry. Owner, assigned only above the resource group, is not counted; the untouched Log Analytics Reader and Storage Blob Data Reader are left out. 965 entries before, 2 after. Requests: one policy list, one atScope() role assignment list, one eligibility list; no single-policy request, no write, no error.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.2 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] oer-s109-rg: policies listed 965 (built in 965); changed 0; without a policy record 0; roles assigned exactly here 1; eligible exactly here 1
[oer-s109] oer-s109-rg: the rule keeps 2: Monitoring Reader, Reader
[oer-s109] oer-s109-rg: Reader: assigned here True; eligible here False; assigned above True; changed False
[oer-s109] oer-s109-rg: Monitoring Reader: assigned here False; eligible here True; assigned above False; changed False
[oer-s109] oer-s109-rg: Log Analytics Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] oer-s109-rg: Storage Blob Data Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] oer-s109-rg: Owner: assigned here False; eligible here False; assigned above True; changed False
[oer-s109] request log: 3 ARM request(s) written to raw\s109\requests-after-rg.log; token requests: 0
[oer-s109] bundle after-rg: roleManagementPolicies 2; roleAssignments 0; scopes read 1 of 1; skipped scopes 0; IncompleteReads 0; warnings 0
[oer-s109] Export-OERInventory own errors: 0
[oer-s109] after-rg: ARM requests 3 (eligibility 1; policy list 1; role assignments atScope 1); writes 0
[oer-s109] after-rg: kept 2; the independent rule keeps 2; the same roles: True
[oer-s109] after-rg: Reader kept: True
[oer-s109] after-rg: Monitoring Reader kept: True
[oer-s109] after-rg: Log Analytics Reader kept: False
[oer-s109] after-rg: Storage Blob Data Reader kept: False
[oer-s109] after-rg: Owner kept: False
[oer-s109] after-rg: kept entries identical to the same role's entry in before-rg: 2 of 2
RUNNER: check 2.2 exit code 0; started 2026-10-10T18:51:29Z; took 18 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.3. The Log Analytics Reader policy at oer-s109-rg is changed once, and the list says so

- [x] **2.3** `Set-OERRoleManagementPolicy -Role 'Log Analytics Reader' -Scope` (the resource group) `-ActivationMaxHours 4` changes one rule; the policy-assignment list then shows that policy changed, and no other policy at `oer-s109-rg`.

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

Result: 2026-10-10 18:52 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Before the change the Log Analytics Reader policy at oer-s109-rg carried no change record (changed False; 0 changed policies there). Set-OERRoleManagementPolicy -ActivationMaxHours 4 changed one rule (Expiration_EndUser_Assignment) with one ARM write and no error; the policy-assignment list then showed that policy changed on the first read (5.1 s) and no other: 1 changed policy at oer-s109-rg. This is the controlled before/after of the change rule on the step's own test resource.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.3 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] before the change: Log Analytics Reader changed: False; policies changed at oer-s109-rg: 0
[oer-s109] Set-OERRoleManagementPolicy: changed rules Expiration_EndUser_Assignment; activation maximum hours 4
[oer-s109] Set-OERRoleManagementPolicy own errors: 0
[oer-s109] set: ARM requests 4 (policy list 1; role definition 1; single policy 2); writes 1
[oer-s109] Log Analytics Reader shows the change at oer-s109-rg: converged after 1 read(s), 5.1 s.
[oer-s109] after the change: Log Analytics Reader changed: True; policies changed at oer-s109-rg: 1
RUNNER: check 2.3 exit code 0; started 2026-10-10T18:52:00Z; took 22 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.4. This branch at oer-s109-rg after the change: the changed policy is kept too

- [x] **2.4** After 2.3, this branch keeps at `oer-s109-rg` Reader, Monitoring Reader and Log Analytics Reader, exactly what the independent rule keeps.

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

Result: 2026-10-10 18:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. After 2.3, this branch kept 3 policies at oer-s109-rg -- Reader (assigned), Monitoring Reader (eligible) and the changed Log Analytics Reader (activationMaxHours 4) -- exactly the independent rule's three; Storage Blob Data Reader and Owner left out. Same three requests as 2.2, no write.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.4 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] oer-s109-rg: policies listed 965 (built in 965); changed 1; without a policy record 0; roles assigned exactly here 1; eligible exactly here 1
[oer-s109] oer-s109-rg: the rule keeps 3: Log Analytics Reader, Monitoring Reader, Reader
[oer-s109] oer-s109-rg: Reader: assigned here True; eligible here False; assigned above True; changed False
[oer-s109] oer-s109-rg: Monitoring Reader: assigned here False; eligible here True; assigned above False; changed False
[oer-s109] oer-s109-rg: Log Analytics Reader: assigned here False; eligible here False; assigned above False; changed True
[oer-s109] oer-s109-rg: Storage Blob Data Reader: assigned here False; eligible here False; assigned above False; changed False
[oer-s109] oer-s109-rg: Owner: assigned here False; eligible here False; assigned above True; changed False
[oer-s109] request log: 3 ARM request(s) written to raw\s109\requests-after-rg-changed.log; token requests: 0
[oer-s109] bundle after-rg-changed: roleManagementPolicies 3; roleAssignments 0; scopes read 1 of 1; skipped scopes 0; IncompleteReads 0; warnings 0
[oer-s109] Export-OERInventory own errors: 0
[oer-s109] after-rg-changed: ARM requests 3 (eligibility 1; policy list 1; role assignments atScope 1); writes 0
[oer-s109] after-rg-changed: kept 3; the independent rule keeps 3; the same roles: True
[oer-s109] after-rg-changed: Reader kept: True
[oer-s109] after-rg-changed: Monitoring Reader kept: True
[oer-s109] after-rg-changed: Log Analytics Reader kept: True
[oer-s109] after-rg-changed: Storage Blob Data Reader kept: False
[oer-s109] after-rg-changed: Owner kept: False
[oer-s109] after-rg-changed: Log Analytics Reader activationMaxHours: 4
RUNNER: check 2.4 exit code 0; started 2026-10-10T18:52:35Z; took 18 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 2.5. -AllRolePolicies at oer-s109-rg: every policy, as the 944976f build reads it

- [x] **2.5** `-AllRolePolicies` at `oer-s109-rg` writes as many entries as 2.1, and every entry is identical to 2.1's except Log Analytics Reader's, which 2.3 changed.

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

Result: 2026-10-10 18:53 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. With -AllRolePolicies this branch wrote 965 entries at oer-s109-rg, as many as 2.1; no role only on one side; exactly one role differs in content, Log Analytics Reader, which 2.3 changed between the two exports. The requests are 2.1's (one policy list, one eligibility list; no atScope() role assignment list), no write.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 2.5 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] request log: 2 ARM request(s) written to raw\s109\requests-all-rg.log; token requests: 0
[oer-s109] bundle all-rg: roleManagementPolicies 965; roleAssignments 0; scopes read 1 of 1; skipped scopes 0; IncompleteReads 0; warnings 0
[oer-s109] Export-OERInventory own errors: 0
[oer-s109] all-rg: ARM requests 2 (eligibility 1; policy list 1); writes 0
[oer-s109] before-rg against all-rg: left 965, right 965; only left 0; only right 0; same role, different content 1: Log Analytics Reader
RUNNER: check 2.5 exit code 0; started 2026-10-10T18:53:04Z; took 14 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

## 3. The exported document converges (G8)

### 3.1. oer-s109-rg's document from 2.4: Unchanged twice

- [x] **3.1** 2.4's `inventory.json` (its `roleManagementPolicies`, all at `oer-s109-rg`, with its `tenantId`) passes `Test-OERStructure`, and `Invoke-OERStructure -Include RoleManagementPolicies` applied twice gives only `Unchanged`, with no write.

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

Result: 2026-10-10 18:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS (G8). 2.4's document -- 3 roleManagementPolicies entries, every one at oer-s109-rg, with tenantId -- is valid (0 errors), and Invoke-OERStructure -Include RoleManagementPolicies gave 3 rows Unchanged in each of two runs, no warning, no error, and no ARM write (each run: 3 policy lists and 3 role definition reads).

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.1 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] document: roleManagementPolicies 3, every one at oer-s109-rg: True; carries tenantId: True
[oer-s109] Test-OERStructure: valid True; errors 0
[oer-s109] run 1:
[oer-s109] row: roleManagementPolicies | Monitoring Reader @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg | Unchanged | policy already matches for 'Monitoring Reader' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg'
[oer-s109] row: roleManagementPolicies | Log Analytics Reader @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg | Unchanged | policy already matches for 'Log Analytics Reader' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg'
[oer-s109] row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg | Unchanged | policy already matches for 'Reader' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg'
[oer-s109] rows: 3; not Unchanged: 0; warnings: 0
[oer-s109] Invoke-OERStructure own errors: 0
[oer-s109] apply run 1: ARM requests 6 (policy list 3; role definition 3); writes 0
[oer-s109] run 2:
[oer-s109] row: roleManagementPolicies | Monitoring Reader @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg | Unchanged | policy already matches for 'Monitoring Reader' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg'
[oer-s109] row: roleManagementPolicies | Log Analytics Reader @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg | Unchanged | policy already matches for 'Log Analytics Reader' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg'
[oer-s109] row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg | Unchanged | policy already matches for 'Reader' at '/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/oer-s109-rg'
[oer-s109] rows: 3; not Unchanged: 0; warnings: 0
[oer-s109] Invoke-OERStructure own errors: 0
[oer-s109] apply run 2: ARM requests 6 (policy list 3; role definition 3); writes 0
RUNNER: check 3.1 exit code 0; started 2026-10-10T18:53:30Z; took 32 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### 3.2. The subscription's document from 1.2: a plan of Unchanged only (read-only)

- [x] **3.2** 1.2's `roleManagementPolicies` (the subscription's policies in use or changed) pass `Test-OERStructure`, and `Invoke-OERStructure -Include RoleManagementPolicies -WhatIf` plans only `Unchanged`, with no write. Nothing outside the prefix is written: this is a plan only.

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

Result: 2026-10-10 18:54 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. 1.2's document -- the subscription's 4 policies in use or changed, the 2 changed ones included, with tenantId -- is valid (0 errors), and Invoke-OERStructure -Include RoleManagementPolicies -WhatIf planned 4 rows, every one Unchanged, no warning, no error, no ARM write. A plan only: nothing outside the prefix was written. So the 2 changed policies the export keeps round-trip as they are.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK 3.2 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] fences in place (Get-AzToken is the proxy, the ARM wrapper records): True
[oer-s109] document: roleManagementPolicies 4; carries tenantId: True
[oer-s109] Test-OERStructure: valid True; errors 0
[oer-s109] row: roleManagementPolicies | Reader @ /subscriptions/00000000-0000-0000-0000-000000000003 | Unchanged | policy already matches for 'Reader' at '/subscriptions/00000000-0000-0000-0000-000000000003'
[oer-s109] row: roleManagementPolicies | Contributor @ /subscriptions/00000000-0000-0000-0000-000000000003 | Unchanged | policy already matches for 'Contributor' at '/subscriptions/00000000-0000-0000-0000-000000000003'
[oer-s109] row: roleManagementPolicies | Owner @ /subscriptions/00000000-0000-0000-0000-000000000003 | Unchanged | policy already matches for 'Owner' at '/subscriptions/00000000-0000-0000-0000-000000000003'
[oer-s109] row: roleManagementPolicies | Storage Blob Data Contributor @ /subscriptions/00000000-0000-0000-0000-000000000003 | Unchanged | policy already matches for 'Storage Blob Data Contributor' at '/subscriptions/00000000-0000-0000-0000-000000000003'
[oer-s109] rows: 4; not Unchanged: 0; warnings: 0
[oer-s109] Invoke-OERStructure own errors: 0
[oer-s109] plan: ARM requests 8 (policy list 4; role definition 4); writes 0
RUNNER: check 3.2 exit code 0; started 2026-10-10T18:54:14Z; took 18 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

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

- [x] **T.1** `Initialize-OerS109Prereq.ps1 -Teardown -Unattended` puts the Log Analytics Reader policy at `oer-s109-rg` back to its baseline, removes the eligibility and the role assignment, the group and the resource group; the sweep finds nothing with the prefix and no unread collection; the group count equals the baseline; no module or Graph SDK session remains; `raw\s109\` is deleted after the results are written.

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

Result: 2026-10-10 18:55 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. Teardown A put the Log Analytics Reader policy at oer-s109-rg back to its baseline (1 rule differed, Expiration_EndUser_Assignment; converged on the first read) before anything was removed; B removed the eligibility (AdminRemove, 200) and the role assignment (DELETE, 200), each no longer listed at the first read; C deleted oer-s109-principal (204; removed 1, residue 0); D deleted oer-s109-rg. The sweep lists nothing with the prefix and no unread collection, oer-s109-rg is not found, the group count equals the baseline (98), exit code 0; no module or Graph SDK session remains; raw\s109 is deleted. The 2 residue rows of other prefixes were counted and not touched.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.1 ===
[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
[oer-s109] Transcript (redacted): raw\s109\teardown-20261010-185449Z.log; OerLive 1.0.3.
[oer-s109] Mode: REMOVE. Prefix 'oer-s109-'. Objects (fixed): oer-s109-principal (security group, no member); oer-s109-rg (tagged, empty); at oer-s109-rg: Reader assigned and Monitoring Reader eligible (P7D) for oer-s109-principal; the Log Analytics Reader policy there baselined. OerLive 1.0.3.
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] Unattended run: the confirmation question is not asked; the identity check above passed.
[oer-s109] Residue: raw\residue.json holds 2 row(s), 0 with this step's prefix; rows of other prefixes are not touched by this script.
[oer-s109] The scope lists its role management policy: converged after 1 read(s), 3.6 s.
[oer-s109] The policy listed at the scope is the scope's own: True
[oer-s109] Azure role policy at the scope: rules differing from the baseline: 1 (Expiration_EndUser_Assignment)
[oer-s109] The scope lists its role management policy: converged after 1 read(s), 3.1 s.
[oer-s109] The policy listed at the scope is the scope's own: True
[oer-s109] Azure role policy back at its baseline: converged after 1 read(s), 4.2 s.
[oer-s109] Teardown A: Log Analytics Reader policy at oer-s109-rg at its baseline: True (rules differing before: 1: Expiration_EndUser_Assignment).
[oer-s109] Grants exactly at oer-s109-rg: role assignment of Reader for oer-s109-principal: True; eligibility of Monitoring Reader for oer-s109-principal: True
[oer-s109] Teardown B: AdminRemove of the eligibility of Monitoring Reader: 200 .
[oer-s109] the eligibility is no longer listed at oer-s109-rg: converged after 1 read(s), 1.8 s.
[oer-s109] Teardown B: DELETE of the role assignment of Reader: 200 .
[oer-s109] the role assignment is no longer listed at oer-s109-rg: converged after 1 read(s), 2 s.
[oer-s109] Teardown of 'oer-s109-': users 0, groups 1, access packages 0, catalogs 0; administrative units 0 and app registrations 0 are reported only.
[oer-s109] Teardown 1/6: directory role assignments of the prefixed principals.
[oer-s109] Teardown 2/6: PIM for Groups eligibility and assignments in the prefixed groups.
[oer-s109] Teardown 3/6: access package resource roles, access packages, catalog resources, catalogs.
[oer-s109] Teardown 4/6: members of the prefixed role-assignable groups.
[oer-s109] Teardown 5/6: the prefixed groups.
[oer-s109] Deleted: group oer-s109-principal (204).
[oer-s109] Teardown 6/6: the prefixed users.
[oer-s109] Teardown of 'oer-s109-': removed 1, residue 0, unreadable 0.
[oer-s109] oer-s109-rg is gone: not yet (read 1, 0.1 s, likely replication delay) -- reading again in 2 s.
[oer-s109] oer-s109-rg is gone: not yet (read 2, 2.4 s, likely replication delay) -- reading again in 4 s.
[oer-s109] oer-s109-rg is gone: converged after 3 read(s), 6.5 s.
[oer-s109] Teardown D: deleted oer-s109-rg.
[oer-s109] no 'oer-s109-' object is listed: not yet (read 1, 0.5 s, likely replication delay) -- reading again in 2 s.
[oer-s109] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s109-' is left.
[oer-s109] no 'oer-s109-' object is listed: converged after 2 read(s), 3.1 s.
[oer-s109] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s109-' is left.
[oer-s109] Resource group oer-s109-rg exists after the teardown: False
[oer-s109] Counts: groups now 98, at the baseline 98; equal: True
[oer-s109] Removed the recorded ids.
[oer-s109] Done.
[oer-s109] teardown exit code: 0
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s109-' is left.
[oer-s109] objects with the prefix: 0; unread collections: 0
[oer-s109] oer-s109-rg found: False
[oer-s109] module session cleared: True; Graph SDK session left: False
[oer-s109] raw\s109 deleted: True
RUNNER: check T.1 exit code 0; started 2026-10-10T18:54:47Z; took 47 s.
LEAK CHECK: psd1 values surviving redaction: 0
```

### T.2. Read-back once the listings have settled

- [x] **T.2** At least a minute after T.1, the sweep lists nothing with the prefix and no unread collection, the resource group is not found, and the tenant lists as many groups as the baseline of 0.2 recorded; `raw\s109\` (which H.1 creates again) is deleted afterwards.

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

Result: 2026-10-10 18:57 UTC, written by Write-OerLiveResult (OerLive 1.0.3).

```text
Verdict: PASS. 89 s after T.1 ended (two earlier read-backs, 18 s and 53 s after it, read the same), the sweep lists nothing with the prefix oer-s109- and no unread collection, oer-s109-rg is not found, and the tenant lists 98 groups, the count the baseline of 0.2 recorded; raw\s109 (created again by H.1) is deleted. Nothing is left in the tenant from this run, and no residue row has this step's prefix.

[OerLive] OerLive 1.0.3; config keys: AppId, CertificateNotAfter, CertificateThumbprint, Domain, ExpectedTenantDisplayName, NoPermAppId, OrgName, Repo, ScriptDir, SubscriptionId, TenantAlias, TenantId, UserDomain
[OerLive] Redactor self-test: no psd1 value survives: True; the module name is kept: True
=== CHECK T.2 ===
[oer-s109] Omnicit.EntraRBAC 1.1.4 loaded from REPO\.claude\worktrees\s10-steg9\output\module\Omnicit.EntraRBAC\1.1.4.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: Disconnect-OER and Disconnect-MgGraph first, then app-only with the certificate from Cert:\CurrentUser\My.
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app-only certificate session with the identity's app id: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: app name in the session is oer-live-cc: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: tenant is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: service principal of that app id is named oer-live-cc and is the token's signed-in object: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: organization name is the expected one: True; user domain is verified: True; organization id is the test tenant: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identity check: the module holds an ARM token for the test tenant, from the certificate: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc identification: the test subscription belongs to the test tenant and is Enabled: True
[oer-s109] Azure Resource Manager sign-in as oer-live-cc: identity check passed: True
[oer-s109] Sweep: no user, group, administrative unit, catalog, access package or app registration starting with 'oer-s109-' is left.
[oer-s109] objects with the prefix: 0; unread collections: 0
[oer-s109] oer-s109-rg found: False
[oer-s109] groups listed: 98
[oer-s109] raw\s109 deleted: True
RUNNER: check T.2 exit code 0; started 2026-10-10T18:57:03Z; took 5 s.
LEAK CHECK: psd1 values surviving redaction: 0
```
