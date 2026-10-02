# Live verification checklist -- PIM settings for Microsoft Entra directory roles (feat/directory-role-management-policies)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to two TENANT-WIDE PIM policies, and it runs the writes for real.** They are the
policies of the built-in directory roles **Reports Reader** and **Message Center Reader** -- two
low-risk, read-only roles, and the only directory roles any command in this file names. Never Global
Administrator, never Privileged Role Administrator, never any other role. A directory role's policy
is not a test object: it carries no prefix, it existed before this file ran and it outlives it, and
it governs every activation of that role in the tenant. So the prerequisite script records the raw
rules of both policies in a baseline file before the first write (1.1 checks that record), and its
teardown restores them from that file, rule by rule, before anything else is removed (T.3); T.4
proves it. Every write is preceded by its `-WhatIf` plan: read the plan against the `Expect:` line
first, and only then run the line that writes. Every apply goes through the `Invoke-S63Check` helper
defined in Setup, which runs `Invoke-OERStructure -WhatIf` unless `-Apply` is passed; the section has
no `-Prune` and no check passes it. Every other object any command or document names was created by
the prerequisite script for this file and carries the prefix `oer-s63`; the only other policy
written is the Reader role management policy at the resource group `oer-s63-rg` (section 5). That
policy outlives its resource group, so the prerequisite script records its raw rule set too, in the
Reader record beside the baseline file (1.4 checks that record), and its teardown restores it IN FULL
from that record -- activation hours, approval and approvers alike -- before the resource group is
deleted (T.3). T.1 also puts the activation hours back through the module, but the teardown does not
depend on it.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s63/` --
the helpers write every document, every raw Graph read and a results log there, the prerequisite
script writes the baseline file and the Reader record there, and the folder is git-ignored. Both
files hold real object ids: never copy either, or any part of it, into a tracked file. What goes into
a `Result:` below is redacted first, per [README.md](README.md):

- **Object ids** become `00000000-0000-0000-0000-0000000000NN` in first-appearance order for THIS
  file (the same id always gets the same placeholder -- several checks turn on two ids being the
  same or different). That includes the two role definition ids: a built-in role's template id is the
  same in every tenant, but it is version-4 shaped and is redacted like any other id. It includes the
  approver ids the prerequisite script prints on its `approver on it:` lines, and the ids its sweep
  lines print.
- **The tenant id** becomes `<TenantId>` and **the subscription id** `<SubscriptionId>`, wherever
  they appear: in the script's `Mode:` and `Identified ...` lines, inside every Azure Resource Manager
  path (`/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg/...`), and as the first half of a
  directory-role policy id, which becomes `DirectoryRole_<TenantId>_00000000-0000-0000-0000-0000000000NN`.
- **The organization display name** becomes `<test tenant>`, the **subscription display name**
  `<test subscription>`, the **verified domain** `<test domain>`, the tenant alias `<Alias>`, and the
  local path of the clone `<Repo>`. Every user principal name on the test domain becomes a
  `personN@example.com` address.
- **No credential, no bearer token, no application id and no certificate thumbprint** is ever pasted.

The test objects' display names and the two role names may stay.
**Never render an error record** (`Format-List` on `$Error[0]`, on a `-ErrorVariable`, or on a catch
variable): a raw Graph failure's record carries the bearer token. Every block below prints the error
id and message only. The helpers name test objects and policies instead of printing their ids wherever
they can, so most blocks need no redaction at all.

## What changed and why this needs a live tenant

The branch adds reading and writing the PIM settings of a Microsoft Entra directory role, as two
cmdlets and an apply-document section. Commits are named by SUBJECT, never by hash: the hashes
change when the branch is rebased onto `main` before it merges.

- **A. `Get-OERDirectoryRoleManagementPolicy` reads a directory role's PIM policy** ("feat: resolve a
  directory role name to its role definition id", "feat: Get-OERDirectoryRoleManagementPolicy reads
  the PIM settings of a directory role", "fix: refuse a group policy id on the directory-role policy
  read"). `-Role` takes a display name or a role definition id: a GUID is used as it stands, with no
  Graph call; a name is looked up in `v1.0/roleManagement/directory/roleDefinitions` -- no match is
  `RoleDefinitionNotFound`, a refused lookup `RoleDefinitionReadFailed` (never "not found"), more
  than one match `AmbiguousRoleName`. The policy comes from
  `v1.0/policies/roleManagementPolicyAssignments` (scope `/`, scope type `DirectoryRole`, policy and
  rules expanded): none is `PolicyNotFound`, a refused read `PolicyReadFailed`. `-PolicyId` reads one
  policy directly; a value starting with `/` (an Azure Resource Manager id) or holding `/`, `?`, `#`
  or whitespace is `InvalidPolicyId` before any call, and a PIM for Groups policy id is refused as
  `InvalidPolicyId` after the read. `-All` reads every directory role's policy in one paged list, plus
  one role-definition list for `RoleName`. The output is the same `Omnicit.EntraRBAC.RoleManagementPolicy`
  object the Azure cmdlet returns, with `Scope` `/`, `RoleName` the name as typed (empty for a GUID),
  and approvers read through the one Graph approver reader, `ConvertFrom-OERGraphApprover`.
- **B. `Set-OERDirectoryRoleManagementPolicy` writes it** ("refactor: give the PIM rule-patch builder
  and policy projection a Graph mode", "feat: Set-OERDirectoryRoleManagementPolicy updates the PIM
  settings of a directory role", "fix: refuse a malformed policy id before any approver lookup",
  "refactor: one owner for the Graph approver semantics of the PIM policy cmdlets"). The parameters of
  `Set-OERRoleManagementPolicy` without the Azure scope ones. The live rules are read, the Azure rule
  builder overlays the settings (in a Graph mode whose default keeps the Azure behaviour exactly), and
  each rule that changed is PATCHed on its own to
  `v1.0/policies/roleManagementPolicies/{id}/rules/{ruleId}` after ONE confirmation. Approvers go out
  in the v1.0 shape -- `@odata.type` plus `userId` or `groupId` -- and follow the Graph semantics of
  `Set-OERGroupPimPolicy`: a bound side replaces that side only, an explicit empty list clears it, the
  unbound side and any other kind of approver are carried from the live stage, supplying approvers
  implies approval, and approval with no approver left is `ApproverRequired`. `-RequireApproval
  $false` alone leaves the live approvers on the stage. Asking for MFA on activation and an
  authentication context together is `InvalidPolicyChange` ("PIM", not "Azure PIM"); asking for one
  clears the other with a warning, and the two rules are PATCHed in the order Graph accepts: a context
  being DISABLED before the activation rule, one being ENABLED after it. A rule Graph rejects does not
  stop the others (`PolicyRulesRejected`, after the object); nothing to change is `NoChange`; no
  setting at all is `NothingToUpdate`. `-AuthenticationContextId` is checked for its `c<number>`
  shape only.
- **C. Tab completion** ("feat: tab-complete built-in directory role names on the directory-role
  policy cmdlets"). `-Role` completes the built-in directory role names, offline; any other name or
  id still binds.
- **D. The apply document** ("feat: diff only the declared approver side on request", "feat:
  directoryRoleManagementPolicies section in the apply document", "fix: converge a declared empty
  approver side on directory-role policies", "docs: name the directory-role section wherever the
  document sections are listed"). `directoryRoleManagementPolicies[]` takes the fields of a
  `roleManagementPolicies[]` item without `scope`; `role` is required, and an unknown key -- `scope`
  included -- is a validation Warning. The section runs after `accessReviews` and before
  `roleAssignments`, never asks for an ARM token by itself, and has no prune. Declared approvers are
  resolved to object ids before the diff; only a DECLARED approver side is sent, and a side declared
  `[]` clears that side and then converges.
- **E. Permissions and docs** ("test: split the PIM policy scope rule so directory-role paths need
  directory permissions", "docs: complete the new-function checklist and correct the source gate
  count"). `Get-OERRequiredScope` names the directory permissions for the new paths.

**Every unit test on this branch mocks the transport.** They prove the module's decisions given the
shapes the tests assume. They cannot prove the six things this file is for:

1. That Microsoft Graph v1.0 ACCEPTS a directory-role rule PATCHed on its own with approvers in the
   `userId`/`groupId` shape, and returns them in the shape the reader assumes -- which fields come
   back per approver is measured, not assumed (checks 2.2, 2.3).
2. That the live approvers carried back unchanged -- as Graph returned them -- are accepted in a
   PATCH (2.7), and that a bound side replaces that side only (2.6).
3. That a document naming approvers by UPN and group name converges -- `Unchanged` on the second run
   -- and that a declared side, and a side declared EMPTY, converge too (section 3).
4. That Graph's asymmetric MFA / authentication-context validation is met by the module's PATCH order
   in both directions, directly and through a document (section 4).
5. That the Azure path still converges through the helpers this branch changed, and that a mixed
   document runs the directory section before the Azure one (section 5).
6. That a real refusal reaches the operator as `RoleDefinitionReadFailed` or `PolicyReadFailed`,
   never as "not found" (section 6).

## What this file does not check, and why

- **An activation that actually goes through approval.** The test users are created DISABLED, and an
  activation request, an approver's decision and PIM's own notification flow are the platform's
  behaviour, not the module's. Nothing in this branch changes how PIM runs an approval.
- **A custom directory role.** It resolves through the same `displayName` query and is read and
  written through the same paths; the suites of `Resolve-OERDirectoryRoleDefinitionId` and both
  cmdlets pin it. Creating one needs the portal and adds no module path.
- **`AmbiguousRoleName`.** It needs two role definitions with one display name, which only a custom
  role can produce. Unit-pinned in both cmdlets' suites and in `AmbiguousName.Guard.Tests.ps1`.
- **`PolicyNotFound`, and a PIM for Groups policy id on `-PolicyId`.** Graph lists a policy for every
  directory role, and this step creates no PIM group. Both unit-pinned in the Get and Set suites.
- **Notification rules (`-NotificationRule`).** The same `New-OERPolicyNotificationRule` objects and
  the same builder code as the Azure path, unit-pinned there and in the Set suite; a live change would
  mail real recipients.
- **A rule Graph rejects (`PolicyRulesRejected`).** It cannot be provoked on demand without an input
  Graph refuses that the module's own guards do not refuse first. Unit-pinned. Checks 2.2, 2.4, 2.7
  and 4.2 record it if Graph does refuse something.
- **An untouched MFA plus authentication-context combination, left alone by an unrelated change.**
  Producing it needs a raw PATCH outside the module (Graph accepts enabling a context while MFA is
  on). Unit-pinned in the Set suite.
- **The Azure path's own empty approver side.** A `roleManagementPolicies[]` item declaring
  `"groups": []` is still compared as one null entry and never converges; that is known, recorded as a
  finding outside this step and deliberately unchanged here. Section 5 declares no empty side.
- **Tenant-scoped versus administrative-unit-scoped policies.** Graph lists directory-role policies
  at scope `/` only; there is nothing else to address.
- **That the engine asks for no ARM token for a directory-only document.** Every sign-in here already
  holds one (`Connect-OER -IncludeARM`), so it cannot be seen live. Pinned in the
  `Invoke-OERStructure` suite.
- **`Get-OERInventory` and `Export-OERInventory`.** The section is apply-only in this step; the
  inventory does not emit it yet.

---

## Setup, once

**You need:**

- A **test tenant** -- never a customer tenant -- with Microsoft Entra ID P2 or ID Governance
  licensing (PIM for Microsoft Entra roles), its tenant id, one verified domain, and one **test
  subscription**. A Tenant Profile alias for it (`Get-OERConfiguration`) is optional: every sign-in
  names the tenant id, and a profile that exists on the machine running this file must name that same
  tenant and the commercial cloud, or nothing runs.
- The **dedicated certificate identity** `oer-live-cc` ([README.md](README.md), first paragraph):
  an app whose only credential is a non-exportable certificate in `Cert:\CurrentUser\My`, with the
  Microsoft Graph application permissions and the Owner role on the test subscription that the
  operator's identity script grants. This file needs, from that grant list,
  `RoleManagement.ReadWrite.Directory` (role definitions and policy reads),
  `RoleManagementPolicy.ReadWrite.Directory` (the rule PATCH), `AuthenticationContext.Read.All`
  (check 4.1), `User.ReadWrite.All`, `Group.ReadWrite.All`, `Application.Read.All` and
  `Organization.Read.All` (the prerequisite script and the identity check), and the Owner role on the
  test subscription (section 5). Every sign-in below is app-only, as that identity -- never
  interactive, never a device code, never a cached context and never a person's account. **The
  operator enables it for the run and disables it right after**; a sign-in answering "application is
  disabled" means it was not enabled: stop there. Its application permissions need no role
  activation.
- For check 6.1 only: the second app `oer-live-cc-noperm` -- the same certificate, no API permission
  and no role.
- The prerequisite script `Initialize-OerS63Prereq.ps1`. It is kept OUTSIDE this repository and is
  never committed; it signs in as the certificate identity, and never runs in CI.
- PowerShell 7 and a clone of this repository on this branch.

**Stop conditions -- for every check below.** Stop, record what happened and do not go around it,
when any of these is true: a command, a document or a plan names a target without the prefix
`oer-s63` other than the two roles above and the Reader policy at `oer-s63-rg`; any directory role
other than Reports Reader and Message Center Reader appears in a target; an object shows up that the
prerequisite script did not create; an identity line prints `False`; or a request on the app path
answers 401, 403 or `Authorization_RequestDenied` anywhere except check 6.1, where a refusal is the
point. A refusal means the certificate identity lacks a permission: name the missing permission,
never finish the step with another sign-in.

**Variables, build and module path.** Paste into one PowerShell 7 window and keep that window for
the whole file.

```powershell
$Repo        = '<your-clone-of-Omnicit.EntraRBAC>'   # the clone whose origin is github.com/Omnicit/Omnicit.EntraRBAC
$Prereq      = '<path-to-Initialize-OerS63Prereq.ps1>'
$Alias       = '<your-test-tenant-alias>'
$OrgName     = '<your-test-tenant-display-name>'   # the organization display name, exactly as Graph reports it
$SubId       = '<your-test-subscription-id>'   # the subscription where the certificate identity is Owner
$Domain      = '<your-verified-domain>'
$TenantId    = '<your-test-tenant-id>'
$AppId       = '<oer-live-cc-application-id>'
$NoPermAppId = '<oer-live-cc-noperm-application-id>'
$Thumbprint  = '<certificate-thumbprint>'   # in Cert:\CurrentUser\My; never exported, its key never read
$Prefix      = 'oer-s63'
$ApproverUpn   = "$Prefix-approver@$Domain"
$Approver2Upn  = "$Prefix-approver2@$Domain"
$ApproversName = "$Prefix-approvers"
$RoleRR  = 'Reports Reader'          # the ONLY two directory roles this file names
$RoleMCR = 'Message Center Reader'
$RgScope = "/subscriptions/$SubId/resourceGroups/$Prefix-rg"
$Raw     = Join-Path $Repo 'docs/live-verification/raw/s63'
$BaselinePath = Join-Path $Raw 'baseline-directory-policies.json'   # written by the prerequisite script
$ReaderRecordPath = Join-Path $Raw 'baseline-azure-reader-policy.json'   # written by the prerequisite script

Set-Location $Repo
git remote get-url origin
git branch --show-current
# Build in a process of its own. ModuleBuilder fills every Build-Module parameter build.yaml leaves
# unset from a variable of the same name in the calling session, so the $Prefix above would be
# written into the top of the built module, and importing it would run 'oer-s63' as a command.
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

**Create the test objects and record the two policies.** The script runs in its own process, so this
window keeps its own sign-in. It signs in three times, every time app-only as the certificate
identity: `Connect-OER` first, only to identify the tenant and read the subscription; then Microsoft
Graph for Phase 1 (after `Disconnect-OER` and `Disconnect-MgGraph`: `Connect-OER` leaves its raw
access token in the Graph SDK's process cache, which a later `Connect-MgGraph` would otherwise try to
read as an MSAL cache); then `Connect-OER` again for Phase 2. After EVERY sign-in it checks the
identity and prints it as True/False only -- `identity check: session app id is oer-live-cc: True` and
`identity check: tenant is the test tenant: True` -- and a `False` stops it before anything is
written. Before its first write it identifies the tenant positively: the organization's display name
must equal `-ExpectedTenantDisplayName` EXACTLY, `-UserDomain` must be one of its verified domains,
and `-TenantId` must be the organization's id; a Tenant Profile for the alias, when one exists on the
machine, must name the same tenant. It then reads the subscription through the module and stops
unless exactly one subscription with that id and a display name comes back. Only then would it ask
once for confirmation; with `-Unattended` -- a run with no operator at the keyboard -- it says instead
that the question is not asked, since both checks passed. Every later sign-in must land in that same
organization too. It ends with a summary of names and REAL object ids -- redact those before pasting
(check 0.2). It is idempotent: a second run creates nothing that exists and only fills in what is
missing. Read the `-WhatIf` plan first: every target must carry the prefix `oer-s63`, apart from the
baseline file and the Reader record it would write.

```powershell
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -ModulePath $ModulePsd1 -WhatIf
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -ModulePath $ModulePsd1 -Unattended
```

What it creates, all named with the prefix: two DISABLED users `oer-s63-approver` and
`oer-s63-approver2` on your domain (display names `OER S63 Approver` and `OER S63 Approver2`, random
passwords never printed); the security group `oer-s63-approvers` with `oer-s63-approver` as its only
member; and the resource group `oer-s63-rg`, tagged `purpose = oer-s63-live-verification`, with
nothing assigned at it, whose Reader role management policy is this file's Azure regression policy.
A resource group deleted and created again under the same name gets its Reader policy back as it was
left, so the script checks that policy after creating or finding the resource group, against the
**Reader record** `raw/s63/baseline-azure-reader-policy.json`. When there is no record yet, the policy
must be at its defaults -- approval off, no approver; leftovers are reported approver by approver
and, with `-Unattended` on the test's own resource group, restored at once -- activation hours other
than 8 (the Azure default) are warned about, and then its raw rule set is written to the record.
When the record exists, the script compares the live policy with it -- activation hours, approval
and approvers, and every rule by id -- and, with `-Unattended` on the test's own resource group,
restores the recorded rule set at once. Its teardown restores the policy IN FULL from that record
before it deletes the resource group. A read of an object the script has just created is retried on
a 404.

What it records: the two directory roles are FIXED in the script, and it refuses any other name. It
resolves each by display name (exactly one built-in role definition) and reads its policy through
`v1.0/policies/roleManagementPolicyAssignments` (exactly one assignment at scope `/`). When the
baseline file `raw/s63/baseline-directory-policies.json` does not exist, it writes the raw rules of
both policies there. When it exists, it compares every live rule with the file and reports each rule
that differs, per role -- and never restores a directory-role policy in a setup run, not even with
`-Unattended`: only `-Teardown` does. It refuses to run while a user
`oer-s63-nobody@<your-verified-domain>` exists (check 2.1 relies on that name resolving to nothing).

**Sign in.**

```powershell
Import-Module Omnicit.EntraRBAC -Force
$ErrorActionPreference = 'Continue'   # module code reads the GLOBAL preference; Stop would end a run at its first Failed row
# App-only, as the certificate identity. The certificate's private key is used, never read out.
$null = Connect-OER -TenantId $TenantId -ClientId $AppId -Certificate (Get-Item -LiteralPath "Cert:\CurrentUser\My\$Thumbprint") -IncludeARM -ErrorAction Stop
# The identity check, BEFORE anything else: printed as True/False, never as the ids. The client and
# tenant ids come from the claims of the token Connect-OER obtained; the service principal's display
# name is read so a client id of some other app cannot pass.
$S63Context = Get-MgContext
try {
    $S63Sp = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop -Uri "v1.0/servicePrincipals(appId='$AppId')?`$select=displayName"
} catch {
    Write-Host "--- reading the session's own service principal FAILED: $($PSItem.Exception.Message)"
    $global:Error.Clear()
}
$S63AppOk    = ([string]$S63Context.ClientId -eq $AppId) -and ([string]$S63Sp.displayName -ceq 'oer-live-cc')
$S63TenantOk = ([string]$S63Context.TenantId -eq $TenantId)
Write-Host "identity check: session app id is oer-live-cc: $S63AppOk"
Write-Host "identity check: tenant is the test tenant: $S63TenantOk"
if (-not ($S63AppOk -and $S63TenantOk)) { throw 'The identity check failed: nothing below may run.' }
```

**The helpers.** Paste this block as it stands. The raw reads use `Invoke-MgGraphRequest` on the
Microsoft Graph context `Connect-OER` set up: independent of the module's own read and write code,
and the same query the prerequisite script used for the baseline file, so the rules compare shape for
shape. The Reader policy at `oer-s63-rg` is read raw the way the script reads it for the Reader
record: through the module's own Azure Resource Manager transport, inside the module's scope. Rules
are compared exactly as the script compares them: key order and list order ignored, an absent
property and a null one the same, and a `claimValue` of `''` the same as null.

```powershell
function Get-S63Name {
    # A test object's name for an object id, so the output names objects instead of printing ids.
    # Filled from 0.3's ids; anything else prints as <not a test object>.
    param([AllowNull()][string]$Id)
    if (-not $Id) { return '<no id>' }
    if ($IdApprover -and $Id -eq $IdApprover) { return "$Prefix-approver" }
    if ($IdApprover2 -and $Id -eq $IdApprover2) { return "$Prefix-approver2" }
    if ($IdApprovers -and $Id -eq $IdApprovers) { return "$Prefix-approvers" }
    '<not a test object>'
}

function Get-S63PolicyName {
    # The role a Microsoft Graph policy id belongs to, from 0.3's policy ids.
    param([AllowNull()][string]$PolicyId)
    if ($PolicyIdRR -and $PolicyId -eq $PolicyIdRR) { return $RoleRR }
    if ($PolicyIdMCR -and $PolicyId -eq $PolicyIdMCR) { return $RoleMCR }
    '<another policy>'
}

function Get-S63RoleName {
    # The role a role definition id belongs to, from 0.3's role definition ids.
    param([AllowNull()][string]$RoleDefinitionId)
    if (-not $RoleDefinitionId) { return '(empty)' }
    if ($RoleIdRR -and $RoleDefinitionId -eq $RoleIdRR) { return $RoleRR }
    if ($RoleIdMCR -and $RoleDefinitionId -eq $RoleIdMCR) { return $RoleMCR }
    '<another role>'
}

function Format-S63Request {
    # One transport verbose line as method and path, with every object id replaced: a directory-role
    # policy id by its role's name, anything GUID-shaped by <id>, and the query string dropped. The
    # transports write the method and the uri only -- never a body or a header -- to that stream.
    param([string]$Message)
    if ($Message -cnotmatch '^\[Invoke-OER(Graph|Arm)Request\] (?<M>GET|POST|PATCH|PUT|DELETE) (?<U>\S+)') { return }
    $Method = $Matches['M']
    $Path = (($Matches['U'] -replace '^https://[^/]+/', '') -split '\?')[0]
    $Path = $Path -replace 'v1\.0/policies/roleManagementPolicies/(?<P>[^/]+)', { 'v1.0/policies/roleManagementPolicies/<' + (Get-S63PolicyName $_.Groups['P'].Value) + '>' }
    $Path = $Path -replace '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '<id>'
    "$Method $Path"
}

function Show-S63Error {
    # Prints the error id and message of each record the named cmdlet PUBLISHED -- never the record
    # itself: a raw transport record can carry the bearer token (README.md, "Credentials"). Records
    # collected from nested calls are counted, not shown.
    param([object[]]$Record, [Parameter(Mandatory)][string]$Cmdlet)
    $All = @($Record | Where-Object { $null -ne $_ })
    $Published = @($All | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains $Cmdlet })
    Write-Host "--- errors published by $($Cmdlet): $($Published.Count) (other records collected, not shown: $($All.Count - $Published.Count))"
    $Published | ForEach-Object { Write-Host "    ERROR [$($_.FullyQualifiedErrorId)]: $($_.Exception.Message)" }
}

function Invoke-S63Call {
    # Runs ONE module cmdlet with -Verbose captured, and prints what it did: every Microsoft Graph and
    # Azure Resource Manager request in the order sent (Format-S63Request), every warning, the error
    # id and message of every error it published (Show-S63Error), and how many objects it returned --
    # kept in $S63Out. A What if: line is PowerShell's own and appears on the console before this.
    param(
        [Parameter(Mandatory)][string]$Cmdlet,
        [Parameter(Mandatory)][hashtable]$Splat,
        [object]$InputObject,
        [Parameter(Mandatory)][string]$Label
    )
    $Call = $Splat + @{ Verbose = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CallError' }
    $Out = if ($PSBoundParameters.ContainsKey('InputObject')) {
        @($InputObject | & $Cmdlet @Call 3>&1 4>&1)
    } else {
        @(& $Cmdlet @Call 3>&1 4>&1)
    }
    $Requests = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
            ForEach-Object { Format-S63Request -Message $_.Message } | Where-Object { $_ })
    $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $global:S63Out = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-Host "=== $Label -- $Cmdlet"
    Write-Host "--- requests, in the order sent: $($Requests.Count)"
    $Requests | ForEach-Object { Write-Host "    $_" }
    Write-Host "--- warnings: $($Warnings.Count)"
    $Warnings | ForEach-Object { Write-Host "    WARNING: $($_.Message)" }
    Show-S63Error -Record $CallError -Cmdlet $Cmdlet
    Write-Host "--- objects returned: $($S63Out.Count)"
}

function Show-S63ModuleApprover {
    # The Approvers of a module policy object, by test-object name, never by id. With -ExpectUser /
    # -ExpectGroup (object ids), one more line: are they exactly that set?
    param([Parameter(Mandatory)][object]$Policy, [string[]]$ExpectUser, [string[]]$ExpectGroup)
    $A = @($Policy.Approvers | Where-Object { $null -ne $_ })
    Write-Host "    approvers: $($A.Count)"
    foreach ($X in $A) {
        Write-Host ('      {0} {1}; DisplayName filled: {2}' -f $X.UserType, (Get-S63Name $X.Id), (-not [string]::IsNullOrEmpty([string]$X.DisplayName)))
    }
    if ($PSBoundParameters.ContainsKey('ExpectUser') -or $PSBoundParameters.ContainsKey('ExpectGroup')) {
        $Got = (@($A | ForEach-Object { '{0}|{1}' -f $_.UserType, ([string]$_.Id).ToLowerInvariant() }) | Sort-Object) -join ';'
        $Want = (@(@($ExpectUser | Where-Object { $_ } | ForEach-Object { "User|$($_.ToLowerInvariant())" }) +
                @($ExpectGroup | Where-Object { $_ } | ForEach-Object { "Group|$($_.ToLowerInvariant())" })) | Sort-Object) -join ';'
        Write-Host "    approvers are exactly the expected set: $($Got -ceq $Want)"
    }
}

function Show-S63Policy {
    # One module directory-role policy object, named instead of printed by id: whose policy it is
    # (0.3's ids), its scope, role name and role definition, the settings the checks change, and its
    # approvers (Show-S63ModuleApprover, which -ExpectUser and -ExpectGroup are passed to).
    param([AllowNull()][object]$Policy, [string]$Label = 'policy', [string[]]$ExpectUser, [string[]]$ExpectGroup)
    if ($null -eq $Policy) { Write-Host "--- $($Label): no object"; return }
    $Changed = if ($Policy.PSObject.Properties['ChangedRuleIds']) { '; ChangedRuleIds [' + (@($Policy.ChangedRuleIds) -join ', ') + ']' } else { '' }
    Write-Host ("--- {0}: policy of {1}; Scope '{2}'; RoleName '{3}'; RoleDefinitionId: {4}{5}" -f $Label, (Get-S63PolicyName $Policy.PolicyId),
        $Policy.Scope, $Policy.RoleName, (Get-S63RoleName $Policy.RoleDefinitionId), $Changed)
    Write-Host ("    ActivationMaxHours {0}; on activation: MFA {1}, justification {2}, ticket {3}; AuthenticationContextId '{4}'" -f
        $Policy.ActivationMaxHours, $Policy.RequireMfaOnActivation, $Policy.RequireJustificationOnActivation, $Policy.RequireTicketOnActivation, $Policy.AuthenticationContextId)
    Write-Host ("    eligible: permanent allowed {0}, {1}; active: permanent allowed {2}, {3}; on active assignment: MFA {4}, justification {5}" -f
        $Policy.AllowPermanentEligibility, $Policy.EligibleDuration, $Policy.AllowPermanentActiveAssignment, $Policy.ActiveDuration,
        $Policy.RequireMfaOnActiveAssignment, $Policy.RequireJustificationOnActiveAssignment)
    Write-Host "    RequireApproval $($Policy.RequireApproval)"
    $Pass = @{ Policy = $Policy }
    if ($PSBoundParameters.ContainsKey('ExpectUser')) { $Pass.ExpectUser = $ExpectUser }
    if ($PSBoundParameters.ContainsKey('ExpectGroup')) { $Pass.ExpectGroup = $ExpectGroup }
    Show-S63ModuleApprover @Pass
}

function Get-S63ModuleView {
    # The settings of one module policy object that T.4 compares with 1.1.
    param([Parameter(Mandatory)][object]$Policy)
    [ordered]@{
        PolicyId                               = [string]$Policy.PolicyId
        ActivationMaxHours                     = $Policy.ActivationMaxHours
        RequireMfaOnActivation                 = $Policy.RequireMfaOnActivation
        RequireJustificationOnActivation       = $Policy.RequireJustificationOnActivation
        RequireTicketOnActivation              = $Policy.RequireTicketOnActivation
        RequireApproval                        = $Policy.RequireApproval
        ApproverCount                          = @($Policy.Approvers | Where-Object { $null -ne $_ }).Count
        AuthenticationContextId                = [string]$Policy.AuthenticationContextId
        AllowPermanentEligibility              = $Policy.AllowPermanentEligibility
        EligibleDuration                       = $Policy.EligibleDuration
        AllowPermanentActiveAssignment         = $Policy.AllowPermanentActiveAssignment
        ActiveDuration                         = $Policy.ActiveDuration
        RequireMfaOnActiveAssignment           = $Policy.RequireMfaOnActiveAssignment
        RequireJustificationOnActiveAssignment = $Policy.RequireJustificationOnActiveAssignment
    }
}

function Get-S63RawUser {
    # One user by user principal name, straight from Microsoft Graph v1.0 (the module has no user
    # read): its id and whether the account is enabled. A failure prints its message only and clears
    # $Error: a raw Invoke-MgGraphRequest error record carries the bearer token.
    param([Parameter(Mandatory)][string]$Upn)
    $F = [uri]::EscapeDataString("userPrincipalName eq '$Upn'")
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/users?`$filter=$F&`$select=id,accountEnabled"
    } catch {
        Write-Host "--- raw user read FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    $U = @($R['value'] | Where-Object { $null -ne $_ })
    if ($U.Count -ne 1) { Write-Host "--- raw user read: $($U.Count) users match, not one"; return }
    [PSCustomObject]@{ Id = [string]$U[0]['id']; AccountEnabled = [bool]$U[0]['accountEnabled'] }
}

function Get-S63RawRoleDefinitionId {
    # A built-in directory role's definition id, read at run time straight from Microsoft Graph v1.0
    # -- never typed: exactly one built-in role definition with exactly this display name, or nothing.
    param([Parameter(Mandatory)][string]$Name)
    $F = [uri]::EscapeDataString("displayName eq '$Name'")
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=$F&`$select=id,displayName,isBuiltIn"
    } catch {
        Write-Host "--- raw role definition read FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    $D = @($R['value'] | Where-Object { $null -ne $_ -and [string]$_['displayName'] -ceq $Name })
    if ($D.Count -ne 1 -or -not [bool]$D[0]['isBuiltIn']) { Write-Host "--- '$Name': $($D.Count) role definition(s) with exactly that name, or not built-in"; return }
    [string]$D[0]['id']
}

function Get-S63RawPolicy {
    # The policy of one directory role straight from Microsoft Graph v1.0, through the same query the
    # prerequisite script used for the baseline file (the assignment at scope '/', the policy and its
    # rules expanded). Saved to the raw folder as <Label>.json.
    param([Parameter(Mandatory)][string]$RoleDefinitionId, [Parameter(Mandatory)][string]$Label)
    $F = [uri]::EscapeDataString("scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$RoleDefinitionId'")
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop `
            -Uri "v1.0/policies/roleManagementPolicyAssignments?`$filter=$F&`$expand=policy(`$expand=rules)"
    } catch {
        Write-Host "--- $($Label): raw read FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    $Assignments = @($R['value'] | Where-Object { $null -ne $_ })
    if ($Assignments.Count -ne 1) { Write-Host "--- $($Label): $($Assignments.Count) policy assignment(s) for this role, not one"; return }
    $Rules = @($Assignments[0]['policy']['rules'] | Where-Object { $null -ne $_ })
    ConvertTo-Json -InputObject $Rules -Depth 30 | Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    [PSCustomObject]@{ PolicyId = [string]$Assignments[0]['policyId']; Rules = $Rules }
}

function Get-S63RawRule {
    # One policy rule straight from Microsoft Graph v1.0, outside the module. Saved as <Label>.json.
    param([Parameter(Mandatory)][string]$PolicyId, [Parameter(Mandatory)][string]$RuleId, [Parameter(Mandatory)][string]$Label)
    try {
        $Rule = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/policies/roleManagementPolicies/$PolicyId/rules/$RuleId"
    } catch {
        Write-Host "--- $($Label): raw read FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    ConvertTo-Json -InputObject $Rule -Depth 30 | Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    $Rule
}

function Show-S63RawApproval {
    # The Approval_EndUser_Assignment rule of one policy as Graph v1.0 returns it: the requirement,
    # the mode, the stage count, the first stage's timeout and approver justification, and for every
    # primary approver the NAMES of the fields Graph returned and which of them are filled -- never
    # the ids themselves, which are named as test objects instead.
    param([Parameter(Mandatory)][string]$PolicyId, [Parameter(Mandatory)][string]$Label)
    $Rule = Get-S63RawRule -PolicyId $PolicyId -RuleId 'Approval_EndUser_Assignment' -Label $Label
    if (-not $Rule) { return }
    $Setting = $Rule['setting']
    $Stages = @($Setting['approvalStages'] | Where-Object { $null -ne $_ })
    $Stage = $Stages | Select-Object -First 1
    Write-Host ('--- {0}: policy of {1}, isApprovalRequired = {2}, approvalMode = {3}, stages = {4}, stage 1 timeout = {5} day(s), approver justification = {6}' -f
        $Label, (Get-S63PolicyName $PolicyId), $Setting['isApprovalRequired'], $Setting['approvalMode'], $Stages.Count,
        $(if ($Stage) { $Stage['approvalStageTimeOutInDays'] } else { '(no stage)' }), $(if ($Stage) { $Stage['isApproverJustificationRequired'] } else { '(no stage)' }))
    $Primary = @(if ($Stage) { $Stage['primaryApprovers'] | Where-Object { $null -ne $_ } })
    Write-Host "    primary approvers: $($Primary.Count)"
    foreach ($A in $Primary) {
        $UserId = [string]$A['userId']; $GroupId = [string]$A['groupId']; $RawId = [string]$A['id']
        $Who = if ($UserId) { Get-S63Name $UserId } elseif ($GroupId) { Get-S63Name $GroupId } elseif ($RawId) { Get-S63Name $RawId } else { '<no id field>' }
        Write-Host ('    {0}: fields [{1}]' -f $A['@odata.type'], ((@($A.Keys | ForEach-Object { [string]$_ }) | Sort-Object) -join ', '))
        Write-Host ('      userId filled {0}, groupId filled {1}, id filled {2}; names {3}; description filled {4}; isBackup {5}' -f
            [bool]$UserId, [bool]$GroupId, [bool]$RawId, $Who, (-not [string]::IsNullOrEmpty([string]$A['description'])), $A['isBackup'])
    }
}

function Show-S63RawSettings {
    # The rules the checks change, as Microsoft Graph v1.0 returns them (Get-S63RawPolicy).
    param([Parameter(Mandatory)][string]$RoleDefinitionId, [Parameter(Mandatory)][string]$Label)
    $P = Get-S63RawPolicy -RoleDefinitionId $RoleDefinitionId -Label $Label
    if (-not $P) { return }
    $ById = @{}
    foreach ($Rule in $P.Rules) { $ById[[string]$Rule['id']] = $Rule }
    $Get = { param($RuleId, $Key) if ($ById.ContainsKey($RuleId)) { $ById[$RuleId][$Key] } else { '(no rule)' } }
    $Claim = & $Get 'AuthenticationContext_EndUser_Assignment' 'claimValue'
    $Setting = & $Get 'Approval_EndUser_Assignment' 'setting'
    Write-Host ('--- {0}: policy of {1}' -f $Label, (Get-S63PolicyName $P.PolicyId))
    Write-Host ('    Expiration_EndUser_Assignment: maximumDuration {0}' -f (& $Get 'Expiration_EndUser_Assignment' 'maximumDuration'))
    Write-Host ('    Enablement_EndUser_Assignment: enabledRules [{0}]' -f ((@(& $Get 'Enablement_EndUser_Assignment' 'enabledRules') | Sort-Object) -join ', '))
    Write-Host ('    AuthenticationContext_EndUser_Assignment: isEnabled {0}, claimValue {1}' -f
        (& $Get 'AuthenticationContext_EndUser_Assignment' 'isEnabled'), $(if ($null -eq $Claim) { '(null)' } else { "'$Claim'" }))
    Write-Host ('    Expiration_Admin_Eligibility: isExpirationRequired {0}, maximumDuration {1}' -f
        (& $Get 'Expiration_Admin_Eligibility' 'isExpirationRequired'), (& $Get 'Expiration_Admin_Eligibility' 'maximumDuration'))
    Write-Host ('    Expiration_Admin_Assignment: isExpirationRequired {0}, maximumDuration {1}' -f
        (& $Get 'Expiration_Admin_Assignment' 'isExpirationRequired'), (& $Get 'Expiration_Admin_Assignment' 'maximumDuration'))
    Write-Host ('    Approval_EndUser_Assignment: isApprovalRequired {0}' -f $(if ($Setting -is [System.Collections.IDictionary]) { $Setting['isApprovalRequired'] } else { '(no setting)' }))
}

function ConvertTo-S63Canonical {
    # The same comparison the prerequisite script makes: every dictionary's keys sorted and every list
    # sorted by its own canonical JSON, so two reads of one rule compare equal whatever the key order
    # and whatever the order of enabledRules, recipients or approvers. '@odata.context' is dropped. Two
    # spellings of "no value" compare as one, exactly as in the script: a property whose value is null
    # is dropped (null and absent are the same), and a claimValue of '' is read as null -- the module
    # disables an authentication context by sending '' and reads null and '' alike.
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $Out = [ordered]@{}
        $Keys = @($Value.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -notmatch '@odata\.context$' } | Sort-Object -CaseSensitive)
        foreach ($Key in $Keys) {
            $Item = $Value[$Key]
            if ($Key -ceq 'claimValue' -and $Item -is [string] -and $Item.Length -eq 0) { $Item = $null }
            if ($null -eq $Item) { continue }
            $Out[$Key] = ConvertTo-S63Canonical -Value $Item
        }
        return $Out
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $Out = [ordered]@{}
        foreach ($Key in @($Value.PSObject.Properties.Name | Where-Object { $_ -notmatch '@odata\.context$' } | Sort-Object -CaseSensitive)) {
            $Item = $Value.$Key
            if ($Key -ceq 'claimValue' -and $Item -is [string] -and $Item.Length -eq 0) { $Item = $null }
            if ($null -eq $Item) { continue }
            $Out[$Key] = ConvertTo-S63Canonical -Value $Item
        }
        return $Out
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Value) { $Items.Add((ConvertTo-S63Canonical -Value $Item)) }
        $Sorted = @($Items | Sort-Object -Property { ConvertTo-Json -InputObject $_ -Depth 50 -Compress })
        return , $Sorted
    }
    return $Value
}

