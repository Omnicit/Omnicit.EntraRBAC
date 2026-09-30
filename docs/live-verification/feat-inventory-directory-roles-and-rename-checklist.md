# Live verification checklist -- the directory role export, Azure PIM eligibility in the bundle, the PIM-for-Groups criterion and the group rename (feat/inventory-directory-roles-and-rename)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file writes to a real tenant and a real Azure subscription, and names two directory roles
and one Azure role and no other.** The directory roles are **Reports Reader** and **Message Center
Reader**, two low-risk, read-only roles; the Azure role is **Reader**. Never Global Administrator,
never Privileged Role Administrator, never an Azure role that grants write access. Every principal and
group it touches was created by the prerequisite script for this file and carries the prefix
`oer-s65`; the only Azure objects it touches are the resource group `oer-s65-rg`, which the same
script creates in the test subscription, and what lies in it. Three things outside that prefix are
recorded before the first write and put back by the teardown: the tenant-wide PIM policy of Reports
Reader (the prerequisite script sets its activation maximum to three hours, after recording both
roles' policies in a baseline file), the direct assignments of the two roles (the script records
them first and compares with them last), and the Reader role management policy of `oer-s65-rg`
(nothing in this file changes it, but it is recorded right after the resource group is created --
only once it has passed a residue check, so an earlier run's leftover is never recorded as the
original state -- and restored BEFORE the resource group is deleted: an Azure role management policy
outlives its resource group, so a leftover change would reach the next resource group of that name).
The one exception to "put back": when setup stopped on that residue check, NO baseline of that policy
exists, and the teardown only reads it -- it deletes the resource group when the policy reads clean,
and otherwise leaves both for a human, with a stop line (0.3, T.1). Two groups, `oer-s65-pim-policy`
and `oer-s65-pim-elig`, are onboarded to PIM for Groups by the script on purpose, which cannot be
undone for them; the teardown deletes both. Section 6 is the one place a person's account appears:
Philip's own, in his own window, run by him.

**Every write is preceded by its `-WhatIf` plan.** Read the plan against the `Expect:` line first,
and only then run the line that writes. Every apply goes through the `Invoke-S65Check` helper defined
in Setup, which runs `Invoke-OERStructure -WhatIf` unless `-Apply` is passed. The one `-Prune` run in
this file (3.3) is a `-WhatIf` plan and nothing else. **Check 1.4 is `-WhatIf` ONLY**: a real run of
its first document would onboard `oer-s65-pim-untouched` to PIM for Groups and destroy the "not in
use" measurement of section 1 for good.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s65/` -- the
helpers write every document, every raw read, both export bundles and a results log there, the
prerequisite script writes its three baseline files and its state file there, and the folder is
git-ignored. The baseline and state files hold real object ids: never copy any of them, or any part
of them, into a tracked file. What goes into a `Result:` below is redacted first, per
[README.md](README.md):

- **Object ids** become `00000000-0000-0000-0000-0000000000NN` in first-appearance order for THIS
  file -- the same id always gets the same placeholder, since several checks turn on two ids being
  the same or different. That includes the two directory role definition ids (a built-in role's
  template id is the same in every tenant, but it is version-4 shaped and is redacted like any other
  id), the Azure Reader role definition id, every policy id, the certificate identity's service
  principal id, and every id in the prerequisite script's summary.
- **The tenant id** becomes `<TenantId>` wherever it appears, including the first half of a
  directory-role policy id (`DirectoryRole_<TenantId>_00000000-0000-0000-0000-0000000000NN`) and the
  name of the tenant root management group. **The subscription id** becomes `<SubId>`, including
  inside every ARM scope (`/subscriptions/<SubId>/resourceGroups/oer-s65-rg`). Any other management
  group name becomes `<MgName>`.
- **The organization display name** becomes `<test tenant>`, the **verified domain**
  `<test domain>`, the tenant alias `<Alias>`, and the local path of the clone `<Repo>`. A user
  principal name on the test domain becomes a `personN@example.com` address wherever PowerShell
  prints it itself (a `What if:` line), and so does Philip's own in section 6. The helpers already
  print a test user as `oer-s65-user1@<test domain>` and Philip as `<Me>`; those may stay.
- **No credential, no bearer token, no application id and no certificate thumbprint** is ever
  pasted.

The test objects' display names, the resource group name and the three role names may stay.
**Never render an error record** (`Format-List` on `$Error[0]`, on a `-ErrorVariable`, or on a catch
variable): a raw Graph failure's record carries the bearer token. Every block below prints the error
id and message only. The helpers name test objects, roles and policies instead of printing their ids
wherever they can, and print only counts for anything that is not a test object -- the tenant's own
role holders and groups are never listed -- so most blocks need no redaction at all; PowerShell's own
`What if:` lines print ids and user principal names as they are, and are always redacted.

## What changed and why this needs a live tenant

The branch makes the inventory export the two Microsoft Entra directory role sections the apply
engine already had, adds the Azure PIM eligible assignments to the export bundle as read-only
context, exports a group's `pimPolicy` only when the group uses PIM for Groups, and lets a group be
renamed from `Set-OERGroup` and from the apply document. Commits are named by SUBJECT, never by hash:
the hashes change when the branch is rebased onto `main` before it merges.

