# Live verification checklist -- eligible and active Microsoft Entra directory role assignments (feat/directory-role-assignments)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it. A check that could not run for a stated reason is marked
`[~]`, never `[x]`.

**This file grants and removes directory role assignments for real, and `-Prune` removes them for
real.** It names two directory roles and no other: **Reports Reader** and **Message Center Reader**,
two low-risk, read-only roles. Never Global Administrator, never Privileged Role Administrator as a
target, never any other role. Every principal it assigns was created by the prerequisite script for
this file and carries the prefix `oer-s64`. Four things outside that prefix are touched, and each
is restored by the teardown: the tenant-wide PIM policies of the two roles (2.5 and 3.1 write them;
the prerequisite script records their raw rules in a baseline file before its first write and its
teardown restores them from it); one ACTIVE, time-bound Message Center Reader assignment of the
certificate identity's own service principal, which the prerequisite script creates so section 4
can prove the engine never prunes the signed-in identity's own assignment; and that service
principal's membership of the role-assignable group `oer-s64-ccrag`, which the prerequisite script
adds so 4.5 can prove the engine never prunes a role the signed-in identity holds through a group --
ended by the teardown when it deletes the group. Section 6 is the one place a person's account
appears: Philip's own, in his own window, run by him.

**Every write is preceded by its `-WhatIf` plan.** Read the plan against the `Expect:` line first,
and only then run the line that writes. Every apply goes through the `Invoke-S64Check` helper
defined in Setup, which runs `Invoke-OERStructure -WhatIf` unless `-Apply` is passed. **Every
`-Prune` run** is preceded by its `-WhatIf` plan AND by a gate on that plan. In this window and in
Philip's, the gate is `Assert-S64PruneTarget`, which prints every row that would remove, removes or
reports `Extra`, by name, and returns `False` -- so the `-Prune` line behind it does not run --
unless the plan holds directoryRoleAssignments rows at all and every such target is a test object
carrying the prefix, in one of the two roles, and is not `oer-s64-ccrag` (the certificate identity
holds Message Center Reader through that group, so it is never a target); section 6's FIRST apply
alone allows exactly one more principal, Philip himself. Section 5's two `-Prune` runs are made by
the refused identity in a process of their own, and their gate is stricter: the real run is made
only when the plan holds nothing but `Failed` rows.

**Redact before you commit.** Raw console output belongs in `docs/live-verification/raw/s64/` --
the helpers write every document, every raw Graph read and a results log there, the prerequisite
script writes both baseline files there, and the folder is git-ignored. The baseline files hold
real object ids: never copy either, or any part of it, into a tracked file. What goes into a
`Result:` below is redacted first, per [README.md](README.md):

- **Object ids** become `00000000-0000-0000-0000-0000000000NN` in first-appearance order for THIS
  file -- the same id always gets the same placeholder, since several checks turn on two ids being
  the same or different. That includes the two role definition ids (a built-in role's template id
  is the same in every tenant, but it is version-4 shaped and is redacted like any other id), the
  certificate identity's service principal id, and every id in the prerequisite script's summary.
- **The tenant id** becomes `<TenantId>` wherever it appears, including the first half of a
  directory-role policy id, which becomes `DirectoryRole_<TenantId>_00000000-0000-0000-0000-0000000000NN`.
- **The organization display name** becomes `<test tenant>`, the **verified domain**
  `<test domain>`, the tenant alias `<Alias>`, and the local path of the clone `<Repo>`. A user
  principal name on the test domain becomes a `personN@example.com` address, and so does Philip's
  own user principal name in section 6 -- wherever PowerShell prints it itself, as in a `What if:`
  line. The helpers already print a test user as `oer-s64-user1@<test domain>` and Philip as
  `<Me>`; those may stay.
- **No credential, no bearer token, no application id and no certificate thumbprint** is ever
  pasted.

The test objects' display names and the two role names may stay. **Never render an error record**
(`Format-List` on `$Error[0]`, on a `-ErrorVariable`, or on a catch variable): a raw Graph failure's
record carries the bearer token. Every block below prints the error id and message only, and the
helpers name test objects, roles and policies instead of printing their ids wherever they can, so
most blocks need no redaction at all -- but PowerShell's own `What if:` lines print ids and user
principal names as they are, and are always redacted.

## What changed and why this needs a live tenant

The branch adds granting, reading and removing eligible and active assignments of Microsoft Entra
directory roles, as six cmdlets and an apply-document section with a prune pass. Commits are named
by SUBJECT, never by hash: the hashes change when the branch is rebased onto `main` before it
merges.