function Get-S63RuleText {
    param([AllowNull()][object]$Rule)
    ConvertTo-Json -InputObject (ConvertTo-S63Canonical -Value $Rule) -Depth 50 -Compress
}

function Get-S63RuleDiff {
    # The id of every rule whose content differs between a live and a baseline rule set, in the
    # baseline's order, then any rule only the live set has.
    param([object[]]$Live, [object[]]$Baseline)
    $LiveById = @{}
    foreach ($Rule in @($Live | Where-Object { $null -ne $_ })) { $LiveById[[string]$Rule['id']] = Get-S63RuleText -Rule $Rule }
    $BaseById = [ordered]@{}
    foreach ($Rule in @($Baseline | Where-Object { $null -ne $_ })) { $BaseById[[string]$Rule['id']] = Get-S63RuleText -Rule $Rule }
    $Ids = @(@($BaseById.Keys) + @($LiveById.Keys | Where-Object { -not $BaseById.Contains($_) }))
    foreach ($Id in $Ids) { if ([string]$LiveById[$Id] -cne [string]$BaseById[$Id]) { $Id } }
}

function Get-S63Baseline {
    # The baseline file the prerequisite script wrote, read back from disk.
    Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json -AsHashtable
}

function Show-S63BaselineDiff {
    # Every rule of the two directory-role policies that differs from the baseline file, read raw
    # (Get-S63RawPolicy) and compared as the prerequisite script compares.
    param([Parameter(Mandatory)][string]$Label)
    $Base = Get-S63Baseline
    foreach ($Entry in @($Base['roles'] | Where-Object { $null -ne $_ })) {
        $Name = [string]$Entry['displayName']
        $Live = Get-S63RawPolicy -RoleDefinitionId ([string]$Entry['roleDefinitionId']) -Label ('{0}-{1}-raw' -f $Label, ($Name -replace ' ', '-'))
        if (-not $Live) { continue }
        $Diff = @(Get-S63RuleDiff -Live $Live.Rules -Baseline @($Entry['rules']))
        Write-Host ('--- {0}: {1}: the baseline names this policy: {2}; rules live {3}, baseline {4}; differing from the baseline: {5}{6}' -f
            $Label, $Name, ([string]$Entry['policyId'] -eq $Live.PolicyId), @($Live.Rules).Count, @($Entry['rules']).Count, $Diff.Count,
            $(if ($Diff.Count) { ' (' + ($Diff -join ', ') + ')' } else { '' }))
    }
}

function Show-S63ReaderRecordDiff {
    # The Reader policy at oer-s63-rg against the Reader record the prerequisite script wrote: whether
    # the record names this policy, and every rule that differs, compared as the script compares. The
    # raw rules are read through the module's own Azure Resource Manager transport inside the module's
    # scope -- as the script reads them for the record -- since the module has no public read that
    # returns raw rules and this file signs in to no Az module. Saved as <Label>-reader-raw.json.
    param([Parameter(Mandatory)][string]$Label)
    try {
        $Record = Get-Content -LiteralPath $ReaderRecordPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable
        $Policy = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
        $Json = & (Get-Module Omnicit.EntraRBAC) {
            param([string]$PolicyId)
            ConvertTo-Json -InputObject @((Invoke-OERArmRequest -Path "$PolicyId`?api-version=2020-10-01").properties.rules) -Depth 30 -Compress
        } ([string]$Policy.PolicyId)
    } catch {
        Write-Host "--- $($Label): Reader record read FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    Set-Content -Path (Join-Path $Raw "$Label-reader-raw.json") -Value $Json -Encoding utf8NoBOM
    $Parsed = $Json | ConvertFrom-Json -AsHashtable
    $Live = @($Parsed | Where-Object { $null -ne $_ })
    $Diff = @(Get-S63RuleDiff -Live $Live -Baseline @($Record['rules']))
    Write-Host ('--- {0}: Reader at oer-s63-rg: the record names this policy: {1}; rules live {2}, recorded {3}; differing from the record: {4}{5}' -f
        $Label, ([string]$Record['policyId'] -eq [string]$Policy.PolicyId), $Live.Count, @($Record['rules']).Count, $Diff.Count,
        $(if ($Diff.Count) { ' (' + ($Diff -join ', ') + ')' } else { '' }))
}

function Invoke-S63Check {
    # Writes the document to the raw folder, validates it offline, then runs Invoke-OERStructure on
    # it -- under -WhatIf unless -Apply is given. Warnings are merged into the output stream (3>&1),
    # which keeps their order; errors are printed as id and message only. Every result row is
    # appended to all-results.csv for T.5.
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string[]]$Include,
        [switch]$Apply,
        [switch]$ValidateOnly
    )
    $Path = Join-Path $Raw "$Id.json"
    Set-Content -Path $Path -Value $Json -Encoding utf8NoBOM
    Write-Host "=== $Id -- $Path"
    Get-Content -Path $Path | ForEach-Object { Write-Host "    $_" }

    $global:S63Validation = Test-OERStructure -Path $Path
    Write-Host "--- offline validation: Valid = $($S63Validation.Valid), findings = $(@($S63Validation.Errors).Count)"
    $S63Validation.Errors | Format-List Section, Item, Path, Severity, Message | Out-Host
    if ($ValidateOnly -or -not $S63Validation.Valid) { return }

    $Splat = @{ Path = $Path; Include = $Include; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CheckError' }
    if ($Apply) { $Splat.Confirm = $false } else { $Splat.WhatIf = $true }
    Write-Host ('--- Invoke-OERStructure -Include {0}{1}' -f ($Include -join ','), $(if ($Apply) { ' -Confirm:$false' } else { ' -WhatIf' }))
    $Out = @(Invoke-OERStructure @Splat 3>&1)
    $global:S63Warning = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $global:S63Result  = @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    $global:S63Error   = @($CheckError)
    Write-Host "--- warnings, in the order written: $($S63Warning.Count)"
    $S63Warning | ForEach-Object { Write-Host "    WARNING: $($_.Message)" }
    Write-Host "--- errors: $($S63Error.Count)"
    $S63Error | ForEach-Object { Write-Host "    ERROR [$($_.FullyQualifiedErrorId)]: $($_.Exception.Message)" }
    Write-Host "--- results: $($S63Result.Count)"
    $S63Result | Format-List Section, Item, Action, Detail | Out-Host
    Write-Host "--- action counts: $(($S63Result | Group-Object Action -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')"
    $S63Result | Select-Object @{ Name = 'CheckId'; Expression = { $Id } }, Section, Item, Action, Detail |
        Export-Csv -Path (Join-Path $Raw 'all-results.csv') -Append -NoTypeInformation
}
```

**The documents, and the script check 6.1 runs in a process of its own.** Paste this block as it
stands -- every here-string must close at column 0. The checks name each document by its `$Docs`
key and describe it. The two section-4 documents are built at run time by `New-S63AcDocument`, since
the authentication context is picked in 4.1.

```powershell
$Docs = @{}

$Docs.DirBoth = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "directoryRoleManagementPolicies": [
    { "role": "$RoleRR", "requireApproval": true, "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] } },
    { "role": "$RoleMCR", "activationMaxHours": 2, "requireApproval": true, "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] } }
  ]
}
"@

$Docs.DirScopeKey = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "directoryRoleManagementPolicies": [
    { "role": "$RoleRR", "scope": "/", "activationMaxHours": 3 }
  ]
}
"@

$Docs.DirBothSides = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "directoryRoleManagementPolicies": [
    { "role": "$RoleRR", "requireMfaOnActivation": true, "authenticationContextId": "c1" }
  ]
}
"@

$Docs.DirUsersOnly = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "directoryRoleManagementPolicies": [
    { "role": "$RoleRR", "requireApproval": true, "approvers": { "users": [ "$Approver2Upn" ] } }
  ]
}
"@

$Docs.DirGroupsEmpty = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "directoryRoleManagementPolicies": [
    { "role": "$RoleRR", "requireApproval": true, "approvers": { "groups": [] } }
  ]
}
"@

$Docs.Mixed = @"
{
  "version": "1.0",
  "tenantAlias": "$Alias",
  "roleManagementPolicies": [
    {
      "scope": "$RgScope",
      "role": "Reader",
      "activationMaxHours": 3,
      "requireApproval": true,
      "approvers": { "users": [ "$ApproverUpn" ], "groups": [ "$ApproversName" ] }
    }
  ],
  "directoryRoleManagementPolicies": [
    { "role": "$RoleMCR", "activationMaxHours": 3 }
  ]
}
"@

