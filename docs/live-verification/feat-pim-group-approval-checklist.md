# Live verification checklist -- approval in PIM for Groups (feat/pim-group-approval)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to PIM policies, and it runs the writes for real.** Every write is preceded by
its `-WhatIf` plan: read the plan against the `Expect:` line first, and only then run the line that
writes. Every apply goes through the `Invoke-S62Check` helper defined in Setup, which runs
`Invoke-OERStructure -WhatIf` unless `-Apply` is passed. No check uses `-Prune`. Every object any
command or document names was created by the prerequisite script for this file, or by check 5, and
carries the prefix `oer-s62`; the only policies written are the member and owner PIM-for-Groups
policies of `oer-s62-pim` and `oer-s62-new` and the Reader role management policy at the resource
group `oer-s62-rg`. Section 1 records the original state of the policies that exist before the first
write, and the Teardown puts them back before anything is deleted.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s62/` --
the helpers write every document, every raw Graph read and a results log there, and the folder is
git-ignored. What goes into a `Result:` below is redacted first, per [README.md](README.md): object
ids become `00000000-0000-0000-0000-0000000000NN` in first-appearance order for THIS file (the same
id always gets the same placeholder -- several checks turn on two ids being the same or different),
every user principal name on the test domain becomes a `personN@example.com` address, and no
credential and no bearer token is ever pasted. The test objects' display names may stay. **Never
render an error record** (`Format-List` on `$Error[0]`, on a `-ErrorVariable`, or on a catch
variable): a raw Graph failure's record carries the bearer token. Every block below prints the
error id and message only.

## What changed and why this needs a live tenant

The branch adds approval on activation to PIM for Groups, end to end, and fixes three things around
it. Commits are named by SUBJECT, never by hash: the hashes change when the branch is rebased onto
`main` before it merges.

- **A. `Set-OERGroupPimPolicy` sets approval** ("feat: approval rule and approver parameters for PIM
  for Groups policies", "fix: carry other-kind live approvers when an approver side is bound").
  New parameters `-RequireApproval [bool]`, `-ApproverUser [string[]]` (UPN or object id) and
  `-ApproverGroup [string[]]` (display name or object id) patch the `Approval_EndUser_Assignment`
  rule. Every approver is resolved to an object id before anything else; one that does not resolve
  refuses the call with `ApproverNotFound`. Binding a side REPLACES that side only: the unbound side,
  and any live approver that is neither a user nor a group, is carried from the live rule, which the
  cmdlet reads first -- a failed read of it refuses the whole call with `ApprovalRuleReadFailed`.
  Supplying approvers implies approval is required; requiring approval with no approver at all is
  refused with `ApproverRequired`. Stage fields the cmdlet has no parameter for carry over from the
  live stage, and a policy with no stage gets a 1-day timeout with approver justification required.
  The summary object reports `RequireApproval`, `ApproverUser` and `ApproverGroup` as SENT (object
  ids, the carried side included).
- **B. Declared approvers are resolved to object ids BEFORE the diff** ("feat: resolve declared
  approvers to object ids before the approval diff"). The private `Resolve-OERDeclaredApprover` turns
  a declared UPN or group display name into an object id, de-duplicated case-insensitively, for a
  group `pimPolicy` block AND for a `roleManagementPolicies[]` item, so both diffs compare ids with
  ids. Before this, an ARM approver declared by UPN or group name never matched the live approver
  and every apply reported a change. When `requireApproval` is declared `false`, declared approvers
  are not resolved at all (they are ignored downstream).
- **C. The group `pimPolicy` block reads, diffs and applies approval** ("feat: read, diff and apply
  approval in group pimPolicy", "feat: approval fields in the group pimPolicy document").
  `Get-OERGroupPimPolicy` gains `RequireApproval` (`$null` when the policy has no approval rule) and
  `Approvers` (`Id`/`UserType`/`DisplayName`). Graph **beta** -- where PIM for Groups is pinned --
  returns a group approver as `id` with no `groupId`; the private `ConvertFrom-OERGraphApprover` is
  now the one reader of an approver and falls back to `id`, so a live group approver finally has an
  id to compare. The document gains `requireApproval` and `approvers { users[], groups[] }` in the
  flat and the nested member/owner forms; each side is presence-gated and only the declared side(s)
  are sent, so an undeclared side survives on the live rule. `Get-OERInventory` emits
  `requireApproval`, and `approvers` as object ids while `requireApproval` is true.
- **D. The owner policy can no longer receive the member policy's settings, and a refused read is
  told apart from a missing policy** ("fix: resolve the requested PIM policy only, and tell a missing
  policy from a refused read", "test: prove PimPolicyNotFound actually reaches the caller, not just
  the result row"). `Get-OERPimGroupPolicyId` used to fall back to the FIRST policy assignment when
  the requested access type was not listed yet -- right after a group is created that returned the
  MEMBER policy for an OWNER lookup, and owner settings were written to the member policy with no
  error. It now returns nothing instead. `Set-OERGroupPimPolicy` reports a refused policy-assignment
  read as `PimPolicyReadFailed` and a genuinely missing policy as `PimPolicyNotFound` (whose message
  now names replication delay first). The apply engine, for a group it CREATED in the same run,
  retries a missing policy with one shared budget of 2, 4, 8 and 16 seconds per group item, then
  reports `Failed` with a replication message; a refused read is never retried.
- **E. Unknown keys in `groups[]` items and `pimPolicy` blocks warn** ("feat: warn about unknown keys
  in groups and pimPolicy blocks"). `Test-OERStructure` reports each as a Warning, with a
  `Did you mean '<current name>'?` suffix for the five field names the inventory README used to
  document before they were renamed (`activationEnabledRules`, `activeEnabledRules`,
  `eligibleAlertRecipients`, `activeAlertRecipients`, `activationAlertRecipients`). The README itself
  was corrected in "docs: correct the pimPolicy field names and add approval to the inventory README".

**Every unit test on this branch mocks the transport.** They prove the module's decisions given the
shapes the tests assume. They cannot prove the five things this file is for:

1. That Graph beta ACCEPTS the approval rule the module sends (no `@odata.type` on the setting or the
   stage, approvers in the `userId`/`groupId` PATCH shape), and returns it in the shape the reader
   assumes -- in particular which id field a group approver comes back with (checks 2, 3).
2. That a document naming approvers by UPN and group name converges -- `Unchanged` on the second
   run -- for PIM for Groups AND for an Azure role management policy (checks 3, 4).
3. That a group created in the same run gets each access type's settings on ITS OWN policy, and what
   the retry actually looks like against real replication (check 5).
4. That a real refusal reaches the operator as `PimPolicyReadFailed`, and a real not-onboarded group
   as `PimPolicyNotFound` (check 6).
5. That an exported inventory carries approval as ids and re-applies as `Unchanged` (check 8).

## What this file does not check, and why

- **An activation that actually goes through approval.** The test users are created DISABLED, and an
  activation request, an approver's decision and PIM's own notification flow are the platform's
  behaviour, not the module's. Nothing in this branch changes how PIM runs an approval.
- **A live approver of a kind other than user or group** (a requestor's manager, for example). The
  module carries such an approver through a PATCH untouched and ignores it in the diff; both are
  pinned by the `Set-OERGroupPimPolicy`, `New-OERPimRuleSet` and `ConvertFrom-OERGraphApprover`
  suites. Putting one on a live policy needs the portal and adds no module path the units do not
  already drive.
- **The same approver declared twice** (a UPN and that user's id, or an id in another letter case)
  and **empty-string entries**. De-duplication and the empty-entry rule are unit-pinned in the
  `Resolve-OERDeclaredApprover`, `Set-OERGroupPimPolicy` and diff suites; live they would show only
  that one approver is sent, which 2.4 already shows for the plain case.
- **`ApprovalRuleReadFailed`.** It needs the approval-rule read refused while the policy-assignment
  read succeeds, which no test identity gives on demand. Unit-pinned.
- **`requireApproval: false` with approver names that do not resolve.** The engine does not resolve
  them at all; unit-pinned in `Resolve-OERDeclaredApprover` and the handler suites.
- **Exhausting the retry budget on purpose.** Check 5 records whatever real replication produces. If
  Graph lists both policies at once, the retry path is not exercised live and is pinned only by the
  `Sync-OERStructureGroup` suite -- say so on 5.2's result line.
- **Restoring an EMPTY approver list with approval off.** No module call can express it: binding an
  approver side implies approval, and `Set-OERGroupPimPolicy` refuses approval with no approver. T.3
  records what is left on an approval-off stage, and T.5 deletes the policies with their group and
  resource group.
- **The approval fields of an Azure policy in `Get-OERInventory`**, and the ARM whole-list approver
  semantics of `Set-OERRoleManagementPolicy`. Not changed by this branch.

---

## Setup, once

**You need:**

- A **test tenant** -- never a customer tenant -- with Microsoft Entra ID P2 or ID Governance
  licensing (PIM for Groups), a Tenant Profile alias for it (`Get-OERConfiguration`) whose profile
  names the commercial cloud, one verified domain, and one **test subscription**.
- One admin account in that tenant that can create users and security groups, grant PIM-for-Groups
  eligibility, change PIM-for-Groups policies, create resource groups and change role management
  policies in the subscription. Global Administrator plus Owner on the test subscription covers all
  of it. **Every role has to be ACTIVE for the whole run, teardown included** -- with PIM, activate
  them before the first block, for the longest window the policy allows, and re-activate before the
  Teardown if they could lapse. A directory role that is not active shows up as
  `Authorization_RequestDenied` or a 403 on a policy write, and on the teardown's deletions.
- For check 6.2 only: a **non-privileged identity** in the same tenant -- an ordinary user with no
  directory role, no PIM role and no ownership of the test group -- that you can sign in as. Without
  one, 6.2 is marked `[~]` with the reason.
- The prerequisite script `Initialize-OerS62Prereq.ps1`. It is kept OUTSIDE this repository and is
  never committed; it is run by hand, by the operator, and never by Claude or CI.
- PowerShell 7 and a clone of this repository on this branch.

**Variables, build and module path.** Paste into one PowerShell 7 window and keep that window for
the whole file.

```powershell
$Repo    = '<your-clone-of-Omnicit.EntraRBAC>'   # the clone whose origin is github.com/Omnicit/Omnicit.EntraRBAC
$Prereq  = '<path-to-Initialize-OerS62Prereq.ps1>'
$Alias   = '<your-test-tenant-alias>'
$OrgName = '<your-test-tenant-display-name>'   # the organization display name, exactly as Graph reports it
$SubId   = '<your-test-subscription-id>'
$Domain  = '<your-verified-domain>'
$Prefix  = 'oer-s62'
$ApproverUpn   = "$Prefix-approver@$Domain"
$EligibleUpn   = "$Prefix-eligible@$Domain"
$ApproversName = "$Prefix-approvers"
$PimName       = "$Prefix-pim"
$NewName       = "$Prefix-new"
$RgScope = "/subscriptions/$SubId/resourceGroups/$Prefix-rg"
$Raw     = Join-Path $Repo 'docs/live-verification/raw/s62'