- **A. The directory sections in the inventory** ("feat: export directory role policies and
  assignments from the inventory", "fix: name a colliding group principal by its id in the directory
  role export"). `Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments`
  reads both tenant-scope schedule lists once, unfiltered. `directoryRoleAssignments` exports only
  the rows `Select-OERManagedDirectoryRoleAssignment` keeps (direct, tenant scope, and for Active an
  Assigned schedule, never an activation), a user by user principal name, a group by display name, a
  service principal by object id, `principalType` whenever the type is known, and `durationDays`
  from the schedule window for a time-bound one (a permanent one carries neither `durationDays` nor
  `permanent`). `directoryRoleManagementPolicies` exports the policy of every role with at least one
  row in those unfiltered reads -- or, with `-AllDirectoryRolePolicies`, of every role -- with no
  `scope`, and approvers only while approval is required.
- **B. The bundle** ("feat: export the directory role sections in the inventory bundle").
  `Export-OERInventory` includes both sections by default, writes
  `directoryRoleManagementPolicies.json` and `directoryRoleAssignments.json`, carries both sections in
  `inventory.json` without `id`, and reports `DirectoryRoleManagementPolicies` and
  `DirectoryRoleAssignments` counts in its summary.
- **C. Azure PIM eligibility as read-only context** ("feat: add Azure PIM eligibility to the
  inventory bundle as read-only context", "fix: pin the bundle JSON shape and state the eligibility
  coverage honestly", "docs: attribute the eligibility help phrase to the unfiltered read"). When an
  Azure section is included, `Export-OERInventory` reads `roleEligibilitySchedules` once per scope of
  its walk -- a management group with `atScope()`, a subscription with no filter -- deduplicates on
  the schedule id and writes `azurePimEligibility.json`; a failed scope is named in the new summary
  property `SkippedEligibilityScopes`, beside `AzurePimEligibility`, the count. The walk enumerates
  management groups and subscriptions only, so a resource-group-scoped eligibility reaches the file
  ONLY if the unfiltered subscription read returns it -- which Microsoft does not document, and
  which section 4 measures for the first time.
- **D. Rename with the cmdlet** ("feat: rename a group with Set-OERGroup -NewDisplayName").
  `-NewDisplayName` is sent in the same PATCH as any other property; with no property at all the
  cmdlet reports `NothingToUpdate`, naming `-NewDisplayName` among the properties.
- **E. Rename through the document** ("feat: rename a group through the apply document with
  previousDisplayName", "fix: verify a previousDisplayName given as an object id", "fix: word the
  onboarding and case-only rename warnings as what they know", "docs: state the rename lookup delay
  and the references a rename must update"). A `groups[]` entry declares its new name as
  `displayName` and its current name (or object id) as `previousDisplayName`. Only the previous name
  resolving: the rename is folded into the property update and reported `Updated` "renamed group
  '<previous>' to '<new>'". Both resolving to DIFFERENT groups: one `Failed` row and a
  `GroupRenameConflict` error, and nothing written -- the document never merges two groups. Neither
  resolving: the group is created (R9, unchanged) -- which is why the documentation now says Graph's
  name lookup can follow a rename with a delay, and to re-apply only once the new name resolves. The
  validator warns when `previousDisplayName` equals `displayName` ignoring case (a case-only rename
  is not possible through the document).
- **F. pimPolicy only for groups that use PIM for Groups** ("feat: export pimPolicy only for groups
  that use PIM for Groups", "fix: report pimPolicy unread when the eligibility half of the criterion
  was not read", "fix: treat a group PIM for Groups cannot manage as not using it").
  `Test-OERGroupPimInUse` decides "in use": PIM eligibility counted, or one of the group's policies,
  listed in ONE beta request, carries a non-empty `lastModifiedDateTime`, `lastModifiedBy.id` or
  `lastModifiedBy.displayName`. A 404 `ResourceNotFound` on that listing, or a 400
  `ResourceTypeNotSupported` (a dynamic group or one synchronized from on-premises, which PIM for
  Groups cannot manage), means not in use. `Get-OERInventory` asks it before the four policy calls
  and skips them for a group not in use; `Sync-OERStructureGroup` warns before the first changed
  `pimPolicy` write of an existing group it was not found to use PIM for Groups, because that write
  onboards the group.
- **G. Docs** ("docs: describe the exported directory role sections in the bundle prompt and
  README", "docs: show every apply section in the worked example", "docs: release notes for the
  directory role export and group rename", "docs: tighten the bundle README, help and release notes",
  "docs: live-verification checklist for the directory role export and group rename", "docs: measure
  the rename window and a dynamic group in the step 5 checklist").

**Every unit test on this branch mocks the transport.** They prove the module's decisions given the
shapes the tests assume. They cannot prove the six things this file is for:

1. That the pimPolicy criterion reads Graph's REAL policy fields right, for an untouched group, a
   group whose policy was changed, a group onboarded only through an eligibility, and a dynamic group
   PIM for Groups cannot manage (what Graph's listing answers for it is measured here first) -- the
   criterion is "NOT counted as proven until it is measured live in the step 5 checklist"
   (docs/development/rationale.md, `pim-in-use-criterion`) -- and that the export and the onboarding
   warning follow it (section 1).
2. That the exported directory sections say what Graph holds: roles, principals, types and windows,
   and the policy selection with and without `-AllDirectoryRolePolicies` (section 2).
3. That the export converges when it is applied back: every row `Unchanged`, and no write (section 3,
   rulings R13 and G11).
4. Whether the UNFILTERED subscription read of `roleEligibilitySchedules` returns an eligibility at a
   resource group below it -- the one claim of ruling R4 that is measured rather than documented
   (docs/development/rationale.md, `inventory-azure-eligibility`), and how many requests the walk
   costs (section 4).
5. That Graph renames a group as the document and the cmdlet ask, that a conflict writes nothing,
   what an IMMEDIATE re-run of the renaming document would do while Graph's name lookup catches up
   (the window the documentation warns about, measured), and that a run once the new name resolves is
   `Unchanged` (section 5, ruling R9).
6. That a management-group eligibility reaches the file through the full tree walk, which only a
   person who can read a management group can run (section 6, ruling R14).

## What this file does not check, and why

- **The criterion's active-only blind spot, as a live measurement.** A group used only through PIM
  ACTIVE assignments, whose policies were never modified, is not found to use PIM for Groups: the
  criterion does not look at assignment schedules (docs/development/rationale.md,
  `pim-in-use-criterion`, "A known blind spot of R1"). It is documented, and it is NOT run live here:
  creating such a group needs a time-bound active member assignment through beta
  `identityGovernance/privilegedAccess/group/assignmentScheduleRequests`, which needs
  `PrivilegedAssignmentSchedule.ReadWrite.AzureADGroup`, and that permission is no longer in the
  certificate identity's grant (it was revoked). No `oer-s65-pim-active` group is created. Section 1
  records the blind spot as a known limit of what it measures, not as a result.
- **A criterion that cannot be read, and the half answer.** A failed policy listing (the group's
  `pimPolicy` omitted and reported unread through `InventoryPartial`, and the apply warning "could not
  determine whether group ... uses PIM for Groups"), and a failed eligibility read under a "not in
  use" answer (`groups/<name>/pimPolicy` reported unread beside `groups/<name>/eligibility`). Both need
  an identity that may read groups but not their PIM data; unit-pinned in the
  `Test-OERGroupPimInUse`, `Get-OERInventory` and `Sync-OERStructureGroup` suites.
- **`previousDisplayName` given as an object id.** Its one Graph call is a plain
  `v1.0/groups/<id>?$select=id` read, whose not-found answer for an id that names no group was
  measured in the directory role assignment checklist, check 2.4. Unit-pinned, with the stale-id and
  the conflict-by-id cases.
- **An ambiguous `previousDisplayName`** (`AmbiguousName`), and **a directory export whose group
  principal collides with another principal's name** (named by object id instead). Both need two
  groups with one display name holding the same role, which adds nothing a unit test does not
  already prove. Unit-pinned in the `Sync-OERStructureGroup`, `Get-OERInventory` and
  `DirectoryRoleInventory.RoundTrip` suites.
- **Two live schedules for one role, principal and kind** (the first exported, with a warning). It
  needs a future-dated second schedule; unit-pinned.
- **A failed directory schedule or policy read in the export** (`InventoryPartial`, the
  `directoryRoleManagementPolicies/role selection` collection). The refused-read behaviour of the two
  schedule reads was measured in the directory role assignment checklist, section 5; the export's
  handling of it is unit-pinned.
- **Azure ACTIVE assignments.** Neither `azurePimEligibility.json` nor any apply section captures one,
  by design.
- **An Azure scope skipped in the eligibility pass while the role-assignment walk succeeded**, and
  the reverse. The two passes are separate by design (R4); a refusal cannot be made for one and not
  the other with this identity. Unit-pinned in the `Export-OERInventory` suite.
- **The prompt, the README and the worked example.** Documentation, not tenant behaviour.
- **Sovereign clouds.** Nothing on this branch changes an endpoint.

---

## Setup, once

**You need:**

- A **test tenant** -- never a customer tenant -- with Microsoft Entra ID P2 or ID Governance
  licensing (PIM for Microsoft Entra roles and PIM for Groups), its tenant id and one verified
  domain; and an **Azure test subscription** in it, on which the certificate identity holds the
  Azure role Owner, and which holds nothing of value in a resource group named `oer-s65-rg` (the
  script refuses one it did not create). No Tenant Profile is needed: every sign-in names the tenant
  id itself. The tenant guard is the identity check against the tenant claim of the token after every
  sign-in (`identity check: tenant is the test tenant: True`), and the prerequisite script's positive
  identification of the organization (its display name, a verified domain and its id) and of the
  subscription (it belongs to that tenant). When a profile for the alias happens to exist on the
  machine, the prerequisite script still refuses one that names another tenant or a cloud other than
  the commercial one.
- The **dedicated certificate identity** `oer-live-cc` ([README.md](README.md), first paragraph): an
  app whose only credential is a non-exportable certificate in `Cert:\CurrentUser\My`. Its grant list
  covers this file, and no other permission is needed:
  `RoleManagement.ReadWrite.Directory`, `RoleEligibilitySchedule.ReadWrite.Directory`,
  `RoleAssignmentSchedule.ReadWrite.Directory` and `RoleManagementPolicy.ReadWrite.Directory` (the
  directory roles, their schedules and their policies -- the prerequisite script's four assignments
  and its Reports Reader change, the export's reads of section 2, the round trip of section 3 and the
  teardown's restore); `RoleManagementPolicy.ReadWrite.AzureADGroup` and
  `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` (the prerequisite script's PIM-for-Groups
  policy change and eligibility, the criterion's policy listing, the group eligibility reads, and the
  onboarding warning's plan in 1.4); `Group.ReadWrite.All` and `User.ReadWrite.All` (the test users
  and groups, the rename writes of section 5, the teardown's deletes); `Directory.Read.All`,
  `Application.Read.All` and `Organization.Read.All` (lookups, the identity check's service principal
  read and the tenant identification); and `AdministrativeUnit.ReadWrite.All`,
  `EntitlementManagement.ReadWrite.All` and `AccessReview.Read.All` (the sections the default
  `Export-OERInventory` of 2.3 reads besides the directory ones) -- plus the Azure role **Owner on the
  test subscription** (the resource group, its Reader policy and the eligibility in it, and the
  Azure walk of sections 2.3 and 4). `Get-OERRequiredScope` also lists `AuthenticationContext.Read.All`
  for `Invoke-OERStructure`: it is used only to validate a declared authentication context in a group
  `pimPolicy` write, which this file never declares. **NOT covered: reading anything at a management
  group** -- the identity has Owner on the test subscription only -- which is why section 6 is run by
  the operator. Every sign-in below is app-only, as that identity -- never interactive, never a device
  code, never a cached context and never a person's account -- except section 6, which is Philip's.
  **The operator enables it for the run and disables it right after**; a sign-in answering
  "application is disabled" means it was not enabled: stop there. Its application permissions need no
  role activation.
- For section 6 only: Philip's own account in the test tenant, able to read a management group and
  to create a PIM eligibility there (for example Owner or User Access Administrator at that management
  group or above, activated in PIM BEFORE he signs in -- never assigned by this file), and a member of
  no `oer-s65` group.
- The prerequisite script `Initialize-OerS65Prereq.ps1`. It is kept OUTSIDE this repository and is
  never committed; it signs in as the certificate identity, and never runs in CI.
- PowerShell 7 and a clone of this repository on this branch.

**Stop conditions -- for every check below.** Stop, record what happened and do not go around it,
when any of these is true: a command, a document or a plan names a target without the prefix
`oer-s65` (other than the two directory roles' tenant-wide policies, which only the prerequisite
script and its teardown write, and in section 6 the management group Philip picks); any directory
role other than Reports Reader and Message Center Reader, or any Azure role other than Reader,
appears as the target of a write; an object the prerequisite script did not create is the TARGET of
a write; an identity line prints `False`; a request on the app path answers 401, 403,
`Authorization_RequestDenied` or `AuthorizationFailed` -- name the missing permission from the list
above and never finish the step with another sign-in; any row other than `Unchanged` appears in a
real round-trip apply plan (section 3); or a row of 1.4 would write to `oer-s65-pim-untouched` other
than under `-WhatIf`.

**Variables, build and module path.** Paste into one PowerShell 7 window and keep that window for
the whole file.

```powershell
$Repo        = '<your-clone-of-Omnicit.EntraRBAC>'   # the clone whose origin is github.com/Omnicit/Omnicit.EntraRBAC
$Prereq      = '<path-to-Initialize-OerS65Prereq.ps1>'
$Alias       = '<your-test-tenant-alias>'
$OrgName     = '<your-test-tenant-display-name>'   # the organization display name, exactly as Graph reports it
$Domain      = '<your-verified-domain>'
$TenantId    = '<your-test-tenant-id>'
$SubId       = '<your-test-subscription-id>'   # oer-live-cc holds Owner on it, and nothing at a management group
$AppId       = '<oer-live-cc-application-id>'
$NoPermAppId = '<oer-live-cc-noperm-application-id>'   # used only by section 6's identity check
$Thumbprint  = '<certificate-thumbprint>'   # in Cert:\CurrentUser\My; never exported, its key never read
$Prefix      = 'oer-s65'
$RoleRR      = 'Reports Reader'          # the ONLY two directory roles this file names
$RoleMCR     = 'Message Center Reader'
$RgName      = 'oer-s65-rg'              # the ONLY Azure resource group this file names; Reader the only Azure role
$RgScope     = "/subscriptions/$($SubId.ToLowerInvariant())/resourceGroups/$RgName"
$Raw         = Join-Path $Repo 'docs/live-verification/raw/s65'
$BaselinePath           = Join-Path $Raw 'baseline-directory-policies.json'      # written by the prerequisite script
$AssignmentBaselinePath = Join-Path $Raw 'baseline-directory-assignments.json'   # written by the prerequisite script
$RgBaselinePath         = Join-Path $Raw 'baseline-rg-reader-policy.json'        # written by the prerequisite script
$StatePath              = Join-Path $Raw 'prereq-state.json'                     # written by the prerequisite script

Set-Location $Repo -ErrorAction Stop
git remote get-url origin
git branch --show-current
# Build in a process of its own. ModuleBuilder fills every Build-Module parameter build.yaml leaves
# unset from a variable of the same name in the calling session, so the $Prefix above would be
# written into the top of the built module, and importing it would run 'oer-s65' as a command.
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

**Create the test objects and record the baselines.** The script runs in its own process, so this
window keeps its own sign-in. It signs in three times, always app-only as the certificate identity,
and BEFORE each sign-in it runs `Disconnect-OER` and then `Disconnect-MgGraph` (`Connect-OER`
leaves its raw access token in the Graph SDK's process cache, which a later `Connect-MgGraph` would
otherwise try to read as an MSAL cache -- step 3's lesson): first an Azure PRE-FLIGHT sign-in,
`Connect-OER -Certificate -IncludeARM`, which only reads -- so the Azure identity check, the
subscription identification and every Azure refusal come before the run writes anything; then
`Connect-MgGraph -ClientId -TenantId -CertificateThumbprint` for everything in Microsoft Graph,
independent of the module's own read and write code; then `Connect-OER -Certificate -IncludeARM`
again for the Azure writes, whose requests go through the module's own transport
`Invoke-OERArmRequest` (nothing else in the script holds an Azure token). After EVERY sign-in it
checks the identity and prints it as True/False only --
`identity check: session app id is oer-live-cc: True` and
`identity check: tenant is the test tenant: True`, and after an Azure sign-in also that the session
holds an Azure Resource Manager token for the test tenant -- and a `False` stops it. After every
sign-in it identifies the tenant positively: the organization's display name must equal
`-ExpectedTenantDisplayName` EXACTLY, `-UserDomain` must be one of its verified domains, and
`-TenantId` must be the organization's id; after an Azure sign-in the subscription must belong to
that tenant and be Enabled. With `-Unattended` -- a run with no operator at the keyboard -- it says,
after the first sign-in, that the confirmation question is not asked, since the identity checks and
the identifications passed. It is idempotent: a second run creates nothing that exists and only fills in what is
missing. It ends with a summary of names and REAL object ids -- redact those before pasting (check
0.3). Read the `-WhatIf` plan first: every target must carry the prefix `oer-s65`, apart from the
four files under `raw/s65/` and the Reports Reader policy change.

```powershell
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -SubscriptionId $SubId -RepoPath $Repo -WhatIf
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -SubscriptionId $SubId -RepoPath $Repo -Unattended
```

What it creates, all named with the prefix: two DISABLED users `oer-s65-user1` and `oer-s65-user2`
on your domain (display names `OER S65 User1` and `OER S65 User2`; random passwords, never printed);
the role-assignable security group `oer-s65-rag` with `oer-s65-user2` as its only member; six plain
security groups (not role-assignable, no members) -- `oer-s65-pim-untouched`, to which NOTHING PIM is
ever done; `oer-s65-pim-policy`, whose PIM-for-Groups MEMBER policy is changed once (beta rule
`Expiration_EndUser_Assignment`, `maximumDuration` `PT4H`), which onboards it; `oer-s65-pim-elig`,
in which `oer-s65-user1` gets a time-bound (`P5D`) PIM-for-Groups MEMBER eligibility (beta
`eligibilityScheduleRequests`), which onboards it; and `oer-s65-rename-old`, `oer-s65-conflict-a` and
`oer-s65-conflict-b` for section 5; and one DYNAMIC security group, `oer-s65-pim-dynamic` (not
role-assignable; membership rule `(user.department -eq "oer-s65-none")`, which matches no user;
processing On), which PIM for Groups cannot manage (Microsoft Learn) and to which nothing PIM is ever
done -- check 1.5 measures what Graph answers for it. Then Reports Reader's activation maximum set to
`PT3H`, and four directory role assignments at directory scope `/` (Microsoft Graph v1.0 schedule requests,
`adminAssign`): Reports Reader ELIGIBLE for `oer-s65-user1`, time-bound `P5D`; Reports Reader
ELIGIBLE for `oer-s65-rag`, permanent when the role's policy allows a permanent eligibility, else
`P10D`; Message Center Reader ACTIVE for `oer-s65-rag`, time-bound `P2D`; Message Center Reader
ACTIVE for `oer-s65-user1`, permanent when the policy allows a permanent active assignment, else
`P3D` -- it prints which. In Azure: the resource group `oer-s65-rg` in the test subscription (tagged
`purpose` = `Omnicit.EntraRBAC live verification (oer-s65)`), and an ELIGIBLE Reader assignment of
`oer-s65-user1` at it, time-bound `P30D`.

What it records, as UTF-8 JSON files, all under `raw/s65/`. `-BaselinePath` names the directory
POLICY baseline and the other three always sit beside it; this file never passes it, so
`$BaselinePath`, `$AssignmentBaselinePath`, `$RgBaselinePath` and `$StatePath` in the variables block
are the defaults. The helpers read them in exactly these shapes:

- **The policy baseline** -- once, before the first write of any kind -- is one object with one key,
  `roles`, an array of exactly two objects in the order Reports Reader, Message Center Reader, each
  with `displayName`, `roleDefinitionId`, `policyId` (`DirectoryRole_<tenant id>_<guid>`) and `rules`:
  every rule object exactly as
  `GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<id>'&$expand=policy($expand=rules)`
  returns it under `value[0].policy.rules`, unmodified.
- **The assignment baseline** -- written with it -- is one object with one key, `roles`, the same two
  roles each with `displayName`, `roleDefinitionId`, `eligible` and `active`: every DIRECT schedule at
  `/` as `roleEligibilitySchedules` and `roleAssignmentSchedules` return it (active: `assignmentType`
  `Assigned` only); an empty list is `[]`, never `null`.
- **The resource group Reader policy baseline** -- right after the resource group is created and its
  Reader policy has passed the residue check (below), before anything else is written in Azure; a
  policy with residue is never recorded -- is one object with `scope` (the resource group's ARM scope),
  `roleName` (`Reader`), `roleDefinitionId` (the full ARM id), `policyId` (under
  `<scope>/providers/Microsoft.Authorization/roleManagementPolicies/`) and `rules`: every rule exactly
  as `GET <policyId>?api-version=2020-10-01` returns it under `properties.rules`.
- **The state file** holds the object ids the script created or found: `users` and `groups` keyed by
  role in the script (the groups under their setup names, so the teardown finds a group section 5
  renamed), the resource group, and the Azure eligibility.

It refuses to run -- before its first write, and so writing nothing -- while either directory role
holds a direct assignment of a principal it did not create; while a group under one of its eight
names has the wrong shape (`oer-s65-rag` must be a role-assignable security group whose only member
is `oer-s65-user2`, `oer-s65-pim-dynamic` a dynamic security group that is NOT role-assignable, every
other one an assigned security group that is NOT role-assignable); and, from the Azure
pre-flight, when the subscription is not the test tenant's or not Enabled, when a resource group
`oer-s65-rg` exists without its purpose tag, and when an existing `oer-s65-rg` without a baseline has a
Reader policy with residue. **The residue check comes BEFORE the resource group's baseline is
written** (step 2's finding: an Azure role management policy outlives its resource group, so a new
`oer-s65-rg` can inherit an earlier run's approval): approval required, or any approver named, stops
the run. With no baseline yet, NONE is written for that policy, so the residue is never recorded as
the original state and nothing puts it back (a human resets it); with a baseline from an earlier run
-- only ever written for a clean policy -- the baseline is kept, and the teardown restores the policy
from it. The residue of a resource group this run creates can only be read once it
exists, after the directory writes; a stop there is a stop after a write. If any run stops after its
first write, it puts back what the baselines record before it exits, and prints each step: the
resource group's Reader policy from its baseline (when there is one and the Azure session is up), then
both directory policies from the policy baseline -- signing in to Microsoft Graph again first, with its
identity check, when the failure left no verified Graph session. It deletes nothing then -- that is the
teardown's job. The teardown deletes `oer-s65-rg` only once its Reader policy is back at its baseline,
or -- when there is no baseline, as after a residue stop -- reads clean (approval off, no approver); a
policy without a baseline is only read, never written, and one that does not read clean is left, with
the resource group, for a human.

**What the script prints, and the checks read.** 0.2, 0.3 and T.1 compare its output with these
lines; `<...>` is a value, and every line starts `[oer-s65] ` (shown once here):

- Every run, first: `Mode: CREATE or complete. Tenant alias '<alias>', tenant <tenant id>, subscription <subscription id>, prefix 'oer-s65', expected organization '<organization>'.`
  (`Mode: RESTORE and REMOVE. ...` with `-Teardown`), then
  `Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Azure (fixed): role 'Reader' only, resource group 'oer-s65-rg' in subscription <subscription id>, location 'swedencentral'.`,
  `Baselines and state in <folder>: directory policies exists: <True|False>; directory assignments exists: <True|False>; resource group Reader policy exists: <True|False>; state file exists: <True|False>.`,
  `Omnicit.EntraRBAC <version> loaded from <path>.` and
  `No Tenant Profile '<alias>' on this machine; the sign-ins name -TenantId.` (or
  `Tenant Profile '<alias>' names the same tenant as -TenantId, in the commercial cloud: True`).
- Each sign-in announces itself -- setup: `Azure Resource Manager pre-flight sign-in: ...`, then
  `Microsoft Graph sign-in: ...`, then `Azure Resource Manager sign-in: ...`; teardown:
  `Azure Resource Manager sign-in: ...`, then `Microsoft Graph sign-in: ...` -- the Graph one ending
  `Disconnect-OER and Disconnect-MgGraph first, then Connect-MgGraph as the certificate identity (...)`
  and each Azure one `Disconnect-OER and Disconnect-MgGraph first, then Connect-OER -Certificate -IncludeARM as the certificate identity (...)`.
  Each is followed by two lines ending exactly
  `identity check: session app id is oer-live-cc: <True|False>` and
  `identity check: tenant is the test tenant: <True|False>`, each preceded by the sign-in's own label
  (`[oer-s65] Microsoft Graph sign-in identity check: ...`); after an Azure sign-in a third,
  `<label> identity check: the session holds an Azure Resource Manager token for the test tenant, from the certificate: <True|False>`.
  Then, after each sign-in, `Identified the test tenant: organization '<organization>', tenant id <tenant id>, verified domain <domain>.`;
  after an Azure one, `Identified the test subscription: it belongs to the test tenant: True; state 'Enabled'.`;
  and after the FIRST sign-in only, with `-Unattended`,
  `Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.`
  Setup's pre-flight then prints `Azure role 'Reader': one built-in role definition at the test subscription: True.`
  and `Azure pre-flight: resource group oer-s65-rg does not exist yet; this run creates it after the directory objects.`
  (on a later run `Azure pre-flight: resource group oer-s65-rg exists and carries this script's tag.`).
  A refusal is one line starting `Refusing to run: ` (`Refusing the teardown: `), and the script then
  has written nothing; a stop after a write is a line starting `Stopped after this run had written ...`,
  preceded by the restore lines (`Restore: ...`).
- Setup, the directory side, in this order:
  `Directory role '<role>': one built-in role definition and one tenant-wide policy assignment: True (<n> rules).`
  (twice); on a first run `No directory baseline files yet; this run captures both before its first write.`,
  `Wrote the policy baseline (<n> + <m> rules): <path>` and
  `Wrote the assignment baseline (Reports Reader: eligible <a>, active <b>; Message Center Reader: eligible <c>, active <d>): <path>`
  (on a later run `The directory baseline files exist; comparing the live state with them.` and the
  per-role comparison lines); `Created user <upn> (disabled).` (twice); `Created group <name>.` eight
  times, `oer-s65-rag` as `Created group oer-s65-rag (role-assignable).` and `oer-s65-pim-dynamic` as
  `Created group oer-s65-pim-dynamic (dynamic).`;
  `Added <upn of oer-s65-user2> to oer-s65-rag.`;
  `PIM for Groups: changed the member policy of oer-s65-pim-policy (Expiration_EndUser_Assignment maximumDuration PT4H); this onboarded the group.`;
  `PIM for Groups: requested a time-bound (P5D) member eligibility of <upn of oer-s65-user1> in oer-s65-pim-elig: <status>; this onboarded the group.`;
  `Directory role 'Reports Reader': set Expiration_EndUser_Assignment maximumDuration PT3H (activation maximum 3 hours; it was <before>).`;
  `Directory role 'Reports Reader': permanent eligibility allowed by its policy: <True|False>; so the eligible assignment of oer-s65-rag is <permanent|time-bound P10D>.`
  and `Directory role 'Message Center Reader': permanent active assignment allowed by its policy: <True|False>; so the active assignment of <upn of oer-s65-user1> is <permanent|time-bound P3D>.`;
  four `Requested the <eligible|active> '<role>' assignment of <name> (<window>): <status>.`; and
  `Wrote the state file (Microsoft Graph): <path>`. A retry after a 404 prints a line containing
  `likely replication delay`. On a later run `... exists.` replaces each create.
- Setup, the Azure side, after its own sign-in: `Azure role 'Reader': one built-in role definition at the test subscription: True.`,
  `Created resource group oer-s65-rg in location 'swedencentral'.`,
  `The 'Reader' policy listed at oer-s65-rg is the resource group's own: True`,
  `Resource group Reader policy residue check: approval required False, approvers 0; clean: True`
  BEFORE `Wrote the resource group Reader policy baseline (<n> rules): <path>`,
  `Requested the eligible Azure role 'Reader' for <upn of oer-s65-user1> at resource group oer-s65-rg (time-bound P30D): <status>.`
  and `Wrote the state file (Azure): <path>`. Under `-WhatIf` the residue check prints
  `Resource group Reader policy residue check: not run (WhatIf: the resource group does not exist yet).`
- Teardown, the Azure side first, in this order: the role and baseline checks
  (`Directory role '<role>': both baselines name the same role definition and policy as this tenant: True`,
  twice), `Teardown: Azure eligibility of oer-s65 principals at resource group oer-s65-rg: <n>`, one
  `Removed the eligible 'Reader' assignment of <upn> at resource group oer-s65-rg.` per removal,
  `Teardown: the Reader policy of oer-s65-rg: rules differing from its baseline: <n>` (with
  `Restored <n> rule(s) of the Reader policy of oer-s65-rg.` when `<n>` is not 0),
  `Teardown: the Reader policy of oer-s65-rg: restored: <True|False|not attempted (WhatIf)>` and
  `Deleted resource group oer-s65-rg.` -- or, when there is no baseline for that policy (a setup run
  that stopped on residue writes none),
  `Teardown: the Reader policy of oer-s65-rg: no baseline to restore it from (a setup run that stopped on residue writes none); it is read, never written.`,
  `Teardown: the Reader policy of oer-s65-rg: approval required <True|False>, approvers <n>; clean: <True|False>`
  and, only when clean, `Deleted resource group oer-s65-rg.`; when not clean,
  `Teardown: resource group oer-s65-rg is NOT deleted: ... Both are left for a human: ...` and the
  rest goes on. Then the Graph side, after its own sign-in:
  `Teardown: oer-s65 assignments on the two roles: <n>`, before a removal a line
  `waiting <n> s: Microsoft Graph refuses to change or remove a principal's assignments of a role until its active assignment has run for five minutes`
  when an active assignment of that principal and role is younger than five minutes, one
  `Removed the <eligible|active> '<role>' assignment of <name>.` per removal (an assignment of a
  principal whose current name lacks the prefix as
  `Teardown: left in place: the <eligible|active> '<role>' assignment of '<name>', which does not carry the prefix 'oer-s65'; it is never touched.`); per role
  `Teardown: directory role '<role>': rules differing from the policy baseline: <n>` (the rule ids in
  parentheses), one `Restored rule <rule id> of '<role>'.` per rule and
  `Teardown: directory role '<role>': restored: <True|False|not attempted (WhatIf)>`; per role
  `Teardown: directory role '<role>': baseline assignments missing and re-created: <n>`;
  `Teardown: PIM-for-Groups eligibility of oer-s65 users in oer-s65-pim-elig: <n>` and
  `Removed the member eligibility of <upn> in oer-s65-pim-elig.` (when that group's current name lacks
  the prefix,
  `Teardown: left in place: group '<name>' (created as oer-s65-pim-elig) does not carry the prefix 'oer-s65'; its PIM-for-Groups eligibility is never touched.`
  instead);
  `Removed <upn of oer-s65-user2> from oer-s65-rag.` BEFORE `Deleted group oer-s65-rag.`, then the
  other seven `Deleted group <current name>.` (the renamed one as
  `Deleted group oer-s65-rename-direct (created as oer-s65-rename-old).`, anything the prefix sweep
  found besides as `... (found by the prefix sweep).`, and a group whose current name lacks the prefix
  as `Teardown: left in place: group '<name>' ... does not carry the prefix 'oer-s65'; it is never touched.`);
  `Deleted user <upn>.` (twice); per role
  `Teardown: directory role '<role>': direct assignments equal the assignment baseline: <True|False|not checked (WhatIf)>`;
  and `Sweep: no user or group starting with 'oer-s65' is left.` (or one
  `Sweep, still present: <user|group> '<name>' (<id>)` line each -- with a REAL id: redact it). A
  refused user deletion, a resource group left for a human, or any `left in place` line above (an
  object without the prefix, which the sweep and T.2 cannot see) ends the run with one
  `Stopped after this run had written ...: everything else is done, but: ...` line naming each, and
  exit code 1 -- the `left in place` ones as
  `<n> object(s) were left in place because their current name does not carry the prefix 'oer-s65' (...)`. Under
  `-WhatIf` every write is a PowerShell `What if:` line instead, and since nothing is deleted, the
  sweep lists every test object still there.
- Last: a summary headed `Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:`
  -- a table of `Kind`, `Name`, `Id` with the kinds `user` (2), `group` (8), `group member`,
  `directory role (built-in, fixed)` and `directory role policy` (2 each), `directory policy change`,
  `directory assignment (schedule)` (4), `PIM for Groups member policy`, `PIM for Groups eligibility`,
  `resource group`, `Azure role (built-in, fixed)`, `resource group Reader policy`,
  `Azure eligibility (schedule)`, and the four files with how they came to be (`written by this run`,
  `existed` or `not written (WhatIf)`); `(none -- not created)` as the id of anything missing; under
  `-WhatIf` `WhatIf: nothing was created, restored, removed or written.`; and finally `Done.`

**Sign in.** `Connect-S65` signs in app-only as the certificate identity, and ALWAYS runs
`Disconnect-OER` and `Disconnect-MgGraph` first. It prints the identity check as True/False only and
throws on a `False`. Without `-Arm` the session holds no Azure Resource Manager token; 2.3 is the
first check that needs one, and signs in again with `-Arm`.

```powershell
Import-Module Omnicit.EntraRBAC -Force
$ErrorActionPreference = 'Continue'   # module code reads the GLOBAL preference; Stop would end a run at its first Failed row
function Connect-S65 {
    # App-only, as the certificate identity; -Arm adds -IncludeARM (from 2.3 on). The certificate's
    # private key is used, never read out. The client and tenant ids of the identity check come from the
    # claims of the token Connect-OER obtained; the service principal's display name is read so a client
    # id of some other app cannot pass.
    param([switch]$Arm)
    Disconnect-OER -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    $global:Error.Clear()
    $Splat = @{ TenantId = $TenantId; ClientId = $AppId; Certificate = (Get-Item -LiteralPath "Cert:\CurrentUser\My\$Thumbprint"); ErrorAction = 'Stop' }
    if ($Arm) { $Splat.IncludeARM = $true }
    $null = Connect-OER @Splat
    $Ctx = Get-MgContext
    $global:S65Sp = $null
    try {
        $global:S65Sp = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop -Uri "v1.0/servicePrincipals(appId='$AppId')?`$select=id,displayName"
    } catch {
        Write-Host "--- reading the session's own service principal FAILED: $($PSItem.Exception.Message)"
        $global:Error.Clear()
    }
    $AppOk    = ([string]$Ctx.ClientId -eq $AppId) -and ([string]$S65Sp.displayName -ceq 'oer-live-cc')
    $TenantOk = ([string]$Ctx.TenantId -eq $TenantId)
    Write-Host "identity check: session app id is oer-live-cc: $AppOk"
    Write-Host "identity check: tenant is the test tenant: $TenantOk"
    if (-not ($AppOk -and $TenantOk)) { throw 'The identity check failed: nothing below may run.' }
}
Connect-S65
```

**The helpers.** Paste this block as it stands. The raw reads use `Invoke-MgGraphRequest` on the
Microsoft Graph context `Connect-OER` set up, with `-SkipHttpErrorCheck`: independent of the module's
own read and write code, and a refusal comes back as data, never as an error record. Policy rules are
compared exactly as the prerequisite script compares them: key and list order ignored, an absent
property and a null one the same, and a `claimValue` of `''` the same as null.

```powershell
function Test-S65Guid {
    param([AllowNull()][string]$Value)
    $Value -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
}

function Get-S65Name {
    # The name of a test object, role or identity for an object id, so output names objects instead of
    # printing ids. Filled from 0.5's ids (and, in section 6, $MeId); anything else is 'not a test object'.
    param([AllowNull()][string]$Id)
    if (-not $Id) { return 'no id' }
    $Known = [ordered]@{
        "$Prefix-user1"         = $IdUser1
        "$Prefix-user2"         = $IdUser2
        "$Prefix-rag"           = $IdRag
        "$Prefix-pim-untouched" = $IdPimUntouched
        "$Prefix-pim-policy"    = $IdPimPolicy
        "$Prefix-pim-elig"      = $IdPimElig
        "$Prefix-pim-dynamic"   = $IdPimDynamic
        "$Prefix-rename-group"  = $IdRename      # created as oer-s65-rename-old; section 5 renames it
        "$Prefix-conflict-a"    = $IdConflictA
        "$Prefix-conflict-b"    = $IdConflictB
        'oer-live-cc'           = $IdCc
        $RoleRR                 = $RoleIdRR
        $RoleMCR                = $RoleIdMCR
        'Me'                    = $MeId
    }
    foreach ($K in $Known.GetEnumerator()) {
        if ($K.Value -and [string]::Equals([string]$K.Value, $Id, [System.StringComparison]::OrdinalIgnoreCase)) { return [string]$K.Key }
    }
    'not a test object'
}

function Format-S65Text {
    # Any text with the tenant's own values replaced: Philip's user principal name (section 6) by <Me>,
    # a directory-role policy id by its role, the tenant id by <TenantId>, the subscription id by
    # <SubId>, every other GUID by its Get-S65Name in angle brackets, and the test domain by
    # <test domain>.
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return [string]$Text }
    $Out = $Text
    if ($Me) { $Out = $Out -ireplace [regex]::Escape($Me), '<Me>' }
    if ($PolicyIdRR) { $Out = $Out -ireplace [regex]::Escape($PolicyIdRR), "<policy of $RoleRR>" }
    if ($PolicyIdMCR) { $Out = $Out -ireplace [regex]::Escape($PolicyIdMCR), "<policy of $RoleMCR>" }
    if ($TenantId) { $Out = $Out -ireplace [regex]::Escape($TenantId), '<TenantId>' }
    if ($SubId) { $Out = $Out -ireplace [regex]::Escape($SubId), '<SubId>' }
    $Out = $Out -replace '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', { '<' + (Get-S65Name $_.Value) + '>' }
    if ($Domain) { $Out = $Out -ireplace ('@' + [regex]::Escape($Domain)), '@<test domain>' }
    $Out
}

function Format-S65Request {
    # One transport verbose line as method, path and decoded query, ids named (Format-S65Text) and a
    # paging token dropped. Both transports write the method and the uri or path only -- never a body
    # or a header -- to that stream.
    param([string]$Message)
    if ($Message -cnotmatch '^\[Invoke-OER(Graph|Arm)Request\] (?<M>GET|POST|PATCH|PUT|DELETE) (?<U>.+)$') { return }
    $Method = $Matches['M']
    $Uri = [uri]::UnescapeDataString(($Matches['U'] -replace '^https://[^/]+/', ''))
    $Uri = $Uri -replace '(?i)(\$skiptoken=)[^&]+', '$1<token>'
    "$Method $(Format-S65Text $Uri)"
}

function Show-S65Error {
    # The error id and message of each record the named cmdlet PUBLISHED -- never the record itself (a
    # raw transport record can carry the bearer token). Records collected from nested calls are counted.
    param([object[]]$Record, [Parameter(Mandatory)][string]$Cmdlet)
    $All = @($Record | Where-Object { $null -ne $_ })
    $Published = @($All | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains $Cmdlet })
    Write-Host "--- errors published by $($Cmdlet): $($Published.Count) (other records collected, not shown: $($All.Count - $Published.Count))"
    $Published | ForEach-Object { Write-Host "    ERROR [$($_.FullyQualifiedErrorId)]: $(Format-S65Text $_.Exception.Message)" }
}

function Invoke-S65Call {
    # Runs ONE module cmdlet with -Verbose captured and prints what it did: every Microsoft Graph and ARM
    # request in the order sent (kept in $S65Requests; -Quiet prints only the count per method), the
    # cmdlet's own verbose lines, every warning, the error id and message of every error it published,
    # and how many objects it returned (kept in $S65Out). A What if: line is PowerShell's own.
    param(
        [Parameter(Mandatory)][string]$Cmdlet,
        [Parameter(Mandatory)][hashtable]$Splat,
        [Parameter(Mandatory)][string]$Label,
        [switch]$Quiet
    )
    $Call = $Splat + @{ Verbose = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CallError' }
    $Out = @(& $Cmdlet @Call 3>&1 4>&1)
    $VerboseRecords = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
    $global:S65Requests = @($VerboseRecords | ForEach-Object { Format-S65Request -Message $_.Message } | Where-Object { $_ })
    $Own = @($VerboseRecords | Where-Object { $_.Message -notmatch '^\[Invoke-OER(Graph|Arm)Request\]' })
    $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $global:S65Out = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-Host "=== $Label -- $Cmdlet"
    Write-Host "--- requests, in the order sent: $($S65Requests.Count) ($(($S65Requests | Group-Object { ($_ -split ' ')[0] } -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))"
    if (-not $Quiet) { $S65Requests | ForEach-Object { Write-Host "    $_" } }
    Write-Host "--- the cmdlet's own verbose lines: $($Own.Count)"
    if (-not $Quiet) { $Own | ForEach-Object { Write-Host "    $(Format-S65Text $_.Message)" } }
    Write-Host "--- warnings: $($Warnings.Count)"
    $Warnings | ForEach-Object { Write-Host "    WARNING: $(Format-S65Text $_.Message)" }
    Show-S65Error -Record $CallError -Cmdlet $Cmdlet
    Write-Host "--- objects returned: $($S65Out.Count)"
}

function Get-S65RawStatus {
    # One GET straight from Microsoft Graph, returning the HTTP status, Graph's error code and the body.
    # -SkipHttpErrorCheck: a refusal is read as data and never thrown, so no error record is created.
    param([Parameter(Mandatory)][string]$Uri)
    $Body = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType HashTable -SkipHttpErrorCheck -StatusCodeVariable 'S65Status'
    $Code = if ($Body -is [System.Collections.IDictionary] -and $Body['error']) { [string]$Body['error']['code'] } else { '' }
    [PSCustomObject]@{ Status = [int]$S65Status; ErrorCode = $Code; Body = $Body }
}

function Get-S65RawAll {
    # Every page of one GET list straight from Microsoft Graph, read as data. A page that is not 200
    # ends the walk and is returned with its status and Graph's error code.
    param([Parameter(Mandatory)][string]$Uri)
    $Rows = [System.Collections.Generic.List[object]]::new()
    $Next = $Uri
    while ($Next) {
        $R = Get-S65RawStatus -Uri $Next
        if ($R.Status -ne 200) { return [PSCustomObject]@{ Status = $R.Status; ErrorCode = $R.ErrorCode; Rows = @($Rows) } }
        foreach ($V in @($R.Body['value'])) { if ($null -ne $V) { $Rows.Add($V) } }
        $Next = [string]$R.Body['@odata.nextLink']
    }
    [PSCustomObject]@{ Status = 200; ErrorCode = ''; Rows = @($Rows) }
}

function Get-S65RawGroup {
    # One group by object id, straight from Microsoft Graph v1.0: its name, description, shape and its
    # members' ids. Saved to the raw folder, named after -Label.
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Label)
    $G = Get-S65RawStatus -Uri "v1.0/groups/$Id`?`$select=id,displayName,description,isAssignableToRole,securityEnabled"
    $M = Get-S65RawAll -Uri "v1.0/groups/$Id/members?`$select=id"
    ConvertTo-Json -InputObject @{ group = $G.Body; members = $M.Rows } -Depth 10 | Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    if ($G.Status -ne 200) { Write-Host "--- $($Label): group <$(Get-S65Name $Id)>: status $($G.Status) $($G.ErrorCode)"; return }
    $Out = [PSCustomObject]@{
        Id = [string]$G.Body['id']; DisplayName = [string]$G.Body['displayName']; Description = [string]$G.Body['description']
        IsAssignableToRole = $G.Body['isAssignableToRole']; SecurityEnabled = $G.Body['securityEnabled']
        MemberIds = @($M.Rows | ForEach-Object { [string]$_['id'] })
    }
    Write-Host ("--- {0}: group <{1}>: displayName '{2}'; description '{3}'; isAssignableToRole '{4}'; securityEnabled {5}; members [{6}]" -f
        $Label, (Get-S65Name $Id), $Out.DisplayName, $Out.Description, $Out.IsAssignableToRole, $Out.SecurityEnabled,
        ((@($Out.MemberIds) | ForEach-Object { Get-S65Name $_ }) -join ', '))
    $Out
}

function Get-S65RawRoleDefinitionId {
    # A built-in directory role's definition id, read at run time straight from Microsoft Graph v1.0.
    param([Parameter(Mandatory)][string]$Name)
    $F = [uri]::EscapeDataString("displayName eq '$Name'")
    $R = Get-S65RawStatus -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=$F&`$select=id,displayName,isBuiltIn"
    $D = @($R.Body['value'] | Where-Object { $null -ne $_ -and [string]$_['displayName'] -ceq $Name })
    if ($R.Status -ne 200 -or $D.Count -ne 1 -or -not [bool]$D[0]['isBuiltIn']) { Write-Host "--- '$Name': status $($R.Status) $($R.ErrorCode); $($D.Count) role definition(s) with exactly that name, or not built-in"; return }
    [string]$D[0]['id']
}

function Get-S65RawPolicy {
    # The policy of one directory role straight from Microsoft Graph v1.0, through the query of the
    # policy baseline. Saved to the raw folder, named after -Label.
    param([Parameter(Mandatory)][string]$RoleDefinitionId, [Parameter(Mandatory)][string]$Label)
    $F = [uri]::EscapeDataString("scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$RoleDefinitionId'")
    $R = Get-S65RawStatus -Uri "v1.0/policies/roleManagementPolicyAssignments?`$filter=$F&`$expand=policy(`$expand=rules)"
    $A = @($R.Body['value'] | Where-Object { $null -ne $_ })
    if ($R.Status -ne 200 -or $A.Count -ne 1) { Write-Host "--- $($Label): status $($R.Status) $($R.ErrorCode); $($A.Count) policy assignment(s), not one"; return }
    $Rules = @($A[0]['policy']['rules'] | Where-Object { $null -ne $_ })
    ConvertTo-Json -InputObject $Rules -Depth 30 | Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    [PSCustomObject]@{ PolicyId = [string]$A[0]['policyId']; Rules = $Rules }
}

function Get-S65WindowDays {
    # The window of one raw schedule's scheduleInfo in days (two decimals): end minus start, or the ISO
    # duration when Graph returned no end. '' for a schedule that never ends.
    param([System.Collections.IDictionary]$Info)
    if (-not $Info) { return '' }
    $Exp = $Info['expiration']
    if (-not $Exp -or [string]$Exp['type'] -eq 'noExpiration') { return '' }
    $ToOffset = {
        param($V)
        if ($V -is [datetimeoffset]) { $V } elseif ($V -is [datetime]) { [datetimeoffset]$V } else { [datetimeoffset]::Parse([string]$V, [cultureinfo]::InvariantCulture) }
    }
    if ($Exp['endDateTime'] -and $Info['startDateTime']) { return [math]::Round(((& $ToOffset $Exp['endDateTime']) - (& $ToOffset $Info['startDateTime'])).TotalDays, 2) }
    if ($Exp['duration']) { return [math]::Round([System.Xml.XmlConvert]::ToTimeSpan([string]$Exp['duration']).TotalDays, 2) }
    ''
}

function Get-S65RawRoleRow {
    # Every schedule of one directory role, both kinds, straight from Microsoft Graph v1.0 -- direct and
    # inherited, every directory scope -- one flat row each: role, kind, principal id, memberType,
    # directoryScopeId, assignmentType (Active only) and the window in whole days ('' when it never ends).
    param([Parameter(Mandatory)][string]$RoleName, [Parameter(Mandatory)][string]$RoleDefinitionId)
    foreach ($Kind in 'Eligible', 'Active') {
        $Resource = if ($Kind -eq 'Eligible') { 'roleEligibilitySchedules' } else { 'roleAssignmentSchedules' }
        $F = [uri]::EscapeDataString("roleDefinitionId eq '$RoleDefinitionId'")
        $R = Get-S65RawAll -Uri "v1.0/roleManagement/directory/$Resource`?`$filter=$F"
        if ($R.Status -ne 200) { Write-Host "--- raw $Resource of <$RoleName> FAILED: status $($R.Status) $($R.ErrorCode)"; continue }
        foreach ($Row in $R.Rows) {
            $Days = Get-S65WindowDays -Info $Row['scheduleInfo']
            [PSCustomObject]@{
                Role = $RoleName; Kind = $Kind; PrincipalId = ([string]$Row['principalId']).ToLowerInvariant()
                MemberType = [string]$Row['memberType']; Scope = [string]$Row['directoryScopeId']
                AssignmentType = $(if ($Row.ContainsKey('assignmentType')) { [string]$Row['assignmentType'] } else { '' })
                Days = $(if ($Days -eq '') { '' } else { [string][int][math]::Round([double]$Days) })
            }
        }
    }
}

function Get-S65RawGroupPim {
    # Section 1's independent read of one group, straight from Microsoft Graph beta: its PIM-for-Groups
    # policies (id, lastModifiedDateTime, lastModifiedBy), each tagged member or owner through the policy
    # assignment listing and each field printed as True/False (non-empty or not), and how many PIM
    # eligibility schedules and schedule instances the group has. Read as data: a 404 or 400 is printed
    # as status and code. Saved to the raw folder, named after -Label.
    param([Parameter(Mandatory)][string]$GroupId, [Parameter(Mandatory)][string]$Label)
    $F = [uri]::EscapeDataString("scopeId eq '$GroupId' and scopeType eq 'Group'")
    $P = Get-S65RawStatus -Uri "beta/policies/roleManagementPolicies?`$filter=$F&`$select=id,lastModifiedDateTime,lastModifiedBy"
    $A = Get-S65RawStatus -Uri "beta/policies/roleManagementPolicyAssignments?`$filter=$F"
    $G = [uri]::EscapeDataString("groupId eq '$GroupId'")
    $E = Get-S65RawStatus -Uri "beta/identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=$G"
    $I = Get-S65RawStatus -Uri "beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=$G"
    ConvertTo-Json -InputObject @{ policies = $P.Body; assignments = $A.Body; eligibilitySchedules = $E.Body; eligibilityScheduleInstances = $I.Body } -Depth 20 |
        Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    $AccessOf = @{}
    if ($A.Status -eq 200) { foreach ($X in @($A.Body['value'] | Where-Object { $null -ne $_ })) { $AccessOf[[string]$X['policyId']] = [string]$X['roleDefinitionId'] } }
    $Policies = if ($P.Status -eq 200) { @($P.Body['value'] | Where-Object { $null -ne $_ }) } else { @() }
    Write-Host "--- $($Label): <$(Get-S65Name $GroupId)>: policy listing status $($P.Status) $($P.ErrorCode); policies $($Policies.Count); assignment listing status $($A.Status) $($A.ErrorCode)"
    $AnyModified = $false
    foreach ($Policy in $Policies) {
        $Date = -not [string]::IsNullOrWhiteSpace([string]$Policy['lastModifiedDateTime'])
        $By = $Policy['lastModifiedBy']
        $ById = [bool]($By -and -not [string]::IsNullOrWhiteSpace([string]$By['id']))
        $ByName = [bool]($By -and -not [string]::IsNullOrWhiteSpace([string]$By['displayName']))
        if ($Date -or $ById -or $ByName) { $AnyModified = $true }
        $Access = if ($AccessOf.ContainsKey([string]$Policy['id'])) { $AccessOf[[string]$Policy['id']] } else { 'access type not listed' }
        Write-Host ('    policy ({0}): lastModifiedDateTime set {1}; lastModifiedBy.id set {2}; lastModifiedBy.displayName set {3}' -f $Access, $Date, $ById, $ByName)
    }
    $ECount = if ($E.Status -eq 200) { @($E.Body['value'] | Where-Object { $null -ne $_ }).Count } else { -1 }
    $ICount = if ($I.Status -eq 200) { @($I.Body['value'] | Where-Object { $null -ne $_ }).Count } else { -1 }
    Write-Host ('--- {0}: any policy modified: {1}; eligibility schedules: {2}; eligibility schedule instances: {3}' -f $Label, $AnyModified,
        $(if ($ECount -ge 0) { $ECount } else { "status $($E.Status) $($E.ErrorCode)" }), $(if ($ICount -ge 0) { $ICount } else { "status $($I.Status) $($I.ErrorCode)" }))
    [PSCustomObject]@{ PolicyStatus = $P.Status; Policies = $Policies.Count; AnyModified = $AnyModified; Eligibility = $ECount; Instances = $ICount }
}

function ConvertTo-S65Canonical {
    # The same comparison the prerequisite script makes: every dictionary's keys sorted and every list
    # sorted by its own canonical JSON; '@odata.context' dropped; a null property dropped (null and
    # absent are the same); a claimValue of '' read as null. Every rule set it sees here is read as
    # hashtables (-OutputType HashTable, ConvertFrom-Json -AsHashtable).
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $Out = [ordered]@{}
        foreach ($Key in @($Value.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -notmatch '@odata\.context$' } | Sort-Object -CaseSensitive)) {
            $Item = $Value[$Key]
            if ($Key -ceq 'claimValue' -and $Item -is [string] -and $Item.Length -eq 0) { $Item = $null }
            if ($null -eq $Item) { continue }
            $Out[$Key] = ConvertTo-S65Canonical -Value $Item
        }
        return $Out
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Value) { $Items.Add((ConvertTo-S65Canonical -Value $Item)) }
        $Sorted = @($Items | Sort-Object -Property { ConvertTo-Json -InputObject $_ -Depth 50 -Compress })
        return , $Sorted
    }
    return $Value
}

function Get-S65RuleDiff {
    # The id of every rule whose content differs between two rule sets, in the second set's order, then
    # any rule only the first set has.
    param([object[]]$Live, [object[]]$Baseline)
    $Text = { param($Rule) ConvertTo-Json -InputObject (ConvertTo-S65Canonical -Value $Rule) -Depth 50 -Compress }
    $LiveById = @{}
    foreach ($Rule in @($Live | Where-Object { $null -ne $_ })) { $LiveById[[string]$Rule['id']] = & $Text $Rule }
    $BaseById = [ordered]@{}
    foreach ($Rule in @($Baseline | Where-Object { $null -ne $_ })) { $BaseById[[string]$Rule['id']] = & $Text $Rule }
    $Ids = @(@($BaseById.Keys) + @($LiveById.Keys | Where-Object { -not $BaseById.Contains($_) }))
    foreach ($Id in $Ids) { if ([string]$LiveById[$Id] -cne [string]$BaseById[$Id]) { $Id } }
}

function Show-S65BaselineDiff {
    # Every rule of the two directory-role policies that differs from the policy baseline, read raw.
    param([Parameter(Mandatory)][string]$Label)
    $Base = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($Entry in @($Base['roles'] | Where-Object { $null -ne $_ })) {
        $Name = [string]$Entry['displayName']
        $Live = Get-S65RawPolicy -RoleDefinitionId ([string]$Entry['roleDefinitionId']) -Label ('{0}-{1}-policy-raw' -f $Label, ($Name -replace ' ', '-'))
        if (-not $Live) { continue }
        $Diff = @(Get-S65RuleDiff -Live $Live.Rules -Baseline @($Entry['rules']))
        Write-Host ('--- {0}: {1}: the baseline names this policy: {2}; rules live {3}, baseline {4}; differing from the baseline: {5}{6}' -f
            $Label, $Name, ([string]$Entry['policyId'] -eq $Live.PolicyId), @($Live.Rules).Count, @($Entry['rules']).Count, $Diff.Count,
            $(if ($Diff.Count) { ' (' + ($Diff -join ', ') + ')' } else { '' }))
    }
}

function Show-S65AssignmentBaselineDiff {
    # The DIRECT rows at '/' of both roles, read raw (active: Assigned only), against the assignment
    # baseline, per role and kind, by principal: who only the live read has, and who only the baseline
    # has -- named, never printed as ids.
    param([Parameter(Mandatory)][string]$Label)
    $Base = Get-Content -LiteralPath $AssignmentBaselinePath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($Entry in @($Base['roles'] | Where-Object { $null -ne $_ })) {
        $Name = [string]$Entry['displayName']
        $Rows = @(Get-S65RawRoleRow -RoleName $Name -RoleDefinitionId ([string]$Entry['roleDefinitionId']))
        foreach ($Kind in 'Eligible', 'Active') {
            $BaseIds = @($Entry[$Kind.ToLowerInvariant()] | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_['principalId']).ToLowerInvariant() } | Sort-Object -Unique)
            $LiveIds = @($Rows | Where-Object { $_.Kind -eq $Kind -and $_.MemberType -eq 'Direct' -and $_.Scope -eq '/' -and ($Kind -eq 'Eligible' -or $_.AssignmentType -eq 'Assigned') } |
                    ForEach-Object { $_.PrincipalId } | Sort-Object -Unique)
            $OnlyLive = @($LiveIds | Where-Object { $BaseIds -notcontains $_ } | ForEach-Object { Get-S65Name $_ } | Sort-Object)
            $OnlyBase = @($BaseIds | Where-Object { $LiveIds -notcontains $_ } | ForEach-Object { Get-S65Name $_ } | Sort-Object)
            Write-Host ('--- {0}: {1}, {2}: direct principals live {3}, baseline {4}; only live [{5}]; only baseline [{6}]' -f
                $Label, $Name, $Kind, $LiveIds.Count, $BaseIds.Count, ($OnlyLive -join ', '), ($OnlyBase -join ', '))
        }
    }
}

function Invoke-S65ArmRead {
    # One Azure Resource Manager GET through the module's own transport, in the module's scope -- the
    # session's ARM token never leaves it. Returns the parsed body, or the error message as text.
    param([Parameter(Mandatory)][string]$Path)
    try {
        $Body = & (Get-Module Omnicit.EntraRBAC) { param($P) Invoke-OERArmRequest -Path $P } $Path
        [PSCustomObject]@{ Ok = $true; Body = $Body; Error = '' }
    } catch {
        $Message = Format-S65Text $PSItem.Exception.Message
        $global:Error.Clear()
        [PSCustomObject]@{ Ok = $false; Body = $null; Error = $Message }
    }
}

function New-S65Doc {
    # One apply document with a groups[] section, as JSON, under the test tenant's alias.
    param([Parameter(Mandatory)][object[]]$Group)
    [ordered]@{ version = '1.0'; tenantAlias = $Alias; groups = @($Group) } | ConvertTo-Json -Depth 10
}

function Invoke-S65Check {
    # Writes the document to the raw folder, prints it (not with -Quiet), validates it offline, then runs
    # Invoke-OERStructure on it -- under -WhatIf unless -Apply is given, with -Prune only when asked.
    # Warnings keep their order; errors print as id and message only; every row prints on one line, ids
    # named -- with -Quiet only the rows of the two roles and every row that is not Unchanged, since a
    # document of every role names the tenant's own role holders -- then the count per section and
    # action; every row is appended to all-results.csv for T.2. -ShowRequests runs with -Verbose, prints
    # the requests per method and every request that is not a GET. The rows stay in $S65Result and the
    # requests in $S65Requests, both emptied first.
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Json,
        [Parameter(Mandatory)][string[]]$Include,
        [switch]$Apply,
        [switch]$Prune,
        [switch]$Quiet,
        [switch]$ShowRequests
    )
    $global:S65Result = @()
    $global:S65Requests = @()
    $Path = Join-Path $Raw "$Id.json"
    Set-Content -Path $Path -Value $Json -Encoding utf8NoBOM
    Write-Host "=== $Id"
    if (-not $Quiet) { Get-Content -Path $Path | ForEach-Object { Write-Host "    $(Format-S65Text ($_ -replace '("tenantAlias":\s*")[^"]*', '$1<Alias>'))" } }
    $Validation = Test-OERStructure -Path $Path
    $Findings = @($Validation.Errors | Where-Object { $null -ne $_ })
    Write-Host "--- offline validation: Valid = $($Validation.Valid), findings = $($Findings.Count)"
    foreach ($F in $Findings) {
        if ($Quiet) { Write-Host "    [$($F.Severity)] $($F.Section) $($F.Path)" } else { Write-Host "    [$($F.Severity)] $($F.Section) $($F.Path): $(Format-S65Text $F.Message)" }
    }
    if (-not $Validation.Valid) { return }
    $Splat = @{ Path = $Path; Include = $Include; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CheckError' }
    if ($Prune) { $Splat.Prune = $true }
    if ($Apply) { $Splat.Confirm = $false } else { $Splat.WhatIf = $true }
    if ($ShowRequests) { $Splat.Verbose = $true }
    Write-Host ('--- Invoke-OERStructure -Include {0}{1}{2}{3}' -f ($Include -join ','), $(if ($Prune) { ' -Prune' } else { '' }), $(if ($Apply) { ' -Confirm:$false' } else { ' -WhatIf' }), $(if ($ShowRequests) { ' -Verbose' } else { '' }))
    $Out = @(Invoke-OERStructure @Splat 3>&1 4>&1)
    $Warn = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $VerboseRecords = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
    $global:S65Result = @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] -and $_ -isnot [System.Management.Automation.VerboseRecord] })
    Write-Host "--- warnings, in the order written: $($Warn.Count)"
    $Warn | ForEach-Object { Write-Host "    WARNING: $(Format-S65Text $_.Message)" }
    $Errs = @($CheckError | Where-Object { $null -ne $_ })
    Write-Host "--- errors: $($Errs.Count)"
    foreach ($E in $Errs) { Write-Host "    ERROR [$($E.FullyQualifiedErrorId)]: $(Format-S65Text $E.Exception.Message)" }
    $Shown = if ($Quiet) { @($S65Result | Where-Object { $_.Action -ne 'Unchanged' -or ([string]$_.Item) -match ('^(' + [regex]::Escape($RoleRR) + '|' + [regex]::Escape($RoleMCR) + ')( ->|$)') }) } else { $S65Result }
    Write-Host "--- results, in the order returned: $($S65Result.Count)$(if ($Quiet) { " (shown: $($Shown.Count) -- the two roles, and every row that is not Unchanged)" })"
    $Shown | ForEach-Object { Write-Host ('    [{0}] {1} | {2} | {3}' -f $_.Section, (Format-S65Text $_.Item), $_.Action, (Format-S65Text $_.Detail)) }
    Write-Host "--- counts per section and action: $(($S65Result | Group-Object Section, Action -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join '; ')"
    if ($ShowRequests) {
        $global:S65Requests = @($VerboseRecords | ForEach-Object { Format-S65Request -Message $_.Message } | Where-Object { $_ })
        Write-Host "--- requests: $($S65Requests.Count) ($(($S65Requests | Group-Object { ($_ -split ' ')[0] } -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', '))"
        $NotGet = @($S65Requests | Where-Object { $_ -notmatch '^GET ' })
        $Writes = @($NotGet | Where-Object { $_ -notmatch '^POST v1\.0/directoryObjects/(getByIds|[^/]+/getMemberGroups)' })
        Write-Host "--- requests that are not a GET: $($NotGet.Count); writes among them (not the read-only getByIds / getMemberGroups): $($Writes.Count)"
        $NotGet | ForEach-Object { Write-Host "    $_" }
    }
    $S65Result | Select-Object @{ Name = 'CheckId'; Expression = { $Id } }, Section, Item, Action, Detail |
        Export-Csv -Path (Join-Path $Raw 'all-results.csv') -Append -NoTypeInformation
}
```

**The test principals.** Paste this block as it stands.

```powershell
$User1Upn = "$Prefix-user1@$Domain"
$User2Upn = "$Prefix-user2@$Domain"   # the only member of oer-s65-rag
$RagName  = "$Prefix-rag"             # role-assignable
$Pim      = "$Prefix-pim"             # the four section 1 groups start with this
```

In the `Expect:` lines below, a name in angle brackets is an id the helpers have already named:
`<oer-s65-user1>`, `<oer-s65-user2>`, `<oer-s65-rag>`, `<oer-s65-pim-untouched>`,
`<oer-s65-pim-policy>`, `<oer-s65-pim-elig>`, `<oer-s65-pim-dynamic>`, `<oer-s65-rename-group>`
(the group created as `oer-s65-rename-old`, whatever its name at the time), `<oer-s65-conflict-a>`,
`<oer-s65-conflict-b>`,
`<oer-live-cc>` (the certificate identity's service principal), `<Reports Reader>` and
`<Message Center Reader>` (the role definition ids), `<policy of Reports Reader>` and
`<policy of Message Center Reader>`, `<TenantId>`, `<SubId>`, and in section 6 `<Me>` (Philip).
`<not a test object>` is an id none of those is. A test user principal name prints as
`oer-s65-user1@<test domain>`. PowerShell's own `What if:` lines print the ids and names as they
are: they are described below as `<the id of oer-s65-rename-group>` or
`<oer-s65-user1's user principal name>`.