function New-S63AcDocument {
    # The 4.3 and 4.4 documents: Reports Reader declaring only authenticationContextId -- the context
    # 4.1 picked, or "" to disable it.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    [ordered]@{
        version                         = '1.0'
        tenantAlias                     = $Alias
        directoryRoleManagementPolicies = @([ordered]@{ role = $RoleRR; authenticationContextId = $Value })
    } | ConvertTo-Json -Depth 5
}

$RefusedReadScript = @'
# Check 6.1 -- runs in a process of its own, signed in app-only as oer-live-cc-noperm: the same
# certificate as oer-live-cc, and no API permission at all. Written by the checklist; its inputs come
# from 6.1-input.json beside it. An app-only session has no v1.0/me: the session's own ids, from the
# claims of the token it obtained, identify it, printed as True/False only.
$ErrorActionPreference = 'Continue'
$In = Get-Content -Path (Join-Path $PSScriptRoot '6.1-input.json') -Raw | ConvertFrom-Json
$env:PSModulePath = $In.PSModulePathPrefix + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module Omnicit.EntraRBAC -Force
$null = Connect-OER -TenantId $In.TenantId -ClientId $In.NoPermAppId -Certificate (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($In.Thumbprint)") -ErrorAction Stop
$Ctx = Get-MgContext
Write-Host "identity check: session app id is oer-live-cc-noperm: $([string]$Ctx.ClientId -eq $In.NoPermAppId)"
Write-Host "identity check: tenant is the test tenant: $([string]$Ctx.TenantId -eq $In.TenantId)"
Write-Host "identity check: the token carries application permissions: $(@($Ctx.Scopes | Where-Object { $_ }).Count)"
function Show-Published {
    # The error id and message of each error the named cmdlet published -- never the record itself.
    param([object[]]$Record, [string]$Cmdlet)
    $Published = @($Record | Where-Object { $null -ne $_ -and @(([string]$_.FullyQualifiedErrorId) -split ',') -contains $Cmdlet })
    Write-Host "Errors published by $($Cmdlet): $($Published.Count)"
    $Published | ForEach-Object { Write-Host "ERROR [$($_.FullyQualifiedErrorId)]: $($_.Exception.Message)" }
}
# (a) By name: the role-definition lookup is what gets refused.
$A = @(Get-OERDirectoryRoleManagementPolicy -Role $In.RoleName -ErrorAction SilentlyContinue -ErrorVariable ErrA)
Write-Host "(a) Get by name -- result objects: $($A.Count)"
Show-Published -Record $ErrA -Cmdlet 'Get-OERDirectoryRoleManagementPolicy'
# (b) By role definition id: no lookup, so the policy-assignment read is the one refused.
$B = @(Get-OERDirectoryRoleManagementPolicy -Role $In.RoleId -ErrorAction SilentlyContinue -ErrorVariable ErrB)
Write-Host "(b) Get by role definition id -- result objects: $($B.Count)"
Show-Published -Record $ErrB -Cmdlet 'Get-OERDirectoryRoleManagementPolicy'
# (c) Set by name under -WhatIf: the lookup runs before ShouldProcess, so a refused lookup takes the
# path a real call would take, and an identity that turns out to have write rights still writes nothing.
$C = @(Set-OERDirectoryRoleManagementPolicy -Role $In.RoleName -ActivationMaxHours $In.ProbeHours -WhatIf -ErrorAction SilentlyContinue -ErrorVariable ErrC)
Write-Host "(c) Set by name, -WhatIf -- result objects: $($C.Count)"
Show-Published -Record $ErrC -Cmdlet 'Set-OERDirectoryRoleManagementPolicy'
# The same two reads outside the module. Only the HTTP status is taken from a failure; nothing else in
# that record is printed, since it carries the bearer token.
$Probes = [ordered]@{
    'role-definition lookup' = 'v1.0/roleManagement/directory/roleDefinitions?$filter=' + [uri]::EscapeDataString("displayName eq '$($In.RoleName)'") + '&$select=id'
    'policy-assignment read' = 'v1.0/policies/roleManagementPolicyAssignments?$filter=' + [uri]::EscapeDataString("scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$($In.RoleId)'")
}
foreach ($Probe in $Probes.GetEnumerator()) {
    $Status = 'not captured'
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop -Uri $Probe.Value
        $Status = "200, $(@($R.value).Count) object(s)"
    } catch {
        $Ex = $PSItem.Exception
        if ($null -ne $Ex.Response -and $null -ne $Ex.Response.StatusCode) { $Status = [int]$Ex.Response.StatusCode }
        elseif ($null -ne $Ex.ResponseStatusCode) { $Status = [int]$Ex.ResponseStatusCode }
    }
    Write-Host "Raw status of the $($Probe.Key) for this identity: $Status"
}
$Error.Clear()
Disconnect-OER
Write-Host 'Done. Copy the lines above into check 6.1.'
'@
```

In the `Expect:` lines below, `<RgScope>` is
`/subscriptions/<your-test-subscription-id>/resourceGroups/oer-s63-rg`, `<ApproverUpn>` is
`oer-s63-approver@<your-verified-domain>` and `<Approver2Upn>` is
`oer-s63-approver2@<your-verified-domain>`. `<IdApprover>`, `<IdApprover2>` and `<IdApprovers>` are
the object ids 0.3 records (the two users and the approver group); `<RoleIdRR>` and `<RoleIdMCR>` the
role definition ids of Reports Reader and Message Center Reader, and `<PolicyIdRR>` and
`<PolicyIdMCR>` their policy ids, all read by 0.3 at run time; `<ArmPolicyId>` is the Reader policy
id at `oer-s63-rg` that 1.4 records; `<AcId>` is the authentication context 4.1 picks. Where a block
prints a policy as `<Reports Reader>` or a test object by its name, the helper has already replaced
the id.

**Run order.** Section 0, then section 1 before ANY other check -- 1.1 proves the baseline file the
Teardown restores matches the live policies, and 1.4 proves the same of the Reader record and keeps
the activation hours T.1 puts back. Then sections 2, 3 and 4 in order: each starts from the state the
one before it leaves, and 2.8 needs Message Center Reader untouched, which it is until 3.3. Section 5
after section 3 (5.2 expects Message Center Reader at 3.3's value), section 6 at any time after
section 1 (6.2 compares two values read around 6.1, so it holds wherever section 6 runs). Teardown
last. If the window is closed part-way,
paste the Setup blocks again (variables, sign-in, helpers, documents), re-run 0.3, then set
`$ArmPolicyId = (Get-Content (Join-Path $Raw '1.4-arm-baseline.json') -Raw | ConvertFrom-Json).PolicyId`
and, from section 4 on, `$AcId = Get-Content (Join-Path $Raw '4.1-acid.txt')`. A raw read answering
401 after a long pause means the token `Connect-OER` handed the Graph SDK has expired: paste the
sign-in block again.

---

### 0. Preparation

- [x] **0.1 The session runs THIS branch's build.**

  ```powershell
  git -C $Repo fetch origin
  git -C $Repo log --format=%s origin/main..HEAD
  $M = Get-Module Omnicit.EntraRBAC
  '{0} {1} from {2}' -f $M.Name, $M.Version, $M.ModuleBase
  & $M { Get-Command Resolve-OERDirectoryRoleDefinitionId, Get-OERPimRulePatchOrder, Resolve-OERGraphApproverSet, Sync-OERStructureDirectoryRoleManagementPolicy } | Format-Table Name, CommandType -AutoSize
  Get-Command Get-OERDirectoryRoleManagementPolicy, Set-OERDirectoryRoleManagementPolicy | Format-Table Name, CommandType -AutoSize
  (Get-Command Invoke-OERStructure).Parameters['Include'].Attributes.ValidValues -contains 'DirectoryRoleManagementPolicies'
  Get-OERRequiredScope -Cmdlet Get-OERDirectoryRoleManagementPolicy, Set-OERDirectoryRoleManagementPolicy |
      ForEach-Object { '{0} [{1}]: {2}' -f $_.Cmdlet, $_.Transport, ($_.GraphScope -join ', ') }
  $S = 'Get-OERDirectoryRoleManagementPolicy -Role Reports'
  (TabExpansion2 -inputScript $S -cursorColumn $S.Length).CompletionMatches.CompletionText
  ```

  **Expect:** before the merge, the log lists at least these subjects (record any later one too --
  review fixes land after this file was written): "feat: resolve a directory role name to its role
  definition id", "refactor: give the PIM rule-patch builder and policy projection a Graph mode",
  "feat: Get-OERDirectoryRoleManagementPolicy reads the PIM settings of a directory role", "fix:
  refuse a group policy id on the directory-role policy read", "feat:
  Set-OERDirectoryRoleManagementPolicy updates the PIM settings of a directory role", "fix: refuse a
  malformed policy id before any approver lookup", "refactor: one owner for the Graph approver
  semantics of the PIM policy cmdlets", "feat: tab-complete built-in directory role names on the
  directory-role policy cmdlets", "feat: diff only the declared approver side on request", "feat:
  directoryRoleManagementPolicies section in the apply document", "fix: converge a declared empty
  approver side on directory-role policies", "docs: name the directory-role section wherever the
  document sections are listed", "test: split the PIM policy scope rule so directory-role paths need
  directory permissions", "docs: complete the new-function checklist and correct the source gate
  count" and "docs: live-verification checklist for directory-role PIM settings". Subjects, not
  hashes: a rebase onto `main` rewrites every hash. After the merge the range is empty -- the squash
  merge folds the branch into one commit on `main`. `ModuleBase` lies under
  `<your-clone>/output/module/Omnicit.EntraRBAC/`; the four private functions and the two public ones
  are listed as `Function`; the `ValidValues` line prints `True`; the scope lines read
  `Get-OERDirectoryRoleManagementPolicy [Graph]: RoleManagement.Read.Directory` and
  `Set-OERDirectoryRoleManagementPolicy [Graph]: Application.Read.All, Group.Read.All, RoleManagement.Read.Directory, RoleManagementPolicy.ReadWrite.Directory, User.ReadBasic.All`;
  the completion list holds `'Reports Reader'` -- quoted, since the name holds a space.
  **Failure looks like:** `CommandNotFound` for any of the functions, `False`, a missing scope row, or
  no completion -- a build without this branch's change is loaded. Rebuild, fix `PSModulePath`,
  re-import; nothing below means anything until this passes.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Run 1, from the main
  clone on `feat/directory-role-management-policies` at `5d2b5a5`, built from it. Every block of
  this run ran in a process of its own, as this file's recovery path describes (Setup blocks,
  sign-in, helpers, documents, 0.3's ids), so each block below starts with its own two identity
  lines. Run order: sections 0 and 1, then 2.2 and 2.3 FIRST -- the approver-shape measurement --
  then 2.1, then everything else in order. The log lists every expected subject plus the review
  fixes and three later commits; `ModuleBase` is the clone's build; the four private and two public
  functions are `Function`; `True`; both scope lines exactly as expected; the completion is
  `'Reports Reader'`.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  docs: tighten the release notes for the coming minor release
  test: find an object id wrapped over a line break in dochygiene
  docs: redact an object id wrapped over two lines in the PIM group approval checklist
  fix: lower-case a role definition id passed to -Role
  refactor: describe the directory-role code by behaviour, not by plan step
  docs: correct the directory-role policy help and release notes
  fix: put back the accepted half of a rejected MFA and authentication-context pair
  docs: restore the Azure test policy in full in the directory-role live checklist
  docs: release notes for directory-role PIM settings
  docs: live-verification checklist for directory-role PIM settings
  docs: complete the new-function checklist and correct the source gate count
  test: split the PIM policy scope rule so directory-role paths need directory permissions
  docs: name the directory-role section wherever the document sections are listed
  fix: converge a declared empty approver side on directory-role policies
  feat: directoryRoleManagementPolicies section in the apply document
  feat: diff only the declared approver side on request
  feat: tab-complete built-in directory role names on the directory-role policy cmdlets
  refactor: one owner for the Graph approver semantics of the PIM policy cmdlets
  fix: refuse a malformed policy id before any approver lookup
  feat: Set-OERDirectoryRoleManagementPolicy updates the PIM settings of a directory role
  fix: refuse a group policy id on the directory-role policy read
  feat: Get-OERDirectoryRoleManagementPolicy reads the PIM settings of a directory role
  refactor: give the PIM rule-patch builder and policy projection a Graph mode
  feat: resolve a directory role name to its role definition id
  Omnicit.EntraRBAC 1.1.0 from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0
  Name                                           CommandType
  ----                                           -----------
  Resolve-OERDirectoryRoleDefinitionId              Function
  Get-OERPimRulePatchOrder                          Function
  Resolve-OERGraphApproverSet                       Function
  Sync-OERStructureDirectoryRoleManagementPolicy    Function
  Name                                 CommandType
  ----                                 -----------
  Get-OERDirectoryRoleManagementPolicy    Function
  Set-OERDirectoryRoleManagementPolicy    Function
  True
  Get-OERDirectoryRoleManagementPolicy [Graph]: RoleManagement.Read.Directory
  Set-OERDirectoryRoleManagementPolicy [Graph]: Application.Read.All, Group.Read.All, RoleManagement.Read.Directory, RoleManagementPolicy.ReadWrite.Directory, User.ReadBasic.All
  'Reports Reader'
  ```

- [x] **0.2 The prerequisite script ran, every test object exists, and the baseline file and the Reader record are written.** Paste its output and summary table, redacted per the redaction rules at the top: `<TenantId>`, `<SubscriptionId>`, `<test tenant>`, `<test subscription>`, `<test domain>`, `<Alias>`, `<Repo>`, `personN@example.com`, and a placeholder for every object id -- the summary's, the `approver on it:` lines' and the sweep lines' alike.

  **Expect:** the `-WhatIf` run names only `oer-s63` targets, plus one
  `What if: Performing the operation "Write the baseline file: ..." on target "<your-clone>\docs\live-verification\raw\s63\baseline-directory-policies.json".`
  line when no baseline file exists yet, and one
  `What if: Performing the operation "Write the Reader record: ..." on target "<your-clone>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json".`
  line when no Reader record exists yet (only when the resource group exists already -- a `-WhatIf`
  run does not create it). The real run prints, before any sign-in,
  `Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Baseline file: ... (exists: False)`
  and `Reader record: ... (exists: False)` (`True` on a later run). After EACH of its three sign-ins it printed the two identity lines,
  `... identity check: session app id is oer-live-cc: True` and
  `... identity check: tenant is the test tenant: True`. Before any write it printed
  `Identified the test tenant: organization '<your-test-tenant-display-name>', tenant id <id>, verified domain <your-verified-domain>.`,
  `Identified the test subscription: '<your-test-subscription-name>' (<your-test-subscription-id>).`
  and `Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.`,
  and later `Phase 1 is signed in to the confirmed test tenant ...` and
  `Phase 2 (Connect-OER) is signed in to the confirmed test tenant ...`. In Phase 1, for each role,
  `Directory role 'Reports Reader': one built-in role definition and one tenant-wide policy assignment: True (<n> rules).`
  (and the same for Message Center Reader). On a first run: `No baseline file yet at ...; this run captures it.`,
  `Directory role '<role>': approval required False, approvers 0.` for both roles, NO warning, and
  `Wrote the baseline file (<n> + <m> rules): <path>`. On a later run instead:
  `The baseline file exists (captured <time>); comparing the live rules with it. ...`, then for each
  role `the baseline names the same role definition and policy: True` and
  `rules differing from the baseline: 0`, and no warning. After the resource group line, on a first
  run: `No Reader record yet at ...; this run captures it.`,
  `Setup: Reader policy at oer-s63-rg: approval required False, approvers 0, activation max hours 8; at its defaults (approval off, no approver): True`,
  NO warning, and `Wrote the Reader record (<n> rules): <path>`. On a later run instead:
  `Setup: the Reader record (captured <time>) names this policy: True`, the same `Setup: Reader policy ...`
  line, and
  `Setup: Reader policy at oer-s63-rg against its record: activation max hours 8 (record 8), approval required False (record False), approvers 0 (record 0); rules differing from the record: 0`.
  (With leftovers from an earlier run: `approver on it:` lines, a warning, a `Restored the Reader role
  management policy at resource group 'oer-s63-rg' ...` line -- `to its defaults.` without a record,
  `from its record.` with one -- and a read again: record every line.) The summary has one row each for
  the two users, the group `oer-s63-approvers`, the resource group, one `group member` row
  (`oer-s63-approvers <- <ApproverUpn>`), one `directory role (built-in, fixed)` and one
  `directory role policy` row per role, one `baseline file (written by this run)` row (or
  `(existed; 0 rule(s) differing)`) and one `Reader record (written by this run)` row (or
  `(existed; 0 rule(s) differing)`). No row reads `(none -- not created)`. It ends `Done.`
  **Failure looks like:** a `(none -- not created)` row, or the script stopped on an error -- fix the
  cause and re-run it before 0.3. A `Refusing to run: ...` line from the tenant identification means
  nothing was written: check `$OrgName` (exact, case-sensitive), `$Domain`, `$TenantId` and any
  Tenant Profile for the alias before trying again -- never weaken the check. A warning that a
  policy "is being recorded with approval required or approvers on it", or a non-zero
  `rules differing from the baseline`: an earlier run did not finish its teardown, or someone changed
  the role's settings. Stop -- no check may write to the policy before this is understood; a leftover
  baseline file is restored with the script's `-Teardown`. A warning that the Reader policy "allows
  `<n>` activation hour(s), not 8" (no record yet), or "differs from its record" and was not restored,
  or that "the Reader record names another policy": the Azure test policy does not start where this
  file assumes -- stop, and let the script's `-Teardown` restore it from the record, or move a foreign
  record aside, before section 5. A refusal naming a directory role that is not one of the two, or a
  user `oer-s63-nobody@...` that exists: stop and record it.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The `-WhatIf` run named
  only `oer-s63` targets besides the baseline file (no Reader-record line: the resource group did
  not exist yet) and wrote nothing. The real run: both identity lines `True` after each of its
  three sign-ins; the tenant and the subscription identified; the baseline file written (17 + 17
  rules) BEFORE the first object was created; both roles at approval off with no approver, no
  warning; one membership add answered 404 once (replication) and succeeded on the retry; the
  Reader policy at its defaults with 8 activation hours, and the Reader record written (17 rules);
  no `(none -- not created)` row; `Done.` Then, read-only: both files exist under `raw/s63/`, with
  their rule counts, and git ignores the folder. Omitted below: the `What if: ... "Update
  TypeData"` lines PowerShell prints while modules import in the `-WhatIf` process -- not targets
  of the script.

  ```text
  [oer-s63] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s63] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s63] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s63', expected organization '<test tenant>'.
  [oer-s63] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Baseline file: <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json (exists: False).
  [oer-s63] Reader record: <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json (exists: False).
  [oer-s63] Tenant identification (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s63] Tenant identification (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s63] Tenant identification (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s63] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s63] Identified the test subscription: '<test subscription>' (<SubscriptionId>).
  [oer-s63] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s63] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s63] Phase 1 identity check: tenant is the test tenant: True
  [oer-s63] Phase 1 is signed in to the confirmed test tenant '<test tenant>' (<TenantId>).
  [oer-s63] Directory role 'Reports Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s63] Directory role 'Message Center Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s63] No baseline file yet at <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json; this run captures it.
  [oer-s63] Directory role 'Reports Reader': approval required False, approvers 0.
  [oer-s63] Directory role 'Message Center Reader': approval required False, approvers 0.
  What if: Performing the operation "Write the baseline file: the raw Microsoft Graph v1.0 rules of both directory-role policies, which -Teardown restores" on target "<Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json".
  What if: Performing the operation "Create a DISABLED test user with a random, unprinted password" on target "person1@example.com".
  What if: Performing the operation "Create a DISABLED test user with a random, unprinted password" on target "person2@example.com".
  What if: Performing the operation "Create security group" on target "oer-s63-approvers".
  [oer-s63] Skipping the member of oer-s63-approvers: the group does not exist yet.
  [oer-s63] Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s63] Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s63] Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s63] Phase 2 (Connect-OER) is signed in to the confirmed test tenant '<test tenant>' (<TenantId>).
  What if: Performing the operation "Create in swedencentral" on target "resource group 'oer-s63-rg' in subscription '<SubscriptionId>'".
  [oer-s63] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
  Kind                                 Name                                                                                      Id
  ----                                 ----                                                                                      --
  user                                 person1@example.com                                                  (none -- not created)
  user                                 person2@example.com                                                 (none -- not created)
  group                                oer-s63-approvers                                                                         (none -- not created)
  resource group                       oer-s63-rg                                                                                (none -- not created)
  directory role (built-in, fixed)     Reports Reader                                                                            00000000-0000-0000-0000-000000000001
  directory role policy                Reports Reader                                                                            DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002
  directory role (built-in, fixed)     Message Center Reader                                                                     00000000-0000-0000-0000-000000000003
  directory role policy                Message Center Reader                                                                     DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004
  baseline file (not written (WhatIf)) <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json  -
  Reader record ()                     <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json -
  [oer-s63] WhatIf: nothing was created, restored, removed or written.
  [oer-s63] Done.

  [oer-s63] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s63] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s63] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s63', expected organization '<test tenant>'.
  [oer-s63] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Baseline file: <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json (exists: False).
  [oer-s63] Reader record: <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json (exists: False).
  [oer-s63] Tenant identification (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s63] Tenant identification (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s63] Tenant identification (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s63] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s63] Identified the test subscription: '<test subscription>' (<SubscriptionId>).
  [oer-s63] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
  [oer-s63] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s63] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s63] Phase 1 identity check: tenant is the test tenant: True
  [oer-s63] Phase 1 is signed in to the confirmed test tenant '<test tenant>' (<TenantId>).
  [oer-s63] Directory role 'Reports Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s63] Directory role 'Message Center Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s63] No baseline file yet at <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json; this run captures it.
  [oer-s63] Directory role 'Reports Reader': approval required False, approvers 0.
  [oer-s63] Directory role 'Message Center Reader': approval required False, approvers 0.
  [oer-s63] Wrote the baseline file (17 + 17 rules): <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json
  [oer-s63] Created user person1@example.com (disabled).
  [oer-s63] Created user person2@example.com (disabled).
  [oer-s63] Created group oer-s63-approvers.
  [oer-s63] Adding person1@example.com to oer-s63-approvers failed (attempt 1 of 6, likely replication delay): Response status code does not indicate success: NotFound (Not Found). -- retrying in 10 s.
  [oer-s63] Added person1@example.com to oer-s63-approvers.
  [oer-s63] Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s63] Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s63] Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s63] Phase 2 (Connect-OER) is signed in to the confirmed test tenant '<test tenant>' (<TenantId>).
  [oer-s63] Created resource group oer-s63-rg in swedencentral, tagged purpose = oer-s63-live-verification.
  [oer-s63] No Reader record yet at <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json; this run captures it.
  [oer-s63] Setup: Reader policy at oer-s63-rg: approval required False, approvers 0, activation max hours 8; at its defaults (approval off, no approver): True
  [oer-s63] Wrote the Reader record (17 rules): <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json
  [oer-s63] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
  Kind                                Name                                                                                      Id
  ----                                ----                                                                                      --
  user                                person1@example.com                                                  00000000-0000-0000-0000-000000000005
  user                                person2@example.com                                                 00000000-0000-0000-0000-000000000006
  group                               oer-s63-approvers                                                                         00000000-0000-0000-0000-000000000007
  group member                        oer-s63-approvers <- person1@example.com                             00000000-0000-0000-0000-000000000005
  resource group                      oer-s63-rg                                                                                /subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg
  directory role (built-in, fixed)    Reports Reader                                                                            00000000-0000-0000-0000-000000000001
  directory role policy               Reports Reader                                                                            DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002
  directory role (built-in, fixed)    Message Center Reader                                                                     00000000-0000-0000-0000-000000000003
  directory role policy               Message Center Reader                                                                     DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004
  baseline file (written by this run) <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json  -
  Reader record (written by this run) <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json -
  [oer-s63] Done.

  baseline-directory-policies.json: exists True; 20581 bytes; written 2026-09-29T09:04:08
  baseline-azure-reader-policy.json: exists True; 8826 bytes; written 2026-09-29T09:04:32
  baseline file: role entries 2: Reports Reader (17 rules, policyId recorded True, roleDefinitionId recorded True); Message Center Reader (17 rules, policyId recorded True, roleDefinitionId recorded True)
  Reader record: 17 rules, policyId recorded True
  raw/s63 is ignored by git: True
  ```