- **A. A role name matches in any letter case** ("fix: match a directory role name without regard
  to letter case"). `Resolve-OERDirectoryRoleDefinitionId` still sends the exact-case
  `displayName eq '...'` filter first; only when that finds nothing does it read the whole
  role-definition list (`$select=id,displayName`, paged with `-All`) and match without regard to
  letter case. A name typed in its exact case costs one request; another case costs two; no match
  is `$null` after two. This closes the finding of the step 3 checklist, check 1.2b, where Graph's
  filter was measured case-SENSITIVE. It changes `Get-` and `Set-OERDirectoryRoleManagementPolicy`
  too, which resolve `-Role` through the same helper.
- **B. Reading** ("feat: read eligible and active directory role assignments", "test: pin exact
  call counts in the directory role assignment read tests").
  `Get-OEREligibleDirectoryRoleAssignment` reads `v1.0/roleManagement/directory/roleEligibilitySchedules`
  and `Get-OERActiveDirectoryRoleAssignment` reads `roleAssignmentSchedules`, both at
  `directoryScopeId eq '/'` with `$expand=principal,roleDefinition`, paged. `-Role` (name or id,
  through `Resolve-OERDirectoryRoleInput`: `AmbiguousRoleName`, `RoleDefinitionReadFailed`,
  `RoleDefinitionNotFound`, each with no schedule request) and a principal filter narrow the read.
  Every row at `/` is returned -- direct and group-inherited (`MemberType`), and for Active both
  `Assigned` and `Activated` (`AssignmentType`) -- as `ScheduleId`, `RoleDefinitionId`, `RoleName`,
  `PrincipalId`, `PrincipalDisplayName`, `PrincipalType`, `DirectoryScopeId`, `MemberType`,
  (`AssignmentType`), `Status`, `StartDateTime`, `EndDateTime`, `ExpirationType`, `DurationDays`.
- **C. Granting and removing** ("feat: grant and remove eligible and active directory role
  assignments", "test: prove the error paths of the directory role assignment cmdlets", "fix:
  refuse a named principal alongside piped assignments on directory role removal"). The two New
  cmdlets POST a schedule request (`adminAssign`, or `adminUpdate` with `-Action`) at `/`, with a
  standard justification when none is given; the two Remove cmdlets POST `adminRemove` with no
  schedule, `ConfirmImpact = 'High'`, and a warning before the request. Before any write: a group,
  or a principal of unknown type (a raw `-PrincipalId`), is read at `v1.0/groups/{id}?$select=id,isAssignableToRole`
  -- `isAssignableToRole` false is `GroupNotRoleAssignable`, a `Request_ResourceNotFound` /
  `ResourceNotFound` answer means "not a group" and the request proceeds; a permanent request is
  checked against the role's PIM policy -- not allowed is `PermanentAssignmentNotAllowed`, with no
  write of any kind and no change to the policy. A named principal together with piped objects that
  carry their own `PrincipalId` is `AmbiguousPrincipal`.
- **D. Permissions, completion, format** ("test: require directory schedule permissions for the
  directory role assignment paths", "feat: tab-complete, format and list the directory role
  assignment cmdlets"). `Get-OERRequiredScope` names the schedule permissions per cmdlet; `-Role`
  tab-completes the built-in role names on all six.
- **E. The apply section** ("feat: decide which live directory role assignment a document entry can
  match", "feat: directoryRoleAssignments section in the apply document", "fix: report an unknown
  assignmentType and prove both directory role reads"). `directoryRoleAssignments[]` entries
  (`role`, `principal`, `assignmentType` `Eligible`/`Active`, optional `principalType`,
  `durationDays`, `permanent`, `justification`) run after `directoryRoleManagementPolicies` and
  before the Azure sections, and never ask for an Azure Resource Manager token. An entry is matched
  on role, principal and assignmentType against the rows `Select-OERManagedDirectoryRoleAssignment`
  keeps -- tenant scope, `MemberType` `Direct`, and for Active `AssignmentType` `Assigned` -- so an
  activation is never a declared active assignment. A missing one is `Created` (`adminAssign`), a
  changed window `Updated` (`adminUpdate`), a matching one `Unchanged`. Rows are labelled
  `<role> -> <principal> (<assignmentType>)`.
- **F. The prune pass** ("feat: record the signed-in identity's object id from the token's oid
  claim", "feat: prune directory role assignments only within declared role and type pairs", "test:
  prove a declared principal id matches its live assignment in any letter case", "fix: decide
  principalType alike in the prune pass and the item, and reword the unknown-identity reason"). The
  pass runs once, before the section's first item, keyed on RESOLVED role ids, and reads only the
  (role, assignmentType) pairs the document declares. For every undeclared direct candidate, in this
  order: an unresolved principal withholds its own pair and an unresolved role every pair of its
  kind (`Skipped`, `prune withheld: ...`); an unknown signed-in identity withholds everything; the
  signed-in identity's own assignment -- its object id taken from the Graph token's `oid` claim,
  never `/me` -- is `Skipped`; then the group guard (H): a group the signed-in identity is a member
  of is `Skipped`; otherwise `Extra`, or under `-Prune` a warning, a confirmation gate and the
  Remove cmdlet (`Removed`). A pair whose read fails is one `Failed` row, and nothing in it is
  removed or reported `Extra`.
- **G. Docs** ("docs: release note and rules for directory role assignments", "docs:
  live-verification checklist for directory role assignments").
- **H. Two fixes before the live run** ("fix: refuse an ambiguous service principal display name",
  "fix: never prune a directory role the signed-in identity holds through a group"). A service
  principal display name that more than one service principal carries is refused instead of
  resolved to one of them (`AmbiguousName`): the cmdlets report `AmbiguousApplicationName` or
  `AmbiguousPrincipalName`, and an apply entry naming one reports `Failed` and withholds the prune
  of its (role, assignmentType) pair. And the prune pass reads the signed-in identity's transitive
  group memberships ONCE per run (`POST v1.0/directoryObjects/{id}/getMemberGroups`,
  `securityEnabledOnly` false), and only when a candidate whose `PrincipalType` is Group or unknown
  reaches that guard. A direct assignment whose principal is a group the signed-in identity is a
  member of, directly or through nesting, is `Skipped`, with or without `-Prune`:
  `undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)`.
  A membership read that fails writes its error once and withholds every Group or unknown
  candidate
  (`prune withheld: the signed-in identity's group memberships could not be read, so ... : <message>`).
  The guard order is: an unresolved entry withholds, then an unknown signed-in identity, then the
  signed-in identity's own assignment, then the group guard, then `Extra` or `-Prune`. A group the
  signed-in identity is NOT a member of is pruned as before.

**Every unit test on this branch mocks the transport.** They prove the module's decisions given the
shapes the tests assume. They cannot prove the nine things this file is for:

1. That Microsoft Graph's `roleDefinitions` list, matched ignoring case, returns what the exact
   filter misses -- the step 3 finding closed (1.2).
2. That Graph v1.0 ACCEPTS the schedule request bodies the module builds -- `adminAssign`,
   `adminUpdate` and `adminRemove`, `afterDuration` and `noExpiration`, the standard justification,
   for a user and a role-assignable group, eligible and active (sections 2 and 3).
3. The shape of the schedules Graph returns -- expiration type, `memberType`, `assignmentType`,
   `directoryScopeId` -- which the converter and the managed-row filter read (2.1, 2.2, 2.7), and
   whether a member of a role-assignable group is listed with an inherited row at all (4.4).
4. Graph's real answers to the two pre-write reads: `isAssignableToRole` of a group created without
   the flag (2.3), and the error code of `groups/{id}` for a user's id (2.4).
5. That a document converges on Graph's real windows: the second run is `Unchanged`, a changed
   `durationDays` is re-issued with `adminUpdate` and the run after it is `Unchanged` (section 3).
6. That the prune pass removes exactly an undeclared direct assignment in a declared pair, leaves
   pairs the document does not declare alone, withholds on an unresolved entry, and never touches
   the signed-in identity's own assignment, identified from a real app-only token (section 4).
7. That a refused read reaches the operator as `Failed` rows and never as an empty pair (section 5).
8. That a real PIM activation is neither matched nor pruned (section 6).
9. That the group guard reads a real app-only identity's group membership from Graph and reports
   the row of the group through which that identity holds the role `Skipped`, while a group it is
   not a member of is still pruned (4.5).

## What this file does not check, and why

- **`AmbiguousRoleName`.** It needs two role definitions whose display names are the same, or
  differ only in letter case, which only a custom role can produce; creating one needs the portal
  and adds no module path. Unit-pinned in the `Resolve-OERDirectoryRoleDefinitionId`,
  `Resolve-OERDirectoryRoleInput` and cmdlet suites and in `AmbiguousName.Guard.Tests.ps1`.
- **The Azure lesson of step 3 has nothing to apply to here (ruling R17).** Step 3 learned that an
  Azure Resource Manager role management policy outlives its resource group and must be restored
  before the resource group is deleted. This file creates no Azure object at all -- no
  subscription object, no resource group, no Azure policy -- and every sign-in, the prerequisite
  script's included, is made WITHOUT `-IncludeARM`. The only tenant-wide objects it writes are the
  two directory-role policies, restored from the baseline file. 0.4 shows the session holds no
  Azure Resource Manager token, and 3.2 that a directory-only apply run did not acquire one.
- **The group guard's failed membership read, and deep nesting.** Privilege held through a group
  is now protected from `-Prune` (H), and 4.5 runs that guard against a real app-only identity's
  membership. Two of its paths are not run live. A membership read that fails -- every Group or
  unknown candidate withheld with `prune withheld: the signed-in identity's group memberships could
  not be read, ...` -- is unit-pinned and mutation-proved. And membership through nesting: a
  role-assignable group cannot contain a group, so the live path is one level deep.
- **An ambiguous service principal display name** (`AmbiguousApplicationName`,
  `AmbiguousPrincipalName`, and the `Failed` apply entry that withholds its pair). Two service
  principals with one display name would need a second app registration. Unit-pinned in the
  `Resolve-OERApplicationId` suite, in `AmbiguousName.Guard.Tests.ps1` and in the handler suites.
- **An unknown signed-in identity** (a token without an `oid` claim, or a session state built
  before the key existed). Every token Microsoft Entra ID issues carries `oid`, so it cannot be
  produced live. Unit-pinned in the `Get-OERTokenObjectId`, `Get-OERSignedInObjectId`,
  `Initialize-OERAuth` and handler suites.
- **A declared active entry for the very principal who activated.** Section 6 proves an activation
  is neither matched nor pruned in a declared Active pair; declaring Philip himself as Active would
  grant him a standing assignment of the role, so it is not run. Unit-pinned in the
  `Select-OERManagedDirectoryRoleAssignment` and handler suites.
- **That a role declared only for one assignmentType never has the other one READ.** 4.3 shows the
  effect (the undeclared pairs are untouched); the absence of the request itself is unit-pinned in
  the handler suite.
- **An administrative-unit-scoped assignment.** Both reads filter on `directoryScopeId eq '/'`,
  and this step creates none; the client-side scope guard is unit-pinned and mutation-proved.
- **Offline refusals.** `durationDays` with `permanent` true, `permanent` false without
  `durationDays`, and two entries for one role, principal and assignmentType are validator Errors
  (`Test-OERStructureSchema` suite); `AmbiguousSchedule`, `InvalidSchedule`, `InvalidPrincipalId`
  and `NoPrincipal` are local parameter checks (cmdlet suites). None needs a tenant.
- **A pre-write read that fails for another reason** (the role-assignable read or the permanent
  pre-check refused while the write itself would be allowed): written to Verbose and the request
  proceeds. No identity can be built that reads less than it may write here. Unit-pinned.
- **The New cmdlets' `AmbiguousPrincipal`.** Unit-pinned; the Remove variant is run in 2.6.
- **An activation that goes through approval, and PIM's notifications.** The platform's behaviour,
  not the module's; both roles' baseline policies require no approval.
- **`Get-OERInventory` and `Export-OERInventory`.** The section is apply-only in this step.

---

## Setup, once

**You need:**

- A **test tenant** -- never a customer tenant -- with Microsoft Entra ID P2 or ID Governance
  licensing (PIM for Microsoft Entra roles), its tenant id and one verified domain. No subscription
  is needed, and no Tenant Profile is needed either: the apply documents carry the alias, but the
  engine resolves no profile for these sections, and every sign-in names the tenant id itself. The
  tenant guard is the identity check against the tenant claim of the token, after every sign-in
  (`identity check: tenant is the test tenant: True`), and the prerequisite script's positive
  identification of the organization (its display name, a verified domain and its id). When a
  profile for the alias happens to exist on the machine, the prerequisite script still refuses one
  that names another tenant or a cloud other than the commercial one.
- The **dedicated certificate identity** `oer-live-cc` ([README.md](README.md), first paragraph):
  an app whose only credential is a non-exportable certificate in `Cert:\CurrentUser\My`, with the
  Microsoft Graph application permissions the operator's identity script grants. This file needs,
  from that grant list:
  `RoleEligibilitySchedule.ReadWrite.Directory` (the eligible schedule requests and reads);
  `RoleAssignmentSchedule.ReadWrite.Directory` (the active schedule requests and reads, and the
  prerequisite script's own Message Center Reader assignment);
  `RoleManagement.ReadWrite.Directory` (role definition lookups, the policy read of the permanent
  pre-check, and creating a role-assignable group in the prerequisite script);
  `RoleManagementPolicy.ReadWrite.Directory` (the rule PATCHes of 2.5 and 3.1 and the teardown's
  restore); `User.ReadWrite.All` and `Group.ReadWrite.All` (the prerequisite script's users and
  groups, `oer-s64-ccrag`'s membership, the user principal name and group name lookups, and the
  `isAssignableToRole` read); `Application.Read.All` (the service principal read of the identity
  check); `Directory.Read.All` (the group guard's read of the certificate identity's group
  memberships, `POST v1.0/directoryObjects/{id}/getMemberGroups`: Microsoft documents
  `Directory.Read.All` for that generic form, and `Get-OERRequiredScope` lists it for
  `Invoke-OERStructure`; 4.5's raw read sends the same request) and `Organization.Read.All` (the
  prerequisite script's tenant identification). Every sign-in below
  is app-only, as that identity -- never interactive, never a device code, never a cached context
  and never a person's account -- except section 6, which is Philip's. **The operator enables it
  for the run and disables it right after**; a sign-in answering "application is disabled" means it
  was not enabled: stop there. Its application permissions need no role activation.
- For section 5 only: the second app `oer-live-cc-noperm` -- the same certificate, no API
  permission and no role.
- For section 6 only: Philip's own account in the test tenant, holding or eligible for
  Privileged Role Administrator (it is activated BEFORE he signs in, never assigned by this file),
  and a member of no `oer-s64` group.
- The prerequisite script `Initialize-OerS64Prereq.ps1`. It is kept OUTSIDE this repository and is
  never committed; it signs in as the certificate identity, and never runs in CI.
- PowerShell 7 and a clone of this repository on this branch.

**Stop conditions -- for every check below.** Stop, record what happened and do not go around it,
when any of these is true: a command, a document or a plan names a principal without the prefix
`oer-s64` as a target, other than the certificate identity's own Message Center Reader assignment
(section 4 proves it is left alone) and, in section 6, Philip himself; any directory role other
than Reports Reader and Message Center Reader appears in a target; an assignment of either role
shows up for a principal the prerequisite script did not create (other than those two); a plan or
a result names `<oer-s64-ccrag>` as a prune TARGET -- `would remove`, `Removed` or `Extra` --
although it carries the prefix (the certificate identity holds Message Center Reader through that
group; its membership of `oer-s64-ccrag`, and an inherited Message Center Reader row it may show
through it, are expected); `Assert-S64PruneTarget` prints `STOP`; an identity line prints
`False`; or a request on the app path answers 401, 403 or `Authorization_RequestDenied` anywhere
except section 5, where a refusal is the point, and the prerequisite script's refused membership of
`oer-s64-ccrag`, which only marks 4.5 `[~]`. A refusal means the certificate identity lacks a
permission: name the missing permission, never finish the step with another sign-in.

**Variables, build and module path.** Paste into one PowerShell 7 window and keep that window for
the whole file.

```powershell
$Repo        = '<your-clone-of-Omnicit.EntraRBAC>'   # the clone whose origin is github.com/Omnicit/Omnicit.EntraRBAC
$Prereq      = '<path-to-Initialize-OerS64Prereq.ps1>'
$Alias       = '<your-test-tenant-alias>'
$OrgName     = '<your-test-tenant-display-name>'   # the organization display name, exactly as Graph reports it
$Domain      = '<your-verified-domain>'
$TenantId    = '<your-test-tenant-id>'
$AppId       = '<oer-live-cc-application-id>'
$NoPermAppId = '<oer-live-cc-noperm-application-id>'
$Thumbprint  = '<certificate-thumbprint>'   # in Cert:\CurrentUser\My; never exported, its key never read
$Prefix      = 'oer-s64'
$RoleRR      = 'Reports Reader'          # the ONLY two directory roles this file names
$RoleMCR     = 'Message Center Reader'
$Raw         = Join-Path $Repo 'docs/live-verification/raw/s64'
$BaselinePath           = Join-Path $Raw 'baseline-directory-policies.json'      # written by the prerequisite script
$AssignmentBaselinePath = Join-Path $Raw 'baseline-directory-assignments.json'   # written by the prerequisite script

Set-Location $Repo
git remote get-url origin
git branch --show-current
# Build in a process of its own. ModuleBuilder fills every Build-Module parameter build.yaml leaves
# unset from a variable of the same name in the calling session, so the $Prefix above would be
# written into the top of the built module, and importing it would run 'oer-s64' as a command.
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
window keeps its own sign-in. It signs in app-only as the certificate identity, WITHOUT
`-IncludeARM`, and after EVERY sign-in it checks the identity and prints it as True/False only --
`identity check: session app id is oer-live-cc: True` and
`identity check: tenant is the test tenant: True` -- and a `False` stops it before anything is
written. Before its first write it identifies the tenant positively: the organization's display
name must equal `-ExpectedTenantDisplayName` EXACTLY, `-UserDomain` must be one of its verified
domains, and `-TenantId` must be the organization's id. No Tenant Profile is needed; when one for
the alias happens to exist on the machine, it must name the same tenant, in the commercial cloud,
or the script refuses to run. Before each `Connect-MgGraph` it runs
`Disconnect-OER` and then `Disconnect-MgGraph` (`Connect-OER` leaves its raw access token in the
Graph SDK's process cache, which a later `Connect-MgGraph` would otherwise try to read as an MSAL
cache). A read of an object it has just created is retried on a 404. With `-Unattended` -- a run
with no operator at the keyboard -- it says that the confirmation question is not asked, since the
identity check and the tenant identification both passed. It is idempotent: a second run creates
nothing that exists and only fills in what is missing. It ends with a summary of names and REAL
object ids -- redact those before pasting (check 0.3). Read the `-WhatIf` plan first: every target
must carry the prefix `oer-s64`, apart from the two baseline files and the certificate identity's
own Message Center Reader assignment (the membership of `oer-s64-ccrag` is a target on that
prefixed group, naming the certificate identity's service principal as the member).

```powershell
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -WhatIf
pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -Unattended
```

What it creates, all named with the prefix: two DISABLED users `oer-s64-user1` and `oer-s64-user2`
on your domain (random passwords, never printed); the role-assignable security group `oer-s64-rag`
with `oer-s64-user2` as its only member; the plain security group `oer-s64-plain` (not
role-assignable); through `roleAssignmentScheduleRequests`, an ACTIVE, time-bound (`P2D`)
Message Center Reader assignment of the certificate identity's OWN service principal -- the one
assignment section 4 relies on to prove the own-assignment guard; the role-assignable security group
`oer-s64-ccrag`, created exactly as `oer-s64-rag` is, with the certificate identity's own service
principal as its ONLY member; and, only while that membership exists, an ACTIVE, time-bound
(`P2D`) Message Center Reader assignment of `oer-s64-ccrag`, requested exactly as the own assignment
is -- the certificate identity then holds Message Center Reader through the group, which 4.5 relies
on to prove the group guard. When Graph REFUSES the membership (any HTTP 4xx answer other than a
404 it retries), the script does not stop: it prints the refusal and that 4.5 cannot run as
written, requests no assignment for the group, and carries on with everything else. It creates no
subscription object, no resource group and nothing else in Azure.

What it records, once and before its first write, as two UTF-8 JSON files. `-BaselinePath` names
the POLICY baseline; its default is
`<RepoPath>/docs/live-verification/raw/s64/baseline-directory-policies.json`. The ASSIGNMENT
baseline is always written beside it, in the same folder, as `baseline-directory-assignments.json`.
This file never passes `-BaselinePath`, so `$BaselinePath` and `$AssignmentBaselinePath` in the
variables block are those two defaults. The helpers below read both files in exactly these shapes:

- **The policy baseline** is one object with one key, `roles`, an array of exactly two objects, one
  per role, in the order Reports Reader, Message Center Reader. Each has `displayName` (the role's
  display name, exactly `Reports Reader` or `Message Center Reader`), `roleDefinitionId` (the role
  definition id as Graph returns it), `policyId` (the Graph policy id, `DirectoryRole_<tenant id>_<guid>`)
  and `rules`: every rule object exactly as
  `GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<id>'&$expand=policy($expand=rules)`
  returns it under `value[0].policy.rules` -- unmodified, `id` and `@odata.type` included, nothing
  added or dropped. The helpers find a rule by its `id` and compare the rest of it.
- **The assignment baseline** is one object with one key, `roles`, an array of the same two
  objects' identity -- each with `displayName` and `roleDefinitionId` as above -- plus `eligible` and
  `active`. `eligible` holds every schedule object exactly as
  `GET v1.0/roleManagement/directory/roleEligibilitySchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<id>'`
  returns it under `value`, keeping only those whose `memberType` is `Direct`; `active` the same from
  `roleAssignmentSchedules`, keeping only `memberType` `Direct` and `assignmentType` `Assigned` (an
  activation cannot be re-created). Each row is the unmodified Graph object, so it carries at least
  `id`, `principalId`, `roleDefinitionId`, `directoryScopeId`, `memberType`, `scheduleInfo` and,
  in `active`, `assignmentType`; the helpers read `principalId`, the teardown also what it needs to
  re-create a missing row. A role with no such row has `"eligible": []` or `"active": []` -- an
  empty array, never `null` and never a missing key.

It refuses to run while either role holds a direct assignment of a principal it did not create
(other than the Message Center Reader assignment it creates itself), while a user
`oer-s64-nobody@<your-verified-domain>` exists (4.2 relies on that name resolving to nothing), and
while a group under one of its three names has the wrong shape -- `oer-s64-ccrag` included: it
must be a role-assignable security group whose only member is the certificate identity's service
principal, and one with any other member is refused, never repaired. Its `-Teardown` removes the
certificate identity's own Message Center Reader assignment and every `oer-s64` principal's
assignment on both roles (`oer-s64-ccrag`'s included), restores both policies from the policy
baseline rule by rule, re-creates any baseline assignment that is missing, deletes the test users
and groups (deleting `oer-s64-ccrag` ends the certificate identity's membership of it), and
verifies both roles' direct assignments equal the assignment baseline.

**What the script prints, and the checks read.** 0.2, 0.3 and T.2 compare its output with these
lines; `<...>` is a value, and every line starts `[oer-s64] ` (shown once here):

- Every run, first: `Mode: CREATE or complete. Tenant alias '<alias>', tenant <tenant id>, prefix 'oer-s64', expected organization '<organization>'.`
  (`Mode: RESTORE and REMOVE. ...` with `-Teardown`), then
  `Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Policy baseline: <path> (exists: <True|False>). Assignment baseline: <path> (exists: <True|False>).`
- After EVERY sign-in, two lines ending exactly
  `identity check: session app id is oer-live-cc: <True|False>` and
  `identity check: tenant is the test tenant: <True|False>`, each preceded by the sign-in's own
  label (for example `[oer-s64] Phase 1 identity check: ...`).
- Before the first write: `Identified the test tenant: organization '<organization>', tenant id <tenant id>, verified domain <domain>.`,
  and with `-Unattended`:
  `Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.`
  A refusal is one line starting `Refusing to run: ` (`Refusing the teardown: ` with `-Teardown`),
  and the script then writes nothing. No Tenant Profile is needed: before the sign-in it prints
  `No Tenant Profile '<alias>' on this machine; the sign-in names -TenantId.`, or, when one exists
  and names the same tenant in the commercial cloud,
  `Tenant Profile '<alias>' names the same tenant as -TenantId, in the commercial cloud: True`.
- Setup, the baselines: on a first run `No baseline files yet; this run captures both before its first write.`,
  `Wrote the policy baseline (<n> + <m> rules): <path>` and
  `Wrote the assignment baseline (Reports Reader: eligible <a>, active <b>; Message Center Reader: eligible <c>, active <d>): <path>`;
  on a later run `The baseline files exist; comparing the live state with them.` and, per role,
  `Directory role '<role>': rules differing from the policy baseline: <n>` (a setup run never
  restores a policy).
- Setup, the objects, in this order: `Created user <upn> (disabled).` (twice),
  `Created group oer-s64-rag (role-assignable).`, `Created group oer-s64-plain.`,
  `Created group oer-s64-ccrag (role-assignable).`, `Added <upn> to oer-s64-rag.`,
  `Requested the active Message Center Reader assignment of oer-live-cc (P2D): <request status>.`,
  `Added the service principal of oer-live-cc to oer-s64-ccrag.` and
  `Requested the active Message Center Reader assignment of oer-s64-ccrag (P2D): <request status>.`
  On a later run instead `Group <name> exists ...`, `<upn> is already a member of oer-s64-rag.`,
  `The active Message Center Reader assignment of oer-live-cc exists.`,
  `The service principal of oer-live-cc is already a member of oer-s64-ccrag.` and
  `The active Message Center Reader assignment of oer-s64-ccrag exists.` A retry after a 404
  prints a line containing `likely replication delay`. When Graph REFUSES the membership, the two
  lines `Adding the service principal of oer-live-cc to oer-s64-ccrag was refused: <Graph's answer>`
  (the transport's one-line message, every object id in it printed as `<id>`) and
  `Check 4.5 cannot run as written: mark it [~] with the line above.` take the place of the last
  two, no assignment is requested for the group, and the run goes on to its summary and `Done.`
- Teardown, in this order: `Teardown: oer-s64 assignments on the two roles: <n>`, one
  `Removed the <eligible|active> '<role>' assignment of <name>.` per removal (for `oer-s64-ccrag`:
  `Removed the active 'Message Center Reader' assignment of oer-s64-ccrag.`), and
  `Removed the active Message Center Reader assignment of oer-live-cc.`; per role
  `Teardown: directory role '<role>': rules differing from the policy baseline: <n>` (the rule ids
  in parentheses when `<n>` is not 0), one `Restored rule <rule id> of '<role>'.` per rule, and
  `Teardown: directory role '<role>': restored: <True|False|not attempted (WhatIf)>`; per role
  `Teardown: directory role '<role>': baseline assignments missing and re-created: <n>`; then
  `Deleted group <name>.` (`oer-s64-rag`, `oer-s64-plain`, `oer-s64-ccrag`) and
  `Deleted user <upn>.`; per role, last,
  `Teardown: directory role '<role>': direct assignments equal the assignment baseline: <True|False|not checked (WhatIf)>`,
  and `Sweep: no user or group starting with 'oer-s64' is left.` (or one
  `Sweep, still present: <user|group> '<name>' (<id>)` line each). Under `-WhatIf` every write is a
  PowerShell `What if:` line instead -- a rule restore's reads
  `"Restore rule <rule id> from the policy baseline (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role '<role>'"`.
- Last: a summary headed `Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:`
  -- a table of `Kind`, `Name`, `Id` with the kinds `user` (2), `group` (3), `group member` (2:
  `oer-s64-rag <- <upn of oer-s64-user2>` and `oer-s64-ccrag <- oer-live-cc`),
  `directory role (built-in, fixed)`, `directory role policy`, `own assignment`,
  `group assignment` (the Message Center Reader assignment of `oer-s64-ccrag`),
  `policy baseline (<written by this run|existed|not written (WhatIf)>)` and
  `assignment baseline (<written by this run|existed|not written (WhatIf)>)`, and
  `(none -- not created)` as the id of anything missing; under `-WhatIf`
  `WhatIf: nothing was created, restored, removed or written.`; and finally `Done.`

**Sign in.**

```powershell
Import-Module Omnicit.EntraRBAC -Force
$ErrorActionPreference = 'Continue'   # module code reads the GLOBAL preference; Stop would end a run at its first Failed row
# App-only, as the certificate identity, WITHOUT -IncludeARM: nothing in this file calls Azure
# Resource Manager. The certificate's private key is used, never read out.
$null = Connect-OER -TenantId $TenantId -ClientId $AppId -Certificate (Get-Item -LiteralPath "Cert:\CurrentUser\My\$Thumbprint") -ErrorAction Stop
# The identity check, BEFORE anything else: printed as True/False, never as the ids. The client and
# tenant ids come from the claims of the token Connect-OER obtained; the service principal's display
# name is read so a client id of some other app cannot pass.
$S64Context = Get-MgContext
try {
    $S64Sp = Invoke-MgGraphRequest -Method GET -OutputType PSObject -ErrorAction Stop -Uri "v1.0/servicePrincipals(appId='$AppId')?`$select=id,displayName"
} catch {
    Write-Host "--- reading the session's own service principal FAILED: $($PSItem.Exception.Message)"
    $global:Error.Clear()
}
$S64AppOk    = ([string]$S64Context.ClientId -eq $AppId) -and ([string]$S64Sp.displayName -ceq 'oer-live-cc')
$S64TenantOk = ([string]$S64Context.TenantId -eq $TenantId)
Write-Host "identity check: session app id is oer-live-cc: $S64AppOk"
Write-Host "identity check: tenant is the test tenant: $S64TenantOk"
if (-not ($S64AppOk -and $S64TenantOk)) { throw 'The identity check failed: nothing below may run.' }
```

**The helpers.** Paste this block as it stands. The raw reads use `Invoke-MgGraphRequest` on the
Microsoft Graph context `Connect-OER` set up: independent of the module's own read and write code.
Policy rules are compared exactly as the prerequisite script compares them: key order and list
order ignored, an absent property and a null one the same, and a `claimValue` of `''` the same as
null.

```powershell
function Test-S64Guid {
    param([AllowNull()][string]$Value)
    $Value -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
}

function Get-S64Name {
    # The name of a test object, role or identity for an object id, so output names objects instead
    # of printing ids. Filled from 0.5's ids (and, in section 6, $MeId); anything else is
    # 'not a test object'.
    param([AllowNull()][string]$Id)
    if (-not $Id) { return 'no id' }
    $Known = [ordered]@{
        "$Prefix-user1" = $IdUser1
        "$Prefix-user2" = $IdUser2
        "$Prefix-rag"   = $IdRag
        "$Prefix-plain" = $IdPlain
        "$Prefix-ccrag" = $IdCcRag
        'oer-live-cc'   = $IdCc
        $RoleRR         = $RoleIdRR
        $RoleMCR        = $RoleIdMCR
        'Me'            = $MeId
    }
    foreach ($K in $Known.GetEnumerator()) {
        if ($K.Value -and [string]::Equals([string]$K.Value, $Id, [System.StringComparison]::OrdinalIgnoreCase)) { return [string]$K.Key }
    }
    'not a test object'
}

function Format-S64Text {
    # Any text with the tenant's own values replaced: Philip's user principal name (section 6) by
    # <Me>, a directory-role policy id by its role, the tenant id by <TenantId>, every other GUID by
    # its Get-S64Name in angle brackets, and the test domain by <test domain>.
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return [string]$Text }
    $Out = $Text
    if ($Me) { $Out = $Out -ireplace [regex]::Escape($Me), '<Me>' }
    if ($PolicyIdRR) { $Out = $Out -ireplace [regex]::Escape($PolicyIdRR), "<policy of $RoleRR>" }
    if ($PolicyIdMCR) { $Out = $Out -ireplace [regex]::Escape($PolicyIdMCR), "<policy of $RoleMCR>" }
    if ($TenantId) { $Out = $Out -ireplace [regex]::Escape($TenantId), '<TenantId>' }
    $Out = $Out -replace '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', { '<' + (Get-S64Name $_.Value) + '>' }
    if ($Domain) { $Out = $Out -ireplace ('@' + [regex]::Escape($Domain)), '@<test domain>' }
    $Out
}

function Format-S64Request {
    # One transport verbose line as method, path and decoded query, with every id named
    # (Format-S64Text) and a paging token dropped. The transports write the method and the uri only
    # -- never a body or a header -- to that stream.
    param([string]$Message)
    if ($Message -cnotmatch '^\[Invoke-OER(Graph|Arm)Request\] (?<M>GET|POST|PATCH|PUT|DELETE) (?<U>.+)$') { return }
    $Method = $Matches['M']
    $Uri = [uri]::UnescapeDataString(($Matches['U'] -replace '^https://[^/]+/', ''))
    $Uri = $Uri -replace '(?i)(\$skiptoken=)[^&]+', '$1<token>'
    "$Method $(Format-S64Text $Uri)"
}

function Show-S64Error {
    # Prints the error id and message of each record the named cmdlet PUBLISHED -- never the record
    # itself: a raw transport record can carry the bearer token (README.md, "Credentials"). Records
    # collected from nested calls are counted, not shown.
    param([object[]]$Record, [Parameter(Mandatory)][string]$Cmdlet)
    $All = @($Record | Where-Object { $null -ne $_ })
    $Published = @($All | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains $Cmdlet })
    Write-Host "--- errors published by $($Cmdlet): $($Published.Count) (other records collected, not shown: $($All.Count - $Published.Count))"
    $Published | ForEach-Object { Write-Host "    ERROR [$($_.FullyQualifiedErrorId)]: $(Format-S64Text $_.Exception.Message)" }
}

function Invoke-S64Call {
    # Runs ONE module cmdlet with -Verbose captured, and prints what it did: every Microsoft Graph
    # request in the order sent (Format-S64Request), the cmdlet's own verbose lines, every warning,
    # the error id and message of every error it published (Show-S64Error), and how many objects it
    # returned -- kept in $S64Out. A What if: line is PowerShell's own and appears before this.
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
    $VerboseRecords = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
    $Requests = @($VerboseRecords | ForEach-Object { Format-S64Request -Message $_.Message } | Where-Object { $_ })
    $Own = @($VerboseRecords | Where-Object { $_.Message.StartsWith("[$Cmdlet]", [System.StringComparison]::Ordinal) })
    $Warnings = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $global:S64Out = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] -and $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-Host "=== $Label -- $Cmdlet"
    Write-Host "--- requests, in the order sent: $($Requests.Count)"
    $Requests | ForEach-Object { Write-Host "    $_" }
    Write-Host "--- the cmdlet's own verbose lines: $($Own.Count)"
    $Own | ForEach-Object { Write-Host "    $(Format-S64Text $_.Message)" }
    Write-Host "--- warnings: $($Warnings.Count)"
    $Warnings | ForEach-Object { Write-Host "    WARNING: $(Format-S64Text $_.Message)" }
    Show-S64Error -Record $CallError -Cmdlet $Cmdlet
    Write-Host "--- objects returned: $($S64Out.Count)"
}

function Show-S64Request {
    # The schedule request objects a New or Remove cmdlet returned (default: $S64Out), ids named.
    param([AllowEmptyCollection()][object[]]$Object = $S64Out)
    foreach ($O in @($Object | Where-Object { $null -ne $_ })) {
        Write-Host ("    request: Kind {0}; Action {1}; Status {2}; role <{3}>; principal <{4}>; scope '{5}'; expiration '{6}', duration '{7}', end set {8}; justification '{9}'" -f
            $O.Kind, $O.Action, $O.Status, (Get-S64Name $O.RoleDefinitionId), (Get-S64Name $O.PrincipalId), $O.DirectoryScopeId,
            $O.ExpirationType, $O.Duration, [bool]$O.EndDateTime, $O.Justification)
    }
}

function Format-S64Row {
    # One module assignment row (Get-OEREligible/ActiveDirectoryRoleAssignment output) on one line.
    param([Parameter(Mandatory)][object]$Row)
    $Type = if ($Row.PSObject.Properties['AssignmentType']) { " $($Row.AssignmentType)" } else { '' }
    "<{0}> ({1}){2}; MemberType {3}; scope '{4}'; status {5}; expiration '{6}'; DurationDays {7}; end {8}" -f
        (Get-S64Name $Row.PrincipalId), $Row.PrincipalType, $Type, $Row.MemberType, $Row.DirectoryScopeId, $Row.Status, $Row.ExpirationType,
        $(if ($null -eq $Row.DurationDays) { '(none)' } else { $Row.DurationDays }), $(if ($Row.EndDateTime) { 'set' } else { 'never' })
}

function Get-S64State {
    # Every row at tenant scope of the two roles, both kinds, read through the module with
    # -ErrorAction Stop (a refused read must never look like an empty role), each tagged with the
    # role it was read for (S64Role) and its Kind.
    foreach ($Role in @($RoleRR, $RoleMCR)) {
        foreach ($Kind in 'Eligible', 'Active') {
            $Read = if ($Kind -eq 'Eligible') { @(Get-OEREligibleDirectoryRoleAssignment -Role $Role -ErrorAction Stop) }
                    else { @(Get-OERActiveDirectoryRoleAssignment -Role $Role -ErrorAction Stop) }
            foreach ($R in $Read) {
                $R | Add-Member -NotePropertyName S64Role -NotePropertyValue $Role -Force
                $R | Add-Member -NotePropertyName Kind -NotePropertyValue $Kind -Force
                $R
            }
        }
    }
}

function Show-S64State {
    # The rows of Get-S64State per role and kind, one line each, ids named. -Role narrows the roles.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$State, [Parameter(Mandatory)][string]$Label, [string[]]$Role = @($RoleRR, $RoleMCR))
    foreach ($R in $Role) {
        foreach ($Kind in 'Eligible', 'Active') {
            $Rows = @($State | Where-Object { $_.S64Role -eq $R -and $_.Kind -eq $Kind } | Sort-Object { Get-S64Name $_.PrincipalId }, MemberType)
            Write-Host "--- $($Label): $R, $($Kind): $($Rows.Count) row(s)"
            foreach ($X in $Rows) { Write-Host "    $(Format-S64Row $X)" }
        }
    }
}

function Get-S64StateKey {
    # Every row as one line of the fields a write would change, sorted -- for "nothing changed".
    param([AllowEmptyCollection()][object[]]$State)
    (@($State | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $_.S64Role, $_.Kind, $_.ScheduleId, $_.PrincipalId, $_.MemberType, $_.AssignmentType, $_.StartDateTime, $_.EndDateTime }) | Sort-Object) -join "`n"
}

function Show-S64AssignmentBaselineDiff {
    # The DIRECT rows of both roles against the assignment baseline file the prerequisite script
    # wrote, per role and kind, by principal: who only the live read has, and who only the baseline
    # has -- named, never printed as ids, and sorted by name.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$State)
    $Base = Get-Content -LiteralPath $AssignmentBaselinePath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($Entry in @($Base['roles'] | Where-Object { $null -ne $_ })) {
        $Name = [string]$Entry['displayName']
        foreach ($Kind in 'Eligible', 'Active') {
            $BaseIds = @($Entry[$Kind.ToLowerInvariant()] | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_['principalId']).ToLowerInvariant() } | Sort-Object -Unique)
            $LiveIds = @($State | Where-Object { $_.Kind -eq $Kind -and [string]$_.RoleDefinitionId -eq [string]$Entry['roleDefinitionId'] -and $_.MemberType -eq 'Direct' } |
                    ForEach-Object { ([string]$_.PrincipalId).ToLowerInvariant() } | Sort-Object -Unique)
            $OnlyLive = @($LiveIds | Where-Object { $BaseIds -notcontains $_ } | ForEach-Object { Get-S64Name $_ } | Sort-Object)
            $OnlyBase = @($BaseIds | Where-Object { $LiveIds -notcontains $_ } | ForEach-Object { Get-S64Name $_ } | Sort-Object)
            Write-Host ('--- {0}: {1}, {2}: direct principals live {3}, baseline {4}; only live [{5}]; only baseline [{6}]' -f
                $Label, $Name, $Kind, $LiveIds.Count, $BaseIds.Count, ($OnlyLive -join ', '), ($OnlyBase -join ', '))
        }
    }
}

function Get-S64RawUser {
    # One user by user principal name, straight from Microsoft Graph v1.0: its id and whether the
    # account is enabled. A failure prints its message only and clears $Error: a raw
    # Invoke-MgGraphRequest error record carries the bearer token.
    param([Parameter(Mandatory)][string]$Upn)
    $F = [uri]::EscapeDataString("userPrincipalName eq '$Upn'")
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/users?`$filter=$F&`$select=id,accountEnabled"
    } catch {
        Write-Host "--- raw user read FAILED: $(Format-S64Text $PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    $U = @($R['value'] | Where-Object { $null -ne $_ })
    if ($U.Count -ne 1) { Write-Host "--- raw user read: $($U.Count) users match '$(Format-S64Text $Upn)', not one"; return }
    [PSCustomObject]@{ Id = [string]$U[0]['id']; AccountEnabled = [bool]$U[0]['accountEnabled'] }
}

function Get-S64RawGroup {
    # One group by display name, straight from Microsoft Graph v1.0: its id, isAssignableToRole as
    # Graph returns it (null kept as null), securityEnabled, and its members' ids.
    param([Parameter(Mandatory)][string]$Name)
    $F = [uri]::EscapeDataString("displayName eq '$Name'")
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/groups?`$filter=$F&`$select=id,isAssignableToRole,securityEnabled"
        $G = @($R['value'] | Where-Object { $null -ne $_ })
        if ($G.Count -ne 1) { Write-Host "--- raw group read: $($G.Count) groups named '$Name', not one"; return }
        $M = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/groups/$($G[0]['id'])/members?`$select=id"
    } catch {
        Write-Host "--- raw group read FAILED: $(Format-S64Text $PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    [PSCustomObject]@{
        Id                 = [string]$G[0]['id']
        IsAssignableToRole = $G[0]['isAssignableToRole']
        SecurityEnabled    = $G[0]['securityEnabled']
        MemberIds          = @($M['value'] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_['id'] })
    }
}

function Get-S64RawRoleDefinitionId {
    # A built-in directory role's definition id, read at run time straight from Microsoft Graph v1.0
    # -- never typed: exactly one built-in role definition with exactly this display name, or nothing.
    param([Parameter(Mandatory)][string]$Name)
    $F = [uri]::EscapeDataString("displayName eq '$Name'")
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=$F&`$select=id,displayName,isBuiltIn"
    } catch {
        Write-Host "--- raw role definition read FAILED: $(Format-S64Text $PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    $D = @($R['value'] | Where-Object { $null -ne $_ -and [string]$_['displayName'] -ceq $Name })
    if ($D.Count -ne 1 -or -not [bool]$D[0]['isBuiltIn']) { Write-Host "--- '$Name': $($D.Count) role definition(s) with exactly that name, or not built-in"; return }
    [string]$D[0]['id']
}

function Get-S64RawStatus {
    # One GET straight from Microsoft Graph v1.0, returning the HTTP status, Graph's error code and
    # the body. -SkipHttpErrorCheck: a refusal is read as data and never thrown, so no error record
    # -- which can carry the bearer token -- is ever created.
    param([Parameter(Mandatory)][string]$Uri)
    $Body = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType HashTable -SkipHttpErrorCheck -StatusCodeVariable 'S64Status'
    $Code = if ($Body -is [System.Collections.IDictionary] -and $Body['error']) { [string]$Body['error']['code'] } else { '' }
    [PSCustomObject]@{ Status = [int]$S64Status; ErrorCode = $Code; Body = $Body }
}

function Get-S64WindowDays {
    # The window of one raw schedule's scheduleInfo in days (two decimals): end minus start, or the
    # ISO duration when Graph returned no end. '' for a schedule that never ends.
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

function Get-S64RawSchedule {
    # The schedules of one role and principal straight from Microsoft Graph v1.0, outside the module
    # -- the same resource the Get cmdlets read. -Want waits (6 x 10 s) until exactly that many rows
    # are listed, and -WantWindowDays until every row's window rounds to that many days: Graph lists a
    # just-accepted request a moment later. -DirectOnly keeps only the rows whose memberType is Direct:
    # a member of a role-assignable group may be listed with an inherited row too (4.4), which -Want
    # must not count. Saved as <Label>.json; prints the fields the checks compare.
    param(
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Kind,
        [Parameter(Mandatory)][string]$RoleDefinitionId,
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Label,
        [int]$Want = -1,
        [int]$WantWindowDays = 0,
        [switch]$DirectOnly
    )
    $Resource = if ($Kind -eq 'Eligible') { 'roleEligibilitySchedules' } else { 'roleAssignmentSchedules' }
    $F = [uri]::EscapeDataString("roleDefinitionId eq '$RoleDefinitionId' and principalId eq '$PrincipalId'")
    $Rows = @()
    for ($Try = 1; $Try -le 6; $Try++) {
        try {
            $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop -Uri "v1.0/roleManagement/directory/$Resource`?`$filter=$F"
        } catch {
            Write-Host "--- $($Label): raw read FAILED: $(Format-S64Text $PSItem.Exception.Message)"
            $global:Error.Clear()
            return
        }
        $Rows = @($R['value'] | Where-Object { $null -ne $_ -and (-not $DirectOnly -or [string]$_['memberType'] -eq 'Direct') })
        $WindowOk = ($WantWindowDays -le 0) -or (@($Rows | Where-Object { [math]::Round([double](Get-S64WindowDays -Info $_['scheduleInfo'])) -eq $WantWindowDays }).Count -eq $Rows.Count)
        if ($Want -lt 0 -or ($Rows.Count -eq $Want -and $WindowOk)) { break }
        Write-Host "    ($($Label): $($Rows.Count) row(s) listed, waiting -- attempt $Try of 6)"
        Start-Sleep -Seconds 10
    }
    ConvertTo-Json -InputObject $Rows -Depth 20 | Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    Write-Host "--- $($Label): raw $Resource of <$(Get-S64Name $RoleDefinitionId)> for <$(Get-S64Name $PrincipalId)>$(if ($DirectOnly) { ', memberType Direct only' }): $($Rows.Count) row(s)"
    foreach ($Row in $Rows) {
        $Info = $Row['scheduleInfo']
        $Exp = if ($Info) { $Info['expiration'] } else { $null }
        $Window = Get-S64WindowDays -Info $Info
        Write-Host ("    memberType {0}; directoryScopeId '{1}'; assignmentType {2}; status {3}; expiration type {4}, endDateTime set {5}, duration {6}; window {7}" -f
            $Row['memberType'], $Row['directoryScopeId'], $(if ($Row.ContainsKey('assignmentType')) { $Row['assignmentType'] } else { '(none)' }), $Row['status'],
            $(if ($Exp) { $Exp['type'] } else { '(none)' }), [bool]($Exp -and $Exp['endDateTime']), $(if ($Exp -and $Exp['duration']) { $Exp['duration'] } else { '(none)' }),
            $(if ($Window -eq '') { 'never ends' } else { "$Window day(s)" }))
    }
    $Rows   # enumerated: wrap the call in @() to keep the rows as an array
}

function Get-S64RawPolicy {
    # The policy of one directory role straight from Microsoft Graph v1.0, through the same query the
    # prerequisite script used for the baseline file (the assignment at scope '/', the policy and its
    # rules expanded). Saved to the raw folder as <Label>.json.
    param([Parameter(Mandatory)][string]$RoleDefinitionId, [Parameter(Mandatory)][string]$Label)
    $F = [uri]::EscapeDataString("scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '$RoleDefinitionId'")
    try {
        $R = Invoke-MgGraphRequest -Method GET -OutputType HashTable -ErrorAction Stop `
            -Uri "v1.0/policies/roleManagementPolicyAssignments?`$filter=$F&`$expand=policy(`$expand=rules)"
    } catch {
        Write-Host "--- $($Label): raw read FAILED: $(Format-S64Text $PSItem.Exception.Message)"
        $global:Error.Clear()
        return
    }
    $Assignments = @($R['value'] | Where-Object { $null -ne $_ })
    if ($Assignments.Count -ne 1) { Write-Host "--- $($Label): $($Assignments.Count) policy assignment(s) for this role, not one"; return }
    $Rules = @($Assignments[0]['policy']['rules'] | Where-Object { $null -ne $_ })
    ConvertTo-Json -InputObject $Rules -Depth 30 | Set-Content -Path (Join-Path $Raw "$Label.json") -Encoding utf8NoBOM
    [PSCustomObject]@{ PolicyId = [string]$Assignments[0]['policyId']; Rules = $Rules }
}

function ConvertTo-S64Canonical {
    # The same comparison the prerequisite script makes: every dictionary's keys sorted and every list
    # sorted by its own canonical JSON; '@odata.context' dropped; a null property dropped (null and
    # absent are the same); a claimValue of '' read as null.
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $Out = [ordered]@{}
        foreach ($Key in @($Value.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ -notmatch '@odata\.context$' } | Sort-Object -CaseSensitive)) {
            $Item = $Value[$Key]
            if ($Key -ceq 'claimValue' -and $Item -is [string] -and $Item.Length -eq 0) { $Item = $null }
            if ($null -eq $Item) { continue }
            $Out[$Key] = ConvertTo-S64Canonical -Value $Item
        }
        return $Out
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $Out = [ordered]@{}
        foreach ($Key in @($Value.PSObject.Properties.Name | Where-Object { $_ -notmatch '@odata\.context$' } | Sort-Object -CaseSensitive)) {
            $Item = $Value.$Key
            if ($Key -ceq 'claimValue' -and $Item -is [string] -and $Item.Length -eq 0) { $Item = $null }
            if ($null -eq $Item) { continue }
            $Out[$Key] = ConvertTo-S64Canonical -Value $Item
        }
        return $Out
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Value) { $Items.Add((ConvertTo-S64Canonical -Value $Item)) }
        $Sorted = @($Items | Sort-Object -Property { ConvertTo-Json -InputObject $_ -Depth 50 -Compress })
        return , $Sorted
    }
    return $Value
}

function Get-S64RuleDiff {
    # The id of every rule whose content differs between two rule sets, in the second set's order,
    # then any rule only the first set has.
    param([object[]]$Live, [object[]]$Baseline)
    $Text = { param($Rule) ConvertTo-Json -InputObject (ConvertTo-S64Canonical -Value $Rule) -Depth 50 -Compress }
    $LiveById = @{}
    foreach ($Rule in @($Live | Where-Object { $null -ne $_ })) { $LiveById[[string]$Rule['id']] = & $Text $Rule }
    $BaseById = [ordered]@{}
    foreach ($Rule in @($Baseline | Where-Object { $null -ne $_ })) { $BaseById[[string]$Rule['id']] = & $Text $Rule }
    $Ids = @(@($BaseById.Keys) + @($LiveById.Keys | Where-Object { -not $BaseById.Contains($_) }))
    foreach ($Id in $Ids) { if ([string]$LiveById[$Id] -cne [string]$BaseById[$Id]) { $Id } }
}

function Show-S64BaselineDiff {
    # Every rule of the two directory-role policies that differs from the baseline file, read raw
    # (Get-S64RawPolicy) and compared as the prerequisite script compares.
    param([Parameter(Mandatory)][string]$Label)
    $Base = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($Entry in @($Base['roles'] | Where-Object { $null -ne $_ })) {
        $Name = [string]$Entry['displayName']
        $Live = Get-S64RawPolicy -RoleDefinitionId ([string]$Entry['roleDefinitionId']) -Label ('{0}-{1}-policy-raw' -f $Label, ($Name -replace ' ', '-'))
        if (-not $Live) { continue }
        $Diff = @(Get-S64RuleDiff -Live $Live.Rules -Baseline @($Entry['rules']))
        Write-Host ('--- {0}: {1}: the baseline names this policy: {2}; rules live {3}, baseline {4}; differing from the baseline: {5}{6}' -f
            $Label, $Name, ([string]$Entry['policyId'] -eq $Live.PolicyId), @($Live.Rules).Count, @($Entry['rules']).Count, $Diff.Count,
            $(if ($Diff.Count) { ' (' + ($Diff -join ', ') + ')' } else { '' }))
    }
}

function Show-S64Policy {
    # One module directory-role policy object: whose it is and its two permanent settings.
    param([AllowNull()][object]$Policy, [string]$Label = 'policy')
    if ($null -eq $Policy) { Write-Host "--- $($Label): no object"; return }
    $Changed = if ($Policy.PSObject.Properties['ChangedRuleIds']) { '; ChangedRuleIds [' + (@($Policy.ChangedRuleIds) -join ', ') + ']' } else { '' }
    Write-Host ("--- {0}: {1}; RoleName '{2}'; eligible: permanent allowed {3}, {4}; active: permanent allowed {5}, {6}{7}" -f
        $Label, (Format-S64Text $Policy.PolicyId), $Policy.RoleName, $Policy.AllowPermanentEligibility, $Policy.EligibleDuration,
        $Policy.AllowPermanentActiveAssignment, $Policy.ActiveDuration, $Changed)
}

function Assert-S64PruneTarget {
    # The gate in front of every real -Prune run. Prints every directoryRoleAssignments row that
    # removes, would remove or reports Extra, by name, and returns $true only when the plan holds
    # directoryRoleAssignments rows at all (no row means the plan did not run -- an invalid document,
    # or a stale result -- and proves nothing) and every such target names a test object carrying the
    # prefix, in one of the two roles -- never oer-s64-ccrag, through which the certificate identity
    # holds Message Center Reader (a stop condition, although it carries the prefix).
    # -AllowPrincipalId adds exactly one more principal (section 6's first apply only: Philip's own
    # object id). A candidate row's Item is the engine's '<role> -> <principal id> (<assignmentType>)';
    # anything else counts as not allowed.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Result, [Parameter(Mandatory)][string]$Label, [string]$AllowPrincipalId)
    $SectionRows = @($Result | Where-Object { $null -ne $_ -and $_.Section -eq 'directoryRoleAssignments' })
    if ($SectionRows.Count -eq 0) {
        Write-Host "--- $($Label): the plan holds no directoryRoleAssignments row at all"
        Write-Host '--- STOP: there is no plan to check. The -Prune line does not run.'
        return $false
    }
    $Targets = @($Result | Where-Object {
            $_.Section -eq 'directoryRoleAssignments' -and
            ($_.Action -in 'Removed', 'Extra' -or ($_.Action -eq 'Skipped' -and ([string]$_.Detail).StartsWith('would remove', [System.StringComparison]::Ordinal)))
        })
    $Ok = $true
    foreach ($T in $Targets) {
        $Good = $false
        if ([string]$T.Item -match '^(?<Role>.+) -> (?<P>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}) \((Eligible|Active)\)$') {
            $Role = $Matches['Role']; $P = $Matches['P']
            if (Test-S64Guid $Role) { $Role = Get-S64Name $Role }
            $Who = Get-S64Name $P
            $Good = ($Role -in @($RoleRR, $RoleMCR)) -and ($Who -ne "$Prefix-ccrag") -and
                ($Who.StartsWith("$Prefix-", [System.StringComparison]::Ordinal) -or ($AllowPrincipalId -and [string]::Equals($P, $AllowPrincipalId, [System.StringComparison]::OrdinalIgnoreCase)))
        }
        Write-Host ('    target: {0} -- {1}; allowed: {2}' -f (Format-S64Text $T.Item), $T.Action, $Good)
        if (-not $Good) { $Ok = $false }
    }
    Write-Host "--- $($Label): prune targets (would remove, removed or Extra): $($Targets.Count); every one allowed: $Ok"
    if (-not $Ok) { Write-Host '--- STOP: a target is not a prefixed test object in one of the two roles, or is oer-s64-ccrag. The -Prune line does not run.' }
    $Ok
}

function New-S64Entry {
    # One directoryRoleAssignments[] entry. -Days makes it time-bound, -Permanent writes permanent
    # true; with neither the entry is permanent all the same (an entry without durationDays is).
    param([Parameter(Mandatory)][string]$Role, [Parameter(Mandatory)][string]$Principal, [string]$Type,
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Kind, [int]$Days, [switch]$Permanent)
    $E = [ordered]@{ role = $Role; principal = $Principal }
    if ($Type) { $E.principalType = $Type }
    $E.assignmentType = $Kind
    if ($Days) { $E.durationDays = $Days }
    if ($Permanent) { $E.permanent = $true }
    $E
}

function New-S64Doc {
    # One apply document as JSON, under the test tenant's alias.
    param([object[]]$Policy, [object[]]$Assignment)
    $Doc = [ordered]@{ version = '1.0'; tenantAlias = $Alias }
    if ($Policy) { $Doc.directoryRoleManagementPolicies = @($Policy) }
    if ($Assignment) { $Doc.directoryRoleAssignments = @($Assignment) }
    $Doc | ConvertTo-Json -Depth 10
}

function Invoke-S64Check {
    # Writes the document to the raw folder, prints it (ids and domain named), validates it offline,
    # then runs Invoke-OERStructure on it -- under -WhatIf unless -Apply is given, with -Prune only
    # when asked. Warnings keep their order (3>&1); errors print as id and message only; every row
    # prints on one line, ids named, and is appended to all-results.csv for T.3. The rows stay in
    # $S64Result, which is emptied first: a run that stops early (an invalid document) must never
    # leave the previous run's rows for Assert-S64PruneTarget to approve.
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Json,
        [string[]]$Include = @('DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments'),
        [switch]$Apply,
        [switch]$Prune
    )
    $global:S64Result = @()
    $Path = Join-Path $Raw "$Id.json"
    Set-Content -Path $Path -Value $Json -Encoding utf8NoBOM
    Write-Host "=== $Id"
    Get-Content -Path $Path | ForEach-Object { Write-Host "    $(Format-S64Text ($_ -replace '("tenantAlias":\s*")[^"]*', '$1<Alias>'))" }
    $Validation = Test-OERStructure -Path $Path
    $Findings = @($Validation.Errors | Where-Object { $null -ne $_ })
    Write-Host "--- offline validation: Valid = $($Validation.Valid), findings = $($Findings.Count)"
    foreach ($Finding in $Findings) { Write-Host "    [$($Finding.Severity)] $($Finding.Section) $($Finding.Path): $(Format-S64Text $Finding.Message)" }
    if (-not $Validation.Valid) { return }

    $Splat = @{ Path = $Path; Include = $Include; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'CheckError' }
    if ($Prune) { $Splat.Prune = $true }
    if ($Apply) { $Splat.Confirm = $false } else { $Splat.WhatIf = $true }
    Write-Host ('--- Invoke-OERStructure -Include {0}{1}{2}' -f ($Include -join ','), $(if ($Prune) { ' -Prune' } else { '' }), $(if ($Apply) { ' -Confirm:$false' } else { ' -WhatIf' }))
    $Out = @(Invoke-OERStructure @Splat 3>&1)
    $Warn = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $global:S64Result = @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
    Write-Host "--- warnings, in the order written: $($Warn.Count)"
    $Warn | ForEach-Object { Write-Host "    WARNING: $(Format-S64Text $_.Message)" }
    $Errs = @($CheckError | Where-Object { $null -ne $_ })
    Write-Host "--- errors: $($Errs.Count)"
    foreach ($E in $Errs) { Write-Host "    ERROR [$($E.FullyQualifiedErrorId)]: $(Format-S64Text $E.Exception.Message)" }
    Write-Host "--- results, in the order returned: $($S64Result.Count)"
    $S64Result | ForEach-Object { Write-Host ('    [{0}] {1} | {2} | {3}' -f $_.Section, (Format-S64Text $_.Item), $_.Action, (Format-S64Text $_.Detail)) }
    Write-Host "--- action counts: $(($S64Result | Group-Object Action -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')"
    $S64Result | Select-Object @{ Name = 'CheckId'; Expression = { $Id } }, Section, Item, Action, Detail |
        Export-Csv -Path (Join-Path $Raw 'all-results.csv') -Append -NoTypeInformation
}
```

**The test principals, and the script section 5 runs in a process of its own.** Paste this block as
it stands -- the here-string must close at column 0.

```powershell
$User1Upn  = "$Prefix-user1@$Domain"
$User2Upn  = "$Prefix-user2@$Domain"
$NobodyUpn = "$Prefix-nobody@$Domain"   # must resolve to nothing: the prerequisite script refuses to run while it exists
$RagName   = "$Prefix-rag"              # role-assignable; oer-s64-user2 is its only member
$PlainName = "$Prefix-plain"            # NOT role-assignable
$CcRagName = "$Prefix-ccrag"            # role-assignable; oer-live-cc's service principal is its only member

$RefusedScript = @'
# Check 5.1 -- runs in a process of its own, signed in app-only as oer-live-cc-noperm: the same
# certificate as oer-live-cc, and no API permission at all. Written by the checklist; its inputs come
# from 5.1-input.json beside it. It signs in without -IncludeARM. An app-only session has no v1.0/me:
# the session's own ids, from the claims of the token it obtained, identify it, as True/False only.
$ErrorActionPreference = 'Continue'
$In = Get-Content -Path (Join-Path $PSScriptRoot '5.1-input.json') -Raw | ConvertFrom-Json
$env:PSModulePath = $In.PSModulePathPrefix + [System.IO.Path]::PathSeparator + $env:PSModulePath
Import-Module Omnicit.EntraRBAC -Force
try {
    $null = Connect-OER -TenantId $In.TenantId -ClientId $In.NoPermAppId -Certificate (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($In.Thumbprint)") -ErrorAction Stop
} catch {
    Write-Host "STOP: the sign-in as oer-live-cc-noperm failed, so nothing below ran: $($PSItem.Exception.Message)"
    $Error.Clear()
    exit 1
}
# The identity check, BEFORE anything else, printed as True/False only -- never the ids. Nothing
# below may run unless all three are True: this script makes two real -Prune runs unattended.
$Ctx = Get-MgContext
$AppOk = [string]$Ctx.ClientId -eq $In.NoPermAppId
$TenantOk = [string]$Ctx.TenantId -eq $In.TenantId
$NoPermissionOk = @($Ctx.Scopes | Where-Object { $_ }).Count -eq 0
Write-Host "identity check: session app id is oer-live-cc-noperm: $AppOk"
Write-Host "identity check: tenant is the test tenant: $TenantOk"
Write-Host "identity check: the token carries no application permission: $NoPermissionOk"
if (-not ($AppOk -and $TenantOk -and $NoPermissionOk)) {
    Disconnect-OER
    Write-Host 'STOP: the identity check failed, so nothing below ran. Signed out.'
    exit 1
}
$Names = @{}
$Names[([string]$In.RoleId).ToLowerInvariant()] = $In.RoleName
$Names[([string]$In.User1Id).ToLowerInvariant()] = $In.User1Name
$Names[([string]$In.RagId).ToLowerInvariant()] = $In.RagName
function Format-Text {
    # The tenant id, every GUID (by the names above, else <id>) and the test domain replaced.
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return [string]$Text }
    $Out = $Text -ireplace [regex]::Escape([string]$In.TenantId), '<TenantId>'
    $Out = $Out -replace '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', {
        $Key = $_.Value.ToLowerInvariant()
        if ($Names.ContainsKey($Key)) { '<' + $Names[$Key] + '>' } else { '<id>' }
    }
    $Out -ireplace ('@' + [regex]::Escape([string]$In.Domain)), '@<test domain>'
}
function Show-Published {
    # The error id and message of each error the named cmdlet published -- never the record itself.
    param([object[]]$Record, [string]$Cmdlet)
    $All = @($Record | Where-Object { $null -ne $_ })
    $Published = @($All | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains $Cmdlet })
    Write-Host "Errors published by $($Cmdlet): $($Published.Count) (records collected: $($All.Count))"
    $Published | ForEach-Object { Write-Host "ERROR [$($_.FullyQualifiedErrorId)]: $(Format-Text $_.Exception.Message)" }
}
function Show-Distinct {
    # Every distinct error id and message among the records -- never the records themselves.
    param([object[]]$Record)
    $All = @($Record | Where-Object { $null -ne $_ })
    $Distinct = @($All | ForEach-Object { "[$($_.FullyQualifiedErrorId)]: $(Format-Text $_.Exception.Message)" } | Select-Object -Unique)
    Write-Host "Error records collected: $($All.Count); distinct: $($Distinct.Count)"
    $Distinct | ForEach-Object { Write-Host "ERROR $_" }
}
function New-Doc {
    param([Parameter(Mandatory)][object[]]$Assignment)
    [ordered]@{ version = '1.0'; tenantAlias = $In.Alias; directoryRoleAssignments = @($Assignment) } | ConvertTo-Json -Depth 10
}
function Invoke-Doc {
    # One document with -Prune: the -WhatIf plan first; the real run only when the plan holds nothing
    # but Failed rows -- this identity can read nothing, so any other row means it is not the refused
    # identity this check describes, and nothing may be written on its account.
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Json)
    $Path = Join-Path $PSScriptRoot "$Id.json"
    Set-Content -Path $Path -Value $Json -Encoding utf8NoBOM
    foreach ($Real in $false, $true) {
        $Splat = @{ Path = $Path; Include = 'DirectoryRoleAssignments'; Prune = $true; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'DocError' }
        if ($Real) { $Splat.Confirm = $false } else { $Splat.WhatIf = $true }
        $Out = @(Invoke-OERStructure @Splat 3>&1)
        $Rows = @($Out | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
        $WarnCount = @($Out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count
        Write-Host "=== $Id $(if ($Real) { '-Prune, for real' } else { '-Prune -WhatIf' }) -- rows: $($Rows.Count); warnings: $WarnCount"
        $Rows | ForEach-Object { Write-Host ('  [{0}] {1} | {2} | {3}' -f $_.Section, (Format-Text $_.Item), $_.Action, (Format-Text $_.Detail)) }
        Write-Host "action counts: $(($Rows | Group-Object Action -NoElement | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')"
        Show-Distinct -Record $DocError
        if (-not $Real -and @($Rows | Where-Object { $_.Action -ne 'Failed' }).Count -gt 0) {
            Write-Host "STOP: the plan of $Id holds a row that is not Failed; its real -Prune run is not made."
            return
        }
    }
}
# (a) By name: the role-definition lookup is what gets refused.
$A = @(Get-OEREligibleDirectoryRoleAssignment -Role $In.RoleName -ErrorAction SilentlyContinue -ErrorVariable ErrA)
Write-Host "(a) Get eligible by name -- result objects: $($A.Count)"
Show-Published -Record $ErrA -Cmdlet 'Get-OEREligibleDirectoryRoleAssignment'
# (b), (c) By role definition id: no lookup, so the schedule read is the one refused.
$B = @(Get-OEREligibleDirectoryRoleAssignment -Role $In.RoleId -ErrorAction SilentlyContinue -ErrorVariable ErrB)
Write-Host "(b) Get eligible by role definition id -- result objects: $($B.Count)"
Show-Published -Record $ErrB -Cmdlet 'Get-OEREligibleDirectoryRoleAssignment'
$C = @(Get-OERActiveDirectoryRoleAssignment -Role $In.RoleId -ErrorAction SilentlyContinue -ErrorVariable ErrC)
Write-Host "(c) Get active by role definition id -- result objects: $($C.Count)"
Show-Published -Record $ErrC -Cmdlet 'Get-OERActiveDirectoryRoleAssignment'
# (d) A document naming the role and principals by name: every role lookup is refused.
Invoke-Doc -Id '5.1d-by-name' -Json (New-Doc -Assignment @(
        [ordered]@{ role = $In.RoleName; principal = $In.User1Upn; assignmentType = 'Eligible'; durationDays = 7 },
        [ordered]@{ role = $In.RoleName; principal = $In.User1Upn; assignmentType = 'Active'; permanent = $true },
        [ordered]@{ role = $In.RoleName; principal = $In.RagName; principalType = 'Group'; assignmentType = 'Eligible' },
        [ordered]@{ role = $In.RoleName; principal = $In.RagName; principalType = 'Group'; assignmentType = 'Active'; durationDays = 5 }))
# (e) The same document by ids: nothing to look up, so the pair reads and the item reads are refused.
Invoke-Doc -Id '5.1e-by-id' -Json (New-Doc -Assignment @(
        [ordered]@{ role = $In.RoleId; principal = $In.User1Id; assignmentType = 'Eligible'; durationDays = 7 },
        [ordered]@{ role = $In.RoleId; principal = $In.User1Id; assignmentType = 'Active'; permanent = $true },
        [ordered]@{ role = $In.RoleId; principal = $In.RagId; principalType = 'Group'; assignmentType = 'Eligible' },
        [ordered]@{ role = $In.RoleId; principal = $In.RagId; principalType = 'Group'; assignmentType = 'Active'; durationDays = 5 }))
# (f) The same reads outside the module, read as data: status and Graph's error code only.
$Probes = [ordered]@{
    'role-definition lookup'    = 'v1.0/roleManagement/directory/roleDefinitions?$filter=' + [uri]::EscapeDataString("displayName eq '$($In.RoleName)'") + '&$select=id'
    'eligibility schedule read' = 'v1.0/roleManagement/directory/roleEligibilitySchedules?$filter=' + [uri]::EscapeDataString("roleDefinitionId eq '$($In.RoleId)'")
    'assignment schedule read'  = 'v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=' + [uri]::EscapeDataString("roleDefinitionId eq '$($In.RoleId)'")
}
foreach ($Probe in $Probes.GetEnumerator()) {
    $Body = Invoke-MgGraphRequest -Method GET -Uri $Probe.Value -OutputType HashTable -SkipHttpErrorCheck -StatusCodeVariable 'ProbeStatus'
    $Code = if ($Body -is [System.Collections.IDictionary] -and $Body['error']) { [string]$Body['error']['code'] } else { '' }
    Write-Host "Raw status of the $($Probe.Key) for this identity: $ProbeStatus $Code"
}
$Error.Clear()
Disconnect-OER
Write-Host 'Done. Copy the lines above into check 5.1.'
'@
```

In the `Expect:` lines below, a name in angle brackets is an id the helpers have already named:
`<oer-s64-user1>`, `<oer-s64-user2>`, `<oer-s64-rag>`, `<oer-s64-plain>`, `<oer-s64-ccrag>`,
`<oer-live-cc>` (the certificate identity's service principal), `<Reports Reader>` and
`<Message Center Reader>` (the role definition ids), `<policy of Reports Reader>` and
`<policy of Message Center Reader>` (the policy ids), and in section 6 `<Me>` (Philip).
`<not a test object>` is an id none of those is --
as a prune target, a stop condition. A test user principal name prints as
`oer-s64-user1@<test domain>`. PowerShell's own `What if:` lines print the ids and names as they
are: they are described below as `<the id of oer-s64-user2>` or `<oer-s64-user1's user principal name>`.

**Run order.** Section 0, then section 1 before ANY write -- 1.1 and 1.3 compare the tenant with the
two baseline files the Teardown restores. Then sections 2, 3 and 4 in order: each starts from the
state the one before it leaves (2.6 removes what 2.1 made, 2.7 changes what 2.2 made, section 3
builds the Reports Reader state section 4 prunes, 4.2 needs 2.4's assignment, and 4.5 -- after
4.4 -- prunes 2.7's). Run sections 0 to 4 within two days of the prerequisite run: the certificate
identity's own Message Center Reader assignment and `oer-s64-ccrag`'s are time-bound (`P2D`), 4.3
needs the first and 4.5 both -- if either has expired, re-run the prerequisite script, which only
fills in what is missing. Section 5 after section 4. Section 6 last, by Philip, then the Teardown.
If this window is closed part-way, paste the Setup blocks again (variables, sign-in, helpers, test
principals) and re-run 0.5 -- it also sets `$IdCcRag`, which 4.5 needs; from 3.3 on, also paste
section 3's document block and the first two lines of 3.3 (its seven-day `$E1` and `$Doc33`), and
from section 4 on section 4's document block (4.5 builds its own document). A raw read answering
401 after a long pause means the token `Connect-OER` handed the Graph SDK has expired: paste the
sign-in block again. **Wait five minutes after a write that starts a principal's active assignment
before updating or removing any of that principal's assignments of the same role** -- Microsoft
Graph refuses those with `ActiveDurationTooShort` until the active assignment has run for five
minutes (measured in this file's run; see 3.3 and T.1). That means five minutes between 3.1c and
3.3b, and between the last write of section 6 and T.1.

---

### 0. Preparation

- [x] **0.1 The session runs THIS branch's build.**

  ```powershell
  git -C $Repo fetch origin
  git -C $Repo log --format=%s origin/main..HEAD
  $M = Get-Module Omnicit.EntraRBAC
  '{0} {1} from {2}' -f $M.Name, $M.Version, $M.ModuleBase
  & $M { Get-Command Resolve-OERDirectoryRoleDefinitionId, Resolve-OERDirectoryRoleInput, Get-OERRoleAssignableState,
      Test-OERDirectoryRolePermanentAllowed, New-OERDirectoryRoleScheduleRequestBody, ConvertTo-OERDirectoryRoleAssignment,
      ConvertTo-OERDirectoryRoleScheduleRequest, Select-OERManagedDirectoryRoleAssignment, Resolve-OERDirectoryRoleAssignmentChange,
      Get-OERTokenObjectId, Get-OERSignedInObjectId, Sync-OERStructureDirectoryRoleAssignment, Get-OERMemberGroupId } | Format-Table Name, CommandType -AutoSize
  $Six = 'Get-OEREligibleDirectoryRoleAssignment', 'New-OEREligibleDirectoryRoleAssignment', 'Remove-OEREligibleDirectoryRoleAssignment',
      'Get-OERActiveDirectoryRoleAssignment', 'New-OERActiveDirectoryRoleAssignment', 'Remove-OERActiveDirectoryRoleAssignment'
  Get-Command $Six | Format-Table Name, CommandType -AutoSize
  (Get-Command Invoke-OERStructure).Parameters['Include'].Attributes.ValidValues -contains 'DirectoryRoleAssignments'
  Get-OERRequiredScope -Cmdlet $Six | ForEach-Object { '{0} [{1}]: {2}' -f $_.Cmdlet, $_.Transport, ($_.GraphScope -join ', ') }
  $S = 'New-OEREligibleDirectoryRoleAssignment -Role Reports'
  (TabExpansion2 -inputScript $S -cursorColumn $S.Length).CompletionMatches.CompletionText
  ```

  **Expect:** before the merge, the log lists at least these subjects (record any later one too --
  review fixes land after this file was written): "fix: match a directory role name without regard
  to letter case", "feat: read eligible and active directory role assignments", "test: pin exact
  call counts in the directory role assignment read tests", "feat: grant and remove eligible and
  active directory role assignments", "test: prove the error paths of the directory role
  assignment cmdlets", "fix: refuse a named principal alongside piped assignments on directory role
  removal", "test: require directory schedule permissions for the directory role assignment paths",
  "feat: tab-complete, format and list the directory role assignment cmdlets", "feat: decide which
  live directory role assignment a document entry can match", "feat: directoryRoleAssignments
  section in the apply document", "feat: record the signed-in identity's object id from the token's
  oid claim", "fix: report an unknown assignmentType and prove both directory role reads", "feat:
  prune directory role assignments only within declared role and type pairs", "test: prove a
  declared principal id matches its live assignment in any letter case", "fix: decide principalType
  alike in the prune pass and the item, and reword the unknown-identity reason", "docs: release note
  and rules for directory role assignments", "docs: live-verification checklist for directory
  role assignments", "fix: refuse an ambiguous service principal display name" and "fix: never
  prune a directory role the signed-in identity holds through a group". Subjects, not hashes: a
  rebase onto `main` rewrites every hash. After the merge the range is empty -- the squash merge
  folds the branch into one commit on `main`. `ModuleBase` lies under
  `<your-clone>/output/module/Omnicit.EntraRBAC/`; the thirteen private functions (the last,
  `Get-OERMemberGroupId`, came with the group guard) and the six public ones are listed as
  `Function`; the `ValidValues` line prints `True`; the scope lines
  read, in this order,
  `Get-OEREligibleDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleEligibilitySchedule.Read.Directory, RoleManagement.Read.Directory, User.ReadBasic.All`,
  `New-OEREligibleDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleEligibilitySchedule.ReadWrite.Directory, RoleManagement.Read.Directory, User.ReadBasic.All`,
  `Remove-OEREligibleDirectoryRoleAssignment [Graph]:` the same list as New,
  `Get-OERActiveDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleAssignmentSchedule.Read.Directory, RoleManagement.Read.Directory, User.ReadBasic.All`,
  `New-OERActiveDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleAssignmentSchedule.ReadWrite.Directory, RoleManagement.Read.Directory, User.ReadBasic.All`
  and `Remove-OERActiveDirectoryRoleAssignment [Graph]:` the same list as New; the completion list
  holds `'Reports Reader'` -- quoted, since the name holds a space.
  **Failure looks like:** `CommandNotFound` for any of the functions, `False`, a missing or
  different scope row, or no completion -- a build without this branch's change is loaded. Rebuild,
  fix `PSModulePath`, re-import; nothing below means anything until this passes.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass (2026-09-29, CC as oer-live-cc, the clone at e955842). The log lists the branch's 33 subjects, the 17 this check names among them, plus the two fix subjects of the follow-up; the 13 private and 6 public functions are Function; True; the six scope rows as expected; the completion lists 'Reports Reader'.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  docs: correct why the group guard reads every group membership
  test: pin the service principal lookup in the ambiguity tests
  fix: emit the signed-in identity's group ids one by one
  docs: release note for the service principal refusal and the group guard
  docs: live checks for the group guard and the service principal refusal
  docs: drop the tenant profile requirement and relabel the manual checks
  fix: never prune a directory role the signed-in identity holds through a group
  fix: refuse an ambiguous service principal display name
  docs: require the tenant profile in the directory role assignment checklist
  docs: name what the principal scopes resolve on directory role writes
  fix: lower-case the principal id in the directory role assignment filter
  fix: refuse inherited or activated rows piped into directory role removal
  docs: state that a group's own directory role assignment can be pruned
  fix: warn when a directory role assignment names a service principal by display name
  fix: pass the Graph token to the oid reader as a secure string
  docs: stop the refused-read run on a failed identity check and harden the prune gate
  docs: live-verification checklist for directory role assignments
  docs: release note and rules for directory role assignments
  fix: decide principalType alike in the prune pass and the item, and reword the unknown-identity reason
  test: prove a declared principal id matches its live assignment in any letter case
  feat: prune directory role assignments only within declared role and type pairs
  fix: report an unknown assignmentType and prove both directory role reads
  feat: record the signed-in identity's object id from the token's oid claim
  feat: directoryRoleAssignments section in the apply document
  feat: decide which live directory role assignment a document entry can match
  feat: tab-complete, format and list the directory role assignment cmdlets
  test: require directory schedule permissions for the directory role assignment paths
  fix: refuse a named principal alongside piped assignments on directory role removal
  test: prove the error paths of the directory role assignment cmdlets
  feat: grant and remove eligible and active directory role assignments
  test: pin exact call counts in the directory role assignment read tests
  feat: read eligible and active directory role assignments
  fix: match a directory role name without regard to letter case
  Omnicit.EntraRBAC 1.1.0 from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0
  
  Name                                      CommandType
  ----                                      -----------
  Resolve-OERDirectoryRoleDefinitionId         Function
  Resolve-OERDirectoryRoleInput                Function
  Get-OERRoleAssignableState                   Function
  Test-OERDirectoryRolePermanentAllowed        Function
  New-OERDirectoryRoleScheduleRequestBody      Function
  ConvertTo-OERDirectoryRoleAssignment         Function
  ConvertTo-OERDirectoryRoleScheduleRequest    Function
  Select-OERManagedDirectoryRoleAssignment     Function
  Resolve-OERDirectoryRoleAssignmentChange     Function
  Get-OERTokenObjectId                         Function
  Get-OERSignedInObjectId                      Function
  Sync-OERStructureDirectoryRoleAssignment     Function
  Get-OERMemberGroupId                         Function
  
  
  Name                                      CommandType
  ----                                      -----------
  Get-OEREligibleDirectoryRoleAssignment       Function
  New-OEREligibleDirectoryRoleAssignment       Function
  Remove-OEREligibleDirectoryRoleAssignment    Function
  Get-OERActiveDirectoryRoleAssignment         Function
  New-OERActiveDirectoryRoleAssignment         Function
  Remove-OERActiveDirectoryRoleAssignment      Function
  
  True
  Get-OEREligibleDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleEligibilitySchedule.Read.Directory, RoleManagement.Read.Directory, User.ReadBasic.All
  New-OEREligibleDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleEligibilitySchedule.ReadWrite.Directory, RoleManagement.Read.Directory, User.ReadBasic.All
  Remove-OEREligibleDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleEligibilitySchedule.ReadWrite.Directory, RoleManagement.Read.Directory, User.ReadBasic.All
  Get-OERActiveDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleAssignmentSchedule.Read.Directory, RoleManagement.Read.Directory, User.ReadBasic.All
  New-OERActiveDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleAssignmentSchedule.ReadWrite.Directory, RoleManagement.Read.Directory, User.ReadBasic.All
  Remove-OERActiveDirectoryRoleAssignment [Graph]: Application.Read.All, Group.Read.All, RoleAssignmentSchedule.ReadWrite.Directory, RoleManagement.Read.Directory, User.ReadBasic.All
  'Reports Reader'
  ```

- [x] **0.2 The prerequisite script's plan names only `oer-s64` targets, the two baseline files and the certificate identity's own assignment.** Paste the `-WhatIf` run's output from Setup, redacted per the rules at the top.

  **Expect:** the lines Setup lists under "What the script prints": first
  `[oer-s64] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, prefix 'oer-s64', expected organization '<test tenant>'.`
  and the `Directory roles (fixed): ...` line with `(exists: False)` twice on a first run; after
  each of its sign-ins both lines `... identity check: session app id is oer-live-cc: True` and
  `... identity check: tenant is the test tenant: True`;
  `[oer-s64] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.`;
  no `Unattended run: ...` line and no question (`-WhatIf`). Every `What if:` target is one of: the
  two baseline files under `<your-clone>\docs\live-verification\raw\s64\` (when they do not exist
  yet), the DISABLED users `oer-s64-user1` and `oer-s64-user2` (printed as user principal names --
  redact), the groups `oer-s64-rag` (role-assignable), `oer-s64-plain` and `oer-s64-ccrag`
  (role-assignable), the membership `oer-s64-rag <- oer-s64-user2`, the ACTIVE time-bound (`P2D`)
  Message Center Reader assignment of the certificate identity's own service principal, the
  membership of that service principal in `oer-s64-ccrag`
  (`Performing the operation "Add member 'the service principal of oer-live-cc'" on target "oer-s64-ccrag"`),
  and the ACTIVE time-bound (`P2D`) Message Center Reader assignment of `oer-s64-ccrag`
  (`... on target "active directory role 'Message Center Reader' for oer-s64-ccrag at directory scope '/'"`).
  No subscription, no resource group, nothing in Azure; no directory role other than the two. Then
  the summary, with `(none -- not created)` as the id of every object it would create -- the three
  groups, both `group member` rows, the `own assignment` and the `group assignment` included -- and
  `policy baseline (not written (WhatIf))` / `assignment baseline (not written (WhatIf))`,
  `[oer-s64] WhatIf: nothing was created, restored, removed or written.` and `[oer-s64] Done.`
  **Failure looks like:** a target without the prefix other than those named above; a directory
  role other than the two; a refusal line -- `Refusing to run: ...` from the tenant identification
  (check `$OrgName` exactly, case-sensitive, `$Domain` and `$TenantId`; never weaken the check), a
  refusal naming a group under one of the three names with the wrong shape or another member (it
  is never repaired: delete it by hand), a refusal naming a direct assignment of either role to a
  principal the script did not create (someone holds the role: stop, this file cannot restore what
  it did not record), or a user `oer-s64-nobody@...` that exists. Record it and stop.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Every What if target carries the prefix oer-s64, apart from the two baseline files, the certificate identity's own Message Center Reader assignment and its membership of oer-s64-ccrag; no directory role but the two; both identity lines True; the tenant identified; no Tenant Profile on this machine.

  ```text
  [oer-s64] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, prefix 'oer-s64', expected organization '<test tenant>'.
  [oer-s64] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Policy baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json (exists: False). Assignment baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json (exists: False).
  [oer-s64] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s64] No Tenant Profile '<Alias>' on this machine; the sign-in names -TenantId.
  [oer-s64] Microsoft Graph sign-in: signing in to Microsoft Graph as the certificate identity (app-only, certificate from Cert:\CurrentUser\My, process-scoped context, no Azure Resource Manager).
  [oer-s64] Microsoft Graph sign-in identity check: session app id is oer-live-cc: True
  [oer-s64] Microsoft Graph sign-in identity check: tenant is the test tenant: True
  [oer-s64] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s64] Directory role 'Reports Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] Directory role 'Message Center Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] No baseline files yet; this run captures both before its first write.
  What if: Performing the operation "Write the policy baseline: the raw Microsoft Graph v1.0 rules of both directory-role policies, which -Teardown restores" on target "<Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json".
  What if: Performing the operation "Write the assignment baseline: the direct eligible and active assignments of both directory roles, which -Teardown verifies and restores" on target "<Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json".
  What if: Performing the operation "Create a DISABLED test user with a random, unprinted password" on target "person1@example.com".
  What if: Performing the operation "Create a DISABLED test user with a random, unprinted password" on target "person2@example.com".
  What if: Performing the operation "Create a ROLE-ASSIGNABLE security group (isAssignableToRole true, which can be set only when a group is created)" on target "oer-s64-rag".
  What if: Performing the operation "Create a security group that is NOT role-assignable" on target "oer-s64-plain".
  What if: Performing the operation "Create a ROLE-ASSIGNABLE security group (isAssignableToRole true, which can be set only when a group is created)" on target "oer-s64-ccrag".
  What if: Performing the operation "Add member 'person2@example.com'" on target "oer-s64-rag".
  What if: Performing the operation "Request an ACTIVE, time-bound (P2D) assignment (Microsoft Graph v1.0 roleAssignmentScheduleRequests, adminAssign)" on target "active directory role 'Message Center Reader' for the service principal of oer-live-cc at directory scope '/'".
  What if: Performing the operation "Add member 'the service principal of oer-live-cc'" on target "oer-s64-ccrag".
  What if: Performing the operation "Request an ACTIVE, time-bound (P2D) assignment (Microsoft Graph v1.0 roleAssignmentScheduleRequests, adminAssign)" on target "active directory role 'Message Center Reader' for oer-s64-ccrag at directory scope '/'".
  
  [oer-s64] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
  
  Kind                                       Name                                                                                        Id
  ----                                       ----                                                                                        --
  user                                       person1@example.com                                                       (none -- not created)
  user                                       person2@example.com                                                       (none -- not created)
  group                                      oer-s64-rag                                                                                 (none -- not created)
  group                                      oer-s64-plain                                                                               (none -- not created)
  group                                      oer-s64-ccrag                                                                               (none -- not created)
  group member                               oer-s64-rag <- person2@example.com                                        (none -- not created)
  group member                               oer-s64-ccrag <- oer-live-cc                                                                (none -- not created)
  directory role (built-in, fixed)           Reports Reader                                                                              00000000-0000-0000-0000-000000000001
  directory role policy                      Reports Reader                                                                              DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002
  directory role (built-in, fixed)           Message Center Reader                                                                       00000000-0000-0000-0000-000000000003
  directory role policy                      Message Center Reader                                                                       DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004
  own assignment                             Message Center Reader, active, P2D, of oer-live-cc (schedule)                               (none -- not created)
  group assignment                           Message Center Reader, active, P2D, of oer-s64-ccrag (schedule)                             (none -- not created)
  policy baseline (not written (WhatIf))     <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json    -
  assignment baseline (not written (WhatIf)) <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json -
  
  
  [oer-s64] WhatIf: nothing was created, restored, removed or written.
  [oer-s64] Done.
  ```

- [x] **0.3 The prerequisite script ran, every test object exists, and both baseline files are written.** Paste its output and summary, redacted per the rules at the top, then run the read-only block below.

  ```powershell
  foreach ($P in $BaselinePath, $AssignmentBaselinePath) {
      $I = Get-Item -LiteralPath $P -ErrorAction SilentlyContinue
      '{0}: exists {1}; written {2}' -f (Split-Path $P -Leaf), [bool]$I, $(if ($I) { $I.LastWriteTime.ToString('s') } else { '-' })
  }
  $BP = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json -AsHashtable
  $BA = Get-Content -LiteralPath $AssignmentBaselinePath -Raw | ConvertFrom-Json -AsHashtable
  foreach ($E in @($BP['roles'])) { 'policy baseline: {0}: {1} rules; policyId recorded {2}; roleDefinitionId recorded {3}' -f $E['displayName'], @($E['rules']).Count, [bool]$E['policyId'], [bool]$E['roleDefinitionId'] }
  foreach ($E in @($BA['roles'])) { 'assignment baseline: {0}: eligible {1}, active {2}; roleDefinitionId recorded {3}' -f $E['displayName'], @($E['eligible'] | Where-Object { $null -ne $_ }).Count, @($E['active'] | Where-Object { $null -ne $_ }).Count, [bool]$E['roleDefinitionId'] }
  git -C $Repo check-ignore -q -- 'docs/live-verification/raw/s64/probe.json'
  "raw/s64 is ignored by git: $($LASTEXITCODE -eq 0)"
  ```

  **Expect:** from the script, the lines Setup lists: the `Mode: CREATE or complete. ...` and
  `Directory roles (fixed): ...` lines; both identity lines ending `True` after EVERY sign-in; the
  `Identified the test tenant: ...` line, then
  `[oer-s64] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.`
  On a first run `[oer-s64] No baseline files yet; this run captures both before its first write.`,
  `[oer-s64] Wrote the policy baseline (<n> + <m> rules): <path>` and
  `[oer-s64] Wrote the assignment baseline (Reports Reader: eligible 0, active 0; Message Center Reader: eligible 0, active 0): <path>`
  BEFORE the first `Created ...` line (on a later run instead
  `[oer-s64] The baseline files exist; comparing the live state with them.` and, for both roles,
  `[oer-s64] Directory role '<role>': rules differing from the policy baseline: 0`). Then
  `[oer-s64] Created user <upn> (disabled).` twice, `[oer-s64] Created group oer-s64-rag (role-assignable).`,
  `[oer-s64] Created group oer-s64-plain.`,
  `[oer-s64] Created group oer-s64-ccrag (role-assignable).`,
  `[oer-s64] Added <upn> to oer-s64-rag.` (a line containing `likely replication delay` before it
  is a retry after a 404, not a failure),
  `[oer-s64] Requested the active Message Center Reader assignment of oer-live-cc (P2D): <request status>.`,
  `[oer-s64] Added the service principal of oer-live-cc to oer-s64-ccrag.` (the same retry lines
  may come before it) and
  `[oer-s64] Requested the active Message Center Reader assignment of oer-s64-ccrag (P2D): <request status>.`
  (a later run: `... is already a member of ...` and `... exists.`); no `Refusing to run: ` line.
  The summary: one row per object, kinds `user` (2), `group` (3), `group member` (2:
  `oer-s64-rag <- <upn>` and `oer-s64-ccrag <- oer-live-cc`), `directory role (built-in, fixed)`
  (2), `directory role policy` (2), `own assignment` (1), `group assignment` (1),
  `policy baseline (written by this run)` and `assignment baseline (written by this run)`
  (`(existed)` on a later run), and no `(none -- not created)`; redact every id and user principal
  name. The last line `[oer-s64] Done.` When Graph REFUSED the membership instead:
  `[oer-s64] Adding the service principal of oer-live-cc to oer-s64-ccrag was refused: <Graph's answer>`
  and `[oer-s64] Check 4.5 cannot run as written: mark it [~] with the line above.` in place of the
  last two lines, `(none -- not created)` for `oer-s64-ccrag <- oer-live-cc` and for the
  `group assignment` and nowhere else, and still `[oer-s64] Done.` -- carry on, and mark 4.5 `[~]`
  with the refusal line. From the block: both files
  `exists True`; `policy baseline:` one line per role, with the rule count Graph lists (step 3
  measured 17) and `True` twice; `assignment baseline:` one line per role -- the counts are
  normally `0` and `0`, since the script refuses to run while either role holds a direct assignment
  of a principal it did not create -- and `True`; `raw/s64 is ignored by git: True`.
  **Failure looks like:** an object missing from the summary, a refusal, a `False` identity line, or
  the script stopped on an error -- fix the cause and re-run it before 0.4. A baseline file missing
  or holding another shape than Setup describes: the helpers cannot compare with it -- stop before
  any write, since the teardown restores from exactly these files. `raw/s64 is ignored by git:
  False`: stop, the baseline files would be committable.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Both baselines written BEFORE the first Created line (17 + 17 rules; every assignment count 0). Graph ACCEPTED the service principal as a member of the role-assignable group ("Added the service principal of oer-live-cc to oer-s64-ccrag.") and the group's P2D assignment is Provisioned. Two retries after a 404 on oer-s64-rag (replication), then success. raw/s64 is ignored by git: True.

  ```text
  [oer-s64] Mode: CREATE or complete. Tenant alias '<Alias>', tenant <TenantId>, prefix 'oer-s64', expected organization '<test tenant>'.
  [oer-s64] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Policy baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json (exists: False). Assignment baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json (exists: False).
  [oer-s64] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s64] No Tenant Profile '<Alias>' on this machine; the sign-in names -TenantId.
  [oer-s64] Microsoft Graph sign-in: signing in to Microsoft Graph as the certificate identity (app-only, certificate from Cert:\CurrentUser\My, process-scoped context, no Azure Resource Manager).
  [oer-s64] Microsoft Graph sign-in identity check: session app id is oer-live-cc: True
  [oer-s64] Microsoft Graph sign-in identity check: tenant is the test tenant: True
  [oer-s64] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s64] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
  [oer-s64] Directory role 'Reports Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] Directory role 'Message Center Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] No baseline files yet; this run captures both before its first write.
  [oer-s64] Wrote the policy baseline (17 + 17 rules): <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json
  [oer-s64] Wrote the assignment baseline (Reports Reader: eligible 0, active 0; Message Center Reader: eligible 0, active 0): <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json
  [oer-s64] Created user person1@example.com (disabled).
  [oer-s64] Created user person2@example.com (disabled).
  [oer-s64] Created group oer-s64-rag (role-assignable).
  [oer-s64] Created group oer-s64-plain.
  [oer-s64] Created group oer-s64-ccrag (role-assignable).
  [oer-s64] Reading the members of oer-s64-rag, created moments ago failed (attempt 1 of 6, likely replication delay): Microsoft Graph answered 404 to GET v1.0/groups/<id>/members: Request_ResourceNotFound -- Resource '<id>' does not exist or one of its queried reference-property objects are not present. -- retrying in 5 s.
  [oer-s64] Adding person2@example.com to oer-s64-rag failed (attempt 1 of 6, likely replication delay): Microsoft Graph answered 404 to POST v1.0/groups/<id>/members/$ref: Request_ResourceNotFound -- Resource '<id>' does not exist or one of its queried reference-property objects are not present. -- retrying in 5 s.
  [oer-s64] Added person2@example.com to oer-s64-rag.
  [oer-s64] Requested the active Message Center Reader assignment of oer-live-cc (P2D): Provisioned.
  [oer-s64] Added the service principal of oer-live-cc to oer-s64-ccrag.
  [oer-s64] Requested the active Message Center Reader assignment of oer-s64-ccrag (P2D): Provisioned.
  [oer-s64] Reading back the active Message Center Reader assignment of oer-s64-ccrag failed (attempt 1 of 6, likely replication delay): the schedule is not listed yet -- retrying in 10 s.
  [oer-s64] Reading back the active Message Center Reader assignment of oer-s64-ccrag failed (attempt 2 of 6, likely replication delay): the schedule is not listed yet -- retrying in 10 s.
  
  [oer-s64] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
  
  Kind                                      Name                                                                                        Id
  ----                                      ----                                                                                        --
  user                                      person1@example.com                                                       00000000-0000-0000-0000-000000000005
  user                                      person2@example.com                                                       00000000-0000-0000-0000-000000000006
  group                                     oer-s64-rag                                                                                 00000000-0000-0000-0000-000000000007
  group                                     oer-s64-plain                                                                               00000000-0000-0000-0000-000000000008
  group                                     oer-s64-ccrag                                                                               00000000-0000-0000-0000-000000000009
  group member                              oer-s64-rag <- person2@example.com                                        00000000-0000-0000-0000-000000000006
  group member                              oer-s64-ccrag <- oer-live-cc                                                                00000000-0000-0000-0000-000000000010
  directory role (built-in, fixed)          Reports Reader                                                                              00000000-0000-0000-0000-000000000001
  directory role policy                     Reports Reader                                                                              DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002
  directory role (built-in, fixed)          Message Center Reader                                                                       00000000-0000-0000-0000-000000000003
  directory role policy                     Message Center Reader                                                                       DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004
  own assignment                            Message Center Reader, active, P2D, of oer-live-cc (schedule)                               00000000-0000-0000-0000-000000000011
  group assignment                          Message Center Reader, active, P2D, of oer-s64-ccrag (schedule)                             00000000-0000-0000-0000-000000000012
  policy baseline (written by this run)     <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json    -
  assignment baseline (written by this run) <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json -
  
  
  [oer-s64] Done.
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  baseline-directory-policies.json: exists True; written 2026-09-29T22:13:39
  baseline-directory-assignments.json: exists True; written 2026-09-29T22:13:39
  policy baseline: Reports Reader: 17 rules; policyId recorded True; roleDefinitionId recorded True
  policy baseline: Message Center Reader: 17 rules; policyId recorded True; roleDefinitionId recorded True
  assignment baseline: Reports Reader: eligible 0, active 0; roleDefinitionId recorded True
  assignment baseline: Message Center Reader: eligible 0, active 0; roleDefinitionId recorded True
  raw/s64 is ignored by git: True
  ```