**Run order.** Section 0, then section 1 before ANY other check writes (1.4 is `-WhatIf` only).
Sections 2, 3 and 4 read; 3.2 applies a document that must change nothing. Section 5 renames three of
the test groups and must run after sections 1 to 4, since nothing earlier depends on its names. Then
section 6, by Philip, then the Teardown. Run sections 0 to 5 within two days of the prerequisite run:
Message Center Reader's active assignment of `oer-s65-rag` is time-bound (`P2D`), and 2.1 and section
3 count on it -- if it has expired, re-run the prerequisite script, which only fills in what is
missing. If this window is closed part-way, paste the Setup blocks again (variables, sign-in,
helpers, test principals) and re-run 0.5; from 2.3 on, run `Connect-S65 -Arm` instead of the plain
sign-in. A raw read answering 401 after a long pause means the token `Connect-OER` handed the Graph
SDK has expired: sign in again.

---

### 0. Preparation

- [ ] **0.1 The session runs THIS branch's build.**

  ```powershell
  git -C $Repo fetch origin
  git -C $Repo log --format=%s origin/main..HEAD
  $M = Get-Module Omnicit.EntraRBAC
  '{0} {1} from {2}' -f $M.Name, $M.Version, $M.ModuleBase
  & $M { Get-Command Test-OERGroupPimInUse, Get-OERInventoryAzureEligibility, ConvertTo-OERInventoryRoleManagementPolicy,
      Select-OERManagedDirectoryRoleAssignment, Sync-OERStructureGroup } | Format-Table Name, CommandType -AutoSize
  'Get-OERInventory -Include accepts: ' + ((Get-Command Get-OERInventory).Parameters['Include'].Attributes.ValidValues -join ', ')
  'switches: Get-OERInventory -AllDirectoryRolePolicies {0}; Export-OERInventory -AllDirectoryRolePolicies {1}; Set-OERGroup -NewDisplayName {2}' -f
      (Get-Command Get-OERInventory).Parameters.ContainsKey('AllDirectoryRolePolicies'),
      (Get-Command Export-OERInventory).Parameters.ContainsKey('AllDirectoryRolePolicies'),
      (Get-Command Set-OERGroup).Parameters.ContainsKey('NewDisplayName')
  Get-OERRequiredScope -Cmdlet Get-OERInventory, Export-OERInventory, Set-OERGroup, Invoke-OERStructure |
      ForEach-Object { '{0} [{1}]: {2}' -f $_.Cmdlet, $_.Transport, ($_.GraphScope -join ', ') }
  ```

  **Expect:** before the merge, the log lists at least these subjects (record any later one too --
  review fixes land after this file was written): "feat: export directory role policies and
  assignments from the inventory", "fix: name a colliding group principal by its id in the directory
  role export", "feat: export the directory role sections in the inventory bundle", "feat: add Azure
  PIM eligibility to the inventory bundle as read-only context", "fix: pin the bundle JSON shape and
  state the eligibility coverage honestly", "docs: attribute the eligibility help phrase to the
  unfiltered read", "feat: rename a group with Set-OERGroup -NewDisplayName", "feat: rename a group
  through the apply document with previousDisplayName", "fix: verify a previousDisplayName given as an
  object id", "feat: export pimPolicy only for groups that use PIM for Groups", "fix: report pimPolicy
  unread when the eligibility half of the criterion was not read", "docs: describe the exported
  directory role sections in the bundle prompt and README", "docs: show every apply section in the
  worked example", "docs: release notes for the directory role export and group rename", "docs:
  live-verification checklist for the directory role export and group rename", "fix: treat a group
  PIM for Groups cannot manage as not using it", "fix: word the onboarding and case-only rename
  warnings as what they know", "docs: state the rename lookup delay and the references a rename must
  update", "docs: tighten the bundle README, help and release notes" and "docs: measure the rename
  window and a dynamic group in the step 5 checklist". Subjects, not hashes: a
  rebase onto `main` rewrites every hash. After the merge the range is empty. `ModuleBase` lies under
  `<Repo>/output/module/Omnicit.EntraRBAC/`; the five private functions are listed as `Function`; the
  `-Include` line names `DirectoryRoleManagementPolicies` and `DirectoryRoleAssignments` among nine
  values; `switches: ... True; ... True; ... True`; and the scope lines read, in this order,
  `Get-OERInventory [GraphAndArm]: AccessReview.Read.All, AdministrativeUnit.Read.All, Directory.Read.All, EntitlementManagement.Read.All, PrivilegedEligibilitySchedule.Read.AzureADGroup, RoleManagement.Read.Directory, RoleManagementPolicy.Read.AzureADGroup`,
  `Export-OERInventory [GraphAndArm]:` the same list,
  `Set-OERGroup [Graph]: Group.ReadWrite.All, RoleManagement.ReadWrite.Directory` and
  `Invoke-OERStructure [GraphAndArm]: AccessReview.ReadWrite.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.ReadWrite.All, Group.ReadWrite.All, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.ReadWrite.AzureADGroup`
  -- every one of them covered by the grant list in Setup (a ReadWrite grant covers its Read scope;
  `AuthenticationContext.Read.All` is never reached here, see Setup).
  **Failure looks like:** `CommandNotFound` for any function, a `False`, a missing section in the
  `-Include` line or a different scope row -- a build without this branch's change is loaded.
  Rebuild, fix `PSModulePath`, re-import; nothing below means anything until this passes.
  **Result:**