- [x] **0.3 Record the object ids every later check compares against.** Read-only.

  ```powershell
  $IdApprovers = (Get-OERGroup -Group $ApproversName -ErrorAction Stop).Id
  $ApproverMembers = @(Get-OERGroupMember -Group $ApproversName -ErrorAction Stop)
  $IdApprover = ($ApproverMembers | Where-Object UserPrincipalName -eq $ApproverUpn).PrincipalId
  $U1 = Get-S63RawUser -Upn $ApproverUpn
  $U2 = Get-S63RawUser -Upn $Approver2Upn
  $IdApprover2 = $U2.Id
  $RoleIdRR  = Get-S63RawRoleDefinitionId -Name $RoleRR
  $RoleIdMCR = Get-S63RawRoleDefinitionId -Name $RoleMCR
  $PolicyIdRR  = (Get-S63RawPolicy -RoleDefinitionId $RoleIdRR -Label '0.3-rr-raw').PolicyId
  $PolicyIdMCR = (Get-S63RawPolicy -RoleDefinitionId $RoleIdMCR -Label '0.3-mcr-raw').PolicyId
  $Base0 = Get-S63Baseline
  $BaseRR  = @($Base0['roles'] | Where-Object { $_['displayName'] -ceq $RoleRR })[0]
  $BaseMCR = @($Base0['roles'] | Where-Object { $_['displayName'] -ceq $RoleMCR })[0]
  "members of $($ApproversName): $($ApproverMembers.Count); $Prefix-approver among them: $([bool]$IdApprover)"
  "$Prefix-approver: raw id is the member's id: $($U1.Id -eq $IdApprover); account enabled: $($U1.AccountEnabled)"
  "$Prefix-approver2: account enabled: $($U2.AccountEnabled); a member of $($ApproversName): $(@($ApproverMembers | Where-Object PrincipalId -eq $IdApprover2).Count -gt 0)"
  "baseline file: role entries $(@($Base0['roles']).Count)"
  "$($RoleRR): the baseline names this role definition: $($BaseRR['roleDefinitionId'] -eq $RoleIdRR); this policy: $($BaseRR['policyId'] -eq $PolicyIdRR)"
  "$($RoleMCR): the baseline names this role definition: $($BaseMCR['roleDefinitionId'] -eq $RoleIdMCR); this policy: $($BaseMCR['policyId'] -eq $PolicyIdMCR)"
  "the two roles, and their policies, differ: $(($RoleIdRR -ne $RoleIdMCR) -and ($PolicyIdRR -ne $PolicyIdMCR))"
  $IdApprovers, $IdApprover, $IdApprover2, $RoleIdRR, $RoleIdMCR, $PolicyIdRR, $PolicyIdMCR | ForEach-Object { [bool]$_ }
  ```

  **Expect:** `members of oer-s63-approvers: 1; oer-s63-approver among them: True`;
  `oer-s63-approver: raw id is the member's id: True; account enabled: False`;
  `oer-s63-approver2: account enabled: False; a member of oer-s63-approvers: False`;
  `baseline file: role entries 2`; both roles `the baseline names this role definition: True; this policy: True`;
  `the two roles, and their policies, differ: True`; then `True` seven times. No `FAILED` line.
  **Failure looks like:** any count off, a `False`, or a `raw ... read FAILED` line -- a 403 there
  is a missing permission (see Stop conditions). A baseline naming another role definition or policy
  is not this tenant's baseline: stop, move it aside and run the prerequisite script again.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Every line as expected:
  one member, `oer-s63-approver`, both users disabled, `oer-s63-approver2` not a member, two
  baseline entries naming these role definitions and policies, the roles and policies differ, and
  seven `True`.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  members of oer-s63-approvers: 1; oer-s63-approver among them: True
  oer-s63-approver: raw id is the member's id: True; account enabled: False
  oer-s63-approver2: account enabled: False; a member of oer-s63-approvers: False
  baseline file: role entries 2
  Reports Reader: the baseline names this role definition: True; this policy: True
  Message Center Reader: the baseline names this role definition: True; this policy: True
  the two roles, and their policies, differ: True
  True
  True
  True
  True
  True
  True
  True
  ```

---

### 1. Baseline -- the original state of every policy this file touches

Nothing below this section may run before it: the Teardown restores exactly what the baseline file
holds, and T.4 compares with what 1.1 saves.

- [x] **1.1 Both directory-role policies, through the module and raw from Graph v1.0, against the baseline file.**

  ```powershell
  $View11 = [ordered]@{}
  foreach ($R in @(@{ Key = 'rr'; Name = $RoleRR; RoleId = $RoleIdRR; PolicyId = $PolicyIdRR }, @{ Key = 'mcr'; Name = $RoleMCR; RoleId = $RoleIdMCR; PolicyId = $PolicyIdMCR })) {
      Invoke-S63Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ Role = $R.Name } -Label "1.1 $($R.Name)"
      $P = $S63Out | Select-Object -First 1
      Show-S63Policy -Policy $P -Label $R.Name
      $View11[$R.Key] = Get-S63ModuleView -Policy $P
      $Raw11 = Get-S63RawPolicy -RoleDefinitionId $R.RoleId -Label "1.1-$($R.Key)-raw"
      $ById = @{}; foreach ($Rule in $Raw11.Rules) { $ById[[string]$Rule['id']] = $Rule }
      $Stage = @($ById['Approval_EndUser_Assignment']['setting']['approvalStages'])[0]
      $RawApprovers = if ($Stage) { @($Stage['primaryApprovers'] | Where-Object { $null -ne $_ }).Count } else { 0 }
      Write-Host ('--- module and raw agree: PolicyId {0}; RequireApproval {1}; approvers {2}; ActivationMaxHours {3}' -f
          ($P.PolicyId -eq $Raw11.PolicyId), ($P.RequireApproval -eq [bool]$ById['Approval_EndUser_Assignment']['setting']['isApprovalRequired']),
          (@($P.Approvers).Count -eq $RawApprovers), ("PT$($P.ActivationMaxHours)H" -eq [string]$ById['Expiration_EndUser_Assignment']['maximumDuration']))
      Show-S63RawApproval -PolicyId $R.PolicyId -Label "1.1-$($R.Key)-approval-raw"
  }
  $View11 | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $Raw '1.1-module-view.json') -Encoding utf8NoBOM
  Show-S63BaselineDiff -Label '1.1'
  ```

  **Expect:** for each role, two requests in this order, `GET v1.0/roleManagement/directory/roleDefinitions`
  and `GET v1.0/policies/roleManagementPolicyAssignments`, no warning, no error, one object. Printed:
  `policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader`
  (the same for Message Center Reader) -- the name as typed, the scope `/`. `RequireApproval False`
  and `approvers: 0` -- a built-in role's defaults. The module-and-raw line prints `True` four
  times; the raw approval line prints `isApprovalRequired = False` and `primary approvers: 0`. Then
  `--- 1.1: Reports Reader: the baseline names this policy: True; ...; differing from the baseline: 0`
  and the same for Message Center Reader. **Record every setting printed** -- T.4 compares with them,
  and the checks below assume what a built-in role starts with: approval off, no approver, no
  authentication context, ticket on activation off, and neither 2 nor 3 activation hours. A check
  whose `Expect:` rests on one of those says so.
  **Failure looks like:** a baseline difference above `0` -- an earlier run's leftovers or a change by
  someone else; no check may write to that policy until it is understood (the prerequisite script's
  `-Teardown` restores from the file). A `False` on the module-and-raw line -- the projection reads
  Graph v1.0 differently from Graph itself: record which field. Approvers or approval on at the
  baseline: record them; 2.8 is then `[~]`, and the approver counts below change.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Both roles: the two
  requests in order, no warning, no error, one object, the name as typed and scope `/`; approval
  off, no approver; the module-and-raw line `True` four times; raw `isApprovalRequired = False`,
  `SingleStage`, one stage, a one-day timeout, approver justification on, no primary approver;
  `differing from the baseline: 0` for both. Recorded for T.4, identical for both roles:
  `ActivationMaxHours 1`; on activation MFA off, justification on, ticket off; no authentication
  context; eligible permanent allowed, `P365D`; active permanent allowed, `P180D`; on active
  assignment MFA off, justification on.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 1.1 Reports Reader -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- Reports Reader: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 1; on activation: MFA False, justification True, ticket False; AuthenticationContextId ''
      eligible: permanent allowed True, P365D; active: permanent allowed True, P180D; on active assignment: MFA False, justification True
      RequireApproval False
      approvers: 0
  --- module and raw agree: PolicyId True; RequireApproval True; approvers True; ActivationMaxHours True
  --- 1.1-rr-approval-raw: policy of Reports Reader, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 0
  === 1.1 Message Center Reader -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- Message Center Reader: policy of Message Center Reader; Scope '/'; RoleName 'Message Center Reader'; RoleDefinitionId: Message Center Reader
      ActivationMaxHours 1; on activation: MFA False, justification True, ticket False; AuthenticationContextId ''
      eligible: permanent allowed True, P365D; active: permanent allowed True, P180D; on active assignment: MFA False, justification True
      RequireApproval False
      approvers: 0
  --- module and raw agree: PolicyId True; RequireApproval True; approvers True; ActivationMaxHours True
  --- 1.1-mcr-approval-raw: policy of Message Center Reader, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 0
  --- 1.1: Reports Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  --- 1.1: Message Center Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  ```

- [x] **1.2 A role definition id, a name in another letter case, a name no role has, and the policy id.** Read-only; before the first write, so every read compares with 1.1.

  ```powershell
  Invoke-S63Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleIdRR } -Label '1.2a by role definition id'
  $G = $S63Out | Select-Object -First 1
  'PolicyId is the one by name: {0}; RoleName empty: {1}; RoleDefinitionId is the GUID: {2}; Scope: {3}' -f ($G.PolicyId -eq $PolicyIdRR), [string]::IsNullOrEmpty($G.RoleName), ($G.RoleDefinitionId -eq $RoleIdRR), $G.Scope
  Invoke-S63Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR.ToLowerInvariant() } -Label '1.2b by name in lower case'
  $L = $S63Out | Select-Object -First 1
  'PolicyId is the one by name: {0}; RoleName as typed: {1}' -f ($L.PolicyId -eq $PolicyIdRR), ($L.RoleName -ceq $RoleRR.ToLowerInvariant())
  Invoke-S63Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ Role = "$Prefix-no-such-role" } -Label '1.2c a name no role has'
  Invoke-S63Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ PolicyId = $PolicyIdRR } -Label '1.2d by policy id'
  $D = $S63Out | Select-Object -First 1
  $Was12 = (Get-Content -Path (Join-Path $Raw '1.1-module-view.json') -Raw | ConvertFrom-Json).rr
  $Same12 = [bool]$D -and (@((Get-S63ModuleView -Policy $D).GetEnumerator() | Where-Object { [string]$_.Value -cne [string]$Was12.($_.Key) }).Count -eq 0)
  'PolicyId is the one by name: {0}; RoleName empty: {1}; RoleDefinitionId empty: {2}; Scope: {3}; every setting equals 1.1''s: {4}' -f
      ($D.PolicyId -eq $PolicyIdRR), [string]::IsNullOrEmpty($D.RoleName), [string]::IsNullOrEmpty($D.RoleDefinitionId), $D.Scope, $Same12
  ```

  **Expect:** (a) exactly ONE request, `GET v1.0/policies/roleManagementPolicyAssignments` -- a GUID
  is used as it stands, with no role-definition lookup; one object; the line prints
  `True; RoleName empty: True; ...: True; Scope: /`. (b) two requests (the lookup, then the
  assignment read), one object, `True; RoleName as typed: True` -- Graph's `displayName` filter
  matched the name in another letter case. (c) exactly one request,
  `GET v1.0/roleManagement/directory/roleDefinitions`; no object; one published error,
  `ERROR [RoleDefinitionNotFound,Get-OERDirectoryRoleManagementPolicy]: No Microsoft Entra directory role definition named 'oer-s63-no-such-role' was found. Use Tab completion on -Role, or pass the role definition id directly.`
  (d) exactly ONE request, `GET v1.0/policies/roleManagementPolicies/<Reports Reader>` -- the policy
  itself, with its rules expanded; no role lookup and no assignment read; one object, no warning, no
  error; the line prints `PolicyId is the one by name: True; RoleName empty: True; RoleDefinitionId empty: True; Scope: /; every setting equals 1.1's: True`
  -- the policy's own scope passed the module's directory-scope check, and the same rules project to
  the same settings whichever way the policy was found.
  **Failure looks like:** a role-definition request in (a), or a different policy id; in (b)
  `RoleDefinitionNotFound` -- Graph's filter is case-sensitive for role definitions: not a module
  defect (the module passes the name as typed), but record it as a finding, since the help promises a
  server-side lookup; in (c) `RoleDefinitionReadFailed` (a lookup that answered is not a refused one)
  or an object. In (d) an `InvalidPolicyId` error -- Graph answered this directory-role policy with a
  `scopeType` other than `Directory` or `DirectoryRole`, or a `scopeId` other than `/`, which the
  module's scope check refuses: record the message, it names what Graph returned; a `PolicyReadFailed`;
  or a setting that differs from 1.1 (the two reads project the same rules differently).
  **Result:** PASS, with a FINDING in (b) -- 2026-09-29, run by Claude Code as the certificate
  identity `oer-live-cc` (app-only), every output below passed through the run's redaction first.
  (a) exactly one request, no role lookup, and `True; RoleName empty: True; ...: True; Scope: /`.
  (c) one request and `RoleDefinitionNotFound` with the expected text. (d) exactly one request, the
  policy itself, and every setting equal to 1.1's. FINDING (b): Microsoft Graph's `displayName`
  filter on `roleDefinitions` is CASE-SENSITIVE -- `reports reader` matched nothing, so the module
  reported `RoleDefinitionNotFound` after its one request. Not a module defect (the module passes
  the name as typed), but this Expect line assumed a case-insensitive match, and neither the help
  nor the error message says the lookup is case-sensitive. Tab completion on `-Role` inserts the
  exact name.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 1.2a by role definition id -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 1
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  PolicyId is the one by name: True; RoleName empty: True; RoleDefinitionId is the GUID: True; Scope: /
  === 1.2b by name in lower case -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 1
      GET v1.0/roleManagement/directory/roleDefinitions
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [RoleDefinitionNotFound,Get-OERDirectoryRoleManagementPolicy]: No Microsoft Entra directory role definition named 'reports reader' was found. Use Tab completion on -Role, or pass the role definition id directly.
  --- objects returned: 0
  PolicyId is the one by name: False; RoleName as typed: False
  === 1.2c a name no role has -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 1
      GET v1.0/roleManagement/directory/roleDefinitions
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [RoleDefinitionNotFound,Get-OERDirectoryRoleManagementPolicy]: No Microsoft Entra directory role definition named 'oer-s63-no-such-role' was found. Use Tab completion on -Role, or pass the role definition id directly.
  --- objects returned: 0
  === 1.2d by policy id -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 1
      GET v1.0/policies/roleManagementPolicies/<Reports Reader>
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  PolicyId is the one by name: True; RoleName empty: True; RoleDefinitionId empty: True; Scope: /; every setting equals 1.1's: True
  ```

- [x] **1.3 `-All`: every directory role's policy, each named.** Read-only.

  ```powershell
  Invoke-S63Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ All = $true } -Label '1.3 -All'
  $All13 = @($S63Out)
  'rows {0}; distinct PolicyIds {1}; Scope not "/": {2}; empty RoleName: {3}; empty RoleDefinitionId: {4}' -f $All13.Count,
      @($All13.PolicyId | Sort-Object -Unique).Count, @($All13 | Where-Object Scope -ne '/').Count,
      @($All13 | Where-Object { [string]::IsNullOrEmpty($_.RoleName) }).Count, @($All13 | Where-Object { [string]::IsNullOrEmpty($_.RoleDefinitionId) }).Count
  foreach ($R in @(@{ Name = $RoleRR; PolicyId = $PolicyIdRR; RoleId = $RoleIdRR }, @{ Name = $RoleMCR; PolicyId = $PolicyIdMCR; RoleId = $RoleIdMCR })) {
      $Rows = @($All13 | Where-Object RoleName -ceq $R.Name)
      "$($R.Name): rows $($Rows.Count); PolicyId is 0.3's: $($Rows.Count -eq 1 -and $Rows[0].PolicyId -eq $R.PolicyId); RoleDefinitionId is 0.3's: $($Rows.Count -eq 1 -and $Rows[0].RoleDefinitionId -eq $R.RoleId)"
  }
  ```

  **Expect:** requests: one `GET v1.0/policies/roleManagementPolicyAssignments` per page and one
  `GET v1.0/roleManagement/directory/roleDefinitions` per page, nothing else; no warning, no error.
  Well over a hundred rows -- every directory role, built-in and custom, has a policy -- with as many
  distinct policy ids as rows, and `0`, `0`, `0`. Both role lines: `rows 1; ...: True; ...: True`.
  **Failure looks like:** a warning `Could not read Microsoft Entra directory role definition names: ...`
  with every `RoleName` empty (the name read was refused: record it); a count above `0` of empty
  `RoleName` rows (a policy for a role definition the name list lacks: record the count).
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. One page of each list,
  nothing else; 145 rows, 145 distinct policy ids, `0`, `0`, `0`; one row each for the two roles,
  with 0.3's policy and role definition ids.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 1.3 -All -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/policies/roleManagementPolicyAssignments
      GET v1.0/roleManagement/directory/roleDefinitions
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 145
  rows 145; distinct PolicyIds 145; Scope not "/": 0; empty RoleName: 0; empty RoleDefinitionId: 0
  Reports Reader: rows 1; PolicyId is 0.3's: True; RoleDefinitionId is 0.3's: True
  Message Center Reader: rows 1; PolicyId is 0.3's: True; RoleDefinitionId is 0.3's: True
  ```