- [x] **0.4 The identity check, the signed-in object id and no Azure Resource Manager token.** Read-only. Paste the two identity lines the sign-in block printed, then run:

  ```powershell
  $S64SignedIn = & (Get-Module Omnicit.EntraRBAC) { Get-OERSignedInObjectId }
  "the module's signed-in object id is a GUID: $(Test-S64Guid $S64SignedIn)"
  "the module's signed-in object id is oer-live-cc's service principal: $([string]::Equals([string]$S64SignedIn, [string]$S64Sp.id, [System.StringComparison]::OrdinalIgnoreCase))"
  "the session holds an Azure Resource Manager token: $([bool](& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.ArmToken }))"
  ```

  **Expect:** `identity check: session app id is oer-live-cc: True` and
  `identity check: tenant is the test tenant: True`; then `True`, `True` and
  `the session holds an Azure Resource Manager token: False`. The first two are what section 4's
  own-assignment guard compares against: `Initialize-OERAuth` stored the `oid` claim of the Graph
  token (`Get-OERTokenObjectId`, lower-cased), and an app-only token's `oid` is the service
  principal's object id. The last proves the sign-in was made without `-IncludeARM` (R17).
  **Failure looks like:** a `False` identity line -- stop. `is a GUID: False`: the token carried no
  `oid` claim, or the state was built by an older module -- every prune candidate in section 4
  would be withheld with `prune withheld: the signed-in identity's object id is unknown`; record it
  and stop before section 4. `oer-live-cc's service principal: False` with a GUID: the claim names
  someone else -- stop. An ARM token `True`: the sign-in block was changed; sign in again as given.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. identity check True, True; the signed-in object id is a GUID and is oer-live-cc's service principal: True, True; no Azure Resource Manager token.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  the module's signed-in object id is a GUID: True
  the module's signed-in object id is oer-live-cc's service principal: True
  the session holds an Azure Resource Manager token: False
  ```

- [x] **0.5 Record the object ids every later check compares against.** Read-only.

  ```powershell
  $U1 = Get-S64RawUser -Upn $User1Upn
  $U2 = Get-S64RawUser -Upn $User2Upn
  $Rag = Get-S64RawGroup -Name $RagName
  $Plain = Get-S64RawGroup -Name $PlainName
  $CcRag = Get-S64RawGroup -Name $CcRagName
  $IdUser1 = $U1.Id; $IdUser2 = $U2.Id; $IdRag = $Rag.Id; $IdPlain = $Plain.Id; $IdCcRag = $CcRag.Id
  $Sp = Get-S64RawStatus -Uri "v1.0/servicePrincipals(appId='$AppId')?`$select=id,displayName"
  $IdCc = if ($Sp.Status -eq 200) { [string]$Sp.Body['id'] } else { $null }
  $RoleIdRR  = Get-S64RawRoleDefinitionId -Name $RoleRR
  $RoleIdMCR = Get-S64RawRoleDefinitionId -Name $RoleMCR
  $PolicyIdRR  = (Get-S64RawPolicy -RoleDefinitionId $RoleIdRR -Label '0.5-rr-policy-raw').PolicyId
  $PolicyIdMCR = (Get-S64RawPolicy -RoleDefinitionId $RoleIdMCR -Label '0.5-mcr-policy-raw').PolicyId
  "users: oer-s64-user1 enabled $($U1.AccountEnabled); oer-s64-user2 enabled $($U2.AccountEnabled)"
  "oer-s64-rag: isAssignableToRole '$($Rag.IsAssignableToRole)'; securityEnabled $($Rag.SecurityEnabled); members [$((@($Rag.MemberIds) | ForEach-Object { Get-S64Name $_ }) -join ', ')]"
  "oer-s64-plain: isAssignableToRole '$($Plain.IsAssignableToRole)' (null prints as ''); securityEnabled $($Plain.SecurityEnabled); members $(@($Plain.MemberIds).Count)"
  "oer-s64-ccrag: isAssignableToRole '$($CcRag.IsAssignableToRole)'; securityEnabled $($CcRag.SecurityEnabled); members [$((@($CcRag.MemberIds) | ForEach-Object { Get-S64Name $_ }) -join ', ')]"
  "oer-live-cc service principal: status $($Sp.Status); displayName is oer-live-cc: $([string]$Sp.Body['displayName'] -ceq 'oer-live-cc')"
  Get-S64RawUser -Upn $NobodyUpn
  $S05Ids = @($IdUser1, $IdUser2, $IdRag, $IdPlain, $IdCcRag, $IdCc, $RoleIdRR, $RoleIdMCR)
  "ids read: $(@($S05Ids | Where-Object { Test-S64Guid $_ }).Count) of 8; all different: $(@($S05Ids | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique).Count -eq 8)"
  "policy ids read: $([bool]$PolicyIdRR) $([bool]$PolicyIdMCR); different: $($PolicyIdRR -ne $PolicyIdMCR)"
  ```

  **Expect:** `users: oer-s64-user1 enabled False; oer-s64-user2 enabled False`;
  `oer-s64-rag: isAssignableToRole 'True'; securityEnabled True; members [oer-s64-user2]`;
  `oer-s64-plain: isAssignableToRole 'False'` or `''` -- record which: 2.3 turns on it (null and
  false both count as not role-assignable) -- `; securityEnabled True; members 0`;
  `oer-s64-ccrag: isAssignableToRole 'True'; securityEnabled True; members [oer-live-cc]` --
  `members []` when the prerequisite run printed that Graph refused the membership: then 4.5 is
  `[~]`, with that refusal line;
  `oer-live-cc service principal: status 200; displayName is oer-live-cc: True`;
  `--- raw user read: 0 users match 'oer-s64-nobody@<test domain>', not one`;
  `ids read: 8 of 8; all different: True`; `policy ids read: True True; different: True`. No
  `FAILED` line.
  **Failure looks like:** any count off, a `True` for a user's `enabled`, `oer-s64-plain` role-assignable,
  a member missing from `oer-s64-rag` or an extra one, any member of `oer-s64-ccrag` other than
  `oer-live-cc`, or a `raw ... read FAILED` line -- a 403 there is a missing permission (see Stop
  conditions). `1 users match` for `oer-s64-nobody`: stop, 4.2 cannot run as written.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass, with one measured deviation: "oer-s64-ccrag: ... members []". App-only, Graph's untyped groups/{id}/members does not list a service principal member: the same group read as groups/{id}/members/microsoft.graph.servicePrincipal returns [oer-live-cc], and the service principal's own memberOf lists oer-s64-ccrag (raw reads 22:15-22:16). The membership exists; Get-S64RawGroup reads the untyped form -- a checklist fix, not a module one. ids 8 of 8, all different.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  users: oer-s64-user1 enabled False; oer-s64-user2 enabled False
  oer-s64-rag: isAssignableToRole 'True'; securityEnabled True; members [oer-s64-user2]
  oer-s64-plain: isAssignableToRole '' (null prints as ''); securityEnabled True; members 0
  oer-s64-ccrag: isAssignableToRole 'True'; securityEnabled True; members []
  oer-live-cc service principal: status 200; displayName is oer-live-cc: True
  --- raw user read: 0 users match 'oer-s64-nobody@<test domain>', not one
  ids read: 8 of 8; all different: True
  policy ids read: True True; different: True
  ```