Set-Location $Repo
git remote get-url origin
git branch --show-current
# Build in a process of its own. ModuleBuilder fills every Build-Module parameter build.yaml leaves
# unset from a variable of the same name in the calling session, so the $Prefix above would be
# written into the top of the built module, and importing it would run 'oer-s62' as a command.
pwsh -NoProfile -File ./build.ps1 -Tasks build
if ($LASTEXITCODE -ne 0) { throw 'The build failed.' }
$Sep = [System.IO.Path]::PathSeparator
$env:PSModulePath = (Resolve-Path ./output/module).Path + $Sep + (Resolve-Path ./output/RequiredModules).Path + $Sep + $env:PSModulePath
$ModulePsd1 = (Get-ChildItem ./output/module/Omnicit.EntraRBAC/*/Omnicit.EntraRBAC.psd1 |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (Select-String -Path ($ModulePsd1 -replace '\.psd1$', '.psm1') -Pattern "^#Region 'PREFIX'" -Quiet) {
    throw 'The built module carries a PREFIX region: rebuild with the line above, never with ./build.ps1 in this window.'
}
New-Item -ItemType Directory -Path $Raw -Force | Out-Null
```

**Create the test objects.** The script runs in its own process, so this window keeps its own
sign-in. It signs in twice (Microsoft Graph for Phase 1, `Connect-OER` for Phase 2). Before its
first write it identifies the tenant positively: it reads the signed-in organization and refuses to
go on -- nothing written -- unless the organization's display name equals
`-ExpectedTenantDisplayName` EXACTLY, `-UserDomain` is one of its verified domains, and the Tenant
Profile's tenant id (or domain) names the same organization. Only then does it ask once for
confirmation, naming the organization display name, the tenant id and the subscription; the
`Connect-OER` sign-in must land in that same organization too. It ends with a summary of names and
REAL object ids -- redact those before pasting (check 0.2). It is idempotent: a second run creates
nothing that exists and only fills in what is missing. The `-WhatIf` line is optional (it still
signs in and identifies the tenant, and asks nothing).

```powershell
pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -WhatIf
pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1
```

What it creates, all named with the prefix: two DISABLED users `oer-s62-approver` and
`oer-s62-eligible` on your domain (display names `OER S62 Approver` and `OER S62 Eligible`, random
passwords never printed); the security group `oer-s62-approvers` with the approver user as its only
member; the security group `oer-s62-pim` with no members, onboarded to PIM for Groups by a 30-day
member eligibility for the eligible user (that first eligibility is what creates its member and
owner policies); and the resource group `oer-s62-rg`, with nothing assigned at it, whose Reader role
management policy is this file's Azure test policy. It refuses to run while a user
`oer-s62-nobody@<your-verified-domain>` exists (check 2.1 relies on that name resolving to nothing),
and warns while a group `oer-s62-new` exists (check 5 must create it).

**Sign in, and define the helpers.**

```powershell
Import-Module Omnicit.EntraRBAC -Force
$ErrorActionPreference = 'Continue'   # module code reads the GLOBAL preference; Stop would end a run at its first Failed row
Connect-OER -TenantAlias $Alias -IncludeARM

function Invoke-S62Check {
    # Writes the document to the raw folder, validates it offline, then runs Invoke-OERStructure on
    # it -- under -WhatIf unless -Apply is given. Warnings are merged into the output stream (3>&1),
    # which keeps their order. With -VerboseLog the verbose stream is captured as well (4>&1): all of
    # it goes to a -verbose.log file named after the check id, and only the step-4 retry lines are
    # printed.
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string[]]$Include,
        [switch]$Apply,
        [switch]$ValidateOnly,
        [switch]$VerboseLog
    )
    $Path = Join-Path $Raw "$Id.json"
    Set-Content -Path $Path -Value $Json -Encoding utf8NoBOM
    Write-Host "=== $Id -- $Path"
    Get-Content -Path $Path | ForEach-Object { Write-Host "    $_" }

    $global:S62Validation = Test-OERStructure -Path $Path
    Write-Host "--- offline validation: Valid = $($S62Validation.Valid), findings = $(@($S62Validation.Errors).Count)"
    $S62Validation.Errors | Format-List Section, Item, Path, Severity, Message | Out-Host
    if ($ValidateOnly -or -not $S62Validation.Valid) { return }

    $Splat = @{ Path = $Path; Include = $Include; ErrorAction = 'Continue'; ErrorVariable = 'CheckError' }
    if ($Apply) { $Splat.Confirm = $false } else { $Splat.WhatIf = $true }
    if ($VerboseLog) { $Splat.Verbose = $true }
    Write-Host ('--- Invoke-OERStructure -Include {0}{1}{2}' -f ($Include -join ','),
        $(if ($Apply) { ' -Confirm:$false' } else { ' -WhatIf' }), $(if ($VerboseLog) { ' -Verbose' } else { '' }))

    $Out = @(Invoke-OERStructure @Splat 3>&1 4>&1)
    $VerboseRecords    = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
    $global:S62Warning = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $global:S62Result  = @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] -and $_ -isnot [System.Management.Automation.VerboseRecord] })
    $global:S62Error   = @($CheckError)

    if ($VerboseLog) {
        $VerboseRecords | ForEach-Object { $_.Message } | Set-Content -Path (Join-Path $Raw "$Id-verbose.log") -Encoding utf8NoBOM
        $global:S62Retry = @($VerboseRecords | Where-Object { $_.Message -like '*is not listed yet; retry*' } | ForEach-Object { $_.Message })
        Write-Host "--- step-4 retry lines: $($S62Retry.Count) (all $($VerboseRecords.Count) verbose lines are in $Id-verbose.log)"
        $S62Retry | ForEach-Object { Write-Host "    VERBOSE: $_" }
    }
    Write-Host "--- warnings, in the order written: $($S62Warning.Count)"
    $S62Warning | ForEach-Object { Write-Host "    WARNING: $($_.Message)" }
    Write-Host "--- errors: $($S62Error.Count)"
    $S62Error | ForEach-Object { Write-Host "    ERROR [$($_.FullyQualifiedErrorId)]: $($_.Exception.Message)" }
    Write-Host "--- results: $($S62Result.Count)"
    $S62Result | Format-List Section, Item, Action, Detail | Out-Host
    Write-Host "--- action counts: $(($S62Result | Group-Object Action -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')"
    $S62Result | Select-Object @{ Name = 'CheckId'; Expression = { $Id } }, Section, Item, Action, Detail |
        Export-Csv -Path (Join-Path $Raw 'all-results.csv') -Append -NoTypeInformation
}

function Show-S62Error {
    # Prints the error id and message of each record the named cmdlet PUBLISHED -- never the record
    # itself: a raw transport record can carry the bearer token (README.md, "Credentials"). Records the
    # engine collected from nested calls are counted, not shown.
    param([object[]]$Record, [Parameter(Mandatory)][string]$Cmdlet)
    $All = @($Record | Where-Object { $null -ne $_ })
    $Published = @($All | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains $Cmdlet })
    Write-Host "--- errors published by $($Cmdlet): $($Published.Count) (other records collected, not shown: $($All.Count - $Published.Count))"
    $Published | ForEach-Object { Write-Host "    ERROR [$($_.FullyQualifiedErrorId)]: $($_.Exception.Message)" }
}

function Get-S62RawRule {
    # One policy rule read straight from Microsoft Graph beta, OUTSIDE the module -- an independent
    # witness of what the module wrote -- through the Microsoft Graph context Connect-OER set up.
    # Saved to the raw folder as a .json file named after -Label. A failure prints its message only
    # and clears $Error: a raw Invoke-MgGraphRequest error record carries the bearer token.
    param([Parameter(Mandatory)][string]$PolicyId, [Parameter(Mandatory)][string]$RuleId, [Parameter(Mandatory)][string]$Label)
    try {
        $Rule = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop `
            -Uri "beta/policies/roleManagementPolicies/$PolicyId/rules/$RuleId"
    } catch {
        Write-Host "--- $($Label): raw read FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    $Rule | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    $Rule
}

function Show-S62RawApproval {
    # The Approval_EndUser_Assignment rule of one policy as Graph beta returns it: the requirement,
    # the mode, the stage count, the first stage's timeout and approver justification, and every
    # primary approver with the id fields Graph actually filled in.
    param([Parameter(Mandatory)][string]$PolicyId, [Parameter(Mandatory)][string]$Label)
    $Rule = Get-S62RawRule -PolicyId $PolicyId -RuleId 'Approval_EndUser_Assignment' -Label $Label
    if (-not $Rule) { return }
    $Stages = @($Rule.setting.approvalStages | Where-Object { $null -ne $_ })
    $Stage = $Stages | Select-Object -First 1
    Write-Host ('--- {0}: policy {1}, isApprovalRequired = {2}, approvalMode = {3}, stages = {4}, stage 1 timeout = {5} day(s), approver justification = {6}' -f
        $Label, $PolicyId, $Rule.setting.isApprovalRequired, $Rule.setting.approvalMode, $Stages.Count,
        $Stage.approvalStageTimeOutInDays, $Stage.isApproverJustificationRequired)
    $Primary = @($Stage.primaryApprovers | Where-Object { $null -ne $_ })
    Write-Host "    primary approvers: $($Primary.Count)"
    $Primary | Select-Object @{ Name = 'odataType'; Expression = { $_.'@odata.type' } }, id, userId, groupId, description |
        Format-Table -AutoSize | Out-Host
}

function Get-S62RawPolicyAssignment {
    # A group's PIM-for-Groups policy assignments straight from Graph beta, outside the module: one
    # row per access type (roleDefinitionId member or owner) with the policy id it points at.
    param([Parameter(Mandatory)][string]$GroupId)
    $F = [uri]::EscapeDataString("scopeId eq '$GroupId' and scopeType eq 'Group'")
    try {
        @((Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop `
                    -Uri "beta/policies/roleManagementPolicyAssignments?`$filter=$F").value)
    } catch {
        Write-Host "--- raw policy-assignment read FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
    }
}

function Get-S62Baseline {
    # The 1.x baseline, read back from disk so a restarted window still has it.
    Get-Content -Path (Join-Path $Raw '1-baseline.json') -Raw | ConvertFrom-Json
}

function Restore-S62Policy {
    # Puts the three policies section 1 recorded back to that baseline -- under -WhatIf unless -Apply
    # is given. Per policy: first the baseline approvers, only when there were any (binding an approver
    # side turns approval on), then the baseline requirement.
    param([switch]$Apply)
    $Base = Get-S62Baseline
    $Mode = if ($Apply) { @{ Confirm = $false } } else { @{ WhatIf = $true } }
    $Targets = @(
        @{ Key = 'member'; Cmdlet = 'Set-OERGroupPimPolicy'; Splat = @{ Group = $PimName; AccessType = 'member' } }
        @{ Key = 'owner'; Cmdlet = 'Set-OERGroupPimPolicy'; Splat = @{ Group = $PimName; AccessType = 'owner' } }
        @{ Key = 'arm'; Cmdlet = 'Set-OERRoleManagementPolicy'; Splat = @{ Role = 'Reader'; Scope = $RgScope } }
    )
    foreach ($T in $Targets) {
        $B = $Base.($T.Key)
        $BUser  = @(@($B.Approvers) | Where-Object { $_ -and $_.UserType -eq 'User' } | ForEach-Object { [string]$_.Id })
        $BGroup = @(@($B.Approvers) | Where-Object { $_ -and $_.UserType -eq 'Group' } | ForEach-Object { [string]$_.Id })
        if ($BUser.Count + $BGroup.Count -gt 0) {
            Write-Host "--- $($T.Key): restoring the baseline approvers ($($BUser.Count) user(s), $($BGroup.Count) group(s))"
            $Splat = $T.Splat + $Mode + @{ ApproverUser = $BUser; ApproverGroup = $BGroup; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'RestoreError' }
            & $T.Cmdlet @Splat | Out-Null
            Show-S62Error -Record $RestoreError -Cmdlet $T.Cmdlet
        }
        Write-Host "--- $($T.Key): restoring RequireApproval = $([bool]$B.RequireApproval)"
        $Splat = $T.Splat + $Mode + @{ RequireApproval = [bool]$B.RequireApproval; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'RestoreError' }
        & $T.Cmdlet @Splat | Out-Null
        Show-S62Error -Record $RestoreError -Cmdlet $T.Cmdlet
    }
}
```

**The documents, and the script check 6.2 runs in a second window.** Paste this block as it
stands -- every here-string must close at column 0. The checks name each document by its `$Docs`
key and describe it.

```powershell
$Docs = @{}

$Docs.PimApproval = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [
    {
      "displayName": "$PimName",
      "members": null,
      "pimPolicy": {
        "member": { "requireApproval": true, "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] } },
        "owner":  { "requireApproval": true, "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] } }
      }
    }
  ]
}
"@

$Docs.PimDropUser = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [
    {
      "displayName": "$PimName",
      "members": null,
      "pimPolicy": {
        "member": { "requireApproval": true, "approvers": { "users": [] } },
        "owner":  { "requireApproval": true, "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] } }
      }
    }
  ]
}
"@

$Docs.ArmApproval = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "roleManagementPolicies": [
    {
      "scope": "$RgScope",
      "role": "Reader",
      "requireApproval": true,
      "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] }
    }
  ]
}
"@

$Docs.NewGroup = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [
    {
      "displayName": "$NewName",
      "members": null,
      "eligibility": [ { "principal": "$EligibleUpn", "durationDays": 30 } ],
      "pimPolicy": {
        "member": { "activationMaxHours": 2 },
        "owner":  { "activationMaxHours": 3, "requireApproval": true, "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] } }
      }
    }
  ]
}
"@

$Docs.OldNames = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [
    {
      "displayName": "$PimName",
      "members": null,
      "eligibilities": [],
      "pimPolicy": { "member": { "activationEnabledRules": [ "Justification" ] } }
    },
    {
      "displayName": "$NewName",
      "members": null,
      "pimPolicy": { "activeEnabledRules": [ "Justification" ] }
    }
  ]
}
"@

$RefusedReadScript = @'
# Check 6.2 -- runs in a window of its own, signed in as the NON-privileged identity. Written by the
# checklist; its inputs come from 6.2-input.json beside it.
$ErrorActionPreference = 'Continue'
$In = Get-Content -Path (Join-Path $PSScriptRoot '6.2-input.json') -Raw | ConvertFrom-Json
$env:PSModulePath = $In.PSModulePathPrefix + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module Omnicit.EntraRBAC -Force
Write-Host 'Sign in as the NON-privileged identity, not the admin account. A private browser window keeps the admin session out of the way.'
Connect-OER -TenantAlias $In.Alias -DeviceCode -Force
try {
    $Me = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop -Uri 'v1.0/me?$select=userPrincipalName'
    Write-Host "Signed in as: $($Me.userPrincipalName)"
} catch {
    Write-Host "Could not read the signed-in user: $($PSItem.Exception.Message)"
}
$Result = @(Set-OERGroupPimPolicy -Group $In.PimName -ActivationMaxHours 2 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable SetError)
Write-Host "Result objects: $($Result.Count)"
$Published = @($SetError | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains 'Set-OERGroupPimPolicy' })
Write-Host "Errors published by Set-OERGroupPimPolicy: $($Published.Count)"
$Published | ForEach-Object { Write-Host "ERROR [$($_.FullyQualifiedErrorId)]: $($_.Exception.Message)" }
# The same policy-assignment read, outside the module. Only the HTTP status is taken from a failure;
# nothing else in that record is printed, since it carries the bearer token.
$F = [uri]::EscapeDataString("scopeId eq '$($In.PimId)' and scopeType eq 'Group'")
$Status = 'not captured'
try {
    $R = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop -Uri "beta/policies/roleManagementPolicyAssignments?`$filter=$F"
    $Status = "200, $(@($R.value).Count) assignment(s)"
} catch {
    $Ex = $PSItem.Exception
    if ($null -ne $Ex.Response -and $null -ne $Ex.Response.StatusCode) { $Status = [int]$Ex.Response.StatusCode }
    elseif ($null -ne $Ex.ResponseStatusCode) { $Status = [int]$Ex.ResponseStatusCode }
}
Write-Host "Raw status of the policy-assignment read for this identity: $Status"
$Error.Clear()
Disconnect-OER
Write-Host 'Done. Copy the lines above into check 6.2, then close this window.'
'@
```

In the `Expect:` lines below, `<RgScope>` is `/subscriptions/<your-test-subscription-id>/resourceGroups/oer-s62-rg`,
`<ApproverUpn>` is `oer-s62-approver@<your-verified-domain>` and `<EligibleUpn>` is
`oer-s62-eligible@<your-verified-domain>`. `<IdApprover>`, `<IdApprovers>`, `<PimId>` and
`<IdEligible>` are the object ids 0.3 records (the approver user, the approver group, the PIM test
group and the eligible user); `<PolicyIdMember>` and `<PolicyIdOwner>` are the two policy ids 1.1
records and `<ArmPolicyId>` the one 1.2 records; `<IdNew>` is the id of the group check 5 creates.

**Run order.** Section 0, then section 1 before ANY other check -- it is the baseline the Teardown
restores. Section 2 before 3 (3 starts from the state 2 leaves), and 3 before 8 (8 expects the state
3.4 leaves). Sections 4, 5 and 6 at any time after 1; section 7 at any time (offline). Teardown last.
If the window is closed part-way, paste the Setup blocks again (variables, sign-in and helpers,
documents), re-run 0.3, and restore the policy ids with
`$PolicyIdMember = (Get-S62Baseline).member.PolicyId; $PolicyIdOwner = (Get-S62Baseline).owner.PolicyId`.

---

### 0. Preparation

- [ ] **0.1 The session runs THIS branch's build.**

  ```powershell
  git -C $Repo fetch origin
  git -C $Repo log --format=%s origin/main..HEAD
  $M = Get-Module Omnicit.EntraRBAC
  '{0} {1} from {2}' -f $M.Name, $M.Version, $M.ModuleBase
  & $M { Get-Command ConvertFrom-OERGraphApprover, Resolve-OERDeclaredApprover } | Format-Table Name, CommandType -AutoSize
  (Get-Command Set-OERGroupPimPolicy).Parameters.Keys -match '^(RequireApproval|ApproverUser|ApproverGroup)$'
  (Get-OERRequiredScope -Cmdlet Set-OERGroupPimPolicy).GraphScope -contains 'User.ReadBasic.All'
  ```

  **Expect:** before the merge, the log lists at least these subjects (record any later one too --
  the release notes and review fixes land after this file was written): "feat: resolve declared
  approvers to object ids before the approval diff", "feat: approval rule and approver parameters
  for PIM for Groups policies", "fix: carry other-kind live approvers when an approver side is
  bound", "feat: read, diff and apply approval in group pimPolicy", "feat: approval fields in the
  group pimPolicy document", "feat: warn about unknown keys in groups and pimPolicy blocks", "fix:
  resolve the requested PIM policy only, and tell a missing policy from a refused read", "test: prove
  PimPolicyNotFound actually reaches the caller, not just the result row", "docs: correct the
  pimPolicy field names and add approval to the inventory README" and "docs: live-verification
  checklist for approval in PIM for Groups". Subjects, not hashes: a rebase onto `main` rewrites every
  hash. After the merge the range is empty -- the squash merge folds the branch into one commit on
  `main`, and these subjects appear in that commit's body instead. `ModuleBase` lies under
  `<your-clone>/output/module/Omnicit.EntraRBAC/`; both private functions are listed as `Function`;
  the parameter line prints `RequireApproval`, `ApproverUser` and `ApproverGroup`; the last line
  prints `True`.
  **Failure looks like:** `CommandNotFound` for either function, no parameter names, or `False` -- a
  build without this branch's change is loaded. Rebuild, fix `PSModulePath`, re-import; nothing
  below means anything until this passes.
  **Result:**

- [ ] **0.2 The prerequisite script ran and every test object exists.** Paste its summary table, redacted.

  **Expect:** before any write the run printed
  `Identified the test tenant: organization '<your-test-tenant-display-name>', tenant id <id>, verified domain <your-verified-domain>.`,
  asked once with a question naming that organization, its tenant id and the subscription, and later
  printed `Phase 2 (Connect-OER) is signed in to the confirmed test tenant ...`. No warning about
  `oer-s62-new`. The run ends with `Done.` and no error; the summary has one row each for the two
  users, the groups `oer-s62-approvers` and `oer-s62-pim` and the resource group `oer-s62-rg`, one
  `group member` row (`oer-s62-approvers <- <ApproverUpn>`) and one `PIM eligibility (member, ends ...)`
  row (`oer-s62-pim <- <EligibleUpn>`, about 30 days out). No row reads `(none -- not created)`.
  **Failure looks like:** a `(none -- not created)` row, or the script stopped on an error -- fix the
  cause and re-run the script before 0.3. A `Refusing to run: ...` line from the tenant
  identification means nothing was written: check `$OrgName` (exact, case-sensitive), `$Domain` and
  the Tenant Profile before trying again -- never weaken the check. A warning that `oer-s62-new`
  exists means a previous run was not torn down: run the Teardown's T.4 and T.5 first.
  **Result:**

- [ ] **0.3 Record the object ids every later check compares against.** Read-only.

  ```powershell
  $IdApprovers = (Get-OERGroup -Group $ApproversName -ErrorAction Stop).Id
  $ApproverMembers = @(Get-OERGroupMember -Group $ApproversName -ErrorAction Stop)
  $ApproverMembers | Format-Table PrincipalId, UserPrincipalName -AutoSize
  $IdApprover = ($ApproverMembers | Where-Object UserPrincipalName -eq $ApproverUpn).PrincipalId
  $PimId = (Get-OERGroup -Group $PimName -ErrorAction Stop).Id
  $Elig0 = @(Get-OERGroupEligibility -Group $PimName -ErrorAction Stop)
  $Elig0 | Format-Table PrincipalId, AccessType, StartDateTime, EndDateTime -AutoSize
  $IdEligible = ($Elig0 | Where-Object AccessType -eq 'member' | Select-Object -First 1).PrincipalId
  @(Get-OERGroupMember -Group $PimName -ErrorAction Stop).Count
  @(Get-OERGroup -Filter "displayName eq '$NewName'" -ErrorAction SilentlyContinue).Count
  $IdApprovers, $IdApprover, $PimId, $IdEligible | ForEach-Object { [bool]$_ }
  ```

  **Expect:** `oer-s62-approvers` has exactly one member, `<ApproverUpn>`. `oer-s62-pim` has exactly
  one eligibility, `AccessType` `member`, for `<IdEligible>`, and `0` members. The `oer-s62-new`
  count is `0`. The `[bool]` line prints `True` four times.
  **Failure looks like:** any count off, or a `False` -- re-run the prerequisite script and record it.
  An `oer-s62-new` count of `1` means check 5 cannot test a group created in the same run: run T.4
  and T.5, then the prerequisite script again.
  **Result:**

---

### 1. Baseline -- the original state of every policy this file touches

Nothing below this section may run before it: the Teardown restores exactly what 1.1 and 1.2 save.

- [ ] **1.1 The member and owner policies of `oer-s62-pim`, through the module and raw from Graph.**

  ```powershell
  $Base = [ordered]@{}
  foreach ($T in 'member', 'owner') {
      $P = Get-OERGroupPimPolicy -Group $PimName -AccessType $T -ErrorAction Stop
      Write-Host ('=== {0}: PolicyId {1}, ActivationMaxHours {2}, RequireApproval {3}, approvers {4}' -f $T, $P.PolicyId,
          $P.ActivationMaxHours, $(if ($null -eq $P.RequireApproval) { '(no approval rule)' } else { $P.RequireApproval }), @($P.Approvers).Count)
      $P.Approvers | Format-Table Id, UserType, DisplayName -AutoSize | Out-Host
      @($P.Rules | Where-Object id -eq 'Approval_EndUser_Assignment') | ConvertTo-Json -Depth 12 |
          Set-Content -Path (Join-Path $Raw "1.1-$T-approval-rule-module.json") -Encoding utf8NoBOM
      $Base[$T] = [ordered]@{ PolicyId = $P.PolicyId; ActivationMaxHours = $P.ActivationMaxHours
          RequireApproval = $P.RequireApproval; Approvers = @($P.Approvers | Select-Object Id, UserType, DisplayName) }
      Show-S62RawApproval -PolicyId $P.PolicyId -Label "1.1-$T-raw"
  }
  $PolicyIdMember = $Base.member.PolicyId
  $PolicyIdOwner  = $Base.owner.PolicyId
  [bool]$PolicyIdMember -and [bool]$PolicyIdOwner -and ($PolicyIdMember -ne $PolicyIdOwner)
  ```

  **Expect:** two policies with DIFFERENT policy ids (the last line prints `True`). On both,
  `RequireApproval` is `False` -- not `(no approval rule)` -- with `0` approvers, and the raw read
  agrees: `isApprovalRequired = False`, `primary approvers: 0`. Record each policy's
  `ActivationMaxHours`, `approvalMode`, stage count, stage timeout and approver justification as
  printed -- 2.4 shows which of them carry over.
  **Failure looks like:** `PimPolicyNotFound` for either access type (the group is not onboarded:
  re-run the prerequisite script), the same policy id twice, or approvers already present (record
  them; the Teardown restores them, and 2.1's first line then prints a `What if:` line instead of
  `ApproverRequired`).
  **Result:**

- [ ] **1.2 The Reader role management policy at `oer-s62-rg`, and the baseline file.**

  ```powershell
  $Arm0 = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  $Arm0 | Format-List PolicyId, Scope, RoleName, ActivationMaxHours, RequireApproval
  $Arm0.Approvers | Format-Table Id, UserType, DisplayName -AutoSize
  @($Arm0.EffectiveRules | Where-Object id -eq 'Approval_EndUser_Assignment') | ConvertTo-Json -Depth 12 |
      Set-Content -Path (Join-Path $Raw '1.2-arm-approval-rule.json') -Encoding utf8NoBOM
  $Base.arm = [ordered]@{ PolicyId = $Arm0.PolicyId; RequireApproval = $Arm0.RequireApproval
      Approvers = @($Arm0.Approvers | Select-Object Id, UserType, DisplayName) }
  $Base | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $Raw '1-baseline.json') -Encoding utf8NoBOM
  Get-Content -Path (Join-Path $Raw '1-baseline.json')
  ```

  **Expect:** `Scope` is `<RgScope>`, `RoleName` `Reader`, `RequireApproval` `False` and no approvers
  -- the Azure default for a new resource group. The baseline file holds `member`, `owner` and `arm`,
  each with its `PolicyId`, `RequireApproval` and `Approvers`.
  **Failure looks like:** a read error (the ARM token or the Owner role is missing -- see Setup), or
  approval already on (record it: 4.2 may then report `Unchanged`, and the Teardown restores it).
  **Result:**

---

### 2. `Set-OERGroupPimPolicy` -- approval on the member and the owner policy

- [ ] **2.1 The two approver guards refuse before anything is sent.** `-WhatIf` only: a guard that failed would print a `What if:` line here, never a write.

  ```powershell
  Set-OERGroupPimPolicy -Group $PimName -AccessType member -RequireApproval $true -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E21a
  Show-S62Error -Record $E21a -Cmdlet Set-OERGroupPimPolicy
  Set-OERGroupPimPolicy -Group $PimName -AccessType member -ApproverUser "$Prefix-nobody@$Domain" -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E21b
  Show-S62Error -Record $E21b -Cmdlet Set-OERGroupPimPolicy
  ```

  **Expect:** no `What if:` line and no object from either call. The first publishes exactly one
  error, `ApproverRequired,Set-OERGroupPimPolicy`:
  `Approval cannot be required with no approver: PIM policy '<PolicyIdMember>' has none on its live approval rule and none was supplied. Pass -ApproverUser or -ApproverGroup.`
  The second publishes exactly one, `ApproverNotFound,Set-OERGroupPimPolicy`:
  `User 'oer-s62-nobody@<your-verified-domain>' was not found.`
  **Failure looks like:** a `What if: ... "Patch rule Approval_EndUser_Assignment" ...` line from
  either call -- the guard let an approval without approvers, or an unresolved approver, through to
  the PATCH. (After a baseline with approvers, see 1.1, the first call's `What if:` line is correct.)
  **Result:**

- [ ] **2.2 The plan: one rule per access type.**

  ```powershell
  foreach ($T in 'member', 'owner') {
      Set-OERGroupPimPolicy -Group $PimName -AccessType $T -RequireApproval $true -ApproverUser $ApproverUpn -ApproverGroup $ApproversName -WhatIf
  }
  ```

  **Expect:** exactly two lines, and no object and no error:
  `What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy <PolicyIdMember>".`
  then the same for `<PolicyIdOwner>`.
  **Failure looks like:** any other rule id in the plan, or a target policy id that is not one of 1.1's.
  **Result:**

- [ ] **2.3 Set approval, with the approver named by UPN and the group by display name.**

  ```powershell
  $Set23 = foreach ($T in 'member', 'owner') {
      Set-OERGroupPimPolicy -Group $PimName -AccessType $T -RequireApproval $true -ApproverUser $ApproverUpn -ApproverGroup $ApproversName `
          -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable E23 -WarningVariable W23
      Show-S62Error -Record $E23 -Cmdlet Set-OERGroupPimPolicy
      Write-Host "--- $T warnings: $(@($W23).Count)"
      $W23 | ForEach-Object { Write-Host "    WARNING: $_" }
  }
  $Set23 | Format-List GroupId, PolicyId, AccessType, RequireApproval, ApproverUser, ApproverGroup, Applied, FailedRules
  ```

  **Expect:** no warning and no published error for either access type. Two objects, member then
  owner: `GroupId` `<PimId>`; `PolicyId` `<PolicyIdMember>`, then `<PolicyIdOwner>`; `RequireApproval`
  `True`; `ApproverUser` `{<IdApprover>}`; `ApproverGroup` `{<IdApprovers>}` -- object ids, not the
  UPN and the name that were passed; `Applied` `True`; `FailedRules` `{}`.
  **Failure looks like:** a warning `Rule 'Approval_EndUser_Assignment' was not applied: ...` and a
  `PolicyRulesRejected` error with `Applied` `False` -- record Graph's message (redacted). If it asks
  for an `@odata.type` on the approval setting or stage, that is the open question this branch left
  for the live run (the module sends neither). If it names the approver as invalid or disabled, the
  prerequisite script's disabled approver account is the cause: record it, enable
  `oer-s62-approver` by hand, re-run 2.3 and record both runs.
  **Result:**

- [ ] **2.4 Read back INDEPENDENTLY, raw from Graph beta, per policy id.**

  ```powershell
  Show-S62RawApproval -PolicyId $PolicyIdMember -Label '2.4-member-raw'
  Show-S62RawApproval -PolicyId $PolicyIdOwner -Label '2.4-owner-raw'
  ```

  **Expect:** for EACH of the two policies: `isApprovalRequired = True`, `approvalMode = SingleStage`,
  `stages = 1`, and exactly two primary approvers -- one `#microsoft.graph.singleUser` whose `id` or
  `userId` is `<IdApprover>`, one `#microsoft.graph.groupMembers` whose `id` or `groupId` is
  `<IdApprovers>`. **Record which columns Graph filled for each approver** -- in particular whether
  the group comes back with `id` (the branch's premise: beta returns a group approver as `id` with no
  `groupId`) or with `groupId`. The stage timeout and approver justification are 1.1's values where
  1.1 had a stage, and `1` and `True` where it had none.
  **Failure looks like:** `isApprovalRequired = False`, a missing approver, a third approver, or a
  policy that does not carry what 2.3 reported.
  **Result:**

- [ ] **2.5 The module reads the same approvers back, with an id for the group.**

  ```powershell
  foreach ($T in 'member', 'owner') {
      $P = Get-OERGroupPimPolicy -Group $PimName -AccessType $T -ErrorAction Stop
      Write-Host ('--- {0}: PolicyId {1}, RequireApproval {2}' -f $T, $P.PolicyId, $P.RequireApproval)
      $P.Approvers | Sort-Object UserType | Format-Table Id, UserType, DisplayName -AutoSize | Out-Host
  }
  ```

  **Expect:** both policies `RequireApproval` `True` with exactly two rows: `Group` with `Id`
  `<IdApprovers>` and `User` with `Id` `<IdApprover>`. No row has an empty `Id` or an empty `UserType`.
  **Failure looks like:** a `Group` row with an empty `Id` -- `ConvertFrom-OERGraphApprover` did not
  read the id beta returned, and check 3's first run will report a change it should not.
  **Result:**

---

### 3. The apply document -- group `pimPolicy` approval converges

Document `$Docs.PimApproval`: the group `oer-s62-pim` with `"members": null` and a nested
`pimPolicy` whose `member` and `owner` blocks both declare `"requireApproval": true` and
`"approvers": { "users": [ "<ApproverUpn>" ], "groups": [ "oer-s62-approvers" ] }` -- a UPN and a
display name, never an id.

- [ ] **3.1 The plan: nothing to change after 2.3.**

  ```powershell
  Invoke-S62Check -Id '3.1' -Json $Docs.PimApproval -Include Groups
  ```

  **Expect:** validation `Valid = True`, `0` findings. No warning, no error, no `What if:` line.
  Exactly three results, all Section `groups`, Item `oer-s62-pim`, in this order: `Unchanged`
  `group properties match`; `Unchanged` `pimPolicy (member) already matches`; `Unchanged`
  `pimPolicy (owner) already matches`.
  **Failure looks like:** `Skipped` `would set pimPolicy (member): approvers(users=[<IdApprover>],groups=[<IdApprovers>])`
  (or the same for the owner) -- the live approvers did not match the resolved declared ids. Before
  this branch that is what every run reported, because the beta group approver had no `groupId`.
  **Result:**

- [ ] **3.2 Run 1 and run 2, applied: both `Unchanged` -- the beta `id` proof.**

  ```powershell
  Invoke-S62Check -Id '3.2a' -Json $Docs.PimApproval -Include Groups -Apply
  Invoke-S62Check -Id '3.2b' -Json $Docs.PimApproval -Include Groups -Apply
  ```

  **Expect:** each run exactly as 3.1: three `Unchanged` rows, no warning, no error.
  **Failure looks like:** an `Updated` row with `pimPolicy (member) set: approvers(...)` on either
  run -- the diff never converges.
  **Result:**

Document `$Docs.PimDropUser`: the same, except that the `member` block declares only
`"approvers": { "users": [] }` -- the user side declared EMPTY, the group side not declared at all.
The `owner` block is unchanged.

- [ ] **3.3 The plan for dropping the user approver from the member policy.**

  ```powershell
  Invoke-S62Check -Id '3.3' -Json $Docs.PimDropUser -Include Groups
  ```

  **Expect:** `Valid = True`, `0` findings. One line
  `What if: Performing the operation "Set PIM policy (member): approvers(users=[])" on target "oer-s62-pim".`
  Exactly three results: `Unchanged` `group properties match`; `Skipped`
  `would set pimPolicy (member): approvers(users=[])`; `Unchanged` `pimPolicy (owner) already matches`.
  **Failure looks like:** `groups=[...]` inside the member change -- the diff would send the side the
  document did not declare; or an owner change.
  **Result:**

- [ ] **3.4 Apply it: the member policy loses the user, and the undeclared group side stays.**

  ```powershell
  Invoke-S62Check -Id '3.4' -Json $Docs.PimDropUser -Include Groups -Apply
  foreach ($T in 'member', 'owner') {
      $P = Get-OERGroupPimPolicy -Group $PimName -AccessType $T -ErrorAction Stop
      Write-Host ('--- {0}: RequireApproval {1}, approvers {2}' -f $T, $P.RequireApproval, @($P.Approvers).Count)
      $P.Approvers | Sort-Object UserType | Format-Table Id, UserType, DisplayName -AutoSize | Out-Host
  }
  Show-S62RawApproval -PolicyId $PolicyIdMember -Label '3.4-member-raw'
  ```

  **Expect:** no warning, no error; three results: `Unchanged` `group properties match`; `Updated`
  `pimPolicy (member) set: approvers(users=[])`; `Unchanged` `pimPolicy (owner) already matches`.
  The member policy: `RequireApproval` `True` with exactly ONE approver, `Group` `<IdApprovers>` --
  carried from the live rule although the document did not declare it. The owner policy: unchanged,
  two approvers. The raw member read: `isApprovalRequired = True`, `primary approvers: 1`, the
  `#microsoft.graph.groupMembers` approver `<IdApprovers>`.
  **Failure looks like:** the member row `Failed` with `ApproverRequired` in its detail, or `0`
  approvers left -- the undeclared group side was sent empty instead of carried.
  **Result:**

- [ ] **3.5 The changed document converges.**

  ```powershell
  Invoke-S62Check -Id '3.5' -Json $Docs.PimDropUser -Include Groups -Apply
  ```

  **Expect:** three `Unchanged` rows (`group properties match`, `pimPolicy (member) already matches`,
  `pimPolicy (owner) already matches`), no warning, no error.
  **Failure looks like:** `Updated` for the member policy again.
  **Result:**

---

### 4. The apply document -- a `roleManagementPolicies[]` approver named by UPN and group name converges

Document `$Docs.ArmApproval`: one `roleManagementPolicies` item, scope `<RgScope>`, role `Reader`,
`"requireApproval": true` and `"approvers": { "users": [ "<ApproverUpn>" ], "groups": [ "oer-s62-approvers" ] }`.

- [ ] **4.1 The plan.**

  ```powershell
  Invoke-S62Check -Id '4.1' -Json $Docs.ArmApproval -Include RoleManagementPolicies
  ```

  **Expect:** `Valid = True`, `0` findings; no warning, no error. One line
  `What if: Performing the operation "Update role management policy" on target "Reader @ <RgScope>".`
  and one result: Section `roleManagementPolicies`, Item `Reader @ <RgScope>`, `Skipped`,
  `would update role management policy for 'Reader' at '<RgScope>'`. (If 1.2 already showed approval
  on with exactly these two approvers: `Unchanged` and no `What if:` line.)
  **Failure looks like:** `Failed` with `could not resolve an approver: ...` -- the UPN or the group
  name did not resolve.
  **Result:**

- [ ] **4.2 Run 1, applied, and read back.**

  ```powershell
  Invoke-S62Check -Id '4.2' -Json $Docs.ArmApproval -Include RoleManagementPolicies -Apply
  $Arm42 = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  $Arm42 | Format-List PolicyId, RequireApproval
  $Arm42.Approvers | Sort-Object UserType | Format-Table Id, UserType, DisplayName -AutoSize
  ```

  **Expect:** no warning, no error; one result, `Updated`,
  `updated role management policy for 'Reader' at '<RgScope>' (requireApproval=True, approvers(users=[<IdApprover>],groups=[<IdApprovers>]))`
  -- ids in the change list, not the UPN and the name. The read-back: `PolicyId` `<ArmPolicyId>`,
  `RequireApproval` `True`, approvers exactly `Group` `<IdApprovers>` and `User` `<IdApprover>`.
  **Failure looks like:** `Failed` with Azure's rejection (record it), or approvers in the change
  list as a UPN or a name.
  **Result:**

- [ ] **4.3 Run 2: `Unchanged`.**

  ```powershell
  Invoke-S62Check -Id '4.3' -Json $Docs.ArmApproval -Include RoleManagementPolicies -Apply
  ```

  **Expect:** one result, `Unchanged`, `policy already matches for 'Reader' at '<RgScope>'`; no
  warning, no error.
  **Failure looks like:** `Updated` again -- a declared name was compared with a live id, which is
  what every run did before this branch.
  **Result:**

---

### 5. A group created in the same run -- each access type gets its own policy

Document `$Docs.NewGroup`: a group `oer-s62-new` that does not exist yet, `"members": null`, one
time-bound eligibility (`<EligibleUpn>`, `"durationDays": 30`, member access) to onboard it, and a
nested `pimPolicy` with DIFFERENT settings per access type: `member` `"activationMaxHours": 2`;
`owner` `"activationMaxHours": 3`, `"requireApproval": true` and the same two approvers as section 3.
Before this branch, an owner lookup that ran before Graph listed the owner policy fell back to the
member policy, and the owner's settings landed there.

- [ ] **5.1 The plan.**

  ```powershell
  Invoke-S62Check -Id '5.1' -Json $Docs.NewGroup -Include Groups
  ```

  **Expect:** `Valid = True`, `0` findings; no warning, no error. One line
  `What if: Performing the operation "Create group" on target "oer-s62-new".` and exactly three
  results, all Item `oer-s62-new`, `Skipped`: `would create group oer-s62-new`,
  `would configure eligibility for '<EligibleUpn>' after group is created`,
  `would configure pimPolicy after group is created`.
  **Failure looks like:** any row for an existing `oer-s62-new` (see 0.3).
  **Result:**

- [ ] **5.2 Apply it, with the verbose stream captured for the retry lines.**

  ```powershell
  Invoke-S62Check -Id '5.2' -Json $Docs.NewGroup -Include Groups -Apply -VerboseLog
  ```

  **Expect:** in this order, all Item `oer-s62-new`:
  1. `Created` `created group oer-s62-new (<IdNew>)`.
  2. `Updated` `set time-bound member eligibility for '<EligibleUpn>' (30 days): time-bound member eligibility (30 days) is absent`.
  3. The member policy: `Updated` `pimPolicy (member) set: activationMaxHours=2` -- or `Failed`
     `pimPolicy (member) not applied: Microsoft Graph does not list a PIM-for-groups policy for 'member' access on group 'oer-s62-new', created in this run, after <n> retries. A new group's policies can take a while to be listed (replication delay); re-running the same document usually applies them.`
     with a matching `ERROR [PimPolicyNotFound,Invoke-OERStructure]: pimPolicy (member) not applied: ...` line.
  4. The owner policy: `Updated` `pimPolicy (owner) set: activationMaxHours=3; requireApproval=True; approvers(users=[<IdApprover>],groups=[<IdApprovers>])`
     -- or the same `Failed` text and error line for `'owner'` access.

  The retry lines are zero to four
  `Sync-OERStructureGroup: pimPolicy (<member or owner>) of new group 'oer-s62-new' is not listed yet; retry <n> in <s> s.`,
  across BOTH access types together, with the delays `2`, `4`, `8`, `16` in that order and `<n>`
  counting within each access type -- one budget per group item, spent by whichever access type hits
  it first (an owner that finds the budget spent fails `after 0 retries`). Record every retry line,
  and whether the path was exercised at all. No warning. With no retry line and no `Failed` row the
  error list is empty. On the retry path it may also hold records whose id starts with
  `PimPolicyNotFound` from the policy reads the handler caught and retried -- the engine collects
  those into `-ErrorVariable` as well; record them, they are expected there.
  **Failure looks like:** the owner row `Updated` while 5.4 shows the owner's settings on the member
  policy (the fallback defect); a `Failed` row naming `PimPolicyReadFailed` or a 403 (a refusal, not
  replication -- record it); more than four retry lines, or a delay sequence other than 2, 4, 8, 16. A
  `Failed` eligibility row (`failed to add eligibility for ...`) means the group was too new for PIM
  itself; the policy rows then fail too -- carry on with 5.3.
  **Result:**

- [ ] **5.3 Only if 5.2 had a `Failed` row: re-run until it applies.** Otherwise write "not needed" as the result.

  ```powershell
  Invoke-S62Check -Id '5.3' -Json $Docs.NewGroup -Include Groups -Apply -VerboseLog
  ```

  **Expect:** `Unchanged` `group properties match`, the eligibility `Unchanged`
  (`eligibility for '<EligibleUpn>' (member) already matches`) or, if it failed in 5.2, `Updated`; and
  `Updated` with 5.2's detail text for each access type that failed there. The group now exists, so no
  retry line appears: a policy still not listed shows as `Failed`
  `pimPolicy (<type>) update failed: Group '<IdNew>' has no PIM-for-groups policy for '<type>' access yet. ...`
  with an error line whose id starts with `PimPolicyNotFound` -- wait a minute and run this block
  again. Record every run.
  **Failure looks like:** the same `Failed` row after several minutes and runs.
  **Result:**

- [ ] **5.4 Read BOTH new policies back by their policy ids.**

  ```powershell
  $IdNew = (Get-OERGroup -Group $NewName -ErrorAction Stop).Id
  $Asg54 = @(Get-S62RawPolicyAssignment -GroupId $IdNew | Sort-Object roleDefinitionId)
  $Asg54 | Format-Table roleDefinitionId, policyId -AutoSize
  $Asg54 | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $Raw '5.4-assignments.json') -Encoding utf8NoBOM
  foreach ($A in $Asg54) {
      $Exp = Get-S62RawRule -PolicyId $A.policyId -RuleId 'Expiration_EndUser_Assignment' -Label "5.4-$($A.roleDefinitionId)-expiration-raw"
      Write-Host ('--- {0}: policy {1}, activation maximumDuration {2}' -f $A.roleDefinitionId, $A.policyId, $Exp.maximumDuration)
      Show-S62RawApproval -PolicyId $A.policyId -Label "5.4-$($A.roleDefinitionId)-raw"
  }
  foreach ($T in 'member', 'owner') {
      $P = Get-OERGroupPimPolicy -Group $NewName -AccessType $T -ErrorAction Stop
      Write-Host ('--- {0} (module): PolicyId {1}, ActivationMaxHours {2}, RequireApproval {3}, approvers {4}' -f
          $T, $P.PolicyId, $P.ActivationMaxHours, $P.RequireApproval, @($P.Approvers).Count)
  }
  ```

  **Expect:** exactly two assignments, `member` and `owner`, pointing at two DIFFERENT policy ids.
  The `member` policy: activation `maximumDuration` `PT2H`, `isApprovalRequired = False`,
  `primary approvers: 0`. The `owner` policy: `PT3H`, `isApprovalRequired = True`, `stages = 1`, two
  primary approvers (`<IdApprover>` and `<IdApprovers>`). The module lines agree per access type: the
  member line names the member assignment's policy id with `ActivationMaxHours 2`,
  `RequireApproval False`, `approvers 0`; the owner line names the owner assignment's policy id with
  `3`, `True`, `2`.
  **Failure looks like:** `PT3H` or approval on the MEMBER policy, or the member policy still at the
  new group's default while 5.2 reported the owner `Updated` -- owner settings written to the member
  policy, the defect this branch fixes. One policy id for both access types.
  **Result:**

- [ ] **5.5 The new group's document converges.**

  ```powershell
  Invoke-S62Check -Id '5.5' -Json $Docs.NewGroup -Include Groups -Apply
  ```

  **Expect:** exactly four results, all `Unchanged`: `group properties match`,
  `eligibility for '<EligibleUpn>' (member) already matches`, `pimPolicy (member) already matches`,
  `pimPolicy (owner) already matches`. No warning, no error.
  **Failure looks like:** any `Updated` row.
  **Result:**

---

### 6. A refused policy read is not a missing policy

- [ ] **6.1 A group that was never onboarded: `PimPolicyNotFound`.** `-WhatIf` only; the refusal comes before any write.

  ```powershell
  Set-OERGroupPimPolicy -Group $ApproversName -ActivationMaxHours 2 -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E61
  Show-S62Error -Record $E61 -Cmdlet Set-OERGroupPimPolicy
  ```

  **Expect:** no `What if:` line, no object, and exactly one published error,
  `PimPolicyNotFound,Set-OERGroupPimPolicy`:
  `Group '<IdApprovers>' has no PIM-for-groups policy for 'member' access yet. A group created moments ago can take a short while before Microsoft Graph lists its policies (replication delay), and re-running usually succeeds. A group never used with PIM for Groups gets its policies when it is first onboarded, for example by its first eligibility.`
  **Failure looks like:** `PimPolicyReadFailed` -- Graph's answer for a never-onboarded group
  (`ResourceTypeNotSupported`) was read as a refusal.
  **Result:**

- [ ] **6.2 A refused read, by a non-privileged identity in a window of its own: `PimPolicyReadFailed`.** Mark `[~]` with the reason if no such identity is available.

  A second window keeps this window's admin sign-in intact: the module keeps one credential per
  process. This block writes the script and its inputs to the raw folder and opens it; on Windows
  `Start-Process` opens a new console window, elsewhere open a second terminal and run
  `pwsh -NoProfile -NoExit -File` on the path it prints.

  ```powershell
  $RefusedReadPath = Join-Path $Raw '6.2-refused-read.ps1'
  [ordered]@{
      Alias              = $Alias
      PimName            = $PimName
      PimId              = $PimId
      PSModulePathPrefix = (Resolve-Path (Join-Path $Repo 'output/module')).Path + [System.IO.Path]::PathSeparator + (Resolve-Path (Join-Path $Repo 'output/RequiredModules')).Path
  } | ConvertTo-Json | Set-Content -Path (Join-Path $Raw '6.2-input.json') -Encoding utf8NoBOM
  Set-Content -Path $RefusedReadPath -Value $RefusedReadScript -Encoding utf8NoBOM
  $RefusedReadPath
  Start-Process -FilePath pwsh -ArgumentList @('-NoExit', '-NoProfile', '-File', ('"{0}"' -f $RefusedReadPath))
  ```

  In the new window, complete the device-code sign-in as the NON-privileged identity, then copy its
  output here (redacted).

  **Expect:** `Signed in as:` the non-privileged identity -- not the admin. `Result objects: 0`.
  `Errors published by Set-OERGroupPimPolicy: 1`, and that one is
  `ERROR [PimPolicyReadFailed,Set-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '<PimId>' ('member' access): <cause>. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.`
  The raw status line reads `403` (or another refusal status).
  **Failure looks like:** `PimPolicyNotFound` while the raw status is `403` -- a refusal collapsed into
  absence, the defect this branch fixes. `PimPolicyNotFound` with a raw status of `200, 0 assignment(s)`
  is a different finding: Graph HID the policy from this identity instead of refusing, and the module
  cannot tell that apart from absence -- record it as "cannot be verified, and therefore we do not
  know". `Result objects: 1` means this identity COULD write: stop, and run 6.3. `GroupNotFound`, or a
  sign-in that cannot complete (consent, conditional access), means no suitable identity: `[~]`.
  **Result:**

- [ ] **6.3 Nothing was written by the refused identity.** Back in this window.

  ```powershell
  $P63 = Get-OERGroupPimPolicy -Group $PimName -AccessType member -ErrorAction Stop
  '{0} -> {1}' -f (Get-S62Baseline).member.ActivationMaxHours, $P63.ActivationMaxHours
  $P63.ActivationMaxHours -eq (Get-S62Baseline).member.ActivationMaxHours
  ```

  **Expect:** the same value on both sides, and `True`.
  **Failure looks like:** `2` on the right -- the refused identity changed the policy.
  **Result:**

---

### 7. Unknown keys in `groups[]` items and `pimPolicy` blocks -- offline

Document `$Docs.OldNames`: two groups. `groups[0]` (`oer-s62-pim`) carries an unknown item key
`eligibilities` and a nested `pimPolicy.member` using the OLD name `activationEnabledRules`;
`groups[1]` (`oer-s62-new`) has a flat `pimPolicy` using the old name `activeEnabledRules`. Nothing
is applied: validation only.

- [ ] **7.1 Each unknown key is a Warning, and the old names get the did-you-mean hint.**

  ```powershell
  Invoke-S62Check -Id '7.1' -Json $Docs.OldNames -Include Groups -ValidateOnly
  ```

  **Expect:** `Valid = True` with exactly three findings, all Section `groups`, Severity `Warning`, in
  this order:
  1. Item `oer-s62-pim`, Path `groups[0].eligibilities`, Message
     `Unknown key 'eligibilities' at groups[0] is not applied by Invoke-OERStructure and will be ignored.`
  2. Item `oer-s62-pim`, Path `groups[0].pimPolicy.member.activationEnabledRules`, Message
     `Unknown key 'activationEnabledRules' at groups[0].pimPolicy.member is not applied by Invoke-OERStructure and will be ignored. Did you mean 'activationEnablement'?`
  3. Item `oer-s62-new`, Path `groups[1].pimPolicy.activeEnabledRules`, Message
     `Unknown key 'activeEnabledRules' at groups[1].pimPolicy is not applied by Invoke-OERStructure and will be ignored. Did you mean 'activeEnablement'?`

  No `Invoke-OERStructure` line follows.
  **Failure looks like:** no finding for a key (it would be dropped silently on apply), an `Error`
  severity (a document that used to apply now refuses), or a hint pointing at the wrong name.
  **Result:**

---

### 8. `Get-OERInventory` -- approval round-trips

- [ ] **8.1 The inventory of `oer-s62-pim` carries approval, with approvers as object ids.**

  ```powershell
  $Inv = Get-OERInventory -Include Groups -GroupFilter "displayName eq '$PimName'" -ErrorAction SilentlyContinue -ErrorVariable E81
  Show-S62Error -Record $E81 -Cmdlet Get-OERInventory
  $InvJson = $Inv | ConvertTo-Json -Depth 20
  Set-Content -Path (Join-Path $Raw '8.1-inventory.json') -Value $InvJson -Encoding utf8NoBOM
  @($Inv.groups).Count
  $Inv.groups[0].displayName
  $Inv.groups[0].pimPolicy | ConvertTo-Json -Depth 8
  ```

  **Expect:** no published error (in particular no `InventoryPartial`); one group, `oer-s62-pim`. In
  its `pimPolicy`: `member` has `"requireApproval": true` and `"approvers": { "groups": [ "<IdApprovers>" ] }`
  with NO `users` key (3.4 emptied that side); `owner` has `"requireApproval": true` and
  `"approvers": { "users": [ "<IdApprover>" ], "groups": [ "<IdApprovers>" ] }`. Every approver is an
  object id -- never a UPN or a display name.
  **Failure looks like:** `requireApproval` missing, `approvers` missing while `requireApproval` is
  true, or an approver written as a name.
  **Result:**

- [ ] **8.2 The exported document re-applies as `Unchanged`.**

  ```powershell
  Invoke-S62Check -Id '8.2a' -Json $InvJson -Include Groups
  Invoke-S62Check -Id '8.2b' -Json $InvJson -Include Groups -Apply
  ```

  **Expect:** `Valid = True` with no `Error` finding (record any Warning). Both runs: no `What if:`
  line, no warning, no error, and every result `Unchanged`, all Item `oer-s62-pim`:
  `group properties match`; `owner '<upn>' already present` for each owner the inventory listed, if
  the group has any; `eligibility for '<EligibleUpn>' (member) already matches`;
  `pimPolicy (member) already matches`; `pimPolicy (owner) already matches`. The action counts line
  reads `Unchanged=<n>` and nothing else.
  **Failure looks like:** any `Skipped`, `Updated` or `Failed` row -- the exported document does not
  describe the live state it was read from.
  **Result:**

---

### Teardown

The approval changes are undone FIRST, while the objects still exist, then the prerequisite script
removes everything. Deleting `oer-s62-pim` and `oer-s62-new` removes their PIM-for-Groups policies,
and deleting `oer-s62-rg` removes its role management policies.

- [ ] **T.1 The restore plan.** `-WhatIf`.

  ```powershell
  Restore-S62Policy
  ```

  **Expect:** for `member`, `owner` and `arm` in turn: `restoring RequireApproval = False` (after a
  `restoring the baseline approvers` line only where 1.x recorded approvers), then one `What if:`
  line each -- `What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy <PolicyIdMember>".`,
  the same for `<PolicyIdOwner>`, and
  `What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "role management policy '<ArmPolicyId>'".`
  -- and `errors published by ...: 0` after each.
  **Failure looks like:** a target that is not one of 1.x's policy ids -- stop, do not run T.2. A
  `NoChange` error for `arm` means the Azure policy already matches its baseline (4.2 did not apply):
  record it and carry on.
  **Result:**

- [ ] **T.2 Restore.**

  ```powershell
  Restore-S62Policy -Apply
  ```

  **Expect:** the same lines as T.1 without the `What if:` lines, and `errors published by ...: 0`
  after each.
  **Failure looks like:** a published error -- record it; T.3 shows what state the policy is left in.
  **Result:**

- [ ] **T.3 Read back against the baseline.**

  ```powershell
  $B = Get-S62Baseline
  foreach ($T in 'member', 'owner') {
      $P = Get-OERGroupPimPolicy -Group $PimName -AccessType $T -ErrorAction Stop
      Write-Host ('=== {0}: RequireApproval {1} (baseline {2}), ActivationMaxHours {3} (baseline {4}), same policy id: {5}' -f
          $T, $P.RequireApproval, $B.$T.RequireApproval, $P.ActivationMaxHours, $B.$T.ActivationMaxHours, ($P.PolicyId -eq $B.$T.PolicyId))
      $P.Approvers | Sort-Object UserType | Format-Table Id, UserType, DisplayName -AutoSize | Out-Host
      Show-S62RawApproval -PolicyId $P.PolicyId -Label "T.3-$T-raw"
  }
  $A = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  Write-Host ('=== arm: RequireApproval {0} (baseline {1}), same policy id: {2}' -f $A.RequireApproval, $B.arm.RequireApproval, ($A.PolicyId -eq $B.arm.PolicyId))
  $A.Approvers | Sort-Object UserType | Format-Table Id, UserType, DisplayName -AutoSize
  ```

  **Expect:** on all three, `RequireApproval` equals its baseline (`False`) and the policy id is the
  same; the two group policies keep their baseline `ActivationMaxHours`; the raw reads show
  `isApprovalRequired = False`. Where 1.x recorded approvers, exactly those. Where it recorded none --
  the expected case -- the approvers the checks left stay on the approval-off stage, and that is the
  one expected difference: the member policy keeps `Group` `<IdApprovers>` (3.4), the owner policy
  and the Azure policy keep `<IdApprover>` and `<IdApprovers>`. No module call can empty an approver
  list while turning approval off (see "What this file does not check"); with approval off none of
  them is ever asked, and T.5 deletes all three policies with their group and resource group. Record
  the residue.
  **Failure looks like:** `RequireApproval` `True` on any of the three, a changed policy id, or a
  changed `ActivationMaxHours`.
  **Result:**

- [ ] **T.4 Read the teardown plan.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -Teardown -WhatIf
  ```

  **Expect:** the tenant is identified first, exactly as in 0.2 (the `Identified the test tenant`
  line, no question under `-WhatIf`), and Phase 2 reports it is signed in to the confirmed test
  tenant. Then `What if:` lines, and nothing else changed, for: deleting the resource group
  `oer-s62-rg`; removing the member eligibility of `<IdEligible>` on `oer-s62-pim` and on
  `oer-s62-new`; deleting the groups `oer-s62-new`, `oer-s62-pim` and `oer-s62-approvers`; deleting
  the two users. Every name starts with `oer-s62`. Nothing was deleted, so both sweeps list what is
  still there (the resource group; the two users and three groups); then
  `WhatIf: nothing was created or removed.` and `Done.`
  **Failure looks like:** any target without the prefix -- stop, do not run T.5.
  **Result:**

- [ ] **T.5 Remove every test object.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantAlias $Alias -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -Teardown
  ```

  **Expect:** the tenant is identified and the one question names the organization, its tenant id
  and the subscription BEFORE anything is removed; the Phase 2 and the second Phase 1 sign-in each
  report `... is signed in to the confirmed test tenant ...`. Then `Deletion of resource group oer-s62-rg accepted.`,
  one `Removed the member eligibility of principal <IdEligible> on ...` line for `oer-s62-pim` and one
  for `oer-s62-new`, `Deleted group ...` for the three groups and `Deleted user ...` for the two
  users. The Phase 2 sweep reports `no resource group starting with 'oer-s62' is left.` or at most
  `oer-s62-rg` in `Deleting` state (Azure deletes it asynchronously); the Phase 1 sweep reports
  `no user or group starting with 'oer-s62' is left.`; `Done.`
  **Failure looks like:** a sweep line `still present: ...` other than a `Deleting` resource group; an
  error. Re-run T.5 (it only removes what is still there) and record both runs. An
  `Authorization_RequestDenied` on a deletion means a role is not active (see Setup): activate it and
  re-run T.5.
  **Result:**

- [ ] **T.6 Read back through the module that everything is gone.**

  ```powershell
  Get-OERGroup -Filter "startswith(displayName,'$Prefix')" -ErrorAction Continue
  Get-OERResourceGroup -Subscription $SubId | Where-Object ResourceGroup -like "$Prefix*"
  ```

  **Expect:** the group line writes a not-found error (or nothing) and the resource group line prints
  nothing. If the resource group is still listed as `Deleting`, re-read after a few minutes and
  record when it went.
  **Failure looks like:** any object listed.
  **Result:**

- [ ] **T.7 No object outside the prefix was touched, and nothing was removed by an apply.**

  ```powershell
  $All = Import-Csv (Join-Path $Raw 'all-results.csv')
  $All | Where-Object Action -in 'Created', 'Updated', 'Removed' | Format-Table CheckId, Section, Item, Action, Detail -Wrap
  @($All | Where-Object { $_.Item -notlike "*$Prefix*" }).Count
  ```

  **Expect:** no `Removed` row anywhere (no check used `-Prune`). The `Created`/`Updated` rows are
  exactly: `3.4` `Updated` for `pimPolicy (member)`; `4.2` `Updated` for `Reader @ <RgScope>` (absent
  if 4.2 reported `Unchanged`); and for `oer-s62-new` across 5.2 and 5.3 one `Created`, one eligibility
  `Updated` and one `Updated` per access type. The count line prints `0`: every row of every run names
  an `oer-s62` object (an Azure row names the scope `.../resourceGroups/oer-s62-rg`). The only writes
  outside the apply engine are 2.3 and T.2, both on `oer-s62-pim`'s policies and the Reader policy at
  `oer-s62-rg`, and the prerequisite script's, all prefix-named.
  **Failure looks like:** a `Removed` row, a `Created` or `Updated` row not listed above, or a count
  above `0`.
  **Result:**

- [ ] **T.8 Read back through Microsoft Graph that no user or group is left.** The module has no user read, so this signs in separately, read-only, at the very end.

  ```powershell
  $TenantId = (Get-OERConfiguration -TenantAlias $Alias).TenantId
  Disconnect-OER
  Connect-MgGraph -TenantId $TenantId -Scopes 'User.Read.All', 'Group.Read.All' -ContextScope Process -NoWelcome
  $F = [uri]::EscapeDataString("startswith(userPrincipalName,'$Prefix')")
  @((Invoke-MgGraphRequest -Uri "v1.0/users?`$filter=$F&`$select=id,userPrincipalName").value).Count
  $F = [uri]::EscapeDataString("startswith(displayName,'$Prefix')")
  @((Invoke-MgGraphRequest -Uri "v1.0/groups?`$filter=$F&`$select=id,displayName").value).Count
  Disconnect-MgGraph
  $Error.Clear()   # a failed raw Graph call leaves an ErrorRecord that can carry the bearer token -- README.md, "Credentials"
  ```

  **Expect:** `0`, `0`. The two users now sit in Deleted items for 30 days, which is Entra ID's
  design; they hold no role, membership or eligibility, and the next prerequisite run can create the
  same names again. The deleted security groups are gone for good.
  **Failure looks like:** any count above `0`.
  **Result:**

- [ ] **T.9 Redact, then clean up.** Move what the results above need from `docs/live-verification/raw/s62/` into this file, redacted per [README.md](README.md), then delete the folder.

  Ids to `00000000-0000-0000-0000-0000000000NN`, user principal names to `personN@example.com`, no
  credential, no bearer token -- and that includes the second window's output from 6.2.

  ```powershell
  Remove-Item -LiteralPath $Raw -Recurse -Force
  git -C $Repo status --short docs/live-verification
  ```

  **Expect:** `git status` shows only this checklist as modified; nothing under `raw/` is ever staged.
  **Result:**