- [ ] **0.2 The prerequisite script's plan names only `oer-s65` targets, the four files and the Reports Reader policy change.** Paste the `-WhatIf` run's output from Setup, redacted per the rules at the top.

  **Expect:** the lines Setup lists under "What the script prints": first
  `[oer-s65] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, subscription <SubId>, prefix 'oer-s65', expected organization '<test tenant>'.`,
  the `Directory roles (fixed): ... Azure (fixed): role 'Reader' only, resource group 'oer-s65-rg' ...` line,
  and `Baselines and state in <Repo>\docs\live-verification\raw\s65: directory policies exists: False; directory assignments exists: False; resource group Reader policy exists: False; state file exists: False.`
  on a first run. Three sign-ins, in this order -- the Azure pre-flight, Microsoft Graph, Azure --
  each announced with `Disconnect-OER and Disconnect-MgGraph first`, each followed by both identity
  lines ending `True` (each Azure one also by
  `... holds an Azure Resource Manager token for the test tenant, from the certificate: True`), each
  followed by `Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.`,
  each Azure one by `Identified the test subscription: it belongs to the test tenant: True; state 'Enabled'.`;
  the pre-flight by `Azure pre-flight: resource group oer-s65-rg does not exist yet; ...` -- and NO
  `What if:` line before the Microsoft Graph sign-in: the pre-flight only reads. No
  `Unattended run: ...` line and no question (`-WhatIf`). The two permanence lines, as the tenant's
  policies allow. Every `What if:` target is one of: the four files under
  `<Repo>\docs\live-verification\raw\s65\` (the two directory baselines, the resource group
  baseline, and the state file twice -- after the Graph phase and after the Azure phase); the
  DISABLED users `oer-s65-user1` and `oer-s65-user2` (printed as user principal names -- redact);
  the eight groups, `oer-s65-rag` role-assignable and the other seven not, `oer-s65-pim-dynamic` as
  `Create a DYNAMIC security group that is NOT role-assignable (membershipRule (user.department -eq "oer-s65-none"), which matches no user; processing On) -- a group PIM for Groups cannot manage`;
  the membership
  `oer-s65-rag <- oer-s65-user2`; `oer-s65-pim-policy`
  (`Change the PIM-for-Groups MEMBER policy once: rule Expiration_EndUser_Assignment, maximumDuration PT4H ...`);
  `member eligibility of <oer-s65-user1's user principal name> in oer-s65-pim-elig`
  (`Request a time-bound (P5D) PIM-for-Groups MEMBER eligibility ...`);
  `PIM policy of directory role 'Reports Reader'`
  (`Set rule Expiration_EndUser_Assignment maximumDuration PT3H ...`); the four directory
  assignments, each on target `<eligible|active> directory role '<role>' for <name> at directory scope '/'`,
  Reports Reader for `oer-s65-user1` and `oer-s65-rag`, Message Center Reader for `oer-s65-rag` and
  `oer-s65-user1`; `resource group oer-s65-rg in the test subscription`
  (`Create the resource group (Azure Resource Manager PUT, location 'swedencentral', tag purpose 'Omnicit.EntraRBAC live verification (oer-s65)')`);
  and `eligible Azure role 'Reader' for <oer-s65-user1's user principal name> at resource group oer-s65-rg`.
  `Resource group Reader policy residue check: not run (WhatIf: the resource group does not exist yet).`
  Nothing is a target of `oer-s65-pim-untouched` but its creation. No directory role but the two, no
  Azure role but Reader, nothing at a management group or at the subscription itself. Then the
  summary, with `(none -- not created)` as the id of everything it would create,
  `[oer-s65] WhatIf: nothing was created, restored, removed or written.` and `[oer-s65] Done.`
  **Failure looks like:** a target without the prefix other than those named above; a role other
  than the three; a `What if:` line before the Microsoft Graph sign-in -- the pre-flight wrote, or
  would write: stop; a refusal line -- `Refusing to run: ...` from the tenant identification (check
  `$OrgName` exactly, case-sensitive, `$Domain` and `$TenantId`; never weaken the check), from the
  subscription (`$SubId` is not the test subscription, or it is not Enabled), a resource group
  `oer-s65-rg` the script did not create, an existing `oer-s65-rg` whose Reader policy has residue and
  no baseline (reset it by hand), a group under one of the eight names with the wrong shape (delete it
  by hand), or a direct assignment of either role to a principal the script did not create (someone
  holds the role: stop). Every one of these comes before the run's first write, in the real run as
  well. Record it and stop.
  **Result:**

- [ ] **0.3 The prerequisite script ran, every test object exists, and the four files are written.** Paste its output and summary, redacted per the rules at the top, then run the read-only block below.

  ```powershell
  foreach ($P in $BaselinePath, $AssignmentBaselinePath, $RgBaselinePath, $StatePath) {
      $I = Get-Item -LiteralPath $P -ErrorAction SilentlyContinue
      '{0}: exists {1}; written {2}' -f (Split-Path $P -Leaf), [bool]$I, $(if ($I) { $I.LastWriteTime.ToString('s') } else { '-' })
  }
  $BP = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json -AsHashtable
  $BA = Get-Content -LiteralPath $AssignmentBaselinePath -Raw | ConvertFrom-Json -AsHashtable
  $BR = Get-Content -LiteralPath $RgBaselinePath -Raw | ConvertFrom-Json -AsHashtable
  $ST = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json -AsHashtable
  foreach ($E in @($BP['roles'])) { 'policy baseline: {0}: {1} rules; policyId recorded {2}' -f $E['displayName'], @($E['rules']).Count, [bool]$E['policyId'] }
  foreach ($E in @($BA['roles'])) { 'assignment baseline: {0}: eligible {1}, active {2}' -f $E['displayName'], @($E['eligible'] | Where-Object { $null -ne $_ }).Count, @($E['active'] | Where-Object { $null -ne $_ }).Count }
  'resource group baseline: scope is oer-s65-rg {0}; role {1}; {2} rules; the policy lies under the resource group {3}' -f
      [string]::Equals([string]$BR['scope'], $RgScope, [System.StringComparison]::OrdinalIgnoreCase), $BR['roleName'], @($BR['rules']).Count,
      ([string]$BR['policyId']).StartsWith("$RgScope/providers/Microsoft.Authorization/roleManagementPolicies/", [System.StringComparison]::OrdinalIgnoreCase)
  'state file: prefix {0}; written after {1}; users {2}; groups {3} ({4}); resource group recorded as existing {5}; Azure eligibility recorded {6}' -f
      $ST['prefix'], $ST['writtenAfter'], @($ST['users'].Keys).Count, @($ST['groups'].Keys).Count, (@($ST['groups'].Keys) -join ', '),
      $ST['resourceGroup']['exists'], [bool]$ST['azureEligibility']
  ```

  **Expect:** the run's output: the same opening lines as 0.2 with `exists: False` four times,
  the three sign-ins in 0.2's order with both identity lines `True`, the ARM token line `True` after
  each Azure one, the identifications and `Identified the test subscription: ... True; state 'Enabled'.`
  twice, ONE
  `Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.`
  (after the first sign-in, the pre-flight, only), the pre-flight's two lines;
  `Wrote the policy baseline (<n> + <m> rules): ...` and
  `Wrote the assignment baseline (Reports Reader: eligible 0, active 0; Message Center Reader: eligible 0, active 0): ...`;
  the users and groups created, `Added ... to oer-s65-rag.`, both `PIM for Groups: ...; this onboarded the group.`
  lines, `Directory role 'Reports Reader': set Expiration_EndUser_Assignment maximumDuration PT3H (activation maximum 3 hours; it was <before>).`
  (record `<before>`; the step 3 checklist measured one hour on this tenant), the two permanence
  lines (record both: 2.1 turns on them) and four `Requested the ... assignment ...` lines with a
  status such as `Provisioned`; `Wrote the state file (Microsoft Graph): ...`; then
  `Created resource group oer-s65-rg in location 'swedencentral'.`,
  `The 'Reader' policy listed at oer-s65-rg is the resource group's own: True`,
  `Resource group Reader policy residue check: approval required False, approvers 0; clean: True`,
  then -- only after that check -- `Wrote the resource group Reader policy baseline (<n> rules): ...`,
  `Requested the eligible Azure role 'Reader' for oer-s65-user1@<test domain> at resource group oer-s65-rg (time-bound P30D): <status>.`
  and `Wrote the state file (Azure): ...`; the summary with an id for everything; `[oer-s65] Done.`
  A `likely replication delay` line or two are normal. The block: all four files `exists True`; both
  policy baselines with rules and a policy id; the assignment baseline `eligible 0, active 0` twice;
  `resource group baseline: scope is oer-s65-rg True; role Reader; <n> rules; the policy lies under the resource group True`;
  `state file: prefix oer-s65; written after Azure; users 2; groups 8 (rag, pimuntouched, pimpolicy, pimelig, pimdynamic, rename, conflicta, conflictb); resource group recorded as existing True; Azure eligibility recorded True`
  (the eight keys in any order).
  **Failure looks like:** a `Stopped ...` line -- read the `Restore: ...` lines above it (the script
  puts the resource group's Reader policy back from its baseline, when there is one, and both
  directory policies from the policy baseline, signing in to Microsoft Graph again first when it has
  to) and record them; the residue line with `clean: False` -- an earlier run's approval is still on
  the resource group's Reader policy (an Azure role management policy outlives its resource group):
  the script stopped BEFORE it wrote a baseline for that policy, so the residue was never recorded as
  the original state and nothing will put it back. Stop; the operator resets that policy by hand
  (approval off, no approver), then either runs the prerequisite script again -- it records the now
  clean policy and carries on -- or runs the teardown, which deletes the resource group only once
  the policy reads clean. (On a LATER run, with `baseline-rg-reader-policy.json` already written,
  the warning says instead that the policy differs from that baseline, which is kept: the run's stop
  restores it when the run wrote anything -- see its `Restore: ...` lines -- and the teardown
  restores it from the baseline otherwise.);
  `The 'Reader' policy listed at oer-s65-rg is the resource group's own: False` -- Azure listed a
  policy of a wider scope there: the script stops, since it never records or restores a policy
  beyond the resource group; record it; a `403` or
  `Authorization_RequestDenied` anywhere -- name the permission (Setup); an assignment baseline that
  is not empty -- someone held a role before this run (the script should have refused: record it).
  **Result:**