---

### 1. Reads and the lookup -- before the first write

Nothing below this section may run before it: 1.1 and 1.3 prove the tenant starts where the two
baseline files say, and the Teardown restores exactly what those files hold.

- [x] **1.1 Both Get cmdlets, on both roles, against the assignment baseline -- and the Message Center Reader rows of the certificate identity and of `oer-s64-ccrag`.** Read-only.

  ```powershell
  foreach ($R in $RoleRR, $RoleMCR) {
      Invoke-S64Call -Cmdlet Get-OEREligibleDirectoryRoleAssignment -Splat @{ Role = $R } -Label "1.1 eligible, $R"
      Invoke-S64Call -Cmdlet Get-OERActiveDirectoryRoleAssignment -Splat @{ Role = $R } -Label "1.1 active, $R"
  }
  $S11 = @(Get-S64State)
  Show-S64State -State $S11 -Label '1.1'
  Show-S64AssignmentBaselineDiff -Label '1.1' -State $S11
  $Cc11 = @($S11 | Where-Object { $_.S64Role -eq $RoleMCR -and $_.Kind -eq 'Active' -and $_.PrincipalId -eq $IdCc })
  "oer-live-cc's own Message Center Reader rows: direct $(@($Cc11 | Where-Object { $_.MemberType -eq 'Direct' }).Count), other $(@($Cc11 | Where-Object { $_.MemberType -ne 'Direct' }).Count)"
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdCc -Label '1.1-cc-mcr-active-raw'
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdCcRag -Label '1.1-ccrag-mcr-active-raw'
  ```

  **Expect:** each of the four calls sends exactly TWO requests, in order:
  `GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq '<role>'&$select=id,displayName`
  (the name typed in its exact case: ONE lookup request) and
  `GET v1.0/roleManagement/directory/roleEligibilitySchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Reports Reader>'&$expand=principal,roleDefinition`
  (or `roleAssignmentSchedules`, or `<Message Center Reader>`); no own verbose line, no warning, no
  error. The state: normally no row for Reports Reader and none for Message Center Reader Eligible;
  for Message Center Reader Active two DIRECT rows,
  `<oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration '<type>'; DurationDays 2; end set`
  and `<oer-s64-ccrag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration '<type>'; DurationDays 2; end set`
  (record the expiration type Graph returns: `afterDateTime` or `afterDuration`), and possibly a
  third, an inherited row for `<oer-live-cc>` with a `MemberType` other than `Direct` -- the
  certificate identity holds the role through `oer-s64-ccrag` too: record whether Graph lists it,
  and its `MemberType`. The baseline diff: for both roles and both kinds `only live []` and
  `only baseline []`, EXCEPT
  `Message Center Reader, Active: ... only live [oer-live-cc, oer-s64-ccrag]`
  -- the script created both assignments after it wrote the baseline (the diff reads direct rows
  only). `oer-live-cc's own Message Center Reader rows: direct 1, other 0` (`other 1` when Graph
  lists the inherited row). The first raw read shows the own row,
  `memberType Direct; directoryScopeId '/'; assignmentType Assigned`, a window of 2 days (and the
  inherited row, when Graph lists it: record it); the second shows `oer-s64-ccrag`'s row, the same.
  When the prerequisite run recorded that Graph refused the membership, there is no
  `<oer-s64-ccrag>` row and no inherited row, `only live [oer-live-cc]`, and the second raw read
  shows 0 rows (4.5 is `[~]`).
  **Failure looks like:** a row for any principal the script did not create -- stop (Stop
  conditions); a non-empty `only baseline` -- a baseline assignment is gone since the script ran;
  record it (the teardown re-creates it); no row for the certificate identity, or one that is not
  `Assigned`/`Direct`: 4.3 cannot run -- re-run the prerequisite script; no row for `oer-s64-ccrag`
  although the prerequisite run added the membership: 4.5 cannot run -- re-run the prerequisite
  script. A third request in any call: the exact-case name did not match in one request -- record
  it.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Two requests per call; Message Center Reader Active holds <oer-live-cc> and <oer-s64-ccrag>, both Assigned, Direct, afterDateTime, 2 days; no inherited row for oer-live-cc (direct 1, other 0); the baseline diff only-live [oer-live-cc, oer-s64-ccrag]; both raw reads one row.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 1.1 eligible, Reports Reader -- Get-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleEligibilitySchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Reports Reader>'&$expand=principal,roleDefinition
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  === 1.1 active, Reports Reader -- Get-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Reports Reader>'&$expand=principal,roleDefinition
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  === 1.1 eligible, Message Center Reader -- Get-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleEligibilitySchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Message Center Reader>'&$expand=principal,roleDefinition
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  === 1.1 active, Message Center Reader -- Get-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Message Center Reader>'&$expand=principal,roleDefinition
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 2
  --- 1.1: Reports Reader, Eligible: 0 row(s)
  --- 1.1: Reports Reader, Active: 0 row(s)
  --- 1.1: Message Center Reader, Eligible: 0 row(s)
  --- 1.1: Message Center Reader, Active: 2 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-ccrag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
  --- 1.1: Reports Reader, Eligible: direct principals live 0, baseline 0; only live []; only baseline []
  --- 1.1: Reports Reader, Active: direct principals live 0, baseline 0; only live []; only baseline []
  --- 1.1: Message Center Reader, Eligible: direct principals live 0, baseline 0; only live []; only baseline []
  --- 1.1: Message Center Reader, Active: direct principals live 2, baseline 0; only live [oer-live-cc, oer-s64-ccrag]; only baseline []
  oer-live-cc's own Message Center Reader rows: direct 1, other 0
  --- 1.1-cc-mcr-active-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-live-cc>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  --- 1.1-ccrag-mcr-active-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-ccrag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  ```

- [x] **1.2 A name in another letter case now matches -- the step 3 finding closed.** Read-only. The active read of Message Center Reader is used because it has a row (1.1), so "the same rows" is not vacuous.

  ```powershell
  Invoke-S64Call -Cmdlet Get-OERActiveDirectoryRoleAssignment -Splat @{ Role = $RoleMCR } -Label '1.2a exact case'
  $A12 = @($S64Out)
  Invoke-S64Call -Cmdlet Get-OERActiveDirectoryRoleAssignment -Splat @{ Role = $RoleMCR.ToLowerInvariant() } -Label '1.2b lower case'
  $B12 = @($S64Out)
  'rows: exact {0}, lower case {1}; the same schedules: {2}' -f $A12.Count, $B12.Count, (((@($A12.ScheduleId) | Sort-Object) -join ',') -ceq ((@($B12.ScheduleId) | Sort-Object) -join ','))
  Invoke-S64Call -Cmdlet Get-OERActiveDirectoryRoleAssignment -Splat @{ Role = $RoleIdMCR } -Label '1.2c by role definition id'
  'by id: the same schedules: {0}' -f (((@($A12.ScheduleId) | Sort-Object) -join ',') -ceq ((@($S64Out.ScheduleId) | Sort-Object) -join ','))
  Invoke-S64Call -Cmdlet Get-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleRR.ToLowerInvariant() } -Label '1.2d policy by name in lower case'
  $D12 = $S64Out | Select-Object -First 1
  'policy: the one by exact name: {0}; RoleName as typed: {1}' -f ($D12.PolicyId -eq $PolicyIdRR), ($D12.RoleName -ceq $RoleRR.ToLowerInvariant())
  Invoke-S64Call -Cmdlet Get-OEREligibleDirectoryRoleAssignment -Splat @{ Role = "$Prefix-no-such-role" } -Label '1.2e a name no role has'
  ```

  **Expect:** (a) two requests -- the exact-case lookup and the schedule read -- and at least one
  object. (b) THREE requests, in order:
  `GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'message center reader'&$select=id,displayName`,
  then the list `GET v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName` (two
  lookup requests; should Graph page the list, each further page is one more
  `GET ...roleDefinitions?...$skiptoken=<token>` line -- record it), then the same schedule read as
  (a); the line prints `rows: exact <n>, lower case <n>; the same schedules: True`. (c) exactly ONE
  request, the schedule read -- a GUID is used as it stands -- and `by id: the same schedules: True`.
  (d) three requests: the lower-case filter, the list, then
  `GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Reports Reader>'&$expand=policy($expand=rules)`;
  one object, no error, and `policy: the one by exact name: True; RoleName as typed: True` -- step
  3's check 1.2b answered `RoleDefinitionNotFound` here. (e) two lookup requests (the filter, then
  the list) and NO schedule request; no object; one published error,
  `ERROR [RoleDefinitionNotFound,Get-OEREligibleDirectoryRoleAssignment]: No Microsoft Entra directory role definition named 'oer-s64-no-such-role' was found. Use Tab completion on -Role, or pass the role definition id directly.`
  **Failure looks like:** `RoleDefinitionNotFound` in (b) or (d) -- the case-insensitive step did
  not run or did not match; only two requests in (b) with rows -- Graph's filter matched in another
  case after all (not a defect; record it, since the rationale says the filter is case-sensitive);
  a schedule request in (e), or `RoleDefinitionReadFailed` there (a lookup that answered is not a
  refused one); a role lookup in (c).
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. (b) three requests and the same schedules; (c) one request; (d) three requests, True, True; (e) the filter and the list, RoleDefinitionNotFound, no schedule request.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 1.2a exact case -- Get-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Message Center Reader>'&$expand=principal,roleDefinition
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 2
  === 1.2b lower case -- Get-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'message center reader'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName
      GET v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Message Center Reader>'&$expand=principal,roleDefinition
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 2
  rows: exact 2, lower case 2; the same schedules: True
  === 1.2c by role definition id -- Get-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 1
      GET v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Message Center Reader>'&$expand=principal,roleDefinition
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 2
  by id: the same schedules: True
  === 1.2d policy by name in lower case -- Get-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'reports reader'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Reports Reader>'&$expand=policy($expand=rules)
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  policy: the one by exact name: True; RoleName as typed: True
  === 1.2e a name no role has -- Get-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'oer-s64-no-such-role'&$select=id,displayName
      GET v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Get-OEREligibleDirectoryRoleAssignment: 1 (other records collected, not shown: 0)
      ERROR [RoleDefinitionNotFound,Get-OEREligibleDirectoryRoleAssignment]: No Microsoft Entra directory role definition named 'oer-s64-no-such-role' was found. Use Tab completion on -Role, or pass the role definition id directly.
  --- objects returned: 0
  ```

- [x] **1.3 Both roles' PIM policies against the policy baseline, and their two permanent settings.** Read-only. Sections 2 and 3 change these settings; T.3 compares with this.

  ```powershell
  Show-S64BaselineDiff -Label '1.3'
  $View13 = [ordered]@{}
  foreach ($R in $RoleRR, $RoleMCR) {
      $P = Get-OERDirectoryRoleManagementPolicy -Role $R -ErrorAction Stop
      Show-S64Policy -Policy $P -Label "1.3 $R"
      $View13[$R] = [ordered]@{ AllowPermanentEligibility = $P.AllowPermanentEligibility; EligibleDuration = $P.EligibleDuration
          AllowPermanentActiveAssignment = $P.AllowPermanentActiveAssignment; ActiveDuration = $P.ActiveDuration; ActivationMaxHours = $P.ActivationMaxHours }
  }
  $View13 | ConvertTo-Json | Set-Content -Path (Join-Path $Raw '1.3-policy-view.json') -Encoding utf8NoBOM
  "Reports Reader: activation max hours $($View13[$RoleRR].ActivationMaxHours) -- section 6 activates for at most this long"
  ```

  **Expect:** for both roles `the baseline names this policy: True; rules live <n>, baseline <n>; differing from the baseline: 0`.
  Then one line per role, `policy of <role>`, with the name as typed; the permanent settings as
  the tenant holds them -- on this test tenant step 3 measured, for both roles,
  `eligible: permanent allowed True, P365D; active: permanent allowed True, P180D` and an
  activation maximum of 1 hour. Record the values: 2.5 and 3.1 are written against them.
  **Failure looks like:** a count above `0` -- a policy differs from the baseline the script just
  recorded: someone changed it in between; stop. A permanent setting already `False`: 2.5 or 3.1's
  closing step then answers `NoChange` for it -- carry on, and record it.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Both policies 0 rules differing; both roles eligible permanent True P365D, active permanent True P180D; activation maximum 1 hour.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 1.3: Reports Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  --- 1.3: Message Center Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  --- 1.3 Reports Reader: <policy of Reports Reader>; RoleName 'Reports Reader'; eligible: permanent allowed True, P365D; active: permanent allowed True, P180D
  --- 1.3 Message Center Reader: <policy of Message Center Reader>; RoleName 'Message Center Reader'; eligible: permanent allowed True, P365D; active: permanent allowed True, P180D
  Reports Reader: activation max hours 1 -- section 6 activates for at most this long
  ```

---

### 2. The cmdlets

Each write is run twice: first with `-WhatIf` (a guard that failed would print a `What if:` line;
nothing is written), then for real, only once the plan matches. Every read-back waits for Graph to
list what it has just accepted.

- [x] **2.1 A time-bound ELIGIBLE assignment for `oer-s64-user1` on Reports Reader, read back raw.**

  The plan:

  ```powershell
  $New21 = @{ Role = $RoleRR; User = $User1Upn; DurationDays = 3 }
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New21 + @{ WhatIf = $true }) -Label '2.1 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New21 + @{ Confirm = $false }) -Label '2.1 write'
  Show-S64Request
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser1 -Label '2.1-raw' -Want 1
  Get-OEREligibleDirectoryRoleAssignment -Role $RoleRR -User $User1Upn -ErrorAction Stop | ForEach-Object { '    module: ' + (Format-S64Row $_) }
  ```

  **Expect:** the plan: ONE `What if:` line,
  `Performing the operation "Create eligible directory role assignment" on target "eligible directory role 'Reports Reader' for User '<oer-s64-user1's user principal name>' at directory scope '/'"`;
  two requests -- the exact-case role lookup and
  `GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName`
  -- no `groups/` read (a user is never checked for role-assignability) and no policy read (a
  time-bound request is never pre-checked); own verbose lines
  `[New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.`
  and `... Resolved principal to '<oer-s64-user1>'.`; no warning, no error, no object. The write:
  the same two requests, then `POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests`;
  one object,
  `request: Kind Eligible; Action adminAssign; Status <status>; role <Reports Reader>; principal <oer-s64-user1>; scope '/'; expiration 'afterDuration', duration 'P3D', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment'`
  (record the status: `Provisioned` is expected). The raw read: one row, `memberType Direct;
  directoryScopeId '/'; assignmentType (none); status Provisioned`, a window of 3 day(s) -- record
  the expiration type and whether `endDateTime` or `duration` carries it: that is the shape
  `ConvertTo-OERDirectoryRoleAssignment` reads. The module line:
  `<oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; ...; DurationDays 3; end set`.
  **Failure looks like:** a `groups/` or policy request; a POST under `-WhatIf`; Graph refusing the
  body -- record its message verbatim (redacted); the raw window other than 3 days, or the module's
  `DurationDays` other than the raw window rounded; `DurationDays (none)` with an end -- the converter
  misreads Graph's shape.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Provisioned. Graph stores the P3D request as afterDateTime (endDateTime set, no duration); a window of 3 days; the module DurationDays 3.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Create eligible directory role assignment" on target "eligible directory role 'Reports Reader' for User 'person1@example.com' at directory scope '/'".
  === 2.1 plan -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.1 write -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Eligible; Action adminAssign; Status Provisioned; role <Reports Reader>; principal <oer-s64-user1>; scope '/'; expiration 'afterDuration', duration 'P3D', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
  --- 2.1-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 3 day(s)
      module: <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 3; end set
  ```

- [x] **2.2 A time-bound ACTIVE assignment for the role-assignable group on Message Center Reader.**

  The plan:

  ```powershell
  $New22 = @{ Role = $RoleMCR; Group = $RagName; DurationDays = 2 }
  Invoke-S64Call -Cmdlet New-OERActiveDirectoryRoleAssignment -Splat ($New22 + @{ WhatIf = $true }) -Label '2.2 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S64Call -Cmdlet New-OERActiveDirectoryRoleAssignment -Splat ($New22 + @{ Confirm = $false }) -Label '2.2 write'
  Show-S64Request
  $Raw22 = @(Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdRag -Label '2.2-raw' -Want 1)
  $Sched22 = if ($Raw22.Count) { [string]$Raw22[0]['id'] } else { '' }
  ```

  **Expect:** the plan: ONE `What if:` line,
  `Performing the operation "Create active directory role assignment" on target "active directory role 'Message Center Reader' for Group 'oer-s64-rag' at directory scope '/'"`;
  three requests -- the role lookup,
  `GET v1.0/groups?$filter=displayName eq 'oer-s64-rag'&$select=id,displayName` and the
  role-assignable read `GET v1.0/groups/<oer-s64-rag>?$select=id,isAssignableToRole` -- and no
  policy read (time-bound); no warning, no error, no object. The write: the same three, then
  `POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests`; one object,
  `Kind Active; Action adminAssign; ...; principal <oer-s64-rag>; scope '/'; expiration 'afterDuration', duration 'P2D', end set False; justification 'Omnicit.EntraRBAC: directory role active assignment'`.
  The raw read: one row, `memberType Direct; directoryScopeId '/'; assignmentType Assigned`, a
  window of 2 day(s).
  **Failure looks like:** `GroupNotRoleAssignable` -- the group is role-assignable (0.5): the
  role-assignable read misreads Graph; no `groups/<oer-s64-rag>` read -- the check did not run for a
  group; Graph refusing a group principal -- record the message.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. The role-assignable read ran; Provisioned; the raw row listed after one 10 s wait; a window of 2 days.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Create active directory role assignment" on target "active directory role 'Message Center Reader' for Group 'oer-s64-rag' at directory scope '/'".
  === 2.2 plan -- New-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups?$filter=displayName eq 'oer-s64-rag'&$select=id,displayName
      GET v1.0/groups/<oer-s64-rag>?$select=id,isAssignableToRole
  --- the cmdlet's own verbose lines: 2
      [New-OERActiveDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by New-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.2 write -- New-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 4
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups?$filter=displayName eq 'oer-s64-rag'&$select=id,displayName
      GET v1.0/groups/<oer-s64-rag>?$select=id,isAssignableToRole
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OERActiveDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by New-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Active; Action adminAssign; Status Provisioned; role <Message Center Reader>; principal <oer-s64-rag>; scope '/'; expiration 'afterDuration', duration 'P2D', end set False; justification 'Omnicit.EntraRBAC: directory role active assignment'
      (2.2-raw: 0 row(s) listed, waiting -- attempt 1 of 6)
  --- 2.2-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-rag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  2.2 schedule id captured: True
  ```

- [x] **2.3 `GroupNotRoleAssignable` for the plain group -- and NO write request.**

  ```powershell
  $New23 = @{ Role = $RoleRR; Group = $PlainName; DurationDays = 1 }
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New23 + @{ WhatIf = $true }) -Label '2.3 plan'
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New23 + @{ Confirm = $false }) -Label '2.3 for real'
  $P23 = Get-S64RawStatus -Uri "v1.0/groups/$IdPlain`?`$select=id,isAssignableToRole"
  "raw: status $($P23.Status); isAssignableToRole '$($P23.Body['isAssignableToRole'])'"
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdPlain -Label '2.3-raw' -Want 0
  ```

  **Expect:** both runs alike -- NO `What if:` line in the plan (the check runs before
  `ShouldProcess`); three requests, the role lookup,
  `GET v1.0/groups?$filter=displayName eq 'oer-s64-plain'&$select=id,displayName` and
  `GET v1.0/groups/<oer-s64-plain>?$select=id,isAssignableToRole`, and NO `POST`; no object; one
  published error,
  `ERROR [GroupNotRoleAssignable,New-OEREligibleDirectoryRoleAssignment]: Group 'oer-s64-plain' is not role-assignable (isAssignableToRole is false), so it cannot hold a Microsoft Entra directory role. isAssignableToRole can only be set when a group is created: create a role-assignable group (New-OERGroup -RoleAssignable) and assign the role to it.`
  The raw line: `status 200; isAssignableToRole 'False'` or `''` (null) -- the same value 0.5
  recorded; the guard reads both as not role-assignable. The raw schedule read: 0 rows.
  **Failure looks like:** a `POST` line -- the guard did not stop the request (Graph then refuses
  it, or worse accepts it: stop and record); a `What if:` line; a row in the raw read.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. GroupNotRoleAssignable in both runs and no POST; raw isAssignableToRole '' (null); 0 rows.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.3 plan -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/groups?$filter=displayName eq 'oer-s64-plain'&$select=id,displayName
      GET v1.0/groups/<oer-s64-plain>?$select=id,isAssignableToRole
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-plain>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 1 (other records collected, not shown: 0)
      ERROR [GroupNotRoleAssignable,New-OEREligibleDirectoryRoleAssignment]: Group 'oer-s64-plain' is not role-assignable (isAssignableToRole is false), so it cannot hold a Microsoft Entra directory role. isAssignableToRole can only be set when a group is created: create a role-assignable group (New-OERGroup -RoleAssignable) and assign the role to it.
  --- objects returned: 0
  === 2.3 for real -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/groups?$filter=displayName eq 'oer-s64-plain'&$select=id,displayName
      GET v1.0/groups/<oer-s64-plain>?$select=id,isAssignableToRole
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-plain>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 1 (other records collected, not shown: 0)
      ERROR [GroupNotRoleAssignable,New-OEREligibleDirectoryRoleAssignment]: Group 'oer-s64-plain' is not role-assignable (isAssignableToRole is false), so it cannot hold a Microsoft Entra directory role. isAssignableToRole can only be set when a group is created: create a role-assignable group (New-OERGroup -RoleAssignable) and assign the role to it.
  --- objects returned: 0
  raw: status 200; isAssignableToRole ''
  --- 2.3-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-plain>: 0 row(s)
  ```

- [x] **2.4 A user's id passed as `-PrincipalId` passes the role-assignable check: Graph answers 404 for `groups/{id}`.** An ELIGIBLE, time-bound assignment of `oer-s64-user2` on Message Center Reader -- 4.1 and 4.2 rely on it staying.

  The plan, and the raw answer the check expects:

  ```powershell
  $New24 = @{ Role = $RoleMCR; PrincipalId = $IdUser2; DurationDays = 2 }
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New24 + @{ WhatIf = $true }) -Label '2.4 plan'
  $P24 = Get-S64RawStatus -Uri "v1.0/groups/$IdUser2`?`$select=id,isAssignableToRole"
  "raw: groups/<oer-s64-user2> answers status $($P24.Status), error code '$($P24.ErrorCode)'"
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New24 + @{ Confirm = $false }) -Label '2.4 write'
  Show-S64Request
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdMCR -PrincipalId $IdUser2 -Label '2.4-raw' -Want 1
  ```

  **Expect:** the plan: ONE `What if:` line,
  `Performing the operation "Create eligible directory role assignment" on target "eligible directory role 'Message Center Reader' for principal '<the id of oer-s64-user2>' at directory scope '/'"`
  -- `principal`, since a raw id has no type; two requests, the role lookup and
  `GET v1.0/groups/<oer-s64-user2>?$select=id,isAssignableToRole` -- no `users` lookup (the id is
  used as it stands); own verbose lines `Resolved role ...` and
  `... Resolved principal to '<oer-s64-user2>'.` and NO line starting
  `Could not check whether principal` -- the 404 was the declared expected answer, not a failed read;
  no warning, no error, no object. The raw line:
  `raw: groups/<oer-s64-user2> answers status 404, error code 'Request_ResourceNotFound'` (or
  `'ResourceNotFound'`; both are the codes `Get-OERRoleAssignableState` declares). The write: the
  same two requests and one `POST .../roleEligibilityScheduleRequests`; one object,
  `Kind Eligible; Action adminAssign; ...; principal <oer-s64-user2>; ...; duration 'P2D'`. The raw
  read: one row, `memberType Direct`, a window of 2 day(s).
  **Failure looks like:** a `Could not check whether principal ...` verbose line -- Graph answered
  with another code than the two declared (the request still proceeds, but the check reads a
  failure where it should read "not a group": record the raw code); `GroupNotRoleAssignable`; a
  `users` request.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. groups/<oer-s64-user2> answered 404 Request_ResourceNotFound; no "Could not check" line; Provisioned; a window of 2 days.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Create eligible directory role assignment" on target "eligible directory role 'Message Center Reader' for principal '00000000-0000-0000-0000-000000000006' at directory scope '/'".
  === 2.4 plan -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups/<oer-s64-user2>?$select=id,isAssignableToRole
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  raw: groups/<oer-s64-user2> answers status 404, error code 'Request_ResourceNotFound'
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.4 write -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups/<oer-s64-user2>?$select=id,isAssignableToRole
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Eligible; Action adminAssign; Status Provisioned; role <Message Center Reader>; principal <oer-s64-user2>; scope '/'; expiration 'afterDuration', duration 'P2D', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
  --- 2.4-raw: raw roleEligibilitySchedules of <Message Center Reader> for <oer-s64-user2>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  ```

- [x] **2.5 `PermanentAssignmentNotAllowed`: Message Center Reader's policy set to refuse permanent active assignments, then a permanent request -- no write of any kind, and the policy unchanged by it.**

  The plan for the policy:

  ```powershell
  Invoke-S64Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleMCR; AllowPermanentActiveAssignment = $false; WhatIf = $true } -Label '2.5a plan'
  ```

  The policy write, only once the plan matches; then the refused request, plan and real:

  ```powershell
  Invoke-S64Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat @{ Role = $RoleMCR; AllowPermanentActiveAssignment = $false; Confirm = $false } -Label '2.5a write'
  Show-S64Policy -Policy ($S64Out | Select-Object -First 1) -Label '2.5a returned'
  $Before25 = Get-S64RawPolicy -RoleDefinitionId $RoleIdMCR -Label '2.5-before-raw'
  $New25 = @{ Role = $RoleMCR; User = $User1Upn; Permanent = $true }
  Invoke-S64Call -Cmdlet New-OERActiveDirectoryRoleAssignment -Splat ($New25 + @{ WhatIf = $true }) -Label '2.5b plan'
  Invoke-S64Call -Cmdlet New-OERActiveDirectoryRoleAssignment -Splat ($New25 + @{ Confirm = $false }) -Label '2.5b for real'
  $After25 = Get-S64RawPolicy -RoleDefinitionId $RoleIdMCR -Label '2.5-after-raw'
  "Message Center Reader rules differing from the read before the request: $(@(Get-S64RuleDiff -Live $After25.Rules -Baseline $Before25.Rules).Count)"
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdUser1 -Label '2.5-raw' -Want 0
  ```

  **Expect:** 2.5a plan: ONE `What if:` line,
  `Performing the operation "Update rules: Expiration_Admin_Assignment" on target "directory role management policy '<the policy id of Message Center Reader>'"`;
  two requests (the role lookup and the policy-assignment read); no warning. 2.5a write: the same
  two, then `PATCH v1.0/policies/roleManagementPolicies/<policy of Message Center Reader>/rules/Expiration_Admin_Assignment`;
  one object, `active: permanent allowed False, <1.3's ActiveDuration>; ChangedRuleIds [Expiration_Admin_Assignment]`.
  2.5b, both runs alike: NO `What if:` line (the pre-check runs before `ShouldProcess`); three
  requests -- the role lookup, the `users` lookup and
  `GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Message Center Reader>'&$expand=policy($expand=rules)`
  -- and NO `POST` and NO `PATCH`; no object; one published error,
  `ERROR [PermanentAssignmentNotAllowed,New-OERActiveDirectoryRoleAssignment]: The PIM policy of Microsoft Entra directory role 'Message Center Reader' does not allow permanent active assignments, so Microsoft Graph would refuse this one, and Omnicit.EntraRBAC never changes a policy implicitly. Nothing was changed. Allow it first with Set-OERDirectoryRoleManagementPolicy -Role 'Message Center Reader' -AllowPermanentActiveAssignment $true, or declare allowPermanentActiveAssignment: true for the role under directoryRoleManagementPolicies in the same apply document (that section runs first), or pass -DurationDays for a time-bound assignment.`
  Then `rules differing from the read before the request: 0` and the raw schedule read: 0 rows.
  The certificate identity's own Message Center Reader assignment and `oer-s64-ccrag`'s are
  time-bound and are not affected by the changed rule.
  **Failure looks like:** a `POST` or `PATCH` in 2.5b -- the policy was opened implicitly or the
  request was sent; a count above `0`; a row in the raw read. A `NoChange` error in 2.5a: 1.3
  recorded permanent active already refused -- carry on to 2.5b, and record it.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. One PATCH, Expiration_Admin_Assignment; PermanentAssignmentNotAllowed in both runs with no POST or PATCH; rules differing 0; 0 rows.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: Expiration_Admin_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004'".
  === 2.5a plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Message Center Reader>'&$expand=policy($expand=rules)
  --- the cmdlet's own verbose lines: 2
      [Set-OERDirectoryRoleManagementPolicy] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [Set-OERDirectoryRoleManagementPolicy] Policy id: '<policy of Message Center Reader>'.
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.5a write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Message Center Reader>'&$expand=policy($expand=rules)
      PATCH v1.0/policies/roleManagementPolicies/<policy of Message Center Reader>/rules/Expiration_Admin_Assignment
  --- the cmdlet's own verbose lines: 2
      [Set-OERDirectoryRoleManagementPolicy] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [Set-OERDirectoryRoleManagementPolicy] Policy id: '<policy of Message Center Reader>'.
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 2.5a returned: <policy of Message Center Reader>; RoleName 'Message Center Reader'; eligible: permanent allowed True, P365D; active: permanent allowed False, P180D; ChangedRuleIds [Expiration_Admin_Assignment]
  === 2.5b plan -- New-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Message Center Reader>'&$expand=policy($expand=rules)
  --- the cmdlet's own verbose lines: 2
      [New-OERActiveDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by New-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 0)
      ERROR [PermanentAssignmentNotAllowed,New-OERActiveDirectoryRoleAssignment]: The PIM policy of Microsoft Entra directory role 'Message Center Reader' does not allow permanent active assignments, so Microsoft Graph would refuse this one, and Omnicit.EntraRBAC never changes a policy implicitly. Nothing was changed. Allow it first with Set-OERDirectoryRoleManagementPolicy -Role 'Message Center Reader' -AllowPermanentActiveAssignment $true, or declare allowPermanentActiveAssignment: true for the role under directoryRoleManagementPolicies in the same apply document (that section runs first), or pass -DurationDays for a time-bound assignment.
  --- objects returned: 0
  === 2.5b for real -- New-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Message Center Reader>'&$expand=policy($expand=rules)
  --- the cmdlet's own verbose lines: 2
      [New-OERActiveDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by New-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 0)
      ERROR [PermanentAssignmentNotAllowed,New-OERActiveDirectoryRoleAssignment]: The PIM policy of Microsoft Entra directory role 'Message Center Reader' does not allow permanent active assignments, so Microsoft Graph would refuse this one, and Omnicit.EntraRBAC never changes a policy implicitly. Nothing was changed. Allow it first with Set-OERDirectoryRoleManagementPolicy -Role 'Message Center Reader' -AllowPermanentActiveAssignment $true, or declare allowPermanentActiveAssignment: true for the role under directoryRoleManagementPolicies in the same apply document (that section runs first), or pass -DurationDays for a time-bound assignment.
  --- objects returned: 0
  Message Center Reader rules differing from the read before the request: 0
  --- 2.5-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-user1>: 0 row(s)
  ```

- [x] **2.6 Remove by pipeline from Get -- and a named principal alongside the pipe is refused.** Removes 2.1's assignment.

  The plan, and the refusal:

  ```powershell
  $Rows26 = @(Get-OEREligibleDirectoryRoleAssignment -Role $RoleRR -User $User1Upn -ErrorAction Stop)
  "rows piped: $($Rows26.Count)"; $Rows26 | ForEach-Object { '    ' + (Format-S64Row $_) }
  Invoke-S64Call -Cmdlet Remove-OEREligibleDirectoryRoleAssignment -Splat @{ User = $User2Upn; WhatIf = $true } -InputObject $Rows26 -Label '2.6a a named principal and the pipe'
  Invoke-S64Call -Cmdlet Remove-OEREligibleDirectoryRoleAssignment -Splat @{ WhatIf = $true } -InputObject $Rows26 -Label '2.6b plan'
  ```

  The removal, only once the plan matches:

  ```powershell
  Invoke-S64Call -Cmdlet Remove-OEREligibleDirectoryRoleAssignment -Splat @{ Confirm = $false } -InputObject $Rows26 -Label '2.6b remove'
  Show-S64Request
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser1 -Label '2.6-raw' -Want 0
  "module rows left: $(@(Get-OEREligibleDirectoryRoleAssignment -Role $RoleRR -User $User1Upn -ErrorAction Stop).Count)"
  ```

  **Expect:** `rows piped: 1` -- 2.1's row. 2.6a: NO `What if:` line, NO request, no object, one
  published error,
  `ERROR [AmbiguousPrincipal,Remove-OEREligibleDirectoryRoleAssignment]: A principal was supplied by name while objects carrying their own PrincipalId '<oer-s64-user1>' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and each piped item's own principal would lose its eligible assignment instead. Supply either the named principal or the pipeline, not both.`
  2.6b plan: NO request -- the piped `RoleDefinitionId` binds `-Role` and is a GUID, the piped
  `PrincipalId` is used as it stands -- and ONE `What if:` line,
  `Performing the operation "Remove eligible directory role assignment" on target "eligible directory role '<the role definition id of Reports Reader>' for principal '<the id of oer-s64-user1>' at directory scope '/'"`;
  no warning. The removal: ONE request,
  `POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests`; one warning,
  `WARNING: Removing eligible directory role '<Reports Reader>' for principal '<oer-s64-user1>' at directory scope '/'.`;
  one object, `Kind Eligible; Action adminRemove; Status <status>; ...; expiration '', duration '', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment removal'`
  (record the status; `Revoked` is expected). The raw read: 0 rows; `module rows left: 0`.
  **Failure looks like:** a removal in 2.6a -- the named principal was ignored silently, or
  `oer-s64-user2` lost something (it has no Reports Reader assignment yet: the raw read of 4.1a
  would show it); a lookup request in 2.6b; Graph refusing an `adminRemove` without a schedule --
  record its message; a row left.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. AmbiguousPrincipal with no request; the plan with no request; the removal Revoked; 0 rows left.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  rows piped: 1
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 3; end set
  === 2.6a a named principal and the pipe -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 0
  --- warnings: 0
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 1 (other records collected, not shown: 0)
      ERROR [AmbiguousPrincipal,Remove-OEREligibleDirectoryRoleAssignment]: A principal was supplied by name while objects carrying their own PrincipalId '<oer-s64-user1>' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and each piped item's own principal would lose its eligible assignment instead. Supply either the named principal or the pipeline, not both.
  --- objects returned: 0
  What if: Performing the operation "Remove eligible directory role assignment" on target "eligible directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000005' at directory scope '/'".
  === 2.6b plan -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 2.6b remove -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 1
      WARNING: Removing eligible directory role '<Reports Reader>' for principal '<oer-s64-user1>' at directory scope '/'.
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Eligible; Action adminRemove; Status Revoked; role <Reports Reader>; principal <oer-s64-user1>; scope '/'; expiration '', duration '', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment removal'
  --- 2.6-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 0 row(s)
  module rows left: 0
  ```

- [x] **2.7 `-Action adminUpdate` changes a window.** 2.2's active assignment of `oer-s64-rag` on Message Center Reader, from two days to four.

  The plan:

  ```powershell
  $New27 = @{ Role = $RoleMCR; Group = $RagName; DurationDays = 4; Action = 'adminUpdate' }
  Invoke-S64Call -Cmdlet New-OERActiveDirectoryRoleAssignment -Splat ($New27 + @{ WhatIf = $true }) -Label '2.7 plan'
  ```

  The write, only once the plan matches:

  ```powershell
  Invoke-S64Call -Cmdlet New-OERActiveDirectoryRoleAssignment -Splat ($New27 + @{ Confirm = $false }) -Label '2.7 write'
  Show-S64Request
  $Raw27 = @(Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdRag -Label '2.7-raw' -Want 1 -WantWindowDays 4)
  "the schedule id is 2.2's: $($Raw27.Count -eq 1 -and [string]$Raw27[0]['id'] -eq $Sched22)"
  ```

  **Expect:** the plan: ONE `What if:` line,
  `Performing the operation "Update active directory role assignment" on target "active directory role 'Message Center Reader' for Group 'oer-s64-rag' at directory scope '/'"`;
  the same three requests as 2.2's plan; no error. The write: those three and one
  `POST .../roleAssignmentScheduleRequests`; one object, `Kind Active; Action adminUpdate; ...; duration 'P4D'`.
  The raw read: still exactly ONE row, `memberType Direct; assignmentType Assigned`, a window of 4
  day(s). The last line: record `True` or `False` -- whether Graph updates a schedule in place or
  replaces it is a measurement; the engine matches on role, principal and kind, never on the
  schedule id.
  **Failure looks like:** Graph refusing `adminUpdate` -- record its message; two rows (the old
  window kept beside the new one: section 3's convergence would then depend on which row the read
  lists first -- record it); a window of 2 days after the wait.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. adminUpdate Provisioned; still ONE row, a window of 4 days. "the schedule id is 2.2's: False" -- Graph replaced the schedule instead of updating it in place (measurement; the engine never matches on the schedule id).

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update active directory role assignment" on target "active directory role 'Message Center Reader' for Group 'oer-s64-rag' at directory scope '/'".
  === 2.7 plan -- New-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups?$filter=displayName eq 'oer-s64-rag'&$select=id,displayName
      GET v1.0/groups/<oer-s64-rag>?$select=id,isAssignableToRole
  --- the cmdlet's own verbose lines: 2
      [New-OERActiveDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by New-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 2.2-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-rag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  === 2.7 write -- New-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 4
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups?$filter=displayName eq 'oer-s64-rag'&$select=id,displayName
      GET v1.0/groups/<oer-s64-rag>?$select=id,isAssignableToRole
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OERActiveDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by New-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Active; Action adminUpdate; Status Provisioned; role <Message Center Reader>; principal <oer-s64-rag>; scope '/'; expiration 'afterDuration', duration 'P4D', end set False; justification 'Omnicit.EntraRBAC: directory role active assignment'
  --- 2.7-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-rag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 4 day(s)
  the schedule id is 2.2's: False
  ```