- [x] **1.4 The Reader role management policy at `oer-s63-rg` -- the Azure baseline for section 5, against the Reader record.** Read-only.

  ```powershell
  $Arm0 = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  $ArmPolicyId = $Arm0.PolicyId
  'Scope is RgScope: {0}; RoleName {1}; ActivationMaxHours {2}; RequireApproval {3}; approvers {4}' -f ($Arm0.Scope -eq $RgScope), $Arm0.RoleName,
      $Arm0.ActivationMaxHours, $Arm0.RequireApproval, @($Arm0.Approvers | Where-Object { $_ }).Count
  [ordered]@{ PolicyId = $Arm0.PolicyId; ActivationMaxHours = $Arm0.ActivationMaxHours; RequireApproval = $Arm0.RequireApproval
      ApproverCount = @($Arm0.Approvers | Where-Object { $_ }).Count } | ConvertTo-Json | Set-Content -Path (Join-Path $Raw '1.4-arm-baseline.json') -Encoding utf8NoBOM
  Show-S63ReaderRecordDiff -Label '1.4'
  ```

  **Expect:** `Scope is RgScope: True; RoleName Reader; ActivationMaxHours 8; RequireApproval False; approvers 0`
  -- the defaults, which the prerequisite script checked before it wrote the Reader record (0.2);
  then `--- 1.4: Reader at oer-s63-rg: the record names this policy: True; rules live <n>, recorded <n>; differing from the record: 0`.
  The record, not this check, is what the Teardown restores; T.1 uses the activation hours printed
  here. 5.1 and 5.3 assume they are neither `2` nor `3`.
  **Failure looks like:** a read error (the ARM token or the Owner role is missing -- see Stop
  conditions); approval on, an approver present, or activation hours other than 8 -- 0.2 then warned,
  and those settings are what the record holds and the Teardown restores: record them, and do not go
  on to section 5 before they are understood; a count above `0` or `the record names this policy:
  False` -- the policy moved since setup, or the record is not this resource group's: run the
  prerequisite script again (with `-Unattended` it restores the policy from its record) before any
  check writes to the policy.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The Reader policy at
  `oer-s63-rg` at its defaults -- 8 activation hours, approval off, no approver -- and `differing
  from the record: 0`.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  Scope is RgScope: True; RoleName Reader; ActivationMaxHours 8; RequireApproval False; approvers 0
  --- 1.4: Reader at oer-s63-rg: the record names this policy: True; rules live 17, recorded 17; differing from the record: 0
  ```

---

### 2. `Set-OERDirectoryRoleManagementPolicy`

- [x] **2.1 The guards refuse before anything is written, and most of them before any request.** `-WhatIf` only: a guard that failed would print a `What if:` line here, never a write.

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; WhatIf = $true } -Label '2.1a no setting'
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; AuthenticationContextId = 'c1'; RequireMfaOnActivation = $true; WhatIf = $true } -Label '2.1b MFA and a context together'
  $ArmPolicy = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -InputObject $ArmPolicy -Splat @{ ActivationMaxHours = 2; ApproverUser = "$Prefix-nobody@$Domain"; WhatIf = $true } -Label '2.1c an Azure policy piped in'
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ PolicyId = $ArmPolicyId; ActivationMaxHours = 2; WhatIf = $true } -Label '2.1d an Azure policy id typed'
  Invoke-S63Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ PolicyId = $ArmPolicyId } -Label '2.1e an Azure policy id on the read'
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; ApproverUser = "$Prefix-nobody@$Domain"; WhatIf = $true } -Label '2.1f an approver that resolves to nothing'
  ```

  **Expect:** no `What if:` line and no object from any of the six; exactly one published error
  each. (a) `requests: 0`,
  `NothingToUpdate,Set-OERDirectoryRoleManagementPolicy`: `No policy change was supplied. Specify at least one setting parameter.`
  (b) `requests: 0`,
  `InvalidPolicyChange,Set-OERDirectoryRoleManagementPolicy`: `Cannot enable both multi-factor authentication and an authentication context on activation; PIM treats them as mutually exclusive. Set only one.`
  -- "PIM", not "Azure PIM". (c) `requests: 0` -- not even the lookup of the approver that would
  resolve to nothing --
  `InvalidPolicyId,Set-OERDirectoryRoleManagementPolicy`: `The policy id '<ArmPolicyId>' looks like an Azure Resource Manager role management policy id, not a Microsoft Graph directory-role policy id. Use Set-OERRoleManagementPolicy to update an Azure role policy by ARM id, or pass the Microsoft Graph policy id (for example 'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.`
  (the `DirectoryRole_<tenantId>_<policyGuid>` text is the module's own). (d) the same as (c).
  (e) `requests: 0`, `InvalidPolicyId,Get-OERDirectoryRoleManagementPolicy`, the same text but
  `Use Get-OERRoleManagementPolicy to read an Azure role policy by ARM id`. (f) exactly one request,
  `GET v1.0/users` -- the approver is resolved before the role or the policy is read --
  `ApproverNotFound,Set-OERDirectoryRoleManagementPolicy`: `User 'oer-s63-nobody@<your-verified-domain>' was not found.`
  **Failure looks like:** a `What if:` line from any call; any request in (a) to (e); `ApproverNotFound`
  instead of `InvalidPolicyId` in (c) -- the id guard runs after the approver lookup again, the defect
  "fix: refuse a malformed policy id before any approver lookup" closed; in (f) a
  `v1.0/roleManagement` or `v1.0/policies` request before the refusal.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Run after 2.2 and 2.3
  (see 0.1); none of the six calls reads a setting those two changed. No `What if:` line and no
  object anywhere; exactly one published error each, with the expected ids and texts; (a) to (e)
  sent no request; (f) sent exactly one, `GET v1.0/users`. Outside this step: (f) also collected
  ten further error records from nested calls beside the one it published (not shown) -- the known
  several-records-per-failure behaviour.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.1a no setting -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 0
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [NothingToUpdate,Set-OERDirectoryRoleManagementPolicy]: No policy change was supplied. Specify at least one setting parameter.
  --- objects returned: 0
  === 2.1b MFA and a context together -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 0
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [InvalidPolicyChange,Set-OERDirectoryRoleManagementPolicy]: Cannot enable both multi-factor authentication and an authentication context on activation; PIM treats them as mutually exclusive. Set only one.
  --- objects returned: 0
  === 2.1c an Azure policy piped in -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 0
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [InvalidPolicyId,Set-OERDirectoryRoleManagementPolicy]: The policy id '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000008' looks like an Azure Resource Manager role management policy id, not a Microsoft Graph directory-role policy id. Use Set-OERRoleManagementPolicy to update an Azure role policy by ARM id, or pass the Microsoft Graph policy id (for example 'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.
  --- objects returned: 0
  === 2.1d an Azure policy id typed -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 0
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [InvalidPolicyId,Set-OERDirectoryRoleManagementPolicy]: The policy id '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000008' looks like an Azure Resource Manager role management policy id, not a Microsoft Graph directory-role policy id. Use Set-OERRoleManagementPolicy to update an Azure role policy by ARM id, or pass the Microsoft Graph policy id (for example 'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.
  --- objects returned: 0
  === 2.1e an Azure policy id on the read -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 0
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [InvalidPolicyId,Get-OERDirectoryRoleManagementPolicy]: The policy id '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000008' looks like an Azure Resource Manager role management policy id, not a Microsoft Graph directory-role policy id. Use Get-OERRoleManagementPolicy to read an Azure role policy by ARM id, or pass the Microsoft Graph policy id (for example 'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.
  --- objects returned: 0
  === 2.1f an approver that resolves to nothing -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 1
      GET v1.0/users
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 10)
      ERROR [ApproverNotFound,Set-OERDirectoryRoleManagementPolicy]: User 'person3@example.com' was not found.
  --- objects returned: 0
  ```

- [x] **2.2 FIRST WRITE -- approval on Reports Reader, the user named by UPN and the group by display name.**

  The plan:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; RequireApproval = $true; ApproverUser = $ApproverUpn; ApproverGroup = $ApproversName; WhatIf = $true } -Label '2.2 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; RequireApproval = $true; ApproverUser = $ApproverUpn; ApproverGroup = $ApproversName; Confirm = $false } -Label '2.2 write'
  Show-S63Policy -Policy ($S63Out | Select-Object -First 1) -Label '2.2 returned' -ExpectUser $IdApprover -ExpectGroup $IdApprovers
  ```

  **Expect:** the plan prints
  `What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "directory role management policy '<PolicyIdRR>'".`
  and four requests in this order: `GET v1.0/users`, `GET v1.0/groups`,
  `GET v1.0/roleManagement/directory/roleDefinitions`, `GET v1.0/policies/roleManagementPolicyAssignments`;
  no warning, no error, no object. The write: the same four GETs, then exactly ONE write,
  `PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Approval_EndUser_Assignment`;
  no warning; `errors published ...: 0`; one object:
  `policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader; ChangedRuleIds [Approval_EndUser_Assignment]`,
  `RequireApproval True`, `approvers: 2` -- `User oer-s63-approver` and `Group oer-s63-approvers`,
  each `DisplayName filled: False` (the object shows the rule as SENT, and the v1.0 body carries
  `@odata.type` and `userId` or `groupId` only) -- and `approvers are exactly the expected set: True`.
  Every other setting is 1.1's.
  **Failure looks like:** a warning `Rule 'Approval_EndUser_Assignment' of directory role management policy '<PolicyIdRR>' was not applied: ...`
  and a `PolicyRulesRejected` error: Graph refused the rule. Record Graph's message, redacted -- if it
  names `userId`, `groupId` or `@odata.type`, the v1.0 approver shape the module sends is wrong, which
  is exactly what this check exists to find. If it names the approver as invalid or disabled, the
  disabled test account is the cause: record it and stop -- enabling a user is the operator's call.
  A second PATCH, or a PATCH to `<another policy>`.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The FIRST WRITE, run
  right after section 1. The plan: one `What if:` line on Reports Reader's policy, the four GETs,
  no object. The write: the four GETs and exactly one PATCH of `Approval_EndUser_Assignment`; no
  400, no warning, no error -- Microsoft Graph v1.0 accepted the approvers in the
  `userId`/`groupId` shape. The object: `ChangedRuleIds [Approval_EndUser_Assignment]`,
  `RequireApproval True`, exactly the expected set, `DisplayName filled: False` (the rule as sent);
  every other setting 1.1's.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002'".
  === 2.2 plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 4
      GET v1.0/users
      GET v1.0/groups
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.2 write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 5
      GET v1.0/users
      GET v1.0/groups
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Approval_EndUser_Assignment
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 2.2 returned: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader; ChangedRuleIds [Approval_EndUser_Assignment]
      ActivationMaxHours 1; on activation: MFA False, justification True, ticket False; AuthenticationContextId ''
      eligible: permanent allowed True, P365D; active: permanent allowed True, P180D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: False
        Group oer-s63-approvers; DisplayName filled: False
      approvers are exactly the expected set: True
  ```

- [x] **2.3 The approval rule read back RAW from Graph v1.0 -- which fields each approver comes back with.**

  ```powershell
  Show-S63RawApproval -PolicyId $PolicyIdRR -Label '2.3-rr-approval-raw'
  $P23 = Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop
  Show-S63Policy -Policy $P23 -Label '2.3 module read' -ExpectUser $IdApprover -ExpectGroup $IdApprovers
  ```

  **Expect:** `isApprovalRequired = True, approvalMode = SingleStage, stages = 1`, with the stage
  timeout and approver justification 1.1's raw approval line printed (the module carries undeclared
  stage fields over); `primary approvers: 2`: one `#microsoft.graph.singleUser` with
  `userId filled True` and `names oer-s63-approver`, one `#microsoft.graph.groupMembers` with
  `groupId filled True` and `names oer-s63-approvers` -- the PATCH was accepted in the
  `userId`/`groupId` shape and comes back in it. **Record each approver's `fields [...]` line and its
  `id filled`, `description filled` and `isBackup` values exactly**: which of `@odata.type`,
  `userId`/`groupId`, `id`, `description` and `isBackup` Graph v1.0 returns is the measurement this
  check exists for. The module read shows `approvers are exactly the expected set: True`, with
  `DisplayName filled` `True` wherever Graph returned a `description`.
  **Failure looks like:** `isApprovalRequired = False`, a missing or a third approver, or a module
  read that is not exactly the set. An approver with `userId filled False` and `groupId filled False`
  but `id filled True` is not a failure of the module (its reader falls back to `id`), but it
  contradicts the v1.0 premise the read and the PATCH both rest on: record it exactly.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. THE MEASUREMENT:
  Microsoft Graph v1.0 returns each approver with exactly `@odata.type`, `description` and `userId`
  (`#microsoft.graph.singleUser`) or `groupId` (`#microsoft.graph.groupMembers`) -- no `id` and no
  `isBackup` field at all; Graph filled `description` itself. `isApprovalRequired = True`,
  `SingleStage`, one stage, the one-day timeout and approver justification 1.1 recorded. The module
  read is exactly the set, `DisplayName` filled from `description`.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 2.3-rr-approval-raw: policy of Reports Reader, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
      #microsoft.graph.singleUser: fields [@odata.type, description, userId]
        userId filled True, groupId filled False, id filled False; names oer-s63-approver; description filled True; isBackup
      #microsoft.graph.groupMembers: fields [@odata.type, description, groupId]
        userId filled False, groupId filled True, id filled False; names oer-s63-approvers; description filled True; isBackup
  --- 2.3 module read: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 1; on activation: MFA False, justification True, ticket False; AuthenticationContextId ''
      eligible: permanent allowed True, P365D; active: permanent allowed True, P180D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  ```

- [x] **2.4 Activation hours, MFA, justification and ticket on activation, and both assignment durations -- one call.**

  The plan:

  ```powershell
  $Set24 = @{ Role = $RoleRR; ActivationMaxHours = 3; RequireMfaOnActivation = $true; RequireJustificationOnActivation = $true; RequireTicketOnActivation = $true
      AllowPermanentEligibility = $false; EligibleDuration = 90; AllowPermanentActiveAssignment = $false; ActiveDuration = 30 }
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat ($Set24 + @{ WhatIf = $true }) -Label '2.4 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat ($Set24 + @{ Confirm = $false }) -Label '2.4 write'
  Show-S63Policy -Policy ($S63Out | Select-Object -First 1) -Label '2.4 returned' -ExpectUser $IdApprover -ExpectGroup $IdApprovers
  ```

  **Expect:** the plan prints ONE `What if:` line,
  `"Update rules: <ids>" on target "directory role management policy '<PolicyIdRR>'"`, naming exactly
  `Expiration_EndUser_Assignment`, `Enablement_EndUser_Assignment`, `Expiration_Admin_Eligibility`
  and `Expiration_Admin_Assignment`, in the policy's own rule order -- no approval rule (not touched)
  and no authentication-context rule (1.1 recorded none enabled, so MFA raises no conflict). Two
  requests (the lookup and the assignment read), no PATCH, no warning. The write: the same two GETs,
  then exactly four PATCHes, one per rule id above and in the same order as the `What if:` line; no
  warning; no error; one object with `ActivationMaxHours 3`, `on activation: MFA True, justification True, ticket True`,
  `eligible: permanent allowed False, P90D`, `active: permanent allowed False, P30D`, `ChangedRuleIds`
  the four ids in the order sent, and still `RequireApproval True` with the approvers exactly 2.2's.
  (`-RequireTicketOnActivation` is there to make the enablement rule change for certain: a built-in
  role may already require MFA and justification. If 1.1 recorded all three on, that rule is missing
  from the list: record it.)
  **Failure looks like:** a fifth rule; a `PolicyRulesRejected` with a warning naming a rule -- record
  Graph's message; for the two expiration rules, a duration Graph refuses for a directory role is the
  likely cause (the portal offers a fixed list of durations; the module sends the ISO value it is
  given); the PATCHes in another order than the `What if:` line.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The plan named exactly
  the four rules, in the policy's own order: `Expiration_Admin_Eligibility`,
  `Expiration_Admin_Assignment`, `Enablement_EndUser_Assignment`, `Expiration_EndUser_Assignment`;
  two GETs, no warning. The write: four PATCHes in that order, no warning, no error, the expected
  values and `ChangedRuleIds` in the order sent. Graph accepted `P90D` and `P30D` for a directory
  role: no value was refused.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: Expiration_Admin_Eligibility, Expiration_Admin_Assignment, Enablement_EndUser_Assignment, Expiration_EndUser_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002'".
  === 2.4 plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.4 write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 6
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Expiration_Admin_Eligibility
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Expiration_Admin_Assignment
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Enablement_EndUser_Assignment
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Expiration_EndUser_Assignment
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 2.4 returned: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader; ChangedRuleIds [Expiration_Admin_Eligibility, Expiration_Admin_Assignment, Enablement_EndUser_Assignment, Expiration_EndUser_Assignment]
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  ```

- [x] **2.5 Read 2.4 back INDEPENDENTLY, raw from Graph v1.0, and through the module.**

  ```powershell
  Show-S63RawSettings -RoleDefinitionId $RoleIdRR -Label '2.5-rr-raw'
  $P25 = Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop
  Show-S63Policy -Policy $P25 -Label '2.5 module read' -ExpectUser $IdApprover -ExpectGroup $IdApprovers
  ```

  **Expect:** raw: `Expiration_EndUser_Assignment: maximumDuration PT3H`;
  `Enablement_EndUser_Assignment: enabledRules [Justification, MultiFactorAuthentication, Ticketing]`;
  `AuthenticationContext_EndUser_Assignment: isEnabled False` (as at 1.1);
  `Expiration_Admin_Eligibility: isExpirationRequired True, maximumDuration P90D`;
  `Expiration_Admin_Assignment: isExpirationRequired True, maximumDuration P30D`;
  `Approval_EndUser_Assignment: isApprovalRequired True`. The module read prints the same values as
  2.4's returned object, and `approvers are exactly the expected set: True`.
  **Failure looks like:** any raw value that is not what 2.4 returned -- the object reported a write
  Graph did not keep.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Every raw value is what
  2.4 returned; the context disabled with `claimValue (null)`; the module read the same values and
  exactly the set.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 2.5-rr-raw: policy of Reports Reader
      Expiration_EndUser_Assignment: maximumDuration PT3H
      Enablement_EndUser_Assignment: enabledRules [Justification, MultiFactorAuthentication, Ticketing]
      AuthenticationContext_EndUser_Assignment: isEnabled False, claimValue (null)
      Expiration_Admin_Eligibility: isExpirationRequired True, maximumDuration P90D
      Expiration_Admin_Assignment: isExpirationRequired True, maximumDuration P30D
      Approval_EndUser_Assignment: isApprovalRequired True
  --- 2.5 module read: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  ```

- [x] **2.6 `-ApproverUser` alone replaces the user side and KEEPS the group side.**

  The plan:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; ApproverUser = $Approver2Upn; WhatIf = $true } -Label '2.6 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; ApproverUser = $Approver2Upn; Confirm = $false } -Label '2.6 write'
  Show-S63Policy -Policy ($S63Out | Select-Object -First 1) -Label '2.6 returned' -ExpectUser $IdApprover2 -ExpectGroup $IdApprovers
  Show-S63RawApproval -PolicyId $PolicyIdRR -Label '2.6-rr-approval-raw'
  ```

  **Expect:** the plan: `What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "directory role management policy '<PolicyIdRR>'".`,
  three requests (`GET v1.0/users`, the lookup, the assignment read) -- no `GET v1.0/groups`, since
  `-ApproverGroup` is not bound. The write: the same three GETs and one PATCH of
  `Approval_EndUser_Assignment`; no warning, no error; the object: `RequireApproval True`,
  `User oer-s63-approver2` and `Group oer-s63-approvers`, `approvers are exactly the expected set: True`.
  Raw: `isApprovalRequired = True`, `primary approvers: 2`: a `#microsoft.graph.singleUser` naming
  `oer-s63-approver2` and a `#microsoft.graph.groupMembers` naming `oer-s63-approvers`.
  **Failure looks like:** `approvers: 1` with the group gone -- the unbound side was not carried (the
  Azure whole-list semantics leaked into the Graph path); `oer-s63-approver` still there.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The plan: the same `What
  if:` line, three GETs, no `GET v1.0/groups`. The write: those three and one PATCH; the user side
  replaced by `oer-s63-approver2`, the group side carried, exactly the set; raw the same two
  approvers.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002'".
  === 2.6 plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 3
      GET v1.0/users
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.6 write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 4
      GET v1.0/users
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Approval_EndUser_Assignment
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 2.6 returned: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader; ChangedRuleIds [Approval_EndUser_Assignment]
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver2; DisplayName filled: False
        Group oer-s63-approvers; DisplayName filled: False
      approvers are exactly the expected set: True
  --- 2.6-rr-approval-raw: policy of Reports Reader, isApprovalRequired = True, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
      #microsoft.graph.singleUser: fields [@odata.type, description, userId]
        userId filled True, groupId filled False, id filled False; names oer-s63-approver2; description filled True; isBackup
      #microsoft.graph.groupMembers: fields [@odata.type, description, groupId]
        userId filled False, groupId filled True, id filled False; names oer-s63-approvers; description filled True; isBackup
  ```

- [x] **2.7 `-RequireApproval $false` alone turns approval off and KEEPS the approvers on the stage.**

  The plan:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; RequireApproval = $false; WhatIf = $true } -Label '2.7 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; RequireApproval = $false; Confirm = $false } -Label '2.7 write'
  Show-S63Policy -Policy ($S63Out | Select-Object -First 1) -Label '2.7 returned' -ExpectUser $IdApprover2 -ExpectGroup $IdApprovers
  Show-S63RawApproval -PolicyId $PolicyIdRR -Label '2.7-rr-approval-raw'
  ```

  **Expect:** the plan: the same `What if:` line as 2.6; two requests (the lookup, the assignment
  read) -- no user or group lookup. The write: those two GETs and one PATCH of
  `Approval_EndUser_Assignment`; no warning, no error. This PATCH sends the live approvers back
  exactly as Graph returned them in 2.6 -- whatever fields 2.6's raw read listed, `description`
  included -- since `-RequireApproval` alone never rebuilds them. The object: `RequireApproval False`,
  still `User oer-s63-approver2` and `Group oer-s63-approvers`, exactly the set `True`. Raw:
  `isApprovalRequired = False`, `primary approvers: 2`, the same two names.
  **Failure looks like:** a `PolicyRulesRejected` for `Approval_EndUser_Assignment` -- Graph refuses
  its own read shape when it is sent back (a read-only field in the carried approvers): record the
  message. `primary approvers: 0` with approval off -- Graph dropped the stage's approvers by itself:
  not a module failure, but record it; 3.2's plan then starts from no approver.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The plan: two GETs, no
  user or group lookup. The write: one PATCH; Graph accepted the carried approvers as it had
  returned them; approval off, the same two approvers on the stage, raw and in the module.
  Recorded: after this PATCH Graph returned `description` EMPTY on both approvers (filled after
  2.6, and sent back filled); with approval on again in 3.3 it is filled again. No effect on the
  module, which compares ids.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: Approval_EndUser_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002'".
  === 2.7 plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.7 write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Approval_EndUser_Assignment
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 2.7 returned: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader; ChangedRuleIds [Approval_EndUser_Assignment]
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval False
      approvers: 2
        User oer-s63-approver2; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  --- 2.7-rr-approval-raw: policy of Reports Reader, isApprovalRequired = False, approvalMode = SingleStage, stages = 1, stage 1 timeout = 1 day(s), approver justification = True
      primary approvers: 2
      #microsoft.graph.singleUser: fields [@odata.type, description, userId]
        userId filled True, groupId filled False, id filled False; names oer-s63-approver2; description filled False; isBackup
      #microsoft.graph.groupMembers: fields [@odata.type, description, groupId]
        userId filled False, groupId filled True, id filled False; names oer-s63-approvers; description filled False; isBackup
  ```

- [x] **2.8 `ApproverRequired` on Message Center Reader -- only while its policy has no approver.** `-WhatIf` only.

  ```powershell
  "Message Center Reader approvers at 1.1: $((Get-Content (Join-Path $Raw '1.1-module-view.json') -Raw | ConvertFrom-Json).mcr.ApproverCount)"
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleMCR; RequireApproval = $true; WhatIf = $true } -Label '2.8a approval with no approver'
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleMCR; ApproverGroup = [string[]]@(); WhatIf = $true } -Label '2.8b an approver side emptied on a policy with none'
  ```

  **Expect:** the first line prints `0` -- otherwise this box is `[~]`, since the guard cannot fire
  on a policy that has approvers: write the count and why. Both calls: two requests (the lookup and
  the assignment read -- no user or group lookup: (a) binds none, (b) binds an empty list), no
  `What if:` line, no object, exactly one published error. (a)
  `ApproverRequired,Set-OERDirectoryRoleManagementPolicy`: `Approval cannot be required with no approver: directory role management policy '<PolicyIdMCR>' has none on its live approval rule and none was supplied. Pass -ApproverUser or -ApproverGroup.`
  (b) `ApproverRequired,Set-OERDirectoryRoleManagementPolicy`: `Approval cannot be required with no approver: after -ApproverUser/-ApproverGroup are applied, directory role management policy '<PolicyIdMCR>' would have none. Pass at least one approver.`
  **Failure looks like:** a `What if: ... "Update rules: Approval_EndUser_Assignment" ...` line -- the
  guard let approval with no approver through to the PATCH.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Message Center Reader
  had `0` approvers at 1.1. Both calls: two requests, no `What if:`, no object, exactly one
  `ApproverRequired` each, with the expected texts.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  Message Center Reader approvers at 1.1: 0
  === 2.8a approval with no approver -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [ApproverRequired,Set-OERDirectoryRoleManagementPolicy]: Approval cannot be required with no approver: directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004' has none on its live approval rule and none was supplied. Pass -ApproverUser or -ApproverGroup.
  --- objects returned: 0
  === 2.8b an approver side emptied on a policy with none -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 1 (other records collected, not shown: 0)
      ERROR [ApproverRequired,Set-OERDirectoryRoleManagementPolicy]: Approval cannot be required with no approver: after -ApproverUser/-ApproverGroup are applied, directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004' would have none. Pass at least one approver.
  --- objects returned: 0
  ```

---

### 3. The apply document -- `directoryRoleManagementPolicies[]`

Document `$Docs.DirBoth`: both roles, each declaring `"requireApproval": true` and
`"approvers": { "users": [ "<ApproverUpn>" ], "groups": [ "oer-s63-approvers" ] }` -- a UPN and a
display name, never an id; Message Center Reader also declares `"activationMaxHours": 2`.

- [x] **3.1 Offline validation: the document is valid, a `scope` key warns, and MFA with a context is refused.**

  ```powershell
  Invoke-S63Check -Id '3.1a' -Json $Docs.DirBoth -Include DirectoryRoleManagementPolicies -ValidateOnly
  Invoke-S63Check -Id '3.1b' -Json $Docs.DirScopeKey -Include DirectoryRoleManagementPolicies -ValidateOnly
  Invoke-S63Check -Id '3.1c' -Json $Docs.DirBothSides -Include DirectoryRoleManagementPolicies -ValidateOnly
  ```

  **Expect:** nothing is sent (validation only). 3.1a: `Valid = True, findings = 0`. 3.1b
  (`$Docs.DirScopeKey`, Reports Reader with `"scope": "/"`): `Valid = True, findings = 1` --
  Section `directoryRoleManagementPolicies`, Item `Reports Reader`, Path
  `directoryRoleManagementPolicies[0].scope`, Severity `Warning`, Message
  `Unknown key 'scope' at directoryRoleManagementPolicies[0] is not applied by Invoke-OERStructure and will be ignored.`
  3.1c (`$Docs.DirBothSides`, `requireMfaOnActivation` true and `authenticationContextId` `c1`):
  `Valid = False, findings = 1` -- Path `directoryRoleManagementPolicies[0]`, Severity `Error`,
  Message `'requireMfaOnActivation' and 'authenticationContextId' at directoryRoleManagementPolicies[0] are mutually exclusive in PIM; declare only one.`
  -- "PIM", not "Azure PIM".
  **Failure looks like:** a `scope` key that validates silently, or turns the document invalid; 3.1c
  valid.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Nothing sent. 3.1a valid
  with no finding; 3.1b valid with one `scope` Warning at the expected path and text; 3.1c invalid
  with the one Error, "PIM", not "Azure PIM".

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.1a -- <Repo>\docs\live-verification\raw\s63\3.1a.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } },
          { "role": "Message Center Reader", "activationMaxHours": 2, "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  === 3.1b -- <Repo>\docs\live-verification\raw\s63\3.1b.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "scope": "/", "activationMaxHours": 3 }
        ]
      }
  --- offline validation: Valid = True, findings = 1
  Section  : directoryRoleManagementPolicies
  Item     : Reports Reader
  Path     : directoryRoleManagementPolicies[0].scope
  Severity : Warning
  Message  : Unknown key 'scope' at directoryRoleManagementPolicies[0] is not applied by Invoke-OERStructure and will be ignored.
  === 3.1c -- <Repo>\docs\live-verification\raw\s63\3.1c.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireMfaOnActivation": true, "authenticationContextId": "c1" }
        ]
      }
  --- offline validation: Valid = False, findings = 1
  Section  : directoryRoleManagementPolicies
  Item     : Reports Reader
  Path     : directoryRoleManagementPolicies[0]
  Severity : Error
  Message  : 'requireMfaOnActivation' and 'authenticationContextId' at directoryRoleManagementPolicies[0] are mutually exclusive in PIM; declare only one.
  ```

- [x] **3.2 The plan: both policies would change, and the declared names are compared as ids.**

  ```powershell
  Invoke-S63Check -Id '3.2' -Json $Docs.DirBoth -Include DirectoryRoleManagementPolicies
  ```

  **Expect:** `Valid = True`, `0` findings. Two lines, Reports Reader first:
  `What if: Performing the operation "Update directory role management policy" on target "Reports Reader".`
  and the same for `Message Center Reader`. No warning, no error. Exactly two results, both Section
  `directoryRoleManagementPolicies`, in document order: Item `Reports Reader`, `Skipped`,
  `would update directory role management policy for 'Reports Reader' (requireApproval=True, approvers(users=[<IdApprover>],groups=[<IdApprovers>]))`;
  Item `Message Center Reader`, `Skipped`,
  `would update directory role management policy for 'Message Center Reader' (requireApproval=True, activationMaxHours=2, approvers(users=[<IdApprover>],groups=[<IdApprovers>]))`.
  The approvers are OBJECT ids: the UPN and the group name were resolved before the diff. Both
  declared sides are named although only the user side differs on Reports Reader: every declared side
  is sent.
  **Failure looks like:** a UPN or a group name inside `approvers(...)` -- a name compared with an id;
  a `Failed` row (read it: a lookup refusal is a missing permission).
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Valid, no finding; two
  `What if:` lines, Reports Reader first; no warning, no error; two `Skipped` rows in document
  order with the expected details -- the approvers as OBJECT ids.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.2 -- <Repo>\docs\live-verification\raw\s63\3.2.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } },
          { "role": "Message Center Reader", "activationMaxHours": 2, "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -WhatIf
  What if: Performing the operation "Update directory role management policy" on target "Reports Reader".
  What if: Performing the operation "Update directory role management policy" on target "Message Center Reader".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 2
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Skipped
  Detail  : would update directory role management policy for 'Reports Reader' (requireApproval=True, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  Section : directoryRoleManagementPolicies
  Item    : Message Center Reader
  Action  : Skipped
  Detail  : would update directory role management policy for 'Message Center Reader' (requireApproval=True, activationMaxHours=2, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  --- action counts: Skipped=2
  ```

