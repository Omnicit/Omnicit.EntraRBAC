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
  A side declared EMPTY clears that side and keeps the other ("test: pin that a document can empty one approver side"; live in 3.6-3.8).
  The summary object reports `RequireApproval`, `ApproverUser` and `ApproverGroup` as SENT (object
  ids, the carried side included). Every user and group approver goes out in the Graph BETA shape
  ("fix: send PIM for Groups approvers in the Graph beta shape"): `@odata.type`, `id` and
  `isBackup = false`, never v1.0's `userId`/`groupId` and never the read-only `description` -- beta's
  `singleUser` and `groupMembers` declare only `id`, `description` and `isBackup`, and the only
  documented `userId`/`groupId` PATCH is v1.0's, for Entra roles. Check 2 settles it.
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
  now names replication delay first, in `Get-OERGroupPimPolicy` too). The apply engine, for a group
  it CREATED in the same run, first ASKS whether each access type's policy is listed yet
  (`Get-OERPimGroupPolicyId`, which answers a silent nothing while it is not) and waits with one
  shared budget of 2, 4, 8 and 16 seconds per group item before its single policy read ("fix: ask
  whether a new group's PIM policy is listed instead of retrying the read") -- so a run that ends
  `Updated` leaves no `PimPolicyNotFound` record behind. While it waits, a `404 ResourceNotFound`
  counts as not listed yet: a group PIM does not know yet answers the question that way, which this
  file's first run measured ("fix: wait through a 404 for the policy of a group created in the same
  run"). With the budget spent it reports `Failed` with a replication message that names a re-run
  and gives no advice about eligibility: Graph lists a group's policies whether or not it was ever
  onboarded (Microsoft Graph documentation, "Onboarding groups to PIM for Groups"). A refused lookup
  is never waited on, and neither is a group that already existed, a 404 included.
- **E. Unknown keys in `groups[]` items and `pimPolicy` blocks warn** ("feat: warn about unknown keys
  in groups and pimPolicy blocks"). `Test-OERStructure` reports each as a Warning, with a
  `Did you mean '<current name>'?` suffix for the five field names the inventory README used to
  document before they were renamed (`activationEnabledRules`, `activeEnabledRules`,
  `eligibleAlertRecipients`, `activeAlertRecipients`, `activationAlertRecipients`). The README itself
  was corrected in "docs: correct the pimPolicy field names and add approval to the inventory README".

**Every unit test on this branch mocks the transport.** They prove the module's decisions given the
shapes the tests assume. They cannot prove the five things this file is for:

1. That Graph beta ACCEPTS the approval rule the module sends (no `@odata.type` on the setting or the
   stage, approvers in the beta `id`/`isBackup` shape -- the documented `userId`/`groupId` PATCH is
   v1.0's), and returns it in the shape the reader assumes -- in particular which id field a group
   approver comes back with (checks 2, 3).
2. That a document naming approvers by UPN and group name converges -- `Unchanged` on the second
   run -- for PIM for Groups AND for an Azure role management policy (checks 3, 4).
3. That a group created in the same run gets each access type's settings on ITS OWN policy, and what
   the retry actually looks like against real replication (check 5).
4. That a real refusal reaches the operator as `PimPolicyReadFailed` (check 6). A group Graph lists
   no policy for cannot be produced on demand -- see check 6.1 -- so `PimPolicyNotFound` is proven by
   the unit suites only.
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
- **Restoring an EMPTY approver list with approval off through a module cmdlet.** No module call can
  express it: binding an approver side implies approval, and `Set-OERGroupPimPolicy` refuses
  approval with no approver. T.3 records what is left on an approval-off stage. The group policies go
  with their groups in T.5. The Azure policy does NOT go with its resource group -- run 2 found it,
  with run 1's approvers still on it, on a resource group created again under the same name -- so
  the prerequisite script's `-Teardown` restores it to its defaults itself, through the module's own
  ARM transport, BEFORE it deletes the resource group, and reads it again (T.4, T.5).
- **The approval fields of an Azure policy in `Get-OERInventory`**, and the ARM whole-list approver
  semantics of `Set-OERRoleManagementPolicy`. Not changed by this branch.
- **`PimPolicyNotFound` from `Get-`/`Set-OERGroupPimPolicy`.** Microsoft Graph lists policies even for
  a group never used with PIM for Groups (6.1), so the only group without a listed policy is one
  created moments ago, which check 5 drives through the apply engine's wait instead. Unit-pinned in
  the `Get-OERGroupPimPolicy` and `Set-OERGroupPimPolicy` suites.

---

## Setup, once

**You need:**

- A **test tenant** -- never a customer tenant -- with Microsoft Entra ID P2 or ID Governance
  licensing (PIM for Groups), its tenant id, one verified domain, and one **test subscription**. A
  Tenant Profile alias for it (`Get-OERConfiguration`) is optional: every sign-in names the tenant id,
  and a profile that exists on the machine running this file must name that same tenant and the
  commercial cloud, or nothing runs.
- The **dedicated certificate identity** `oer-live-cc` ([README.md](README.md), first paragraph):
  an app whose only credential is a non-exportable certificate in `Cert:\CurrentUser\My`, with the
  Microsoft Graph application permissions and the Owner role on the test subscription that the
  operator's identity script grants. Every sign-in below is app-only, as that identity -- never
  interactive, never a device code, never a cached context and never a person's account. **The
  operator enables it for the run and disables it right after**; a sign-in answering
  "application is disabled" means it was not enabled: stop there. Its application permissions need
  no role activation. A missing permission shows up as `Authorization_RequestDenied` or a 403 on the
  app path: stop and name it -- never go around it with another sign-in.
- For check 6.2 only: the second app `oer-live-cc-noperm` -- the same certificate, no API permission
  and no role.
- The prerequisite script `Initialize-OerS62Prereq.ps1`. It is kept OUTSIDE this repository and is
  never committed; it signs in as the certificate identity, and never runs in CI.
- PowerShell 7 and a clone of this repository on this branch.

**Variables, build and module path.** Paste into one PowerShell 7 window and keep that window for
the whole file.

```powershell
$Repo        = '<your-clone-of-Omnicit.EntraRBAC>'   # the clone whose origin is github.com/Omnicit/Omnicit.EntraRBAC
$Prereq      = '<path-to-Initialize-OerS62Prereq.ps1>'
$Alias       = '<your-test-tenant-alias>'
$OrgName     = '<your-test-tenant-display-name>'   # the organization display name, exactly as Graph reports it
$SubId       = '<your-test-subscription-id>'   # the subscription where the certificate identity is Owner
$Domain      = '<your-verified-domain>'
$TenantId    = '<your-test-tenant-id>'
$AppId       = '<oer-live-cc-application-id>'
$NoPermAppId = '<oer-live-cc-noperm-application-id>'
$Thumbprint  = '<certificate-thumbprint>'   # in Cert:\CurrentUser\My; never exported, its key never read
$Prefix      = 'oer-s62'
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
sign-in. It signs in three times, every time app-only as the certificate identity: `Connect-OER`
first, only to identify the tenant and read the subscription; then Microsoft Graph for Phase 1
(disconnecting first: `Connect-OER` leaves its raw access token in the Graph SDK's process cache,
which a later `Connect-MgGraph` would otherwise try to read as an MSAL cache); then `Connect-OER`
again for Phase 2. After EVERY sign-in it checks the identity and prints it as True/False only --
`identity check: session app id is oer-live-cc: True` and `identity check: tenant is the test
tenant: True` -- and a `False` stops it before anything is written. Before its first write it also
identifies the tenant positively: it reads the signed-in organization and refuses to go on --
nothing written -- unless the organization's display name equals `-ExpectedTenantDisplayName`
EXACTLY, `-UserDomain` is one of its verified domains, and `-TenantId` is the organization's id;
a Tenant Profile for the alias, when one exists on the machine, must name the same tenant. It then reads the subscription through the module and stops unless exactly one
subscription with that id and a display name comes back. Only then would it ask once for
confirmation; with `-Unattended` -- a run with no operator at the keyboard -- it says instead that
the question is not asked, since both checks passed (an operator at the keyboard drops
`-Unattended` and is asked). Every later sign-in must land in that same organization too. It tags
the resource group it creates `purpose = oer-s62-live-verification`, and its teardown deletes the
resource group only while that tag is still there. It ends with a summary of names and REAL object
ids -- redact those before pasting (check 0.2). It is idempotent: a second run creates nothing that
exists and only fills in what is missing. Read the `-WhatIf` plan first: every target must carry
the prefix `oer-s62`.

```powershell
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -WhatIf
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -Unattended
```

What it creates, all named with the prefix: two DISABLED users `oer-s62-approver` and
`oer-s62-eligible` on your domain (display names `OER S62 Approver` and `OER S62 Eligible`, random
passwords never printed); the security group `oer-s62-approvers` with the approver user as its only
member; the security group `oer-s62-pim` with no members, onboarded to PIM for Groups by a 30-day
member eligibility for the eligible user (Graph lists a group's member and owner policies before it
is onboarded too, but their ids change when it is -- Microsoft Graph documentation, "Onboarding
groups to PIM for Groups" -- so 1.1 records them after the prerequisite script has run); and the
resource group `oer-s62-rg`, with nothing assigned at it, whose Reader role
management policy is this file's Azure test policy. That policy must start at its defaults --
approval off, no approver -- and the script reads it after creating or finding the resource group:
a resource group deleted and created again under the same name gets its Reader policy back as it
was left, so an earlier run's leftovers are reported approver by approver and, with `-Unattended`
on the test's own resource group, restored at once (an operator at the keyboard is asked). A read of
a group the script has just created is retried on a 404, which Graph answers for a few seconds after
a create. It refuses to run while a user
`oer-s62-nobody@<your-verified-domain>` exists (check 2.1 relies on that name resolving to nothing),
and warns while a group `oer-s62-new` exists (check 5 must create it).

**Sign in, and define the helpers.**

```powershell
Import-Module Omnicit.EntraRBAC -Force
$ErrorActionPreference = 'Continue'   # module code reads the GLOBAL preference; Stop would end a run at its first Failed row
# App-only, as the certificate identity. The certificate's private key is used, never read out.
$null = Connect-OER -TenantId $TenantId -ClientId $AppId -Certificate (Get-Item -LiteralPath "Cert:\CurrentUser\My\$Thumbprint") -IncludeARM -ErrorAction Stop
# The identity check, BEFORE anything else: printed as True/False, never as the ids. The client and
# tenant ids come from the claims of the token Connect-OER obtained; the service principal's display
# name is read so a client id of some other app cannot pass.
$S62Context = Get-MgContext
try {
    $S62Sp = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop -Uri "v1.0/servicePrincipals(appId='$AppId')?`$select=displayName"
} catch {
    Write-Host "--- reading the session's own service principal FAILED: $($PSItem.Exception.Message)"
    $global:Error.Clear()
}
$S62AppOk    = ([string]$S62Context.ClientId -eq $AppId) -and ([string]$S62Sp.displayName -ceq 'oer-live-cc')
$S62TenantOk = ([string]$S62Context.TenantId -eq $TenantId)
Write-Host "identity check: session app id is oer-live-cc: $S62AppOk"
Write-Host "identity check: tenant is the test tenant: $S62TenantOk"
if (-not ($S62AppOk -and $S62TenantOk)) { throw 'The identity check failed: nothing below may run.' }

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

**The documents, and the script check 6.2 runs in a process of its own.** Paste this block as it
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

$Docs.PimDropGroup = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "groups": [
    {
      "displayName": "$PimName",
      "members": null,
      "pimPolicy": {
        "member": { "requireApproval": true, "approvers": { "users": [] } },
        "owner":  { "requireApproval": true, "approvers": { "groups": [] } }
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
# Check 6.2 -- runs in a process of its own, signed in app-only as oer-live-cc-noperm: the same
# certificate as oer-live-cc, and no API permission at all. Written by the checklist; its inputs come
# from 6.2-input.json beside it. An app-only session has no v1.0/me: the session's own ids, from the
# claims of the token it obtained, identify it, printed as True/False only.
$ErrorActionPreference = 'Continue'
$In = Get-Content -Path (Join-Path $PSScriptRoot '6.2-input.json') -Raw | ConvertFrom-Json
$env:PSModulePath = $In.PSModulePathPrefix + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module Omnicit.EntraRBAC -Force
$null = Connect-OER -TenantId $In.TenantId -ClientId $In.NoPermAppId -Certificate (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($In.Thumbprint)") -ErrorAction Stop
$Ctx = Get-MgContext
Write-Host "identity check: session app id is oer-live-cc-noperm: $([string]$Ctx.ClientId -eq $In.NoPermAppId)"
Write-Host "identity check: tenant is the test tenant: $([string]$Ctx.TenantId -eq $In.TenantId)"
Write-Host "identity check: the token carries application permissions: $(@($Ctx.Scopes | Where-Object { $_ }).Count)"
# -WhatIf: the policy-assignment read happens BEFORE ShouldProcess, so a refused read takes the same
# PimPolicyReadFailed path, and an identity that turns out to have write rights still writes nothing.
# The group is named by its object id, which the module passes through without a Graph read -- this
# identity could not read the group by name, and the check is about the policy-assignment read.
$Result = @(Set-OERGroupPimPolicy -Group $In.PimId -ActivationMaxHours 2 -WhatIf -ErrorAction SilentlyContinue -ErrorVariable SetError)
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
Write-Host 'Done. Copy the lines above into check 6.2.'
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
3.4 and 3.7 leave). Sections 4, 5 and 6 at any time after 1; section 7 at any time (offline). Teardown last.
If the window is closed part-way, paste the Setup blocks again (variables, sign-in and helpers,
documents), re-run 0.3, and restore the policy ids with
`$PolicyIdMember = (Get-S62Baseline).member.PolicyId; $PolicyIdOwner = (Get-S62Baseline).owner.PolicyId`.

---

### 0. Preparation

- [x] **0.1 The session runs THIS branch's build.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The main clone was on
  `feat/pim-group-approval` at `3c35a2e` and built from it; the session loaded that build, both
  private functions exist, the three parameters are present, and the last line is `True`.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  docs: name the test tenant by id in the approval checklist, a Tenant Profile optional
  docs: run the approval checklist as the dedicated certificate identity
  docs: allow operator-enabled live runs as a dedicated certificate identity
  fix: tell a new group to declare an eligibility only when it declares none
  docs: drop the false "unset" half of the inventory approver help
  test: pin that a document can empty one approver side
  docs: align the live checklist with the beta approver shape and the new wait
  docs: name the wrong-policy defect and its remedy in the release note
  fix: correct the approval wording and skip whitespace approvers
  fix: ask whether a new group's PIM policy is listed instead of retrying the read
  test: prove ApproverNotFound reaches the caller and a users-only diff binds no group side
  fix: send PIM for Groups approvers in the Graph beta shape
  docs: release note for approval in PIM for Groups
  docs: live-verification checklist for approval in PIM for Groups
  docs: correct the pimPolicy field names and add approval to the inventory README
  test: prove PimPolicyNotFound actually reaches the caller, not just the result row
  fix: resolve the requested PIM policy only, and tell a missing policy from a refused read
  feat: warn about unknown keys in groups and pimPolicy blocks
  feat: approval fields in the group pimPolicy document
  feat: read, diff and apply approval in group pimPolicy
  fix: carry other-kind live approvers when an approver side is bound
  feat: approval rule and approver parameters for PIM for Groups policies
  feat: resolve declared approvers to object ids before the approval diff
  docs: record the teardown of the withheld-prune live verification
  Omnicit.EntraRBAC 1.0.2 from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2
  Name                         CommandType
  ----                         -----------
  ConvertFrom-OERGraphApprover    Function
  Resolve-OERDeclaredApprover     Function
  RequireApproval
  ApproverUser
  ApproverGroup
  True
  ```

- [x] **0.2 The prerequisite script ran and every test object exists.** Paste its summary table, redacted.

  **Expect:** after EACH of its three sign-ins the run printed the two identity lines,
  `... identity check: session app id is oer-live-cc: True` and
  `... identity check: tenant is the test tenant: True`. Before any write it printed
  `Identified the test tenant: organization '<your-test-tenant-display-name>', tenant id <id>, verified domain <your-verified-domain>.`
  and `Identified the test subscription: '<your-test-subscription-name>' (<your-test-subscription-id>).`,
  then `Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.`
  (an operator at the keyboard, without `-Unattended`, is asked once instead, the question naming
  that organization, its tenant id, and the subscription's display name and id), and later printed
  `Phase 1 is signed in to the confirmed test tenant ...` and
  `Phase 2 (Connect-OER) is signed in to the confirmed test tenant ...`. After the resource group
  line: `Setup: Reader policy at oer-s62-rg: approval required False, approvers 0; at its defaults
  (approval off, no approver): True`. If it printed `False` instead, with one `approver on it:` line
  per approver left from an earlier run, the next lines are a warning naming the leftovers,
  `Restored the Reader role management policy at resource group 'oer-s62-rg' to its defaults.` and
  the read again, ending `True` -- record every line. A read of a group created moments ago may print
  `... failed (attempt n of 6, likely replication delay): ... 404 ...` before it succeeds. No warning about
  `oer-s62-new`, and none about the `purpose` tag of `oer-s62-rg`. The run ends with `Done.` and no
  error; the summary has one row each for the two
  users, the groups `oer-s62-approvers` and `oer-s62-pim` and the resource group `oer-s62-rg`, one
  `group member` row (`oer-s62-approvers <- <ApproverUpn>`) and one `PIM eligibility (member, ends ...)`
  row (`oer-s62-pim <- <EligibleUpn>`, about 30 days out). No row reads `(none -- not created)`.
  **Failure looks like:** a `(none -- not created)` row, or the script stopped on an error -- fix the
  cause and re-run the script before 0.3. A `Refusing to run: ...` line from the tenant
  identification means nothing was written: check `$OrgName` (exact, case-sensitive), `$Domain`,
  `$TenantId` and any Tenant Profile for the alias before trying again -- never weaken the check. A warning that `oer-s62-new`
  exists means a previous run was not torn down: run the Teardown's T.4 and T.5 first. A warning
  that `oer-s62-rg` exists without the `purpose` tag `oer-s62-live-verification` means the resource
  group was not created by the script: find out whose it is before any check writes to its Reader
  policy.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Its `-WhatIf` plan ran
  first and named only `oer-s62` targets. The users, the groups, the membership and the eligibility
  already existed from an earlier run of this same script -- checked read-only before anything was
  written (their creation times, the script's own descriptions and display names, no owners, the
  approver as the only member) -- so this run created only `oer-s62-rg`, tagged. Every identity line
  `True`; the tenant and the subscription were identified before the first write.

  ```text
  Tenant Profile for the alias on this machine: False
  [oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
  [oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s62] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
  [oer-s62] Tenant identification (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s62] Tenant identification (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s62] Tenant identification (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
  [oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
  [oer-s62] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
  [oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s62] Phase 1 identity check: tenant is the test tenant: True
  [oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
  [oer-s62] User person1@example.com exists.
  [oer-s62] User person2@example.com exists.
  [oer-s62] Group oer-s62-approvers exists.
  [oer-s62] Group oer-s62-pim exists.
  [oer-s62] person1@example.com is already a member of oer-s62-approvers.
  [oer-s62] Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s62] Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s62] Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s62] Phase 2 (Connect-OER) is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
  [oer-s62] person2@example.com is already eligible (member) on oer-s62-pim.
  [oer-s62] Created resource group oer-s62-rg in swedencentral, tagged purpose = oer-s62-live-verification.
  [oer-s62] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
  Kind                                               Name                                                          Id
  ----                                               ----                                                          --
  user                                               person1@example.com                      00000000-0000-0000-0000-000000000001
  user                                               person2@example.com                      00000000-0000-0000-0000-000000000002
  group                                              oer-s62-approvers                                             00000000-0000-0000-0000-000000000003
  group                                              oer-s62-pim                                                   00000000-0000-0000-0000-000000000004
  resource group                                     oer-s62-rg                                                    /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg
  group member                                       oer-s62-approvers <- person1@example.com 00000000-0000-0000-0000-000000000001
  PIM eligibility (member, ends 10/25/2026 08:55:47) oer-s62-pim <- person2@example.com       00000000-0000-0000-0000-000000000004_member_00000000-0000-0000-0000-000000000002
  [oer-s62] Done.
  ```

- [x] **0.3 Record the object ids every later check compares against.** Read-only.

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  PrincipalId                          UserPrincipalName
  -----------                          -----------------
  00000000-0000-0000-0000-000000000001 person1@example.com
  PrincipalId                          AccessType StartDateTime       EndDateTime
  -----------                          ---------- -------------       -----------
  00000000-0000-0000-0000-000000000002 member     2026-09-25 08:55:47 2026-10-25 08:55:47
  0
  0
  True
  True
  True
  True
  (harness) state saved for later processes
  ```

---

### 1. Baseline -- the original state of every policy this file touches

Nothing below this section may run before it: the Teardown restores exactly what 1.1 and 1.2 save.

- [x] **1.1 The member and owner policies of `oer-s62-pim`, through the module and raw from Graph.**

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
  **Failure looks like:** `PimPolicyNotFound` for either access type (Graph does not list the policy:
  re-run the prerequisite script), the same policy id twice, or approvers already present (record
  them; the Teardown restores them, and 2.1's first line then prints a `What if:` line instead of
  `ApproverRequired`).
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Both policies:
  `ActivationMaxHours` 8, approval off, no approver; raw: `isApprovalRequired = False`,
  `SingleStage`, one stage, a one-day timeout, approver justification on, no primary approver. The
  two policy ids differ.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === member: PolicyId Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005, ActivationMaxHours 8, RequireApproval False, approvers 0
  --- 1.1-member-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 0
  === owner: PolicyId Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006, ActivationMaxHours 8, RequireApproval False, approvers 0
  --- 1.1-owner-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 0
  True
  ```

- [x] **1.2 The Reader role management policy at `oer-s62-rg`, and the baseline file.**

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
  -- the defaults, which the prerequisite script has checked (0.2). The baseline file holds `member`,
  `owner` and `arm`, each with its `PolicyId`, `RequireApproval` and `Approvers`.
  **Failure looks like:** a read error (the ARM token or the Owner role is missing -- see Setup), or
  approval on or an approver present: the prerequisite script's check did not run or its restore
  was declined -- record it, and run the script again (with `-Unattended` it restores the leftovers)
  before any check writes to the policy.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The Reader policy at
  `oer-s62-rg`: approval off, no approver. The baseline file holds member, owner and arm. (Same
  process as 1.1.)

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  PolicyId           : /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000007
  Scope              : /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg
  RoleName           : Reader
  ActivationMaxHours : 8
  RequireApproval    : False
  {
    "member": {
      "PolicyId": "Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005",
      "ActivationMaxHours": 8,
      "RequireApproval": false,
      "Approvers": []
    },
    "owner": {
      "PolicyId": "Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006",
      "ActivationMaxHours": 8,
      "RequireApproval": false,
      "Approvers": []
    },
    "arm": {
      "PolicyId": "/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000007",
      "RequireApproval": false,
      "Approvers": []
    }
  }
  ```

---

### 2. `Set-OERGroupPimPolicy` -- approval on the member and the owner policy

- [x] **2.1 The two approver guards refuse before anything is sent.** `-WhatIf` only: a guard that failed would print a `What if:` line here, never a write.

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. No `What if:` line and no
  object; exactly one `ApproverRequired` and one `ApproverNotFound`, with the expected texts.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- errors published by Set-OERGroupPimPolicy: 1 (other records collected, not shown: 0)
      ERROR [ApproverRequired,Set-OERGroupPimPolicy]: Approval cannot be required with no approver: PIM policy 'Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005' has none on its live approval rule and none was supplied. Pass -ApproverUser or -ApproverGroup.
  --- errors published by Set-OERGroupPimPolicy: 1 (other records collected, not shown: 6)
      ERROR [ApproverNotFound,Set-OERGroupPimPolicy]: User 'person3@example.com' was not found.
  ```

- [x] **2.2 The plan: one rule per access type.**

  ```powershell
  foreach ($T in 'member', 'owner') {
      Set-OERGroupPimPolicy -Group $PimName -AccessType $T -RequireApproval $true -ApproverUser $ApproverUpn -ApproverGroup $ApproversName -WhatIf
  }
  ```

  **Expect:** exactly two lines, and no object and no error:
  `What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy <PolicyIdMember>".`
  then the same for `<PolicyIdOwner>`.
  **Failure looks like:** any other rule id in the plan, or a target policy id that is not one of 1.1's.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Exactly the two lines,
  member then owner, on 1.1's policy ids. (A `What if:` line is written to the console by PowerShell
  itself, so in every block of this file it stands BEFORE the check's other output, not in its
  place.)

  ```text
  What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005".
  What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006".
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  ```

- [x] **2.3 Set approval, with the approver named by UPN and the group by display name.**

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
  for the live run (the module sends neither). If Graph refuses the rule with a message naming `id`,
  `userId` or `groupId`, record the exact error: the module sends each approver in the beta type
  model (`@odata.type`, `id`, `isBackup` -- all that beta's `singleUser` and `groupMembers` declare),
  and the fix is the v1.0 shape (`userId`/`groupId`), one line in `New-OERPimRuleSet`. If it names
  the approver as invalid or disabled, the prerequisite script's disabled approver account is the
  cause: record it, enable `oer-s62-approver` by hand, re-run 2.3 and record both runs.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. No 400: Graph accepted
  the beta approver shape (`@odata.type`, `id`, `isBackup`) on both policies. No warning, no error;
  both objects `Applied` `True` with `FailedRules` `{}`, and the approvers as object ids.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
  --- member warnings: 0
  --- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
  --- owner warnings: 0
  GroupId         : 00000000-0000-0000-0000-000000000004
  PolicyId        : Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005
  AccessType      : member
  RequireApproval : True
  ApproverUser    : {00000000-0000-0000-0000-000000000001}
  ApproverGroup   : {00000000-0000-0000-0000-000000000003}
  Applied         : True
  FailedRules     : {}
  GroupId         : 00000000-0000-0000-0000-000000000004
  PolicyId        : Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006
  AccessType      : owner
  RequireApproval : True
  ApproverUser    : {00000000-0000-0000-0000-000000000001}
  ApproverGroup   : {00000000-0000-0000-0000-000000000003}
  Applied         : True
  FailedRules     : {}
  ```

- [x] **2.4 Read back INDEPENDENTLY, raw from Graph beta, per policy id.**

  ```powershell
  Show-S62RawApproval -PolicyId $PolicyIdMember -Label '2.4-member-raw'
  Show-S62RawApproval -PolicyId $PolicyIdOwner -Label '2.4-owner-raw'
  ```

  **Expect:** for EACH of the two policies: `isApprovalRequired = True`, `approvalMode = SingleStage`,
  `stages = 1`, and exactly two primary approvers -- one `#microsoft.graph.singleUser` whose `id` is
  `<IdApprover>`, one `#microsoft.graph.groupMembers` whose `id` is `<IdApprovers>`, with `userId`
  and `groupId` empty on both: the beta read-back shows `id` for both approvers, the same beta shape
  the module sent. **Record which columns Graph filled for each approver**, `description` included.
  The stage timeout and approver justification are 1.1's values where 1.1 had a stage, and `1` and
  `True` where it had none.
  **Failure looks like:** `isApprovalRequired = False`, a missing approver, a third approver, or a
  policy that does not carry what 2.3 reported. An approver that comes back with `userId` or
  `groupId` and no `id` is not a failure of the module (its reader falls back either way), but it
  contradicts the beta premise both the read and the PATCH rest on: record it exactly.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Both policies:
  `isApprovalRequired = True`, `SingleStage`, one stage, exactly two primary approvers, `id` filled
  and `userId`/`groupId` empty on both -- the beta shape comes back as it was sent. Graph filled
  `description` itself, with the user's and the group's display name. Timeout one day and approver
  justification on, as in 1.1.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 2.4-member-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
  odataType                     id                                   userId groupId description
  ---------                     --                                   ------ ------- -----------
  #microsoft.graph.singleUser   00000000-0000-0000-0000-000000000001                OER S62 Approver
  #microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000003                oer-s62-approvers
  --- 2.4-owner-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
  odataType                     id                                   userId groupId description
  ---------                     --                                   ------ ------- -----------
  #microsoft.graph.singleUser   00000000-0000-0000-0000-000000000001                OER S62 Approver
  #microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000003                oer-s62-approvers
  ```

- [x] **2.5 The module reads the same approvers back, with an id for the group.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Two rows per policy,
  `Group` and `User`, with 2.3's ids; no empty `Id` or `UserType`.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- member: PolicyId Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005, RequireApproval True
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000003 Group    oer-s62-approvers
  00000000-0000-0000-0000-000000000001 User     OER S62 Approver
  --- owner: PolicyId Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006, RequireApproval True
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000003 Group    oer-s62-approvers
  00000000-0000-0000-0000-000000000001 User     OER S62 Approver
  ```

---

### 3. The apply document -- group `pimPolicy` approval converges

Document `$Docs.PimApproval`: the group `oer-s62-pim` with `"members": null` and a nested
`pimPolicy` whose `member` and `owner` blocks both declare `"requireApproval": true` and
`"approvers": { "users": [ "<ApproverUpn>" ], "groups": [ "oer-s62-approvers" ] }` -- a UPN and a
display name, never an id.

- [x] **3.1 The plan: nothing to change after 2.3.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.1 -- raw/s62/3.1.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=3
  ```

- [x] **3.2 Run 1 and run 2, applied: both `Unchanged` -- the beta `id` proof.**

  ```powershell
  Invoke-S62Check -Id '3.2a' -Json $Docs.PimApproval -Include Groups -Apply
  Invoke-S62Check -Id '3.2b' -Json $Docs.PimApproval -Include Groups -Apply
  ```

  **Expect:** each run exactly as 3.1: three `Unchanged` rows, no warning, no error.
  **Failure looks like:** an `Updated` row with `pimPolicy (member) set: approvers(...)` on either
  run -- the diff never converges.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Both runs: three
  `Unchanged` rows, no warning, no error -- the diff reads the beta `id` of both approver kinds.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.2a -- raw/s62/3.2a.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=3
  === 3.2b -- raw/s62/3.2b.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=3
  ```

Document `$Docs.PimDropUser`: the same, except that the `member` block declares only
`"approvers": { "users": [] }` -- the user side declared EMPTY, the group side not declared at all.
The `owner` block is unchanged.

- [x] **3.3 The plan for dropping the user approver from the member policy.**

  ```powershell
  Invoke-S62Check -Id '3.3' -Json $Docs.PimDropUser -Include Groups
  ```

  **Expect:** `Valid = True`, `0` findings. One line
  `What if: Performing the operation "Set PIM policy (member): approvers(users=[])" on target "oer-s62-pim".`
  Exactly three results: `Unchanged` `group properties match`; `Skipped`
  `would set pimPolicy (member): approvers(users=[])`; `Unchanged` `pimPolicy (owner) already matches`.
  **Failure looks like:** `groups=[...]` inside the member change -- the diff would send the side the
  document did not declare; or an owner change.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  What if: Performing the operation "Set PIM policy (member): approvers(users=[])" on target "oer-s62-pim".
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3 -- raw/s62/3.3.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Skipped
  Detail  : would set pimPolicy (member): approvers(users=[])
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Skipped=1, Unchanged=2
  ```

- [x] **3.4 Apply it: the member policy loses the user, and the undeclared group side stays.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The member policy keeps
  exactly the group approver, carried from the live rule; the owner policy is unchanged with two;
  the raw member read has one `groupMembers` approver.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.4 -- raw/s62/3.4.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Updated
  Detail  : pimPolicy (member) set: approvers(users=[])
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=2, Updated=1
  --- member: RequireApproval True, approvers 1
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000003 Group    oer-s62-approvers
  --- owner: RequireApproval True, approvers 2
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000003 Group    oer-s62-approvers
  00000000-0000-0000-0000-000000000001 User     OER S62 Approver
  --- 3.4-member-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 1
  odataType                     id                                   userId groupId description
  ---------                     --                                   ------ ------- -----------
  #microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000003                oer-s62-approvers
  ```

- [x] **3.5 The changed document converges.**

  ```powershell
  Invoke-S62Check -Id '3.5' -Json $Docs.PimDropUser -Include Groups -Apply
  ```

  **Expect:** three `Unchanged` rows (`group properties match`, `pimPolicy (member) already matches`,
  `pimPolicy (owner) already matches`), no warning, no error.
  **Failure looks like:** `Updated` for the member policy again.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.5 -- raw/s62/3.5.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=3
  ```

Document `$Docs.PimDropGroup`: the member block as in `$Docs.PimDropUser` (already applied), and an
`owner` block that declares only `"approvers": { "groups": [] }` -- the GROUP side declared empty, the
user side not declared. The owner policy holds `<IdApprover>` and `<IdApprovers>` since 2.3. This is
the live counterpart of the unit pin "test: pin that a document can empty one approver side".

- [x] **3.6 The plan for emptying the owner policy's group side.**

  ```powershell
  Invoke-S62Check -Id '3.6' -Json $Docs.PimDropGroup -Include Groups
  ```

  **Expect:** `Valid = True`, `0` findings. One line
  `What if: Performing the operation "Set PIM policy (owner): approvers(groups=[])" on target "oer-s62-pim".`
  Exactly three results: `Unchanged` `group properties match`; `Unchanged`
  `pimPolicy (member) already matches`; `Skipped` `would set pimPolicy (owner): approvers(groups=[])`.
  **Failure looks like:** `users=[...]` inside the owner change -- the diff would send the side the
  document did not declare; or no owner change at all -- the empty side was read as undeclared.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  What if: Performing the operation "Set PIM policy (owner): approvers(groups=[])" on target "oer-s62-pim".
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.6 -- raw/s62/3.6.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Skipped
  Detail  : would set pimPolicy (owner): approvers(groups=[])
  --- action counts: Skipped=1, Unchanged=2
  ```

- [x] **3.7 Apply it: the owner policy loses the group, and the live user stays.**

  ```powershell
  Invoke-S62Check -Id '3.7' -Json $Docs.PimDropGroup -Include Groups -Apply
  $P37 = Get-OERGroupPimPolicy -Group $PimName -AccessType owner -ErrorAction Stop
  Write-Host ('--- owner: RequireApproval {0}, approvers {1}' -f $P37.RequireApproval, @($P37.Approvers).Count)
  $P37.Approvers | Sort-Object UserType | Format-Table Id, UserType, DisplayName -AutoSize | Out-Host
  Show-S62RawApproval -PolicyId $PolicyIdOwner -Label '3.7-owner-raw'
  ```

  **Expect:** no warning, no error; three results: `Unchanged` `group properties match`; `Unchanged`
  `pimPolicy (member) already matches`; `Updated` `pimPolicy (owner) set: approvers(groups=[])`. The
  owner policy: `RequireApproval` `True` with exactly ONE approver, `User` `<IdApprover>` -- carried
  from the live rule although the document did not declare the user side. The raw owner read:
  `isApprovalRequired = True`, `primary approvers: 1`, the `#microsoft.graph.singleUser` approver
  `<IdApprover>` and no `#microsoft.graph.groupMembers` row.
  **Failure looks like:** the owner row `Failed` with `ApproverRequired` in its detail, or `0`
  approvers left -- the undeclared user side was sent empty instead of carried; or the group still
  there -- the empty group side never reached the PATCH.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The live counterpart of
  the unit pin holds: the owner policy keeps exactly the user approver although the document did not
  declare the user side, and the group is gone; the raw owner read has one `singleUser` approver and
  no `groupMembers` row.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.7 -- raw/s62/3.7.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Updated
  Detail  : pimPolicy (owner) set: approvers(groups=[])
  --- action counts: Unchanged=2, Updated=1
  --- owner: RequireApproval True, approvers 1
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000001 User     OER S62 Approver
  --- 3.7-owner-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 1
  odataType                   id                                   userId groupId description
  ---------                   --                                   ------ ------- -----------
  #microsoft.graph.singleUser 00000000-0000-0000-0000-000000000001                OER S62 Approver
  ```

- [x] **3.8 That document converges too.**

  ```powershell
  Invoke-S62Check -Id '3.8' -Json $Docs.PimDropGroup -Include Groups -Apply
  ```

  **Expect:** three `Unchanged` rows (`group properties match`, `pimPolicy (member) already matches`,
  `pimPolicy (owner) already matches`), no warning, no error.
  **Failure looks like:** `Updated` for the owner policy again.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.8 -- raw/s62/3.8.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=3
  ```

---

### 4. The apply document -- a `roleManagementPolicies[]` approver named by UPN and group name converges

Document `$Docs.ArmApproval`: one `roleManagementPolicies` item, scope `<RgScope>`, role `Reader`,
`"requireApproval": true` and `"approvers": { "users": [ "<ApproverUpn>" ], "groups": [ "oer-s62-approvers" ] }`.

- [x] **4.1 The plan.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  What if: Performing the operation "Update role management policy" on target "Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg".
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.1 -- raw/s62/4.1.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include RoleManagementPolicies -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : roleManagementPolicies
  Item    : Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg
  Action  : Skipped
  Detail  : would update role management policy for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg'
  --- action counts: Skipped=1
  ```

- [x] **4.2 Run 1, applied, and read back.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. `Updated` with object ids
  in the change list; the read-back has approval on and exactly the two approvers by id.
  Observation: Azure's read-back leaves `DisplayName` empty for both approvers.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.2 -- raw/s62/4.2.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include RoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : roleManagementPolicies
  Item    : Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg
  Action  : Updated
  Detail  : updated role management policy for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg' (requireApproval=True, approvers(users=[00000000-0000-0000-0000-000000000001],groups=[00000000-0000-0000-0000-000000000003]
            ))
  --- action counts: Updated=1
  PolicyId        : /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000007
  RequireApproval : True
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000003 Group
  00000000-0000-0000-0000-000000000001 User
  ```

- [x] **4.3 Run 2: `Unchanged`.**

  ```powershell
  Invoke-S62Check -Id '4.3' -Json $Docs.ArmApproval -Include RoleManagementPolicies -Apply
  ```

  **Expect:** one result, `Unchanged`, `policy already matches for 'Reader' at '<RgScope>'`; no
  warning, no error.
  **Failure looks like:** `Updated` again -- a declared name was compared with a live id, which is
  what every run did before this branch.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.3 -- raw/s62/4.3.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include RoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : roleManagementPolicies
  Item    : Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg
  Action  : Unchanged
  Detail  : policy already matches for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg'
  --- action counts: Unchanged=1
  ```

---

### 5. A group created in the same run -- each access type gets its own policy

Document `$Docs.NewGroup`: a group `oer-s62-new` that does not exist yet, `"members": null`, one
time-bound eligibility (`<EligibleUpn>`, `"durationDays": 30`, member access), and a
nested `pimPolicy` with DIFFERENT settings per access type: `member` `"activationMaxHours": 2`;
`owner` `"activationMaxHours": 3`, `"requireApproval": true` and the same two approvers as section 3.
Before this branch, an owner lookup that ran before Graph listed the owner policy fell back to the
member policy, and the owner's settings landed there.

- [x] **5.1 The plan.**

  ```powershell
  Invoke-S62Check -Id '5.1' -Json $Docs.NewGroup -Include Groups
  ```

  **Expect:** `Valid = True`, `0` findings; no warning, no error. One line
  `What if: Performing the operation "Create group" on target "oer-s62-new".` and exactly three
  results, all Item `oer-s62-new`, `Skipped`: `would create group oer-s62-new`,
  `would configure eligibility for '<EligibleUpn>' after group is created`,
  `would configure pimPolicy after group is created`.
  **Failure looks like:** any row for an existing `oer-s62-new` (see 0.3).
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  What if: Performing the operation "Create group" on target "oer-s62-new".
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.1 -- raw/s62/5.1.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 3
  Section : groups
  Item    : oer-s62-new
  Action  : Skipped
  Detail  : would create group oer-s62-new
  Section : groups
  Item    : oer-s62-new
  Action  : Skipped
  Detail  : would configure eligibility for 'person2@example.com' after group is created
  Section : groups
  Item    : oer-s62-new
  Action  : Skipped
  Detail  : would configure pimPolicy after group is created
  --- action counts: Skipped=3
  ```

- [ ] **5.2 Apply it, with the verbose stream captured for the retry lines.**

  ```powershell
  Invoke-S62Check -Id '5.2' -Json $Docs.NewGroup -Include Groups -Apply -VerboseLog
  "PimPolicyNotFound records in -ErrorVariable: $(@($S62Error | Where-Object { [string]$_.FullyQualifiedErrorId -like 'PimPolicyNotFound*' }).Count)"
  ```

  **Expect:** in this order, all Item `oer-s62-new`:
  1. `Created` `created group oer-s62-new (<IdNew>)`.
  2. `Updated` `set time-bound member eligibility for '<EligibleUpn>' (30 days): time-bound member eligibility (30 days) is absent`
     -- or `Failed` `failed to add eligibility for '<EligibleUpn>': ResourceNotFound: ...`: the group
     is too new for PIM itself, and the eligibility has no wait. Then carry on with 5.3.
  3. The member policy: `Updated` `pimPolicy (member) set: activationMaxHours=2` -- or `Failed`
     `pimPolicy (member) not applied: Microsoft Graph does not list a PIM-for-groups policy for 'member' access on group 'oer-s62-new', created in this run, within the 30-second wait. A new group's policies can take a while to be listed (replication delay); re-running the same document usually applies them.`
     with a matching `ERROR [PimPolicyNotFound,Invoke-OERStructure]: pimPolicy (member) not applied: ...` line,
     and nothing about eligibility.
  4. The owner policy: `Updated` `pimPolicy (owner) set: activationMaxHours=3; requireApproval=True; approvers(users=[<IdApprover>],groups=[<IdApprovers>])`
     -- or the same `Failed` text and error line for `'owner'` access.

  The wait lines are zero to four
  `Sync-OERStructureGroup: pimPolicy (<member or owner>) of new group 'oer-s62-new' is not listed yet; retry <n> in <s> s.`,
  across BOTH access types together, with the delays `2`, `4`, `8`, `16` in that order and `<n>`
  counting within each access type -- one budget per group item, spent by whichever access type needs
  it first (an owner that finds the budget spent fails at once, with the same
  `within the 30-second wait` text and no retry count). A look that Graph answers with 404 while the
  group is too new for PIM is one of those waits, and the log shows it just before the wait line:
  `[Get-OERPimGroupPolicyId] Microsoft Graph answered 404 ResourceNotFound for the policy assignments of group '<IdNew>'; reporting them as not listed yet.`
  Record every wait line and every 404 line, and whether the path was exercised at all: the waits
  between the first 404 and the first look that lists the policy bound how long the 404 lasted. No
  warning. The last line prints `0` when both policy rows are `Updated`, wait lines or not: the
  handler ASKS whether a policy is listed instead of reading it until it is, and a 404 is declared
  as an answer on that question, so a run that ends `Updated` leaves no `PimPolicyNotFound` and no
  `ResourceNotFound` record in `-ErrorVariable`. Each `... within the 30-second wait ...` row adds
  exactly one -- that row's own record. The first policy update onboards the group, and its policy
  ids change when it does, so the owner's policy id in the log can differ from the member's first
  look; 5.4 reads which policy each access type ended on.
  **Failure looks like:** the owner row `Updated` while 5.4 shows the owner's settings on the member
  policy (the fallback defect); a `PimPolicyNotFound` count above `0` while both policy rows are
  `Updated` (the wait left records behind); a `Failed` row naming `PimPolicyReadFailed` or a 403 (a
  refusal, not replication -- record it, with any verbose line
  `Sync-OERStructureGroup: could not ask whether pimPolicy (...) of new group 'oer-s62-new' is listed (...); reading it directly.`
  from the log; that line naming `ResourceNotFound` means the 404 was not waited on, the defect
  this file's first run found); more than four wait lines, or a delay sequence other than 2, 4, 8,
  16. If the budget runs out while Graph still answers 404, record how many looks it answered 404
  and do not change the budget: that is a decision for the operator.
  **Result:** Run 2 (2026-09-28, at `85d4144`, after the 404-wait fix): FAIL again, differently -- the
  policy was LISTED on the first look and the reads right after it answered 404, so the wait never
  ran; see "Run 2: 5.2" at the end of this file.

  Run 1: FAIL -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The member policy row is
  the failure this check names: `Failed` with `PimPolicyReadFailed` instead of a wait. Row 1
  `Created`. Row 2 `Failed` with `ResourceNotFound` -- the group too new for PIM itself, the case
  where the checklist carries on with 5.3. Row 3, member: the handler's question whether the policy
  is listed got `404 ResourceNotFound`, the verbose log shows `could not ask whether pimPolicy
  (member) ... is listed (ResourceNotFound ...); reading it directly.`, and the direct read got the
  same 404. No wait line at all: the retry was never entered. It was not a refusal but replication
  -- a group PIM does not know yet answers the assignment query with 404 `ResourceNotFound`, not
  with an empty list, so the wait never sees the state it waits for. Row 4, owner: `Updated`;
  seconds later the same query answered, and the owner rule was patched on the policy id Graph
  listed then. After that write Graph lists DIFFERENT ids for both of the new group's policies: PIM
  onboards a group on its first policy update, and the ids change when it does (Microsoft Graph
  documentation, PIM for Groups API overview, "Onboarding groups to PIM for Groups"). A read of the
  id that was patched returns the onboarded owner policy under its new id, and 5.4 shows the owner
  settings on the owner policy and none on the member policy -- so the fallback defect is absent.
  The `PimPolicyNotFound` count is `0`. The follow-up reads below were made read-only, before 5.3.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.2 -- raw/s62/5.2.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false -Verbose
  Invoke-OERStructure: <harness>\_signin.ps1:51:14
  Line |
    51 |      $Out = @(Invoke-OERStructure @Splat 3>&1 4>&1)
       |               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
       | ResourceNotFound: The resource is not found.
  Invoke-OERStructure: <harness>\_signin.ps1:51:14
  Line |
    51 |      $Out = @(Invoke-OERStructure @Splat 3>&1 4>&1)
       |               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
       | Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000008' ('member'
       | access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not
       | the same as the group having none, so nothing was changed.
  --- step-4 retry lines: 0 (all 37 verbose lines are in 5.2-verbose.log)
  --- warnings, in the order written: 0
  --- errors: 49
      ERROR []:
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: NotFound (Not Found).
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: NotFound (Not Found).
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound,Add-OERGroupEligibility]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound,Invoke-OERStructure]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [PimPolicyReadFailed,Get-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000008' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so no policy is reported for it.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [PimPolicyReadFailed,Set-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000008' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.
      ERROR [PimPolicyReadFailed,Invoke-OERStructure]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000008' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.
      ERROR []:
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: NotFound (Not Found).
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: NotFound (Not Found).
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
      ERROR []:
      ERROR [ResourceNotFound,Get-OERGroupPimPolicy]: ResourceNotFound: The resource is not found.
  --- results: 4
  Section : groups
  Item    : oer-s62-new
  Action  : Created
  Detail  : created group oer-s62-new (00000000-0000-0000-0000-000000000008)
  Section : groups
  Item    : oer-s62-new
  Action  : Failed
  Detail  : failed to add eligibility for 'person2@example.com': ResourceNotFound: The resource is not found.
  Section : groups
  Item    : oer-s62-new
  Action  : Failed
  Detail  : pimPolicy (member) update failed: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000008' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which
            is not the same as the group having none, so nothing was changed.
  Section : groups
  Item    : oer-s62-new
  Action  : Updated
  Detail  : pimPolicy (owner) set: activationMaxHours=3; requireApproval=True; approvers(users=[00000000-0000-0000-0000-000000000001],groups=[00000000-0000-0000-0000-000000000003])
  --- action counts: Created=1, Failed=2, Updated=1
  PimPolicyNotFound records in -ErrorVariable: 0
  # 5.2-verbose.log, redacted:
  [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
  [Invoke-OERGraphRequest] GET v1.0/groups?$filter=displayName eq 'oer-s62-new'&$select=id,displayName
  Performing the operation "Create group" on target "oer-s62-new".
  [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
  [Invoke-OERGraphRequest] GET v1.0/groups?$filter=displayName eq 'oer-s62-new'&$select=id,displayName
  [Invoke-OERGraphRequest] POST v1.0/groups
  [Invoke-OERGraphRequest] GET v1.0/users?$filter=userPrincipalName eq 'person2%40example.com'&$select=id,userPrincipalName
  Performing the operation "Add time-bound member eligibility for '00000000-0000-0000-0000-000000000002' (30 days)" on target "oer-s62-new".
  [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
  [Add-OERGroupEligibility] Resolved group to '00000000-0000-0000-0000-000000000008'.
  [Add-OERGroupEligibility] Resolved principal to '00000000-0000-0000-0000-000000000002'.
  [Invoke-OERGraphRequest] POST beta/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000008' and scopeType eq 'Group'
  Sync-OERStructureGroup: could not ask whether pimPolicy (member) of new group 'oer-s62-new' is listed (ResourceNotFound: The resource is not found.); reading it directly.
  [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000008' and scopeType eq 'Group'
  Performing the operation "Set PIM policy (member): activationMaxHours=2" on target "oer-s62-new".
  [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
  [Set-OERGroupPimPolicy] Resolved group to '00000000-0000-0000-0000-000000000008'.
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000008' and scopeType eq 'Group'
  [Invoke-OERGraphRequest] GET v1.0/users?$filter=userPrincipalName eq 'person1%40example.com'&$select=id,userPrincipalName
  [Invoke-OERGraphRequest] GET v1.0/groups?$filter=displayName eq 'oer-s62-approvers'&$select=id,displayName
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000008' and scopeType eq 'Group'
  [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000008' and scopeType eq 'Group'
  [Invoke-OERGraphRequest] Fetching page 1...
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicies/Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009/rules
  [Invoke-OERGraphRequest] Page 1 failed with 0 item(s) already aggregated from earlier pages. PartialValue, NextLink and PageNumber are attached to the thrown error's Exception for a caller that opts in; the call still fails.
  Performing the operation "Set PIM policy (owner): activationMaxHours=3; requireApproval=True; approvers(users=[00000000-0000-0000-0000-000000000001],groups=[00000000-0000-0000-0000-000000000003])" on target "oer-s62-new".
  [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
  [Set-OERGroupPimPolicy] Resolved group to '00000000-0000-0000-0000-000000000008'.
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000008' and scopeType eq 'Group'
  [Set-OERGroupPimPolicy] Resolved PIM policy id: 'Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009'.
  [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicies/Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009/rules/Approval_EndUser_Assignment
  [Invoke-OERGraphRequest] PATCH beta/policies/roleManagementPolicies/Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009/rules/Expiration_EndUser_Assignment
  [Invoke-OERGraphRequest] PATCH beta/policies/roleManagementPolicies/Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009/rules/Approval_EndUser_Assignment
  Invoke-OERStructure complete. 4 record(s): Created=1, Failed=2, Updated=1
  # Follow-up reads, read-only, as oer-live-cc, after 5.2 and before 5.3:
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  new group id: 00000000-0000-0000-0000-000000000008
  roleDefinitionId policyId
  ---------------- --------
  member           Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010
  owner            Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011
  --- policies listed for the new group: 2
  id                                                                              lastModifiedDateTime isOrganizationDefault
  --                                                                              -------------------- ---------------------
  Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010                                      False
  Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011 2026-09-28 09:46:01                  False
  --- assignments listed: 2
  id                                                                                     roleDefinitionId policyId
  --                                                                                     ---------------- --------
  Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010_member member           Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010
  Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011_owner  owner            Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011
  --- Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009: activation maximumDuration PT3H
  --- 5.2-diag-d1a36ecb: policy Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
  odataType                     id                                   userId groupId description
  ---------                     --                                   ------ ------- -----------
  #microsoft.graph.singleUser   00000000-0000-0000-0000-000000000001                OER S62 Approver
  #microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000003                oer-s62-approvers
  --- Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010: activation maximumDuration PT8H
  --- 5.2-diag-144c0642: policy Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 0
  --- Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011: activation maximumDuration PT3H
  --- 5.2-diag-7d2427c6: policy Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
  odataType                     id                                   userId groupId description
  ---------                     --                                   ------ ------- -----------
  #microsoft.graph.singleUser   00000000-0000-0000-0000-000000000001                OER S62 Approver
  #microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000003                oer-s62-approvers
  --- GET Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000009: returned id Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011, lastModifiedDateTime 2026-09-28 09:46:01
  --- GET Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000000: failed: Response status code does not indicate success: BadRequest (Bad Request).
  ```

- [x] **5.3 Only if 5.2 had a `Failed` row: re-run until it applies.** Otherwise write "not needed" as the result.

  ```powershell
  Invoke-S62Check -Id '5.3' -Json $Docs.NewGroup -Include Groups -Apply -VerboseLog
  ```

  **Expect:** `Unchanged` `group properties match`, the eligibility `Unchanged`
  (`eligibility for '<EligibleUpn>' (member) already matches`) or, if it failed in 5.2, `Updated`; and
  `Updated` with 5.2's detail text for each access type that failed there. The group now exists, so no
  retry line appears: a policy still not listed shows as `Failed`
  `pimPolicy (<type>) update failed: Microsoft Graph does not list a PIM-for-groups policy for '<type>' access on group '<IdNew>' yet. ...`
  with an error line whose id starts with `PimPolicyNotFound` (or, while Graph still answers 404 for
  the group, `PimPolicyReadFailed` naming `ResourceNotFound`) -- wait a minute and run this block
  again. Record every run.
  **Failure looks like:** the same `Failed` row after several minutes and runs.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Needed, after 5.2's two
  `Failed` rows; one run was enough: the eligibility `Updated`, the member policy `Updated` on the
  listed member policy, the owner `Unchanged`; no retry line, no warning, no error. Deviation, not
  from this branch: a fifth object, `Action : adminAssign` with no Section, Item or Detail --
  `Add-OERGroupEligibility`'s own output reaching `Invoke-OERStructure`'s results through both of
  its call sites in `Sync-OERStructureGroup`, as on `main` since 1.0.0. T.7 counts it.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.3 -- raw/s62/5.3.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false -Verbose
  --- step-4 retry lines: 0 (all 31 verbose lines are in 5.3-verbose.log)
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 5
  Section : groups
  Item    : oer-s62-new
  Action  : Unchanged
  Detail  : group properties match
  Action : adminAssign
  Section : groups
  Item    : oer-s62-new
  Action  : Updated
  Detail  : set time-bound member eligibility for 'person2@example.com' (30 days): time-bound member eligibility (30 days) is absent
  Section : groups
  Item    : oer-s62-new
  Action  : Updated
  Detail  : pimPolicy (member) set: activationMaxHours=2
  Section : groups
  Item    : oer-s62-new
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: adminAssign=1, Unchanged=2, Updated=2
  ```

- [x] **5.4 Read BOTH new policies back by their policy ids.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Two assignments on two
  different policy ids; member `PT2H`, approval off, no approver; owner `PT3H`, approval on, one
  stage, the two approvers; the module lines agree per access type.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  roleDefinitionId policyId
  ---------------- --------
  member           Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010
  owner            Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011
  --- member: policy Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010, activation maximumDuration PT2H
  --- 5.4-member-raw: policy Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 0
  --- owner: policy Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011, activation maximumDuration PT3H
  --- 5.4-owner-raw: policy Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
  odataType                     id                                   userId groupId description
  ---------                     --                                   ------ ------- -----------
  #microsoft.graph.singleUser   00000000-0000-0000-0000-000000000001                OER S62 Approver
  #microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000003                oer-s62-approvers
  --- member (module): PolicyId Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000010, ActivationMaxHours 2, RequireApproval False, approvers 0
  --- owner (module): PolicyId Group_00000000-0000-0000-0000-000000000008_00000000-0000-0000-0000-000000000011, ActivationMaxHours 3, RequireApproval True, approvers 2
  ```

- [x] **5.5 The new group's document converges.**

  ```powershell
  Invoke-S62Check -Id '5.5' -Json $Docs.NewGroup -Include Groups -Apply
  ```

  **Expect:** exactly four results, all `Unchanged`: `group properties match`,
  `eligibility for '<EligibleUpn>' (member) already matches`, `pimPolicy (member) already matches`,
  `pimPolicy (owner) already matches`. No warning, no error.
  **Failure looks like:** any `Updated` row.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.5 -- raw/s62/5.5.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 4
  Section : groups
  Item    : oer-s62-new
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-new
  Action  : Unchanged
  Detail  : eligibility for 'person2@example.com' (member) already matches
  Section : groups
  Item    : oer-s62-new
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-new
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=4
  ```

---

### 6. A refused policy read is not a missing policy

- [~] **6.1 A group Graph lists no policy for: `PimPolicyNotFound` -- cannot be produced live, so this box is `[~]` by design.** `-WhatIf` only, ALWAYS.

  ```powershell
  Set-OERGroupPimPolicy -Group $ApproversName -ActivationMaxHours 2 -WhatIf -ErrorAction SilentlyContinue -ErrorVariable E61
  Show-S62Error -Record $E61 -Cmdlet Set-OERGroupPimPolicy
  ```

  **Expect:** this check cannot show `PimPolicyNotFound`, and its box stays `[~]`. Microsoft Graph
  lists a member and an owner policy for a group that was never used with PIM for Groups: PIM
  onboards a group automatically on its first policy update or its first eligibility or assignment
  request, that cannot be undone, and the policy ids change when it does (Microsoft Graph
  documentation, PIM for Groups API overview, "Onboarding groups to PIM for Groups"). So no group in
  the tenant is in the state `PimPolicyNotFound` reports, apart from one created moments ago, which
  check 5 covers through the apply engine's wait. The call is kept as the record of that: it prints
  one `What if: Performing the operation "Patch rule Expiration_EndUser_Assignment" on target "PIM policy <a policy of oer-s62-approvers>".`
  line and publishes no error. **Never run it without `-WhatIf`**: the PATCH would onboard
  `oer-s62-approvers` to PIM for Groups. `PimPolicyNotFound` itself is unit-pinned in the
  `Get-OERGroupPimPolicy` and `Set-OERGroupPimPolicy` suites.
  **Failure looks like:** `PimPolicyReadFailed` (a refusal where Graph should have listed the
  policy), or anything written.
  **Result:** Cannot be verified, and therefore we do not know how the module answers a group that
  has no PIM policy: this tenant has no such group to try it on. `oer-s62-approvers` was never used
  with PIM for Groups, yet Graph lists a member and an owner policy assignment for it (neither
  policy ever modified), so `Set-OERGroupPimPolicy` found the member policy and printed a `What if:`
  line instead of `PimPolicyNotFound`. Nothing was written (`-WhatIf`), and the group was not
  onboarded. Microsoft Graph documents that a group cannot be onboarded explicitly and is onboarded
  by its first eligibility, assignment or policy update; this run shows it lists policies before
  that. The owner policy id of this never-onboarded group ends in the same id as the one 5.2 patched
  on the new group before it was onboarded: a template id that groups share until they are onboarded
  (inferred from these two reads). 2026-09-28, as `oer-live-cc`.

  ```text
  What if: Performing the operation "Patch rule Expiration_EndUser_Assignment" on target "PIM policy Group_00000000-0000-0000-0000-000000000003_00000000-0000-0000-0000-000000000012".
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
  # Follow-up read, read-only, as oer-live-cc:
  --- approvers group: assignments listed: 2
  roleDefinitionId policyId
  ---------------- --------
  member           Group_00000000-0000-0000-0000-000000000003_00000000-0000-0000-0000-000000000012
  owner            Group_00000000-0000-0000-0000-000000000003_00000000-0000-0000-0000-000000000009
  --- owner: lastModifiedDateTime []
  --- member: lastModifiedDateTime []
  --- approvers group: PIM eligibility schedules 0, PIM assignment schedules 1
  ```

- [x] **6.2 A refused read, by `oer-live-cc-noperm` in a process of its own: `PimPolicyReadFailed`.**

  A second process keeps this window's sign-in intact: the module keeps one credential per process.
  The script signs in app-only as `oer-live-cc-noperm` -- the same certificate, no API permission --
  and runs `Set-OERGroupPimPolicy` with `-WhatIf`: it reads the policy assignment before it asks
  ShouldProcess, so a refused read reaches `PimPolicyReadFailed` exactly as a real call would, and a
  sign-in that turns out to carry write rights still cannot write. It names the group by its object
  id, which the module passes through without a Graph read.
  This block writes the script and its inputs to the raw folder and runs it.

  ```powershell
  $RefusedReadPath = Join-Path $Raw '6.2-refused-read.ps1'
  [ordered]@{
      TenantId           = $TenantId
      NoPermAppId        = $NoPermAppId
      Thumbprint         = $Thumbprint
      PimId              = $PimId
      PSModulePathPrefix = (Resolve-Path (Join-Path $Repo 'output/module')).Path + [System.IO.Path]::PathSeparator + (Resolve-Path (Join-Path $Repo 'output/RequiredModules')).Path
  } | ConvertTo-Json | Set-Content -Path (Join-Path $Raw '6.2-input.json') -Encoding utf8NoBOM
  Set-Content -Path $RefusedReadPath -Value $RefusedReadScript -Encoding utf8NoBOM
  pwsh -NoProfile -File $RefusedReadPath
  ```

  **Expect:** `identity check: session app id is oer-live-cc-noperm: True`, `identity check: tenant
  is the test tenant: True`, and `the token carries application permissions: 0`. NO `What if:` line:
  a refused read returns before ShouldProcess is asked. `Result objects: 0` (under `-WhatIf` it is `0`
  in every case, so it proves nothing on its own). `Errors published by Set-OERGroupPimPolicy: 1`,
  and that one is
  `ERROR [PimPolicyReadFailed,Set-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '<PimId>' ('member' access): <cause>. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.`
  The raw status line reads `403` (or another refusal status).
  **Failure looks like:** `PimPolicyNotFound` while the raw status is `403` -- a refusal collapsed into
  absence, the defect this branch fixes. `PimPolicyNotFound` with a raw status of `200, 0 assignment(s)`
  is a different finding: Graph HID the policy from this identity instead of refusing, and the module
  cannot tell that apart from absence -- record it as "cannot be verified, and therefore we do not
  know". A `What if: Performing the operation "Patch rule Expiration_EndUser_Assignment" ...` line
  and no published error mean this identity COULD read the policy assignment, so it is not a refused
  identity: nothing was written (`-WhatIf`), 6.3 still confirms it, and 6.2 is `[~]` for want of a
  suitable identity. A `False` identity line, or a sign-in answering "application is disabled", means
  the run is not the one this check describes: stop and report it, never retry with another sign-in.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The second process signed
  in as `oer-live-cc-noperm`: both identity lines `True`, no application permission in the token. No
  `What if:` line; one error, `PimPolicyReadFailed`, carrying Graph's `PermissionScopeNotGranted`;
  raw status 403.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  identity check: session app id is oer-live-cc-noperm: True
  identity check: tenant is the test tenant: True
  identity check: the token carries application permissions: 0
  Result objects: 0
  Errors published by Set-OERGroupPimPolicy: 1
  ERROR [PimPolicyReadFailed,Set-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000004' ('member' access): UnauthorizedAccessException: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleManagementPolicy.Read.AzureADGroup,RoleManagementPolicy.ReadWrite.AzureADGroup.","instanceAnnotations":[]}. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.
  Raw status of the policy-assignment read for this identity: 403
  Done. Copy the lines above into check 6.2.
  ```

- [x] **6.3 Nothing was written by the refused identity.** Back in this window, as `oer-live-cc`.

  ```powershell
  $P63 = Get-OERGroupPimPolicy -Group $PimName -AccessType member -ErrorAction Stop
  '{0} -> {1}' -f (Get-S62Baseline).member.ActivationMaxHours, $P63.ActivationMaxHours
  $P63.ActivationMaxHours -eq (Get-S62Baseline).member.ActivationMaxHours
  ```

  **Expect:** the same value on both sides, and `True` -- 6.2 ran under `-WhatIf`, so nothing it did
  can have written.
  **Failure looks like:** `2` on the right -- the policy changed although 6.2 ran under `-WhatIf`:
  stop and record it.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  8 -> 8
  True
  ```

---

### 7. Unknown keys in `groups[]` items and `pimPolicy` blocks -- offline

Document `$Docs.OldNames`: two groups. `groups[0]` (`oer-s62-pim`) carries an unknown item key
`eligibilities` and a nested `pimPolicy.member` using the OLD name `activationEnabledRules`;
`groups[1]` (`oer-s62-new`) has a flat `pimPolicy` using the old name `activeEnabledRules`. Nothing
is applied: validation only.

- [x] **7.1 Each unknown key is a Warning, and the old names get the did-you-mean hint.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 7.1 -- raw/s62/7.1.json
  --- offline validation: Valid = True, findings = 3
  Section  : groups
  Item     : oer-s62-pim
  Path     : groups[0].eligibilities
  Severity : Warning
  Message  : Unknown key 'eligibilities' at groups[0] is not applied by Invoke-OERStructure and will be ignored.
  Section  : groups
  Item     : oer-s62-pim
  Path     : groups[0].pimPolicy.member.activationEnabledRules
  Severity : Warning
  Message  : Unknown key 'activationEnabledRules' at groups[0].pimPolicy.member is not applied by Invoke-OERStructure and will be ignored. Did you mean 'activationEnablement'?
  Section  : groups
  Item     : oer-s62-new
  Path     : groups[1].pimPolicy.activeEnabledRules
  Severity : Warning
  Message  : Unknown key 'activeEnabledRules' at groups[1].pimPolicy is not applied by Invoke-OERStructure and will be ignored. Did you mean 'activeEnablement'?
  ```

---

### 8. `Get-OERInventory` -- approval round-trips

- [x] **8.1 The inventory of `oer-s62-pim` carries approval, with approvers as object ids.**

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
  `"approvers": { "users": [ "<IdApprover>" ] }` with NO `groups` key (3.7 emptied that side). Every
  approver is an object id -- never a UPN or a display name.
  **Failure looks like:** `requireApproval` missing, `approvers` missing while `requireApproval` is
  true, or an approver written as a name.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. No error; `member`
  declares `{ groups }` only and `owner` `{ users }` only, approval on, object ids.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- errors published by Get-OERInventory: 0 (other records collected, not shown: 0)
  1
  oer-s62-pim
  {
    "member": {
      "activationMaxHours": 8,
      "activationEnablement": [
        "Justification"
      ],
      "allowPermanentEligibility": false,
      "eligibleDurationDays": 365,
      "allowPermanentActive": false,
      "activeDurationDays": 180,
      "activeEnablement": [
        "Justification"
      ],
      "requireApproval": true,
      "approvers": {
        "groups": [
          "00000000-0000-0000-0000-000000000003"
        ]
      }
    },
    "owner": {
      "activationMaxHours": 8,
      "activationEnablement": [
        "Justification"
      ],
      "allowPermanentEligibility": false,
      "eligibleDurationDays": 365,
      "allowPermanentActive": false,
      "activeDurationDays": 180,
      "activeEnablement": [
        "Justification"
      ],
      "requireApproval": true,
      "approvers": {
        "users": [
          "00000000-0000-0000-0000-000000000001"
        ]
      }
    }
  }
  ```

- [x] **8.2 The exported document re-applies as `Unchanged`.**

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Both runs four
  `Unchanged` rows (the group has no owner, so no owner row) and no `What if:` line.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 8.2a -- raw/s62/8.2a.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 4
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : eligibility for 'person2@example.com' (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=4
  === 8.2b -- raw/s62/8.2b.json
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include Groups -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 4
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : group properties match
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : eligibility for 'person2@example.com' (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (member) already matches
  Section : groups
  Item    : oer-s62-pim
  Action  : Unchanged
  Detail  : pimPolicy (owner) already matches
  --- action counts: Unchanged=4
  ```

---

### Teardown

The approval changes are undone FIRST, while the objects still exist, then the prerequisite script
removes everything. Deleting `oer-s62-pim` and `oer-s62-new` removes their PIM-for-Groups policies.
Deleting `oer-s62-rg` does NOT remove its Reader role management policy -- it outlives the resource
group and is found as it was left when the name is used again (run 2) -- so the prerequisite
script's `-Teardown` restores that policy to its defaults, approval off and no approver, BEFORE it
deletes the resource group, and reads it again (T.5).

- [x] **T.1 The restore plan.** `-WhatIf`.

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
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The three targets are
  exactly 1.x's policy ids.

  ```text
  What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005".
  What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006".
  What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "role management policy '/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000007'".
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- member: restoring RequireApproval = False
  --- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
  --- owner: restoring RequireApproval = False
  --- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
  --- arm: restoring RequireApproval = False
  --- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
  ```

- [x] **T.2 Restore.**

  ```powershell
  Restore-S62Policy -Apply
  ```

  **Expect:** the same lines as T.1 without the `What if:` lines, and `errors published by ...: 0`
  after each.
  **Failure looks like:** a published error -- record it; T.3 shows what state the policy is left in.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- member: restoring RequireApproval = False
  --- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
  --- owner: restoring RequireApproval = False
  --- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
  --- arm: restoring RequireApproval = False
  --- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
  ```

- [x] **T.3 Read back against the baseline.**

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
  keeps `User` `<IdApprover>` (3.7), and the Azure policy keeps `<IdApprover>` and `<IdApprovers>`. No
  module call can empty an approver list while turning approval off (see "What this file does not
  check"); with approval off none of them is ever asked. The two group policies go with their groups
  in T.5. The Azure policy does NOT go with its resource group: deleting a resource group leaves its
  Reader policy behind, and one created again under the same name finds it as it was left (run 2).
  So T.5 restores it to its defaults -- approval off, no approver -- BEFORE it deletes the resource
  group, and reads it again. Record the residue here.
  **Failure looks like:** `RequireApproval` `True` on any of the three, a changed policy id, or a
  changed `ActivationMaxHours`.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. All three: approval off,
  the same policy id, `ActivationMaxHours` at baseline. Residue exactly as expected: the member
  policy keeps the group, the owner policy the user, the Azure policy both. Observation: with
  approval off, Graph returns the approvers without `description`.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === member: RequireApproval False (baseline False), ActivationMaxHours 8 (baseline 8), same policy id: True
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000003 Group
  --- T.3-member-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000005, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 1
  odataType                     id                                   userId groupId description
  ---------                     --                                   ------ ------- -----------
  #microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000003
  === owner: RequireApproval False (baseline False), ActivationMaxHours 8 (baseline 8), same policy id: True
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000001 User
  --- T.3-owner-raw: policy Group_00000000-0000-0000-0000-000000000004_00000000-0000-0000-0000-000000000006, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 1
  odataType                   id                                   userId groupId description
  ---------                   --                                   ------ ------- -----------
  #microsoft.graph.singleUser 00000000-0000-0000-0000-000000000001
  === arm: RequireApproval False (baseline False), same policy id: True
  Id                                   UserType DisplayName
  --                                   -------- -----------
  00000000-0000-0000-0000-000000000003 Group
  00000000-0000-0000-0000-000000000001 User
  ```

- [x] **T.4 Read the teardown plan.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -Teardown -WhatIf
  ```

  **Expect:** both identity lines `True` after each of its two sign-ins; the tenant is identified
  first, through the `Connect-OER` sign-in, exactly as in 0.2 (the `Identified the test tenant` and
  `Identified the test subscription` lines, no question under `-WhatIf`); the later Phase 1 sign-in
  reports it is signed in to the confirmed test tenant. Then, BEFORE the resource group's line, a read
  `Teardown, before the restore: Reader policy at oer-s62-rg: approval required ..., approvers <n>; at its defaults (approval off, no approver): <True or False>`
  (with one `approver on it:` line per approver) and
  `What if: Performing the operation "Restore to its defaults before the resource group is deleted: approval off, no approver" on target "Reader role management policy at resource group 'oer-s62-rg'".`
  Then `What if:` lines, and nothing else changed, for: deleting the resource group `oer-s62-rg` (its
  target names `tag purpose = oer-s62-live-verification`); removing the member eligibility of
  `<IdEligible>` on `oer-s62-pim` and on `oer-s62-new`; deleting the groups `oer-s62-new`,
  `oer-s62-pim` and `oer-s62-approvers`; deleting the two users. Every name starts with `oer-s62`.
  Nothing was deleted, so both sweeps list what is still there (the resource group; the two users and
  three groups); then `WhatIf: nothing was created or removed.` and `Done.`
  **Failure looks like:** any target without the prefix -- stop, do not run T.5. A warning
  `Refusing to delete resource group oer-s62-rg: its 'purpose' tag is ...` means the resource group
  does not carry the tag the script gave it: it may not be the test's -- find out whose it is before
  T.5, which will refuse it the same way.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Every target carries the
  prefix, the resource group carries the tag.

  ```text
  Tenant Profile for the alias on this machine: False
  [oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
  [oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s62] Mode: REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
  [oer-s62] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
  [oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
  What if: Performing the operation "Delete the resource group (Azure completes it asynchronously)" on target "resource group 'oer-s62-rg' in subscription '<SubscriptionName>' (tag purpose = oer-s62-live-verification)".
  What if: Performing the operation "Remove the member eligibility of principal 00000000-0000-0000-0000-000000000002" on target "oer-s62-pim".
  What if: Performing the operation "Remove the member eligibility of principal 00000000-0000-0000-0000-000000000002" on target "oer-s62-new".
  [oer-s62] Phase 2 sweep, still present: resource group oer-s62-rg (Succeeded -- Azure deletes a resource group asynchronously; re-read in a few minutes)
  [oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s62] Phase 1 identity check: tenant is the test tenant: True
  [oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
  What if: Performing the operation "Delete security group (its PIM-for-Groups policies go with it)" on target "oer-s62-new".
  What if: Performing the operation "Delete security group (its PIM-for-Groups policies go with it)" on target "oer-s62-pim".
  What if: Performing the operation "Delete security group (its PIM-for-Groups policies go with it)" on target "oer-s62-approvers".
  What if: Performing the operation "Delete test user" on target "person1@example.com".
  What if: Performing the operation "Delete test user" on target "person2@example.com".
  [oer-s62] Phase 1 sweep, still present: users 'person1@example.com' (00000000-0000-0000-0000-000000000001)
  [oer-s62] Phase 1 sweep, still present: users 'person2@example.com' (00000000-0000-0000-0000-000000000002)
  [oer-s62] Phase 1 sweep, still present: groups 'oer-s62-approvers' (00000000-0000-0000-0000-000000000003)
  [oer-s62] Phase 1 sweep, still present: groups 'oer-s62-new' (00000000-0000-0000-0000-000000000008)
  [oer-s62] Phase 1 sweep, still present: groups 'oer-s62-pim' (00000000-0000-0000-0000-000000000004)
  [oer-s62] WhatIf: nothing was created or removed.
  [oer-s62] Done.
  ```

- [x] **T.5 Remove every test object.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -ModulePath $ModulePsd1 -Teardown -Unattended
  ```

  **Expect:** both identity lines `True` after each of its two sign-ins; the tenant is identified
  through the `Connect-OER` sign-in and, BEFORE anything is removed, the run prints
  `Unattended run: the confirmation question is not asked; ...` (an operator at the keyboard, without
  `-Unattended`, is asked once instead); the later Phase 1 sign-in reports
  `... is signed in to the confirmed test tenant ...`. No
  `Refusing to delete resource group` warning. Then, BEFORE the resource group is deleted, the Azure
  policy restore: the read `Teardown, before the restore: Reader policy at oer-s62-rg: ...` (the
  residue T.3 recorded, one `approver on it:` line per approver),
  `Restored the Reader role management policy at resource group 'oer-s62-rg' to its defaults.` and the
  read again,
  `Teardown, read again after the restore: Reader policy at oer-s62-rg: approval required False, approvers 0; at its defaults (approval off, no approver): True`.
  Then `Deletion of resource group oer-s62-rg accepted.`,
  one `Removed the member eligibility of principal <IdEligible> on ...` line for `oer-s62-pim` and one
  for `oer-s62-new`, `Deleted group ...` for the three groups and `Deleted user ...` for the two
  users. The Phase 2 sweep reports `no resource group starting with 'oer-s62' is left.` or at most
  `oer-s62-rg` in `Deleting` state (Azure deletes it asynchronously); the Phase 1 sweep reports
  `no user or group starting with 'oer-s62' is left.`; `Done.`
  **Failure looks like:** the read after the restore ending `False` -- the script then stops with
  `... is not at its defaults after the restore. The resource group was NOT deleted ...`: look at the
  policy before running T.5 again; a sweep line `still present: ...` other than a `Deleting` resource group; an
  error; a `Refusing to delete resource group oer-s62-rg` warning (see T.4 -- never delete it by hand
  before knowing whose it is). Re-run T.5 (it only removes what is still there) and record both runs. An
  `Authorization_RequestDenied` or a 403 on a deletion means the certificate identity lacks a
  permission: stop and name it (see Setup) -- never finish the deletion with another sign-in.
  **Result:** PASS on the second run -- 2026-09-28, run by Claude Code as the certificate identity
  `oer-live-cc` (app-only), every output below passed through the run's redaction first. Run 1
  removed everything (the resource group's deletion accepted, both eligibilities removed, the three
  groups and the two users deleted), but its Phase 1 sweep, made right after the deletions, still
  listed the five objects: Graph's list lagging behind the deletes. T.6 then read nothing left. Run
  2 found nothing to remove, and both sweeps report nothing left.

  ```text
  # run 1
  Tenant Profile for the alias on this machine: False
  [oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
  [oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s62] Mode: REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
  [oer-s62] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
  [oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
  [oer-s62] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
  WARNING: Deleting resource group 'oer-s62-rg' permanently deletes ALL resources it contains.
  [oer-s62] Deletion of resource group oer-s62-rg accepted.
  WARNING: Removing PIM member eligibility for principal '00000000-0000-0000-0000-000000000002' from group '00000000-0000-0000-0000-000000000004'. The principal loses the ability to activate this member access.
  [oer-s62] Removed the member eligibility of principal 00000000-0000-0000-0000-000000000002 on oer-s62-pim.
  WARNING: Removing PIM member eligibility for principal '00000000-0000-0000-0000-000000000002' from group '00000000-0000-0000-0000-000000000008'. The principal loses the ability to activate this member access.
  [oer-s62] Removed the member eligibility of principal 00000000-0000-0000-0000-000000000002 on oer-s62-new.
  [oer-s62] Phase 2 sweep: no resource group starting with 'oer-s62' is left.
  [oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s62] Phase 1 identity check: tenant is the test tenant: True
  [oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
  [oer-s62] Deleted group oer-s62-new.
  [oer-s62] Deleted group oer-s62-pim.
  [oer-s62] Deleted group oer-s62-approvers.
  [oer-s62] Deleted user person1@example.com.
  [oer-s62] Deleted user person2@example.com.
  [oer-s62] Phase 1 sweep, still present: users 'person1@example.com' (00000000-0000-0000-0000-000000000001)
  [oer-s62] Phase 1 sweep, still present: users 'person2@example.com' (00000000-0000-0000-0000-000000000002)
  [oer-s62] Phase 1 sweep, still present: groups 'oer-s62-approvers' (00000000-0000-0000-0000-000000000003)
  [oer-s62] Phase 1 sweep, still present: groups 'oer-s62-new' (00000000-0000-0000-0000-000000000008)
  [oer-s62] Phase 1 sweep, still present: groups 'oer-s62-pim' (00000000-0000-0000-0000-000000000004)
  [oer-s62] Done.
  # run 2
  Tenant Profile for the alias on this machine: False
  [oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
  [oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s62] Mode: REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
  [oer-s62] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
  [oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
  [oer-s62] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
  [oer-s62] Resource group oer-s62-rg does not exist.
  [oer-s62] Group oer-s62-pim does not exist.
  [oer-s62] Group oer-s62-new does not exist.
  [oer-s62] Phase 2 sweep: no resource group starting with 'oer-s62' is left.
  [oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s62] Phase 1 identity check: tenant is the test tenant: True
  [oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
  [oer-s62] Group oer-s62-new does not exist.
  [oer-s62] Group oer-s62-pim does not exist.
  [oer-s62] Group oer-s62-approvers does not exist.
  [oer-s62] User person1@example.com does not exist.
  [oer-s62] User person2@example.com does not exist.
  [oer-s62] Phase 1 sweep: no user or group starting with 'oer-s62' is left.
  [oer-s62] Done.
  ```

- [x] **T.6 Read back through the module that everything is gone.**

  ```powershell
  Get-OERGroup -Filter "startswith(displayName,'$Prefix')" -ErrorAction Continue
  Get-OERResourceGroup -Subscription $SubId | Where-Object ResourceGroup -like "$Prefix*"
  ```

  **Expect:** the group line writes a not-found error (or nothing) and the resource group line prints
  nothing. If the resource group is still listed as `Deleting`, re-read after a few minutes and
  record when it went.
  **Failure looks like:** any object listed.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Not-found for the groups,
  nothing for the resource group.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  Get-OERGroup: <harness>\T.6.ps1:1:1
  Line |
     1 |  Get-OERGroup -Filter "startswith(displayName,'$Prefix')" -ErrorAction ...
       |  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
       | No group found for 'startswith(displayName,'oer-s62')'.
  ```

- [x] **T.7 No object outside the prefix was touched, and nothing was removed by an apply.**

  ```powershell
  $All = Import-Csv (Join-Path $Raw 'all-results.csv')
  $All | Where-Object Action -in 'Created', 'Updated', 'Removed' | Format-Table CheckId, Section, Item, Action, Detail -Wrap
  @($All | Where-Object { $_.Item -notlike "*$Prefix*" }).Count
  ```

  **Expect:** no `Removed` row anywhere (no check used `-Prune`). The `Created`/`Updated` rows are
  exactly: `3.4` `Updated` for `pimPolicy (member)`; `3.7` `Updated` for `pimPolicy (owner)`; `4.2`
  `Updated` for `Reader @ <RgScope>` (absent
  if 4.2 reported `Unchanged`); and for `oer-s62-new` across 5.2 and 5.3 one `Created`, one eligibility
  `Updated` and one `Updated` per access type. The count line prints `0`: every row of every run names
  an `oer-s62` object (an Azure row names the scope `.../resourceGroups/oer-s62-rg`). The only writes
  outside the apply engine are 2.3 and T.2, both on `oer-s62-pim`'s policies and the Reader policy at
  `oer-s62-rg`, and the prerequisite script's, all prefix-named.
  **Failure looks like:** a `Removed` row, a `Created` or `Updated` row not listed above, or a count
  above `0`.
  **Result:** PASS, with one explained deviation -- 2026-09-28, run by Claude Code as the
  certificate identity `oer-live-cc` (app-only), every output below passed through the run's
  redaction first. No `Removed` row, and the `Created`/`Updated` rows are exactly the listed ones.
  The count line printed `1`, not `0`: the one row is 5.3's stray `adminAssign` object, with an
  empty Section and Item, not an object outside the prefix.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  CheckId Section                Item                                                                                   Action  Detail
  ------- -------                ----                                                                                   ------  ------
  3.4     groups                 oer-s62-pim                                                                            Updated pimPolicy (member) set: approvers(users=[])
  3.7     groups                 oer-s62-pim                                                                            Updated pimPolicy (owner) set: approvers(groups=[])
  4.2     roleManagementPolicies Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg Updated updated role management policy for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg' (requir
                                                                                                                                eApproval=True, approvers(users=[00000000-0000-0000-0000-000000000001],groups=[00000000-0000-0000-0000-000000000003]))
  5.2     groups                 oer-s62-new                                                                            Created created group oer-s62-new (00000000-0000-0000-0000-000000000008)
  5.2     groups                 oer-s62-new                                                                            Updated pimPolicy (owner) set: activationMaxHours=3; requireApproval=True; approvers(users=[00000000-0000-0000-0000-000000000001],groups=[1f60
                                                                                                                                64f8-879e-49e5-bca4-1736c27f6c73])
  5.3     groups                 oer-s62-new                                                                            Updated set time-bound member eligibility for 'person2@example.com' (30 days): time-bound member eligibility (30 days) is
                                                                                                                                 absent
  5.3     groups                 oer-s62-new                                                                            Updated pimPolicy (member) set: activationMaxHours=2
  1
  ```

- [x] **T.8 Read back through Microsoft Graph that no user or group is left.** The module has no user read, so this signs in to Microsoft Graph directly, as the same certificate identity, read-only, at the very end.

  ```powershell
  # Disconnect first: Connect-OER left its raw access token in the Graph SDK's process cache, which
  # Connect-MgGraph would otherwise try to read as an MSAL cache. Disconnect-OER empties it.
  Disconnect-OER
  Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -ContextScope Process -NoWelcome
  "identity check: session app id is oer-live-cc: $([string](Get-MgContext).ClientId -eq $AppId)"
  "identity check: tenant is the test tenant: $([string](Get-MgContext).TenantId -eq $TenantId)"
  $F = [uri]::EscapeDataString("startswith(userPrincipalName,'$Prefix')")
  @((Invoke-MgGraphRequest -Uri "v1.0/users?`$filter=$F&`$select=id,userPrincipalName").value).Count
  $F = [uri]::EscapeDataString("startswith(displayName,'$Prefix')")
  @((Invoke-MgGraphRequest -Uri "v1.0/groups?`$filter=$F&`$select=id,displayName").value).Count
  Disconnect-MgGraph
  $Error.Clear()   # a failed raw Graph call leaves an ErrorRecord that can carry the bearer token -- README.md, "Credentials"
  ```

  **Expect:** both identity lines `True`, then `0`, `0`. The two users now sit in Deleted items for 30 days, which is Entra ID's
  design; they hold no role, membership or eligibility, and the next prerequisite run can create the
  same names again. The deleted security groups are gone for good.
  **Failure looks like:** any count above `0`.
  **Result:** PASS -- 2026-09-28, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Both identity lines
  `True`, then `0`, `0`. `Disconnect-MgGraph` printed the context it closed.

  ```text
  Tenant Profile for the alias on this machine: False
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  0
  0
  ClientId               : <AppId>
  TenantId               : <TenantId>
  Scopes                 : {RoleManagementPolicy.ReadWrite.Directory, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleEligibilitySchedule.ReadWrite.Directory, AuthenticationContext.Read.All...}
  AuthType               : AppOnly
  TokenCredentialType    : ClientCertificate
  CertificateThumbprint  : <Thumbprint>
  CertificateSubjectName :
  SendCertificateChain   : False
  Account                :
  LoginHint              :
  HomeAccountId          :
  AppName                : oer-live-cc
  ContextScope           : Process
  Certificate            :
  PSHostVersion          : 7.6.6
  ManagedIdentityId      :
  ClientSecret           :
  Environment            : Global
  WamEnabled             : False
  ```

- [x] **T.9 Redact, then clean up.** Move what the results above need from `docs/live-verification/raw/s62/` into this file, redacted per [README.md](README.md), then delete the folder.

  Ids to `00000000-0000-0000-0000-0000000000NN`, user principal names to `personN@example.com`, no
  credential, no bearer token -- and that includes the output of 6.2's second process.

  ```powershell
  Remove-Item -LiteralPath $Raw -Recurse -Force
  git -C $Repo status --short docs/live-verification
  ```

  **Expect:** `git status` shows only this checklist as modified; nothing under `raw/` is ever staged.
  **Result:** PASS -- 2026-09-28, by Claude Code. The results above were written from the raw folder
  with every object id numbered per file and every address on the test domain replaced, in
  first-appearance order; the output of 6.2's second process included. A scan of this file before
  the folder was deleted found no value from the test environment, no id that is not a placeholder
  and no abbreviated id. Then the folder (98 files) was deleted.

  ```text
  raw/s62 exists after: False
   M docs/live-verification/feat-pim-group-approval-checklist.md
  ```

---

## Run 2 -- 2026-09-28, at `85d4144`: the prerequisites, section 5 and the Teardown after the 404-wait fix

Run by Claude Code as the certificate identity `oer-live-cc` (app-only), after "fix: wait through a
404 for the policy of a group created in the same run", "fix: keep the eligibility request out of
the apply results" and "fix: stop advising an eligibility when a PIM for Groups policy is not
listed". Run 1 had torn everything down, so the prerequisite script created new objects; 0.1, 0.3,
1.1 and 1.2 were re-run read-only to record them and the baseline the Teardown restores; X.1 is a
read-only check this run added; then section 5 and the Teardown. Every identity line of every
sign-in is True. Every output below passed through the run's redaction first. Placeholders from
`...13` on are run 2's objects. `...01`, `...03`, `...07` and `person1` to `person3` in
this section are the SAME identifiers as in run 1: run 1's approver user and approver group
(deleted, but still named on the Azure policy -- see 1.2), the Reader role definition id, and the
test UPNs, which the prerequisite script re-creates under the same names.

### Run 2: prerequisite script -- PASS after a re-run

The `-WhatIf` plan named only `oer-s62` targets (five `What if:` lines). The first real run created
the two users and both groups and then stopped: its read of the members of `oer-s62-approvers`, a
group it had created a second earlier, answered `404 Request_ResourceNotFound` -- the same
replication delay section 5 is about, here in the test scaffolding. The error shows the HTTP
response, not the request, so no token. The script completes what exists, so the re-run added the
member, granted the eligibility and created the resource group, tagged.

```text
# -WhatIf
Tenant Profile for the alias on this machine: False
[oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
[oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
[oer-s62] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
[oer-s62] Tenant identification (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Tenant identification (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Tenant identification (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
[oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
[oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
[oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
[oer-s62] Phase 1 identity check: tenant is the test tenant: True
[oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
What if: Performing the operation "Create a DISABLED test user with a random, unprinted password" on target "person1@example.com".
What if: Performing the operation "Create a DISABLED test user with a random, unprinted password" on target "person2@example.com".
What if: Performing the operation "Create security group" on target "oer-s62-approvers".
What if: Performing the operation "Create security group" on target "oer-s62-pim".
[oer-s62] Skipping the member of oer-s62-approvers: the group does not exist yet.
[oer-s62] Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Phase 2 (Connect-OER) is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
[oer-s62] Skipping the eligibility: oer-s62-pim does not exist yet.
What if: Performing the operation "Create in swedencentral" on target "resource group 'oer-s62-rg' in subscription '<SubscriptionId>'".
[oer-s62] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
Kind           Name                                     Id
----           ----                                     --
user           person1@example.com (none -- not created)
user           person2@example.com (none -- not created)
group          oer-s62-approvers                        (none -- not created)
group          oer-s62-pim                              (none -- not created)
resource group oer-s62-rg                               (none -- not created)
[oer-s62] WhatIf: nothing was created or removed.
[oer-s62] Done.
# real run 1 (stopped)
Tenant Profile for the alias on this machine: False
[oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
[oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
[oer-s62] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
[oer-s62] Tenant identification (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Tenant identification (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Tenant identification (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
[oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
[oer-s62] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
[oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
[oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
[oer-s62] Phase 1 identity check: tenant is the test tenant: True
[oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
[oer-s62] Created user person1@example.com (disabled).
[oer-s62] Created user person2@example.com (disabled).
[oer-s62] Created group oer-s62-approvers.
[oer-s62] Created group oer-s62-pim.
Invoke-MgGraphRequest: <Vault>\Initialize-OerS62Prereq.ps1:329:5
Line |
 329 |      Invoke-MgGraphRequest @Params
     |      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | GET https://graph.microsoft.com/v1.0/groups/00000000-0000-0000-0000-000000000013/members?$select=id HTTP/1.1 404
     | Not Found Cache-Control: no-cache Transfer-Encoding: chunked Vary: Accept-Encoding Strict-Transport-Security:
     | max-age=31536000 request-id: 00000000-0000-0000-0000-000000000014 client-request-id:
     | 00000000-0000-0000-0000-000000000015 x-ms-ags-diagnostic: {"ServerInfo":{"DataCenter":"Sweden
     | Central","Slice":"E","Ring":"3","ScaleUnit":"000","RoleInstance":"GVX0EPF00004FE8"}} x-ms-resource-unit: 2 Date:
     | Mon, 28 Sep 2026 10:53:33 GMT Content-Type: application/json
     | {"error":{"code":"Request_ResourceNotFound","message":"Resource '00000000-0000-0000-0000-000000000013' does not
     | exist or one of its queried reference-property objects are not
     | present.","innerError":{"date":"2026-09-28T10:53:34","request-id":"00000000-0000-0000-0000-000000000014","client-request-id":"00000000-0000-0000-0000-000000000015"}}}
# real run 2
Tenant Profile for the alias on this machine: False
[oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
[oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
[oer-s62] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
[oer-s62] Tenant identification (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Tenant identification (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Tenant identification (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
[oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
[oer-s62] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
[oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
[oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
[oer-s62] Phase 1 identity check: tenant is the test tenant: True
[oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
[oer-s62] User person1@example.com exists.
[oer-s62] User person2@example.com exists.
[oer-s62] Group oer-s62-approvers exists.
[oer-s62] Group oer-s62-pim exists.
[oer-s62] Added person1@example.com to oer-s62-approvers.
[oer-s62] Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Phase 2 (Connect-OER) is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
[oer-s62] Granted person2@example.com a 30-day member eligibility on oer-s62-pim.
[oer-s62] Created resource group oer-s62-rg in swedencentral, tagged purpose = oer-s62-live-verification.
[oer-s62] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
Kind                                               Name                                                          Id
----                                               ----                                                          --
user                                               person1@example.com                      00000000-0000-0000-0000-000000000016
user                                               person2@example.com                      00000000-0000-0000-0000-000000000017
group                                              oer-s62-approvers                                             00000000-0000-0000-0000-000000000013
group                                              oer-s62-pim                                                   00000000-0000-0000-0000-000000000018
resource group                                     oer-s62-rg                                                    /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg
group member                                       oer-s62-approvers <- person1@example.com 00000000-0000-0000-0000-000000000016
PIM eligibility (member, ends 10/28/2026 10:54:02) oer-s62-pim <- person2@example.com       00000000-0000-0000-0000-000000000018_member_00000000-0000-0000-0000-000000000017
[oer-s62] Done.
```

### Run 2: 0.1 and 0.3 -- PASS

The session ran the branch build at this commit. 0.3 recorded the new ids; its first run did not
write the state file the harness keeps between processes, so it was run again with that one line
added.

```text
Omnicit.EntraRBAC 1.0.2 from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2
Name                         CommandType
----                         -----------
ConvertFrom-OERGraphApprover    Function
Resolve-OERDeclaredApprover     Function
RequireApproval
ApproverUser
ApproverGroup
True
# 0.3
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
PrincipalId                          UserPrincipalName
-----------                          -----------------
00000000-0000-0000-0000-000000000016 person1@example.com
PrincipalId                          AccessType StartDateTime       EndDateTime
-----------                          ---------- -------------       -----------
00000000-0000-0000-0000-000000000017 member     2026-09-28 10:54:02 2026-10-28 10:54:02
0
0
True
True
True
True
--- state saved: True
```

### Run 2: 1.1 and 1.2 -- PASS, with the Azure policy carrying run 1's approvers

1.1 and 1.2 were first run in separate processes, where 1.2 cannot find the baseline object 1.1
builds; re-run together, as in run 1. The two group policies: `ActivationMaxHours` 8, approval
off, no approver. The Reader policy at the NEW `oer-s62-rg` already names two approvers, with
approval off: `...01` and `...03`, run 1's approver user and approver group. A read-only check
(below) found both deleted from the directory and neither an object of run 2. Deleting a resource
group does not delete its role management policy: the policy is named by the role definition id
(`...07`, Reader), and one created again under the same path finds it as it was left. T.3's
sentence that T.5 deletes the policies "with their group and resource group" holds for the group
policies, not for the Azure one.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
=== member: PolicyId Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000019, ActivationMaxHours 8, RequireApproval False, approvers 0
--- 1.1-member-raw: policy Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000019, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
    primary approvers: 0
=== owner: PolicyId Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000020, ActivationMaxHours 8, RequireApproval False, approvers 0
--- 1.1-owner-raw: policy Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000020, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
    primary approvers: 0
True
PolicyId           : /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000007
Scope              : /subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg
RoleName           : Reader
ActivationMaxHours : 8
RequireApproval    : False
Id                                   UserType DisplayName
--                                   -------- -----------
00000000-0000-0000-0000-000000000001 User
00000000-0000-0000-0000-000000000003 Group
{
  "member": {
    "PolicyId": "Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000019",
    "ActivationMaxHours": 8,
    "RequireApproval": false,
    "Approvers": []
  },
  "owner": {
    "PolicyId": "Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000020",
    "ActivationMaxHours": 8,
    "RequireApproval": false,
    "Approvers": []
  },
  "arm": {
    "PolicyId": "/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000007",
    "RequireApproval": false,
    "Approvers": [
      {
        "Id": "00000000-0000-0000-0000-000000000001",
        "UserType": "User",
        "DisplayName": ""
      },
      {
        "Id": "00000000-0000-0000-0000-000000000003",
        "UserType": "Group",
        "DisplayName": ""
      }
    ]
  }
}
# read-only check of the approvers on the Azure policy
--- Reader policy at the new oer-s62-rg: RequireApproval False, approvers 2
--- approver 00000000-0000-0000-0000-000000000001 (User): exists in the directory now: False; is the approver or the approvers group this run created: False
--- approver 00000000-0000-0000-0000-000000000003 (Group): exists in the directory now: False; is the approver or the approvers group this run created: False
```

### Run 2: X.1 (read-only, added in this run) -- a group never used with PIM for Groups carries a pimPolicy

`Get-OERInventory` of `oer-s62-approvers`, which nothing ever onboarded: one group read,
carrying a `pimPolicy` block (the member and owner defaults), and Graph lists both policy
assignments, neither policy ever modified. This is what "fix: stop advising an eligibility when a
PIM for Groups policy is not listed" now says in the inventory README and in the help of
`Export-OERInventory`. The first attempt ran before the ids were restored and stopped on an empty
group id; the output is the second.

```text
--- errors published by Get-OERInventory: 0 (other records collected, not shown: 0)
--- inventory: groups read 1; carrying pimPolicy 1
--- the pimPolicy the inventory exported:
{
  "member": {
    "activationMaxHours": 8,
    "activationEnablement": [
      "Justification"
    ],
    "allowPermanentEligibility": false,
    "eligibleDurationDays": 365,
    "allowPermanentActive": false,
    "activeDurationDays": 180,
    "activeEnablement": [
      "Justification"
    ],
    "requireApproval": false
  },
  "owner": {
    "activationMaxHours": 8,
    "activationEnablement": [
      "Justification"
    ],
    "allowPermanentEligibility": false,
    "eligibleDurationDays": 365,
    "allowPermanentActive": false,
    "activeDurationDays": 180,
    "activeEnablement": [
      "Justification"
    ],
    "requireApproval": false
  }
}
--- raw policy assignments listed for the approvers group: 2 (member, owner)
--- member policy: ever modified: False
--- owner policy: ever modified: False
```

### Run 2: 5.1 -- PASS


```text
What if: Performing the operation "Create group" on target "oer-s62-new".
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
=== 5.1 -- raw/s62/5.1.json
--- offline validation: Valid = True, findings = 0
--- Invoke-OERStructure -Include Groups -WhatIf
--- warnings, in the order written: 0
--- errors: 0
--- results: 3
Section : groups
Item    : oer-s62-new
Action  : Skipped
Detail  : would create group oer-s62-new
Section : groups
Item    : oer-s62-new
Action  : Skipped
Detail  : would configure eligibility for 'person2@example.com' after group is created
Section : groups
Item    : oer-s62-new
Action  : Skipped
Detail  : would configure pimPolicy after group is created
--- action counts: Skipped=3
```

### Run 2: 5.2 -- FAIL, differently: the first look LISTED the policies, and the reads after it answered 404

Row 1 `Created`. Row 2 `Failed`: the eligibility answered `ResourceNotFound` (the group too
new for PIM itself). Rows 3 and 4, member and owner: `Failed` with `PimPolicyReadFailed` naming
`ResourceNotFound`. The verbose log shows why the 404 wait did not help: for each access type the
wait's question (log lines 13 and 22) came back with the policy LISTED -- no 404 line, no wait line
-- and the policy read right after it (lines 15 and 24) and `Set-OERGroupPimPolicy`'s own lookup
(lines 19 and 28) answered 404. Graph listed the new group's policy assignments on one request and
answered 404 for the same request a second later: the replicas disagree while the group is new, so
"listed once" does not mean "readable next". The wait waits only for the first listing, so it cannot
cover this. The `PimPolicyNotFound` count is `0`. How long the 404 lasted: the whole apply took
about 4 seconds, from 12:57:21 to 12:57:25 local time, and every read of the group's policies after
the first look answered 404; 5.3, started at 12:58:20, read and wrote everything. So at least about
3 seconds after creation, and gone within about a minute. The budget was not reached, and it was not
changed.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
=== 5.2 -- raw/s62/5.2.json
--- offline validation: Valid = True, findings = 0
--- Invoke-OERStructure -Include Groups -Confirm:$false -Verbose
Invoke-OERStructure: <harness>\_signin.ps1:51:14
Line |
  51 |      $Out = @(Invoke-OERStructure @Splat 3>&1 4>&1)
     |               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | ResourceNotFound: The resource is not found.
Invoke-OERStructure: <harness>\_signin.ps1:51:14
Line |
  51 |      $Out = @(Invoke-OERStructure @Splat 3>&1 4>&1)
     |               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('member'
     | access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not
     | the same as the group having none, so nothing was changed.
Invoke-OERStructure: <harness>\_signin.ps1:51:14
Line |
  51 |      $Out = @(Invoke-OERStructure @Splat 3>&1 4>&1)
     |               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('owner'
     | access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not
     | the same as the group having none, so nothing was changed.
--- step-4 retry lines: 0 (all 29 verbose lines are in 5.2-verbose.log)
--- warnings, in the order written: 0
--- errors: 49
    ERROR []:
    ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: NotFound (Not Found).
    ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: NotFound (Not Found).
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound,Add-OERGroupEligibility]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound,Invoke-OERStructure]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [PimPolicyReadFailed,Get-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so no policy is reported for it.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [PimPolicyReadFailed,Set-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.
    ERROR [PimPolicyReadFailed,Invoke-OERStructure]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [PimPolicyReadFailed,Get-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('owner' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so no policy is reported for it.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [ResourceNotFound]: ResourceNotFound: The resource is not found.
    ERROR []:
    ERROR [PimPolicyReadFailed,Set-OERGroupPimPolicy]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('owner' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.
    ERROR [PimPolicyReadFailed,Invoke-OERStructure]: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('owner' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is not the same as the group having none, so nothing was changed.
--- results: 4
Section : groups
Item    : oer-s62-new
Action  : Created
Detail  : created group oer-s62-new (00000000-0000-0000-0000-000000000021)
Section : groups
Item    : oer-s62-new
Action  : Failed
Detail  : failed to add eligibility for 'person2@example.com': ResourceNotFound: The resource is not found.
Section : groups
Item    : oer-s62-new
Action  : Failed
Detail  : pimPolicy (member) update failed: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('member' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which
          is not the same as the group having none, so nothing was changed.
Section : groups
Item    : oer-s62-new
Action  : Failed
Detail  : pimPolicy (owner) update failed: Could not read the PIM-for-groups policy assignment for group '00000000-0000-0000-0000-000000000021' ('owner' access): ResourceNotFound: The resource is not found.. Whether this group has a policy is UNKNOWN, which is
           not the same as the group having none, so nothing was changed.
--- action counts: Created=1, Failed=3
PimPolicyNotFound records in -ErrorVariable: 0
# 5.2-verbose.log, redacted, with line numbers:
 1: [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
 2: [Invoke-OERGraphRequest] GET v1.0/groups?$filter=displayName eq 'oer-s62-new'&$select=id,displayName
 3: Performing the operation "Create group" on target "oer-s62-new".
 4: [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
 5: [Invoke-OERGraphRequest] GET v1.0/groups?$filter=displayName eq 'oer-s62-new'&$select=id,displayName
 6: [Invoke-OERGraphRequest] POST v1.0/groups
 7: [Invoke-OERGraphRequest] GET v1.0/users?$filter=userPrincipalName eq 'person2%40example.com'&$select=id,userPrincipalName
 8: Performing the operation "Add time-bound member eligibility for '00000000-0000-0000-0000-000000000017' (30 days)" on target "oer-s62-new".
 9: [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
10: [Add-OERGroupEligibility] Resolved group to '00000000-0000-0000-0000-000000000021'.
11: [Add-OERGroupEligibility] Resolved principal to '00000000-0000-0000-0000-000000000017'.
12: [Invoke-OERGraphRequest] POST beta/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests
13: [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000021' and scopeType eq 'Group'
14: [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
15: [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000021' and scopeType eq 'Group'
16: Performing the operation "Set PIM policy (member): activationMaxHours=2" on target "oer-s62-new".
17: [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
18: [Set-OERGroupPimPolicy] Resolved group to '00000000-0000-0000-0000-000000000021'.
19: [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000021' and scopeType eq 'Group'
20: [Invoke-OERGraphRequest] GET v1.0/users?$filter=userPrincipalName eq 'person1%40example.com'&$select=id,userPrincipalName
21: [Invoke-OERGraphRequest] GET v1.0/groups?$filter=displayName eq 'oer-s62-approvers'&$select=id,displayName
22: [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000021' and scopeType eq 'Group'
23: [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
24: [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000021' and scopeType eq 'Group'
25: Performing the operation "Set PIM policy (owner): activationMaxHours=3; requireApproval=True; approvers(users=[00000000-0000-0000-0000-000000000016],groups=[00000000-0000-0000-0000-000000000013])" on target "oer-s62-new".
26: [Initialize-OERAuth] Returning cached auth state for tenant '<TenantId>'.
27: [Set-OERGroupPimPolicy] Resolved group to '00000000-0000-0000-0000-000000000021'.
28: [Invoke-OERGraphRequest] GET beta/policies/roleManagementPolicyAssignments?$filter=scopeId eq '00000000-0000-0000-0000-000000000021' and scopeType eq 'Group'
29: Invoke-OERStructure complete. 4 record(s): Created=1, Failed=3
```

### Run 2: 5.3 -- PASS

Needed, after 5.2's three `Failed` rows; one run, about a minute after 5.2, applied the
eligibility and both policies. Four result rows and nothing else: the eligibility request no longer
appears among them ("fix: keep the eligibility request out of the apply results"). No retry line, no
warning, no error.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
=== 5.3 -- raw/s62/5.3.json
--- offline validation: Valid = True, findings = 0
--- Invoke-OERStructure -Include Groups -Confirm:$false -Verbose
--- step-4 retry lines: 0 (all 39 verbose lines are in 5.3-verbose.log)
--- warnings, in the order written: 0
--- errors: 0
--- results: 4
Section : groups
Item    : oer-s62-new
Action  : Unchanged
Detail  : group properties match
Section : groups
Item    : oer-s62-new
Action  : Updated
Detail  : set time-bound member eligibility for 'person2@example.com' (30 days): time-bound member eligibility (30 days) is absent
Section : groups
Item    : oer-s62-new
Action  : Updated
Detail  : pimPolicy (member) set: activationMaxHours=2
Section : groups
Item    : oer-s62-new
Action  : Updated
Detail  : pimPolicy (owner) set: activationMaxHours=3; requireApproval=True; approvers(users=[00000000-0000-0000-0000-000000000016],groups=[00000000-0000-0000-0000-000000000013])
--- action counts: Unchanged=1, Updated=3
# 5.3-verbose.log, redacted, the writes:
Performing the operation "Add time-bound member eligibility for '00000000-0000-0000-0000-000000000017' (30 days)" on target "oer-s62-new".
[Invoke-OERGraphRequest] POST beta/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests
Performing the operation "Set PIM policy (member): activationMaxHours=2" on target "oer-s62-new".
[Invoke-OERGraphRequest] PATCH beta/policies/roleManagementPolicies/Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000022/rules/Expiration_EndUser_Assignment
Performing the operation "Set PIM policy (owner): activationMaxHours=3; requireApproval=True; approvers(users=[00000000-0000-0000-0000-000000000016],groups=[00000000-0000-0000-0000-000000000013])" on target "oer-s62-new".
[Invoke-OERGraphRequest] PATCH beta/policies/roleManagementPolicies/Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000023/rules/Expiration_EndUser_Assignment
[Invoke-OERGraphRequest] PATCH beta/policies/roleManagementPolicies/Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000023/rules/Approval_EndUser_Assignment
Invoke-OERStructure complete. 4 record(s): Unchanged=1, Updated=3
```

### Run 2: 5.4 -- PASS

Two assignments on two different policy ids; member PT2H, approval off; owner PT3H, approval on, the
two approvers; the module agrees.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
roleDefinitionId policyId
---------------- --------
member           Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000022
owner            Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000023
--- member: policy Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000022, activation maximumDuration PT2H
--- 5.4-member-raw: policy Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000022, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
    primary approvers: 0
--- owner: policy Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000023, activation maximumDuration PT3H
--- 5.4-owner-raw: policy Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000023, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
    primary approvers: 2
odataType                     id                                   userId groupId description
---------                     --                                   ------ ------- -----------
#microsoft.graph.singleUser   00000000-0000-0000-0000-000000000016                OER S62 Approver
#microsoft.graph.groupMembers 00000000-0000-0000-0000-000000000013                oer-s62-approvers
--- member (module): PolicyId Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000022, ActivationMaxHours 2, RequireApproval False, approvers 0
--- owner (module): PolicyId Group_00000000-0000-0000-0000-000000000021_00000000-0000-0000-0000-000000000023, ActivationMaxHours 3, RequireApproval True, approvers 2
```

### Run 2: 5.5 -- PASS

Four Unchanged rows.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
=== 5.5 -- raw/s62/5.5.json
--- offline validation: Valid = True, findings = 0
--- Invoke-OERStructure -Include Groups -Confirm:$false
--- warnings, in the order written: 0
--- errors: 0
--- results: 4
Section : groups
Item    : oer-s62-new
Action  : Unchanged
Detail  : group properties match
Section : groups
Item    : oer-s62-new
Action  : Unchanged
Detail  : eligibility for 'person2@example.com' (member) already matches
Section : groups
Item    : oer-s62-new
Action  : Unchanged
Detail  : pimPolicy (member) already matches
Section : groups
Item    : oer-s62-new
Action  : Unchanged
Detail  : pimPolicy (owner) already matches
--- action counts: Unchanged=4
```

### Run 2: T.1 -- PASS

The three targets are 1.x's policy ids. For the Azure policy the plan restores the baseline
approvers -- run 1's residue, `...01` and `...03` -- and its approval step reports `NoChange`,
the case the check says to record and carry on from.

```text
What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000019".
What if: Performing the operation "Patch rule Approval_EndUser_Assignment" on target "PIM policy Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000020".
What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "role management policy '/subscriptions/<SubscriptionId>/resourceGroups/oer-s62-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000007'".
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
--- member: restoring RequireApproval = False
--- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
--- owner: restoring RequireApproval = False
--- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
--- arm: restoring the baseline approvers (1 user(s), 1 group(s))
--- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
--- arm: restoring RequireApproval = False
--- errors published by Set-OERRoleManagementPolicy: 1 (other records collected, not shown: 0)
    ERROR [NoChange,Set-OERRoleManagementPolicy]: No applicable policy rule changed.
```

### Run 2: T.2 -- PASS


```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
--- member: restoring RequireApproval = False
--- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
--- owner: restoring RequireApproval = False
--- errors published by Set-OERGroupPimPolicy: 0 (other records collected, not shown: 0)
--- arm: restoring the baseline approvers (1 user(s), 1 group(s))
--- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
--- arm: restoring RequireApproval = False
--- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
```

### Run 2: T.3 -- PASS for the group policies; the Azure policy lost one of run 1's approvers

Both group policies: approval off, the same policy id, `ActivationMaxHours` 8, no approver -- this
run never wrote them. The Azure policy: approval off, the same policy id, and ONE approver,
`...01` (run 1's deleted approver user, now with a display name), where the baseline had two: T.2
sent both ids without an error and Azure kept only the user. Both are residue of run 1 and neither
exists in the directory; what is left stays on an approval-off stage, where no one is asked.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
=== member: RequireApproval False (baseline False), ActivationMaxHours 8 (baseline 8), same policy id: True
--- T.3-member-raw: policy Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000019, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
    primary approvers: 0
=== owner: RequireApproval False (baseline False), ActivationMaxHours 8 (baseline 8), same policy id: True
--- T.3-owner-raw: policy Group_00000000-0000-0000-0000-000000000018_00000000-0000-0000-0000-000000000020, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
    primary approvers: 0
=== arm: RequireApproval False (baseline False), same policy id: True
Id                                   UserType DisplayName
--                                   -------- -----------
00000000-0000-0000-0000-000000000001 User     OER S62 Approver
```

### Run 2: T.4 -- PASS

Eight `What if:` lines, every one naming an `oer-s62` target; the resource group carries the
tag.

```text
Tenant Profile for the alias on this machine: False
[oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
[oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
[oer-s62] Mode: REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
[oer-s62] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
[oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
What if: Performing the operation "Delete the resource group (Azure completes it asynchronously)" on target "resource group 'oer-s62-rg' in subscription '<SubscriptionName>' (tag purpose = oer-s62-live-verification)".
What if: Performing the operation "Remove the member eligibility of principal 00000000-0000-0000-0000-000000000017" on target "oer-s62-pim".
What if: Performing the operation "Remove the member eligibility of principal 00000000-0000-0000-0000-000000000017" on target "oer-s62-new".
[oer-s62] Phase 2 sweep, still present: resource group oer-s62-rg (Succeeded -- Azure deletes a resource group asynchronously; re-read in a few minutes)
[oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
[oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
[oer-s62] Phase 1 identity check: tenant is the test tenant: True
[oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
What if: Performing the operation "Delete security group (its PIM-for-Groups policies go with it)" on target "oer-s62-new".
What if: Performing the operation "Delete security group (its PIM-for-Groups policies go with it)" on target "oer-s62-pim".
What if: Performing the operation "Delete security group (its PIM-for-Groups policies go with it)" on target "oer-s62-approvers".
What if: Performing the operation "Delete test user" on target "person1@example.com".
What if: Performing the operation "Delete test user" on target "person2@example.com".
[oer-s62] Phase 1 sweep, still present: users 'person1@example.com' (00000000-0000-0000-0000-000000000016)
[oer-s62] Phase 1 sweep, still present: users 'person2@example.com' (00000000-0000-0000-0000-000000000017)
[oer-s62] Phase 1 sweep, still present: groups 'oer-s62-approvers' (00000000-0000-0000-0000-000000000013)
[oer-s62] Phase 1 sweep, still present: groups 'oer-s62-new' (00000000-0000-0000-0000-000000000021)
[oer-s62] Phase 1 sweep, still present: groups 'oer-s62-pim' (00000000-0000-0000-0000-000000000018)
[oer-s62] WhatIf: nothing was created or removed.
[oer-s62] Done.
```

### Run 2: T.5 -- PASS on the second run

Run 1 removed everything; its sweep, right after the deletions, still listed four of the five
objects, as in run 1. T.6 then read nothing left, and run 2 found nothing to remove, with both
sweeps clean.

```text
# run 1
Tenant Profile for the alias on this machine: False
[oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
[oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
[oer-s62] Mode: REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
[oer-s62] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
[oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
[oer-s62] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
WARNING: Deleting resource group 'oer-s62-rg' permanently deletes ALL resources it contains.
[oer-s62] Deletion of resource group oer-s62-rg accepted.
WARNING: Removing PIM member eligibility for principal '00000000-0000-0000-0000-000000000017' from group '00000000-0000-0000-0000-000000000018'. The principal loses the ability to activate this member access.
[oer-s62] Removed the member eligibility of principal 00000000-0000-0000-0000-000000000017 on oer-s62-pim.
WARNING: Removing PIM member eligibility for principal '00000000-0000-0000-0000-000000000017' from group '00000000-0000-0000-0000-000000000021'. The principal loses the ability to activate this member access.
[oer-s62] Removed the member eligibility of principal 00000000-0000-0000-0000-000000000017 on oer-s62-new.
[oer-s62] Phase 2 sweep: no resource group starting with 'oer-s62' is left.
[oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
[oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
[oer-s62] Phase 1 identity check: tenant is the test tenant: True
[oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
[oer-s62] Deleted group oer-s62-new.
[oer-s62] Deleted group oer-s62-pim.
[oer-s62] Deleted group oer-s62-approvers.
[oer-s62] Deleted user person1@example.com.
[oer-s62] Deleted user person2@example.com.
[oer-s62] Phase 1 sweep, still present: users 'person1@example.com' (00000000-0000-0000-0000-000000000016)
[oer-s62] Phase 1 sweep, still present: users 'person2@example.com' (00000000-0000-0000-0000-000000000017)
[oer-s62] Phase 1 sweep, still present: groups 'oer-s62-approvers' (00000000-0000-0000-0000-000000000013)
[oer-s62] Phase 1 sweep, still present: groups 'oer-s62-pim' (00000000-0000-0000-0000-000000000018)
[oer-s62] Done.
# run 2
Tenant Profile for the alias on this machine: False
[oer-s62] Omnicit.EntraRBAC 1.0.2 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.0.2.
[oer-s62] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
[oer-s62] Mode: REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s62', expected organization '<OrgName>'.
[oer-s62] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
[oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
[oer-s62] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
[oer-s62] Identified the test tenant: organization '<OrgName>', tenant id <TenantId>, verified domain <Domain>.
[oer-s62] Identified the test subscription: '<SubscriptionName>' (<SubscriptionId>).
[oer-s62] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
[oer-s62] Resource group oer-s62-rg does not exist.
[oer-s62] Group oer-s62-pim does not exist.
[oer-s62] Group oer-s62-new does not exist.
[oer-s62] Phase 2 sweep: no resource group starting with 'oer-s62' is left.
[oer-s62] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
[oer-s62] Phase 1 identity check: session app id is oer-live-cc: True
[oer-s62] Phase 1 identity check: tenant is the test tenant: True
[oer-s62] Phase 1 is signed in to the confirmed test tenant '<OrgName>' (<TenantId>).
[oer-s62] Group oer-s62-new does not exist.
[oer-s62] Group oer-s62-pim does not exist.
[oer-s62] Group oer-s62-approvers does not exist.
[oer-s62] User person1@example.com does not exist.
[oer-s62] User person2@example.com does not exist.
[oer-s62] Phase 1 sweep: no user or group starting with 'oer-s62' is left.
[oer-s62] Done.
```

### Run 2: T.6 -- PASS


```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
Get-OERGroup: <harness>\T.6.ps1:1:1
Line |
   1 |  Get-OERGroup -Filter "startswith(displayName,'$Prefix')" -ErrorAction ...
     |  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     | No group found for 'startswith(displayName,'oer-s62')'.
```

### Run 2: T.7 -- PASS: the count line prints 0

No `Removed` row; the `Created`/`Updated` rows are exactly 5.2's `Created` and 5.3's three
`Updated` (section 5 is all this run applied). The count line prints `0`: every row names an
`oer-s62` object, with no stray eligibility request among them.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
CheckId Section Item        Action  Detail
------- ------- ----        ------  ------
5.2     groups  oer-s62-new Created created group oer-s62-new (00000000-0000-0000-0000-000000000021)
5.3     groups  oer-s62-new Updated set time-bound member eligibility for 'person2@example.com' (30 days): time-bound member eligibility (30 days) is absent
5.3     groups  oer-s62-new Updated pimPolicy (member) set: activationMaxHours=2
5.3     groups  oer-s62-new Updated pimPolicy (owner) set: activationMaxHours=3; requireApproval=True; approvers(users=[00000000-0000-0000-0000-000000000016],groups=[00000000-0000-0000-0000-000000000013])
0
```

### Run 2: T.8 -- PASS

Both identity lines True, then 0 and 0.

```text
Tenant Profile for the alias on this machine: False
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
identity check: session app id is oer-live-cc: True
identity check: tenant is the test tenant: True
0
0
ClientId               : <AppId>
TenantId               : <TenantId>
Scopes                 : {RoleManagementPolicy.ReadWrite.Directory, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleEligibilitySchedule.ReadWrite.Directory, AuthenticationContext.Read.All...}
AuthType               : AppOnly
TokenCredentialType    : ClientCertificate
CertificateThumbprint  : <Thumbprint>
CertificateSubjectName :
SendCertificateChain   : False
Account                :
LoginHint              :
HomeAccountId          :
AppName                : oer-live-cc
ContextScope           : Process
Certificate            :
PSHostVersion          : 7.6.6
ManagedIdentityId      :
ClientSecret           :
Environment            : Global
WamEnabled             : False
```

### Run 2: T.9 -- PASS

The results above were written from the raw folder with the placeholder rules in this section's
first paragraph, and a scan found no value from the test environment, no id that is not a
placeholder, and no address on the test domain. Then the folder was deleted.

```text
raw/s62 files deleted: 48
raw/s62 exists after: False
 M docs/live-verification/feat-pim-group-approval-checklist.md
```