---

### 3. The document -- `directoryRoleAssignments[]`

The document declares Reports Reader for `oer-s64-user1` and for the role-assignable group, both
kinds, time-bound and permanent. The two permanent entries can only be created because the same
document opens Reports Reader's policy for permanent assignments first: 3.1 closes it through the
Set cmdlet before the document runs, so the ordering is visible.

```powershell
$Pol3 = [ordered]@{ role = $RoleRR; allowPermanentEligibility = $true; allowPermanentActiveAssignment = $true }
$E1 = New-S64Entry -Role $RoleRR -Principal $User1Upn -Kind Eligible -Days 5
$E2 = New-S64Entry -Role $RoleRR -Principal $User1Upn -Kind Active -Permanent
$E3 = New-S64Entry -Role $RoleRR -Principal $RagName -Type Group -Kind Eligible   # neither durationDays nor permanent: permanent
$E4 = New-S64Entry -Role $RoleRR -Principal $RagName -Type Group -Kind Active -Days 5
$Doc3 = New-S64Doc -Policy $Pol3 -Assignment $E1, $E2, $E3, $E4
```

- [x] **3.1 The policy is opened BEFORE the assignments are created.**

  First close Reports Reader's policy -- the plan, then the write once the plan matches:

  ```powershell
  $Close31 = @{ Role = $RoleRR; AllowPermanentEligibility = $false; AllowPermanentActiveAssignment = $false }
  Invoke-S64Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat ($Close31 + @{ WhatIf = $true }) -Label '3.1a plan'
  ```

  ```powershell
  Invoke-S64Call -Cmdlet Set-OERDirectoryRoleManagementPolicy -Splat ($Close31 + @{ Confirm = $false }) -Label '3.1a write'
  Show-S64Policy -Policy ($S64Out | Select-Object -First 1) -Label '3.1a returned'
  ```

  The document's plan:

  ```powershell
  Invoke-S64Check -Id '3.1b' -Json $Doc3
  ```

  The apply, only once the plan matches, and the read-back:

  ```powershell
  Invoke-S64Check -Id '3.1c' -Json $Doc3 -Apply
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser1 -Label '3.1-user1-eligible-raw' -Want 1
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser1 -Label '3.1-user1-active-raw' -Want 1
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdRag -Label '3.1-rag-eligible-raw' -Want 1
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdRR -PrincipalId $IdRag -Label '3.1-rag-active-raw' -Want 1
  Show-S64State -State @(Get-S64State) -Label '3.1 after' -Role $RoleRR
  Show-S64Policy -Policy (Get-OERDirectoryRoleManagementPolicy -Role $RoleRR -ErrorAction Stop) -Label '3.1 policy after'
  ```

  **Expect:** 3.1a plan: ONE `What if:` line,
  `"Update rules: Expiration_Admin_Eligibility, Expiration_Admin_Assignment" on target "directory role management policy '<the policy id of Reports Reader>'"`
  (the policy's own rule order); two requests. The write: the two, then two `PATCH`es in that
  order; one object, `eligible: permanent allowed False, ...; active: permanent allowed False, ...; ChangedRuleIds [Expiration_Admin_Eligibility, Expiration_Admin_Assignment]`.
  3.1b: `Valid = True, findings = 0`; no warning, no error; five rows, in this order:
  `[directoryRoleManagementPolicies] Reports Reader | Skipped | would update directory role management policy for 'Reports Reader' (allowPermanentEligibility=True, allowPermanentActiveAssignment=True)`,
  `[directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Skipped | would create the eligible assignment (time-bound assignment (5 days) is absent)`,
  `... oer-s64-user1@<test domain> (Active) | Skipped | would create the active assignment (permanent assignment is absent)`,
  `... oer-s64-rag (Eligible) | Skipped | would create the eligible assignment (permanent assignment is absent)`,
  `... oer-s64-rag (Active) | Skipped | would create the active assignment (time-bound assignment (5 days) is absent)`;
  `Skipped=5`, and no `Extra` row -- neither Reports Reader pair holds a direct assignment the
  document does not declare. Before the results, the run prints one `What if:` line per row: the
  policy's, `"Update directory role management policy" on target "Reports Reader"`, and for each
  assignment its row label as the target, with the operation
  `create eligible directory role assignment` or `create active directory role assignment`.
  3.1c: the same five rows with `Updated`
  (`updated directory role management policy for 'Reports Reader' (allowPermanentEligibility=True, allowPermanentActiveAssignment=True)`)
  FIRST, then four `Created` (`created the eligible assignment (time-bound assignment (5 days) is absent)`,
  `created the active assignment (permanent assignment is absent)`, and so on); `Updated=1,
  Created=4`; no warning, no error -- in particular no `PermanentAssignmentNotAllowed`: the policy
  row ran first and opened the policy, and the permanent pre-check read it open. The raw reads: one
  row each, `memberType Direct`; user1's eligible and the group's active a window of 5 day(s), the
  other two `expiration type noExpiration ... window never ends`. The state: Reports Reader
  Eligible `<oer-s64-rag> (Group); MemberType Direct; ...; DurationDays (none); end never` and
  `<oer-s64-user1> (User); MemberType Direct; ...; DurationDays 5; end set`; Active the same two
  with `Assigned`, the group time-bound and user1 permanent. Rows for `<oer-s64-user2>` with
  `MemberType Group` may appear too (a member of the group): record them, 4.4 measures exactly that.
  The policy after: both permanent kinds allowed again.
  **Failure looks like:** a `Failed` row with `PermanentAssignmentNotAllowed` -- the assignment ran
  before the policy, or the pre-check read a stale policy (record Graph's timing); Graph refusing a
  permanent request after the policy was opened -- record the message (a propagation delay is a
  finding, not a pass); an `Extra` row; the rows in another order.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. The policy closed (two PATCHes in rule order); the plan Skipped=5 in order, no Extra; the apply Updated=1 then Created=4, no PermanentAssignmentNotAllowed; the raw windows as expected; the role-wide read lists no MemberType Group row.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Update rules: Expiration_Admin_Eligibility, Expiration_Admin_Assignment" on target "directory role management policy 'DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002'".
  === 3.1a plan -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Reports Reader>'&$expand=policy($expand=rules)
  --- the cmdlet's own verbose lines: 2
      [Set-OERDirectoryRoleManagementPolicy] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [Set-OERDirectoryRoleManagementPolicy] Policy id: '<policy of Reports Reader>'.
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.1a write -- Set-OERDirectoryRoleManagementPolicy
  --- requests, in the order sent: 4
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Reports Reader>'&$expand=policy($expand=rules)
      PATCH v1.0/policies/roleManagementPolicies/<policy of Reports Reader>/rules/Expiration_Admin_Eligibility
      PATCH v1.0/policies/roleManagementPolicies/<policy of Reports Reader>/rules/Expiration_Admin_Assignment
  --- the cmdlet's own verbose lines: 2
      [Set-OERDirectoryRoleManagementPolicy] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [Set-OERDirectoryRoleManagementPolicy] Policy id: '<policy of Reports Reader>'.
  --- warnings: 0
  --- errors published by Set-OERDirectoryRoleManagementPolicy: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  --- 3.1a returned: <policy of Reports Reader>; RoleName 'Reports Reader'; eligible: permanent allowed False, P365D; active: permanent allowed False, P180D; ChangedRuleIds [Expiration_Admin_Eligibility, Expiration_Admin_Assignment]
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.1b
      {
        "version": "1.0",
        "tenantAlias": "<Alias>",
        "directoryRoleManagementPolicies": [
          {
            "role": "Reports Reader",
            "allowPermanentEligibility": true,
            "allowPermanentActiveAssignment": true
          }
        ],
        "directoryRoleAssignments": [
          {
            "role": "Reports Reader",
            "principal": "oer-s64-user1@<test domain>",
            "assignmentType": "Eligible",
            "durationDays": 5
          },
          {
            "role": "Reports Reader",
            "principal": "oer-s64-user1@<test domain>",
            "assignmentType": "Active",
            "permanent": true
          },
          {
            "role": "Reports Reader",
            "principal": "oer-s64-rag",
            "principalType": "Group",
            "assignmentType": "Eligible"
          },
          {
            "role": "Reports Reader",
            "principal": "oer-s64-rag",
            "principalType": "Group",
            "assignmentType": "Active",
            "durationDays": 5
          }
        ]
      }
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  What if: Performing the operation "Update directory role management policy" on target "Reports Reader".
  What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> person1@example.com (Eligible)".
  What if: Performing the operation "create active directory role assignment" on target "Reports Reader -> person1@example.com (Active)".
  What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> oer-s64-rag (Eligible)".
  What if: Performing the operation "create active directory role assignment" on target "Reports Reader -> oer-s64-rag (Active)".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Skipped | would update directory role management policy for 'Reports Reader' (allowPermanentEligibility=True, allowPermanentActiveAssignment=True)
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Skipped | would create the eligible assignment (time-bound assignment (5 days) is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Skipped | would create the active assignment (permanent assignment is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Skipped | would create the eligible assignment (permanent assignment is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Skipped | would create the active assignment (time-bound assignment (5 days) is absent)
  --- action counts: Skipped=5
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.1c
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
  --- action counts: Created=4, Updated=1
  --- 3.1-user1-eligible-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  --- 3.1-user1-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  --- 3.1-rag-eligible-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-rag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  --- 3.1-rag-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-rag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  --- 3.1 after: Reports Reader, Eligible: 2 row(s)
      <oer-s64-rag> (Group); MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
  --- 3.1 after: Reports Reader, Active: 2 row(s)
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  --- 3.1 policy after: <policy of Reports Reader>; RoleName 'Reports Reader'; eligible: permanent allowed True, P365D; active: permanent allowed True, P180D
      [directoryRoleManagementPolicies] Reports Reader | Updated | updated directory role management policy for 'Reports Reader' (allowPermanentEligibility=True, allowPermanentActiveAssignment=True)
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Created | created the eligible assignment (time-bound assignment (5 days) is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Created | created the active assignment (permanent assignment is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Created | created the eligible assignment (permanent assignment is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Created | created the active assignment (time-bound assignment (5 days) is absent)
  ```

- [x] **3.2 The same document again: only `Unchanged` -- the proof that Graph's windows converge (G11).**

  The plan, then the apply once the plan matches:

  ```powershell
  Invoke-S64Check -Id '3.2a' -Json $Doc3
  ```

  ```powershell
  Invoke-S64Check -Id '3.2b' -Json $Doc3 -Apply
  "the session holds an Azure Resource Manager token: $([bool](& (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.ArmToken }))"
  ```

  **Expect:** both runs: five rows, the policy
  `[directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'`
  and the four assignment rows `| Unchanged | assignment matches`; `action counts: Unchanged=5`; no
  `What if:` line, no warning, no error. Then
  `the session holds an Azure Resource Manager token: False` -- three directory-only apply runs
  asked for none.
  **Failure looks like:** any `Created` -- the read did not list 3.1's assignment (wait a minute and
  run 3.2a again; if it persists, record it: an assignment the read misses is re-created every run);
  `Updated` -- the live window rounds to another number of days than was declared: record the raw
  window from 3.1; an ARM token `True`.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Both runs Unchanged=5; no Azure Resource Manager token.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.2a
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Unchanged=5
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.2b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Unchanged=5
  the session holds an Azure Resource Manager token: False
  ```

- [x] **3.3 A changed `durationDays` is `Updated` with `adminUpdate`, and the run after it is `Unchanged`.** `oer-s64-user1`'s eligible assignment from five days to seven. Run 3.3b at least five minutes after 3.1c (Run order).

  ```powershell
  $E1 = New-S64Entry -Role $RoleRR -Principal $User1Upn -Kind Eligible -Days 7
  $Doc33 = New-S64Doc -Policy $Pol3 -Assignment $E1, $E2, $E3, $E4
  Invoke-S64Check -Id '3.3a' -Json $Doc33
  ```

  The apply, only once the plan matches, and the read-back:

  ```powershell
  Invoke-S64Check -Id '3.3b' -Json $Doc33 -Apply
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser1 -Label '3.3-raw' -Want 1 -WantWindowDays 7
  ```

  The third run -- the plan, then the apply once the plan matches:

  ```powershell
  Invoke-S64Check -Id '3.3c' -Json $Doc33
  ```

  ```powershell
  Invoke-S64Check -Id '3.3d' -Json $Doc33 -Apply
  ```

  **Expect:** 3.3a: the policy and three assignments `Unchanged`, and
  `Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Skipped | would update the eligible assignment (duration differs (live 5 days, declared 7 days))`,
  and one `What if:` line, with the operation `update eligible directory role assignment`.
  3.3b: that row `Updated`,
  `updated the eligible assignment (duration differs (live 5 days, declared 7 days))` -- the
  engine re-issued the window with `adminUpdate`, never a removal; `Unchanged=4, Updated=1`. The raw
  read: still exactly ONE direct row, a window of 7 day(s). 3.3c and 3.3d: `Unchanged=5`, no
  `What if:` line.
  **Failure looks like:** `Created` instead of `Updated` -- the live row was not matched; two rows in
  the raw read; 3.3c not `Unchanged` -- the new window does not converge: record the raw window.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  **FAIL.** 3.3a as expected (would update, live 5 days, declared 7). 3.3b: Graph refused the engine's adminUpdate of oer-s64-user1's ELIGIBLE Reports Reader assignment with "ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes." (HTTP 400); the row Failed, 12 error records, the raw window still 5 days. 3.3c planned the same update again, so 3.3d was not run. Diagnosis, two probes on prefixed test objects and the two roles: the same request with afterDateTime instead of afterDuration, sent raw, got the same 400; the module's adminUpdate of oer-s64-user2's eligible Message Center Reader assignment (2 -> 3 days), a principal with NO active assignment of that role, was Provisioned. So Graph refuses an eligible adminUpdate while the same principal holds an ACTIVE assignment of the same role (oer-s64-user1 holds Reports Reader active and permanent since 3.1): a document declaring both kinds for one principal cannot converge a changed eligible window. Module finding for the follow-up.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3a
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  What if: Performing the operation "update eligible directory role assignment" on target "Reports Reader -> person1@example.com (Eligible)".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Skipped | would update the eligible assignment (duration differs (live 5 days, declared 7 days))
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Skipped=1, Unchanged=4
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 12
      ERROR []:
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: BadRequest (Bad Request).
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: BadRequest (Bad Request).
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR []:
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR []:
      ERROR [ActiveDurationTooShort,New-OEREligibleDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort,New-OEREligibleDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort,Invoke-OERStructure]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Failed | failed to update the eligible assignment: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Failed=1, Unchanged=4
      (3.3-raw: 1 row(s) listed, waiting -- attempt 1 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 2 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 3 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 4 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 5 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 6 of 6)
  --- 3.3-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  ##### step  +code -- 2026-09-29 22:27:41
  diagnostic adminUpdate afterDateTime: status 400; request status ''; error 'ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.'
      (3.3-diag-raw: 1 row(s) listed, waiting -- attempt 1 of 6)
      (3.3-diag-raw: 1 row(s) listed, waiting -- attempt 2 of 6)
      (3.3-diag-raw: 1 row(s) listed, waiting -- attempt 3 of 6)
      (3.3-diag-raw: 1 row(s) listed, waiting -- attempt 4 of 6)
      (3.3-diag-raw: 1 row(s) listed, waiting -- attempt 5 of 6)
      (3.3-diag-raw: 1 row(s) listed, waiting -- attempt 6 of 6)
  --- 3.3-diag-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  ##### step  +code -- 2026-09-29 22:29:10
  What if: Performing the operation "Update eligible directory role assignment" on target "eligible directory role 'Message Center Reader' for principal '00000000-0000-0000-0000-000000000006' at directory scope '/'".
  === diag plan: user2 MCR eligible 2 -> 3 days -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups/<oer-s64-user2>?$select=id,isAssignableToRole
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  === diag write: user2 MCR eligible 2 -> 3 days -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/groups/<oer-s64-user2>?$select=id,isAssignableToRole
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Message Center Reader' to '<Message Center Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Eligible; Action adminUpdate; Status Provisioned; role <Message Center Reader>; principal <oer-s64-user2>; scope '/'; expiration 'afterDuration', duration 'P3D', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
  --- diag-user2-mcr-raw: raw roleEligibilitySchedules of <Message Center Reader> for <oer-s64-user2>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 3 day(s)
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
      (3.3-raw: 1 row(s) listed, waiting -- attempt 1 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 2 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 3 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 4 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 5 of 6)
      (3.3-raw: 1 row(s) listed, waiting -- attempt 6 of 6)
  --- 3.3-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  === 3.3c
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  What if: Performing the operation "update eligible directory role assignment" on target "Reports Reader -> person1@example.com (Eligible)".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Skipped | would update the eligible assignment (duration differs (live 5 days, declared 7 days))
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Skipped=1, Unchanged=4
  ```

  **Follow-up (CC as oer-live-cc, 2026-09-30, redacted per docs/live-verification/README.md): PASS on re-run; the first run's refusal is a Graph timing rule, measured.** Graph refuses to update or remove ANY of a principal's assignments of a role (either kind) with ActiveDurationTooShort until the principal's ACTIVE assignment of that role has run for five minutes; a create is never refused. The first 3.3b ran two minutes after 3.1c created oer-s64-user1's active assignment. Measured on oer-s64-user1 and Reports Reader: M.2 adminUpdate WITH targetScheduleId, active 16 min old (time-bound): 201; M.3 control WITHOUT targetScheduleId, 16 min: 201 -- targetScheduleId is not the lever; M.4 active updated to permanent: 201, and Graph removed the eligible assignment by itself (no request); M.6 adminUpdate with targetScheduleId, active 3 min old (permanent): 400; M.7 the same without startDateTime: 400 (the one variant allowed); the re-run 3.3b 14 min after the active's start: Updated (and Graph had removed the permanent active assignment by itself; the item re-created it); 3.3c and 3.3d Unchanged=5 twice (convergence). 3.3e/3.3f: an eight-day window 2.6 min after the active's start was refused and the row named the refusal (wording of efbafde; 9884c8c states the five-minute rule, unit-pinned). Teardown T.1 confirms it for adminRemove: refused at 3.7 min, accepted at 8 min. The write path is unchanged (no targetScheduleId, never a remove plus a re-create); the Failed row now names the rule and says to apply again in five minutes.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === M.1 write: recreate user1 eligible (5 days) -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Eligible; Action adminAssign; Status Provisioned; role <Reports Reader>; principal <oer-s64-user1>; scope '/'; expiration 'afterDuration', duration 'P5D', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
  --- M.1-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  eligibility schedule id captured: True
  --- M.1-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
  user1 holds Reports Reader active (direct) at the same time: True
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  M.2 request: POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
      {
    "action": "adminUpdate",
    "principalId": "<oer-s64-user1>",
    "roleDefinitionId": "<Reports Reader>",
    "directoryScopeId": "/",
    "justification": "Omnicit.EntraRBAC live measurement 3.3: adminUpdate with targetScheduleId",
    "targetScheduleId": "<not a test object>",
    "scheduleInfo": {
      "startDateTime": "<now, UTC>",
      "expiration": {
        "type": "afterDuration",
        "duration": "P7D"
      }
    }
  }
  targetScheduleId is the eligibility schedule of <oer-s64-user1> on <Reports Reader>: True
  M.2 answer: HTTP 201; request status 'Provisioned'; action 'adminUpdate'; targetScheduleId echoed is the schedule: False; error ''
  --- M.2-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 7 day(s)
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  M.3 control request (no targetScheduleId): POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
      {
    "action": "adminUpdate",
    "principalId": "<oer-s64-user1>",
    "roleDefinitionId": "<Reports Reader>",
    "directoryScopeId": "/",
    "justification": "Omnicit.EntraRBAC live measurement 3.3: control without targetScheduleId",
    "scheduleInfo": {
      "startDateTime": "<now, UTC>",
      "expiration": {
        "type": "afterDuration",
        "duration": "P6D"
      }
    }
  }
  M.3 answer: HTTP 201; request status 'Provisioned'; error ''
  --- M.3-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 6 day(s)
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === M.4 write: user1 active 1 day -> permanent (eligible present) -- New-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 4
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      GET v1.0/policies/roleManagementPolicyAssignments?$filter=scopeId eq '/' and scopeType eq 'DirectoryRole' and roleDefinitionId eq '<Reports Reader>'&$expand=policy($expand=rules)
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OERActiveDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by New-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Active; Action adminUpdate; Status Provisioned; role <Reports Reader>; principal <oer-s64-user1>; scope '/'; expiration 'noExpiration', duration '', end set False; justification 'Omnicit.EntraRBAC: directory role active assignment'
  --- M.4-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 0 row(s)
  --- M.4-eligible-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 0 row(s)
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- M.4b-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  --- M.4b-eligible-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 0 row(s)
  --- M.4b state: Reports Reader, Eligible: 0 row(s)
  --- M.4b state: Reports Reader, Active: 1 row(s)
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  roleEligibilityScheduleRequests for <oer-s64-user1> on <Reports Reader>: status 200; 7 request(s)
      created 09/29/2026 20:18:11; action adminAssign; status Provisioned; expiration afterDuration P3D
      created 09/29/2026 20:21:02; action adminRemove; status Revoked; expiration
      created 09/29/2026 20:23:07; action adminAssign; status Provisioned; expiration afterDuration P5D
      created 09/30/2026 06:44:26; action adminRemove; status Revoked; expiration
      created 09/30/2026 07:00:31; action adminAssign; status Provisioned; expiration afterDuration P5D
      created 09/30/2026 07:01:21; action adminUpdate; status Provisioned; expiration afterDuration P7D
      created 09/30/2026 07:01:50; action adminUpdate; status Provisioned; expiration afterDuration P6D
  roleAssignmentScheduleRequests for <oer-s64-user1> on <Reports Reader>: status 200; 3 request(s)
      created 09/29/2026 20:23:09; action adminAssign; status Provisioned; expiration noExpiration
      created 09/30/2026 06:45:09; action adminUpdate; status Provisioned; expiration afterDuration P1D
      created 09/30/2026 07:02:52; action adminUpdate; status Provisioned; expiration noExpiration
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  roleEligibilitySchedules for <oer-s64-user1> on <Reports Reader>: status 200; rows 0
  roleEligibilityScheduleInstances for <oer-s64-user1> on <Reports Reader>: status 200; rows 0
  roleAssignmentSchedules for <oer-s64-user1> on <Reports Reader>: status 200; rows 1; memberType Direct
  roleAssignmentScheduleInstances for <oer-s64-user1> on <Reports Reader>: status 200; rows 1; memberType Direct
  the M.1 eligibility schedule read by id: status 404 UnknownError
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === M.5 write: user1 eligible 5 days while active is permanent -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      request: Kind Eligible; Action adminAssign; Status Provisioned; role <Reports Reader>; principal <oer-s64-user1>; scope '/'; expiration 'afterDuration', duration 'P5D', end set False; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
  --- M.5-eligible-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  --- M.5-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  M.6 request: POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
      {
    "action": "adminUpdate",
    "principalId": "<oer-s64-user1>",
    "roleDefinitionId": "<Reports Reader>",
    "directoryScopeId": "/",
    "justification": "Omnicit.EntraRBAC live measurement 3.3: adminUpdate with targetScheduleId, active permanent",
    "targetScheduleId": "<not a test object>",
    "scheduleInfo": {
      "startDateTime": "<now, UTC>",
      "expiration": {
        "type": "afterDuration",
        "duration": "P7D"
      }
    }
  }
  targetScheduleId is the eligibility schedule of <oer-s64-user1> on <Reports Reader>: True
  M.6 answer: HTTP 400; request status ''; error 'ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.'
  --- M.6-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  M.7 request: POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
      {
    "action": "adminUpdate",
    "principalId": "<oer-s64-user1>",
    "roleDefinitionId": "<Reports Reader>",
    "directoryScopeId": "/",
    "justification": "Omnicit.EntraRBAC live measurement 3.3: variant without startDateTime",
    "targetScheduleId": "<not a test object>",
    "scheduleInfo": {
      "expiration": {
        "type": "afterDuration",
        "duration": "P7D"
      }
    }
  }
  M.7 answer: HTTP 400; request status ''; error 'ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.'
  --- M.7-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 5 day(s)
  --- M.7-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  roleEligibilityScheduleRequests for <oer-s64-user1> on <Reports Reader>: 9
      2026-09-29 20:18:11Z; action adminAssign; status Provisioned; afterDuration P3D; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
      2026-09-29 20:21:02Z; action adminRemove; status Revoked; (no schedule); justification 'Omnicit.EntraRBAC: directory role eligible assignment removal'
      2026-09-29 20:23:07Z; action adminAssign; status Provisioned; afterDuration P5D; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
      2026-09-30 06:44:26Z; action adminRemove; status Revoked; (no schedule); justification 'Omnicit.EntraRBAC: directory role eligible assignment removal'
      2026-09-30 07:00:31Z; action adminAssign; status Provisioned; afterDuration P5D; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
      2026-09-30 07:01:21Z; action adminUpdate; status Provisioned; afterDuration P7D; justification 'Omnicit.EntraRBAC live measurement 3.3: adminUpdate with targetScheduleId'
      2026-09-30 07:01:50Z; action adminUpdate; status Provisioned; afterDuration P6D; justification 'Omnicit.EntraRBAC live measurement 3.3: control without targetScheduleId'
      2026-09-30 07:05:39Z; action adminAssign; status Provisioned; afterDuration P5D; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
      2026-09-30 07:17:22Z; action adminUpdate; status Provisioned; afterDuration P7D; justification 'Omnicit.EntraRBAC: directory role eligible assignment'
  roleAssignmentScheduleRequests for <oer-s64-user1> on <Reports Reader>: 4
      2026-09-29 20:23:09Z; action adminAssign; status Provisioned; noExpiration ; justification 'Omnicit.EntraRBAC: directory role active assignment'
      2026-09-30 06:45:09Z; action adminUpdate; status Provisioned; afterDuration P1D; justification 'Omnicit.EntraRBAC: directory role active assignment'
      2026-09-30 07:02:52Z; action adminUpdate; status Provisioned; noExpiration ; justification 'Omnicit.EntraRBAC: directory role active assignment'
      2026-09-30 07:17:25Z; action adminAssign; status Provisioned; noExpiration ; justification 'Omnicit.EntraRBAC: directory role active assignment'
  --- M.8-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  --- M.8-eligible-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 7 day(s)
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3a
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  What if: Performing the operation "update eligible directory role assignment" on target "Reports Reader -> person1@example.com (Eligible)".
  What if: Performing the operation "create eligible directory role assignment" on target "Reports Reader -> oer-s64-rag (Eligible)".
  What if: Performing the operation "create active directory role assignment" on target "Reports Reader -> oer-s64-rag (Active)".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Skipped | would update the eligible assignment (duration differs (live 5 days, declared 7 days))
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Skipped | would create the eligible assignment (permanent assignment is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Skipped | would create the active assignment (time-bound assignment (5 days) is absent)
  --- action counts: Skipped=3, Unchanged=2
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Updated | updated the eligible assignment (duration differs (live 5 days, declared 7 days))
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Created | created the active assignment (permanent assignment is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Created | created the eligible assignment (permanent assignment is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Created | created the active assignment (time-bound assignment (5 days) is absent)
  --- action counts: Created=3, Unchanged=1, Updated=1
  --- 3.3-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 7 day(s)
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 3.3-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 7 day(s)
  === 3.3c
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Unchanged=5
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 3.3-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 7 day(s)
  === 3.3d
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Unchanged=5
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3e
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  What if: Performing the operation "update eligible directory role assignment" on target "Reports Reader -> person1@example.com (Eligible)".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Skipped | would update the eligible assignment (duration differs (live 7 days, declared 8 days))
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Skipped=1, Unchanged=4
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 3.3f
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 12
      ERROR []:
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: BadRequest (Bad Request).
      ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: BadRequest (Bad Request).
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR []:
      ERROR [ActiveDurationTooShort]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR []:
      ERROR [ActiveDurationTooShort,New-OEREligibleDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort,New-OEREligibleDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      ERROR [ActiveDurationTooShort,Invoke-OERStructure]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
  --- results, in the order returned: 5
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Failed | failed to update the eligible assignment: Microsoft Graph refused the new window (ActiveDurationTooShort), which it does while the principal holds a permanent active assignment of the same role, so the eligible assignment is unchanged. Declare the active assignment time-bound (durationDays), or change the eligible window by hand (Remove-OEREligibleDirectoryRoleAssignment, then New-OEREligibleDirectoryRoleAssignment); the apply engine never removes an assignment to re-create it
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Failed=1, Unchanged=4
  --- 3.3f-eligible-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 7 day(s)
  --- 3.3f-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <oer-s64-user1>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  ```

---

### 4. Prune

Every `-Prune` run below is preceded by its `-WhatIf` plan and by `Assert-S64PruneTarget` on that
plan: the `-Prune` line runs only when the assertion printed `every one allowed: True`. The base
document is 3.3's, with ONE change: `oer-s64-rag`'s eligible entry names the role by its role
definition id instead of its name -- one role written two ways must be one pair, so neither entry's
assignment may ever be `Extra` or removed.

```powershell
$Pol3 = [ordered]@{ role = $RoleRR; allowPermanentEligibility = $true; allowPermanentActiveAssignment = $true }
$E1   = New-S64Entry -Role $RoleRR -Principal $User1Upn -Kind Eligible -Days 7   # 3.3's window
$E2   = New-S64Entry -Role $RoleRR -Principal $User1Upn -Kind Active -Permanent
$E3Id = New-S64Entry -Role $RoleIdRR -Principal $RagName -Type Group -Kind Eligible   # the role by its id
$E4   = New-S64Entry -Role $RoleRR -Principal $RagName -Type Group -Kind Active -Days 5
$Doc4 = New-S64Doc -Policy $Pol3 -Assignment $E1, $E2, $E3Id, $E4
```

- [x] **4.1 An undeclared eligible assignment is `Extra` without `-Prune` and `Removed` with it -- and a pair the document does not declare is untouched.**

  First the undeclared assignment, `oer-s64-user2` eligible on Reports Reader -- the plan, then the
  write once the plan matches:

  ```powershell
  $New41 = @{ Role = $RoleRR; User = $User2Upn; DurationDays = 1 }
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New41 + @{ WhatIf = $true }) -Label '4.1a plan'
  ```

  ```powershell
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New41 + @{ Confirm = $false }) -Label '4.1a write'
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser2 -Label '4.1a-raw' -Want 1
  ```

  Without `-Prune`, then the `-Prune` plan and its assertion:

  ```powershell
  Invoke-S64Check -Id '4.1b' -Json $Doc4
  Invoke-S64Check -Id '4.1c' -Json $Doc4 -Prune
  $Plan41 = $S64Result
  $Ok41 = Assert-S64PruneTarget -Result $Plan41 -Label '4.1c plan'
  ```

  The `-Prune` run -- it runs only when the assertion passed -- and the read-back:

  ```powershell
  if ($Ok41) { Invoke-S64Check -Id '4.1d' -Json $Doc4 -Prune -Apply; $null = Assert-S64PruneTarget -Result $S64Result -Label '4.1d applied' } else { Write-Host 'not run: the 4.1c assertion failed' }
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser2 -Label '4.1d-user2-rr-raw' -Want 0
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdMCR -PrincipalId $IdUser2 -Label '4.1d-user2-mcr-raw' -Want 1
  Show-S64State -State @(Get-S64State) -Label '4.1 after'
  ```

  **Expect:** 4.1a: as 2.1, for `oer-s64-user2`, one day; the raw read one row. 4.1b (no `-Prune`,
  `-WhatIf`): `Valid = True`; the policy `Unchanged`; then, BEFORE the four assignment rows, ONE
  prune-pass row,
  `[directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Extra | undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>' (use -Prune to remove)`;
  then `Reports Reader -> oer-s64-user1@<test domain> (Eligible)`, `... (Active)`,
  `<Reports Reader> -> oer-s64-rag (Eligible)` (the entry written by id) and
  `Reports Reader -> oer-s64-rag (Active)`, all four `Unchanged`; `Unchanged=5, Extra=1`; no
  warning. NOT `Extra`: `oer-s64-rag`'s eligible assignment (the same pair, whichever way the role
  is written), anything of Message Center Reader (not in the document). 4.1c (`-Prune -WhatIf`):
  one warning,
  `WARNING: Sync-OERStructureDirectoryRoleAssignment: would remove undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'.`,
  one `What if:` line,
  `Performing the operation "Remove undeclared eligible directory role assignment" on target "Reports Reader -> <the id of oer-s64-user2> (Eligible)"`,
  and the prune row `| Skipped | would remove undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'`;
  the four `Unchanged`. The assertion:
  `target: Reports Reader -> <oer-s64-user2> (Eligible) -- Skipped; allowed: True` and
  `prune targets (would remove, removed or Extra): 1; every one allowed: True`. 4.1d: the warning
  reads `removing ...`; the prune row
  `| Removed | removed undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'`;
  `Unchanged=5, Removed=1`; no error; the applied assertion `1; every one allowed: True`. The raw
  reads: user2 on Reports Reader 0 rows; user2 on Message Center Reader still ONE row (2.4's -- a
  pair the document does not declare). The state: Reports Reader holds exactly section 3's four
  direct rows (and any `MemberType Group` rows 3.1 recorded); Message Center Reader Eligible
  `<oer-s64-user2>`, Active `<oer-live-cc>`, `<oer-s64-ccrag>` and `<oer-s64-rag>` (and any
  inherited `<oer-live-cc>` row 1.1 recorded), as before.
  **Failure looks like:** `Extra` or a `would remove` row for `oer-s64-rag` -- the role written by id
  became a second pair; anything of Message Center Reader named; more than one target; a
  `MemberType Group` row as a target (see 4.4); the assertion printing `STOP` -- the `-Prune` line
  did not run: record the target.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass, with two recorded deviations. (1) The section 4 document was built with oer-s64-user1's eligible entry at FIVE days (the live window), not 3.3's seven, since 3.3 could not move it; nothing else in $Doc4 changed. (2) The raw reads list an INHERITED row for oer-s64-user2 (memberType Group, noExpiration, through oer-s64-rag's eligible assignment) beside the direct one: 2 rows after 4.1a, 1 (the inherited) after 4.1d -- the direct row was removed, the inherited one was never a candidate. 4.1b Extra=1 (user2 direct), Unchanged=5; 4.1c one target, allowed True; 4.1d Removed=1, Unchanged=5, no error; user2's Message Center Reader eligible row still there.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Create eligible directory role assignment" on target "eligible directory role 'Reports Reader' for User 'person2@example.com' at directory scope '/'".
  === 4.1a plan -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user2@<test domain>'&$select=id,userPrincipalName
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.1a write -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user2@<test domain>'&$select=id,userPrincipalName
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.1a-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.1a-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.1a-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  === 4.1b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 6
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Extra | undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>' (use -Prune to remove)
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] <Reports Reader> -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Extra=1, Unchanged=5
  === 4.1c
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Prune -WhatIf
  What if: Performing the operation "Remove undeclared eligible directory role assignment" on target "Reports Reader -> 00000000-0000-0000-0000-000000000006 (Eligible)".
  --- warnings, in the order written: 1
      WARNING: Sync-OERStructureDirectoryRoleAssignment: would remove undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'.
  --- errors: 0
  --- results, in the order returned: 6
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Skipped | would remove undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] <Reports Reader> -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Skipped=1, Unchanged=5
      target: Reports Reader -> <oer-s64-user2> (Eligible) -- Skipped; allowed: True
  --- 4.1c plan: prune targets (would remove, removed or Extra): 1; every one allowed: True
  === 4.1d
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Prune -Confirm:$false
  --- warnings, in the order written: 1
      WARNING: Sync-OERStructureDirectoryRoleAssignment: removing undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'.
  --- errors: 0
  --- results, in the order returned: 6
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Removed | removed undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] <Reports Reader> -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Removed=1, Unchanged=5
      target: Reports Reader -> <oer-s64-user2> (Eligible) -- Removed; allowed: True
  --- 4.1d applied: prune targets (would remove, removed or Extra): 1; every one allowed: True
      (4.1d-user2-rr-raw: 1 row(s) listed, waiting -- attempt 1 of 6)
      (4.1d-user2-rr-raw: 1 row(s) listed, waiting -- attempt 2 of 6)
      (4.1d-user2-rr-raw: 1 row(s) listed, waiting -- attempt 3 of 6)
      (4.1d-user2-rr-raw: 1 row(s) listed, waiting -- attempt 4 of 6)
      (4.1d-user2-rr-raw: 1 row(s) listed, waiting -- attempt 5 of 6)
      (4.1d-user2-rr-raw: 1 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.1d-user2-rr-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 1 row(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  --- 4.1d-user2-mcr-raw: raw roleEligibilitySchedules of <Message Center Reader> for <oer-s64-user2>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 3 day(s)
  --- 4.1 after: Reports Reader, Eligible: 2 row(s)
      <oer-s64-rag> (Group); MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
  --- 4.1 after: Reports Reader, Active: 2 row(s)
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  --- 4.1 after: Message Center Reader, Eligible: 1 row(s)
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 3; end set
  --- 4.1 after: Message Center Reader, Active: 3 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-ccrag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 4; end set
  ```

- [x] **4.2 An unresolved entry withholds the prune: a principal withholds its own pair, a role every pair of its kind.**

  First `oer-s64-user2`'s undeclared eligible assignment on Reports Reader again -- the plan, then
  the write once the plan matches:

  ```powershell
  $New42 = @{ Role = $RoleRR; User = $User2Upn; DurationDays = 1 }
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New42 + @{ WhatIf = $true }) -Label '4.2a plan'
  ```

  ```powershell
  Invoke-S64Call -Cmdlet New-OEREligibleDirectoryRoleAssignment -Splat ($New42 + @{ Confirm = $false }) -Label '4.2a write'
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser2 -Label '4.2a-raw' -Want 1
  ```

  A principal that resolves to nothing -- the `-Prune` plan and its assertion:

  ```powershell
  $Nobody = New-S64Entry -Role $RoleRR -Principal $NobodyUpn -Kind Eligible -Days 1
  $Doc42 = New-S64Doc -Policy $Pol3 -Assignment $E1, $E2, $E3Id, $E4, $Nobody
  Invoke-S64Check -Id '4.2b' -Json $Doc42 -Prune
  $Ok42 = Assert-S64PruneTarget -Result $S64Result -Label '4.2b plan'
  ```

  The `-Prune` run -- only when the assertion passed -- and the read-back:

  ```powershell
  if ($Ok42) { Invoke-S64Check -Id '4.2c' -Json $Doc42 -Prune -Apply; $null = Assert-S64PruneTarget -Result $S64Result -Label '4.2c applied' } else { Write-Host 'not run: the 4.2b assertion failed' }
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $IdUser2 -Label '4.2c-raw' -Want 1
  ```

  A role that resolves to nothing, beside a second eligible pair -- `-WhatIf` only, nothing is
  applied:

  ```powershell
  $NoRole = New-S64Entry -Role "$Prefix-no-such-role" -Principal $User1Upn -Kind Eligible -Days 1
  $RagMcr = New-S64Entry -Role $RoleMCR -Principal $RagName -Type Group -Kind Eligible -Days 1
  Invoke-S64Check -Id '4.2d' -Json (New-S64Doc -Policy $Pol3 -Assignment $E1, $E2, $E3Id, $E4, $NoRole, $RagMcr) -Prune
  $null = Assert-S64PruneTarget -Result $S64Result -Label '4.2d plan'
  ```

  **Expect:** 4.2a: as 4.1a. 4.2b: `Valid = True`; no warning, no `What if:` line for a removal;
  the policy `Unchanged`; the prune row
  `Reports Reader -> <oer-s64-user2> (Eligible) | Skipped | prune withheld: declared entry 'Reports Reader -> oer-s64-nobody@<test domain> (Eligible)' could not be resolved, so undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.`;
  the four declared entries `Unchanged`; the new entry
  `Reports Reader -> oer-s64-nobody@<test domain> (Eligible) | Failed | principal 'oer-s64-nobody@<test domain>' could not be resolved to an object id`;
  `Unchanged=5, Skipped=1, Failed=1`; errors 0 (a lookup that found nothing is not an error). The
  assertion: `prune targets ...: 0; every one allowed: True`. 4.2c: the same rows, for real -- and
  the raw read still ONE row: a real `-Prune` run left `oer-s64-user2`'s assignment in place. 4.2d:
  the Reports Reader pair row, and a SECOND withheld row in the other eligible pair,
  `Message Center Reader -> <oer-s64-user2> (Eligible) | Skipped | prune withheld: declared entry 'oer-s64-no-such-role -> oer-s64-user1@<test domain> (Eligible)' could not be resolved, so undeclared eligible assignment of directory role 'Message Center Reader' for principal '<oer-s64-user2>' ...`
  -- both naming the unresolved ROLE entry (4.2d does not carry the nobody entry); the four declared
  entries `Unchanged`;
  `oer-s64-no-such-role -> oer-s64-user1@<test domain> (Eligible) | Failed | directory role 'oer-s64-no-such-role' could not be resolved to a role definition id`;
  `Message Center Reader -> oer-s64-rag (Eligible) | Skipped | would create the eligible assignment (time-bound assignment (1 days) is absent)`;
  the assertion `0; every one allowed: True`. The Active pairs are not withheld by an Eligible
  entry, and hold no undeclared candidate here.
  **Failure looks like:** a `would remove` or `Removed` row for `oer-s64-user2` in 4.2b or 4.2c, or
  the raw read after 4.2c showing 0 rows -- the withheld rule failed on a real run: stop and record
  it; in 4.2d only one withheld row -- the unresolved role withheld its own pair instead of every
  pair of its kind.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass (deviation (1) of 4.1 applies; the raw reads list the inherited row beside the direct one, 2 rows). 4.2b and 4.2c: the withheld Skipped row naming the nobody entry, Failed for the nobody entry, 0 targets; after the real -Prune run the direct row is still there. 4.2d: two withheld rows (the Reports Reader and Message Center Reader eligible pairs) naming the unresolved role entry; would create for oer-s64-rag's Message Center Reader eligible; 0 targets.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Create eligible directory role assignment" on target "eligible directory role 'Reports Reader' for User 'person2@example.com' at directory scope '/'".
  === 4.2a plan -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 2
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user2@<test domain>'&$select=id,userPrincipalName
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.2a write -- New-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 3
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Reports Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user2@<test domain>'&$select=id,userPrincipalName
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [New-OEREligibleDirectoryRoleAssignment] Resolved role 'Reports Reader' to '<Reports Reader>'.
      [New-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by New-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.2a-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.2a-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  === 4.2b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Prune -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 7
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Skipped | prune withheld: declared entry 'Reports Reader -> oer-s64-nobody@<test domain> (Eligible)' could not be resolved, so undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] <Reports Reader> -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-nobody@<test domain> (Eligible) | Failed | principal 'oer-s64-nobody@<test domain>' could not be resolved to an object id
  --- action counts: Failed=1, Skipped=1, Unchanged=5
  --- 4.2b plan: prune targets (would remove, removed or Extra): 0; every one allowed: True
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.2a-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  === 4.2b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Prune -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 7
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Skipped | prune withheld: declared entry 'Reports Reader -> oer-s64-nobody@<test domain> (Eligible)' could not be resolved, so undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] <Reports Reader> -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-nobody@<test domain> (Eligible) | Failed | principal 'oer-s64-nobody@<test domain>' could not be resolved to an object id
  --- action counts: Failed=1, Skipped=1, Unchanged=5
  --- 4.2b plan: prune targets (would remove, removed or Extra): 0; every one allowed: True
  === 4.2c
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Prune -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 7
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Skipped | prune withheld: declared entry 'Reports Reader -> oer-s64-nobody@<test domain> (Eligible)' could not be resolved, so undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] <Reports Reader> -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-nobody@<test domain> (Eligible) | Failed | principal 'oer-s64-nobody@<test domain>' could not be resolved to an object id
  --- action counts: Failed=1, Skipped=1, Unchanged=5
  --- 4.2c applied: prune targets (would remove, removed or Extra): 0; every one allowed: True
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.2c-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.2a-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.2a-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 1 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 2 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 3 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 4 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 5 of 6)
      (4.2c-raw: 2 row(s) listed, waiting -- attempt 6 of 6)
  --- 4.2c-raw: raw roleEligibilitySchedules of <Reports Reader> for <oer-s64-user2>: 2 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
      memberType Group; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type noExpiration, endDateTime set False, duration (none); window never ends
  === 4.2d
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleManagementPolicies,DirectoryRoleAssignments -Prune -WhatIf
  What if: Performing the operation "create eligible directory role assignment" on target "Message Center Reader -> oer-s64-rag (Eligible)".
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 9
      [directoryRoleManagementPolicies] Reports Reader | Unchanged | policy already matches for 'Reports Reader'
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Skipped | prune withheld: declared entry 'oer-s64-no-such-role -> oer-s64-user1@<test domain> (Eligible)' could not be resolved, so undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-user2> (Eligible) | Skipped | prune withheld: declared entry 'oer-s64-no-such-role -> oer-s64-user1@<test domain> (Eligible)' could not be resolved, so undeclared eligible assignment of directory role 'Message Center Reader' for principal '<oer-s64-user2>' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection.
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] <Reports Reader> -> oer-s64-rag (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
      [directoryRoleAssignments] oer-s64-no-such-role -> oer-s64-user1@<test domain> (Eligible) | Failed | directory role 'oer-s64-no-such-role' could not be resolved to a role definition id
      [directoryRoleAssignments] Message Center Reader -> oer-s64-rag (Eligible) | Skipped | would create the eligible assignment (time-bound assignment (1 days) is absent)
  --- action counts: Failed=1, Skipped=3, Unchanged=5
  --- 4.2d plan: prune targets (would remove, removed or Extra): 0; every one allowed: True
  ```

- [x] **4.3 The signed-in identity's own assignment is `Skipped` under `-Prune`, and stays.** The document declares (Message Center Reader, Active) for `oer-s64-rag` only, so the certificate identity's own active Message Center Reader assignment is an undeclared candidate in a declared pair -- and so is `oer-s64-ccrag`'s, which the certificate identity holds through its membership (4.5 runs the group guard on its own).

  ```powershell
  "the module's signed-in object id is oer-live-cc's service principal: $([string]::Equals([string](& (Get-Module Omnicit.EntraRBAC) { Get-OERSignedInObjectId }), $IdCc, [System.StringComparison]::OrdinalIgnoreCase))"
  $Doc43 = New-S64Doc -Assignment (New-S64Entry -Role $RoleMCR -Principal $RagName -Type Group -Kind Active -Days 4)
  Invoke-S64Check -Id '4.3a' -Json $Doc43 -Include DirectoryRoleAssignments -Prune
  $Ok43 = Assert-S64PruneTarget -Result $S64Result -Label '4.3a plan'
  ```

  The `-Prune` run -- only when the assertion passed -- and the read-back:

  ```powershell
  if ($Ok43) { Invoke-S64Check -Id '4.3b' -Json $Doc43 -Include DirectoryRoleAssignments -Prune -Apply; $null = Assert-S64PruneTarget -Result $S64Result -Label '4.3b applied' } else { Write-Host 'not run: the 4.3a assertion failed' }
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdCc -Label '4.3-cc-raw' -Want 1 -DirectOnly
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdCcRag -Label '4.3-ccrag-raw' -Want 1
  Show-S64State -State @(Get-S64State) -Label '4.3 after'
  ```

  **Expect:** `... oer-live-cc's service principal: True`. 4.3a: `Valid = True`; no warning, no
  `What if:` line for a removal; three rows. First the two prune rows, in the order the pass emits
  them (it walks the pair's rows in Graph's order: record it): the own row, with the own-assignment
  reason -- that guard comes before the group guard --
  `Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)`,
  and the group's row
  `Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)`;
  then `Message Center Reader -> oer-s64-rag (Active) | Unchanged | assignment matches` (2.7's
  four-day window); `Skipped=2, Unchanged=1`; the assertion `0; every one allowed: True`. 4.3b: the
  same three rows, for real. The raw reads: the certificate identity's direct row still there,
  `Assigned`, `Direct`, and `oer-s64-ccrag`'s. The state: unchanged from 4.1's except
  `oer-s64-user2`'s Reports Reader eligible row, which 4.2 created -- Reports Reader is not in this
  document, and Message Center Reader Eligible (`oer-s64-user2`) is a pair it does not declare:
  neither is read, listed or touched. When the prerequisite run recorded that Graph refused the
  membership, `oer-s64-ccrag` holds no assignment: the own row and the `oer-s64-rag` row only,
  `Skipped=1, Unchanged=1`, and the second raw read waits and shows 0 rows.
  **Failure looks like:** `Extra`, `would remove` or `Removed` for `<oer-live-cc>` -- the guard did
  not recognize the signed-in identity (the assertion also stops: `oer-live-cc` carries no
  `oer-s64` prefix); `Extra`, `would remove` or `Removed` for `<oer-s64-ccrag>` -- the group guard
  failed (a stop condition; the assertion also stops: it never allows `oer-s64-ccrag`); the group's
  row `prune withheld: the signed-in identity's group memberships could not be read, ...` -- the
  membership read failed: record the message, 4.5 shows Graph's own answer;
  `prune withheld: the signed-in identity's object id is unknown` -- 0.4 should have caught it;
  the `oer-s64-rag` row `Updated` -- 2.7's window did not converge; any row naming Reports Reader.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Three rows: <oer-live-cc> Skipped (own), <oer-s64-ccrag> Skipped with the group guard's Detail verbatim, oer-s64-rag Unchanged; Skipped=2, Unchanged=1; 0 targets; the real run the same; both raw rows still there (Direct).

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  the module's signed-in object id is oer-live-cc's service principal: True
  === 4.3a
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleAssignments -Prune -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 3
      [directoryRoleAssignments] Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Skipped=2, Unchanged=1
  --- 4.3a plan: prune targets (would remove, removed or Extra): 0; every one allowed: True
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  the module's signed-in object id is oer-live-cc's service principal: True
  === 4.3a
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleAssignments -Prune -WhatIf
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 3
      [directoryRoleAssignments] Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Skipped=2, Unchanged=1
  --- 4.3a plan: prune targets (would remove, removed or Extra): 0; every one allowed: True
  === 4.3b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleAssignments -Prune -Confirm:$false
  --- warnings, in the order written: 0
  --- errors: 0
  --- results, in the order returned: 3
      [directoryRoleAssignments] Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> oer-s64-rag (Active) | Unchanged | assignment matches
  --- action counts: Skipped=2, Unchanged=1
  --- 4.3b applied: prune targets (would remove, removed or Extra): 0; every one allowed: True
  --- 4.3-cc-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-live-cc>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  --- 4.3-ccrag-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-ccrag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  --- 4.3 after: Reports Reader, Eligible: 3 row(s)
      <oer-s64-rag> (Group); MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 1; end set
  --- 4.3 after: Reports Reader, Active: 2 row(s)
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  --- 4.3 after: Message Center Reader, Eligible: 1 row(s)
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 3; end set
  --- 4.3 after: Message Center Reader, Active: 3 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-ccrag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 4; end set
  ```

- [~] **4.4 A member of a role-assignable group: is its inherited row listed, and is it ever a prune target?** Read-only: a measurement over the state and over section 4's results.

  ```powershell
  $S44 = @(Get-S64State)
  $Inherited = @($S44 | Where-Object { $_.MemberType -ne 'Direct' })
  "rows that are not Direct: $($Inherited.Count)"
  $Inherited | ForEach-Object { '    {0} {1}: {2}' -f $_.S64Role, $_.Kind, (Format-S64Row $_) }
  $All44 = @(Import-Csv (Join-Path $Raw 'all-results.csv') | Where-Object { $_.CheckId -like '4.*' })
  "section 4 rows naming oer-s64-user2 in an Active pair: $(@($All44 | Where-Object { $_.Item -match [regex]::Escape($IdUser2) -and $_.Item -match '\(Active\)$' }).Count)"
  "4.1c rows naming oer-s64-user2: $(@($All44 | Where-Object { $_.CheckId -eq '4.1c' -and $_.Item -match [regex]::Escape($IdUser2) }).Count)"
  $Targets44 = @($All44 | Where-Object { $_.Action -in 'Removed', 'Extra' -or ([string]$_.Detail).StartsWith('would remove', [System.StringComparison]::Ordinal) })
  "section 4 prune targets naming oer-live-cc: $(@($Targets44 | Where-Object { $_.Item -match [regex]::Escape($IdCc) }).Count); naming oer-s64-ccrag: $(@($Targets44 | Where-Object { $_.Item -match [regex]::Escape($IdCcRag) }).Count)"
  ```

  **Expect:** if Graph lists them, `rows that are not Direct:` a count above 0, each for
  `<oer-s64-user2>` with a `MemberType` other than `Direct` (Graph documents `Group` and
  `Inherited`; record which) -- in the pairs the group holds: Reports Reader Eligible and Active and
  Message Center Reader Active -- and possibly one for `<oer-live-cc>` in Message Center Reader
  Active, through `oer-s64-ccrag` (1.1 recorded whether Graph lists it). Then
  `section 4 rows naming oer-s64-user2 in an Active pair: 0` and
  `4.1c rows naming oer-s64-user2: 1` -- its DIRECT eligible assignment only: an inherited row was
  neither `Extra` nor a removal target, in any pair -- and
  `section 4 prune targets naming oer-live-cc: 0; naming oer-s64-ccrag: 0`: an inherited row of
  the certificate identity is never a target either. If Graph lists no such row
  (`rows that are not Direct: 0`), the guard cannot be seen live: mark this check `[~]` with that
  measurement -- `Select-OERManagedDirectoryRoleAssignment`'s `MemberType` guard is pinned and
  mutation-proved in its unit suite.
  **Failure looks like:** an inherited row counted in a section 4 result (`Active` pair count above
  0, or `2` for 4.1c) -- the managed-row filter let it through; stop and record the rows. A prune
  target naming `oer-live-cc` or `oer-s64-ccrag` -- stop (Stop conditions).
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Measured; the managed-row guard cannot be seen through the pair reads. "rows that are not Direct: 0": the role-wide reads the prune pass makes list no inherited row. The principal-filtered raw reads (4.1a, 4.1d, 4.2a, 4.2c) DO list one: oer-s64-user2, memberType Group, through oer-s64-rag. Section 4 rows naming oer-s64-user2 in an Active pair: 0; prune targets naming oer-live-cc 0 and oer-s64-ccrag 0. "4.1c rows naming oer-s64-user2: 2" is an artefact: 4.1c ran twice (the first 4.1d attempt failed in the runner before any request), both rows the same direct candidate.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  rows that are not Direct: 0
  section 4 rows naming oer-s64-user2 in an Active pair: 0
  4.1c rows naming oer-s64-user2: 2
  section 4 prune targets naming oer-live-cc: 0; naming oer-s64-ccrag: 0
  ```

- [x] **4.5 A role the signed-in identity holds through a group is `Skipped` under `-Prune`, and stays -- and a group it is not a member of is still pruned.** The document declares (Message Center Reader, Active) for `oer-s64-user1` only, so three undeclared candidates sit in that pair: the certificate identity's own assignment, `oer-s64-ccrag`'s (the certificate identity is its only member) and `oer-s64-rag`'s (2.7's; the certificate identity is NOT a member).

  First the raw facts, read-only: both groups' members, and the certificate identity's own group
  memberships straight from Microsoft Graph, read as data -- the status and two True/False, never
  the ids. If the prerequisite run printed that Graph refused the membership, mark 4.5 `[~]` with
  that refusal line and stop here.

  ```powershell
  $CcRag45 = Get-S64RawGroup -Name $CcRagName
  $Rag45 = Get-S64RawGroup -Name $RagName
  "4.5a oer-s64-ccrag: members [$((@($CcRag45.MemberIds) | ForEach-Object { Get-S64Name $_ }) -join ', ')]"
  "4.5a oer-s64-rag: members [$((@($Rag45.MemberIds) | ForEach-Object { Get-S64Name $_ }) -join ', ')]; oer-live-cc among them: $(@($Rag45.MemberIds) -contains $IdCc)"
  $Mg45 = Invoke-MgGraphRequest -Method POST -Uri "v1.0/directoryObjects/$IdCc/getMemberGroups" -Body @{ securityEnabledOnly = $false } -OutputType HashTable -SkipHttpErrorCheck -StatusCodeVariable 'S64MgStatus'
  $Mg45Code = if ($Mg45 -is [System.Collections.IDictionary] -and $Mg45['error']) { [string]$Mg45['error']['code'] } else { '' }
  $Mg45Ids = @($Mg45['value'] | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
  "4.5a raw getMemberGroups of oer-live-cc: status $S64MgStatus$(if ($Mg45Code) { " $Mg45Code" }); groups listed $($Mg45Ids.Count); holds oer-s64-ccrag: $($Mg45Ids -contains ([string]$IdCcRag).ToLowerInvariant()); holds oer-s64-rag: $($Mg45Ids -contains ([string]$IdRag).ToLowerInvariant())"
  ```

  The document, its `-WhatIf -Prune` plan, and the gate: `$Ok45` is `True` only when
  `Assert-S64PruneTarget` passed AND the plan holds exactly one row for `oer-s64-ccrag`, `Skipped`
  by the group guard, AND the own row is `Skipped` by the own-assignment guard, AND the only prune
  target is `oer-s64-rag`:

  ```powershell
  $Doc45 = New-S64Doc -Assignment (New-S64Entry -Role $RoleMCR -Principal $User1Upn -Kind Active -Days 1)
  Invoke-S64Check -Id '4.5b' -Json $Doc45 -Include DirectoryRoleAssignments -Prune
  $Plan45 = @($S64Result | Where-Object { $_.Section -eq 'directoryRoleAssignments' })
  $Assert45 = Assert-S64PruneTarget -Result $S64Result -Label '4.5b plan'
  $CcRow45 = @($Plan45 | Where-Object { [string]$_.Item -match [regex]::Escape([string]$IdCcRag) })
  $OwnRow45 = @($Plan45 | Where-Object { [string]$_.Item -match [regex]::Escape([string]$IdCc) })
  $Targets45 = @($Plan45 | Where-Object { $_.Action -in 'Removed', 'Extra' -or ($_.Action -eq 'Skipped' -and ([string]$_.Detail).StartsWith('would remove', [System.StringComparison]::Ordinal)) })
  $Gate45 = [ordered]@{
      'the ids of 0.5 are set'                                    = [bool]($IdCc -and $IdCcRag -and $IdRag)
      'the assertion passed'                                      = [bool]$Assert45
      'exactly one oer-s64-ccrag row, Skipped by the group guard' = ($CcRow45.Count -eq 1) -and ($CcRow45[0].Action -eq 'Skipped') -and ([string]$CcRow45[0].Detail).Contains('is a group the signed-in identity is a member of')
      'the own row, Skipped by the own-assignment guard'          = ($OwnRow45.Count -eq 1) -and ($OwnRow45[0].Action -eq 'Skipped') -and ([string]$OwnRow45[0].Detail).Contains('belongs to the signed-in identity itself')
      'the only prune target is oer-s64-rag'                      = ($Targets45.Count -eq 1) -and ([string]$Targets45[0].Item -match [regex]::Escape([string]$IdRag))
  }
  $Gate45.GetEnumerator() | ForEach-Object { "4.5b gate: $($_.Key): $($_.Value)" }
  $Ok45 = @($Gate45.Values | Where-Object { -not $_ }).Count -eq 0
  "4.5b gate: all: $Ok45"
  ```

  The same document's `-WhatIf -Prune` run once more, straight through `Invoke-OERStructure
  -Verbose`: every request it sends, and how many of them read the signed-in identity's group
  memberships -- the pass reads them once per run:

  ```powershell
  $Out45 = @(Invoke-OERStructure -Path (Join-Path $Raw '4.5b.json') -Include DirectoryRoleAssignments -Prune -WhatIf -Verbose -ErrorAction SilentlyContinue -ErrorVariable Err45 3>$null 4>&1)
  $Req45 = @($Out45 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { Format-S64Request -Message $_.Message } | Where-Object { $_ })
  "4.5c requests, in the order sent: $($Req45.Count)"
  $Req45 | ForEach-Object { "    $_" }
  "4.5c getMemberGroups requests in that run: $(@($Req45 | Where-Object { $_ -match 'getMemberGroups' }).Count); errors: $(@($Err45 | Where-Object { $null -ne $_ }).Count)"
  ```

  The `-Prune` run -- only when the gate passed -- and the raw read-backs:

  ```powershell
  if ($Ok45) { Invoke-S64Check -Id '4.5d' -Json $Doc45 -Include DirectoryRoleAssignments -Prune -Apply; $null = Assert-S64PruneTarget -Result $S64Result -Label '4.5d applied' } else { Write-Host 'not run: the 4.5b gate failed' }
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdCcRag -Label '4.5-ccrag-raw' -Want 1
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdCc -Label '4.5-cc-raw' -Want 1 -DirectOnly
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdRag -Label '4.5-rag-raw' -Want 0
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdMCR -PrincipalId $IdUser1 -Label '4.5-user1-raw' -Want 1
  Show-S64State -State @(Get-S64State) -Label '4.5 after' -Role $RoleMCR
  ```

  **Expect:** the raw facts: `4.5a oer-s64-ccrag: members [oer-live-cc]`;
  `4.5a oer-s64-rag: members [oer-s64-user2]; oer-live-cc among them: False`;
  `4.5a raw getMemberGroups of oer-live-cc: status 200; groups listed <n>; holds oer-s64-ccrag: True; holds oer-s64-rag: False`
  (record `<n>`: any other group the certificate identity is a member of counts too). 4.5b:
  `Valid = True`; ONE warning,
  `WARNING: Sync-OERStructureDirectoryRoleAssignment: would remove undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'.`;
  the `What if:` lines of the removal
  (`Performing the operation "Remove undeclared active directory role assignment" on target "Message Center Reader -> <the id of oer-s64-rag> (Active)"`)
  and of the create (`create active directory role assignment`, its row label as the target --
  redact the user principal name). Four rows: first the three prune rows, BEFORE the item row, in
  the order the pass emits them (it reads the pair once and walks its rows in Graph's order:
  record it) -- the own row
  `Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; ...`,
  the group's row
  `Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)`
  and `Message Center Reader -> <oer-s64-rag> (Active) | Skipped | would remove undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'`;
  then `Message Center Reader -> oer-s64-user1@<test domain> (Active) | Skipped | would create the active assignment (time-bound assignment (1 days) is absent)`;
  `Skipped=4`. The assertion:
  `target: Message Center Reader -> <oer-s64-rag> (Active) -- Skipped; allowed: True` and
  `prune targets (would remove, removed or Extra): 1; every one allowed: True`; every gate line
  `True`, and `4.5b gate: all: True`. 4.5c: the requests (record them), among them exactly one
  `POST v1.0/directoryObjects/<oer-live-cc>/getMemberGroups`, and
  `4.5c getMemberGroups requests in that run: 1; errors: 0`. 4.5d: the warning reads
  `removing ...`; the own row and the group's row `Skipped` as in the plan;
  `Message Center Reader -> <oer-s64-rag> (Active) | Removed | removed undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'`;
  `Message Center Reader -> oer-s64-user1@<test domain> (Active) | Created | created the active assignment (time-bound assignment (1 days) is absent)`;
  `Skipped=2, Removed=1, Created=1`; no error; the applied assertion `1; every one allowed: True`.
  The raw reads: `oer-s64-ccrag`'s row still there (1 row, `memberType Direct`,
  `assignmentType Assigned`); the certificate identity's direct row still there (1); `oer-s64-rag`'s
  Message Center Reader active row gone (0); `oer-s64-user1`'s created (1 row, a window of 1
  day(s)). The state: Message Center Reader Eligible `<oer-s64-user2>`; Active `<oer-live-cc>`,
  `<oer-s64-ccrag>` and `<oer-s64-user1>` (and any inherited `<oer-live-cc>` row), and no
  `<oer-s64-rag>`.
  **Failure looks like:** a `<oer-s64-ccrag>` prune target -- `would remove` or `Extra` -- the
  group guard failed: the assertion and the gate both stop the real run; stop and record it. The
  group's row `prune withheld: the signed-in identity's group memberships could not be read, ...`
  -- the membership read failed: record Graph's answer from the `4.5a raw getMemberGroups` line;
  not a pass. `oer-s64-rag`'s row `Skipped` with the group guard's reason -- a group the identity is
  not a member of was protected: the guard over-reaches. The own row carrying the group guard's
  reason instead of its own -- the guard order is wrong. A `getMemberGroups` count other than 1. A
  `holds oer-s64-ccrag: False` or a status other than 200 in the raw facts: the plan cannot be
  judged -- record it and do not run the real `-Prune` line; a `403 Authorization_RequestDenied`
  there is the permission question Setup names (`Directory.Read.All` for the `directoryObjects`
  form): name it, and never finish the check with another sign-in.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass -- the group guard, live. Raw: getMemberGroups of oer-live-cc status 200, 1 group, holds oer-s64-ccrag True, holds oer-s64-rag False (the untyped member read prints [] for oer-s64-ccrag as in 0.5; read as servicePrincipal: [oer-live-cc]). The plan, in Graph's order: oer-s64-rag would remove, <oer-live-cc> Skipped (own), <oer-s64-ccrag> Skipped (group guard, Detail verbatim), oer-s64-user1 would create; Skipped=4; every gate line True. 4.5c: 7 requests, exactly one POST v1.0/directoryObjects/<oer-live-cc>/getMemberGroups, errors 0. 4.5d: Removed=1 (oer-s64-rag), Skipped=2, Created=1, no error; raw: oer-s64-ccrag 1 row, own 1 Direct row, oer-s64-rag 0, oer-s64-user1 1 row (1 day).

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  4.5a oer-s64-ccrag: members []
  4.5a oer-s64-rag: members [oer-s64-user2]; oer-live-cc among them: False
  4.5a raw getMemberGroups of oer-live-cc: status 200; groups listed 1; holds oer-s64-ccrag: True; holds oer-s64-rag: False
  4.5a (supplement) oer-s64-ccrag members read as servicePrincipal: status 200; [oer-live-cc]
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.5b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleAssignments -Prune -WhatIf
  What if: Performing the operation "Remove undeclared active directory role assignment" on target "Message Center Reader -> 00000000-0000-0000-0000-000000000007 (Active)".
  What if: Performing the operation "create active directory role assignment" on target "Message Center Reader -> person1@example.com (Active)".
  --- warnings, in the order written: 1
      WARNING: Sync-OERStructureDirectoryRoleAssignment: would remove undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'.
  --- errors: 0
  --- results, in the order returned: 4
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-rag> (Active) | Skipped | would remove undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'
      [directoryRoleAssignments] Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> oer-s64-user1@<test domain> (Active) | Skipped | would create the active assignment (time-bound assignment (1 days) is absent)
  --- action counts: Skipped=4
      target: Message Center Reader -> <oer-s64-rag> (Active) -- Skipped; allowed: True
  --- 4.5b plan: prune targets (would remove, removed or Extra): 1; every one allowed: True
  4.5b gate: the ids of 0.5 are set: True
  4.5b gate: the assertion passed: True
  4.5b gate: exactly one oer-s64-ccrag row, Skipped by the group guard: True
  4.5b gate: the own row, Skipped by the own-assignment guard: True
  4.5b gate: the only prune target is oer-s64-rag: True
  4.5b gate: all: True
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  What if: Performing the operation "Remove undeclared active directory role assignment" on target "Message Center Reader -> 00000000-0000-0000-0000-000000000007 (Active)".
  What if: Performing the operation "create active directory role assignment" on target "Message Center Reader -> person1@example.com (Active)".
  4.5c requests, in the order sent: 7
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      GET v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Message Center Reader>'&$expand=principal,roleDefinition
      POST v1.0/directoryObjects/<oer-live-cc>/getMemberGroups
      GET v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq 'Message Center Reader'&$select=id,displayName
      GET v1.0/users?$filter=userPrincipalName eq 'oer-s64-user1@<test domain>'&$select=id,userPrincipalName
      GET v1.0/roleManagement/directory/roleAssignmentSchedules?$filter=directoryScopeId eq '/' and roleDefinitionId eq '<Message Center Reader>' and principalId eq '<oer-s64-user1>'&$expand=principal,roleDefinition
  4.5c getMemberGroups requests in that run: 1; errors: 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === 4.5b
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleAssignments -Prune -WhatIf
  What if: Performing the operation "Remove undeclared active directory role assignment" on target "Message Center Reader -> 00000000-0000-0000-0000-000000000007 (Active)".
  What if: Performing the operation "create active directory role assignment" on target "Message Center Reader -> person1@example.com (Active)".
  --- warnings, in the order written: 1
      WARNING: Sync-OERStructureDirectoryRoleAssignment: would remove undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'.
  --- errors: 0
  --- results, in the order returned: 4
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-rag> (Active) | Skipped | would remove undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'
      [directoryRoleAssignments] Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> oer-s64-user1@<test domain> (Active) | Skipped | would create the active assignment (time-bound assignment (1 days) is absent)
  --- action counts: Skipped=4
      target: Message Center Reader -> <oer-s64-rag> (Active) -- Skipped; allowed: True
  --- 4.5b plan: prune targets (would remove, removed or Extra): 1; every one allowed: True
  4.5b gate: the ids of 0.5 are set: True
  4.5b gate: the assertion passed: True
  4.5b gate: exactly one oer-s64-ccrag row, Skipped by the group guard: True
  4.5b gate: the own row, Skipped by the own-assignment guard: True
  4.5b gate: the only prune target is oer-s64-rag: True
  4.5b gate: all: True
  === 4.5d
  --- offline validation: Valid = True, findings = 0
  --- Invoke-OERStructure -Include DirectoryRoleAssignments -Prune -Confirm:$false
  --- warnings, in the order written: 1
      WARNING: Sync-OERStructureDirectoryRoleAssignment: removing undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'.
  --- errors: 0
  --- results, in the order returned: 4
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-rag> (Active) | Removed | removed undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-rag>'
      [directoryRoleAssignments] Message Center Reader -> <oer-live-cc> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-live-cc>' belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> <oer-s64-ccrag> (Active) | Skipped | undeclared active assignment of directory role 'Message Center Reader' for principal '<oer-s64-ccrag>' is a group the signed-in identity is a member of (directly or through nesting), so the signed-in identity holds directory role 'Message Center Reader' through it; the apply engine never removes a role the signed-in identity holds (our own guard, not a Graph rejection)
      [directoryRoleAssignments] Message Center Reader -> oer-s64-user1@<test domain> (Active) | Created | created the active assignment (time-bound assignment (1 days) is absent)
  --- action counts: Created=1, Removed=1, Skipped=2
      target: Message Center Reader -> <oer-s64-rag> (Active) -- Removed; allowed: True
  --- 4.5d applied: prune targets (would remove, removed or Extra): 1; every one allowed: True
  --- 4.5-ccrag-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-ccrag>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  --- 4.5-cc-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-live-cc>, memberType Direct only: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 2 day(s)
  --- 4.5-rag-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-rag>: 0 row(s)
  --- 4.5-user1-raw: raw roleAssignmentSchedules of <Message Center Reader> for <oer-s64-user1>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType Assigned; status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
  --- 4.5 after: Message Center Reader, Eligible: 1 row(s)
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 3; end set
  --- 4.5 after: Message Center Reader, Active: 3 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-ccrag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 1; end set
  ```

---

### 5. A refused read is not an empty pair

- [x] **5.1 A refused lookup and refused schedule reads, by `oer-live-cc-noperm` in a process of its own -- and a `-Prune` document run that removes nothing.**

  A second process keeps this window's sign-in intact: the module keeps one credential per process.
  The script signs in app-only as `oer-live-cc-noperm` -- the same certificate, no API permission,
  without `-IncludeARM` -- checks its identity and stops at once, signed out and with exit code 1,
  unless all three identity lines are `True`; only then it reads Reports Reader's assignments by
  name and by role definition id, and runs two documents with `-Prune`: one naming the role and
  principals by name, one by ids. Each
  document runs its `-WhatIf` plan first, and its real `-Prune` run only when that plan holds
  nothing but `Failed` rows (the script's own gate: this identity can read nothing, so any other
  row means it is not the refused identity this check describes). This block records the state
  for 5.2, writes the script and its inputs to the raw folder and runs it.

  ```powershell
  $Before51 = @(Get-S64State)
  [ordered]@{
      TenantId           = $TenantId
      NoPermAppId        = $NoPermAppId
      Thumbprint         = $Thumbprint
      Domain             = $Domain
      Alias              = $Alias
      RoleName           = $RoleRR
      RoleId             = $RoleIdRR
      User1Upn           = $User1Upn
      User1Id            = $IdUser1
      User1Name          = "$Prefix-user1"
      RagName            = $RagName
      RagId              = $IdRag
      PSModulePathPrefix = (Resolve-Path (Join-Path $Repo 'output/module')).Path + [System.IO.Path]::PathSeparator + (Resolve-Path (Join-Path $Repo 'output/RequiredModules')).Path
  } | ConvertTo-Json | Set-Content -Path (Join-Path $Raw '5.1-input.json') -Encoding utf8NoBOM
  $RefusedPath = Join-Path $Raw '5.1-refused-read.ps1'
  Set-Content -Path $RefusedPath -Value $RefusedScript -Encoding utf8NoBOM
  pwsh -NoProfile -File $RefusedPath
  "the refused-read process exit code: $LASTEXITCODE"
  ```

  **Expect:** `identity check: session app id is oer-live-cc-noperm: True`,
  `identity check: tenant is the test tenant: True` and
  `identity check: the token carries no application permission: True` -- the script goes on only
  when all three are `True`. (a) `result objects: 0`,
  `Errors published by Get-OEREligibleDirectoryRoleAssignment: 1`,
  `ERROR [RoleDefinitionReadFailed,Get-OEREligibleDirectoryRoleAssignment]: Looking up the Microsoft Entra directory role 'Reports Reader' failed, so whether it exists could not be determined: <cause>`
  (step 3 measured the cause as `Authorization_RequestDenied: Insufficient privileges to complete the operation.`).
  (b) and (c) `result objects: 0` and one published error each, the refused schedule read -- never
  `RoleDefinitionNotFound` (a GUID skips the lookup). (d) by name, the plan: `rows: 4`, every one
  `Failed`, `Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Failed | could not resolve directory role 'Reports Reader': <cause>`
  and the same for the other three entries -- no prune-pass row at all, since no entry's role
  resolved and so no pair is known; `action counts: Failed=4`; the errors carry Graph's refusal;
  then the real `-Prune` run: the same four `Failed`. (e) by id, the plan: `rows: 6`, first the two
  pair rows,
  `<Reports Reader> (Eligible) | Failed | could not read the eligible assignments of directory role '<Reports Reader>', so nothing in this pair was pruned or reported Extra: <cause>`
  and the same for `(Active)`, then the four entries,
  `<Reports Reader> -> <oer-s64-user1> (Eligible) | Failed | could not read the eligible assignments of '<Reports Reader>': <cause>`
  and so on; `action counts: Failed=6`; then the real run: the same six. In neither document a
  `Removed`, `Extra`, `Skipped`, `Created`, `Updated` or `Unchanged` row, and no `STOP` line. (f)
  all three raw statuses `403` (with Graph's error code). `Done.`, then in this window
  `the refused-read process exit code: 0`.
  **Failure looks like:** `STOP: the identity check failed, so nothing below ran. Signed out.` or
  `STOP: the sign-in as oer-live-cc-noperm failed, ...` and exit code `1` -- nothing was read or
  run; a `False` line names which part failed: stop and report it, never retry with another
  sign-in. `RoleDefinitionNotFound` in (a), or an `Unchanged`/`Created` row, while
  the raw status is `403` -- a refusal read as absence, the defect this branch must not have; any
  `Removed` or `Extra` -- a failed read treated as an empty pair: stop. A raw status of `200` with
  zero objects: Graph HID the objects instead of refusing -- the module cannot tell that from
  absence; record it as "cannot be verified, and therefore we do not know". A
  `STOP: the plan of ...` line: the plan held another row -- that document's real run was not made;
  record the rows. A sign-in answering "application is disabled": the run is not the one this check
  describes -- stop and report it, never retry with another sign-in.
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass. Identity lines True x3. (a) RoleDefinitionReadFailed (Authorization_RequestDenied); (b), (c) the refused schedule read -- Graph answers 403 with code UnknownError and a body PermissionScopeNotGranted naming the missing scopes (record); (d) Failed=4 in the plan and for real; (e) Failed=6 in the plan and for real; no other action; (f) 403 Authorization_RequestDenied, 403 UnknownError, 403 UnknownError; exit code 0. 84-90 error records collected per document run (the parked error-record family).

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  identity check: session app id is oer-live-cc-noperm: True
  identity check: tenant is the test tenant: True
  identity check: the token carries no application permission: True
  (a) Get eligible by name -- result objects: 0
  Errors published by Get-OEREligibleDirectoryRoleAssignment: 1 (records collected: 11)
  ERROR [RoleDefinitionReadFailed,Get-OEREligibleDirectoryRoleAssignment]: Looking up the Microsoft Entra directory role 'Reports Reader' failed, so whether it exists could not be determined: Authorization_RequestDenied: Insufficient privileges to complete the operation.
  (b) Get eligible by role definition id -- result objects: 0
  Errors published by Get-OEREligibleDirectoryRoleAssignment: 1 (records collected: 11)
  ERROR [UnknownError,Get-OEREligibleDirectoryRoleAssignment]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  (c) Get active by role definition id -- result objects: 0
  Errors published by Get-OERActiveDirectoryRoleAssignment: 1 (records collected: 11)
  ERROR [UnknownError,Get-OERActiveDirectoryRoleAssignment]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  === 5.1d-by-name -Prune -WhatIf -- rows: 4; warnings: 0
  === 5.1d-by-name -Prune, for real -- rows: 4; warnings: 0
  === 5.1e-by-id -Prune -WhatIf -- rows: 6; warnings: 0
  === 5.1e-by-id -Prune, for real -- rows: 6; warnings: 0
  === 5.1d-by-name -Prune -WhatIf -- rows: 4; warnings: 0
    [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
    [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
    [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
    [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
  action counts: Failed=4
  Error records collected: 84; distinct: 4
  ERROR []:
  ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: Forbidden (Forbidden).
  ERROR [Authorization_RequestDenied]: Authorization_RequestDenied: Insufficient privileges to complete the operation.
  ERROR [Authorization_RequestDenied,Invoke-OERStructure]: Authorization_RequestDenied: Insufficient privileges to complete the operation.
  === 5.1d-by-name -Prune, for real -- rows: 4; warnings: 0
    [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
    [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
    [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Eligible) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
    [directoryRoleAssignments] Reports Reader -> oer-s64-rag (Active) | Failed | could not resolve directory role 'Reports Reader': Authorization_RequestDenied: Insufficient privileges to complete the operation.
  action counts: Failed=4
  Error records collected: 84; distinct: 4
  ERROR []:
  ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: Forbidden (Forbidden).
  ERROR [Authorization_RequestDenied]: Authorization_RequestDenied: Insufficient privileges to complete the operation.
  ERROR [Authorization_RequestDenied,Invoke-OERStructure]: Authorization_RequestDenied: Insufficient privileges to complete the operation.
  === 5.1e-by-id -Prune -WhatIf -- rows: 6; warnings: 0
    [directoryRoleAssignments] <Reports Reader> (Eligible) | Failed | could not read the eligible assignments of directory role '<Reports Reader>', so nothing in this pair was pruned or reported Extra: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> (Active) | Failed | could not read the active assignments of directory role '<Reports Reader>', so nothing in this pair was pruned or reported Extra: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-user1> (Eligible) | Failed | could not read the eligible assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-user1> (Active) | Failed | could not read the active assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-rag> (Eligible) | Failed | could not read the eligible assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-rag> (Active) | Failed | could not read the active assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  action counts: Failed=6
  Error records collected: 90; distinct: 8
  ERROR []:
  ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: Forbidden (Forbidden).
  ERROR [UnknownError]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Get-OEREligibleDirectoryRoleAssignment]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Invoke-OERStructure]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Get-OERActiveDirectoryRoleAssignment]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Invoke-OERStructure]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  === 5.1e-by-id -Prune, for real -- rows: 6; warnings: 0
    [directoryRoleAssignments] <Reports Reader> (Eligible) | Failed | could not read the eligible assignments of directory role '<Reports Reader>', so nothing in this pair was pruned or reported Extra: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> (Active) | Failed | could not read the active assignments of directory role '<Reports Reader>', so nothing in this pair was pruned or reported Extra: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-user1> (Eligible) | Failed | could not read the eligible assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-user1> (Active) | Failed | could not read the active assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-rag> (Eligible) | Failed | could not read the eligible assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
    [directoryRoleAssignments] <Reports Reader> -> <oer-s64-rag> (Active) | Failed | could not read the active assignments of '<Reports Reader>': UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  action counts: Failed=6
  Error records collected: 90; distinct: 8
  ERROR []:
  ERROR [InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest]: Response status code does not indicate success: Forbidden (Forbidden).
  ERROR [UnknownError]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Get-OEREligibleDirectoryRoleAssignment]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Invoke-OERStructure]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleEligibilitySchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Get-OERActiveDirectoryRoleAssignment]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  ERROR [UnknownError,Invoke-OERStructure]: UnknownError: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleAssignmentSchedule.Read.Directory,RoleAssignmentSchedule.ReadWrite.Directory,RoleManagement.ReadWrite.Directory,RoleManagement.Read.Directory,RoleManagement.Read.All.","instanceAnnotations":[]}
  Raw status of the role-definition lookup for this identity: 403 Authorization_RequestDenied
  Raw status of the eligibility schedule read for this identity: 403 UnknownError
  Raw status of the assignment schedule read for this identity: 403 UnknownError
  Done. Copy the lines above into check 5.1.
  the refused-read process exit code: 0
  ```

- [x] **5.2 Nothing was written by the refused identity.** Back in this window, as `oer-live-cc`.

  ```powershell
  $After51 = @(Get-S64State)
  "rows before 5.1: $($Before51.Count); after: $($After51.Count); every schedule, window and member the same: $((Get-S64StateKey $Before51) -ceq (Get-S64StateKey $After51))"
  ```

  **Expect:** the same count on both sides and `True`.
  **Failure looks like:** `False` -- something changed while only the refused identity ran: stop and
  compare the two states (`Show-S64State`).
  **Result:** (CC as oer-live-cc, 2026-09-29, redacted per docs/live-verification/README.md)
  Pass: rows before 5.1: 9; after: 9; every row the same: True. Compared as formatted rows (principal, type, member type, status, expiration, window) between the state printed after 4.3 and 4.5 and a fresh read, since 5.1 and 5.2 ran in separate processes here; schedule ids and times were not compared.

  ```text
  rows before 5.1: 9; after: 9; every row the same: True
  ##### step  +code -- 2026-09-29 22:52:18
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- 5.2 now: Reports Reader, Eligible: 3 row(s)
      <oer-s64-rag> (Group); MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 1; end set
  --- 5.2 now: Reports Reader, Active: 2 row(s)
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  --- 5.2 now: Message Center Reader, Eligible: 1 row(s)
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 3; end set
  --- 5.2 now: Message Center Reader, Active: 3 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-ccrag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 1; end set
  ```

---

### 6. Manual (operator) -- an activation is neither matched nor pruned

**Run by Philip, in his own PowerShell 7 window, as himself -- never by the certificate identity,
and last before the Teardown (ruling R18).** Leave the Claude window alone while this runs. The
check: Philip is made eligible for Reports Reader for a day through a document, activates it in
the Microsoft Entra admin center, and then the same document runs with `-Prune`. The document
declares Reports Reader Active for `oer-s64-user1`, so the (Reports Reader, Active) pair is read and
Philip's activation sits in it. The Activated filter must keep that row out entirely: NO row names
him in the Active pair. A `Skipped` own-assignment row there would mean the filter failed and only
the own-assignment guard held.

- [x] **6.1 Manual (operator) -- a document makes Philip eligible, he activates in the portal, and a `-Prune` run neither matches nor prunes the activation.**

  (a) Before signing in: in the Microsoft Entra admin center, ACTIVATE your own Privileged Role
  Administrator role if it is eligible (the sign-in's token must carry it). Then, in a NEW
  PowerShell 7 window of your own on the machine that holds the clone, paste the Setup variables
  block from `$Repo` down to `$AssignmentBaselinePath` (the assignments only -- not the build
  lines), then this block:

  ```powershell
  Set-Location $Repo
  $Sep = [System.IO.Path]::PathSeparator
  $env:PSModulePath = (Resolve-Path ./output/module).Path + $Sep + (Resolve-Path ./output/RequiredModules).Path + $Sep + $env:PSModulePath
  Import-Module Omnicit.EntraRBAC -Force
  $ErrorActionPreference = 'Continue'
  $null = Connect-OER -TenantId $TenantId -Interactive -ErrorAction Stop
  $Me = [string](Get-MgContext).Account
  $MeId = & (Get-Module Omnicit.EntraRBAC) { Get-OERSignedInObjectId }
  $MeRaw = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me?$select=id' -OutputType HashTable -SkipHttpErrorCheck
  $MeRoles = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/me/transitiveMemberOf/microsoft.graph.directoryRole?$select=displayName' -OutputType HashTable -SkipHttpErrorCheck
  # The identity check, BEFORE anything else: True/False only, never the ids, and a False stops here.
  $S64MeTenantOk = [string](Get-MgContext).TenantId -eq $TenantId
  $S64MePersonOk = ([string](Get-MgContext).ClientId -notin @($AppId, $NoPermAppId)) -and [bool]$Me -and -not $Me.StartsWith($Prefix)
  $S64MeIdOk     = [bool]$MeId -and [string]::Equals([string]$MeRaw['id'], [string]$MeId, [System.StringComparison]::OrdinalIgnoreCase)
  $S64MePraOk    = @($MeRoles['value'] | Where-Object { $_['displayName'] -eq 'Privileged Role Administrator' }).Count -eq 1
  Write-Host "identity check: tenant is the test tenant: $S64MeTenantOk"
  Write-Host "identity check: a person's delegated sign-in, not a certificate identity: $S64MePersonOk"
  Write-Host "identity check: the token's object id is this user's (v1.0/me): $S64MeIdOk"
  Write-Host "Privileged Role Administrator active for this user: $S64MePraOk"
  if (-not ($S64MeTenantOk -and $S64MePersonOk -and $S64MeIdOk)) { throw 'The identity check failed: nothing below may run.' }
  if (-not $S64MePraOk) { throw 'Privileged Role Administrator is not active for this sign-in: activate it, run Disconnect-OER, and paste this block again.' }
  ```

  Then paste the Setup blocks "The helpers" and "The test principals" as they stand, and run
  0.5's block (read-only). Then check that the module's user lookup finds you by `$Me`:

  ```powershell
  "the user lookup by `$Me finds this user: $([string]::Equals([string](Get-S64RawUser -Upn $Me).Id, [string]$MeId, [System.StringComparison]::OrdinalIgnoreCase))"
  ```

  (b) The document -- Reports Reader eligible for you for one day, and active for `oer-s64-user1`
  for one day -- its `-Prune` plan with the assertion that allows you and nobody else outside the
  prefix, and, only when it passed, the apply:

  ```powershell
  $Doc6 = New-S64Doc -Assignment (New-S64Entry -Role $RoleRR -Principal $Me -Type User -Kind Eligible -Days 1), (New-S64Entry -Role $RoleRR -Principal $User1Upn -Kind Active -Days 1)
  Show-S64State -State @(Get-S64State) -Label '6.1b before' -Role $RoleRR
  Invoke-S64Check -Id '6.1b' -Json $Doc6 -Include DirectoryRoleAssignments -Prune
  $Ok61b = Assert-S64PruneTarget -Result $S64Result -Label '6.1b plan' -AllowPrincipalId $MeId
  ```

  ```powershell
  if ($Ok61b) { Invoke-S64Check -Id '6.1c' -Json $Doc6 -Include DirectoryRoleAssignments -Prune -Apply; $null = Assert-S64PruneTarget -Result $S64Result -Label '6.1c applied' -AllowPrincipalId $MeId } else { Write-Host 'not run: the 6.1b assertion failed' }
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $MeId -Label '6.1c-me-raw' -Want 1
  ```

  (c) In the Microsoft Entra admin center (entra.microsoft.com), signed in as yourself: **Identity
  governance > Privileged Identity Management > My roles > Microsoft Entra roles > Eligible
  assignments**, find **Reports Reader**, choose **Activate**, set the duration to **1 hour** (1.3
  printed the maximum; the baseline allows one hour), enter the justification `oer-s64 6.1`, and
  choose **Activate**. A freshly created eligibility can take a minute or two to appear there. Wait
  until **Active assignments** shows Reports Reader for you. Then, back in your window:

  ```powershell
  Invoke-S64Call -Cmdlet Get-OERActiveDirectoryRoleAssignment -Splat @{ Role = $RoleRR; User = $Me } -Label '6.1d your active rows'
  $S64Out | ForEach-Object { '    ' + (Format-S64Row $_) }
  ```

  (d) The same document with `-Prune`: the plan, the assertion, and -- only when it passed -- the
  run; then the one line this check is for. This assertion does NOT allow you: a `would remove` of
  your own activation stops the gate here, and the `-Prune` line does not run.

  ```powershell
  Invoke-S64Check -Id '6.1e' -Json $Doc6 -Include DirectoryRoleAssignments -Prune
  $Ok61e = Assert-S64PruneTarget -Result $S64Result -Label '6.1e plan'
  ```

  ```powershell
  if ($Ok61e) { Invoke-S64Check -Id '6.1f' -Json $Doc6 -Include DirectoryRoleAssignments -Prune -Apply; $null = Assert-S64PruneTarget -Result $S64Result -Label '6.1f applied' } else { Write-Host 'not run: the 6.1e assertion failed' }
  "rows naming you in the (Reports Reader, Active) pair: $(@($S64Result | Where-Object { $_.Section -eq 'directoryRoleAssignments' -and [string]$_.Item -match '\(Active\)$' -and ([string]$_.Item -match [regex]::Escape([string]$MeId) -or [string]$_.Item -match [regex]::Escape($Me)) }).Count)"
  ```

  **Expect:** (a) all four lines `True`, and no exception, then `the user lookup by $Me finds this user: True` (if it
  prints `False` -- a guest account, whose sign-in name is not its user principal name here -- use
  `$MeId` wherever this check writes `$Me` as a principal, `-PrincipalId $MeId` for `-User $Me`, and
  record it). (b) `6.1b before` lists the direct Reports Reader rows sections 3 and 4 left:
  Eligible `oer-s64-user1`, `oer-s64-rag` and -- while 4.2's one-day window lasts --
  `oer-s64-user2`; Active `oer-s64-user1` (permanent) and `oer-s64-rag`. The plan: `Valid = True`;
  one `would remove` row, with its warning and its `What if:` line, for EVERY one of those rows
  except `oer-s64-user1`'s Active, which the document declares -- `oer-s64-rag`'s two included:
  you are a member of no `oer-s64` group, so the group guard, which reads your group memberships
  once for this run, leaves them to be pruned; then
  `Reports Reader -> <Me> (Eligible) | Skipped | would create the eligible assignment (time-bound assignment (1 days) is absent)`
  and
  `Reports Reader -> oer-s64-user1@<test domain> (Active) | Skipped | would update the active assignment (window differs (live permanent, declared 1 days))`.
  The assertion: every target `allowed: True` -- all `oer-s64` -- and `every one allowed: True`. The
  apply: the same targets `Removed`, `<Me> (Eligible) | Created`, `oer-s64-user1 ... (Active) | Updated`;
  no error; the raw read one row for you, `memberType Direct`, a window of 1 day(s). (c) the
  portal shows the activation. `6.1d`: one row,
  `<Me> (User) Activated; MemberType Direct; scope '/'; ...` -- the check is not vacuous: an
  activation IS in the (Reports Reader, Active) pair's read. (d) The plan: `Valid = True`; exactly
  two rows, `Reports Reader -> <Me> (Eligible) | Unchanged | assignment matches` and
  `Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches`;
  `Unchanged=2`; no warning; the assertion `0; every one allowed: True`. The run: the same two rows.
  Then `rows naming you in the (Reports Reader, Active) pair: 0` -- not `Unchanged`, not `Extra`,
  not `Removed`, not `Skipped`.
  **Failure looks like:** a `Skipped` row naming `<Me>` in the Active pair, with the reason that it
  belongs to the signed-in identity -- the Activated filter failed and only the own-assignment guard
  held: record it, it is a defect; an `Extra` or `would remove` row for `<Me>` in the 6.1e plan --
  the Activated filter AND the own-assignment guard failed: the assertion prints `STOP` and the
  `-Prune` line does not run; deactivate in the portal first, then record it. `6.1d` with no row --
  wait until the portal shows the activation and read again. (a) throwing
  `The identity check failed ...`: stop and record which line printed `False`; throwing
  `Privileged Role Administrator is not active ...`: activate it, run `Disconnect-OER` and paste the
  block again. The Eligible row not `Unchanged`: the one-day window did not converge; record the raw
  window. `oer-s64-rag`'s rows in the 6.1b plan
  `Skipped | prune withheld: the signed-in identity's group memberships could not be read, ...`
  -- your delegated membership read was refused: record the message; they are then not removed,
  and the Teardown removes them. `oer-s64-rag`'s rows `Skipped` with the group guard's reason --
  you are a member of `oer-s64-rag` after all: stop and record it.
  **Result:**

  Pass (the operator as himself, 2026-09-30; checked by CC against Expect). All four identity lines True and the user lookup True; the first attempt, made before 0.5 had run, was stopped by the gate (every target <not a test object>, every one allowed: False) and wrote nothing. 6.1b: 4 targets, all oer-s64 test objects, every one allowed True; 6.1c Removed=4, <Me> (Eligible) Created, oer-s64-user1 (Active) Updated (permanent to one day -- no refusal, since its eligible assignment had just been removed and the active one was hours old); the raw read one row for <Me>, a window of 1 day. 6.1d: one row <Me> (User) Activated; Direct. 6.1e: Unchanged=2, 0 targets, no row naming <Me> in the (Reports Reader, Active) pair: the Activated filter held. 6.1f and the count line were not run: 6.1e's plan held 0 targets, so the apply would have changed nothing.

  ```text
  --- identity check ---
  identity check: tenant is the test tenant: True
  identity check: a person's delegated sign-in, not a certificate identity: True
  identity check: the token's object id is this user's (v1.0/me): True
  Privileged Role Administrator active for this user: True
  the user lookup by $Me finds this user: True
  
  --- 6.1b before ---
  --- 6.1b before: Reports Reader, Eligible: 3 row(s)
      <oer-s64-rag> (Group); MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 1; end set
  --- 6.1b before: Reports Reader, Active: 2 row(s)
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  
  --- 6.1b plan (-Prune -WhatIf) ---
  What if: Remove undeclared eligible directory role assignment: Reports Reader -> 00000000-0000-0000-0000-000000000005 (Eligible)
  What if: Remove undeclared eligible directory role assignment: Reports Reader -> 00000000-0000-0000-0000-000000000007 (Eligible)
  What if: Remove undeclared eligible directory role assignment: Reports Reader -> 00000000-0000-0000-0000-000000000006 (Eligible)
  What if: Remove undeclared active directory role assignment: Reports Reader -> 00000000-0000-0000-0000-000000000007 (Active)
  What if: create eligible directory role assignment: Reports Reader -> person3@example.com (Eligible)
  What if: update active directory role assignment: Reports Reader -> person1@example.com (Active)
  --- errors: 0 --- results: 6 --- action counts: Skipped=6
      target: Reports Reader -> <oer-s64-user1> (Eligible) -- Skipped; allowed: True
      target: Reports Reader -> <oer-s64-rag> (Eligible) -- Skipped; allowed: True
      target: Reports Reader -> <oer-s64-user2> (Eligible) -- Skipped; allowed: True
      target: Reports Reader -> <oer-s64-rag> (Active) -- Skipped; allowed: True
  --- 6.1b plan: prune targets (would remove, removed or Extra): 4; every one allowed: True
  
  --- 6.1c apply (-Prune -Confirm:$false) ---
  --- errors: 0 --- results: 6
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user1> (Eligible) | Removed
      [directoryRoleAssignments] Reports Reader -> <oer-s64-rag> (Eligible) | Removed
      [directoryRoleAssignments] Reports Reader -> <oer-s64-user2> (Eligible) | Removed
      [directoryRoleAssignments] Reports Reader -> <oer-s64-rag> (Active) | Removed
      [directoryRoleAssignments] Reports Reader -> <Me> (Eligible) | Created | created the eligible assignment (time-bound assignment (1 days) is absent)
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Updated | updated the active assignment (window differs (live permanent, declared 1 days))
  --- action counts: Created=1, Removed=4, Updated=1
  --- 6.1c applied: prune targets (would remove, removed or Extra): 4; every one allowed: True
  --- 6.1c-me-raw: raw roleEligibilitySchedules of <Reports Reader> for <Me>: 1 row(s)
      memberType Direct; directoryScopeId '/'; assignmentType (none); status Provisioned; expiration type afterDateTime, endDateTime set True, duration (none); window 1 day(s)
  
  --- activation in the portal (Reports Reader, 1 hour, justification oer-s64 6.1) ---
  --- 6.1d your active rows (Get-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User <Me>): objects returned: 1, errors 0
      <Me> (User) Activated; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 1; end set
  
  --- 6.1e plan (-Prune -WhatIf), with the activation live ---
  --- warnings: 0 --- errors: 0 --- results: 2
      [directoryRoleAssignments] Reports Reader -> <Me> (Eligible) | Unchanged | assignment matches
      [directoryRoleAssignments] Reports Reader -> oer-s64-user1@<test domain> (Active) | Unchanged | assignment matches
  --- action counts: Unchanged=2
  --- 6.1e plan: prune targets (would remove, removed or Extra): 0; every one allowed: True
  (6.1f's apply and the line "rows naming you in the (Reports Reader, Active) pair" were NOT run.)
  ```

- [~] **6.2 Manual (operator) -- clean up: the activation deactivated, your eligibility removed, you signed out, and your Privileged Role Administrator activation ended.** In your window.

  In the admin center: **My roles > Microsoft Entra roles > Active assignments**, **Reports
  Reader**, **Deactivate** (PIM may refuse a deactivation in the first minutes after an activation:
  wait and try again). Then the plan, and the removal once the plan matches:

  ```powershell
  Invoke-S64Call -Cmdlet Get-OERActiveDirectoryRoleAssignment -Splat @{ Role = $RoleRR; User = $Me } -Label '6.2 your active rows'
  Invoke-S64Call -Cmdlet Remove-OEREligibleDirectoryRoleAssignment -Splat @{ Role = $RoleRR; User = $Me; WhatIf = $true } -Label '6.2 plan'
  ```

  ```powershell
  Invoke-S64Call -Cmdlet Remove-OEREligibleDirectoryRoleAssignment -Splat @{ Role = $RoleRR; User = $Me; Confirm = $false } -Label '6.2 remove'
  $null = Get-S64RawSchedule -Kind Eligible -RoleDefinitionId $RoleIdRR -PrincipalId $MeId -Label '6.2-me-raw' -Want 0
  $null = Get-S64RawSchedule -Kind Active -RoleDefinitionId $RoleIdRR -PrincipalId $MeId -Label '6.2-me-active-raw' -Want 0
  Disconnect-OER
  ```

  Last, once you are signed out: end the Privileged Role Administrator activation you made in
  6.1(a). In the admin center: **Identity governance > Privileged Identity Management > My roles >
  Microsoft Entra roles > Active assignments**, find **Privileged Role Administrator**, choose
  **Deactivate** (the same few-minutes wait may apply). Skip this only if your Privileged Role
  Administrator is a standing active assignment that 6.1(a) did not activate -- then there is
  nothing to deactivate. Close your window; the Teardown runs in the Claude window.

  **Expect:** `6.2 your active rows`: `objects returned: 0` (the deactivation took effect). The
  plan: two requests (the role lookup and the `users` lookup for you), ONE `What if:` line,
  `Performing the operation "Remove eligible directory role assignment" on target "eligible directory role 'Reports Reader' for principal '<your user principal name>' at directory scope '/'"`.
  The removal: the same two requests and one `POST .../roleEligibilityScheduleRequests`; the warning
  `Removing ...`; one object, `Action adminRemove`. Both raw reads: 0 rows. Then the portal's
  **Active assignments** no longer lists Privileged Role Administrator for you (or lists only your
  standing assignment, when you have one) -- record which.
  **Failure looks like:** an active row left -- deactivate first; Graph refusing the removal while
  the activation lasts -- deactivate, wait, and remove again; a row left in either raw read; the
  Privileged Role Administrator activation still listed after the deactivation -- deactivate it
  again, and do not leave it active.
  **Result:**

  Everything in Expect is met in the output except its last line: 6.2 your active rows 0 (deactivated); the plan one What if line; the removal one POST with the warning and one object; both raw reads 0 rows; Disconnect-OER run. The Privileged Role Administrator deactivation does not appear in the output -- the operator confirms it separately -- so this stays [~] until he has.

  ```text
  6.2 your active rows (after the deactivation in the portal): objects returned: 0, errors 0
  6.2 plan: What if: Remove eligible directory role 'Reports Reader' for principal 'person3@example.com' at directory scope '/'. errors 0
  6.2 remove: POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests; WARNING: Removing eligible directory role 'Reports Reader' for principal '<Me>' at directory scope '/'. errors 0, objects returned 1
  --- 6.2-me-raw: raw roleEligibilitySchedules of <Reports Reader> for <Me>: 0 row(s)
  --- 6.2-me-active-raw: raw roleAssignmentSchedules of <Reports Reader> for <Me>: 0 row(s)
  Disconnect-OER: run.
  Privileged Role Administrator deactivation: not in this output; the operator confirms it separately.
  ```

---

### Teardown

Back in the Claude window. Paste the sign-in block again first (a fresh token, and the identity
lines once more). T.1 removes every `oer-s64` assignment through the module's own Remove cmdlets.
T.2 is the prerequisite script's teardown, which does not depend on T.1: it removes the certificate
identity's own Message Center Reader assignment and anything of an `oer-s64` principal still there,
restores both policies from the baseline file rule by rule, re-creates any baseline assignment that
is missing, deletes the test users and groups (deleting `oer-s64-ccrag` ends the certificate
identity's membership of it), and verifies both roles' assignments equal the baseline. There is no
Azure object to restore or delete (R17).

- [x] **T.1 Remove every `oer-s64` assignment through the module.**

  The plan:

  ```powershell
  $T1 = @(Get-S64State | Where-Object {
          $_.MemberType -eq 'Direct' -and (Get-S64Name $_.PrincipalId).StartsWith("$Prefix-", [System.StringComparison]::Ordinal) -and
          ($_.Kind -eq 'Eligible' -or $_.AssignmentType -eq 'Assigned') })
  "direct oer-s64 assignments to remove: $($T1.Count)"
  foreach ($R in $T1) {
      Invoke-S64Call -Cmdlet "Remove-OER$($R.Kind)DirectoryRoleAssignment" -Splat @{ Role = $R.RoleDefinitionId; PrincipalId = $R.PrincipalId; WhatIf = $true } `
          -Label "T.1 plan $($R.Kind) $($R.S64Role) -> $(Get-S64Name $R.PrincipalId)"
  }
  ```

  The removal, only once the plan matches:

  ```powershell
  foreach ($R in $T1) {
      Invoke-S64Call -Cmdlet "Remove-OER$($R.Kind)DirectoryRoleAssignment" -Splat @{ Role = $R.RoleDefinitionId; PrincipalId = $R.PrincipalId; Confirm = $false } `
          -Label "T.1 remove $($R.Kind) $($R.S64Role) -> $(Get-S64Name $R.PrincipalId)"
  }
  Start-Sleep -Seconds 30
  $ST1 = @(Get-S64State)
  Show-S64State -State $ST1 -Label 'T.1 after'
  "direct oer-s64 rows left: $(@($ST1 | Where-Object { $_.MemberType -eq 'Direct' -and (Get-S64Name $_.PrincipalId).StartsWith("$Prefix-", [System.StringComparison]::Ordinal) }).Count)"
  ```

  **Expect:** one removal per direct `oer-s64` row still there. With every earlier check run in
  order, and each time-bound window still open, four: Active Reports Reader `oer-s64-user1`
  (6.1's one day), Eligible Message Center Reader `oer-s64-user2` (2.4's two days), and Active
  Message Center Reader `oer-s64-user1` (4.5's one day) and `oer-s64-ccrag` (the prerequisite
  script's two days) -- 4.5 removed `oer-s64-rag`'s; if section 6 did not run, instead Reports
  Reader Eligible `oer-s64-user1`, `oer-s64-rag` and `oer-s64-user2` (4.2's one day), Reports
  Reader Active `oer-s64-user1` and `oer-s64-rag`, and the same three of Message Center Reader.
  When 4.5 was marked `[~]` because Graph refused the membership, Active Message Center Reader
  holds `oer-s64-rag` (2.7's four days) instead of `oer-s64-user1` and `oer-s64-ccrag`. A
  window that has closed takes its row with it: fewer removals, never other ones. Each plan: NO request (both ids are GUIDs), one `What if:` line
  (`Remove eligible directory role assignment` or `Remove active directory role assignment`, the
  target naming the role definition id and the principal id -- redact), no warning. Each removal:
  one `POST`, the warning `Removing ...`, one object, `Action adminRemove`. After:
  `direct oer-s64 rows left: 0`; `Message Center Reader, Active` still holds `<oer-live-cc>` (T.2
  removes it); a `MemberType Group` row left for `oer-s64-user2` goes with its group's assignment,
  and an inherited row for `<oer-live-cc>` with `oer-s64-ccrag`'s.
  **Failure looks like:** a target that is not an `oer-s64` principal -- impossible by the filter,
  so stop and look; a removal Graph refuses -- record its message; T.2 removes what is left all the
  same. `rows left` above 0 after a minute: read again; Graph lists removals a moment late.
  **Result:**

  Pass after one wait (CC as oer-live-cc, 2026-09-30, redacted per docs/live-verification/README.md). Seven direct oer-s64 rows (the 3.3 re-run had re-created four on Reports Reader). The first run, 3.7 minutes after those four started: every Reports Reader removal refused with ActiveDurationTooShort (the five-minute rule of 3.3), oer-s64-user2's Message Center Reader eligible removed, and the Message Center Reader active removals of oer-s64-user1 and oer-s64-ccrag answered RoleAssignmentDoesNotExist while Graph lists both adminRemove requests Revoked and the rows are gone. The second run, 8 minutes after: both eligible removals accepted; the two active removals again answered RoleAssignmentDoesNotExist with the requests Revoked and the rows gone (recorded as a finding: a successful active removal reported as an error). direct oer-s64 rows left: 0; Message Center Reader Active held only <oer-live-cc>.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  direct oer-s64 assignments to remove: 7
  What if: Performing the operation "Remove eligible directory role assignment" on target "eligible directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000005' at directory scope '/'".
  === T.1 plan Eligible Reports Reader -> oer-s64-user1 -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove eligible directory role assignment" on target "eligible directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000007' at directory scope '/'".
  === T.1 plan Eligible Reports Reader -> oer-s64-rag -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove active directory role assignment" on target "active directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000005' at directory scope '/'".
  === T.1 plan Active Reports Reader -> oer-s64-user1 -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove active directory role assignment" on target "active directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000007' at directory scope '/'".
  === T.1 plan Active Reports Reader -> oer-s64-rag -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove eligible directory role assignment" on target "eligible directory role '00000000-0000-0000-0000-000000000003' for principal '00000000-0000-0000-0000-000000000006' at directory scope '/'".
  === T.1 plan Eligible Message Center Reader -> oer-s64-user2 -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Message Center Reader>' to '<Message Center Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 0
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove active directory role assignment" on target "active directory role '00000000-0000-0000-0000-000000000003' for principal '00000000-0000-0000-0000-000000000005' at directory scope '/'".
  === T.1 plan Active Message Center Reader -> oer-s64-user1 -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Message Center Reader>' to '<Message Center Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove active directory role assignment" on target "active directory role '00000000-0000-0000-0000-000000000003' for principal '00000000-0000-0000-0000-000000000009' at directory scope '/'".
  === T.1 plan Active Message Center Reader -> oer-s64-ccrag -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Message Center Reader>' to '<Message Center Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-ccrag>'.
  --- warnings: 0
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  --- T.1 before: Reports Reader, Eligible: 2 row(s)
      <oer-s64-rag> (Group); MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 7; end set
  --- T.1 before: Reports Reader, Active: 2 row(s)
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  --- T.1 before: Message Center Reader, Eligible: 1 row(s)
      <oer-s64-user2> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 3; end set
  --- T.1 before: Message Center Reader, Active: 3 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-ccrag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 1; end set
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === T.1 remove Eligible Reports Reader -> oer-s64-user1 -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 1
      WARNING: Removing eligible directory role '<Reports Reader>' for principal '<oer-s64-user1>' at directory scope '/'.
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [ActiveDurationTooShort,Remove-OEREligibleDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
  --- objects returned: 0
  === T.1 remove Eligible Reports Reader -> oer-s64-rag -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 1
      WARNING: Removing eligible directory role '<Reports Reader>' for principal '<oer-s64-rag>' at directory scope '/'.
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [ActiveDurationTooShort,Remove-OEREligibleDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
  --- objects returned: 0
  === T.1 remove Active Reports Reader -> oer-s64-user1 -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 1
      WARNING: Removing active directory role '<Reports Reader>' for principal '<oer-s64-user1>' at directory scope '/'.
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [ActiveDurationTooShort,Remove-OERActiveDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
  --- objects returned: 0
  === T.1 remove Active Reports Reader -> oer-s64-rag -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 1
      WARNING: Removing active directory role '<Reports Reader>' for principal '<oer-s64-rag>' at directory scope '/'.
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [ActiveDurationTooShort,Remove-OERActiveDirectoryRoleAssignment]: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
  --- objects returned: 0
  === T.1 remove Eligible Message Center Reader -> oer-s64-user2 -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Message Center Reader>' to '<Message Center Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user2>'.
  --- warnings: 1
      WARNING: Removing eligible directory role '<Message Center Reader>' for principal '<oer-s64-user2>' at directory scope '/'.
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  === T.1 remove Active Message Center Reader -> oer-s64-user1 -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Message Center Reader>' to '<Message Center Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 1
      WARNING: Removing active directory role '<Message Center Reader>' for principal '<oer-s64-user1>' at directory scope '/'.
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [RoleAssignmentDoesNotExist,Remove-OERActiveDirectoryRoleAssignment]: RoleAssignmentDoesNotExist: The Role assignment does not exist.
  --- objects returned: 0
  === T.1 remove Active Message Center Reader -> oer-s64-ccrag -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Message Center Reader>' to '<Message Center Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-ccrag>'.
  --- warnings: 1
      WARNING: Removing active directory role '<Message Center Reader>' for principal '<oer-s64-ccrag>' at directory scope '/'.
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [RoleAssignmentDoesNotExist,Remove-OERActiveDirectoryRoleAssignment]: RoleAssignmentDoesNotExist: The Role assignment does not exist.
  --- objects returned: 0
  --- T.1 after: Reports Reader, Eligible: 2 row(s)
      <oer-s64-rag> (Group); MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
      <oer-s64-user1> (User); MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 7; end set
  --- T.1 after: Reports Reader, Active: 2 row(s)
      <oer-s64-rag> (Group) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 5; end set
      <oer-s64-user1> (User) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'noExpiration'; DurationDays (none); end never
  --- T.1 after: Message Center Reader, Eligible: 0 row(s)
  --- T.1 after: Message Center Reader, Active: 1 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
  direct oer-s64 rows left: 4
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  direct oer-s64 assignments to remove: 4
  What if: Performing the operation "Remove eligible directory role assignment" on target "eligible directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000005' at directory scope '/'".
  === T.1 plan Eligible Reports Reader -> oer-s64-user1 -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove eligible directory role assignment" on target "eligible directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000007' at directory scope '/'".
  === T.1 plan Eligible Reports Reader -> oer-s64-rag -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove active directory role assignment" on target "active directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000005' at directory scope '/'".
  === T.1 plan Active Reports Reader -> oer-s64-user1 -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 0
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  What if: Performing the operation "Remove active directory role assignment" on target "active directory role '00000000-0000-0000-0000-000000000001' for principal '00000000-0000-0000-0000-000000000007' at directory scope '/'".
  === T.1 plan Active Reports Reader -> oer-s64-rag -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 0
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 0
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 0
  now (UTC): 07:25:31
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  === T.1 remove Eligible Reports Reader -> oer-s64-user1 -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 1
      WARNING: Removing eligible directory role '<Reports Reader>' for principal '<oer-s64-user1>' at directory scope '/'.
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  === T.1 remove Eligible Reports Reader -> oer-s64-rag -- Remove-OEREligibleDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleEligibilityScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 1
      WARNING: Removing eligible directory role '<Reports Reader>' for principal '<oer-s64-rag>' at directory scope '/'.
  --- errors published by Remove-OEREligibleDirectoryRoleAssignment: 0 (other records collected, not shown: 0)
  --- objects returned: 1
  === T.1 remove Active Reports Reader -> oer-s64-user1 -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-user1>'.
  --- warnings: 1
      WARNING: Removing active directory role '<Reports Reader>' for principal '<oer-s64-user1>' at directory scope '/'.
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [RoleAssignmentDoesNotExist,Remove-OERActiveDirectoryRoleAssignment]: RoleAssignmentDoesNotExist: The Role assignment does not exist.
  --- objects returned: 0
  === T.1 remove Active Reports Reader -> oer-s64-rag -- Remove-OERActiveDirectoryRoleAssignment
  --- requests, in the order sent: 1
      POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests
  --- the cmdlet's own verbose lines: 2
      [Remove-OERActiveDirectoryRoleAssignment] Resolved role '<Reports Reader>' to '<Reports Reader>'.
      [Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '<oer-s64-rag>'.
  --- warnings: 1
      WARNING: Removing active directory role '<Reports Reader>' for principal '<oer-s64-rag>' at directory scope '/'.
  --- errors published by Remove-OERActiveDirectoryRoleAssignment: 1 (other records collected, not shown: 8)
      ERROR [RoleAssignmentDoesNotExist,Remove-OERActiveDirectoryRoleAssignment]: RoleAssignmentDoesNotExist: The Role assignment does not exist.
  --- objects returned: 0
  --- T.1 after: Reports Reader, Eligible: 0 row(s)
  --- T.1 after: Reports Reader, Active: 0 row(s)
  --- T.1 after: Message Center Reader, Eligible: 0 row(s)
  --- T.1 after: Message Center Reader, Active: 1 row(s)
      <oer-live-cc> (ServicePrincipal) Assigned; MemberType Direct; scope '/'; status Provisioned; expiration 'afterDateTime'; DurationDays 2; end set
  direct oer-s64 rows left: 0
  ```

- [~] **T.2 The prerequisite script's teardown -- its plan, then the run.**

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -Teardown -WhatIf
  ```

  Only once the plan matches:

  ```powershell
  pwsh -NoProfile -File $Prereq -TenantId $TenantId -TenantAlias $Alias -ClientId $AppId -CertificateThumbprint $Thumbprint -UserDomain $Domain -ExpectedTenantDisplayName $OrgName -RepoPath $Repo -Teardown -Unattended
  ```

  **Expect:** both runs, the lines Setup lists: `[oer-s64] Mode: RESTORE and REMOVE. ...`, the
  `Directory roles (fixed): ...` line with `(exists: True)` twice, both identity lines ending `True`
  after every sign-in, the `Identified the test tenant: ...` line, and -- the real run only -- the
  `Unattended run: ...` line; no sign-in with `-IncludeARM`. Then, in order:
  `[oer-s64] Teardown: oer-s64 assignments on the two roles: 0` (T.1 removed them, `oer-s64-ccrag`'s
  included; any other count lists each one -- for the group,
  `[oer-s64] Removed the active 'Message Center Reader' assignment of oer-s64-ccrag.`); the
  certificate identity's own Message Center Reader assignment (a `What if:` line, then
  `[oer-s64] Removed the active Message Center Reader assignment of oer-live-cc.`);
  `[oer-s64] Teardown: directory role 'Reports Reader': rules differing from the policy baseline: 0`
  when 1.3 recorded both permanent kinds allowed (3.1 closed them and the document opened them
  again -- any rule listed there, record it) and
  `[oer-s64] Teardown: directory role 'Message Center Reader': rules differing from the policy baseline: 1 (Expiration_Admin_Assignment)`
  (2.5), with ONE
  `What if: Performing the operation "Restore rule Expiration_Admin_Assignment from the policy baseline (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Message Center Reader'".`
  line in the plan and `[oer-s64] Restored rule Expiration_Admin_Assignment of 'Message Center Reader'.`
  in the run; per role `... restored: not attempted (WhatIf)` in the plan and `... restored: True`
  in the run; per role `... baseline assignments missing and re-created: 0`; the groups
  `oer-s64-rag`, `oer-s64-plain` and `oer-s64-ccrag` and the two users (`What if:` lines, then
  `Deleted group ...` / `Deleted user ...` -- `[oer-s64] Deleted group oer-s64-ccrag.` ends the
  certificate identity's membership of it); per role, last,
  `... direct assignments equal the assignment baseline: not checked (WhatIf)` in the plan and
  `... direct assignments equal the assignment baseline: True` in the run; the sweep,
  `[oer-s64] Sweep: no user or group starting with 'oer-s64' is left.` (Graph's list can lag a
  moment behind the deletes -- a `Sweep, still present: ...` line then, `oer-s64-ccrag` included,
  is not a failure, T.3 reads again); the summary;
  `WhatIf: nothing was created, restored, removed or written.` in
  the plan; `[oer-s64] Done.` Nothing else is a target: no directory role other than the two,
  nothing in Azure. Paste both outputs redacted per the rules at the top.
  **Failure looks like:** a target outside that list -- stop, do not run the real teardown; a rule
  restore Graph refuses, or `restored: False` -- the script stops before it deletes anything;
  record Graph's message and look at the policy before running it again;
  `direct assignments equal the assignment baseline: False` -- record the difference and restore it
  by hand from the assignment baseline before T.4; a `Refusing the teardown: ` line; a baseline file
  missing -- find it before anything else, never delete the principals while a policy may be
  unrestored. Re-run the teardown after a fix (it only restores what differs and removes what is
  still there) and record both runs.
  **Result:**

  Stopped at a stop condition (403 on the app path), and not worked around. The plan matched Expect (0 oer-s64 assignments; the own assignment; Reports Reader 0 rules differing, Message Center Reader 1, Expiration_Admin_Assignment; three groups and two users). The run: the own assignment "already gone" (404 RoleAssignmentDoesNotExist; T.3 confirms it gone); Reports Reader restored True (0 differing), Message Center Reader Expiration_Admin_Assignment restored, restored True; baseline assignments re-created 0 and 0; the three groups and oer-s64-user1 deleted; then DELETE oer-s64-user2 answered 403 Authorization_RequestDenied and the script stopped. oer-s64-user2 was the member of the role-assignable oer-s64-rag, which is only soft-deleted (restorable for 30 days), and Microsoft Learn ("Delete a user") says User.ReadWrite.All is not enough app-only to delete a privileged user; it needs a higher Entra role (Privileged Authentication Administrator), which this identity must not hold. oer-s64-user2 is left disabled and without any role schedule; the operator deletes it by hand. Lesson for the next prerequisite script: remove the members of a role-assignable test group before deleting the group.

  ```text
  [oer-s64] Mode: RESTORE and REMOVE. Tenant alias '<Alias>', tenant <TenantId>, prefix 'oer-s64', expected organization '<test tenant>'.
  [oer-s64] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Policy baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json (exists: True). Assignment baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json (exists: True).
  [oer-s64] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s64] No Tenant Profile '<Alias>' on this machine; the sign-in names -TenantId.
  [oer-s64] Microsoft Graph sign-in: signing in to Microsoft Graph as the certificate identity (app-only, certificate from Cert:\CurrentUser\My, process-scoped context, no Azure Resource Manager).
  [oer-s64] Microsoft Graph sign-in identity check: session app id is oer-live-cc: True
  [oer-s64] Microsoft Graph sign-in identity check: tenant is the test tenant: True
  [oer-s64] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s64] Directory role 'Reports Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] Directory role 'Message Center Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] Directory role 'Reports Reader': both baselines name the same role definition and policy as this tenant: True
  [oer-s64] Directory role 'Message Center Reader': both baselines name the same role definition and policy as this tenant: True
  [oer-s64] Teardown: oer-s64 assignments on the two roles: 0
  What if: Performing the operation "Remove the certificate identity's own assignment (Microsoft Graph v1.0 roleAssignmentScheduleRequests, adminRemove)" on target "active directory role 'Message Center Reader' for the service principal of oer-live-cc at directory scope '/'".
  [oer-s64] Teardown: directory role 'Reports Reader': rules differing from the policy baseline: 0
  [oer-s64] Teardown: directory role 'Reports Reader': restored: not attempted (WhatIf)
  [oer-s64] Teardown: directory role 'Message Center Reader': rules differing from the policy baseline: 1 (Expiration_Admin_Assignment)
  What if: Performing the operation "Restore rule Expiration_Admin_Assignment from the policy baseline (Microsoft Graph v1.0 PATCH)" on target "PIM policy of directory role 'Message Center Reader'".
  [oer-s64] Teardown: directory role 'Message Center Reader': restored: not attempted (WhatIf)
  [oer-s64] Teardown: directory role 'Reports Reader': baseline assignments missing and re-created: 0
  [oer-s64] Teardown: directory role 'Message Center Reader': baseline assignments missing and re-created: 0
  What if: Performing the operation "Delete security group" on target "oer-s64-rag".
  What if: Performing the operation "Delete security group" on target "oer-s64-plain".
  What if: Performing the operation "Delete security group" on target "oer-s64-ccrag".
  What if: Performing the operation "Delete test user" on target "person1@example.com".
  What if: Performing the operation "Delete test user" on target "person2@example.com".
  [oer-s64] Teardown: directory role 'Reports Reader': direct assignments equal the assignment baseline: not checked (WhatIf)
  [oer-s64] Teardown: directory role 'Message Center Reader': direct assignments equal the assignment baseline: not checked (WhatIf)
  [oer-s64] Sweep, still present: user 'person1@example.com' (00000000-0000-0000-0000-000000000005)
  [oer-s64] Sweep, still present: user 'person2@example.com' (00000000-0000-0000-0000-000000000006)
  [oer-s64] Sweep, still present: group 'oer-s64-ccrag' (00000000-0000-0000-0000-000000000009)
  [oer-s64] Sweep, still present: group 'oer-s64-plain' (00000000-0000-0000-0000-000000000008)
  [oer-s64] Sweep, still present: group 'oer-s64-rag' (00000000-0000-0000-0000-000000000007)
  
  [oer-s64] Summary -- REAL object ids. Redact them per docs/live-verification/README.md before pasting:
  
  Kind                             Name                                                                                        Id
  ----                             ----                                                                                        --
  user                             person1@example.com                                                       00000000-0000-0000-0000-000000000005
  user                             person2@example.com                                                       00000000-0000-0000-0000-000000000006
  group                            oer-s64-rag                                                                                 00000000-0000-0000-0000-000000000007
  group                            oer-s64-plain                                                                               00000000-0000-0000-0000-000000000008
  group                            oer-s64-ccrag                                                                               00000000-0000-0000-0000-000000000009
  group member                     oer-s64-rag <- person2@example.com                                        00000000-0000-0000-0000-000000000006
  group member                     oer-s64-ccrag <- oer-live-cc                                                                (none -- not created)
  directory role (built-in, fixed) Reports Reader                                                                              00000000-0000-0000-0000-000000000001
  directory role policy            Reports Reader                                                                              DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000002
  directory role (built-in, fixed) Message Center Reader                                                                       00000000-0000-0000-0000-000000000003
  directory role policy            Message Center Reader                                                                       DirectoryRole_<TenantId>_00000000-0000-0000-0000-000000000004
  own assignment                   Message Center Reader, active, P2D, of oer-live-cc (schedule)                               00000000-0000-0000-0000-000000000011
  group assignment                 Message Center Reader, active, P2D, of oer-s64-ccrag (schedule)                             (none -- not created)
  policy baseline (existed)        <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json    -
  assignment baseline (existed)    <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json -
  
  
  [oer-s64] WhatIf: nothing was created, restored, removed or written.
  [oer-s64] Done.
  [oer-s64] Mode: RESTORE and REMOVE. Tenant alias '<Alias>', tenant <TenantId>, prefix 'oer-s64', expected organization '<test tenant>'.
  [oer-s64] Directory roles (fixed): 'Reports Reader', 'Message Center Reader'. Policy baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-policies.json (exists: True). Assignment baseline: <Repo>\docs\live-verification\raw\s64\baseline-directory-assignments.json (exists: True).
  [oer-s64] Omnicit.EntraRBAC 1.1.0 loaded from <Repo>\output\module\Omnicit.EntraRBAC\1.1.0.
  [oer-s64] No Tenant Profile '<Alias>' on this machine; the sign-in names -TenantId.
  [oer-s64] Microsoft Graph sign-in: signing in to Microsoft Graph as the certificate identity (app-only, certificate from Cert:\CurrentUser\My, process-scoped context, no Azure Resource Manager).
  [oer-s64] Microsoft Graph sign-in identity check: session app id is oer-live-cc: True
  [oer-s64] Microsoft Graph sign-in identity check: tenant is the test tenant: True
  [oer-s64] Identified the test tenant: organization '<test tenant>', tenant id <TenantId>, verified domain <test domain>.
  [oer-s64] Unattended run: the confirmation question is not asked; the identity check and the tenant identification above both passed.
  [oer-s64] Directory role 'Reports Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] Directory role 'Message Center Reader': one built-in role definition and one tenant-wide policy assignment: True (17 rules).
  [oer-s64] Directory role 'Reports Reader': both baselines name the same role definition and policy as this tenant: True
  [oer-s64] Directory role 'Message Center Reader': both baselines name the same role definition and policy as this tenant: True
  [oer-s64] Teardown: oer-s64 assignments on the two roles: 0
  [oer-s64] The active Message Center Reader assignment of oer-live-cc was already gone: Microsoft Graph answered 404 to POST v1.0/roleManagement/directory/roleAssignmentScheduleRequests: RoleAssignmentDoesNotExist -- The Role assignment does not exist.
  [oer-s64] Teardown: directory role 'Reports Reader': rules differing from the policy baseline: 0
  [oer-s64] Teardown: directory role 'Reports Reader': restored: True
  [oer-s64] Teardown: directory role 'Message Center Reader': rules differing from the policy baseline: 1 (Expiration_Admin_Assignment)
  [oer-s64] Restored rule Expiration_Admin_Assignment of 'Message Center Reader'.
  [oer-s64] Teardown: directory role 'Message Center Reader': restored: True
  [oer-s64] Teardown: directory role 'Reports Reader': baseline assignments missing and re-created: 0
  [oer-s64] Teardown: directory role 'Message Center Reader': baseline assignments missing and re-created: 0
  [oer-s64] Deleted group oer-s64-rag.
  [oer-s64] Deleted group oer-s64-plain.
  [oer-s64] Deleted group oer-s64-ccrag.
  [oer-s64] Deleted user person1@example.com.
  [oer-s64] Stopped after this run had written to the tenant or the baseline files (see the lines above): Microsoft Graph answered 403 to DELETE v1.0/users/<id>: Authorization_RequestDenied -- Insufficient privileges to complete the operation.
  ```

- [~] **T.3 Read everything back: both policies and both roles' assignments equal the baselines, no test object is left, and every write of this file named a test object.**

  ```powershell
  Show-S64BaselineDiff -Label 'T.3'
  $ST3 = @(Get-S64State)
  Show-S64State -State $ST3 -Label 'T.3'
  Show-S64AssignmentBaselineDiff -Label 'T.3' -State $ST3
  $F = [uri]::EscapeDataString("startswith(userPrincipalName,'$Prefix')")
  "users starting with the prefix: $(@((Get-S64RawStatus -Uri "v1.0/users?`$filter=$F&`$select=id").Body['value']).Count)"
  $F = [uri]::EscapeDataString("startswith(displayName,'$Prefix')")
  "groups starting with the prefix: $(@((Get-S64RawStatus -Uri "v1.0/groups?`$filter=$F&`$select=id").Body['value']).Count)"
  $All = @(Import-Csv (Join-Path $Raw 'all-results.csv'))
  $All | Where-Object { $_.Action -in 'Created', 'Updated', 'Removed', 'Failed' } |
      ForEach-Object { '    {0} {1} | {2} | {3}' -f $_.CheckId, (Format-S64Text $_.Item), $_.Action, (Format-S64Text $_.Detail) }
  $PrincipalOk = '-> <' + [regex]::Escape($Prefix) + '-'
  $RoleOk = '^(<?(' + [regex]::Escape($RoleRR) + '|' + [regex]::Escape($RoleMCR) + ')>?|' + [regex]::Escape($Prefix) + '-no-such-role)( ->| \(|$)'
  $BadRemoved = @($All | Where-Object { $_.Action -eq 'Removed' -and (Format-S64Text $_.Item) -notmatch $PrincipalOk })
  "Removed rows naming a principal that is not an oer-s64 test object: $($BadRemoved.Count)"
  $BadRole = @($All | Where-Object { (Format-S64Text $_.Item) -notmatch $RoleOk })
  "rows naming a role other than the two: $($BadRole.Count)"
  ```

  **Expect:** `--- T.3: Reports Reader: the baseline names this policy: True; ...; differing from the baseline: 0`
  and the same for Message Center Reader. The state: exactly the baseline -- normally no row at all;
  the assignment diff `only live []` and `only baseline []` for both roles and both kinds (the
  certificate identity's own assignment and `oer-s64-ccrag`'s are gone).
  `users starting with the prefix: 0` and `groups starting with the prefix: 0` (the two users sit
  in Deleted items for 30 days, which is Entra ID's design). The listed rows, and no others: `3.1c`
  `Reports Reader | Updated` and the four `Created`; `3.3b`
  `oer-s64-user1 ... (Eligible) | Updated`; `4.1d` `<oer-s64-user2> (Eligible) | Removed`;
  `4.2b` and `4.2c` `oer-s64-nobody ... | Failed`; `4.2d` `oer-s64-no-such-role ... | Failed`;
  `4.5d`
  `Message Center Reader -> <oer-s64-rag> (Active) | Removed` and
  `Message Center Reader -> oer-s64-user1@<test domain> (Active) | Created` (neither when 4.5 was
  `[~]`); and,
  when section 6 ran, `6.1c`'s `Removed` rows (all named `<oer-s64-...>`),
  `Reports Reader -> <Philip's user principal name> (Eligible) | Created` and
  `Reports Reader -> oer-s64-user1@<test domain> (Active) | Updated`. This window never set `$Me`,
  so the helpers cannot name Philip: that row prints his user principal name exactly as the 6.1
  document wrote it (its domain replaced by `<test domain>` only when it is the test domain) --
  redact it to a `personN@example.com` address before pasting (T.4).
  `Removed rows naming a principal that is not an oer-s64 test object: 0`
  and `rows naming a role other than the two: 0`.
  **Failure looks like:** a policy rule differing from the baseline, or an assignment that is not
  the baseline -- restore it before anything else (the script's `-Teardown` again, or by hand from
  the baseline files) and never delete the raw folder (T.4) while this is not clean: it holds the only
  record of the original state. A count above 0; a `Removed` row naming anything but an `oer-s64`
  principal; a row not listed above.
  **Result:**

  Both policies equal the baseline (differing 0 and 0); both roles' direct assignments equal the assignment baseline (none; only live [] and only baseline [] everywhere; the own assignment and oer-s64-ccrag's are gone); groups starting with the prefix 0; users starting with the prefix 1 -- oer-s64-user2, disabled, 0 eligibility and 0 assignment schedules (T.2). Removed rows naming a principal that is not an oer-s64 test object: 0 (re-counted with the ids restored from the redaction map, since the deleted objects could no longer be read back to name them; the first count printed 4 for that reason); rows naming a role other than the two: 0. The list holds more rows than Expect names: the first 3.3b Failed, the 3.3b re-run and 3.3f, and 4.2b twice -- every one on an oer-s64 test object and the two roles. Operator's user principal name redacted.

  ```text
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  --- raw user read: 0 users match 'oer-s64-user1@<test domain>', not one
  --- raw group read: 0 groups named 'oer-s64-rag', not one
  --- raw group read: 0 groups named 'oer-s64-plain', not one
  --- raw group read: 0 groups named 'oer-s64-ccrag', not one
  --- T.3: Reports Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  --- T.3: Message Center Reader: the baseline names this policy: True; rules live 17, baseline 17; differing from the baseline: 0
  --- T.3: Reports Reader, Eligible: 0 row(s)
  --- T.3: Reports Reader, Active: 0 row(s)
  --- T.3: Message Center Reader, Eligible: 0 row(s)
  --- T.3: Message Center Reader, Active: 0 row(s)
  --- T.3: Reports Reader, Eligible: direct principals live 0, baseline 0; only live []; only baseline []
  --- T.3: Reports Reader, Active: direct principals live 0, baseline 0; only live []; only baseline []
  --- T.3: Message Center Reader, Eligible: direct principals live 0, baseline 0; only live []; only baseline []
  --- T.3: Message Center Reader, Active: direct principals live 0, baseline 0; only live []; only baseline []
  users starting with the prefix: 1
  groups starting with the prefix: 0
      3.1c Reports Reader | Updated | updated directory role management policy for 'Reports Reader' (allowPermanentEligibility=True, allowPermanentActiveAssignment=True)
      3.1c Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Created | created the eligible assignment (time-bound assignment (5 days) is absent)
      3.1c Reports Reader -> oer-s64-user1@<test domain> (Active) | Created | created the active assignment (permanent assignment is absent)
      3.1c Reports Reader -> oer-s64-rag (Eligible) | Created | created the eligible assignment (permanent assignment is absent)
      3.1c Reports Reader -> oer-s64-rag (Active) | Created | created the active assignment (time-bound assignment (5 days) is absent)
      3.3b Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Failed | failed to update the eligible assignment: ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5 minutes.
      4.1d Reports Reader -> <oer-s64-user2> (Eligible) | Removed | removed undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'
      4.2b Reports Reader -> oer-s64-nobody@<test domain> (Eligible) | Failed | principal 'oer-s64-nobody@<test domain>' could not be resolved to an object id
      4.2b Reports Reader -> oer-s64-nobody@<test domain> (Eligible) | Failed | principal 'oer-s64-nobody@<test domain>' could not be resolved to an object id
      4.2c Reports Reader -> oer-s64-nobody@<test domain> (Eligible) | Failed | principal 'oer-s64-nobody@<test domain>' could not be resolved to an object id
      4.2d oer-s64-no-such-role -> oer-s64-user1@<test domain> (Eligible) | Failed | directory role 'oer-s64-no-such-role' could not be resolved to a role definition id
      4.5d Message Center Reader -> <not a test object> (Active) | Removed | removed undeclared active assignment of directory role 'Message Center Reader' for principal '<not a test object>'
      4.5d Message Center Reader -> oer-s64-user1@<test domain> (Active) | Created | created the active assignment (time-bound assignment (1 days) is absent)
      6.1c Reports Reader -> <not a test object> (Eligible) | Removed | removed undeclared eligible assignment of directory role 'Reports Reader' for principal '<not a test object>'
      6.1c Reports Reader -> <not a test object> (Eligible) | Removed | removed undeclared eligible assignment of directory role 'Reports Reader' for principal '<not a test object>'
      6.1c Reports Reader -> <oer-s64-user2> (Eligible) | Removed | removed undeclared eligible assignment of directory role 'Reports Reader' for principal '<oer-s64-user2>'
      6.1c Reports Reader -> <not a test object> (Active) | Removed | removed undeclared active assignment of directory role 'Reports Reader' for principal '<not a test object>'
      6.1c Reports Reader -> person3@example.com (Eligible) | Created | created the eligible assignment (time-bound assignment (1 days) is absent)
      6.1c Reports Reader -> oer-s64-user1@<test domain> (Active) | Updated | updated the active assignment (window differs (live permanent, declared 1 days))
      3.3b Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Updated | updated the eligible assignment (duration differs (live 5 days, declared 7 days))
      3.3b Reports Reader -> oer-s64-user1@<test domain> (Active) | Created | created the active assignment (permanent assignment is absent)
      3.3b Reports Reader -> oer-s64-rag (Eligible) | Created | created the eligible assignment (permanent assignment is absent)
      3.3b Reports Reader -> oer-s64-rag (Active) | Created | created the active assignment (time-bound assignment (5 days) is absent)
      3.3f Reports Reader -> oer-s64-user1@<test domain> (Eligible) | Failed | failed to update the eligible assignment: Microsoft Graph refused the new window (ActiveDurationTooShort), which it does while the principal holds a permanent active assignment of the same role, so the eligible assignment is unchanged. Declare the active assignment time-bound (durationDays), or change the eligible window by hand (Remove-OEREligibleDirectoryRoleAssignment, then New-OEREligibleDirectoryRoleAssignment); the apply engine never removes an assignment to re-create it
  Removed rows naming a principal that is not an oer-s64 test object: 4
  rows naming a role other than the two: 0
  oer-s64-user2 still present: True; enabled: False
  oer-s64-user2 roleEligibilitySchedules (any role): 0
  oer-s64-user2 roleAssignmentSchedules (any role): 0
  identity check: session app id is oer-live-cc: True
  identity check: tenant is the test tenant: True
  ids restored from the redaction map: 5 of 5
  Removed rows naming a principal that is not an oer-s64 test object: 0
      4.1d Reports Reader -> <oer-s64-user2> (Eligible) | Removed
      4.5d Message Center Reader -> <oer-s64-rag> (Active) | Removed
      6.1c Reports Reader -> <oer-s64-user1> (Eligible) | Removed
      6.1c Reports Reader -> <oer-s64-rag> (Eligible) | Removed
      6.1c Reports Reader -> <oer-s64-user2> (Eligible) | Removed
      6.1c Reports Reader -> <oer-s64-rag> (Active) | Removed
  ```

- [x] **T.4 Redact, then delete `raw/s64`.** Only once T.3 printed `differing from the baseline: 0` twice and the assignment diff was empty: the raw folder holds both baseline files, the only records of the original state. Move what the results above need from `docs/live-verification/raw/s64/` into this file, redacted per [README.md](README.md) and the rules at the top, then delete the folder.

  Object ids to `00000000-0000-0000-0000-0000000000NN` -- the two role definition ids, the
  certificate identity's service principal id and the policy half of each directory-role policy id
  included -- the tenant id to `<TenantId>`, the organization and the domain to `<test tenant>` and
  `<test domain>`, user principal names (Philip's included) to `personN@example.com`; no credential,
  no bearer token, no application id, no thumbprint, and nothing copied out of the baseline files.
  That includes the output of 5.1's second process, of Philip's window, of every
  prerequisite-script run, and T.3's list, which prints Philip's user principal name as it stands
  (the Claude window has no `$Me` to name it by).

  ```powershell
  Remove-Item -LiteralPath $Raw -Recurse -Force
  "raw/s64 exists after: $(Test-Path -LiteralPath $Raw)"
  git -C $Repo status --short docs/live-verification
  ```

  **Expect:** `raw/s64 exists after: False`; `git status` shows only this checklist as modified;
  nothing under `raw/` is ever staged. Before the commit, `tests/QA/dochygiene.tests.ps1` is green.
  **Failure looks like:** `raw/s64 exists after: True` -- a file in it is still open (an editor, or
  a second PowerShell window): close it and run the block again. `git status` listing anything
  under `docs/live-verification/raw/`, or any file besides this checklist -- unstage it and find out
  how it got there. A value a scan of this file still finds -- a GUID that is not a `00000000-...`
  placeholder, an address outside `example.com`, the tenant id, the organization or domain name --
  means redaction is not finished: redact it before the commit, and if it was a credential, rotate
  it ([README.md](README.md), "Credentials").
  **Result:**

  raw/s64 exists after: False; git status lists only this checklist under docs/live-verification; the redaction map was deleted too. dochygiene green before the commit.