- [x] **3.3 Run 1, applied, and read back.**

  ```powershell
  Invoke-S63Check -Id '3.3' -Json $Docs.DirBoth -Include DirectoryRoleManagementPolicies -Apply
  foreach ($R in $RoleRR, $RoleMCR) {
      Show-S63Policy -Policy (Get-OERDirectoryRoleManagementPolicy -Role $R -ErrorAction Stop) -Label "3.3 $R" -ExpectUser $IdApprover -ExpectGroup $IdApprovers
  }
  ```

  **Expect:** no warning, no error; two results in document order: `Reports Reader` `Updated`
  `updated directory role management policy for 'Reports Reader' (requireApproval=True, approvers(users=[<IdApprover>],groups=[<IdApprovers>]))`
  and `Message Center Reader` `Updated`
  `updated directory role management policy for 'Message Center Reader' (requireApproval=True, activationMaxHours=2, approvers(users=[<IdApprover>],groups=[<IdApprovers>]))`.
  Read back: both `RequireApproval True` and `approvers are exactly the expected set: True`; Reports
  Reader keeps `ActivationMaxHours 3` (2.4), Message Center Reader has `ActivationMaxHours 2`.
  **Failure looks like:** a `Failed` row -- record its detail and the published error.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. No warning, no error;
  two `Updated` rows with the expected details. Read back: both `RequireApproval True` and exactly
  the set; Reports Reader keeps 3 hours, Message Center Reader has 2.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3 -- <Repo>\docs\live-verification\raw\s63\3.3.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } },
          { "role": "Message Center Reader", "activationMaxHours": 2, "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 2
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Updated
  Detail  : updated directory role management policy for 'Reports Reader' (requireApproval=True, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  Section : directoryRoleManagementPolicies
  Item    : Message Center Reader
  Action  : Updated
  Detail  : updated directory role management policy for 'Message Center Reader' (requireApproval=True, activationMaxHours=2, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  --- action counts: Updated=2
  --- 3.3 Reports Reader: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  --- 3.3 Message Center Reader: policy of Message Center Reader; Scope '/'; RoleName 'Message Center Reader'; RoleDefinitionId: Message Center Reader
      ActivationMaxHours 2; on activation: MFA False, justification True, ticket False; AuthenticationContextId ''
      eligible: permanent allowed True, P365D; active: permanent allowed True, P180D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  ```

- [x] **3.4 Run 2: only `Unchanged` -- the proof that the v1.0 read shape converges.**

  ```powershell
  Invoke-S63Check -Id '3.4' -Json $Docs.DirBoth -Include DirectoryRoleManagementPolicies -Apply
  ```

  **Expect:** no warning, no error; exactly two results, `Reports Reader` `Unchanged`
  `policy already matches for 'Reports Reader'` and `Message Center Reader` `Unchanged`
  `policy already matches for 'Message Center Reader'`.
  **Failure looks like:** an `Updated` row naming `approvers(...)` -- the live approvers, read through
  `ConvertFrom-OERGraphApprover`, do not match the resolved ids, and every run would rewrite the rule.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Exactly two `Unchanged`
  rows, no warning, no error: the v1.0 read shape converges.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.4 -- <Repo>\docs\live-verification\raw\s63\3.4.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } },
          { "role": "Message Center Reader", "activationMaxHours": 2, "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 2
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Unchanged
  Detail  : policy already matches for 'Reports Reader'
  Section : directoryRoleManagementPolicies
  Item    : Message Center Reader
  Action  : Unchanged
  Detail  : policy already matches for 'Message Center Reader'
  --- action counts: Unchanged=2
  ```

Document `$Docs.DirUsersOnly`: Reports Reader only, `"requireApproval": true` and
`"approvers": { "users": [ "<Approver2Upn>" ] }` -- the user side declared, the group side not
declared at all.

- [x] **3.5 Only the declared side is sent: the user side changes, the undeclared group side stays.**

  The plan:

  ```powershell
  Invoke-S63Check -Id '3.5a' -Json $Docs.DirUsersOnly -Include DirectoryRoleManagementPolicies
  ```

  The apply, only once the plan matches:

  ```powershell
  Invoke-S63Check -Id '3.5b' -Json $Docs.DirUsersOnly -Include DirectoryRoleManagementPolicies -Apply
  Show-S63Policy -Policy (Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop) -Label '3.5 read' -ExpectUser $IdApprover2 -ExpectGroup $IdApprovers
  ```

  **Expect:** the plan: `Valid = True`, one `What if:` line on target `Reports Reader`, one result,
  `Skipped`, `would update directory role management policy for 'Reports Reader' (approvers(users=[<IdApprover2>]))`
  -- no `groups=` and no `requireApproval=` (already true). The apply: one result, `Updated`, the same
  detail with `updated`; no warning, no error. Read back: `RequireApproval True`,
  `User oer-s63-approver2` and `Group oer-s63-approvers`, exactly the set `True`.
  **Failure looks like:** `groups=[...]` in the detail -- the undeclared side was sent; the group gone
  from the read-back.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The plan: one `What
  if:`, one `Skipped` row with `approvers(users=[...])` only -- no `groups=` and no
  `requireApproval=`. The apply: `Updated`, the same detail; read back `oer-s63-approver2` and the
  carried group, exactly the set.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.5a -- <Repo>\docs\live-verification\raw\s63\3.5a.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person2@example.com" ] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -WhatIf
  What if: Performing the operation "Update directory role management policy" on target "Reports Reader".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Skipped
  Detail  : would update directory role management policy for 'Reports Reader' (approvers(users=[00000000-0000-0000-0000-000000000006]))
  --- action counts: Skipped=1

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.5b -- <Repo>\docs\live-verification\raw\s63\3.5b.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person2@example.com" ] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Updated
  Detail  : updated directory role management policy for 'Reports Reader' (approvers(users=[00000000-0000-0000-0000-000000000006]))
  --- action counts: Updated=1
  --- 3.5 read: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver2; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  ```

- [x] **3.6 That document converges.**

  ```powershell
  Invoke-S63Check -Id '3.6' -Json $Docs.DirUsersOnly -Include DirectoryRoleManagementPolicies -Apply
  ```

  **Expect:** one result, `Unchanged`, `policy already matches for 'Reports Reader'`; no warning, no
  error.
  **Failure looks like:** `Updated` again.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. One `Unchanged` row, no
  warning, no error.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.6 -- <Repo>\docs\live-verification\raw\s63\3.6.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person2@example.com" ] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Unchanged
  Detail  : policy already matches for 'Reports Reader'
  --- action counts: Unchanged=1
  ```

Document `$Docs.DirGroupsEmpty`: Reports Reader only, `"requireApproval": true` and
`"approvers": { "groups": [] }` -- the group side declared EMPTY, the user side not declared.

- [x] **3.7 A side declared `[]` is cleared, and the other side stays.**

  The plan:

  ```powershell
  Invoke-S63Check -Id '3.7a' -Json $Docs.DirGroupsEmpty -Include DirectoryRoleManagementPolicies
  ```

  The apply, only once the plan matches:

  ```powershell
  Invoke-S63Check -Id '3.7b' -Json $Docs.DirGroupsEmpty -Include DirectoryRoleManagementPolicies -Apply
  Show-S63Policy -Policy (Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop) -Label '3.7 read' -ExpectUser $IdApprover2 -ExpectGroup @()
  ```

  **Expect:** the plan: one `What if:` line on target `Reports Reader`, one result, `Skipped`,
  `would update directory role management policy for 'Reports Reader' (approvers(groups=[]))`. The
  apply: one result, `Updated`, `updated directory role management policy for 'Reports Reader' (approvers(groups=[]))`;
  no warning, no error. Read back: `RequireApproval True`, `approvers: 1`, `User oer-s63-approver2`,
  exactly the set `True`.
  **Failure looks like:** `users=[...]` in the detail; `approvers: 0` (the user side lost); an
  `ApproverRequired` error (the user side was not carried).
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The plan and the apply:
  `approvers(groups=[])` only; read back `approvers: 1`, the user side kept, exactly the set.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.7a -- <Repo>\docs\live-verification\raw\s63\3.7a.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "groups": [] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -WhatIf
  What if: Performing the operation "Update directory role management policy" on target "Reports Reader".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Skipped
  Detail  : would update directory role management policy for 'Reports Reader' (approvers(groups=[]))
  --- action counts: Skipped=1

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.7b -- <Repo>\docs\live-verification\raw\s63\3.7b.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "groups": [] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Updated
  Detail  : updated directory role management policy for 'Reports Reader' (approvers(groups=[]))
  --- action counts: Updated=1
  --- 3.7 read: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 1
        User oer-s63-approver2; DisplayName filled: True
      approvers are exactly the expected set: True
  ```

- [x] **3.8 The emptied side converges.**

  ```powershell
  Invoke-S63Check -Id '3.8' -Json $Docs.DirGroupsEmpty -Include DirectoryRoleManagementPolicies -Apply
  ```

  **Expect:** one result, `Unchanged`, `policy already matches for 'Reports Reader'`; no warning, no
  error.
  **Failure looks like:** a `Failed` row with an error `NoChange` (`No applicable policy rule changed.`)
  -- the declared empty side is compared as one null entry again, so the diff reports a change the
  write then finds nothing for, on every run: the defect "fix: converge a declared empty approver side
  on directory-role policies" closed. An `Updated` row.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. One `Unchanged` row, no
  `NoChange`, no warning: the declared empty side converges.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.8 -- <Repo>\docs\live-verification\raw\s63\3.8.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          { "role": "Reports Reader", "requireApproval": true, "approvers": { "groups": [] } }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Unchanged
  Detail  : policy already matches for 'Reports Reader'
  --- action counts: Unchanged=1
  ```

---

### 4. Authentication context on and off -- the rule pair and its PATCH order

Graph refuses MFA on activation while an authentication context is on, and accepts enabling a
context while MFA is on. So the module PATCHes a context being DISABLED before the activation rule,
and one being ENABLED after it. Reports Reader requires MFA on activation since 2.4.

- [x] **4.1 Enabling a context clears MFA, with a warning, and the context is PATCHed LAST.**

  The context, the starting state, and the plan:

  ```powershell
  $AcAll = @(Get-OERAuthenticationContext -Available -ErrorAction Stop)
  $AcId = ($AcAll | Select-Object -First 1).AuthenticationContextId
  $AcPublished = [bool]$AcId
  if (-not $AcId) { $AcId = 'c1' }
  Set-Content -Path (Join-Path $Raw '4.1-acid.txt') -Value $AcId -Encoding utf8NoBOM
  "published authentication contexts: $($AcAll.Count); using '$AcId'; published in this tenant: $AcPublished"
  $P41 = Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop
  "before: RequireMfaOnActivation $($P41.RequireMfaOnActivation); AuthenticationContextId '$($P41.AuthenticationContextId)'"
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; AuthenticationContextId = $AcId; WhatIf = $true } -Label '4.1 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; AuthenticationContextId = $AcId; Confirm = $false } -Label '4.1 write'
  Show-S63Policy -Policy ($S63Out | Select-Object -First 1) -Label '4.1 returned'
  Show-S63RawSettings -RoleDefinitionId $RoleIdRR -Label '4.1-rr-raw'
  ```

  **Expect:** `published authentication contexts: <n>; using '<AcId>'; published in this tenant: True`,
  and `before: RequireMfaOnActivation True; AuthenticationContextId ''`. If the tenant publishes none,
  the line reads `0; using 'c1'; ... False`: Graph accepts a claim value no context defines (the
  cmdlet checks the `c<number>` shape only, as `Set-OERRoleManagementPolicy` does), so the check
  still proves the rule pair and its order -- record it, since an end user activating Reports Reader
  before the Teardown would then fail at an unknown context (nobody activates it in this file). The
  plan: one warning, `Policy '<PolicyIdRR>': mfa cleared: mutually exclusive with authenticationContextId=<AcId>`;
  `What if: Performing the operation "Update rules: Enablement_EndUser_Assignment, AuthenticationContext_EndUser_Assignment" on target "directory role management policy '<PolicyIdRR>'".`
  -- the enablement rule FIRST; two requests, no PATCH. The write: the same warning; the two GETs,
  then exactly two PATCHes in this order,
  `PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Enablement_EndUser_Assignment`
  then `.../rules/AuthenticationContext_EndUser_Assignment`; no error; the object
  `ChangedRuleIds [Enablement_EndUser_Assignment, AuthenticationContext_EndUser_Assignment]`,
  `on activation: MFA False, justification True, ticket True; AuthenticationContextId '<AcId>'`. Raw:
  `enabledRules [Justification, Ticketing]` and
  `AuthenticationContext_EndUser_Assignment: isEnabled True, claimValue '<AcId>'`.
  **Failure looks like:** the context PATCH before the enablement PATCH; MFA still `True` beside an
  enabled context (the reconcile did not happen); a `PolicyRulesRejected` naming either rule --
  record Graph's message.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The tenant publishes two
  authentication contexts; `c1` is one of them. Before: MFA on, no context. The plan and the write:
  one warning, the enablement rule FIRST and the context rule second, two PATCHes in that order, no
  error. After: MFA off, context `c1`, raw `isEnabled True, claimValue 'c1'`.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  published authentication contexts: 2; using 'c1'; published in this tenant: True
  before: RequireMfaOnActivation True; AuthenticationContextId ''
  What if: Performing the operation "Update rules: Enablement_EndUser_Assignment, AuthenticationContext_EndUser_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002'".
  === 4.1 plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 1
      WARNING: Policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002': mfa cleared: mutually exclusive with authenticationContextId=c1
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.1 write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 4
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Enablement_EndUser_Assignment
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/AuthenticationContext_EndUser_Assignment
  --- warnings: 1
      WARNING: Policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002': mfa cleared: mutually exclusive with authenticationContextId=c1
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 4.1 returned: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader; ChangedRuleIds [Enablement_EndUser_Assignment, AuthenticationContext_EndUser_Assignment]
      ActivationMaxHours 3; on activation: MFA False, justification True, ticket True; AuthenticationContextId 'c1'
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 1
        User oer-s63-approver2; DisplayName filled: True
  --- 4.1-rr-raw: policy of Reports Reader
      Expiration_EndUser_Assignment: maximumDuration PT3H
      Enablement_EndUser_Assignment: enabledRules [Justification, Ticketing]
      AuthenticationContext_EndUser_Assignment: isEnabled True, claimValue 'c1'
      Expiration_Admin_Eligibility: isExpirationRequired True, maximumDuration P90D
      Expiration_Admin_Assignment: isExpirationRequired True, maximumDuration P30D
      Approval_EndUser_Assignment: isApprovalRequired True
  ```

- [x] **4.2 Requiring MFA disables the context, with a warning, and the context is PATCHed FIRST.**

  The plan:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; RequireMfaOnActivation = $true; WhatIf = $true } -Label '4.2 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR; RequireMfaOnActivation = $true; Confirm = $false } -Label '4.2 write'
  Show-S63Policy -Policy ($S63Out | Select-Object -First 1) -Label '4.2 returned'
  Show-S63RawSettings -RoleDefinitionId $RoleIdRR -Label '4.2-rr-raw'
  ```

  **Expect:** the plan: one warning,
  `Policy '<PolicyIdRR>': authentication context '<AcId>' disabled: mutually exclusive with multi-factor authentication on activation`;
  `What if: Performing the operation "Update rules: AuthenticationContext_EndUser_Assignment, Enablement_EndUser_Assignment" on target "directory role management policy '<PolicyIdRR>'".`
  -- the context rule FIRST; no PATCH. The write: the same warning; the two GETs, then exactly two
  PATCHes, `.../rules/AuthenticationContext_EndUser_Assignment` then
  `.../rules/Enablement_EndUser_Assignment`; no error; the object
  `ChangedRuleIds [AuthenticationContext_EndUser_Assignment, Enablement_EndUser_Assignment]`,
  `on activation: MFA True, justification True, ticket True; AuthenticationContextId ''`. Raw:
  `enabledRules [Justification, MultiFactorAuthentication, Ticketing]` and
  `AuthenticationContext_EndUser_Assignment: isEnabled False, claimValue ...` -- **record exactly
  what `claimValue` came back as** (`''` or `(null)`). Either is fine: the module sends `''` to
  disable a context and reads `''` and null alike, and the comparisons in 1.1, T.1 and T.4 (and the
  prerequisite script's teardown) do the same, so a disabled context never counts as "not back at its
  baseline" over which of the two Graph stores.
  **Failure looks like:** the enablement PATCH first -- Graph then refuses it with
  `MfaAndAcrsConflict` (a `PolicyRulesRejected` naming `Enablement_EndUser_Assignment`), and the policy
  is left with the context disabled and MFA off: neither protection in force, the defect
  `Get-OERPimRulePatchOrder` exists to prevent.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. One warning; the context
  rule PATCHed FIRST, then the enablement rule; no error, no `MfaAndAcrsConflict`. After: MFA on,
  no context. Recorded exactly: Graph returned the disabled context with `claimValue ''` (an empty
  string, not null).

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: AuthenticationContext_EndUser_Assignment, Enablement_EndUser_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002'".
  === 4.2 plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
  --- warnings: 1
      WARNING: Policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002': authentication context 'c1' disabled: mutually exclusive with multi-factor authentication on activation
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.2 write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 4
      GET v1.0/roleManagement/directory/roleDefinitions
      GET v1.0/policies/roleManagementPolicyAssignments
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/AuthenticationContext_EndUser_Assignment
      PATCH v1.0/policies/roleManagementPolicies/<Reports Reader>/rules/Enablement_EndUser_Assignment
  --- warnings: 1
      WARNING: Policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002': authentication context 'c1' disabled: mutually exclusive with multi-factor authentication on activation
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 4.2 returned: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader; ChangedRuleIds [AuthenticationContext_EndUser_Assignment, Enablement_EndUser_Assignment]
      ActivationMaxHours 3; on activation: MFA True, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 1
        User oer-s63-approver2; DisplayName filled: True
  --- 4.2-rr-raw: policy of Reports Reader
      Expiration_EndUser_Assignment: maximumDuration PT3H
      Enablement_EndUser_Assignment: enabledRules [Justification, MultiFactorAuthentication, Ticketing]
      AuthenticationContext_EndUser_Assignment: isEnabled False, claimValue ''
      Expiration_Admin_Eligibility: isExpirationRequired True, maximumDuration P90D
      Expiration_Admin_Assignment: isExpirationRequired True, maximumDuration P30D
      Approval_EndUser_Assignment: isApprovalRequired True
  ```

- [x] **4.3 A document declaring the context: run 1 clears MFA with the same warning, run 2 is `Unchanged`.**

  The document -- Reports Reader declaring only `"authenticationContextId": "<AcId>"` -- and its plan:

  ```powershell
  $Docs.DirAcOn = New-S63AcDocument -Value $AcId
  Invoke-S63Check -Id '4.3a' -Json $Docs.DirAcOn -Include DirectoryRoleManagementPolicies
  ```

  Run 1 and run 2, only once the plan matches:

  ```powershell
  Invoke-S63Check -Id '4.3b' -Json $Docs.DirAcOn -Include DirectoryRoleManagementPolicies -Apply
  Invoke-S63Check -Id '4.3c' -Json $Docs.DirAcOn -Include DirectoryRoleManagementPolicies -Apply
  Show-S63Policy -Policy (Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop) -Label '4.3 read'
  ```

  **Expect:** 4.3a: `Valid = True`, `0` findings; one `What if:` line on target `Reports Reader`;
  one result, `Skipped`,
  `would update directory role management policy for 'Reports Reader' (authenticationContextId=<AcId>)`;
  no warning (the plan never reaches the Set). 4.3b: exactly one warning,
  `Policy '<PolicyIdRR>': mfa cleared: mutually exclusive with authenticationContextId=<AcId>`
  (from the Set the handler calls); one result, `Updated`,
  `updated directory role management policy for 'Reports Reader' (authenticationContextId=<AcId>)`;
  no error. 4.3c: one result, `Unchanged`, `policy already matches for 'Reports Reader'`; no
  warning. Read: `MFA False`, `AuthenticationContextId '<AcId>'`.
  **Failure looks like:** 4.3c `Updated` again; a `Failed` row in 4.3b.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. 4.3a valid, one `What
  if:`, `Skipped`, no warning. 4.3b the one warning, `Updated`, no error. 4.3c `Unchanged`, no
  warning. Read: MFA off, context `c1`.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.3a -- <Repo>\docs\live-verification\raw\s63\4.3a.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          {
            "role": "Reports Reader",
            "authenticationContextId": "c1"
          }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -WhatIf
  What if: Performing the operation "Update directory role management policy" on target "Reports Reader".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Skipped
  Detail  : would update directory role management policy for 'Reports Reader' (authenticationContextId=c1)
  --- action counts: Skipped=1

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.3b -- <Repo>\docs\live-verification\raw\s63\4.3b.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          {
            "role": "Reports Reader",
            "authenticationContextId": "c1"
          }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 1
      WARNING: Policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002': mfa cleared: mutually exclusive with authenticationContextId=c1
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Updated
  Detail  : updated directory role management policy for 'Reports Reader' (authenticationContextId=c1)
  --- action counts: Updated=1
  === 4.3c -- <Repo>\docs\live-verification\raw\s63\4.3c.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          {
            "role": "Reports Reader",
            "authenticationContextId": "c1"
          }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Unchanged
  Detail  : policy already matches for 'Reports Reader'
  --- action counts: Unchanged=1
  --- 4.3 read: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 3; on activation: MFA False, justification True, ticket True; AuthenticationContextId 'c1'
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 1
        User oer-s63-approver2; DisplayName filled: True
  ```

- [x] **4.4 A document declaring the context `""`: run 1 disables it, run 2 is `Unchanged`.**

  The document -- Reports Reader declaring only `"authenticationContextId": ""` -- and its plan:

  ```powershell
  $Docs.DirAcOff = New-S63AcDocument -Value ''
  Invoke-S63Check -Id '4.4a' -Json $Docs.DirAcOff -Include DirectoryRoleManagementPolicies
  ```

  Run 1 and run 2, only once the plan matches:

  ```powershell
  Invoke-S63Check -Id '4.4b' -Json $Docs.DirAcOff -Include DirectoryRoleManagementPolicies -Apply
  Invoke-S63Check -Id '4.4c' -Json $Docs.DirAcOff -Include DirectoryRoleManagementPolicies -Apply
  Show-S63Policy -Policy (Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop) -Label '4.4 read'
  ```

  **Expect:** 4.4a: `Valid = True`; one `What if:` line; `Skipped`,
  `would update directory role management policy for 'Reports Reader' (authenticationContextId=)`.
  4.4b: `Updated`, `updated directory role management policy for 'Reports Reader' (authenticationContextId=)`;
  no warning (disabling a context conflicts with nothing), no error. 4.4c: `Unchanged`,
  `policy already matches for 'Reports Reader'`. Read: `AuthenticationContextId ''` and `MFA False` --
  disabling a context never puts MFA back; justification and ticket still `True`.
  **Failure looks like:** 4.4c `Updated` again -- an empty declared value and a disabled live context
  compared as different; MFA `True` after 4.4b.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. 4.4a `Skipped` with
  `authenticationContextId=`. 4.4b `Updated`, no warning, no error. 4.4c `Unchanged`. Read: no
  context, MFA still off, justification and ticket on.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.4a -- <Repo>\docs\live-verification\raw\s63\4.4a.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          {
            "role": "Reports Reader",
            "authenticationContextId": ""
          }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -WhatIf
  What if: Performing the operation "Update directory role management policy" on target "Reports Reader".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Skipped
  Detail  : would update directory role management policy for 'Reports Reader' (authenticationContextId=)
  --- action counts: Skipped=1

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.4b -- <Repo>\docs\live-verification\raw\s63\4.4b.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          {
            "role": "Reports Reader",
            "authenticationContextId": ""
          }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Updated
  Detail  : updated directory role management policy for 'Reports Reader' (authenticationContextId=)
  --- action counts: Updated=1
  === 4.4c -- <Repo>\docs\live-verification\raw\s63\4.4c.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          {
            "role": "Reports Reader",
            "authenticationContextId": ""
          }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 1
  Section : directoryRoleManagementPolicies
  Item    : Reports Reader
  Action  : Unchanged
  Detail  : policy already matches for 'Reports Reader'
  --- action counts: Unchanged=1
  --- 4.4 read: policy of Reports Reader; Scope '/'; RoleName 'Reports Reader'; RoleDefinitionId: Reports Reader
      ActivationMaxHours 3; on activation: MFA False, justification True, ticket True; AuthenticationContextId ''
      eligible: permanent allowed False, P90D; active: permanent allowed False, P30D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 1
        User oer-s63-approver2; DisplayName filled: True
  ```

---

### 5. The Azure path through the helpers this branch changed

The directory-role code shares the rule builder, the policy projection and the diff with the Azure
path, each given a mode whose default is the Azure behaviour. This section runs the Azure path
through them once more, on the Reader policy at `oer-s63-rg`, and runs one document holding both
sections. It changes that policy's activation hours (to 2, then 3), its approval and its approvers.
The policy outlives its resource group, so none of this may survive the run: the prerequisite
script's teardown restores the whole recorded rule set from the Reader record 1.4 checked -- whether
or not T.1 has put the hours back, and also after a run that stops part-way here (T.3).

- [x] **5.1 `Set-OERRoleManagementPolicy -ActivationMaxHours 2` on the Reader policy at `oer-s63-rg`.**

  The plan:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERRoleManagementPolicy -Splat @{ Role = 'Reader'; Scope = $RgScope; ActivationMaxHours = 2; WhatIf = $true } -Label '5.1 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERRoleManagementPolicy -Splat @{ Role = 'Reader'; Scope = $RgScope; ActivationMaxHours = 2; Confirm = $false } -Label '5.1 write'
  $Ret51 = $S63Out | Select-Object -First 1
  $A51 = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  'returned ActivationMaxHours {0}, ChangedRuleIds [{1}]; read back ActivationMaxHours {2}, RequireApproval {3}, approvers {4}' -f $Ret51.ActivationMaxHours,
      (@($Ret51.ChangedRuleIds) -join ', '), $A51.ActivationMaxHours, $A51.RequireApproval, @($A51.Approvers | Where-Object { $_ }).Count
  ```

  **Expect:** the plan:
  `What if: Performing the operation "Update rules: Expiration_EndUser_Assignment" on target "role management policy '<ArmPolicyId>'".`;
  only Azure Resource Manager `GET` requests (paths starting `/subscriptions/<id>/` or `/providers/`),
  no `v1.0/` request. The write: the same reads, then exactly ONE `PATCH` of the Reader policy's ARM
  path -- the whole rule set in one request, unlike the directory path's one per rule; no warning, no
  error; the line prints `returned ActivationMaxHours 2, ChangedRuleIds [Expiration_EndUser_Assignment]; read back ActivationMaxHours 2, RequireApproval False, approvers 0`.
  **Failure looks like:** a `v1.0/` request, more than one rule id, or `NoChange` (1.4 recorded `2`).
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The plan: one `What if:`
  naming `Expiration_EndUser_Assignment`, Azure Resource Manager GETs only. The write: exactly one
  ARM PATCH, no warning, no error, and the line as expected.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: Expiration_EndUser_Assignment" on target "role management policy '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000008'".
  === 5.1 plan -- Set-OERRoleManagementPolicy
  --- requests, in the order sent: 3
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleDefinitions
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicyAssignments
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/<id>
  --- warnings: 0
  --- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.1 write -- Set-OERRoleManagementPolicy
  --- requests, in the order sent: 4
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleDefinitions
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicyAssignments
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/<id>
      PATCH /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/<id>
  --- warnings: 0
  --- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  returned ActivationMaxHours 2, ChangedRuleIds [Expiration_EndUser_Assignment]; read back ActivationMaxHours 2, RequireApproval False, approvers 0
  ```

Document `$Docs.Mixed`: `roleManagementPolicies[]` FIRST in the text -- Reader at `<RgScope>` with
`"activationMaxHours": 3`, `"requireApproval": true` and
`"approvers": { "users": [ "<ApproverUpn>" ], "groups": [ "oer-s63-approvers" ] }` -- then
`directoryRoleManagementPolicies[]` with Message Center Reader and `"activationMaxHours": 3`.

- [x] **5.2 The plan: the directory row comes first, whatever the document and `-Include` say.**

  ```powershell
  Invoke-S63Check -Id '5.2' -Json $Docs.Mixed -Include RoleManagementPolicies, DirectoryRoleManagementPolicies
  ```

  **Expect:** `Valid = True`, `0` findings. Two `What if:` lines in THIS order:
  `... "Update directory role management policy" on target "Message Center Reader".`, then
  `... "Update role management policy" on target "Reader @ <RgScope>".` No warning, no error. Two
  results in the same order: Section `directoryRoleManagementPolicies`, Item `Message Center Reader`,
  `Skipped`, `would update directory role management policy for 'Message Center Reader' (activationMaxHours=3)`;
  Section `roleManagementPolicies`, Item `Reader @ <RgScope>`, `Skipped`,
  `would update role management policy for 'Reader' at '<RgScope>'`. The document and `-Include` both
  list the Azure section first; the engine's own section order decides.
  **Failure looks like:** the Azure row first; a `Failed` row.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Valid; the directory row
  FIRST in the `What if:` lines and in the results, although the document and `-Include` list the
  Azure section first; no warning, no error.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.2 -- <Repo>\docs\live-verification\raw\s63\5.2.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "roleManagementPolicies": [
          {
            "scope": "/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg",
            "role": "Reader",
            "activationMaxHours": 3,
            "requireApproval": true,
            "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] }
          }
        ],
        "directoryRoleManagementPolicies": [
          { "role": "Message Center Reader", "activationMaxHours": 3 }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include RoleManagementPolicies,DirectoryRoleManagementPolicies -WhatIf
  What if: Performing the operation "Update directory role management policy" on target "Message Center Reader".
  What if: Performing the operation "Update role management policy" on target "Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 2
  Section : directoryRoleManagementPolicies
  Item    : Message Center Reader
  Action  : Skipped
  Detail  : would update directory role management policy for 'Message Center Reader' (activationMaxHours=3)
  Section : roleManagementPolicies
  Item    : Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg
  Action  : Skipped
  Detail  : would update role management policy for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg'
  --- action counts: Skipped=2
  ```

- [x] **5.3 Run 1, applied, and read back.**

  ```powershell
  Invoke-S63Check -Id '5.3' -Json $Docs.Mixed -Include RoleManagementPolicies, DirectoryRoleManagementPolicies -Apply
  $A53 = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  "Reader at oer-s63-rg: ActivationMaxHours $($A53.ActivationMaxHours); RequireApproval $($A53.RequireApproval)"
  Show-S63ModuleApprover -Policy $A53 -ExpectUser $IdApprover -ExpectGroup $IdApprovers
  Show-S63Policy -Policy (Get-OERDirectoryRoleManagementPolicy -Role $RoleMCR -ErrorAction Stop) -Label '5.3 Message Center Reader' -ExpectUser $IdApprover -ExpectGroup $IdApprovers
  ```

  **Expect:** no warning, no error; two results in the same order as 5.2: `Message Center Reader`
  `Updated` `updated directory role management policy for 'Message Center Reader' (activationMaxHours=3)`,
  then `Reader @ <RgScope>` `Updated`
  `updated role management policy for 'Reader' at '<RgScope>' (requireApproval=True, activationMaxHours=3, approvers(users=[<IdApprover>],groups=[<IdApprovers>]))`.
  Read back: `Reader at oer-s63-rg: ActivationMaxHours 3; RequireApproval True`, its approvers
  exactly the set `True`; Message Center Reader `ActivationMaxHours 3`, approvers still exactly 3.3's.
  **Failure looks like:** a `Failed` row; Message Center Reader's approvers changed (this document
  declares none for it).
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Two `Updated` rows in
  5.2's order with the expected details. Read back: Reader 3 hours, approval on, exactly the set;
  Message Center Reader 3 hours, its approvers still exactly 3.3's.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.3 -- <Repo>\docs\live-verification\raw\s63\5.3.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "roleManagementPolicies": [
          {
            "scope": "/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg",
            "role": "Reader",
            "activationMaxHours": 3,
            "requireApproval": true,
            "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] }
          }
        ],
        "directoryRoleManagementPolicies": [
          { "role": "Message Center Reader", "activationMaxHours": 3 }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include RoleManagementPolicies,DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 2
  Section : directoryRoleManagementPolicies
  Item    : Message Center Reader
  Action  : Updated
  Detail  : updated directory role management policy for 'Message Center Reader' (activationMaxHours=3)
  Section : roleManagementPolicies
  Item    : Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg
  Action  : Updated
  Detail  : updated role management policy for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg' (requireApproval=True, activationMaxHours=3, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  --- action counts: Updated=2
  Reader at oer-s63-rg: ActivationMaxHours 3; RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  --- 5.3 Message Center Reader: policy of Message Center Reader; Scope '/'; RoleName 'Message Center Reader'; RoleDefinitionId: Message Center Reader
      ActivationMaxHours 3; on activation: MFA False, justification True, ticket False; AuthenticationContextId ''
      eligible: permanent allowed True, P365D; active: permanent allowed True, P180D; on active assignment: MFA False, justification True
      RequireApproval True
      approvers: 2
        User oer-s63-approver; DisplayName filled: True
        Group oer-s63-approvers; DisplayName filled: True
      approvers are exactly the expected set: True
  ```

- [x] **5.4 Run 2: only `Unchanged`, in the same order.**

  ```powershell
  Invoke-S63Check -Id '5.4' -Json $Docs.Mixed -Include RoleManagementPolicies, DirectoryRoleManagementPolicies -Apply
  ```

  **Expect:** no warning, no error; two results, `Message Center Reader` `Unchanged`
  `policy already matches for 'Message Center Reader'`, then `Reader @ <RgScope>` `Unchanged`
  `policy already matches for 'Reader' at '<RgScope>'` -- the Azure approvers, named by UPN and group
  name, still converge through the shared diff and projection in their default mode.
  **Failure looks like:** an `Updated` row for the Reader policy naming `approvers(...)` -- the Azure
  approver key or projection changed with this branch.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Two `Unchanged` rows in
  the same order: the Azure approvers still converge through the shared helpers in their default
  mode.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 5.4 -- <Repo>\docs\live-verification\raw\s63\5.4.json
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "roleManagementPolicies": [
          {
            "scope": "/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg",
            "role": "Reader",
            "activationMaxHours": 3,
            "requireApproval": true,
            "approvers": { "users": [ "person1@example.com" ], "groups": [ "oer-s63-approvers" ] }
          }
        ],
        "directoryRoleManagementPolicies": [
          { "role": "Message Center Reader", "activationMaxHours": 3 }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include RoleManagementPolicies,DirectoryRoleManagementPolicies -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results: 2
  Section : directoryRoleManagementPolicies
  Item    : Message Center Reader
  Action  : Unchanged
  Detail  : policy already matches for 'Message Center Reader'
  Section : roleManagementPolicies
  Item    : Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg
  Action  : Unchanged
  Detail  : policy already matches for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg'
  --- action counts: Unchanged=2
  ```

---

### 6. A refused read is not a missing role

- [x] **6.1 A refused lookup and a refused policy read, by `oer-live-cc-noperm` in a process of its own.**

  A second process keeps this window's sign-in intact: the module keeps one credential per process.
  The script signs in app-only as `oer-live-cc-noperm` -- the same certificate, no API permission --
  and reads Reports Reader's policy by name and by role definition id, and runs the Set by name with
  `-WhatIf`: the lookup runs before ShouldProcess, so a refused lookup takes the path a real call
  would, and a sign-in that turns out to carry write rights still cannot write. This block records
  the activation hours for 6.2 -- whatever they are when section 6 runs -- picks for the Set a value
  that differs from them, writes the script and its inputs to the raw folder and runs it.

  ```powershell
  $Before61 = (Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop).ActivationMaxHours
  $Probe61 = if ($Before61 -eq 2) { 5 } else { 2 }
  "activation hours before 6.1: $Before61; the refused Set asks for: $Probe61"
  $RefusedReadPath = Join-Path $Raw '6.1-refused-read.ps1'
  [ordered]@{
      TenantId           = $TenantId
      NoPermAppId        = $NoPermAppId
      Thumbprint         = $Thumbprint
      RoleName           = $RoleRR
      RoleId             = $RoleIdRR
      ProbeHours         = $Probe61
      PSModulePathPrefix = (Resolve-Path (Join-Path $Repo 'output/module')).Path + [System.IO.Path]::PathSeparator + (Resolve-Path (Join-Path $Repo 'output/RequiredModules')).Path
  } | ConvertTo-Json | Set-Content -Path (Join-Path $Raw '6.1-input.json') -Encoding utf8NoBOM
  Set-Content -Path $RefusedReadPath -Value $RefusedReadScript -Encoding utf8NoBOM
  pwsh -NoProfile -File $RefusedReadPath
  ```

  **Expect:** first, in this window, `activation hours before 6.1: <n>; the refused Set asks for: <m>`
  with `<m>` different from `<n>` (`<n>` is 1.1's value when section 6 runs before 2.4, `3` after
  it). Then, from the second process: `identity check: session app id is oer-live-cc-noperm: True`, `identity check: tenant
  is the test tenant: True`, and `the token carries application permissions: 0`. (a)
  `result objects: 0`, `Errors published by Get-OERDirectoryRoleManagementPolicy: 1`,
  `ERROR [RoleDefinitionReadFailed,Get-OERDirectoryRoleManagementPolicy]: Looking up the Microsoft Entra directory role 'Reports Reader' failed, so whether it exists could not be determined: <cause>`.
  (b) `result objects: 0`, one `ERROR [PolicyReadFailed,Get-OERDirectoryRoleManagementPolicy]: <cause>`
  -- a GUID skips the lookup, so the policy-assignment read is the one refused. (c) NO `What if:`
  line, `result objects: 0`, one
  `ERROR [RoleDefinitionReadFailed,Set-OERDirectoryRoleManagementPolicy]: Looking up the Microsoft Entra directory role 'Reports Reader' failed, ...`.
  Both raw status lines read `403` (or another refusal status).
  **Failure looks like:** `RoleDefinitionNotFound` in (a) or (c), or `PolicyNotFound` in (b), while
  the raw status is `403` -- a refusal collapsed into absence, the defect this branch must not have.
  The same with a raw status of `200, 0 object(s)` is a different finding: Graph HID the object from
  this identity instead of refusing, and the module cannot tell that apart from absence -- record it
  as "cannot be verified, and therefore we do not know". A `What if:` line in (c) means this identity
  could read the role, so it is not a refused identity: nothing was written (`-WhatIf`), 6.2 still
  confirms it, and 6.1 is `[~]`. A `False` identity line, or a sign-in answering "application is
  disabled", means the run is not the one this check describes: stop and report it, never retry with
  another sign-in.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Hours before 6.1: 3, the
  refused Set asked for 2. The second process: both identity lines `True`, no application
  permission. (a) and (c) `RoleDefinitionReadFailed` (Authorization_RequestDenied), (b)
  `PolicyReadFailed`, no `What if:` in (c), raw `403` twice: a refusal never read as absence.
  Graph's refusal in (b) names the permissions that would admit the policy read:
  `RoleManagementPolicy.Read.Directory`, `RoleManagementPolicy.ReadWrite.Directory`,
  `RoleManagement.Read.Directory`, `RoleManagement.ReadWrite.Directory` and
  `RoleManagement.Read.All`.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  activation hours before 6.1: 3; the refused Set asks for: 2
  identity check: session app id is oer-live-cc-noperm: True
  identity check: tenant is the test tenant: True
  identity check: the token carries application permissions: 0
  (a) Get by name -- result objects: 0
  Errors published by Get-OERDirectoryRoleManagementPolicy: 1
  ERROR [RoleDefinitionReadFailed,Get-OERDirectoryRoleManagementPolicy]: Looking up the Microsoft Entra directory role 'Reports Reader' failed, so whether it exists could not be determined: Authorization_RequestDenied: Insufficient privileges to complete the operation.
  (b) Get by role definition id -- result objects: 0
  Errors published by Get-OERDirectoryRoleManagementPolicy: 1
  ERROR [PolicyReadFailed,Get-OERDirectoryRoleManagementPolicy]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleManagementPolicy.Read.Directory,RoleManagementPolicy.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  (c) Set by name, -WhatIf -- result objects: 0
  Errors published by Set-OERDirectoryRoleManagementPolicy: 1
  ERROR [RoleDefinitionReadFailed,Set-OERDirectoryRoleManagementPolicy]: Looking up the Microsoft Entra directory role 'Reports Reader' failed, so whether it exists could not be determined: Authorization_RequestDenied: Insufficient privileges to complete the operation.
  Raw status of the role-definition lookup for this identity: 403
  Raw status of the policy-assignment read for this identity: 403
  Done. Copy the lines above into check 6.1.
  ```

- [x] **6.2 Nothing was written by the refused identity.** Back in this window, as `oer-live-cc`.

  ```powershell
  $After61 = (Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop).ActivationMaxHours
  '{0} -> {1}: {2}; the value the refused Set asked for: {3}' -f $Before61, $After61, ($After61 -eq $Before61), $Probe61
  ```

  **Expect:** the same value on both sides of the arrow -- 6.1's first line printed it -- then
  `: True`; the right side is not the value the refused Set asked for. This holds whenever section 6
  runs: both sides are read in this run, around 6.1, and 6.1's Set ran under `-WhatIf`.
  **Failure looks like:** the right side equals the value the refused Set asked for, or differs from
  the left in any other way: stop and record it.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. The same value on both
  sides, `True`, and not the value the refused Set asked for.

  ```text
  3 -> 3: True; the value the refused Set asked for: 2
  ```

---

### Teardown

The prerequisite script's teardown restores everything this file wrote, and does not depend on any
step here: first both directory-role policies from the baseline file, rule by rule, stopping before
anything is deleted if either is not back at its baseline; then the Reader policy at `oer-s63-rg`, IN
FULL from the Reader record -- activation hours, approval and approvers -- stopping before the
resource group is deleted if it is not back at its record (the policy outlives the resource group and
comes back as it was left when the name is used again); then the resource group, the group and the
users. T.1 reads what it will restore, and also puts the Reader policy's activation hours back through
the module first -- one more pass through the module's Azure write path, not something the teardown
needs.

- [x] **T.1 What the teardown will restore, and the Reader policy's activation hours put back through the module.**

  The restore plan, read-only, and the plan for the activation hours:

  ```powershell
  Show-S63BaselineDiff -Label 'T.1'
  Show-S63ReaderRecordDiff -Label 'T.1 before'
  $ArmBase = Get-Content -Path (Join-Path $Raw '1.4-arm-baseline.json') -Raw | ConvertFrom-Json
  Invoke-S63Call -Cmdlet Set-OERRoleManagementPolicy -Splat @{ Role = 'Reader'; Scope = $RgScope; ActivationMaxHours = [int]$ArmBase.ActivationMaxHours; WhatIf = $true } -Label 'T.1 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S63Call -Cmdlet Set-OERRoleManagementPolicy -Splat @{ Role = 'Reader'; Scope = $RgScope; ActivationMaxHours = [int]$ArmBase.ActivationMaxHours; Confirm = $false } -Label 'T.1 write'
  $AT1 = Get-OERRoleManagementPolicy -Role Reader -Scope $RgScope -ErrorAction Stop
  'Reader at oer-s63-rg: ActivationMaxHours {0} (1.4: {1}): {2}' -f $AT1.ActivationMaxHours, $ArmBase.ActivationMaxHours, ($AT1.ActivationMaxHours -eq $ArmBase.ActivationMaxHours)
  Show-S63ReaderRecordDiff -Label 'T.1 after'
  ```

  **Expect:** `--- T.1: Reports Reader: the baseline names this policy: True; ...; differing from the baseline: 5 (...)`
  listing exactly `Approval_EndUser_Assignment`, `Enablement_EndUser_Assignment`,
  `Expiration_EndUser_Assignment`, `Expiration_Admin_Eligibility` and `Expiration_Admin_Assignment`
  -- not `AuthenticationContext_EndUser_Assignment`: 4.4 left the context disabled as it was at 1.1,
  and a `claimValue` of `''` compares equal to the baseline's null; then
  `Message Center Reader: ... differing from the baseline: 2 (Approval_EndUser_Assignment, Expiration_EndUser_Assignment)`.
  Nothing else: no `Notification_*` rule, no `Enablement_Admin_Assignment`. Then
  `--- T.1 before: Reader at oer-s63-rg: the record names this policy: True; ...; differing from the record: 2 (...)`,
  naming `Expiration_EndUser_Assignment` and `Approval_EndUser_Assignment`, and
  `What if: Performing the operation "Update rules: Expiration_EndUser_Assignment" on target "role management policy '<ArmPolicyId>'".`
  The write: one ARM `PATCH`, no error, the hours line ends `: True`, and
  `--- T.1 after: ... differing from the record: 1 (Approval_EndUser_Assignment)` -- approval and
  approvers are left for the teardown, which restores them from the record.
  **Failure looks like:** a rule no check wrote -- something else changed the policy, or Graph
  changed a rule by itself: record it; the teardown restores it from the file all the same, and T.4
  shows whether it could. `AuthenticationContext_EndUser_Assignment` listed: its `isEnabled` or
  `claimValue` differs for real (not merely `''` against null) -- 4.4 did not disable the context; record
  it. A `NoChange` error in the write: the hours already match 1.4 (5.x did not apply). If this write
  fails or is skipped, carry on: `T.1 after` then still lists `Expiration_EndUser_Assignment`, and
  T.3 restores it from the record.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Exactly the five Reports
  Reader rules and the two Message Center Reader rules, no context rule (`''` compares equal to the
  baseline's null); the Reader policy two rules; one `What if:`. The write: one ARM PATCH, `8 (1.4:
  8): True`, and after it only `Approval_EndUser_Assignment` differs.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- T.1: Reports Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 5 (Expiration_Admin_Eligibility, Expiration_Admin_Assignment, Expiration_EndUser_Assignment, Enablement_EndUser_Assignment, Approval_EndUser_Assignment)
  --- T.1: Message Center Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 2 (Expiration_EndUser_Assignment, Approval_EndUser_Assignment)
  --- T.1 before: Reader at oer-s63-rg: the record names this policy: True; rules live 17, recorded 17; differing from the record: 2 (Expiration_EndUser_Assignment, Approval_EndUser_Assignment)
  What if: Performing the operation "Update rules: Expiration_EndUser_Assignment" on target "role management policy '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000008'".
  === T.1 plan -- Set-OERRoleManagementPolicy
  --- requests, in the order sent: 3
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleDefinitions
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicyAssignments
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/<id>
  --- warnings: 0
  --- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0

  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === T.1 write -- Set-OERRoleManagementPolicy
  --- requests, in the order sent: 4
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleDefinitions
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicyAssignments
      GET /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/<id>
      PATCH /subscriptions/<id>/resourceGroups/oer-s63-rg/providers/Microsoft.Authorization/roleManagementPolicies/<id>
  --- warnings: 0
  --- errors published by Set-OERRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  Reader at oer-s63-rg: ActivationMaxHours 8 (1.4: 8): True
  --- T.1 after: Reader at oer-s63-rg: the record names this policy: True; rules live 17, recorded 17; differing from the record: 1 (Approval_EndUser_Assignment)
  ```

- [x] **T.2 Read the teardown plan.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -ModulePath $ModulePsd1 -Teardown -WhatIf
  ```

  **Expect:** `Mode: RESTORE and REMOVE. ...`, the `Directory roles (fixed): ... (exists: True)` line
  and `Reader record: ... (exists: True)`; both identity lines `True` after each of its two sign-ins;
  the tenant and the subscription identified through the `Connect-OER` sign-in, as in 0.2, no question
  under `-WhatIf`. Then, for each role,
  `Teardown: directory role '<role>': the baseline names the same role definition and policy: True`,
  `... rules differing from the baseline: <n> (...)` with exactly T.1's lists, one
  `What if: Performing the operation "Restore rule <rule id> from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role '<role>'".`
  line per listed rule, in the baseline's rule order, and
  `Teardown: directory role '<role>': restored: not attempted (WhatIf)`. Then the Reader policy:
  `Teardown, before the restore: Reader policy at oer-s63-rg: approval required True, approvers 2, activation max hours <1.4's hours>; ...: False`
  with two `approver on it:` lines (5.3's), `Teardown: the Reader record names this policy: True`,
  `Teardown, before the restore: Reader policy at oer-s63-rg against its record: activation max hours <1.4's hours> (record <1.4's hours>), approval required True (record False), approvers 2 (record 0); rules differing from the record: 1 (Approval_EndUser_Assignment)`
  (`2`, with `Expiration_EndUser_Assignment` and the hours line showing 3, if T.1's write did not
  happen), then
  `What if: Performing the operation "Restore from its record before the resource group is deleted: the recorded rule set, in one Azure Resource Manager PATCH" on target "Reader role management policy at resource group 'oer-s63-rg'".`,
  `Teardown: Reader policy at oer-s63-rg: restored: not attempted (WhatIf)`, and a `What if:` line for
  deleting the resource group `oer-s63-rg` (its target names `tag purpose = oer-s63-live-verification`);
  the Phase 2 sweep lists the resource group as still present. After the Phase 1 sign-in, `What if:`
  lines for deleting the group `oer-s63-approvers` and the two users, the sweep listing the three, then
  `WhatIf: nothing was created, restored, removed or written.` and `Done.` Paste the output redacted
  per the rules at the top -- the `Mode:`, `Identified ...` and sweep lines carry the tenant and
  subscription ids, the organization and the domain; the `approver on it:` lines carry object ids.
  **Failure looks like:** any target without the prefix other than the two roles' policies and the
  Reader policy at `oer-s63-rg`; a directory role other than the two; a rule list that differs from
  T.1's -- stop, do not run T.3. A `Refusing the teardown: the baseline file ... does not exist` line:
  the file is gone -- find it (`-BaselinePath`) before anything else; never delete the approvers while
  the policies may still name them. `the Reader record names this policy: False`: the record is not
  this resource group's, and T.3 would stop before deleting it -- find the right record. A warning
  `There is no Reader record at ...`: the record is gone, and the teardown would restore approval
  only -- find it (it sits beside the baseline file) before T.3. A warning
  `Refusing to delete resource group oer-s63-rg: its 'purpose' tag is ...`: find out whose it is first.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Both identity lines
  `True` after each sign-in; T.1's rule lists, one `What if:` per rule in the baseline's order; the
  Reader policy with the two 5.3 approvers, the record naming it, one rule differing, restored
  before the resource group's deletion; only `oer-s63` objects, the two roles' policies and that
  Reader policy targeted; `WhatIf: nothing was created, restored, removed or written.`

  ```text
  [oer-s63] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s63] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s63] Mode: RESTORE and REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s63', expected organization '<test tenant>'.
  [oer-s63] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Baseline file: <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json (exists: True).
  [oer-s63] Reader record: <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json (exists: True).
  [oer-s63] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s63] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s63] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s63] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s63] Identified the test subscription: '<test subscription>' (<SubscriptionId>).
  [oer-s63] Teardown: directory role 'Reports Reader': the baseline names the same role definition and policy: True
  [oer-s63] Teardown: directory role 'Reports Reader': rules differing from the baseline: 5 (Expiration_Admin_Eligibility, Expiration_Admin_Assignment, Expiration_EndUser_Assignment, Enablement_EndUser_Assignment, Approval_EndUser_Assignment)
  What if: Performing the operation "Restore rule Expiration_Admin_Eligibility from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Reports Reader'".
  What if: Performing the operation "Restore rule Expiration_Admin_Assignment from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Reports Reader'".
  What if: Performing the operation "Restore rule Expiration_EndUser_Assignment from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Reports Reader'".
  What if: Performing the operation "Restore rule Enablement_EndUser_Assignment from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Reports Reader'".
  What if: Performing the operation "Restore rule Approval_EndUser_Assignment from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Reports Reader'".
  [oer-s63] Teardown: directory role 'Reports Reader': restored: not attempted (WhatIf)
  [oer-s63] Teardown: directory role 'Message Center Reader': the baseline names the same role definition and policy: True
  [oer-s63] Teardown: directory role 'Message Center Reader': rules differing from the baseline: 2 (Expiration_EndUser_Assignment, Approval_EndUser_Assignment)
  What if: Performing the operation "Restore rule Expiration_EndUser_Assignment from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Message Center Reader'".
  What if: Performing the operation "Restore rule Approval_EndUser_Assignment from the baseline file (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Message Center Reader'".
  [oer-s63] Teardown: directory role 'Message Center Reader': restored: not attempted (WhatIf)
  [oer-s63] Teardown, before the restore: Reader policy at oer-s63-rg: approval required True, approvers 2, activation max hours 8; at its defaults (approval off, no approver): False
  [oer-s63] Teardown, before the restore:   approver on it: User 00000000-0000-0000-0000-000000000005
  [oer-s63] Teardown, before the restore:   approver on it: Group 00000000-0000-0000-0000-000000000007
  [oer-s63] Teardown: the Reader record names this policy: True
  [oer-s63] Teardown, before the restore: Reader policy at oer-s63-rg against its record: activation max hours 8 (record 8), approval required True (record False), approvers 2 (record 0); rules differing from the record: 1 (Approval_EndUser_Assignment)
  What if: Performing the operation "Restore from its record before the resource group is deleted: the recorded rule set, in one Azure Resource Manager PATCH" on target "Reader role management policy at resource group 'oer-s63-rg'".
  [oer-s63] Teardown: Reader policy at oer-s63-rg: restored: not attempted (WhatIf)
  What if: Performing the operation "Delete the resource group (Azure completes it asynchronously)" on target "resource group 'oer-s63-rg' in subscription '<SubscriptionId>' (tag purpose = oer-s63-live-verification)".
  [oer-s63] Phase 2 sweep, still present: resource group oer-s63-rg (Succeeded -- Azure deletes a resource group asynchronously; re-read in a few minutes)
  [oer-s63] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s63] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s63] Phase 1 identity check: tenant is the test tenant: True
  [oer-s63] Phase 1 is signed in to the confirmed test tenant '<test tenant>' (<TenantId>).
  What if: Performing the operation "Delete security group" on target "oer-s63-approvers".
  What if: Performing the operation "Delete test user" on target "person1@example.com".
  What if: Performing the operation "Delete test user" on target "person2@example.com".
  [oer-s63] Phase 1 sweep, still present: users 'person1@example.com' (00000000-0000-0000-0000-000000000005)
  [oer-s63] Phase 1 sweep, still present: users 'person2@example.com' (00000000-0000-0000-0000-000000000006)
  [oer-s63] Phase 1 sweep, still present: groups 'oer-s63-approvers' (00000000-0000-0000-0000-000000000007)
  [oer-s63] WhatIf: nothing was created, restored, removed or written.
  [oer-s63] Done.
  ```

- [x] **T.3 Restore both policies and remove every test object.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -SubscriptionId $SubId -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -ModulePath $ModulePsd1 -Teardown -Unattended
  ```

  **Expect:** both identity lines `True` after each sign-in; `Unattended run: the confirmation
  question is not asked; ...` before anything is changed. For each role, the lines T.2 printed, then
  one `Restored rule <rule id> of '<role>'.` per listed rule in the same order, no warning, and
  `Teardown: directory role '<role>': restored: True`. Then the Reader policy: the three
  `Teardown, before the restore: ...` / `the Reader record names this policy: True` lines T.2 printed,
  `Restored the Reader role management policy at resource group 'oer-s63-rg' from its record.`,
  `Teardown, read again after the restore: Reader policy at oer-s63-rg against its record: activation max hours <1.4's hours> (record <1.4's hours>), approval required False (record False), approvers 0 (record 0); rules differing from the record: 0`,
  `Teardown: Reader policy at oer-s63-rg: restored: True`, and only then
  `Deletion of resource group oer-s63-rg accepted.` The Phase 2 sweep reports
  `no resource group starting with 'oer-s63' is left.` or at most `oer-s63-rg` in `Deleting` state.
  After the Phase 1 sign-in: `Deleted group oer-s63-approvers.`, `Deleted user ...` for both users,
  and the sweep `no user or group starting with 'oer-s63' is left.` (Graph's list can lag a moment
  behind the deletes -- T.5 reads it again); `Done.` The Reader policy cannot be read once its
  resource group is gone, so the `read again after the restore` line is its read-back: record it. Paste
  the output redacted per the rules at the top, as for T.2.
  **Failure looks like:** `Microsoft Graph refused to restore rule ...` or `restored: False` with a
  `still differing:` line -- the script then stops with `... is not back at its baseline after the
  restore. Nothing was deleted ...`: record Graph's message and look at the policy before running T.3
  again. For the Reader policy, `restored: False` stops the script with `... is not back at its record
  after the restore. The resource group was NOT deleted ...`, and a record naming another policy stops
  it with `Refusing to restore the Reader role management policy ...` -- both before the resource group
  is deleted. A warning `There is no Reader record at ...` means only approval was restored: the
  activation hours and every other setting are not verified -- record it and restore the policy by
  hand from 1.4's values before the name `oer-s63-rg` is used again. A `Refusing ...` line. An
  `Authorization_RequestDenied` or a 403 on a restore or a deletion: a missing permission -- stop and
  name it (see Stop conditions). Re-run T.3 after a fix (it only restores what differs and removes what
  is still there) and record both runs.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Every listed rule
  restored, `restored: True` for both roles, no warning. The Reader policy restored from its record
  BEFORE the resource group was deleted, and its read-back: `rules differing from the record: 0`,
  `restored: True`; then the deletion accepted (the resource group `Deleting`). The group and both
  users deleted; the sweep still listed them a moment later -- Graph's list lagging the deletes --
  and T.5 reads them gone.

  ```text
  [oer-s63] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s63] No Tenant Profile '<Alias>' on this machine; every sign-in names -TenantId.
  [oer-s63] Mode: RESTORE and REMOVE. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubscriptionId>, prefix 'oer-s63', expected organization '<test tenant>'.
  [oer-s63] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Baseline file: <Repo>\docs\live-verification\raw\s63\baseline-directory-policies.json (exists: True).
  [oer-s63] Reader record: <Repo>\docs\live-verification\raw\s63\baseline-azure-reader-policy.json (exists: True).
  [oer-s63] Tenant identification and Phase 2 (Connect-OER): signing in with Connect-OER -TenantId -ClientId -Certificate -IncludeARM as the certificate identity.
  [oer-s63] Tenant identification and Phase 2 (Connect-OER) identity check: session app id is oer-live-cc: True
  [oer-s63] Tenant identification and Phase 2 (Connect-OER) identity check: tenant is the test tenant: True
  [oer-s63] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s63] Identified the test subscription: '<test subscription>' (<SubscriptionId>).
  [oer-s63] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
  [oer-s63] Teardown: directory role 'Reports Reader': the baseline names the same role definition and policy: True
  [oer-s63] Teardown: directory role 'Reports Reader': rules differing from the baseline: 5 (Expiration_Admin_Eligibility, Expiration_Admin_Assignment, Expiration_EndUser_Assignment, Enablement_EndUser_Assignment, Approval_EndUser_Assignment)
  [oer-s63] Restored rule Expiration_Admin_Eligibility of 'Reports Reader'.
  [oer-s63] Restored rule Expiration_Admin_Assignment of 'Reports Reader'.
  [oer-s63] Restored rule Expiration_EndUser_Assignment of 'Reports Reader'.
  [oer-s63] Restored rule Enablement_EndUser_Assignment of 'Reports Reader'.
  [oer-s63] Restored rule Approval_EndUser_Assignment of 'Reports Reader'.
  [oer-s63] Teardown: directory role 'Reports Reader': restored: True
  [oer-s63] Teardown: directory role 'Message Center Reader': the baseline names the same role definition and policy: True
  [oer-s63] Teardown: directory role 'Message Center Reader': rules differing from the baseline: 2 (Expiration_EndUser_Assignment, Approval_EndUser_Assignment)
  [oer-s63] Restored rule Expiration_EndUser_Assignment of 'Message Center Reader'.
  [oer-s63] Restored rule Approval_EndUser_Assignment of 'Message Center Reader'.
  [oer-s63] Teardown: directory role 'Message Center Reader': restored: True
  [oer-s63] Teardown, before the restore: Reader policy at oer-s63-rg: approval required True, approvers 2, activation max hours 8; at its defaults (approval off, no approver): False
  [oer-s63] Teardown, before the restore:   approver on it: User 00000000-0000-0000-0000-000000000005
  [oer-s63] Teardown, before the restore:   approver on it: Group 00000000-0000-0000-0000-000000000007
  [oer-s63] Teardown: the Reader record names this policy: True
  [oer-s63] Teardown, before the restore: Reader policy at oer-s63-rg against its record: activation max hours 8 (record 8), approval required True (record False), approvers 2 (record 0); rules differing from the record: 1 (Approval_EndUser_Assignment)
  [oer-s63] Restored the Reader role management policy at resource group 'oer-s63-rg' from its record.
  [oer-s63] Teardown, read again after the restore: Reader policy at oer-s63-rg against its record: activation max hours 8 (record 8), approval required False (record False), approvers 0 (record 0); rules differing from the record: 0
  [oer-s63] Teardown: Reader policy at oer-s63-rg: restored: True
  WARNING: Deleting resource group 'oer-s63-rg' permanently deletes ALL resources it contains.
  [oer-s63] Deletion of resource group oer-s63-rg accepted.
  [oer-s63] Phase 2 sweep, still present: resource group oer-s63-rg (Deleting -- Azure deletes a resource group asynchronously; re-read in a few minutes)
  [oer-s63] Phase 1: signing in to Microsoft Graph as the certificate identity (app-only, process-scoped context).
  [oer-s63] Phase 1 identity check: session app id is oer-live-cc: True
  [oer-s63] Phase 1 identity check: tenant is the test tenant: True
  [oer-s63] Phase 1 is signed in to the confirmed test tenant '<test tenant>' (<TenantId>).
  [oer-s63] Deleted group oer-s63-approvers.
  [oer-s63] Deleted user person1@example.com.
  [oer-s63] Deleted user person2@example.com.
  [oer-s63] Phase 1 sweep, still present: users 'person1@example.com' (00000000-0000-0000-0000-000000000005)
  [oer-s63] Phase 1 sweep, still present: users 'person2@example.com' (00000000-0000-0000-0000-000000000006)
  [oer-s63] Phase 1 sweep, still present: groups 'oer-s63-approvers' (00000000-0000-0000-0000-000000000007)
  [oer-s63] Done.
  ```

- [x] **T.4 Read both directory-role policies back, through the module and raw, against the baseline.**

  ```powershell
  $View11 = Get-Content -Path (Join-Path $Raw '1.1-module-view.json') -Raw | ConvertFrom-Json
  foreach ($R in @(@{ Key = 'rr'; Name = $RoleRR }, @{ Key = 'mcr'; Name = $RoleMCR })) {
      $Now = Get-S63ModuleView -Policy (Get-OERDirectoryRoleManagementPolicy -Role $R.Name -ErrorAction Stop)
      $Was = $View11.($R.Key)
      $Differ = @($Now.Keys | Where-Object { [string]$Now[$_] -cne [string]$Was.$_ })
      Write-Host ('=== {0}: module view equals 1.1''s: {1}{2}' -f $R.Name, ($Differ.Count -eq 0), $(if ($Differ.Count) { ' -- differs in ' + ($Differ -join ', ') } else { '' }))
  }
  Show-S63BaselineDiff -Label 'T.4'
  ```

  **Expect:** `=== Reports Reader: module view equals 1.1's: True` and the same for Message Center
  Reader -- every setting 1.1 recorded, the approver count included (`0`); then for both roles
  `the baseline names this policy: True; ...; differing from the baseline: 0`: every rule is back,
  as Graph v1.0 returns it.
  **Failure looks like:** a `False` or a count above `0`: the policy is not back at its baseline.
  Record which setting or rule, and restore it before anything else -- by the prerequisite script's
  `-Teardown` again, or by hand in the portal from the baseline file -- and never delete the raw folder
  (T.6) while this is not clean: it holds the only record of the original rules.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. `module view equals
  1.1's: True` twice and `differing from the baseline: 0` twice: both directory-role policies are
  back at their baseline, as Graph v1.0 returns them. (The 0.3 ids are no longer loadable here: the
  approver group is gone.)

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === Reports Reader: module view equals 1.1's: True
  === Message Center Reader: module view equals 1.1's: True
  --- T.4: Reports Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  --- T.4: Message Center Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  ```

- [x] **T.5 No object outside the prefix was touched, nothing was removed by an apply, and no user or group is left.** The module has no user read, so this signs in to Microsoft Graph directly, as the same certificate identity, read-only, at the very end.

  ```powershell
  $All = Import-Csv (Join-Path $Raw 'all-results.csv')
  $All | Where-Object Action -in 'Created', 'Updated', 'Removed', 'Failed' | Format-Table CheckId, Item, Action, Detail -Wrap
  $Allowed = @($RoleRR, $RoleMCR, "Reader @ $RgScope")
  "rows naming anything else: $(@($All | Where-Object { $Allowed -notcontains $_.Item }).Count)"
  # Disconnect first: Connect-OER left its raw access token in the Graph SDK's process cache, which
  # Connect-MgGraph would otherwise try to read as an MSAL cache.
  Disconnect-OER
  $null = Disconnect-MgGraph -ErrorAction SilentlyContinue
  Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint -ContextScope Process -NoWelcome
  "identity check: session app id is oer-live-cc: $([string](Get-MgContext).ClientId -eq $AppId)"
  "identity check: tenant is the test tenant: $([string](Get-MgContext).TenantId -eq $TenantId)"
  $F = [uri]::EscapeDataString("startswith(userPrincipalName,'$Prefix')")
  "users starting with the prefix: $(@((Invoke-MgGraphRequest -Uri "v1.0/users?`$filter=$F&`$select=id").value).Count)"
  $F = [uri]::EscapeDataString("startswith(displayName,'$Prefix')")
  "groups starting with the prefix: $(@((Invoke-MgGraphRequest -Uri "v1.0/groups?`$filter=$F&`$select=id").value).Count)"
  $null = Disconnect-MgGraph
  $Error.Clear()   # a failed raw Graph call leaves an ErrorRecord that can carry the bearer token -- README.md, "Credentials"
  ```

  **Expect:** no `Created`, `Removed` or `Failed` row anywhere. The `Updated` rows are exactly: `3.3`
  Reports Reader and Message Center Reader; `3.5b`, `3.7b`, `4.3b` and `4.4b` Reports Reader; `5.3`
  Message Center Reader and `Reader @ <RgScope>`. `rows naming anything else: 0`: every row of every
  run names one of the two roles or the Reader policy at `oer-s63-rg`. The writes outside the apply
  engine are 2.2, 2.4, 2.6, 2.7, 4.1 and 4.2 (Reports Reader), 5.1 and T.1 (the Reader policy at
  `oer-s63-rg`), and the prerequisite script's. Both identity lines `True`, then
  `users starting with the prefix: 0` and `groups starting with the prefix: 0`. The two users sit in
  Deleted items for 30 days, which is Entra ID's design; the deleted group is gone for good.
  **Failure looks like:** a `Created`, `Removed` or `Failed` row, an `Updated` row not listed above,
  or any count above `0`.
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Exactly the expected
  `Updated` rows, no `Created`, `Removed` or `Failed` row, `rows naming anything else: 0`; both
  identity lines `True`; no user and no group left with the prefix.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  CheckId Item                                                                                   Action  Detail
  ------- ----                                                                                   ------  ------
  3.3     Reports Reader                                                                         Updated updated directory role management policy for 'Reports Reader' (requireApproval=True, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  3.3     Message Center Reader                                                                  Updated updated directory role management policy for 'Message Center Reader' (requireApproval=True, activationMaxHours=2, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  3.5b    Reports Reader                                                                         Updated updated directory role management policy for 'Reports Reader' (approvers(users=[00000000-0000-0000-0000-000000000006]))
  3.7b    Reports Reader                                                                         Updated updated directory role management policy for 'Reports Reader' (approvers(groups=[]))
  4.3b    Reports Reader                                                                         Updated updated directory role management policy for 'Reports Reader' (authenticationContextId=c1)
  4.4b    Reports Reader                                                                         Updated updated directory role management policy for 'Reports Reader' (authenticationContextId=)
  5.3     Message Center Reader                                                                  Updated updated directory role management policy for 'Message Center Reader' (activationMaxHours=3)
  5.3     Reader @ /subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg Updated updated role management policy for 'Reader' at '/subscriptions/<SubscriptionId>/resourceGroups/oer-s63-rg' (requireApproval=True, activationMaxHours=3, approvers(users=[00000000-0000-0000-0000-000000000005],groups=[00000000-0000-0000-0000-000000000007]))
  rows naming anything else: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  users starting with the prefix: 0
  groups starting with the prefix: 0
  ```

- [x] **T.6 Redact, then clean up.** Only once T.4 printed `True` twice and `0` twice, and T.3 printed `Teardown: Reader policy at oer-s63-rg: restored: True`: the raw folder holds the baseline file and the Reader record, the only records of the original rules. Move what the results above need from `docs/live-verification/raw/s63/` into this file, redacted per [README.md](README.md) and the rules at the top, then delete the folder.

  Object ids to `00000000-0000-0000-0000-0000000000NN` -- the two role definition ids and the policy
  half of each directory-role policy id included -- the tenant id to `<TenantId>`, the subscription id
  to `<SubscriptionId>`, the organization, subscription name and domain to `<test tenant>`,
  `<test subscription>` and `<test domain>`, user principal names to `personN@example.com`; no
  credential, no bearer token, no application id, no thumbprint, and nothing copied out of the baseline
  file or the Reader record. That includes the output of 6.1's second process and of both
  prerequisite-script runs.

  ```powershell
  Remove-Item -LiteralPath $Raw -Recurse -Force
  "raw/s63 exists after: $(Test-Path -LiteralPath $Raw)"
  git -C $Repo status --short docs/live-verification
  ```

  **Expect:** `raw/s63 exists after: False`; `git status` shows only this checklist as modified;
  nothing under `raw/` is ever staged.
  **Failure looks like:** `raw/s63 exists after: True` -- a file in it is still open (an editor, or
  a second PowerShell window): close it and run the block again. `git status` listing anything under `docs/live-verification/raw/`, or
  any file besides this checklist -- unstage it and find out how it got there. A value a scan of this
  file still finds -- a GUID that is not a `00000000-...` placeholder, an address outside
  `example.com`, the tenant or subscription id, the organization or domain name -- means redaction
  is not finished: redact it before the commit, and if it was a credential, rotate it
  ([README.md](README.md), "Credentials").
  **Result:** PASS -- 2026-09-29, run by Claude Code as the certificate identity `oer-live-cc`
  (app-only), every output below passed through the run's redaction first. Run once T.4 printed
  `True` twice and `0` twice and T.3 printed `restored: True` for the Reader policy. Every result
  above was moved in redacted, and nothing was copied out of the baseline file or the Reader
  record. Before the commit, a scan of this file found none of the tenant values -- the tenant,
  subscription and application ids, the thumbprint, the organization, the domain and the clone path
  -- no GUID outside the placeholder range, no address outside `example.com`, and nothing
  token-shaped, and `tests/QA/dochygiene.tests.ps1`, with its new pass for an id wrapped over a
  line break, was green. The results were committed and pushed first; the folder was deleted after
  that, so `git status` printed nothing: this file was already committed and nothing under `raw/`
  was ever staged.

  ```text
  raw/s63 exists after: False
  ```