- [ ] **0.4 The identity check, and no Azure Resource Manager token yet.** Read-only. Paste the two identity lines the sign-in block printed, then run:

  ```powershell
  $S65SignedIn = & (Get-Module Omnicit.EntraRBAC) { Get-OERSignedInObjectId }
  "the module's signed-in object id is oer-live-cc's service principal: $([string]::Equals([string]$S65SignedIn, [string]$S65Sp.id, [System.StringComparison]::OrdinalIgnoreCase))"
  "the session holds an Azure Resource Manager token: $([bool](& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.ArmToken }))"
  ```

  **Expect:** `identity check: session app id is oer-live-cc: True`,
  `identity check: tenant is the test tenant: True`, then `True` and
  `the session holds an Azure Resource Manager token: False` -- the sign-in was made without
  `-IncludeARM`; nothing before 2.3 needs Azure.
  **Failure looks like:** a `False` identity line -- stop. An ARM token `True`: the sign-in block was
  changed; sign in again as given.
  **Result:**

- [ ] **0.5 Record the object ids every later check compares against, and the objects' shape.** Read-only. The ids come from the state file and are each read back from Microsoft Graph by id, so this block gives the same answer before and after section 5 renames a group.

  ```powershell
  $ST = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json -AsHashtable
  $IdUser1 = [string]$ST['users']['user1']['id']; $IdUser2 = [string]$ST['users']['user2']['id']
  $IdRag = [string]$ST['groups']['rag']['id']; $IdPimUntouched = [string]$ST['groups']['pimuntouched']['id']
  $IdPimPolicy = [string]$ST['groups']['pimpolicy']['id']; $IdPimElig = [string]$ST['groups']['pimelig']['id']
  $IdRename = [string]$ST['groups']['rename']['id']; $IdConflictA = [string]$ST['groups']['conflicta']['id']
  $IdConflictB = [string]$ST['groups']['conflictb']['id']; $IdPimDynamic = [string]$ST['groups']['pimdynamic']['id']
  $IdCc = [string]$S65Sp.id
  $RoleIdRR  = Get-S65RawRoleDefinitionId -Name $RoleRR
  $RoleIdMCR = Get-S65RawRoleDefinitionId -Name $RoleMCR
  $PolicyIdRR  = (Get-S65RawPolicy -RoleDefinitionId $RoleIdRR -Label '0.5-rr-policy-raw').PolicyId
  $PolicyIdMCR = (Get-S65RawPolicy -RoleDefinitionId $RoleIdMCR -Label '0.5-mcr-policy-raw').PolicyId
  foreach ($U in @(@{ Id = $IdUser1; Upn = $User1Upn }, @{ Id = $IdUser2; Upn = $User2Upn })) {
      $R = Get-S65RawStatus -Uri "v1.0/users/$($U.Id)?`$select=id,userPrincipalName,accountEnabled"
      '<{0}>: status {1}; user principal name as expected {2}; enabled {3}' -f (Get-S65Name $U.Id), $R.Status, ([string]$R.Body['userPrincipalName'] -eq $U.Upn), $R.Body['accountEnabled']
  }
  foreach ($Id in $IdRag, $IdPimUntouched, $IdPimPolicy, $IdPimElig, $IdPimDynamic, $IdRename, $IdConflictA, $IdConflictB) { $null = Get-S65RawGroup -Id $Id -Label "0.5-$(Get-S65Name $Id)" }
  $D05 = Get-S65RawStatus -Uri "v1.0/groups/$IdPimDynamic`?`$select=groupTypes,membershipRule,membershipRuleProcessingState"
  "0.5 oer-s65-pim-dynamic: status $($D05.Status); dynamic $(@($D05.Body['groupTypes']) -contains 'DynamicMembership'); rule as set $([string]$D05.Body['membershipRule'] -ceq '(user.department -eq "oer-s65-none")'); processing $($D05.Body['membershipRuleProcessingState'])"
  $S05Ids = @($IdUser1, $IdUser2, $IdRag, $IdPimUntouched, $IdPimPolicy, $IdPimElig, $IdPimDynamic, $IdRename, $IdConflictA, $IdConflictB, $IdCc, $RoleIdRR, $RoleIdMCR)
  "ids read: $(@($S05Ids | Where-Object { Test-S65Guid $_ }).Count) of 13; all different: $(@($S05Ids | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique).Count -eq 13)"
  "policy ids read: $([bool]$PolicyIdRR) $([bool]$PolicyIdMCR); different: $($PolicyIdRR -ne $PolicyIdMCR)"
  ```

  **Expect:** `<oer-s65-user1>: status 200; user principal name as expected True; enabled False` and
  the same for `<oer-s65-user2>`; `0.5-oer-s65-rag: group <oer-s65-rag>: displayName 'oer-s65-rag'; ... isAssignableToRole 'True'; securityEnabled True; members [oer-s65-user2]`;
  the seven others each with its setup name as `displayName`, `isAssignableToRole 'False'` or `''`
  (null prints as `''`; both mean not role-assignable -- record which), `securityEnabled True` and
  `members []`;
  `0.5 oer-s65-pim-dynamic: status 200; dynamic True; rule as set True; processing On`;
  `ids read: 13 of 13; all different: True`; `policy ids read: True True; different: True`.
  **Failure looks like:** a status other than 200, an enabled user, a group of the wrong shape or with
  a member it should not have, or a count off -- the prerequisite run did not finish: read its output
  again. A 403 is a missing permission (Stop conditions).
  **Result:**

---

### 1. The pimPolicy criterion, measured against Graph

`Test-OERGroupPimInUse` decides whether a group uses PIM for Groups, and the rationale
(docs/development/rationale.md, `pim-in-use-criterion`) says the criterion is "NOT counted as proven
until it is measured live" on these groups: `oer-s65-pim-untouched` (nothing PIM ever done),
`oer-s65-pim-policy` (its member policy changed once by the prerequisite script),
`oer-s65-pim-elig` (onboarded only through an eligibility) and -- measured in 1.5 --
`oer-s65-pim-dynamic`, a dynamic group, which PIM for Groups cannot manage (Microsoft Learn), and
for which the criterion takes a 400 `ResourceTypeNotSupported` on its listing as "not in use".
Microsoft Learn documents the untouched shape for a GROUP policy (`lastModifiedDateTime` null,
`lastModifiedBy` with a null id and display name), but shows a modified shape only for a directory
policy, does not say whether an eligibility request stamps the group's policies, and does not say
what the listing answers for a dynamic group -- 1.1 and 1.5 measure all of it. **What this section does
not measure:** a group used only through PIM ACTIVE assignments, with untouched policies, reads as
"not in use" by design (the documented blind spot); the certificate identity can no longer create an
active group assignment, so it is not run live ("What this file does not check").

- [ ] **1.1 The independent read: Graph's own policy fields and eligibility, per group.** Read-only, outside the module.

  ```powershell
  $P11U = Get-S65RawGroupPim -GroupId $IdPimUntouched -Label '1.1-untouched'
  $P11P = Get-S65RawGroupPim -GroupId $IdPimPolicy -Label '1.1-policy'
  $P11E = Get-S65RawGroupPim -GroupId $IdPimElig -Label '1.1-elig'
  ```

  **Expect:** `oer-s65-pim-untouched`: `policy listing status 200`, two policies (member and owner),
  every field `set False`, `any policy modified: False`, and eligibility `0` -- or a listing answering
  `404 ResourceNotFound` (PIM does not know the group) and eligibility reads answering
  `400 ResourceTypeNotSupported` or `404`: record which; both mean "not in use" to the criterion.
  `oer-s65-pim-policy`: status 200; the `(member)` policy with `lastModifiedDateTime set True` (record
  both `lastModifiedBy` fields -- Learn shows `id` null on a modified directory policy); the `(owner)`
  policy all `False` (record it); `any policy modified: True`; eligibility `0`. `oer-s65-pim-elig`:
  status 200; eligibility schedules `1` and instances `1`; record whether any policy field is `True`
  -- that is the answer to "does an eligibility request stamp the group's policies", and it is data,
  not a pass or fail.
  **Failure looks like:** `oer-s65-pim-untouched` with any field `True` or any eligibility -- the group
  was onboarded after all (by an earlier 1.4 run without `-WhatIf`?): stop, section 1 cannot measure
  "not in use"; `oer-s65-pim-policy` with its member policy all `False` -- a modified group policy
  shows no modification, so the criterion's policy half does not work on groups: record it, it is a
  finding against R1; `oer-s65-pim-elig` with eligibility `0` -- the prerequisite request did not
  land; a 403 on any read -- a missing permission.
  **Result:**

- [ ] **1.2 `Test-OERGroupPimInUse` per group.** Read-only; the helper runs in the module's scope, with the eligibility count 1.1 read for the group, exactly as `Get-OERInventory` passes it.

  ```powershell
  $M = Get-Module Omnicit.EntraRBAC
  foreach ($G in @(@{ Name = "$Pim-untouched"; Id = $IdPimUntouched; Count = [math]::Max(0, $P11U.Instances) },
          @{ Name = "$Pim-policy"; Id = $IdPimPolicy; Count = [math]::Max(0, $P11P.Instances) },
          @{ Name = "$Pim-elig"; Id = $IdPimElig; Count = [math]::Max(0, $P11E.Instances) })) {
      try {
          $R = & $M { param($Id, $Count) Test-OERGroupPimInUse -GroupId $Id -EligibilityCount $Count } $G.Id $G.Count
          '{0} (eligibility count {1}): InUse {2}; Reason: {3}' -f $G.Name, $G.Count, $R.InUse, $R.Reason
      } catch {
          '{0}: the criterion THREW: {1}' -f $G.Name, (Format-S65Text $PSItem.Exception.Message)
          $global:Error.Clear()
      }
  }
  try {
      $R0 = & $M { param($Id) Test-OERGroupPimInUse -GroupId $Id } $IdPimElig
      "oer-s65-pim-elig on its policies alone (eligibility count 0; data, not pass/fail): InUse $($R0.InUse); Reason: $($R0.Reason)"
  } catch {
      'oer-s65-pim-elig on its policies alone: the criterion THREW: {0}' -f (Format-S65Text $PSItem.Exception.Message)
      $global:Error.Clear()
  }
  ```

  **Expect:**
  `oer-s65-pim-untouched (eligibility count 0): InUse False; Reason: no PIM policy of the group has been modified and no PIM eligibility was counted`
  (or `Reason: PIM for Groups does not know the group (404 ResourceNotFound)` when 1.1 read the 404),
  `oer-s65-pim-policy (eligibility count 0): InUse True; Reason: a PIM policy of the group has been modified`,
  `oer-s65-pim-elig (eligibility count 1): InUse True; Reason: the group has PIM eligibility`. The
  data line: `InUse` equal to 1.1's `any policy modified` for `oer-s65-pim-elig` -- record it.
  **Failure looks like:** any other `InUse` in the first three lines -- the criterion is wrong for that
  case: record 1.1's fields beside it, it is a defect; a `THREW` line -- a listing answered something
  other than 200 or 404 (a 403 is a missing permission).
  **Result:**

- [ ] **1.3 The export follows the criterion: `pimPolicy` for the two groups in use only, and the untouched and the dynamic group each cost one PIM listing and no policy read.** Read-only.

  ```powershell
  Invoke-S65Call -Cmdlet Get-OERInventory -Splat @{ Include = 'Groups'; GroupFilter = "startswith(displayName,'$Pim')" } -Label '1.3 the four oer-s65-pim groups'
  $Inv13 = $S65Out | Select-Object -First 1
  ConvertTo-Json -InputObject $Inv13 -Depth 20 | Set-Content -Path (Join-Path $Raw '1.3-inventory.json') -Encoding utf8NoBOM
  foreach ($N in "$Pim-untouched", "$Pim-policy", "$Pim-elig", "$Pim-dynamic") {
      $G = @($Inv13.groups | Where-Object { $_.displayName -eq $N })
      $Has = ($G.Count -eq 1) -and ($G[0].PSObject.Properties.Name -contains 'pimPolicy')
      $Max = if ($Has -and $G[0].pimPolicy.PSObject.Properties.Name -contains 'member') { $G[0].pimPolicy.member.activationMaxHours } else { '-' }
      $E = [regex]::Escape("<$N>")
      '{0}: in the inventory {1}; pimPolicy present {2} (member activationMaxHours {3}); requests: eligibility read {4}, criterion listing {5}, policy-assignment listings {6}, rule reads {7}' -f $N, $G.Count, $Has, $Max,
          @($S65Requests | Where-Object { $_ -match "^GET beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances\?.*groupId eq '$E'" }).Count,
          @($S65Requests | Where-Object { $_ -match "^GET beta/policies/roleManagementPolicies\?.*scopeId eq '$E'" }).Count,
          @($S65Requests | Where-Object { $_ -match "^GET beta/policies/roleManagementPolicyAssignments\?.*scopeId eq '$E'" }).Count,
          @($S65Requests | Where-Object { $_ -match "^GET beta/policies/roleManagementPolicies/[^?]*$E[^?]*/rules" }).Count
  }
  "rule reads in all: $(@($S65Requests | Where-Object { $_ -match '^GET beta/policies/roleManagementPolicies/[^?]+/rules' }).Count)"
  ```

  **Expect:** the call: no warning, no error, one object. `oer-s65-pim-untouched: in the inventory 1; pimPolicy present False (member activationMaxHours -); requests: eligibility read 1, criterion listing 1, policy-assignment listings 0, rule reads 0`
  -- ONE PIM request for the criterion and no policy read at all -- and among the cmdlet's own verbose
  lines `Get-OERInventory: group 'oer-s65-pim-untouched': pimPolicy not exported -- no PIM policy of the group has been modified and no PIM eligibility was counted.`
  (or `-- PIM for Groups does not know the group (404 ResourceNotFound).`, as 1.2).
  `oer-s65-pim-policy: in the inventory 1; pimPolicy present True (member activationMaxHours 4); requests: eligibility read 1, criterion listing 1, policy-assignment listings 4, rule reads 2`
  (two listings ask whether each access type has a policy, two more come with the two policy reads).
  `oer-s65-pim-elig: in the inventory 1; pimPolicy present True (member activationMaxHours <n>); requests: eligibility read 1, criterion listing 0, policy-assignment listings 4, rule reads 2`
  -- its counted eligibility decides without a listing.
  `oer-s65-pim-dynamic: in the inventory 1; pimPolicy present False (member activationMaxHours -); requests: eligibility read 1, criterion listing 1, policy-assignment listings 0, rule reads 0`,
  with the verbose line
  `Get-OERInventory: group 'oer-s65-pim-dynamic': pimPolicy not exported -- PIM for Groups cannot manage the group (ResourceTypeNotSupported).`
  (or the reason 1.5 reads for it). `rule reads in all: 4`. The rule-read split
  per group relies on Graph's policy id carrying the group id (`Group_<group id>_<guid>`); when it
  does not, the per-group counts read 0 and only the total counts -- record which.
  **Failure looks like:** `pimPolicy present True` for the untouched or the dynamic group, or any
  policy read for either -- the criterion runs after the reads, or says "in use" (1.2, 1.5);
  `pimPolicy present False` for either of the others; a warning or an `InventoryPartial` error -- a
  read failed: record its message. An `InventoryPartial` naming `groups/oer-s65-pim-dynamic/pimPolicy`
  with a `Could not determine whether group ...` cause is the defect the fix "treat a group PIM for
  Groups cannot manage as not using it" exists for: Graph answered the dynamic group's listing with a
  code the criterion does not declare -- record it with 1.5's raw answer.
  **Result:**

- [ ] **1.4 The onboarding warning, `-WhatIf` ONLY: a changed `pimPolicy` for the untouched group warns, for the modified one it does not, and nothing is written.** Never run these two documents without `-WhatIf` -- `Invoke-S65Check` without `-Apply` IS `-WhatIf`.

  ```powershell
  $Doc14a = New-S65Doc -Group ([ordered]@{ displayName = "$Pim-untouched"; pimPolicy = [ordered]@{ member = [ordered]@{ activationMaxHours = 2 } } })
  Invoke-S65Check -Id '1.4a' -Json $Doc14a -Include Groups
  $Doc14b = New-S65Doc -Group ([ordered]@{ displayName = "$Pim-policy"; pimPolicy = [ordered]@{ member = [ordered]@{ activationMaxHours = 2 } } })
  Invoke-S65Check -Id '1.4b' -Json $Doc14b -Include Groups
  $P14U = Get-S65RawGroupPim -GroupId $IdPimUntouched -Label '1.4-untouched-after'
  ```

  **Expect:** in the order printed -- `Invoke-S65Check` shows PowerShell's own `What if:` line while
  the call runs and the warnings it captured only after the call -- 1.4a: `Valid = True`; the line
  `What if: Performing the operation "Set PIM policy (member): activationMaxHours=2" on target "oer-s65-pim-untouched"`;
  then `--- warnings, in the order written: 1` and the ONE warning,
  `WARNING: Sync-OERStructureGroup: group 'oer-s65-pim-untouched' was not found to use PIM for Groups (no PIM policy of the group has been modified and no PIM eligibility was counted); applying its pimPolicy onboards it to PIM for Groups, which cannot be undone (Microsoft Graph documentation, 'Onboarding groups to PIM for Groups').`
  -- the handler writes it BEFORE its `ShouldProcess` gate, which is why `-WhatIf` shows it at all.
  The reason says "no PIM eligibility was counted" because a `pimPolicy`-only entry makes the
  handler read no eligibility (it reads PIM eligibility only when the entry declares `eligibility`),
  so the count it passes is 0 by construction; with 1.1's 404 the reason reads
  `(PIM for Groups does not know the group (404 ResourceNotFound))` instead. No error; two rows,
  `[groups] oer-s65-pim-untouched | Unchanged | group properties match` and
  `[groups] oer-s65-pim-untouched | Skipped | would set pimPolicy (member): activationMaxHours=2`.
  1.4b: `Valid = True`; the `What if:` line for `oer-s65-pim-policy`; `--- warnings, in the order written: 0`; the rows
  `Unchanged | group properties match` and `Skipped | would set pimPolicy (member): activationMaxHours=2`.
  Afterwards `1.4-untouched-after` reads exactly as 1.1 did: `any policy modified: False` and no
  eligibility -- the plan wrote nothing.
  **Failure looks like:** no warning in 1.4a -- the handler did not ask the criterion, or the
  criterion said "in use"; a warning in 1.4b -- the criterion missed the modified policy; any row
  `Updated`, or `1.4-untouched-after` with a field `True` -- the plan WROTE: stop, the untouched
  group is onboarded and section 1's measurement is spent; record it.
  **Result:**

- [ ] **1.5 A dynamic group PIM for Groups cannot manage: Graph's raw answer on the criterion's listing, and the criterion's answer.** Read-only; nothing PIM is ever written to `oer-s65-pim-dynamic`.

  ```powershell
  $P15 = Get-S65RawGroupPim -GroupId $IdPimDynamic -Label '1.5-dynamic'
  $M = Get-Module Omnicit.EntraRBAC
  try {
      $R15 = & $M { param($Id) Test-OERGroupPimInUse -GroupId $Id } $IdPimDynamic
      "oer-s65-pim-dynamic (eligibility count 0): InUse $($R15.InUse); Reason: $($R15.Reason)"
  } catch {
      'oer-s65-pim-dynamic: the criterion THREW: {0}' -f (Format-S65Text $PSItem.Exception.Message)
      $global:Error.Clear()
  }
  ```

  **Expect:** `1.5-dynamic: <oer-s65-pim-dynamic>: policy listing status <status> <code>` -- RECORD
  the status and code: this is the first measurement of what the criterion's listing
  (`beta/policies/roleManagementPolicies?$filter=scopeId eq '<id>' and scopeType eq 'Group'`) answers
  for a group PIM for Groups cannot manage. Expected: `400 ResourceTypeNotSupported`, the answer the
  module's sibling reads of the same family already take for such a group. A `404 ResourceNotFound`,
  or `200` with untouched policies (`any policy modified: False`), are the two other answers the
  criterion reads as not in use -- record which Graph gave. Record the eligibility reads' status and
  code too (expected `400 ResourceTypeNotSupported`). Then the criterion, with the 400:
  `oer-s65-pim-dynamic (eligibility count 0): InUse False; Reason: PIM for Groups cannot manage the group (ResourceTypeNotSupported)`
  -- or, with the other two answers, `Reason: PIM for Groups does not know the group (404 ResourceNotFound)`
  or `Reason: no PIM policy of the group has been modified and no PIM eligibility was counted`. 1.3
  showed the export of the same group: no `pimPolicy`, and no `InventoryPartial`.
  **Failure looks like:** a `THREW` line -- the listing answered a code the criterion does not
  declare: record the status and code `1.5-dynamic` printed (it names the code), it is a defect of
  the fix for dynamic groups; `InUse True` -- a group PIM cannot manage shows a modified policy:
  record the fields; a 403 -- a missing permission (Stop conditions).
  **Result:**

---

### 2. The directory sections exported

Ruling R15: the spec's "checked against the portal" is done as an INDEPENDENT raw Microsoft Graph
read -- the certificate identity has no portal, and the raw schedules are the same data the portal
shows.

- [ ] **2.1 `Get-OERInventory` exports exactly the `oer-s65` directory assignments Graph holds, and Reports Reader's policy with activation maximum 3.** Read-only.

  ```powershell
  Invoke-S65Call -Cmdlet Get-OERInventory -Splat @{ Include = 'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments' } -Label '2.1 the two directory sections'
  $Inv21 = $S65Out | Select-Object -First 1
  ConvertTo-Json -InputObject $Inv21 -Depth 20 | Set-Content -Path (Join-Path $Raw '2.1-inventory.json') -Encoding utf8NoBOM
  $Two21 = @($Inv21.directoryRoleAssignments | Where-Object { $_.role -in $RoleRR, $RoleMCR })
  "assignment entries: $(@($Inv21.directoryRoleAssignments).Count) in all, of the two roles $($Two21.Count); policy entries: $(@($Inv21.directoryRoleManagementPolicies).Count) in all"
  $Two21 | ForEach-Object { '    entry: {0} | {1} | {2} | {3} | durationDays {4} | id present {5}' -f $_.role, (Format-S65Text $_.principal), $_.principalType, $_.assignmentType,
      $(if ($_.PSObject.Properties.Name -contains 'durationDays') { $_.durationDays } else { '(none)' }), ($_.PSObject.Properties.Name -contains 'id') }
  "entries of other roles naming an oer-s65 principal: $(@($Inv21.directoryRoleAssignments | Where-Object { $_.role -notin $RoleRR, $RoleMCR -and ([string]$_.principal).StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
  foreach ($P in @($Inv21.directoryRoleManagementPolicies | Where-Object { $_.role -in $RoleRR, $RoleMCR })) {
      '    policy {0}: activationMaxHours {1}; allowPermanentEligibility {2}; eligibleDurationDays {3}; allowPermanentActiveAssignment {4}; activeDurationDays {5}; requireApproval {6}; scope key {7}; id present {8}' -f
          $P.role, $P.activationMaxHours, $P.allowPermanentEligibility, $P.eligibleDurationDays, $P.allowPermanentActiveAssignment, $P.activeDurationDays, $P.requireApproval,
          ($P.PSObject.Properties.Name -contains 'scope'), ($P.PSObject.Properties.Name -contains 'id')
  }
  $Raw21 = @(Get-S65RawRoleRow -RoleName $RoleRR -RoleDefinitionId $RoleIdRR) + @(Get-S65RawRoleRow -RoleName $RoleMCR -RoleDefinitionId $RoleIdMCR)
  $Raw21 | ForEach-Object { '    raw: {0} {1} <{2}> memberType {3}; scope {4}; assignmentType {5}; days {6}' -f $_.Role, $_.Kind, (Get-S65Name $_.PrincipalId), $_.MemberType, $_.Scope, $_.AssignmentType, $(if ($_.Days) { $_.Days } else { 'never ends' }) }
  $Want = @{}; $Want[$IdUser1] = @($User1Upn, 'User'); $Want[$IdUser2] = @($User2Upn, 'User'); $Want[$IdRag] = @($RagName, 'Group')
  $Managed = @($Raw21 | Where-Object { $_.MemberType -eq 'Direct' -and $_.Scope -eq '/' -and ($_.Kind -eq 'Eligible' -or $_.AssignmentType -eq 'Assigned') })
  $RawKeys = @($Managed | ForEach-Object { $W = $Want[$_.PrincipalId]; ('{0}|{1}|{2}|{3}|{4}' -f $_.Role, $(if ($W) { $W[0] } else { $_.PrincipalId }), $(if ($W) { $W[1] } else { '?' }), $_.Kind, $_.Days).ToLowerInvariant() } | Sort-Object)
  $OutKeys = @($Two21 | ForEach-Object { ('{0}|{1}|{2}|{3}|{4}' -f $_.role, $_.principal, $_.principalType, $_.assignmentType, $(if ($null -ne $_.durationDays) { $_.durationDays } else { '' })).ToLowerInvariant() } | Sort-Object)
  "managed raw rows of the two roles: $($RawKeys.Count); exported entries of the two roles: $($OutKeys.Count); the same (role, principal, principalType, assignmentType, durationDays): $(($RawKeys -join ';') -ceq ($OutKeys -join ';'))"
  "only raw: [$((@($RawKeys | Where-Object { $OutKeys -notcontains $_ }) | ForEach-Object { Format-S65Text $_ }) -join '; ')]; only exported: [$((@($OutKeys | Where-Object { $RawKeys -notcontains $_ }) | ForEach-Object { Format-S65Text $_ }) -join '; ')]"
  ```

  **Expect:** the call: requests
  `GET v1.0/roleManagement/directory/roleEligibilitySchedules?$filter=directoryScopeId eq '/'&$expand=principal,roleDefinition`,
  the same for `roleAssignmentSchedules` (each read ONCE, plus a page each when Graph pages), one
  `POST v1.0/directoryObjects/getByIds` naming the users and groups, the policy list
  (`GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole'&$expand=policy($expand=rules)`)
  and the role-definition list; no warning, no error, one object. Exactly four entries of the two
  roles, sorted role, Eligible before Active, principal:
  `Message Center Reader | oer-s65-rag | Group | Active | durationDays 2 | id present False`,
  `Message Center Reader | oer-s65-user1@<test domain> | User | Active | durationDays 3` (or
  `durationDays (none)` when 0.3 printed that a permanent active assignment is allowed),
  `Reports Reader | oer-s65-rag | Group | Eligible | durationDays 10` (or `(none)` when a permanent
  eligibility is allowed) and `Reports Reader | oer-s65-user1@<test domain> | User | Eligible | durationDays 5`;
  NO entry for `oer-s65-user2`, which holds both roles only through `oer-s65-rag` (an inherited raw
  row, when Graph lists one, has a `memberType` other than `Direct` -- record whether it does);
  `entries of other roles naming an oer-s65 principal: 0`. The policies:
  `policy Reports Reader: activationMaxHours 3; ...; scope key False; id present False` and
  `policy Message Center Reader: activationMaxHours <n>; ...` -- record the other values. Every raw
  row of the two roles names a test principal; the comparison
  `managed raw rows of the two roles: 4; exported entries of the two roles: 4; the same ...: True`,
  `only raw: []; only exported: []`.
  **Failure looks like:** a raw row naming `<not a test object>` -- someone else holds the role:
  stop; an entry missing, extra, or with another principal form, type or `durationDays` -- the
  export does not say what Graph holds: record both keys, it is a defect; an entry for
  `oer-s65-user2`, or for an activation -- the managed-row filter failed; `activationMaxHours` other
  than 3 for Reports Reader -- the prerequisite change did not land, or the projection is wrong
  (compare with `0.5-rr-policy-raw.json`); a `scope` or `id` key -- the directory projection kept a
  field it must not.
  **Result:**

- [ ] **2.2 `-AllDirectoryRolePolicies` exports every role's policy: more than the default, and exactly as many as Graph lists.** Read-only.

  ```powershell
  Invoke-S65Call -Cmdlet Get-OERInventory -Splat @{ Include = 'DirectoryRoleManagementPolicies'; AllDirectoryRolePolicies = $true } -Label '2.2 every directory role policy'
  $All22 = @(($S65Out | Select-Object -First 1).directoryRoleManagementPolicies).Count
  $Default22 = @($Inv21.directoryRoleManagementPolicies).Count
  $F = [uri]::EscapeDataString("scopeId eq '/' and scopeType eq 'DirectoryRole'")
  $R22 = Get-S65RawAll -Uri "v1.0/policies/roleManagementPolicyAssignments?`$filter=$F"
  "policy entries: default (2.1) $Default22; -AllDirectoryRolePolicies $All22; raw policy assignments at '/' $($R22.Rows.Count) (status $($R22.Status) $($R22.ErrorCode))"
  "more than the default: $($All22 -gt $Default22); equal to the raw count: $($All22 -eq $R22.Rows.Count)"
  "schedule reads in this call: $(@($S65Requests | Where-Object { $_ -match 'roleEligibilitySchedules|roleAssignmentSchedules' }).Count)"
  ```

  **Expect:** the call: the policy list and the role-definition list only, no warning, no error;
  `schedule reads in this call: 0` (the help: with the switch "the schedules are then not read for
  the policy section at all"); `more than the default: True; equal to the raw count: True`. Record
  the three numbers.
  **Failure looks like:** `equal to the raw count: False` -- a policy dropped or doubled (Graph can
  page this list: record the page count from the requests); `more than the default: False` -- every
  directory role in the tenant is in use, which is implausible: record it; a schedule read -- the
  switch did not skip it.
  **Result:**

- [ ] **2.3 `Export-OERInventory` with its default `-Include`: both directory files, both sections in `inventory.json` without `id`, the summary counts, and `Test-OERStructure` Valid.** Signs in again WITH Azure Resource Manager: the default `-Include` has `RoleAssignments`, which walks Azure. Writes only under `raw/s65/`.

  ```powershell
  Connect-S65 -Arm
  "the session holds an Azure Resource Manager token: $([bool](& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.ArmToken }))"
  $Out23 = Join-Path $Raw 'export-2.3'
  New-Item -ItemType Directory -Path $Out23 -Force | Out-Null
  $B23 = Export-OERInventory -OutputPath $Out23 -ErrorAction SilentlyContinue -ErrorVariable E23 -WarningAction SilentlyContinue -WarningVariable W23
  "warnings: $(@($W23).Count)"; @($W23) | ForEach-Object { "    WARNING: $(Format-S65Text $_.Message)" }
  "errors: $(@($E23).Count)"; @($E23) | ForEach-Object { "    ERROR [$($_.FullyQualifiedErrorId)]: $(Format-S65Text $_.Exception.Message)" }
  $global:Error.Clear()
  "bundle: $(Format-S65Text (Split-Path $B23.BundlePath -Leaf)); files: $($B23.Files -join ', ')"
  foreach ($F in 'inventory.json', 'directoryRoleManagementPolicies.json', 'directoryRoleAssignments.json', 'azurePimEligibility.json') { '{0} exists: {1}' -f $F, (Test-Path -LiteralPath (Join-Path $B23.BundlePath $F)) }
  $Doc23 = Get-Content -LiteralPath (Join-Path $B23.BundlePath 'inventory.json') -Raw | ConvertFrom-Json
  $PolFile = @(Get-Content -LiteralPath (Join-Path $B23.BundlePath 'directoryRoleManagementPolicies.json') -Raw | ConvertFrom-Json)
  $AsgFile = @(Get-Content -LiteralPath (Join-Path $B23.BundlePath 'directoryRoleAssignments.json') -Raw | ConvertFrom-Json)
  "inventory.json keys: $($Doc23.PSObject.Properties.Name -join ', ')"
  "inventory.json directoryRoleManagementPolicies $(@($Doc23.directoryRoleManagementPolicies).Count) (with id: $(@($Doc23.directoryRoleManagementPolicies | Where-Object { $_.PSObject.Properties.Name -contains 'id' }).Count)); directoryRoleAssignments $(@($Doc23.directoryRoleAssignments).Count) (with id: $(@($Doc23.directoryRoleAssignments | Where-Object { $_.PSObject.Properties.Name -contains 'id' }).Count))"
  "per-area files equal the sections: policies $((ConvertTo-Json -InputObject $PolFile -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject @($Doc23.directoryRoleManagementPolicies) -Depth 20 -Compress)); assignments $((ConvertTo-Json -InputObject $AsgFile -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject @($Doc23.directoryRoleAssignments) -Depth 20 -Compress))"
  "summary: DirectoryRoleManagementPolicies $($B23.DirectoryRoleManagementPolicies); DirectoryRoleAssignments $($B23.DirectoryRoleAssignments); AzurePimEligibility $($B23.AzurePimEligibility); ScopesEnumerated $($B23.ScopesEnumerated); ScopeCount $($B23.ScopeCount); SkippedScopes [$((@($B23.SkippedScopes) | ForEach-Object { Format-S65Text $_ }) -join ', ')]; SkippedEligibilityScopes [$((@($B23.SkippedEligibilityScopes) | ForEach-Object { Format-S65Text $_ }) -join ', ')]; IncompleteReads $(@($B23.IncompleteReads).Count)"
  "summary counts equal inventory.json: $($B23.DirectoryRoleManagementPolicies -eq @($Doc23.directoryRoleManagementPolicies).Count -and $B23.DirectoryRoleAssignments -eq @($Doc23.directoryRoleAssignments).Count)"
  $Key = { param($E) ('{0}|{1}|{2}|{3}' -f $E.role, $E.principal, $E.assignmentType, $E.durationDays).ToLowerInvariant() }
  "the two roles' assignment entries equal 2.1's: $(((@($Doc23.directoryRoleAssignments | Where-Object { $_.role -in $RoleRR, $RoleMCR }) | ForEach-Object { & $Key $_ }) -join ';') -ceq ((@($Two21) | ForEach-Object { & $Key $_ }) -join ';'))"
  $V23 = Test-OERStructure -Path (Join-Path $B23.BundlePath 'inventory.json')
  $F23 = @($V23.Errors | Where-Object { $null -ne $_ })
  "Test-OERStructure on inventory.json: Valid $($V23.Valid); errors $(@($F23 | Where-Object { $_.Severity -eq 'Error' }).Count); warnings $(@($F23 | Where-Object { $_.Severity -ne 'Error' }).Count)"
  $F23 | Where-Object { $_.Section -like 'directoryRole*' } | ForEach-Object { "    [$($_.Severity)] $($_.Section) $($_.Path): $(Format-S65Text $_.Message)" }
  ```

  **Expect:** both identity lines `True`, then `the session holds an Azure Resource Manager token: True`.
  The export: no error (an `InventoryPartial` error is acceptable ONLY when it names management-group
  scopes as skipped -- R14 -- record it); warnings, if any, only "Skipping scope ..." for a management
  group. All four files `exists: True`; `inventory.json keys:` `version, groups, administrativeUnits, catalogs, accessPackages, accessReviews, directoryRoleManagementPolicies, directoryRoleAssignments, roleAssignments, roleManagementPolicies`;
  both sections non-empty, `(with id: 0)` twice; `per-area files equal the sections: policies True; assignments True`;
  the summary's two directory counts equal to the sections (`summary counts equal inventory.json: True`)
  and to 2.1's `policy entries` and `assignment entries` counts -- record them, with
  `AzurePimEligibility`, `ScopesEnumerated`, `ScopeCount` and the two skipped lists (section 4 reads
  the same walk); `IncompleteReads 0`; `the two roles' assignment entries equal 2.1's: True`;
  `Valid True; errors 0` -- record the warning count, and no finding in a `directoryRole*` section.
  **Failure looks like:** a missing file; an `id` in either section; a count mismatch; `Valid False`
  or a `directoryRole*` finding -- the exported sections do not validate: record the finding;
  `IncompleteReads` above 0 -- a default section could not be read: record the entry (a missing
  permission is a stop condition; `groups/oer-s65-pim-dynamic/pimPolicy` is the dynamic-group defect
  of 1.3 and 1.5); an `InventoryPartial` naming a subscription -- the Azure walk could
  not read the test subscription: stop, sections 2 to 4 need it.
  **Result:**

---

### 3. The round trip -- the export applied back changes nothing (R13, G11)

Ruling R13: the full export's directory sections are applied only with `-WhatIf` (every role in the
tenant, read-only); the real applies run on a document filtered to Reports Reader and Message Center
Reader. The documents are built from 2.3's `inventory.json`, read from disk again, so this section
also runs from a reopened window.

- [ ] **3.1 Every directory role, `-WhatIf` only: every row `Unchanged`.**

  ```powershell
  $B23Path = (Get-ChildItem -LiteralPath (Join-Path $Raw 'export-2.3') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
  $Doc23 = Get-Content -LiteralPath (Join-Path $B23Path 'inventory.json') -Raw | ConvertFrom-Json
  $Doc31 = [ordered]@{ version = $Doc23.version; directoryRoleManagementPolicies = @($Doc23.directoryRoleManagementPolicies); directoryRoleAssignments = @($Doc23.directoryRoleAssignments) } | ConvertTo-Json -Depth 20
  Invoke-S65Check -Id '3.1' -Json $Doc31 -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -Quiet
  ```

  **Expect:** `Valid = True`; no warning, no error, no `What if:` line; the rows shown are the six of
  the two roles, each `Unchanged` (see 3.2 for their text); and the counts
  `directoryRoleManagementPolicies, Unchanged=<n>; directoryRoleAssignments, Unchanged=<m>`, where
  `<n>` and `<m>` are 2.3's section counts -- every row `Unchanged`, nothing else. Record `<n>` and
  `<m>`.
  **Failure looks like:** ANY row that is not `Unchanged` -- `Skipped` with `would update`, `would
  create`, `Extra` or `Failed`: **STOP**. The export does not converge on this tenant for that entry
  (it is printed; a `What if:` line above it names the principal as it stands -- redact it). Record
  the row; do not run 3.2's real apply until it is understood.
  **Result:**

- [ ] **3.2 The two roles: the plan all `Unchanged`, the real run all `Unchanged` with no write request, and a second real run the same.**

  ```powershell
  $Two = { param($Entries) @($Entries | Where-Object { $_.role -in $RoleRR, $RoleMCR }) }
  $Doc32 = [ordered]@{ version = $Doc23.version; directoryRoleManagementPolicies = @(& $Two $Doc23.directoryRoleManagementPolicies); directoryRoleAssignments = @(& $Two $Doc23.directoryRoleAssignments) } | ConvertTo-Json -Depth 20
  Invoke-S65Check -Id '3.2a' -Json $Doc32 -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -ShowRequests
  ```

  Only when the plan is all `Unchanged`:

  ```powershell
  Invoke-S65Check -Id '3.2b' -Json $Doc32 -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -ShowRequests -Apply
  Invoke-S65Check -Id '3.2c' -Json $Doc32 -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -ShowRequests -Apply
  ```

  **Expect:** the document holds two policy entries and four assignment entries (2.1's). Each of the
  three runs: `Valid = True`; no warning, no error, no `What if:` line; exactly six rows,
  `[directoryRoleManagementPolicies] Message Center Reader | Unchanged | policy already matches for 'Message Center Reader'`,
  `[directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'`,
  and four `[directoryRoleAssignments] <role> -> <principal> (<assignmentType>) | Unchanged | assignment matches`
  -- `Reports Reader -> oer-s65-user1@<test domain> (Eligible)`, `Reports Reader -> oer-s65-rag (Eligible)`,
  `Message Center Reader -> oer-s65-rag (Active)`, `Message Center Reader -> oer-s65-user1@<test domain> (Active)`;
  the counts `directoryRoleManagementPolicies, Unchanged=2; directoryRoleAssignments, Unchanged=4`;
  and `requests that are not a GET: 0; writes among them ...: 0` (record the GET count of each run).
  **Failure looks like:** a row that is not `Unchanged` in 3.2a -- STOP, do not run 3.2b; a POST,
  PATCH, PUT or DELETE in 3.2b or 3.2c -- the engine wrote although every row was `Unchanged`:
  record the request, it is a defect; 3.2c different from 3.2b -- the first real run changed
  something after all.
  **Result:**

- [ ] **3.3 The two roles with `-Prune -WhatIf`: nothing would be removed.**

  ```powershell
  Invoke-S65Check -Id '3.3' -Json $Doc32 -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments -Prune
  "rows that remove, would remove or report Extra: $(@($S65Result | Where-Object { $_.Action -in 'Removed', 'Extra' -or ($_.Action -eq 'Skipped' -and ([string]$_.Detail).StartsWith('would remove', [System.StringComparison]::Ordinal)) }).Count)"
  ```

  **Expect:** the same six `Unchanged` rows as 3.2, no warning, no `What if:` line, and
  `rows that remove, would remove or report Extra: 0` -- every direct assignment in the two declared
  (role, assignmentType) pairs is declared, since the export named them all.
  **Failure looks like:** any `Removed`, `Extra` or `would remove` row -- the export left out an
  assignment the prune pass sees: record it; it is never run without `-WhatIf` in this file.
  **Result:**

---

### 4. `azurePimEligibility.json` -- the measurement of the unfiltered subscription read (R4)

This is the check docs/development/rationale.md (`inventory-azure-eligibility`) and
`Export-OERInventory`'s help point at as "the step 5 live-verification checklist, section 4".
`Resolve-OERInventoryScopeTree` enumerates management group and subscription scopes only, so a
resource-group-scoped eligibility can reach `azurePimEligibility.json` in exactly ONE way: through the
unfiltered subscription read's below-scope behaviour, which Microsoft Learn documents for none of the
four `listForScope` filters and not at all for an unfiltered read. **If the unfiltered subscription
read does NOT return the resource-group-level eligibility, resource-group eligibility is missing from
`azurePimEligibility.json`, the design does not capture resource-group-scoped eligibility at all,
and R4 must change** -- not a gap to document away. Ruling R14: the walk runs as `oer-live-cc`, which
holds Owner on the test subscription only; either no management group in the tree or
management-group scopes listed as skipped is accepted here, and section 6 covers the management
group level.

- [ ] **4.1 The file holds `oer-s65-user1`'s Reader eligibility at `oer-s65-rg`, read through the subscription.** Read-only; writes only under `raw/s65/`. The session from 2.3 holds the ARM token.

  ```powershell
  $Out41 = Join-Path $Raw 'export-4.1'
  New-Item -ItemType Directory -Path $Out41 -Force | Out-Null
  Invoke-S65Call -Cmdlet Export-OERInventory -Splat @{ OutputPath = $Out41; Include = 'RoleAssignments' } -Label '4.1 the default scope walk, RoleAssignments only'
  $B41 = $S65Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.InventoryBundle' } | Select-Object -First 1
  $R41 = @($S65Requests)
  $File41 = Join-Path $B41.BundlePath 'azurePimEligibility.json'
  $E41 = @(Get-Content -LiteralPath $File41 -Raw | ConvertFrom-Json)
  "azurePimEligibility.json exists: $(Test-Path -LiteralPath $File41); entries: $($E41.Count); at a scope below a subscription: $(@($E41 | Where-Object { [string]$_.scope -match '/resourceGroups/' }).Count)"
  $Rg41 = @($E41 | Where-Object { [string]::Equals([string]$_.scope, $RgScope, [System.StringComparison]::OrdinalIgnoreCase) })
  "entries at resource group oer-s65-rg: $($Rg41.Count)"
  $Rg41 | ForEach-Object { '    scope {0}; role {1}; principal {2}; principalType {3}; memberType {4}; status {5}; endDateTime in {6} days' -f (Format-S65Text $_.scope), $_.role, $_.principal, $_.principalType, $_.memberType, $_.status,
      $(if ($_.endDateTime) { [math]::Round(([datetime]$_.endDateTime - [datetime]::UtcNow).TotalDays, 1) } else { 'never' }) }
  "THE MEASUREMENT -- the unfiltered subscription read returned the resource-group-level eligibility of oer-s65-user1: $(@($Rg41 | Where-Object { $_.role -eq 'Reader' -and $_.principal -eq 'OER S65 User1' }).Count -eq 1)"
  ```

  **Expect:** the call: no error except, per R14, an `InventoryPartial` naming only management-group
  scopes as skipped (record it); one bundle object. `azurePimEligibility.json exists: True`;
  `entries at resource group oer-s65-rg: 1`, reading
  `scope /subscriptions/<SubId>/resourceGroups/oer-s65-rg; role Reader; principal OER S65 User1; principalType User; memberType Direct; status Provisioned; endDateTime in <about 30> days`
  (record the status and the exact figure); and
  `THE MEASUREMENT -- the unfiltered subscription read returned the resource-group-level eligibility of oer-s65-user1: True`.
  Record `entries` and `at a scope below a subscription` too.
  **Failure looks like:** `entries at resource group oer-s65-rg: 0` and `THE MEASUREMENT ...: False`
  while 4.3 finds the eligibility -- **the unfiltered subscription read does NOT return
  resource-group-level eligibility: resource-group eligibility is missing from
  `azurePimEligibility.json`, and the design (R4) must change.** Record it as that finding, not as a
  flake, and do not tick this box. The subscription in `SkippedEligibilityScopes` -- the read was
  refused (a missing permission, Stop conditions) and the measurement was not made: `[~]`.
  **Result:**

- [ ] **4.2 What the walk cost: one eligibility request per scope, plus one per extra page.** Read-only; from 4.1's captured requests and summary. The numbers go into the final report.

  ```powershell
  $Elig42 = @($R41 | Where-Object { $_ -match '^GET /.*/providers/Microsoft\.Authorization/roleEligibilitySchedules\?' })
  "roleEligibilitySchedules requests: $($Elig42.Count) (pages after the first: $(@($Elig42 | Where-Object { $_ -match 'skiptoken' }).Count))"
  $Elig42 | ForEach-Object { "    $_" }
  "ARM requests in all: $(@($R41 | Where-Object { $_ -match '^(GET|POST|PUT|PATCH|DELETE) /' }).Count)"
  "summary: ScopesEnumerated $($B41.ScopesEnumerated); ScopeCount $($B41.ScopeCount); SkippedScopes [$((@($B41.SkippedScopes) | ForEach-Object { Format-S65Text $_ }) -join ', ')]; SkippedEligibilityScopes [$((@($B41.SkippedEligibilityScopes) | ForEach-Object { Format-S65Text $_ }) -join ', ')]; AzurePimEligibility $($B41.AzurePimEligibility)"
  $H41 = Get-Content -LiteralPath (Join-Path $B41.BundlePath 'scopeHierarchy.json') -Raw | ConvertFrom-Json
  "scopeHierarchy.json: management groups $(@($H41.managementGroups).Count); subscriptions $(@($H41.subscriptions).Count)"
  "AzurePimEligibility equals the file's entries: $($B41.AzurePimEligibility -eq $E41.Count)"
  ```

  **Expect:** `roleEligibilitySchedules requests:` equal to `ScopesEnumerated` plus the pages after
  the first -- every scope of the walk read once, a management group with `$filter=atScope()` and the
  subscription with no `$filter` at all (`GET /subscriptions/<SubId>/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01`);
  per R14 either `management groups 0` (the identity sees none) or management-group scopes named in
  `SkippedScopes` and `SkippedEligibilityScopes`, and no subscription in either list;
  `AzurePimEligibility equals the file's entries: True`. Record every number: requests, pages,
  `ScopesEnumerated`, `ScopeCount`, both skipped lists, the ARM total and the hierarchy counts.
  **Failure looks like:** more eligibility requests than scopes plus pages -- a scope read twice, or
  one read per role (R4 says one per scope): record it; fewer -- a scope was not read at all; the
  subscription skipped -- see 4.1.
  **Result:**

- [ ] **4.3 An independent read of the resource group agrees with the file.** Read-only.

  ```powershell
  Invoke-S65Call -Cmdlet Get-OEREligibleRoleAssignment -Splat @{ Scope = $RgScope } -Label '4.3 the resource group read directly'
  $D43 = @($S65Out | Where-Object { [string]::Equals([string]$_.Scope, $RgScope, [System.StringComparison]::OrdinalIgnoreCase) })
  "rows AT the resource group: $($D43.Count); rows above it (inherited, not printed): $($S65Out.Count - $D43.Count)"
  $D43 | ForEach-Object { '    scope {0}; role {1}; principal {2}; principalType {3}; memberType {4}; status {5}; endDateTime in {6} days' -f (Format-S65Text $_.Scope), $_.RoleName, $_.PrincipalDisplayName, $_.PrincipalType, $_.MemberType, $_.Status,
      $(if ($_.EndDateTime) { [math]::Round(([datetime]$_.EndDateTime - [datetime]::UtcNow).TotalDays, 1) } else { 'never' }) }
  $K = { param($S, $R, $P, $T, $Mt, $St, $End) ('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $S, $R, $P, $T, $Mt, $St, $(if ($End) { ([datetime]$End).ToUniversalTime().ToString('s') } else { '' })).ToLowerInvariant() }
  "the file's entries at the resource group equal the direct read's: $(((@($Rg41) | ForEach-Object { & $K $_.scope $_.role $_.principal $_.principalType $_.memberType $_.status $_.endDateTime }) -join ';') -ceq ((@($D43) | ForEach-Object { & $K $_.Scope $_.RoleName $_.PrincipalDisplayName $_.PrincipalType $_.MemberType $_.Status $_.EndDateTime }) -join ';'))"
  ```

  **Expect:** one request,
  `GET /subscriptions/<SubId>/resourceGroups/oer-s65-rg/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01`;
  no error; `rows AT the resource group: 1`, the same values 4.1 printed; and
  `the file's entries at the resource group equal the direct read's: True`.
  **Failure looks like:** the row here but not in 4.1 -- the finding 4.1 describes (R4 must change);
  a value that differs -- the projection changes what it reads: record both.
  **Result:**

---

### 5. The rename (R9, G11)

Every write below is preceded by its `-WhatIf` plan. The group created as `oer-s65-rename-old` is
tracked by its id throughout (`<oer-s65-rename-group>`); it ends as `oer-s65-rename-direct`, and the
teardown finds it by that id.

- [ ] **5.1 A rename through the document: planned, applied, read back by the same id, the window measured with an immediate `-WhatIf` plan, and `Unchanged` once the new name resolves.**

  ```powershell
  $null = Get-S65RawGroup -Id $IdRename -Label '5.1-before'
  $Doc51 = New-S65Doc -Group ([ordered]@{ displayName = "$Prefix-rename-new"; previousDisplayName = "$Prefix-rename-old"; description = 's65 renamed' })
  Invoke-S65Check -Id '5.1a' -Json $Doc51 -Include Groups
  ```

  Only when the plan matches:

  ```powershell
  Invoke-S65Check -Id '5.1b' -Json $Doc51 -Include Groups -Apply
  $Renamed51 = Get-Date
  $null = Get-S65RawGroup -Id $IdRename -Label '5.1b-after'
  # THE WINDOW, MEASURED: the same document planned again at once -- -WhatIf, NEVER -Apply -- before
  # Graph's name lookup has been given any time. Read-only. It records what an immediate re-run would do.
  Invoke-S65Check -Id '5.1b-now' -Json $Doc51 -Include Groups
  $Row51 = @($S65Result | Where-Object { [string]$_.Item -eq "$Prefix-rename-new" }) | Select-Object -First 1
  $Verdict51 = if (-not $Row51) { 'no row' } elseif ($Row51.Action -eq 'Unchanged') { 'Unchanged' } elseif ([string]$Row51.Detail -match '^would rename') { 'rename it again' } elseif ([string]$Row51.Detail -match '^would create') { 'CREATE A NEW GROUP' } else { "other: $($Row51.Action) | $(Format-S65Text ([string]$Row51.Detail))" }
  "an immediate re-run, $([int]((Get-Date) - $Renamed51).TotalSeconds) s after the rename, would: $Verdict51"
  for ($Try = 1; $Try -le 6; $Try++) {
      $New = @((Get-S65RawStatus -Uri ("v1.0/groups?`$filter=" + [uri]::EscapeDataString("displayName eq '$Prefix-rename-new'") + '&$select=id')).Body['value'])
      $Old = @((Get-S65RawStatus -Uri ("v1.0/groups?`$filter=" + [uri]::EscapeDataString("displayName eq '$Prefix-rename-old'") + '&$select=id')).Body['value'])
      $Ready = ($New.Count -eq 1) -and ([string]$New[0]['id'] -eq $IdRename) -and ($Old.Count -eq 0)
      "try $Try, $([int]((Get-Date) - $Renamed51).TotalSeconds) s after the rename: new name listed $($New.Count), old name listed $($Old.Count); the name filter lists the new name under the same id and the old name nowhere: $Ready"
      if ($Ready) { break }
      Start-Sleep -Seconds 10
  }
  Invoke-S65Check -Id '5.1c' -Json $Doc51 -Include Groups
  ```

  Only when 5.1c is `Unchanged`:

  ```powershell
  Invoke-S65Check -Id '5.1d' -Json $Doc51 -Include Groups -Apply
  ```

  **Expect:** `5.1-before`: `displayName 'oer-s65-rename-old'`. 5.1a: `Valid = True`, no warning;
  `What if: Performing the operation "Rename group 'oer-s65-rename-old' to 'oer-s65-rename-new' and update group properties (Description)" on target "oer-s65-rename-new"`;
  one row, `[groups] oer-s65-rename-new | Skipped | would rename group 'oer-s65-rename-old' to 'oer-s65-rename-new'; would update group properties (Description)`.
  5.1b: no error; one row,
  `[groups] oer-s65-rename-new | Updated | renamed group 'oer-s65-rename-old' to 'oer-s65-rename-new'; updated group properties (Description)`;
  `5.1b-after`, read BY THE SAME ID: `displayName 'oer-s65-rename-new'; description 's65 renamed'`.
  Then 5.1b-now, the immediate plan: `Valid = True`, no error, and one line
  `an immediate re-run, <s> s after the rename, would: <verdict>` -- RECORD the verdict, the seconds
  and 5.1b-now's row and `What if:` line (redact). Each verdict is data, not a pass or fail:
  `Unchanged` (the name lookup had already caught up), `rename it again` (the old name still
  resolved to the group, the new one not yet -- a harmless second PATCH of the same name), or
  `CREATE A NEW GROUP` (neither name resolved -- the window the documentation warns about, in which
  an immediate real re-run would create a duplicate group). Then the wait: one
  `try <n>, <s> s after the rename: new name listed <a>, old name listed <b>; ...: <True|False>` line
  per try until `True` -- record every line: together they measure how long Graph's name filter
  trails the rename. 5.1c and 5.1d: one row each,
  `[groups] oer-s65-rename-new | Unchanged | group properties match` -- the previous name finds no
  group any more, so the entry is applied normally (G11).
  **Failure looks like:** 5.1a `would create group oer-s65-rename-new` -- the previous name did not
  resolve: stop, a real run would create a second group; 5.1b `Failed` -- record the message; the
  read-back with the old name or description -- the PATCH did not carry them; ANY write in 5.1b-now
  (a row `Created` or `Updated`) -- the plan was run with `-Apply`: record it, and look for a second
  `oer-s65-rename-new` group; the wait never printing `True` -- do NOT run 5.1c/5.1d until it does
  (with neither name resolving, the document would create a new group); 5.1c anything but `Unchanged`.
  **Result:**

- [ ] **5.2 A conflict: both names exist as different groups -- one `Failed` row, `GroupRenameConflict`, and both groups untouched.** The entry writes nothing by design; the plan runs first all the same.

  ```powershell
  $A0 = Get-S65RawGroup -Id $IdConflictA -Label '5.2-a-before'
  $B0 = Get-S65RawGroup -Id $IdConflictB -Label '5.2-b-before'
  $Doc52 = New-S65Doc -Group ([ordered]@{ displayName = "$Prefix-conflict-b"; previousDisplayName = "$Prefix-conflict-a" })
  Invoke-S65Check -Id '5.2a' -Json $Doc52 -Include Groups
  ```

  Only when the plan matches:

  ```powershell
  Invoke-S65Check -Id '5.2b' -Json $Doc52 -Include Groups -Apply
  $A1 = Get-S65RawGroup -Id $IdConflictA -Label '5.2-a-after'
  $B1 = Get-S65RawGroup -Id $IdConflictB -Label '5.2-b-after'
  "oer-s65-conflict-a unchanged (name, description, members): $(($A0.DisplayName -ceq $A1.DisplayName) -and ($A0.Description -ceq $A1.Description) -and ((@($A0.MemberIds) -join ',') -eq (@($A1.MemberIds) -join ',')))"
  "oer-s65-conflict-b unchanged (name, description, members): $(($B0.DisplayName -ceq $B1.DisplayName) -and ($B0.Description -ceq $B1.Description) -and ((@($B0.MemberIds) -join ',') -eq (@($B1.MemberIds) -join ',')))"
  ```

  **Expect:** 5.2a and 5.2b alike: `Valid = True`; no warning; no `What if:` line; ONE error,
  `ERROR [GroupRenameConflict,Invoke-OERStructure]: Group 'oer-s65-conflict-b' (<oer-s65-conflict-b>) and its previousDisplayName 'oer-s65-conflict-a' (<oer-s65-conflict-a>) are different groups. The document never merges two groups, so nothing was changed for this entry; rename or delete one of them, or remove previousDisplayName.`
  (the id is `GroupRenameConflict`, with the publishing command appended); exactly ONE row,
  `[groups] oer-s65-conflict-b | Failed | both 'oer-s65-conflict-b' and its previousDisplayName 'oer-s65-conflict-a' exist as different groups; the document never merges two groups, so nothing was changed -- rename or delete one of them, or remove previousDisplayName`.
  The groups keep their ids and names: `5.2-a-after` reads `displayName 'oer-s65-conflict-a'`,
  `5.2-b-after` `displayName 'oer-s65-conflict-b'`, each with its setup description; both
  `unchanged ...: True`.
  **Failure looks like:** more than one row, an `Updated` row, or either read-back changed -- the
  conflict wrote or merged: record it, it is a defect; an error id other than `GroupRenameConflict`.
  **Result:**

- [ ] **5.3 `Set-OERGroup -NewDisplayName` renames, and with no property it reports `NothingToUpdate` naming `-NewDisplayName`.**

  ```powershell
  Invoke-S65Call -Cmdlet Set-OERGroup -Splat @{ Group = "$Prefix-rename-new"; NewDisplayName = "$Prefix-rename-direct"; WhatIf = $true } -Label '5.3a plan'
  ```

  Only when the plan matches:

  ```powershell
  Invoke-S65Call -Cmdlet Set-OERGroup -Splat @{ Group = "$Prefix-rename-new"; NewDisplayName = "$Prefix-rename-direct"; Confirm = $false } -Label '5.3b rename'
  "returned: DisplayName '$($S65Out[0].DisplayName)'; the same group: $([string]::Equals([string]$S65Out[0].Id, $IdRename, [System.StringComparison]::OrdinalIgnoreCase))"
  $null = Get-S65RawGroup -Id $IdRename -Label '5.3b-after'
  Invoke-S65Call -Cmdlet Set-OERGroup -Splat @{ Group = "$Prefix-rename-direct" } -Label '5.3c no property'
  ```

  **Expect:** 5.3a: one request,
  `GET v1.0/groups?$filter=displayName eq 'oer-s65-rename-new'&$select=id,displayName`; the line
  `What if: Performing the operation "Update group properties" on target "<the id of oer-s65-rename-group>"`;
  no error; 0 objects. 5.3b: the same lookup, `PATCH v1.0/groups/<oer-s65-rename-group>` and
  `GET v1.0/groups/<oer-s65-rename-group>`; no error; one object;
  `returned: DisplayName 'oer-s65-rename-direct'; the same group: True`; `5.3b-after` reads
  `displayName 'oer-s65-rename-direct'; description 's65 renamed'`. 5.3c: NO request; one error,
  `ERROR [NothingToUpdate,Set-OERGroup]: No updatable property was supplied. Pass at least one of -NewDisplayName, -Description, -MailNickname, -MembershipRule, or -MembershipRuleProcessingState.`;
  0 objects.
  **Failure looks like:** 5.3a or 5.3b `GroupNotFound` -- Graph's name filter has not caught up with
  5.1 yet: wait a minute and run the plan again; a request in 5.3c -- the property check runs after
  the lookup; a read-back with another name.
  **Result:**

- [ ] **5.4 `Test-OERStructure` warns once when `previousDisplayName` equals `displayName`.** Offline; no request.

  ```powershell
  $Path54 = Join-Path $Raw '5.4.json'
  Set-Content -Path $Path54 -Value (New-S65Doc -Group ([ordered]@{ displayName = "$Prefix-rename-direct"; previousDisplayName = "$Prefix-RENAME-DIRECT" })) -Encoding utf8NoBOM
  $V54 = Test-OERStructure -Path $Path54
  "Valid $($V54.Valid); findings $(@($V54.Errors).Count)"
  @($V54.Errors) | ForEach-Object { "    [$($_.Severity)] $($_.Section) $($_.Path): $($_.Message)" }
  ```

  **Expect:** `Valid True; findings 1` and
  `[Warning] groups groups[0].previousDisplayName: 'previousDisplayName' at groups[0] equals displayName ignoring case; a case-only rename is not possible through the document -- use Set-OERGroup -NewDisplayName.`
  -- equal ignoring letter case, as Graph matches display names, so the document cannot express a
  case-only rename.
  **Failure looks like:** no finding, an Error, or `Valid False`.
  **Result:**

---

### 6. Manual (operator) -- a management-group eligibility through the full tree

**Run by Philip, in his own PowerShell 7 window, as himself -- never by the certificate identity, and
last before the Teardown (ruling R14).** The certificate identity cannot read a management group
(Owner on the test subscription only), so the management-group level of the eligibility walk, and the
call count of a full tree, are measured here. **The live-run session stops at this check and
continues with the Teardown afterwards**, once Philip has done both boxes.

- [ ] **6.1 Manual (operator) -- an eligible Reader assignment at a management group reaches `azurePimEligibility.json` at the management group's scope; the full-tree call count.**

  (a) Before signing in: in the Microsoft Entra admin center, ACTIVATE the PIM role that lets you
  read the management group you will use and create a role eligibility there (Owner or User Access
  Administrator at it or above). Then, in a NEW PowerShell 7 window of your own on the machine that
  holds the clone, paste the Setup variables block from `$Repo` down to `$StatePath` (the assignments
  only -- not the build lines), then this block:

  ```powershell
  Set-Location $Repo -ErrorAction Stop
  $Sep = [System.IO.Path]::PathSeparator
  $env:PSModulePath = (Resolve-Path ./output/module).Path + $Sep + (Resolve-Path ./output/RequiredModules).Path + $Sep + $env:PSModulePath
  Import-Module Omnicit.EntraRBAC -Force
  $ErrorActionPreference = 'Continue'
  $null = Connect-OER -TenantId $TenantId -Interactive -IncludeARM -ErrorAction Stop
  $Me = [string](Get-MgContext).Account
  $MeId = & (Get-Module Omnicit.EntraRBAC) { Get-OERSignedInObjectId }
  $MeRaw = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me?$select=id' -OutputType HashTable -SkipHttpErrorCheck
  # The identity check, BEFORE anything else: True/False only, never the ids, and a False stops here.
  $S65MeTenantOk = [string](Get-MgContext).TenantId -eq $TenantId
  $S65MePersonOk = ([string](Get-MgContext).ClientId -notin @($AppId, $NoPermAppId)) -and [bool]$Me -and -not $Me.StartsWith($Prefix)
  $S65MeIdOk     = [bool]$MeId -and [string]::Equals([string]$MeRaw['id'], [string]$MeId, [System.StringComparison]::OrdinalIgnoreCase)
  $S65MeArmOk    = [bool](& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.ArmToken })
  Write-Host "identity check: tenant is the test tenant: $S65MeTenantOk"
  Write-Host "identity check: a person's delegated sign-in, not a certificate identity: $S65MePersonOk"
  Write-Host "identity check: the token's object id is this user's (v1.0/me): $S65MeIdOk"
  Write-Host "the session holds an Azure Resource Manager token: $S65MeArmOk"
  if (-not ($S65MeTenantOk -and $S65MePersonOk -and $S65MeIdOk -and $S65MeArmOk)) { throw 'The identity check failed: nothing below may run.' }
  ```

  Then paste the Setup blocks "The helpers" and "The test principals" as they stand, and run 0.5's
  block (read-only; it reads the state file on this machine). Then list the management groups you
  can read, and pick one:

  ```powershell
  Get-OERManagementGroup | ForEach-Object { '{0} -- {1}' -f (Format-S65Text $_.Name), $_.DisplayName }
  $MgName = $TenantId   # the tenant root group; or the name of another management group listed above that you may read and assign at
  $MgScope = "/providers/Microsoft.Management/managementGroups/$MgName"
  ```

  (b) The plan, then -- only when it matches -- the eligibility (Reader, one day, for `oer-s65-user1`):

  ```powershell
  Invoke-S65Call -Cmdlet New-OEREligibleRoleAssignment -Splat @{ ManagementGroup = $MgName; Role = 'Reader'; User = $User1Upn; DurationDays = 1; WhatIf = $true } -Label '6.1b plan'
  ```

  ```powershell
  Invoke-S65Call -Cmdlet New-OEREligibleRoleAssignment -Splat @{ ManagementGroup = $MgName; Role = 'Reader'; User = $User1Upn; DurationDays = 1; Confirm = $false } -Label '6.1b create'
  Invoke-S65Call -Cmdlet Get-OEREligibleRoleAssignment -Splat @{ ManagementGroup = $MgName; AtScope = $true } -Label '6.1b read back' -Quiet
  "rows of oer-s65-user1 AT the management group: $(@($S65Out | Where-Object { [string]$_.PrincipalId -eq $IdUser1 -and [string]::Equals([string]$_.Scope, $MgScope, [System.StringComparison]::OrdinalIgnoreCase) }).Count)"
  ```

  (c) The full tree, as yourself:

  ```powershell
  $Out61 = Join-Path $Raw 'export-6.1'
  New-Item -ItemType Directory -Path $Out61 -Force | Out-Null
  Invoke-S65Call -Cmdlet Export-OERInventory -Splat @{ OutputPath = $Out61; Include = 'RoleAssignments' } -Label '6.1c the full tree' -Quiet
  $B61 = $S65Out | Where-Object { $_.PSObject.TypeNames -contains 'Omnicit.EntraRBAC.InventoryBundle' } | Select-Object -First 1
  $E61 = @(Get-Content -LiteralPath (Join-Path $B61.BundlePath 'azurePimEligibility.json') -Raw | ConvertFrom-Json)
  $Mg61 = @($E61 | Where-Object { [string]::Equals([string]$_.scope, $MgScope, [System.StringComparison]::OrdinalIgnoreCase) -and $_.principal -eq 'OER S65 User1' })
  "entries of oer-s65-user1 at the management group: $($Mg61.Count)"
  $Mg61 | ForEach-Object { '    scope {0}; role {1}; principalType {2}; memberType {3}; status {4}; endDateTime in {5} days' -f (Format-S65Text $_.scope), $_.role, $_.principalType, $_.memberType, $_.status, [math]::Round(([datetime]$_.endDateTime - [datetime]::UtcNow).TotalDays, 1) }
  "entries of oer-s65-user1 in all: $(@($E61 | Where-Object { $_.principal -eq 'OER S65 User1' }).Count) (the resource group one of section 4, and this one -- once each: deduplicated on the schedule id)"
  $Elig61 = @($S65Requests | Where-Object { $_ -match '^GET /.*/providers/Microsoft\.Authorization/roleEligibilitySchedules\?' })
  "roleEligibilitySchedules requests: $($Elig61.Count) (with atScope(): $(@($Elig61 | Where-Object { $_ -match 'atScope\(\)' }).Count); pages after the first: $(@($Elig61 | Where-Object { $_ -match 'skiptoken' }).Count)); ARM requests in all: $(@($S65Requests | Where-Object { $_ -match '^(GET|POST|PUT|PATCH|DELETE) /' }).Count)"
  "summary: ScopesEnumerated $($B61.ScopesEnumerated); ScopeCount $($B61.ScopeCount); SkippedScopes $(@($B61.SkippedScopes).Count); SkippedEligibilityScopes $(@($B61.SkippedEligibilityScopes).Count); AzurePimEligibility $($B61.AzurePimEligibility)"
  ```

  **Expect:** (a) all four lines `True`, no exception; 0.5's block then prints `ids read: 12 of 13`
  in this window -- there is no certificate-identity sign-in here, so `$IdCc` is empty -- and every
  other line as in 0.5. (b) the plan: the role and user lookups, one
  `What if:` line naming the eligible Reader role for `<oer-s65-user1's user principal name>` at the
  management group; the create: one `PUT .../roleEligibilityScheduleRequests/<name>?api-version=2020-10-01`,
  one object, no error; `rows of oer-s65-user1 AT the management group: 1`. (c) the export: no error
  (every scope readable as you); `entries of oer-s65-user1 at the management group: 1`, reading
  `scope /providers/Microsoft.Management/managementGroups/<MgName>; role Reader; principalType User; memberType Direct; status Provisioned; endDateTime in <about 1> days`
  (the tenant root group's name prints as `<TenantId>`); `entries of oer-s65-user1 in all: 2`; and
  `roleEligibilitySchedules requests:` equal to `ScopesEnumerated` plus the pages after the first,
  with one `atScope()` request per management group. Record every number: the full-tree call count,
  `ScopesEnumerated`, `ScopeCount`, the ARM total and the skipped counts (0 expected).
  **Failure looks like:** the entry missing at the management group while (b) read it back -- the
  management-group read with `atScope()` does not return an eligibility AT that management group:
  record it, it is a defect in R4; `entries ... in all: 3` or more -- the deduplication did not hold;
  a skipped scope -- you cannot read part of the tree: record which kind and continue.
  **Result:**

- [ ] **6.2 Manual (operator) -- clean up: the management-group eligibility removed and confirmed gone, you signed out, and your PIM role deactivated.** In your window.

  ```powershell
  Invoke-S65Call -Cmdlet Remove-OEREligibleRoleAssignment -Splat @{ ManagementGroup = $MgName; Role = 'Reader'; User = $User1Upn; WhatIf = $true } -Label '6.2 plan'
  ```

  Only when the plan matches:

  ```powershell
  Invoke-S65Call -Cmdlet Remove-OEREligibleRoleAssignment -Splat @{ ManagementGroup = $MgName; Role = 'Reader'; User = $User1Upn; Confirm = $false } -Label '6.2 remove'
  for ($Try = 1; $Try -le 6; $Try++) {
      $Left = @(Get-OEREligibleRoleAssignment -ManagementGroup $MgName -AtScope -ErrorAction SilentlyContinue | Where-Object { [string]$_.PrincipalId -eq $IdUser1 -and [string]::Equals([string]$_.Scope, $MgScope, [System.StringComparison]::OrdinalIgnoreCase) })
      "rows of oer-s65-user1 AT the management group: $($Left.Count)"
      if ($Left.Count -eq 0) { break }
      Start-Sleep -Seconds 10
  }
  Disconnect-OER
  ```

  Last, once you are signed out: end the PIM role activation you made in 6.1(a) (admin center, **My
  roles > Azure resources > Active assignments**, **Deactivate**; PIM may refuse a deactivation in its
  first minutes -- wait and try again). Close your window; the Teardown runs in the Claude window.

  **Expect:** the plan: one `What if:` line,
  `Performing the operation "Remove eligible Azure role assignment" on target "eligible role 'Reader' for principal '<oer-s65-user1's user principal name>' at scope '/providers/Microsoft.Management/managementGroups/<MgName>'"`.
  The removal: the warning `Removing eligible role 'Reader' for principal ... at scope ...`, one
  `PUT .../roleEligibilityScheduleRequests/<name>`, one object, no error; then
  `rows of oer-s65-user1 AT the management group: 0` (after a wait or two); `Disconnect-OER` run; the
  portal lists no active assignment of the role you activated (or only a standing one you had
  before) -- record which.
  **Failure looks like:** a row left after six tries -- remove it in the portal (PIM > Azure resources
  > the management group > Assignments > Eligible) and record it; the activation still listed after
  the deactivation -- deactivate it again, and do not leave it active.
  **Result:**

---

### Teardown

Back in the Claude window, after section 6. Sign in again first (`Connect-S65 -Arm`: a fresh
token, the identity lines once more, and the Azure session T.2 needs). The prerequisite script's
teardown does the work, in the order Setup describes: the Azure eligibility removed, the resource
group's Reader policy restored from its baseline and read again (or, with no baseline, only read),
the resource group deleted once that policy is restored or reads clean; then
every `oer-s65` directory assignment removed (five-minute rule), both directory policies restored
from the policy baseline rule by rule, missing baseline assignments re-created, the PIM-for-Groups
eligibility removed, `oer-s65-rag`'s member removed BEFORE the group is deleted, the groups deleted
whatever their current name, the users deleted after all of that, both roles compared with the
assignment baseline, and the sweep.

- [ ] **T.1 The prerequisite script's teardown -- its plan, then the run.**

  ```powershell
  Connect-S65 -Arm
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -SubscriptionId $SubId -RepoPath $Repo -Teardown -WhatIf
  ```

  Only once the plan matches:

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -SubscriptionId $SubId -RepoPath $Repo -Teardown -Unattended
  ```

  **Expect:** both runs, the lines Setup lists: `[oer-s65] Mode: RESTORE and REMOVE. ...`, the
  `Baselines and state in ...` line with `exists: True` four times, the Azure sign-in FIRST (both
  identity lines and the ARM line `True`, the tenant and subscription identified) and -- the real run
  only -- the `Unattended run: ...` line; then, in order:
  `Teardown: Azure eligibility of oer-s65 principals at resource group oer-s65-rg: 1` (a `What if:`
  line, then `Removed the eligible 'Reader' assignment of oer-s65-user1@<test domain> at resource group oer-s65-rg.`);
  `The 'Reader' policy listed at oer-s65-rg is the resource group's own: True`;
  `Teardown: the Reader policy of oer-s65-rg: rules differing from its baseline: 0` (nothing in this
  file writes it -- any rule listed there, record it) and `... restored: not attempted (WhatIf)` in
  the plan, `... restored: True` in the run; `Delete the resource group` as a `What if:` line, then
  `Deleted resource group oer-s65-rg.`. Then the Graph sign-in (both identity lines `True`),
  `Teardown: oer-s65 assignments on the two roles: 4` and one removal each -- Reports Reader eligible
  of `oer-s65-user1` and `oer-s65-rag`, Message Center Reader active of `oer-s65-rag` and
  `oer-s65-user1` (no `waiting ...` line: the active assignments are hours old; one appears only
  within five minutes of one being created); `Teardown: directory role 'Reports Reader': rules differing from the policy baseline: 1 (Expiration_EndUser_Assignment)`
  (the prerequisite script's `PT3H`) with ONE
  `What if: Performing the operation "Restore rule Expiration_EndUser_Assignment from the policy baseline (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Reports Reader'".`
  in the plan and `[oer-s65] Restored rule Expiration_EndUser_Assignment of 'Reports Reader'.` in the
  run; `Teardown: directory role 'Message Center Reader': rules differing from the policy baseline: 0`;
  per role `... restored: not attempted (WhatIf)` / `... restored: True`; per role
  `... baseline assignments missing and re-created: 0`;
  `Teardown: PIM-for-Groups eligibility of oer-s65 users in oer-s65-pim-elig: 1` and its removal;
  `Removed oer-s65-user2@<test domain> from oer-s65-rag.` BEFORE `Deleted group oer-s65-rag.`; the
  other seven groups -- `Deleted group oer-s65-rename-direct (created as oer-s65-rename-old).` and
  `Deleted group oer-s65-pim-dynamic.` among them -- no `left in place` line, and nothing
  `(found by the prefix sweep)`; the two users; per role
  `... direct assignments equal the assignment baseline: not checked (WhatIf)` in the plan and
  `... True` in the run; the sweep -- in the PLAN, which deletes nothing, one
  `[oer-s65] Sweep, still present: <user|group> '<name>' (<id>)` line for each of the two users and
  eight groups (`oer-s65-rename-direct` among them), each with its REAL id: redact every one; in the
  RUN `[oer-s65] Sweep: no user or group starting with 'oer-s65' is left.` (Graph's list can lag a
  moment behind the deletes -- a `Sweep, still present: ...` line in the run is then not a failure,
  T.2 reads again); the summary; `WhatIf: nothing was created, restored, removed or written.` in the
  plan; `[oer-s65] Done.` Nothing else is a target: no directory role other than the two, no Azure
  role other than Reader, nothing outside `oer-s65-rg` in Azure. Paste both outputs redacted per the
  rules at the top.
  **Failure looks like:** a target outside that list -- stop, do not run the real teardown; a
  `Refusing the teardown: ` line (a missing directory baseline, an untagged `oer-s65-rg`, a resource
  in it, an eligibility there of another principal) -- nothing was changed: record it and look before
  running again; `no baseline to restore it from` for the resource group's Reader policy -- setup
  stopped on residue (0.3): the policy is only read, and the resource group is deleted only when it
  reads `clean: True`; with `clean: False` the line `resource group oer-s65-rg is NOT deleted ... left
  for a human` and a final `Stopped ...: everything else is done, but: ...` line -- the operator resets
  the policy by hand, runs the teardown again, and records both runs; the resource group policy
  `restored: False` or a refused rule -- the script stops BEFORE it deletes the resource group: record
  Azure's message and look at the policy; a directory rule restore refused or
  `restored: False` -- the script stops before it deletes anything; a user deletion refused (the line
  `Teardown: user ... was NOT deleted: ...` and a final stop line) -- step 4 measured that app-only
  cannot delete a user Entra still treats as privileged: the operator deletes it by hand, and records
  it; a `Teardown: left in place: ...` line (a test group, or an assignment or PIM eligibility of one,
  whose current name no longer carries the prefix) and a final `Stopped ...: everything else is done,
  but: <n> object(s) were left in place ...` line with exit code 1 -- the sweep and T.2 cannot see
  such an object: the operator removes it by hand, or renames it back to an `oer-s65` name and runs
  the teardown again, and records it. Re-run the teardown after a fix (it only restores what differs
  and removes what is still there) and record both runs.
  **Result:**

- [ ] **T.2 Read everything back: both directory policies and both roles' assignments equal their baselines, the resource group is gone, no test object is left, and every write of this file named a test object.**

  ```powershell
  Show-S65BaselineDiff -Label 'T.2'
  Show-S65AssignmentBaselineDiff -Label 'T.2'
  $Rg = Invoke-S65ArmRead -Path "$RgScope`?api-version=2021-04-01"
  "resource group oer-s65-rg exists: $($Rg.Ok); answer: $(if ($Rg.Ok) { 'the resource group' } else { $Rg.Error })"
  if (Test-Path -LiteralPath $RgBaselinePath) {
      $BR = Get-Content -LiteralPath $RgBaselinePath -Raw | ConvertFrom-Json -AsHashtable
      $Pol = Invoke-S65ArmRead -Path "$([string]$BR['policyId'])?api-version=2020-10-01"
      if ($Pol.Ok) {
          $PolRules = @(ConvertTo-Json -InputObject @($Pol.Body.properties.rules) -Depth 50 | ConvertFrom-Json -AsHashtable)
          "the Reader policy of the deleted resource group, read by its baseline id (data): still readable; rules differing from its baseline: $(@(Get-S65RuleDiff -Live $PolRules -Baseline @($BR['rules'])).Count)"
      } else { "the Reader policy of the deleted resource group, read by its baseline id (data): $($Pol.Error)" }
  } else { 'no resource group Reader policy baseline: setup stopped on residue (0.3), and the teardown only read that policy' }
  $F = [uri]::EscapeDataString("startswith(userPrincipalName,'$Prefix')")
  "users starting with the prefix: $(@((Get-S65RawAll -Uri "v1.0/users?`$filter=$F&`$select=id").Rows).Count)"
  $F = [uri]::EscapeDataString("startswith(displayName,'$Prefix')")
  "groups starting with the prefix: $(@((Get-S65RawAll -Uri "v1.0/groups?`$filter=$F&`$select=id").Rows).Count)"
  $All = @(Import-Csv (Join-Path $Raw 'all-results.csv'))
  $All | Where-Object { $_.Action -in 'Created', 'Updated', 'Removed', 'Failed' } |
      ForEach-Object { '    {0} [{1}] {2} | {3} | {4}' -f $_.CheckId, $_.Section, (Format-S65Text $_.Item), $_.Action, (Format-S65Text $_.Detail) }
  "rows that changed something outside 5.1b and 5.3: $(@($All | Where-Object { $_.Action -in 'Created', 'Updated', 'Removed' -and $_.CheckId -ne '5.1b' }).Count)"
  "directory rows that are not Unchanged: $(@($All | Where-Object { $_.Section -like 'directoryRole*' -and $_.Action -ne 'Unchanged' }).Count)"
  ```

  **Expect:** `--- T.2: Reports Reader: the baseline names this policy: True; ...; differing from the baseline: 0`
  and the same for Message Center Reader; the assignment diff `only live []` and `only baseline []`
  for both roles and both kinds; `resource group oer-s65-rg exists: False; answer: ResourceGroupNotFound: ...`;
  the deleted resource group's Reader policy read by its baseline id -- record the answer (a
  `not found` answer, or still readable with `rules differing from its baseline: 0`; step 3 found
  that such a policy outlives its resource group, which is why the teardown restores it first) -- or,
  after a residue stop, `no resource group Reader policy baseline: ...`;
  `users starting with the prefix: 0` and `groups starting with the prefix: 0` (deleted users sit in
  Deleted items for 30 days, which is Entra ID's design); the listed rows, and no others:
  `5.1b [groups] oer-s65-rename-new | Updated | renamed group 'oer-s65-rename-old' to 'oer-s65-rename-new'; updated group properties (Description)`,
  `5.2a [groups] oer-s65-conflict-b | Failed | ...` and `5.2b [groups] oer-s65-conflict-b | Failed | ...`
  (`Set-OERGroup` in 5.3 writes no row); `rows that changed something outside 5.1b and 5.3: 0`;
  `directory rows that are not Unchanged: 0`.
  **Failure looks like:** a policy rule differing from its baseline, or an assignment that is not the
  baseline -- restore it before anything else (the script's `-Teardown` again, or by hand from the
  baseline files) and never delete the raw folder (T.3) while this is not clean: it holds the only
  record of the original state; the resource group still there; a count above 0; a row not listed
  above.
  **Result:**

- [ ] **T.3 Redact, then delete `raw/s65`.** Only once T.2 printed `differing from the baseline: 0` twice, the assignment diff was empty and the resource group was gone: the raw folder holds the baseline files, the only records of the original state. Move what the results above need from `docs/live-verification/raw/s65/` into this file, redacted per [README.md](README.md) and the rules at the top, then delete the folder.

  Object ids to `00000000-0000-0000-0000-0000000000NN` -- the role definition ids, every policy id
  and the certificate identity's service principal id included -- the tenant id to `<TenantId>`, the
  subscription id to `<SubId>`, a management group name to `<MgName>`, the organization and the
  domain to `<test tenant>` and `<test domain>`, user principal names (Philip's included) to
  `personN@example.com`; no credential, no bearer token, no application id, no thumbprint, and nothing
  copied out of the baseline or state files. That includes the output of every prerequisite-script
  run and of Philip's window.

  ```powershell
  Remove-Item -LiteralPath $Raw -Recurse -Force
  "raw/s65 exists after: $(Test-Path -LiteralPath $Raw)"
  git -C $Repo status --short docs/live-verification
  ```

  **Expect:** `raw/s65 exists after: False`; `git status` shows only this checklist as modified;
  nothing under `raw/` is ever staged. Before the commit, `tests/QA/dochygiene.tests.ps1` is green.
  **Failure looks like:** `raw/s65 exists after: True` -- a file in it is still open (an editor, or a
  second PowerShell window): close it and run the block again. `git status` listing anything under
  `docs/live-verification/raw/`, or any file besides this checklist -- unstage it and find out how it
  got there. A value a scan of this file still finds -- a GUID that is not a `00000000-...`
  placeholder, an address outside `example.com`, the tenant or subscription id, the organization or
  domain name -- means redaction is not finished: redact it before the commit, and if it was a
  credential, rotate it ([README.md](README.md), "Credentials").
  **Result:**
