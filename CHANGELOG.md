# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

`Invoke-OERStructure -Prune` no longer removes anything because a lookup failed. When a declared
entry cannot be resolved -- a group member, owner or PIM eligibility, an administrative unit member
or scoped role, an access package resource role, or a role assignment under the same `scope` --
nothing in that collection is removed: its undeclared live entries are reported `Skipped`, rather
than removed or `Extra`, with the reason
`prune withheld: declared entry '<entry>' could not be resolved`, and the unresolved entry is still
`Failed`. Such a live entry could previously be deleted, PIM eligibility and Azure role assignments
included. A service principal named in `roleAssignments` needs `"principalType": "ServicePrincipal"`
to resolve.

`Test-OERStructure` now warns about an omitted `members`, `scopedRoles`, catalog `resources` or
access package `resourceRoles` key, which still prunes, and `Invoke-OERStructure -Prune` lists them
before it writes anything; set such a key to `null` to leave it untouched. `Get-OERRequiredScope`
lists `RoleManagement.ReadWrite.Directory` for `Set-OERGroup`.

PIM for Groups policies now support approval: `Set-OERGroupPimPolicy` takes `-RequireApproval`,
`-ApproverUser` and `-ApproverGroup`, and a group's `pimPolicy` accepts `requireApproval` and
`approvers { users[], groups[] }`, which `Get-OERInventory` now exports (`requireApproval` appears
in every exported `pimPolicy` block). Approvers declared by UPN or group name are resolved to object
ids before comparison, in `pimPolicy` and `roleManagementPolicies` alike, so a re-run reports
`Unchanged`; a `roleManagementPolicies` user approver must now be a UPN or object id, since a
display name is reported `Failed`. Earlier versions could resolve the OWNER policy of a group whose
owner policy was not yet listed to its MEMBER policy, so owner settings, a permanent-eligibility
opening included, could land on the member policy: review the member policies of groups onboarded by
an apply run. A refused policy read is now `PimPolicyReadFailed` rather than `PimPolicyNotFound`,
and a group created in the same run gets up to 30 seconds for its policies to appear.
`Test-OERStructure` warns about unknown keys in `groups` and `pimPolicy`.

## [1.0.1] - 2026-09-23

Omnicit.EntraRBAC no longer depends on Az.Resources. The module never called a cmdlet from it:
Azure Resource Manager requests are made directly with a token acquired through AzAuth, and always
have been. Installing or updating the module therefore pulls a smaller dependency tree, and an
environment that carried Az.Resources only for this module can drop it.

`Disconnect-OER` no longer signs out an Az PowerShell session that you started yourself. It clears
this module's cached tokens and session state and disconnects Microsoft Graph, and now leaves your
Az context and its on-disk Az token cache untouched; run `Disconnect-AzAccount` yourself when you
want to end that one too. The module never establishes an Az context, so that sign-out could only
ever have reached a session of your own. No other cmdlet, parameter or output shape changes, and
`-IncludeARM` works exactly as before.

A long-standing documentation error is corrected alongside it. `Connect-OER` stated that
`-IncludeARM` made Az.Resources cmdlets usable in the same session. It never did: the module
acquires an Azure Resource Manager token for its own Azure cmdlets and deliberately does not call
`Connect-AzAccount`, so no Az PowerShell context is created. If you relied on that, sign in to Az
separately.

## [1.0.0] - 2026-09-18

Omnicit.EntraRBAC 1.0.0 is the first public release. It manages Entra ID and Azure RBAC from
PowerShell 7.2+ on Windows, Linux and macOS, in the tenants you administer: groups and PIM for
Groups, Administrative Units, Entitlement Management, Access Reviews, Azure resources and role
assignments, and Azure PIM. A JSON inventory exports a tenant's configuration, and a declarative
apply engine validates an edited document and converges the tenant to it.

Every state-changing cmdlet supports `-WhatIf` and `-Confirm`, and deleting a high-value object
prompts by default. Sign-in uses AzAuth for interactive, device code, client secret, certificate
and managed identity sessions, against the commercial cloud or the GCC High, DoD and China clouds.
Help examples use placeholder identifiers and addresses; substitute your own values before running them.

One PowerShell session works in one tenant at a time, and switching tenants inside a session is
limited by the sign-in type. A client secret sign-in for the same application cannot move to another
tenant until you run `Connect-OER -Force`, and a device code or managed identity sign-in does not
send the tenant you name: a device code token may come from the signed-in account's own tenant
instead, and a managed identity token normally comes from the identity's own tenant. The module
warns when it can see that a switch did not take effect, naming Azure Resource Manager calls,
including the ones that write role assignments, as affected alongside Microsoft Graph, and refuses a
token issued for another tenant outright when you name the tenant by its ID.

Known limitation: switching tenants by device code inside one session usually needs that same
`Connect-OER -Force` -- not every such switch is affected -- and without it the sign-in can stop
responding rather than fail: no device code appears, no error is raised, and only Ctrl+C ends the
call, after which the PowerShell session has to be exited. `-Force` cured it every time it was used,
and a new PowerShell session starts from a fresh credential.

Start with `README.md`, `Get-Help about_Omnicit.EntraRBAC`, and `Get-OERRequiredScope`, which
reports the Microsoft Graph permissions and Azure roles each cmdlet needs. Versions before 1.0.0
were never published; their history is kept in `CHANGELOG.md` in the project repository.

## [0.10.0] - 2026-09-13

Unpublished pre-release milestone: a rejected token is refreshed whatever shape the 401 arrives in,
a failed paged read records what it had already read, an unknown access package id is reported, and
a `NoSubjects` requestor scope can be written.

### Fixed

- **A rejected access token is now recognized by its HTTP status, not only by the wording of the
  error message.** Some 401 responses arrived from the underlying client library in a shape whose
  message text the module did not recognize, so a token that should have been silently refreshed
  and retried could instead surface as an authentication failure. App-only sessions (client secret
  or certificate) are unaffected by design: they still report a clear error and never refresh
  silently, since there is no interactive identity behind them to refresh with.
- **A paged read that fails partway through still fails, deliberately, but no longer discards what
  it already read.** A partial collection is never returned as though it were complete. What was
  read before the failure, and which page the read stopped on, are now recorded on the thrown error,
  so the failure can be reported and diagnosed with those facts in hand instead of being reduced to
  "the read failed". Re-running still starts the read from the beginning; no resume mechanism was
  added.
- **An access package id that does not exist is now reported instead of silently ignored.** A stale
  or mistyped GUID passed to an access-package parameter now raises `AccessPackageNotFound` naming
  the id, where it previously returned nothing at all and looked identical to "this package is just
  empty". The message and the `ObjectNotFound` category are the module's own: the code the service
  really answers with was measured against a live tenant rather than assumed, so the tailored error
  is what you get instead of Microsoft Graph's terse text under an unrelated category. Confirming an
  id costs one extra read per id; a permission error or a throttled request hit while confirming it
  is now reported as itself, not folded into "not found".
- **An apply document asking for a requestor scope of `NoSubjects` can now create the assignment
  policy.** That value is a legacy spelling the service's own vocabulary does not contain, so the
  write was rejected every time and such an entry never converged -- on any run, with no way to make
  it succeed. It is now sent as `NotSpecified`, which is the same state (administrator direct
  assignment only), and the substitution is announced on every call. Write `NotSpecified` directly
  to keep the warning quiet; the apply-document guide and the inventory's own prompt template now
  recommend it.

### Changed

- `Get-OERAccessPackageAssignment -State` accepts either casing (`delivered` or `Delivered`) and
  sends the spelling you typed to Microsoft Graph unchanged; the exact filter text is now pinned by
  tests. Verified against a live tenant on 2026-09-11: the service compares the value
  case-insensitively, so both spellings return the same assignments. Only the
  `delivered`/`Delivered` pair could be produced there, so that is the extent of the measurement.

## [0.9.0] - 2026-09-07

Omnicit.EntraRBAC manages Entra ID and Azure RBAC from PowerShell 7.2+ (Windows, Linux, macOS):
groups and PIM for Groups, Administrative Units, Entitlement Management, Access Reviews, Azure
resources/role assignments, and Azure PIM, plus a JSON inventory and declarative apply engine.

Start with `README.md`, `Get-Help about_Omnicit.EntraRBAC`, and `Get-OERRequiredScope` for the
Graph permissions and Azure roles a cmdlet needs.

Corrections from a live tenant run; none changes which operations succeed.

### Fixed

- `Invoke-OERStructure` and `Get-OERInventory` no longer write phantom errors during a successful
  run: creating an access review left two `AccessReviewDefinitionNotFound` records in the caller's
  `-ErrorVariable` and `$Error`, which automation inspecting `$Error` or running under
  `$ErrorActionPreference = 'Stop'` reads as a failure. A genuine read failure is still reported
  and still prevents the create.
- The `approvalStages: []` warning now describes what Graph actually does. It claimed the policy is
  written with approval required and no stages, so no request could ever be approved; measured
  live, Graph refuses the write with `InvalidApprovalStages` and the assignment policy is reported
  `Failed` and left unchanged.
- New warning: clearing every approval stage without also declaring `requireApproval` false AND
  `requireApprovalForUpdate` false cannot be applied to an existing policy -- an undeclared
  `requireApprovalForUpdate` is carried forward from the live one.
- The approver-substitution warning names only what was actually substituted; it listed the tenant
  profile's escalation approvers even where the document's own `alternateUsers` had survived.
- Deleting an access review scoped to an access package's assignments now warns that, if it is that
  policy's Lifecycle access review, the policy is un-updatable until the review is re-created or
  "Require access reviews" is turned off. Conditional deliberately: an ad-hoc review over the same
  package has an identical scope shape.
- An assignment policy blocked by a deleted Lifecycle review reports
  `AccessPackageLifecycleReviewMissing`, naming the missing definition and the remedy, not a raw
  Graph `BusinessFlow not found` 404.
- **A destructive cmdlet's warning now precedes its confirmation prompt.** `Remove-OERGroup`,
  `Remove-OERAdministrativeUnit`, `Remove-OERAccessPackageAssignmentPolicy` and
  `Remove-OERAccessReviewDefinition` wrote their high-impact warning only after `ShouldProcess`
  returned, so `-WhatIf` printed no warning at all and a real delete showed it after you had
  already confirmed. The warnings now print before the prompt and under `-WhatIf`, and the
  access-review prompt text itself says when the definition targets an access package's
  assignments.
- **Azure Resource Manager calls now survive throttling.** A 429 -- and a 503 that names a wait --
  is retried, honouring `Retry-After` in either legal form and falling back to exponential backoff
  without it. Headers were discarded before the status was judged, so ARM had no throttle handling
  at all and a throttled read failed. Retrying is bounded as on the Graph side -- 300 seconds
  of waiting per request (per page under paging), ten retries per request, and a 900-second ceiling
  on how long a command may keep BACKING OFF, not on how long it may run: it is read only at a
  decision to wait, so an unthrottled read never meets it. A bound is reached by refusing to wait,
  never by ending an enumeration early, so a throttled read fails rather than returning a short
  list. `-Verbose` names each wait, its length and source.
- `Get-OERAccessReviewInstance` asks Microsoft Graph only for the fields it returns, so a definition
  with many instances transfers and parses less data. What it returns is unchanged.
- Looking up an access review definition by exact name reads only that definition, not every
  definition in the tenant.

## [0.8.0] - 2026-09-06

Unpublished pre-release milestone: sovereign-cloud sign-in, an unreadable collection no longer
reported as an empty one, and the declared-value rules across the apply engine.

### Added

- **Sovereign clouds.** `Connect-OER -Environment` (or a profile's `Environment` key) signs in to
  GCC High, DoD, or China instead of commercial; every later call keeps that cloud's Graph/ARM
  endpoints. M365 GCC runs on commercial endpoints and needs no selection; only GCC High, DoD and
  China differ. `*-OERConfiguration` cmdlets return the stored cloud; `Get-OERConfiguration`
  errors on and skips a profile with an unrecognised `Environment`, rather than treating it as
  commercial. `Set-OERConfiguration -Environment` is command-line only; omitting it keeps what is
  stored. Verified live on GCC High: sign-in, Graph reads, inventory export, PIM-for-Groups'
  `beta` endpoint; DoD, China, and all sovereign-cloud PIM writes are untested.
- `Get-OERGroup -All` lists every group, unfiltered.

### Fixed

- `Get-OERGroup`/`Get-OERAdministrativeUnit` no longer report an unreadable
  member/owner/PIM-eligibility/scoped-role collection as empty: the property is omitted with a
  non-terminating error; `Get-OERInventory`/`Export-OERInventory` carry the gap as an explicit
  `null` (never a silent `[]`), reported via `InventoryPartial`/`IncompleteReads`;
  `Invoke-OERStructure` no longer prunes or reconciles it. A declared `null` also now reads as
  omitted: `recurrence` gives a one-time review instead of failing,
  `requestorScope.users`/`.groups` is ignored, not widening a request, and likewise for access
  review creation fields, `pimPolicy.member`/`.owner`, and role-assignment `principalType`. An
  approval stage omitting `durationDays` now warns offline.
- A declared `alternateUsers` on an approval stage is no longer overwritten by the profile's
  escalation-approver default; falling back to it now warns, not silently substitutes.
- A group declared into an administrative unit is flagged offline if the unit's entry omits it
  from `members` -- `-Prune` otherwise undoes it.
- A failed Graph or Azure call no longer leaves an access token in the caller's `$Error` or
  `-ErrorVariable`.
- A clean `Get-OERInventory` no longer floods the error stream over an un-onboarded PIM group
  (expected, not four errors); a permission-refused policy read reports `PimPolicyReadFailed`,
  omitting `pimPolicy` rather than implying none.
- A device-code sign-in's URL/code print on the information stream now, not a warning a silenced
  session missed -- it used to seem hung.
- A token issued for a tenant other than the GUID named is refused as `TenantMismatch`.
- `groupsRoster.json` now lists every group by name, not only security-enabled ones
  (M365/distribution groups were excluded); `inventory.json` keeps that filter for the apply
  engine, and `-GroupFilter` widens it.
- A throttled Graph call no longer raises a spurious header error or misses `Retry-After`.

### Changed

- **Behaviour changes.** A `Get-OERGroup`/`Get-OERAdministrativeUnit` property that its switch
  guaranteed can now be absent when the read fails -- under `Set-StrictMode`, test with
  `$G.PSObject.Properties.Name -contains 'Members'`. The read writes a
  non-terminating error and sets a partial inventory's `$?` to `$false`, so
  `$ErrorActionPreference = 'Stop'` now stops where it silently continued with an empty collection
  (`Export-OERInventory` still writes the whole bundle first). Separately, a `requestorScope` with
  `users`/`groups` but no `scope` now applies `SpecificDirectoryUsers`: a document once refused at
  validation is now accepted -- declaring `scope` explicitly is still recommended.

## [0.7.0] - 2026-08-28

Unpublished pre-release milestone. The `0.x` headings below are unpublished pre-release history from
phases 0-5; full detail is under `[0.6.0] - 2026-08-20`. See README.md and
`Get-Help about_Omnicit.EntraRBAC`.

### Added

- **Authentication.** `Connect-OER` signs in interactively, by device code, client secret, client
  certificate, managed identity, or a stored tenant alias; `-IncludeARM` adds an ARM token.
  Connecting first is optional -- every cmdlet auto-authenticates and inherits the session's
  identity.
- **Tenant profiles.** `New`/`Get`/`Set`/`Remove-OERConfiguration` keep per-tenant naming and
  defaults (approvers, catalog, authentication context, activation ceiling) as PSD1 under
  `<home>/.config/Omnicit.EntraRBAC/Profiles/`, resolved against the user's home directory on
  Windows, Linux and macOS alike.
- **Groups and PIM for Groups.** CRUD for regular, role-assignable and PIM-enabled groups,
  membership, eligible assignment, and the group PIM policy (duration, approval,
  MFA/authentication context, notifications); a permanent grant opens the governing policy with
  warning and confirmation.
- **Administrative Units.** CRUD for regular and restricted-management units, membership, and
  AU-scoped role assignment.
- **Entitlement Management.** Catalogs, catalog resources (groups, apps, SharePoint sites), access
  packages, resource-role bindings, assignment policies (approval-stage/requestor-scope), and
  admin grant/revoke.
- **Access Reviews.** Review definitions and instances over access packages, stage builders,
  decision retrieval/application, reminders, cancellation.
- **Azure inventory and RBAC.** Management groups, subscriptions, resource groups and resources;
  role definitions; role assignments (create, read, in-place update of description/ABAC
  condition, delete).
- **Azure PIM.** Eligible and active role assignments (grant, activation, deactivation, read,
  removal), and the role management policy engine for duration, MFA, authentication context,
  approval and notifications.
- **JSON inventory and declarative apply.** `Get-OERInventory` reads tenant state -- group owners,
  catalog external visibility, membership-rule state, access review settings and
  recurrence range, fallback approvers and all seven requestor-settings flags -- into a
  round-trippable document; `Export-OERInventory` writes it beside its JSON schema and an LLM
  prompt bundle; `Test-OERStructure` validates offline; `Invoke-OERStructure` applies one
  idempotently, dependency-ordered, with `-WhatIf` planning and opt-in `-Prune` for children.
- **Permission discovery.** `Get-OERRequiredScope` reports the Graph permissions and Azure roles
  cmdlets need, transitively and offline; `-Unique` returns a consent list.
- **Discoverability.** Tab completion for role names and tenant aliases; a format view per type;
  friendly names wherever an object id is accepted; pipeline binding.
- **Authentication context discovery.** `Get-OERAuthenticationContext` lists Conditional Access
  authentication contexts; `-Available` limits to the published ones a PIM policy can require.

### Changed

Behaviour worth knowing before automating. Nothing is a regression -- there was no published
version -- but a `0.x` build behaves differently:

- Eighteen cmdlets declare `ConfirmImpact = 'High'` and prompt by default: thirteen
  `Remove-OER*` cmdlets, plus `Set-OERRoleAssignment`, `Disable-OEREligibleRoleAssignment`,
  `Stop-OERAccessReviewInstance`, `Invoke-OERAccessReviewInstanceDecision` and
  `Invoke-OERStructure`. Pass `-Confirm:$false` for unattended automation; every other
  state-changing cmdlet is `Medium` or lower, prompting only if `$ConfirmPreference` drops.
- A display name matching more than one group, catalog, access package, AU or Azure role
  definition raises an `Ambiguous*Name` error naming the candidates.
- All eleven `Set-OER*` cmdlets report a no-updatable-property call as `NothingToUpdate`.
  **Breaking** for the five that previously wrote silently on one --
  `Set-OERAccessPackageAssignmentPolicy` (now with mandatory `-DisplayName`, refusing a
  rename-only call), `Set-OERAccessReviewDefinition`, `Set-OERConfiguration`,
  `Set-OERGroupPimPolicy` and `Set-OERResourceGroup`. `Set-OERRoleManagementPolicy` keeps a
  distinct `NoChange` for its "no rule differs" case.
- `Get-OERAccessPackage` populates `CatalogId` and expands v1.0's `resourceRoleScopes`, both
  structurally broken.
- `Export-OERInventory` reports partial Azure coverage as an `InventoryPartial` error, and its
  `ScopeCount` counts scopes read, not enumerated.
- An explicit JSON `null` now means **undeclared**, unlike an omitted key, across the apply
  engine -- it previously cleared a description, disabled approval, widened a requestor scope to
  every member, and could empty a child collection under `-Prune`. Undeclared PIM-for-groups
  eligibility is reported/pruned if declared; an undeclared assignment policy reports `Extra` and
  is never pruned; prune warnings are truthful under `-WhatIf`; an access package and its
  assignment-policy/resource-role paths now resolve within the declared catalog (was tenant-wide);
  an AU is created before the group placed in it; unappliable group drift replaces a false
  `Unchanged`; a dynamic group's members are no longer reconciled; a permanence-only
  `Set-OERGroupPimPolicy` call no longer overwrites the live expiration maximum; and a
  multi-stage access review is skipped with a warning, not exported as a fabricated self review.
  A reviewer scope carrying Graph's `/v1.0/users/{id}` prefix is now parsed, not misread as a
  self review. An access review update Graph accepts without storing is now `Failed`, not
  `Updated`, and `Export-OERInventory` no longer writes a document its own schema rejects.
- Child collections distinguish absent from `null`, unlike scalars: under `-Prune` an omitted
  `members`, `resources`, `resourceRoles` or an AU's `members`/`scopedRoles` still reconciles to
  empty (grandfathered), while an explicit `null` is left untouched. The new `eligibility` and
  `owners` passes skip an omitted key too -- firing on it would revoke standing privileged access.

### Fixed

- **A declared-empty `approvalStages` now clears the live approval stages** instead of being
  ignored, so the document converges; `Test-OERStructure` warns if `requireApproval: true` is
  declared with it.
- **A declared-empty `reviewers` now creates a self review** on a new access review, instead of the
  manager default that reported `Failed` and created nothing. Both are a **behaviour change** for a
  document already carrying the empty array.
- **PIM-for-groups no longer leaves MFA and an authentication context both enabled.**
  `Set-OERGroupPimPolicy` reconciles them like Azure PIM: a context clears
  `MultiFactorAuthentication`, MFA disables a context, and requesting both is
  `MfaAuthContextConflict`. The claim is tenant-validated; the apply engine reconciles the same
  way, converging instead of flapping. The conflict-removing rule is patched first: Graph rejects
  adding MFA while a context is live, and a fixed order left neither control in force.

### Security

- Every Graph and ARM `catch` scrubs the failed request from the caller's `$Error` first: its
  `HttpRequestMessage` holds `Authorization: Bearer <token>` in plain text. Client secrets are
  accepted only as `[securestring]`, materialised at the request boundary and dropped in a
  `finally` on terminating paths.
- The ARM token cache is keyed on tenant and auth identity, so a tenant switch cannot serve one
  customer's Azure state under another's label.
- A throttled Graph read now honours `Retry-After`, so it may BLOCK up to 300 s a request and
  900 s a call where it gave up after 7 s: the header sat on a member the SDK lacks.
- Session planning docs and the pre-release audit quote live tenant ids and a customer address;
  git-ignored, not merely uncommitted.

## [0.6.0] - 2026-08-20

### Added

- `Get-OERRequiredScope` reports the Graph permissions and Azure RBAC roles one or more cmdlets
  need, per cmdlet and transitively through their private helpers. `-Unique` returns the
  deduplicated consent list for a whole workflow. It reads a static table, so it needs no tenant
  and no sign-in. README and the about topic no longer state scopes of their own: a functional
  area is not a permission boundary, and `tests/QA/requiredscope.tests.ps1` now gates the table
  against the module's own call graph.

- `Export-OERInventory`'s prompt bundle and run-folder README now state what the inventory and the
  apply engine do NOT model: Azure resource groups and individual Azure resources, Azure PIM
  eligible and active role assignments, and multi-stage access reviews. The bundle is fed to an
  LLM, which otherwise assumes those areas are covered and emits an apply document declaring
  things the engine silently ignores. Each exclusion names what IS covered instead and the OER
  cmdlets that manage the area directly.
- Manifest `LicenseUri` and an explicit `RequireLicenseAcceptance = $false` in
  `PrivateData.PSData`, so the licence is discoverable from the package and not only from the
  repository.
- Defensive `.gitignore` rules so a tenant inventory export can never be staged by accident:
  `docs/examples/*` with an explicit allowlist negation for the tracked worked example, plus
  `oer-inventory-*/` and `inventory.json` for `Export-OERInventory` bundles written into a clone.
- `build.yaml` no longer defines a `publish` workflow, so `./build.ps1 -Tasks publish` does not
  resolve. The module's intended destination is the public PowerShell Gallery, but only once 1.0.0
  is ready; until then the only thing that had stood between a high-privilege module and a live
  push was whether `GalleryApiToken` happened to be set in the invoking shell.
  `Publish_Release_To_GitHub` is not a guard either -- it is declared
  `-if ($GitHubToken -and ...)` and skips silently without a token, so the gallery task would run
  on its own. Removing the workflow is the only brake that lives in the repository: Sampler reads
  publish settings through InvokeBuild's `property`, which resolves a PowerShell variable, then an
  environment variable, then a literal default, and never consults `build.yaml` -- so
  `SkipPublish:` / `PSModuleFeed:` keys placed there read as guards and enforce nothing. The
  restore instructions and the reasoning are recorded in `build.yaml` where the workflow was.
- Microsoft Graph `429` responses are now honoured with a bounded `Retry-After` backoff in
  `Invoke-OERGraphRequest`: up to three retries, waiting the number of seconds the header
  specifies, exponential fallback when the header is absent, each wait capped at 120 seconds. A
  `503` is retried only when it carries a `Retry-After` header. Previously a throttled Access
  Reviews or inventory read lost the whole section outright.
- `tests/QA/about.tests.ps1`, the first test of any kind over the about topic. It asserts the file
  exists in source and in the built module, that the two are byte-identical, that it is UTF-8
  BOM-less and ASCII-only, and that it names every exported cmdlet and no non-exported one.
- A README roster assertion in `tests/QA/module.tests.ps1`: every `FunctionsToExport` name must
  appear in `README.md`, no `Verb-OER` name in README may be invented, and no `PSModulePath`
  example may reintroduce a hardcoded Windows `;`.
- README now documents all 88 cmdlets in eleven cohort sections with their Graph scope or Azure
  role, plus a `## Documentation` section, an inventory to apply walkthrough, and install paths for
  the Gallery and for a build artifact with the `-UseModuleFast` bootstrap fallback.
- The about topic gained `COMMAND COHORTS` (all 88 cmdlets and their scopes) and `TENANT PROFILE`
  (the profile PSD1 schema, previously only in `CLAUDE.md` and therefore never shipped).
- `Test-OERStructure`, `Invoke-OERStructure` and `Export-OERInventory` now point at
  `docs/examples/example-structure.json` and `docs/inventory-to-llm/README.md` from their help.
  Nothing a consumer receives referenced the `docs/` tree, so both were undiscoverable.
- The apply-engine round-trip closed -- or documented as out of scope -- 34 findings from the
  pre-release audit across 22 tasks. The structure document now round-trips: group owners
  (`Get-OERInventory` captures them, `Invoke-OERStructure` adds declared owners and, gated on the
  `owners` key being declared, reports undeclared ones as `Extra` or removes them under `-Prune`
  -- refusing to remove a group's last standing owner); a catalog's `externallyVisible` flag; a
  dynamic group's live `membershipRuleProcessingState`; PIM-for-groups eligibility as a full
  `Extra`/prune pass gated on the declared `eligibility` key; access review `settings` (mail and
  reminder notification, justification, recommendations, auto-apply, default decision) and its
  recurrence range (start, end, occurrence count); and approval-stage `fallbackPrimaryApprovers`.
- `New-OERAccessPackageRequestorSettings` and the structure engine now model all seven requestor
  self-service booleans -- `allowSelfRequest`, `allowManagerRequest` (with `managerLevel`),
  `allowCustomSchedule`, `allowSelfExtend`, `allowSelfRemove`, `allowOnBehalfUpdate`, and
  `allowOnBehalfRemove` -- merging the declared subset onto the live object on
  `Set-OERAccessPackageAssignmentPolicy` instead of three of the seven being write-only.
- New private helpers `Test-OERDeclaredProperty` and `Test-OERDeclaredNull`, the single owners of
  the apply engine's three-way absent / `null` / `""` presence rule -- a property is "declared"
  only when it is present and not `null`; an empty string or an empty array still counts as
  declared, because `""` is the documented value that clears a description and `[]` is how a
  document asserts an empty list; `Test-OERDeclaredNull` separately isolates the "explicitly
  null, as opposed to merely absent" case that the child-collection handlers need -- and
  `ConvertFrom-OERDuration`, the read-side mirror of `ConvertTo-OERDuration`, which parses any ISO
  8601 duration via `[System.Xml.XmlConvert]::ToTimeSpan()` instead of an anchored single-unit
  regex.
- `tests/QA/sourcehygiene.tests.ps1`, holding two static gates over the authored tree. The first
  is a byte-level check that every `.ps1`, `.psd1`, `.psm1` and `.ps1xml` file under `source/` and
  `tests/` is ASCII-only and carries no UTF-8 BOM. PSScriptAnalyzer's
  `PSUseBOMForUnicodeEncodedFile` does not cover this: it fires only on non-ASCII in a BOM-LESS
  file, so adding a BOM inverts it to a pass, and the existing gate never hands anything under
  `tests/` to the analyzer at all.
- The second gate is an AST scan asserting that `Remove-OERErrorRecord -Record $PSItem` is the
  FIRST statement of every `catch` in a file that reaches a Graph, ARM or token-acquisition call --
  directly, or transitively through any module function it calls. That is `CLAUDE.md` SECURITY
  rule 6: the raw `HttpRequestMessage` stored in `$Error` carries `Authorization: Bearer <token>`
  in plain text. Transport is detected from `CommandAst`, never from a text grep --
  `source/Private/Remove-OERErrorRecord.ps1` carries a literal `Invoke-MgGraphRequest` inside its
  `.EXAMPLE` block, which a grep would score as a violation. Four `Resolve-OERName` catches are
  exempt; each entry carries a written reason and is anchored on the shape of the `try` body
  rather than on a line number.
- Pipeline binding widened across four cohorts. Groups: `-Group` now binds `GroupId` before the
  generic `Id` on all eleven group cmdlets that take it (nine reordered; `Add`/`Remove-OERGroupMember`
  already had it right), so piping a group member into a sibling cmdlet targets the parent group
  instead of mis-binding the member as the target; `Get-OERGroupEligibility` and `Get-OERGroupMember`
  gained a `DisplayName` alias to match. `Get-OERGroupMember` gained `-AccessType` alongside its
  existing `-Owners` switch, and `-AccessType` now binds from the pipeline on the group PIM policy
  cmdlets so a `Get-OERGroupPimPolicy` object pipes straight into `Set-OERGroupPimPolicy`. Azure/ARM:
  `-ManagementGroup` binds from the pipeline on `Get`/`Set-OERRoleManagementPolicy`, and the three
  `New-OER*RoleAssignment` cmdlets gained a pipeline-bindable `-PrincipalId` (`New-OERRoleAssignment`
  also gained `-PrincipalType`, sent in the PUT body whenever it is known -- an explicitly supplied
  or piped value wins, otherwise the type a friendly-name resolution populated; when neither is
  available the key is omitted entirely rather than sent as a bare `null`). Entitlement Management:
  `Get-OERAccessPackage -Catalog` binds from a
  piped catalog; `Set-OERAccessPackageAssignmentPolicy -DisplayName` binds from the pipeline (still
  mandatory); `New-OERAccessPackageAssignment` binds `-AccessPackage` and `-Policy` from the pipeline;
  `Add-OERAccessPackageResourceRole` accepts `-Group`/`-Application` alongside its resource-origin
  parameters. Access Reviews: an access review stage now pipes directly into
  `Get-OERAccessReviewInstanceDecision -Stage`, and `Set-OERAccessReviewDefinition -Id` accepts a
  definition display name, not only a GUID.
- Administrative Units: `-Id` and `-DisplayName` are unified into one `-AdministrativeUnit`
  parameter across `Get`/`Set`/`Remove-OERAdministrativeUnit`, `Add`/`Remove-OERAdministrativeUnitMember`
  and `Add`/`Remove`/`Get-OERAdministrativeUnitScopedRole`, with both old spellings kept as aliases
  (plus the new `AdministrativeUnitId`) so existing calls and apply-documents keep working unchanged.
  `Get-OERAdministrativeUnit` now dispatches on the VALUE's shape (a GUID reads directly, anything
  else filters) instead of on which alias happened to bind. `Remove-OERAdministrativeUnit`,
  `Set-OERAdministrativeUnit`, `Add`/`Remove-OERAdministrativeUnitMember` and
  `Add`/`Remove`/`Get-OERAdministrativeUnitScopedRole` collapse to a single parameter set as a side
  effect. Two competing sets had suppressed implicit positional binding on those cmdlets entirely;
  with one set left, EVERY parameter becomes positional in declaration order -- not just
  `-AdministrativeUnit`. Measured: `Set-OERAdministrativeUnit` and
  `Remove-OERAdministrativeUnitScopedRole` positions 0..7,
  `Add-OERAdministrativeUnitScopedRole` 0..6, `Add`/`Remove-OERAdministrativeUnitMember` 0..4,
  `Remove-OERAdministrativeUnit` and `Get-OERAdministrativeUnitScopedRole` 0..1
  (`Get-OERAdministrativeUnit` keeps its separate `List`/`ByFilter` sets and is unaffected). This is
  additive -- nothing that worked before stops working -- but a stray positional argument that used
  to be rejected now binds, on cmdlets that revoke delegated administrator privilege: on
  `Remove-OERAdministrativeUnitScopedRole` (`ConfirmImpact = 'High'`) positions 1-4 are
  `-ScopedRoleMembershipId`, `-RoleName`, `-RoleId` and `-PrincipalId`.
- New non-terminating guards: `AmbiguousRole` on `Add`/`Remove-OERAdministrativeUnitScopedRole`
  (conflicting `-RoleName`/`-RoleId`); `AmbiguousPrincipal` on `Remove-OERAdministrativeUnitScopedRole`
  (an explicit command-line `-PrincipalId` that disagrees with a piped item's own principal);
  `MutuallyExclusiveReviewer` on `New-OERAccessReviewDefinition`, `New-OERAccessReviewStage` and
  `Set-OERAccessReviewDefinition` (`-SelfReview` combined with `-Reviewer`/`-ReviewerGroup`/`-Manager`
  previously dropped `-SelfReview` silently instead of refusing the combination);
  `ResourceIdEqualsCatalogId` on `Remove-OERCatalogResource`, now that `-Catalog` binds from a piped
  catalog object and could collide with `-ResourceId`; `InvalidPolicyId` on
  `New-OERAccessPackageAssignment`. `-Occurrences` and `-DurationInDays` across
  `New-OERAccessReviewDefinition`, `New-OERAccessReviewStage` and `Set-OERAccessReviewDefinition`
  (five parameters in all) now reject a zero or negative value at bind time via
  `[ValidateRange(1, [int]::MaxValue)]` instead of reaching Graph with it. `-ConditionVersion` on the
  three `New-OER*RoleAssignment` cmdlets is now `[ValidateSet('2.0')]`; `Set-OERRoleAssignment`
  deliberately keeps accepting `'1.0'` too, since it is the documented upgrade path for editing a
  legacy assignment.
- Piping an assignment-shaped object into `New-OERRoleAssignment`, `New-OERActiveRoleAssignment` or
  `New-OEREligibleRoleAssignment` while ALSO naming a principal with `-User`, `-Group` or
  `-ServicePrincipal` is now refused with a non-terminating `AmbiguousPrincipal` instead of creating
  the assignment for a principal the caller did not name. `-PrincipalId` binds from the pipeline on
  all three cmdlets and takes precedence over the friendly parameters, so every piped assignment's
  own `PrincipalId` silently won and the named principal was ignored -- once per piped item, on
  cmdlets that grant privileged Azure access. The guard fires only when the piped object actually
  carries a `PrincipalId`: piping a role definition to supply the role, or a subscription, resource
  group or resource to supply the scope, alongside a named principal is unaffected and keeps working
  exactly as documented. A direct, non-piped call supplying both `-PrincipalId` and a friendly
  parameter still only warns, as before. This is the same treatment `Remove-OERGroupEligibility` and
  `Remove-OERAdministrativeUnitScopedRole` already give the identical collision.
- `-PrincipalType` on `New-OERRoleAssignment` also accepts the legacy ARM principal-type values
  (`Unknown`, `DirectoryRoleTemplate`, `Application`, `MSI`, `DirectoryObjectOrGroup`, `Everyone`)
  alongside the current ones. The parameter binds from the pipeline, and a closed set turned an
  unrecognised value into a per-item binding failure that skipped that item silently while the rest
  of the pipeline continued; a piped record carrying a legacy value now binds instead of vanishing.

### Fixed

- Destructive guards: `Remove-OERAdministrativeUnitScopedRole`,
  `Invoke-OERAccessReviewInstanceDecision` and `Stop-OERAccessReviewInstance` now declare
  `ConfirmImpact = 'High'` and warn before mutating; `Remove-OERGroupEligibility` gained the warning
  it lacked; `New`/`Set-OERResourceGroup` moved from `Low` to `Medium`. **The three `High` cmdlets
  now prompt by default -- unattended automation must pass `-Confirm:$false`. The `Low` -> `Medium`
  move does not prompt by default (`$ConfirmPreference` defaults to `High`); it only makes
  `New`/`Set-OERResourceGroup` promptable when `$ConfirmPreference` is lowered to `Medium`, where
  `Low` did not prompt; at `$ConfirmPreference = 'Low'` they prompted before and still do.**
- **Breaking:** "nothing to update" is now `NothingToUpdate` across the six `Set-*` cmdlets that
  carried the guard as of 0.6.0; the old ids `NoUpdateSpecified` (group, AU) and `NoChange`
  (policy, no setting passed) are gone -- fix any `catch` on them.
- A display name matching more than one group, catalog, access package, administrative unit or Azure
  role definition now raises an `Ambiguous*Name` error naming the candidates, instead of silently
  acting on an arbitrary first match.
- The PIM permanent self-heal no longer weakens a policy when the operator declines, warns about the
  blast radius before the prompt, and rolls the policy back (ARM) or reports
  `PolicyOpenedButGrantFailed` (Graph) when the grant fails.
- `New-OERGroup`, `New-OERCatalog` and `New-OERAccessPackage` stop with `<Noun>ResolveFailed` when
  their idempotency pre-check is throttled or denied, instead of creating a duplicate.
- `Export-OERInventory` reports partial Azure coverage as an `InventoryPartial` error and adds
  `ScopesEnumerated`/`SkippedScopes`; `ScopeCount` now counts scopes successfully READ, not
  enumerated -- a meaning change on an existing field; a scope whose read fails partway is now
  dropped whole and listed in `SkippedScopes` instead of contributing partial data.
- Tenant profiles: PSD1 keys are quoted so a profile round-trips; an unparsable profile is skipped
  with `TenantProfileMalformed` instead of silently authenticating against the operator's home
  tenant, and `Set-OERConfiguration` no longer rewrites one; the profile path resolves on Linux and
  macOS (unchanged on Windows).
- Paging on the scoped-role removal read and two resolver scans; `-Filter` percent-encoding on
  `Get-OERCatalog`/`Get-OERAccessPackage`; `-User` plus a GUID guard and a `-State` `ValidateSet` on
  `Get-OERAccessPackageAssignment`; role-not-found errors name `Get-OERRoleDefinition`; PIM prompts
  name the principal actually acted on.
- Three documented permissions were wrong. PIM-for-Groups eligibility needs
  `PrivilegedEligibilitySchedule.*.AzureADGroup`, not the legacy `PrivilegedAccess.*` name;
  `Enable`/`Disable-OEREligibleRoleAssignment` are authorised by the caller's own eligibility and
  need `Reader`, not `User Access Administrator`; resource-group writes need `Contributor`, not the
  authorization roles.

- `Initialize-OERAuth` now inherits the current session's tenant and credential instead of
  comparing the cached state against its own parameter defaults. `-AuthMethod` declared `=
  'Interactive'` and the tenant fell back to `'organizations'`, so any of the 22 ARM cmdlets
  -- none of which pass `-AuthMethod` -- called on an app-only or managed-identity session
  fell through to `Get-AzToken -Interactive` with no `-Tenant`: an unattended run stopped at
  a browser prompt, an attended one silently continued as a different principal, and the auth
  state was stamped `TenantId = 'organizations'`, a label pointing at no real tenant. A caller
  that omits `-TenantId` now targets the session's tenant, and one that omits `-AuthMethod` and
  either omits `-ClientId` or names the one already signed in as reuses the session's credential
  (the two are inherited as a pair, so a user-assigned managed identity is never re-acquired as
  the system-assigned one). An explicit parameter still wins, a `-ClientId` naming a different
  application forces re-authentication rather than silently reusing another application's session,
  a `-TenantId` naming a different tenant inherits nothing, and a first call with no session
  is unchanged. An inherited app-only session that needs a new token now raises a terminating
  `AppOnlySessionCredentialUnavailable` error with the state left intact, rather than prompting:
  the client-credentials flow issues no refresh token and the module deliberately never caches
  the secret or certificate, so the token genuinely cannot be re-acquired. This is the same
  hazard class as the tenant-isolation fix in #36 -- an auth-state tenant label that does not
  describe the token beneath it -- and was explicitly named as out of scope there. `Connect-OER`
  inherits the tenant half of this too: called without `-TenantId` or `-TenantAlias`, it now
  targets the current session's tenant instead of starting a fresh tenant-agnostic sign-in;
  run `Disconnect-OER` first to sign in as a different tenant or account.
- **Release blocker:** the ARM token cache is now scoped to its tenant and auth identity. The
  cache predicate carried no tenant, `AuthMethod` or `ClientId` term, so switching tenants kept
  the previous tenant's ARM token cached while the auth state reported the new tenant. Azure reads
  after a tenant switch returned the previous customer's resources under the new customer's
  label, and a write reached through a friendly name (group, role, scope) could land in the
  previous customer's tenant, with no error raised anywhere. The ARM token is also no longer
  carried into a rebuilt auth state for a different identity.
- `-ForceRefresh` on the ARM path now actually re-acquires the ARM token instead of resending the
  same rejected bearer. A 401 is not always an expiry -- revocation, Conditional Access, or a key
  rotation return the same status -- so the forced-refresh retry previously resent the identical
  rejected token and guaranteed a second 401.
- The three `Initialize-OERAuth` catch blocks -- Graph token acquisition, the `Connect-MgGraph`
  handoff, and ARM token acquisition -- now call `Remove-OERErrorRecord` first, matching every
  other Graph/ARM catch block in the module; a failed `ClientSecret` sign-in binds the plaintext
  secret into the request the swallowed error record describes. Separately, the materialized
  plaintext client secret is now dropped in a `finally` that also covers the terminating paths --
  the old single cleanup line sat outside any `try`/`finally` and so was skipped on every one of
  them. The `-ClientSecret` help text is corrected: it previously claimed the plaintext was
  'cleared immediately afterwards', which was false. A .NET string is immutable, so dropping the
  reference only bounds how long the secret stays reachable from managed code; it does not scrub
  it from memory. The help now says exactly that.
- ARM page fetches now get the same 401 detect/refresh/retry-once handling as the first request,
  budgeted once per call rather than once per page. A token expiring mid-pagination previously
  failed the whole `-All` enumeration outright instead of recovering the way the first page
  already did; a per-page budget would instead turn a long enumeration against a genuinely broken
  token into a refresh storm, so the retry is deliberately scoped to the call.
- `Get-OERInventory`'s Graph collection reads no longer silently stop at the first page. Graph's
  default page size for groups is 100, so a tenant with more than 100 groups, or a group with more
  than 100 members, was captured incomplete with no warning. `Invoke-OERGraphRequest` gained a
  strictly opt-in `-All` switch that follows `@odata.nextLink` and aggregates every page; every
  collection read behind `Get-OERInventory` now opts in: the tenant-wide group list, group members
  and owners, PIM eligibility instances, administrative units and their members and scoped-role
  members, catalogs, catalog resources, access packages, assignment policies, and access review
  definitions -- `Get-OERAccessReviewDefinition`'s own hand-rolled `nextLink` loop was replaced by a
  call to the wrapper's new switch. The switch is opt-in, so no call site outside those reads
  changed behavior, with two user-facing exceptions where the larger result set is the intended
  fix: `Get-OERGroup -Filter` and `Get-OERAdministrativeUnit -Filter` also opted in, so a matching
  result set that previously capped at the first page (100 items) can now come back larger and take
  longer to return.
- `Export-OERInventory` now acquires an ARM token only when `-Include` names an Azure section. It
  previously called `Initialize-OERAuth -IncludeARM` unconditionally; because the cmdlet passes no
  `-AuthMethod`, that unconditional ARM acquisition could push a session already established with
  a client secret or certificate into a fresh interactive sign-in -- an unattended automation run
  stopping dead at a browser prompt even when the run only needed a non-Azure section such as
  Groups.
- `Connect-OER -TenantAlias` now combines with every credential selector. It previously sat in its
  own parameter set that excluded them all, so `-TenantAlias corp -DeviceCode` was an unresolvable
  parameter set and an alias-only sign-in silently fell through to interactive -- worst for
  `-ManagedIdentity`, where a pipeline-hosted run is exactly the case a stored alias exists to
  help. Supplying `-TenantId` and `-TenantAlias` together now raises a non-terminating
  `AmbiguousTenant` error; that combination was never expressible before, so nothing that used to
  work stops working.
- `Write-CmdletError -TargetObject` no longer defaults to the caller's caught `ErrorRecord`. A
  parameter default resolves `$PSItem` through the caller's dynamic scope, so a bare
  `Write-CmdletError` call inside a `catch` block silently bound the very error record being
  handled as the new error's target. The default is now `$null`, and all 128 call sites that
  relied on the old default now pass an explicit, meaningful target instead -- a resolved object
  id, an ARM scope string, or the caller-supplied friendly name that failed to resolve.
- README's from-source snippet built `$env:PSModulePath` with a hardcoded `;`, which is
  Windows-only. In a `CompatiblePSEditions = @('Core')` module whose CI runs on Linux and macOS,
  that produced one malformed path entry and the following `Import-Module` failed to resolve the
  required modules. It now uses `[IO.Path]::PathSeparator`.
- README's quick-start comment said "Client certificate by thumbprint path" above a `-CertificatePath`
  example taking a PFX file; `Connect-OER` has no thumbprint parameter.
- README's end-to-end Entitlement Management example no longer uses four variables it never
  assigns. `$salesGroupId`, `$userId` and `$assignmentId` were bound to `$null` for anyone who
  copied the block, and the captured `$cat`/`$res` were never used. The revoke step also now
  reflects that `New-OERAccessPackageAssignment` returns an assignment *request*, so the assignment
  id has to come from `Get-OERAccessPackageAssignment`.
- `Export-OERInventory` now writes an `inventory.json` that validates against the `schema.json`
  written beside it. `ConvertTo-OERInventory` emitted PascalCase root keys (`Version`, `Groups`, ...)
  while the schema declares them lowercase with `additionalProperties: false` and
  `required: ["version"]`, so every exported document was rejected by its own schema and the
  `Export-OERInventory` -> `Test-OERStructure` loop failed on the first try. The root keys are now
  emitted in the schema's spelling. PowerShell member lookup is case-insensitive, so
  `$Inventory.Groups` is unaffected, and a document already on disk with PascalCase root keys still
  reads and validates -- both directions are covered by tests.
- Enum casing in an apply document now has a single owner, the new private
  `Resolve-OERStructureEnumCasing`. `Test-OERStructureSchema` matched enum values case-insensitively
  while the emitted draft-07 schema declares them case-sensitively, so a document with
  `"accessType": "Member"` passed `Test-OERStructure` and was rejected by the shipped `schema.json`.
  The validator still accepts any casing -- no document that validates today starts failing -- but now
  reports a Warning naming the canonical spelling, and `Read-OERStructureDocument` normalizes the
  value so the spelling that reaches a Graph or ARM request body is the one the schema declares.
  The two public cmdlets therefore differ on purpose: `Test-OERStructure` validates the document
  exactly as written, so it can warn that a file will be rejected by a validator outside the module,
  while `Invoke-OERStructure` normalizes and applies that same file successfully.
- An explicit JSON `null` was treated the same as a declared value across 36 write-feeding presence
  gates in the structure engine: it cleared a group's description or mail nickname, un-hid an
  access package, disabled an assignment policy's approval requirement, widened a
  `SpecificDirectoryUsers` requestor scope to every member user in the tenant, cleared a group PIM
  policy's authentication context and MFA requirement, and, in four `-Prune` handlers
  (`Sync-OERStructureGroup` members, `Sync-OERStructureAdministrativeUnit` members and scoped
  roles, `Sync-OERStructureCatalog` resources, `Sync-OERStructureAccessPackage` resource roles),
  deleted an entire live child collection. Every one of those gates now goes through the new
  `Test-OERDeclaredProperty`/`Test-OERDeclaredNull` and treats `null` as undeclared -- the same as
  an omitted key for a scalar, but distinct from an omitted key for a child collection under
  `-Prune` (an omitted collection still reconciles to empty; only an explicit `null` is left
  alone).
- `Set-OERGroupPimPolicy -AllowPermanentEligibility`/`-AllowPermanentActive` rewrote the live
  expiration rule's `maximumDuration` to the unbound `-EligibleDuration`/`-ActiveDuration`
  parameter default (365/180 days) whenever a permanence switch was passed without its duration
  parameter, silently replacing whatever maximum the tenant already had configured; it now reads
  the live rule and carries its `maximumDuration` forward untouched when the duration parameter is
  not bound. Separately, the read side could not parse a live `P1Y`, `P6M` or `PT1H30M`
  `maximumDuration` (an anchored single-unit regex), which read back as "not configured" and made
  the carry-forward above unreliable in the first place; both converters now route through the new
  `ConvertFrom-OERDuration`, which parses any ISO 8601 duration.
- `Resolve-OERPolicyRulePatch` reported a PIM rule as changed whenever its value merely looked
  different -- for example a boolean compared against a boolean-valued string -- so
  `Set-OERGroupPimPolicy`/`Set-OERRoleManagementPolicy` patched and reported rules that had not
  actually changed; the overlay now diffs by normalized value and reports only genuine changes.
- PIM-for-groups eligibility and access package assignment policies had no `Extra`/prune reconcile
  pass: an undeclared eligibility grant was never reported and never removable through `-Prune`,
  and an undeclared assignment policy was invisible to an operator reading the apply result.
  Eligibility now gets a full `Extra`/prune pass, gated on the declared `eligibility` key (never on
  an omitted one -- a newly destructive pass firing on every existing document's omitted key would
  revoke standing privileged access on its next `-Prune` run). An undeclared assignment policy is
  now reported as `Extra` and is deliberately never removed by `-Prune`: whether a package's last
  policy may be deleted at all is unverified, so the deletion path needs a live answer first, and
  `Remove-OERAccessPackageAssignmentPolicy` remains the direct way to delete one.
- Every handler-level `-Prune` warning (group members, administrative unit members and scoped
  roles, catalog resources, access package resource-role bindings, role assignments, and group
  eligibility) logged its action in the present tense even under `-WhatIf`, when no call was
  actually made; each now reads its verb from `$WhatIfPreference`. The group eligibility prune
  warning, dropped in an earlier round to avoid double-warning against
  `Remove-OERGroupEligibility`'s own warning, is restored -- the earlier removal left no warning at
  all under `-WhatIf` or a declined `-Confirm` prompt -- and the child cmdlet's duplicate is
  silenced at the call site instead.
- `Sync-OERStructureAccessPackage` matched a declared access package's `displayName` tenant-wide
  instead of inside its declared `catalog`, so two catalogs each holding a same-named package could
  update the wrong one; it now lists access packages by catalog and matches client-side. A failed
  catalog-scoped read is now a hard stop instead of falling through to create a duplicate
  high-privilege access package, which is indistinguishable from a genuine "no match" without
  `-ErrorAction Stop`.
- A group declared into an administrative unit that the same document also declares, but that does
  not exist yet, failed outright on the first apply because the AU had not been created; a declared
  administrative unit is now created before the groups placed in it.
- An immutable drift on a group's `roleAssignable` or `dynamic` flag (both are creation-only on
  Microsoft Graph) was previously reported as a matching `Unchanged` or attempted and left to fail
  silently; it is now reported as a `Skipped` drift naming the live and declared values, and the
  group's live dynamic/static state, not the document's declared one, decides which reconcile
  branch runs on the update path. A dynamic group's membership is rule-derived and Microsoft Graph
  rejects a manual add or remove against it; the handler no longer attempts to reconcile a dynamic
  group's members.
- `Get-OERInventory` emitted a `members` array for a dynamic administrative unit, which
  `Invoke-OERStructure` then tried to reconcile against a rule-owned membership; a dynamic AU's
  membership is no longer exported as an addable list.
- Access review recurrence ranges and settings (mail and reminder notification, justification,
  recommendations, auto-apply, default decision) were not captured by `Get-OERInventory` at all, so
  they could not round-trip. A recurrence interval the module's vocabulary cannot represent (for
  example a semi-annual cadence) is no longer silently rewritten to the nearest representable one
  -- it is left alone with a warning instead. A multi-stage access review was previously exported
  as a single-stage self review that had never actually been configured; it is now skipped with a
  warning naming the reviewer configuration that was not captured, rather than fabricating one.
- Approval-stage fallback approvers (`fallbackPrimaryApprovers`) were dropped every time a policy's
  approval stages were rebuilt on update, because Microsoft Graph takes the whole `approvalStages`
  array on write and a rebuilt stage sent an empty fallback array; the primary fallback
  (`-FallbackUser`/`-FallbackGroup`) is now modeled end to end through the structure engine.
  `fallbackEscalationApprovers` remains neither authorable nor read through this engine -- Learn
  frames the fallback mechanism around the primary approver only, so this is a documented gap, not
  a fix.
- `Export-OERInventory`'s PIM-enablement and notification-recipient lists could not distinguish a
  deliberately empty list from an absent field, so an apply document built from an export could
  never declare "no recipients" explicitly. Separately, the roster member-count join matched
  groups by `displayName`, which Entra permits to duplicate, so one group's member count could be
  attributed to a different, same-named group; the join now keys on object id (via
  `Get-OERInventory -IncludeId` used internally by `Export-OERInventory`) with a display-name
  fallback. The internal `-IncludeId` stamp does not change the emitted `inventory.json` shape --
  every id it adds is stripped again before the canonical document and the per-area files are
  written, matching `Get-OERInventory`'s own documented id-free portability contract.
- Two authored files broke the module's own encoding rule:
  `source/Private/Write-CmdletError.ps1` carried a UTF-8 BOM and two em-dashes, and
  `tests/Unit/Private/Initialize-OERAuth.Tests.ps1` carried 1,839 non-ASCII bytes. Both are now
  ASCII-only and BOM-free, which is what the new encoding gate asserts.
- Roughly a hundred assertions across the test suite looked like guards but could not fail, and
  are now repaired or replaced. The classes: `-ErrorVariable` assertions matching a BARE error
  code, which PowerShell satisfies with the mock's own auto-recorded record at about a dozen call
  boundaries before the cmdlet's `catch` ever runs -- these now match the cmdlet-qualified id;
  `Should -BeFalse` on tri-state permanence flags, which passes on `$null` and so could not tell
  "expiration not required" from "no such rule in the policy" -- now `Should -Be $false`; `.Count`
  assertions on a property chain, which pass when the property is absent because `$null.Count` is
  `0` -- now `@(...)`-wrapped; completer tests that assigned inside a `{ } | Should -Not -Throw`
  scriptblock, whose child scope left the outer variable `$null`, proven to pass even while the
  completer returned 14 results; and a format-view test that only asserted rendering did not
  throw, when a renamed column renders as an empty cell rather than an exception.
- The mandatory bearer scrub now has runtime proof that it actually RUNS, added across the cmdlets
  that previously had none -- the guard was documented and present in the source but untested on
  most call sites.
- `Disconnect-OER`'s suite executed the real `Disconnect-AzAccount`, so running the test suite
  cleared the operator's local Az context and token cache. It is a local context wipe, not a live
  tenant call, and `CLAUDE.md` hard rule 2 names `Connect-AzAccount` rather than its counterpart;
  the cmdlet is now mocked like the rest.
- Two assertions in the QA gate itself were inert: an `It` carrying `-Skip:$skipTest` against a
  variable defined nowhere in the repo, and an example-quality check whose `$function.Name` was
  `$null` at run time -- Pester v5 discovery-phase variables do not survive into the run phase --
  which degraded it to `-Match ''`, unconditionally true.
- `Get-OERAccessPackage -IncludeResourceRoles` and `-IncludePolicies` (#58): the request built the
  Graph `$expand` correctly, but the converter discarded the expanded data, so both switches were
  inert. Both now surface their collections as `ResourceRoleScopes` and `AssignmentPolicies` on the
  returned object, present only when the matching switch is supplied. `ResourceRoleScopes[].ResourceDisplayName`
  is `$null` by design here -- populating it needs a second, per-resource Graph call that only
  `Get-OERAccessPackageResourceRole` makes.
- **Breaking footgun fix (correctness):** `Get-OERRoleDefinition` no longer exposes a bare `Id`; the
  ARM resource path is `RoleDefinitionId`, aliased as `ResourceId` -- the same fix already shipped
  for `Get-OERSubscription`/`Get-OERManagementGroup` (see `[0.2.0]` below). A bare `Id` on a role
  definition collided with the `Id` alias already declared on `-PolicyId`/`-RoleEligibilityScheduleId`,
  so a piped role definition could silently mis-bind onto the wrong parameter on
  `Get`/`Set-OERRoleManagementPolicy` and the PIM cmdlets.
- Eleven more Graph collection reads that stopped at the first page now page fully via
  `Invoke-OERGraphRequest -All`: `Get-OERAccessReviewInstance` (the unfiltered list,
  `-IncludeStages`, `-IncludeDecisions`), `Get-OERAccessReviewInstanceDecision`,
  `Get-OERAccessReviewDefinition` (`-IncludeInstances` and the `-Filter` branch -- the latter
  matters because the endpoint silently ignores an unsupported filter and returns the WHOLE tenant
  collection when it does), `Get-OERGroupPimPolicy` and the private
  `Get-OERGroupPermanentEligibilityState` (the same beta rules endpoint, migrated together per the
  PIM-beta-pin rule), `Get-OERAccessPackageAssignment`, the private `Get-OERCatalogResourceRole`,
  and the apply engine's own `Sync-OERStructureAccessPackage` resourceRoleScopes read -- the
  sharpest of the eleven, since a truncated read there made the reconcile loop re-`Add` bindings it
  already had and, under `-Prune`, risked removing bindings it never saw.
- `Get-OERRoleAssignment -ResolveNames` now resolves principal display names in one batched
  `Resolve-OERPrincipalName` call per page instead of one Graph request per principal, using a new
  opt-in `-PreferDisplayName` mode on the resolver that never falls back to a UPN.
- New static QA gates in `tests/QA/sourcehygiene.tests.ps1`: duration-encoder template hygiene (only
  `ConvertTo-OERDuration` may build an ISO-8601-shaped format string), ARM api-version documentation
  (every `api-version=` literal in `source/` must be recorded in `docs/development/rationale.md`),
  and byte-identity between `suffix.ps1` and the dev-mode `psm1`'s type-data region. Every exported
  cmdlet now declares an explicit `[OutputType(...)]`, including `[OutputType([void])]` on the
  eleven that return nothing. Corrected help text across many cmdlets caught during this pass,
  including stale parameter-set wording left over from the Administrative Unit and Access Package
  pipeline-binding changes above.

### Changed

- The licence is unambiguously MIT. `LICENSE` (year corrected to 2026), the manifest `Copyright`
  and the README License section previously made three mutually incompatible statements; all
  three now agree.
- Manifest `Description` names Access Reviews and the JSON inventory/orchestration engine, the two
  capability areas it omitted.
- Manifest `ProjectUri` points at the real remote, `PhilipHaglund/Omnicit.EntraRBAC`. The previous
  value named an `Omnicit` organisation: `GET /orgs/Omnicit` does not resolve (`Omnicit` is a user
  account, not an organisation), and `Omnicit/Omnicit.EntraRBAC` does not resolve for the
  repository owner's own credentials, so a consumer following the link from a feed got a 404.
  Reversed for 1.0.0: the module is published from `Omnicit/Omnicit.EntraRBAC`, and `ProjectUri`
  and `LicenseUri` point there.
- README no longer claims the module is internal and never published to the public Gallery. It is
  MIT licensed and destined for the PowerShell Gallery once 1.0.0 is cut; the same correction is
  applied to the trailing note in `azure-pipelines.yml`.
- `.gitattributes` declares a line-ending policy that git can actually act on. `* text
  eol=autocrlf` was inert -- `eol` accepts only `lf` or `crlf` -- so checkout fell back to the
  per-machine `core.autocrlf`. Replaced with `* text=auto` plus explicit per-extension rules. The
  index was already LF throughout, so no tracked file changes content.
- `GitVersion.yml` `next-version` 0.0.1 -> 1.0.0, so an untagged main build reads as a 1.x
  prerelease. Note that `source/Omnicit.EntraRBAC.psd1`'s `ModuleVersion` is NOT the version
  source of truth: ModuleBuilder overwrites it at build time from GitVersion or `$env:ModuleVersion`.
- `azure-pipelines.yml` `pathToSources` drops the `$(dscBuildVariable.RepositoryName)` segment.
  This is a single-repo pipeline, so the checkout lands directly in `Build.SourcesDirectory` and
  the extra segment resolved to a nonexistent path, silently breaking source rendering in the
  published Code Coverage tab. Coverage numbers were never affected.
- This changelog's pre-release history is closed under dated `0.x` headings. It was previously a
  single 1040-line `[Unreleased]` section, which Sampler truncates at 10,000 characters when it
  writes the built manifest's `ReleaseNotes` -- the published notes ended mid-word.
- README no longer advertises Access Reviews, Azure resources and JSON orchestration as unbuilt
  future work. The `## Coming in Later Phases` section described three phases that had all shipped.
- The about topic's Azure scope list says three forms, not two. It omitted `-ManagementGroup`,
  which every Azure RBAC and PIM assignment cmdlet declares, so management-group-scoped delegation
  was undocumented in the only in-box overview. It also now states that
  `Get`/`Set-OERRoleManagementPolicy` take the same scope forms minus `-ResourceType` and
  `-ResourceName`, and that `Set`/`Remove-OERRoleAssignment` take `-Id` only.
- `GitVersion.yml`'s three bump-message regexes matched loose prose instead of requiring an
  explicit directive -- the old patch pattern had no word boundary at all, so it even matched
  inside "prefix" and "suffix" or a bystander "this fixes a typo" note in an unrelated commit
  body. All three now require an explicit `+semver:` trailer naming the level: `breaking` or
  `major`, `feature` or `minor`, `fix` or `patch` (the untouched no-bump rule already required
  `+semver: none` or `+semver: skip`). The major regex additionally honors a leading
  conventional-commit `!:` breaking-change marker (for example `fix(errors)!:`), so a marked
  breaking change still bumps major even without the trailer. A commit carrying none of these now
  falls back to an unconditional patch bump instead of guessing from prose.

### Removed

- `codecov.yml`. It advertised a 70% codecov.io project gate that no pipeline step ever fed, while
  the gate that actually runs is `build.yaml` `CodeCoverageThreshold: 80`.
- The `inspiration/` tree (4 files, ~93 KB). It was a named third party's internal tooling, kept
  as a porting reference for phase 1, which is complete.

### Security

- Removed real customer data from the repository. The tracked `inspiration/` tree hard-coded a
  named customer's tenant GUID as a parameter default and six real approver object ids. Separately,
  five untracked `Get-OERInventory` exports (~170 KB) sat un-ignored inside the tracked
  `docs/examples/` directory carrying 18 distinct real identities across two tenants, including a
  customer domain address. `git log --all` confirms those five were never committed, so that half
  was a near-miss rather than a history leak; the `inspiration/` identifiers remain in history.

## [0.5.0] - 2026-08-15

### Added

- Private helper `ConvertTo-OERODataFilterValue`, the single owner of the OData filter-value
  escaping rule (double an embedded single quote, then percent-encode per RFC 3986). Adopted by all
  eleven Graph display-name lookups that interpolate a caller-supplied value into a URL `$filter`.
- Regression tests for the mandatory `Remove-OERErrorRecord` bearer-token scrub on the Graph and ARM
  wrappers, asserting against the caller's `$global:Error` by exception reference identity rather
  than a module-scoped `$Error` count that could never have held the record.
- A throwing-Graph-catch test for every entitlement-management and access-review cmdlet whose catch
  block can leak a bearer token (29 cmdlets; `Get-OERAccessReviewInstance` was already covered from
  an earlier audit PR, so this closes the remaining 29 of the 30 EM/AR cmdlets that call Graph).
- `-WarningVariable` assertions proving the CLAUDE.md-mandated operator warning fires before the
  destructive call, across the ten destructive EM/AR/AU/Group/Azure-PIM cmdlets that lacked one
  (`Remove-OERRoleAssignment` already had this assertion and was not part of this sweep);
  `Remove-OERGroup` and `Remove-OERResourceGroup` additionally gained a `-WhatIf` (no warning, no
  call) case and a Graph/ARM-failure bearer-scrub case.
- Real end-to-end pipeline-binding tests on ten Azure RBAC/PIM cmdlets that previously asserted only
  parameter-attribute metadata, plus regression guards on `Get-OERManagementGroup` and
  `Set-OERRoleManagementPolicy` proving a piped subscription or management group cannot mis-bind its
  ARM resource path as a PIM schedule id or select the `ByPolicyId` parameter set.
- Branch coverage for the previously untested `Add-OERGroupMember` per-principal Graph failure,
  `Add-OERGroupEligibility` POST failure, both `Enable-OERGroupPermanentEligibility` re-throws, and
  the `Get-OERPimGroupPolicyId` owner-match and fallback-to-first branches.

### Fixed

- Display-name lookups for access packages, catalogs, administrative units, groups, access review
  definitions, applications (service principals) and users -- both the private `Resolve-*Id` helpers
  and the `Get-*` `ByName` branches for access packages, catalogs, administrative units and groups --
  now percent-encode the filter value. Previously a display name containing `&`, `+`, `#` or a space
  corrupted the query string and failed to resolve; a name containing `#` silently truncated the
  request at the URL fragment delimiter.
- Known regression: an operator who pre-encoded a display name to work around the old bug
  (`-DisplayName 'R%26D'`) now gets it double-encoded to `R%2526D` -- pass the literal name instead.
- CLAUDE.md's Module Layout named 64 of 88 exported cmdlets and 53 of 106 private helpers, and
  listed two Access-Review helpers that do not exist (`Resolve-OERAccessReviewScopeQuery`,
  `Resolve-OERRecurrencePattern`, both wrong-verb/noun stand-ins for the real
  `New-OERAccessReviewScopeQuery` / `New-OERAccessReviewRecurrence` files). Both rosters are
  regenerated from the real file tree (88 exported cmdlets, 107 private helpers as of this revision).

### Changed

- The canonical GUID regex is no longer re-implemented inline: thirteen `Resolve-*`/`Get-*` call
  sites across the module now call the existing `Test-OERGuid` predicate. The three `-as [guid]`
  sites in `Get-OERInventory` and `New-OERGroup` deliberately keep the wider cast, which
  `Test-OERGuid`'s help now documents.

## [0.4.0] - 2026-08-14

### Added

- Private predicate `Test-OERTenantAlias`, the single owner of the safe-profile-name rule shared by
  `Resolve-OERProfilePath`, the four `*-OERConfiguration` cmdlets and `Connect-OER`. Beyond the
  path-traversal character set, it also rejects a Windows reserved device name (`CON`, `PRN`, `AUX`,
  `NUL`, `COM1`-`COM9`, `LPT1`-`LPT9`), matched against the whole alias or the segment before the
  first dot, since such a name addresses a device rather than a regular file on Windows.
- `-WhatIf` support on `Export-OERInventory`: the bundle plan (target folder and the full file list) is
  reported without touching disk.
- `Omnicit.EntraRBAC.AssignmentRequest` output type, Format view and the private
  `ConvertTo-OERAssignmentRequest` converter, so `New-OERAccessPackageAssignment` returns a tagged
  object instead of the raw Graph response.
- `Omnicit.EntraRBAC.GroupPimPolicyResult` output type and Format view for the
  `Set-OERGroupPimPolicy` patch summary, carried on top of the shared `GroupPimPolicy` type name.
- Private converters `ConvertTo-OERTenantConfiguration`, `ConvertTo-OERGroupEligibilityRequest`,
  `ConvertTo-OERGroupPimPolicy` and `ConvertTo-OERGroupPimPolicyResult`, each the single owner of a
  shape that used to be hand-built inline in two or three cmdlets.
- `PrincipalId` and `ResourceId` on the access review decision shape; Graph returns both and they
  were previously dropped.
- A `RequestId` column on the `Omnicit.EntraRBAC.GroupEligibility` table view, which previously hid
  the shape's primary property.

### Changed

- **Behaviour change for pre-existing Tenant Profiles:** `Test-OERTenantAlias` now rejects any alias
  containing characters outside letters, digits, dot (`.`), underscore (`_`) and hyphen (`-`), and any
  Windows reserved device name. A profile `.psd1` already on disk whose basename uses a space, a
  non-ASCII letter (for example an accented or Nordic character) or any other character outside that
  set can no longer be read, written or deleted through `-TenantAlias` -- `Get-OERConfiguration` with
  no `-TenantAlias` still lists it (and now also warns about it). Rename the file on disk to a basename
  built only from that character set to make it addressable again.
- The reused `GroupNotFound` errors on `Get-OERGroupMember`, `Get-OERGroupEligibility`,
  `Get-OERGroupPimPolicy`, `Add-OERGroupEligibility`, `Remove-OERGroupEligibility` and
  `Set-OERGroupPimPolicy` now name a concrete next step (verify the display name matches exactly, or
  pass the object id) instead of a bare not-found message. The ErrorId is unchanged.
- The administrative-unit cmdlets report a failed lookup (403, throttling, 5xx) as
  `AdministrativeUnitResolveFailed` / `DirectoryRoleResolveFailed` instead of masking it as a
  not-found. A genuine no-match still reports the original `AdministrativeUnitNotFound` / `RoleNotFound`
  -- this required `Resolve-OERDirectoryRoleId` (private) to change contract: it now returns `$null` on
  a genuine no-match, mirroring its sibling `Resolve-OERAdministrativeUnitId`, instead of throwing, so
  the ordinary "operator typed a bad role name" path still reaches `RoleNotFound` and only a real
  transport/permission failure reaches `DirectoryRoleResolveFailed`.
- `Export-OERInventory`'s `-Force` help now describes what the switch actually does; it never prompted.
- `New-OERConfiguration` and `Set-OERConfiguration` now return the full tenant configuration shape
  including `Naming` and `Defaults`; they previously emitted a three-property variant under the same
  type name, so reading `.Naming` off their output silently yielded `$null`.
- `Add-OERAccessPackageResourceRole` returns a tagged `Omnicit.EntraRBAC.AccessPackageResourceRole`.
  Graph answers the create with only an id, so this cmdlet now re-reads the binding through
  `Get-OERAccessPackageResourceRole` and emits that object, falling back to a composed object (from
  the already-resolved catalog resource) only when the confirmation read fails or finds no match.
- `Get-OERGroup -IncludeMembers` returns tagged `Omnicit.EntraRBAC.GroupMember` objects instead of
  raw Graph dictionaries, matching `Get-OERAdministrativeUnit -IncludeMembers`.
- `Set-OERGroupPimPolicy` reports only the settings it actually patched. A setting whose parameter
  was not bound is now absent from the summary instead of being reported as `$null` or `$false`. The
  eligible- and active-expiration rules are each a unit -- binding either the duration or the
  permanence switch sends both fields, so both are reported.
- The directory object kind is stored as `ObjectType` on the administrative unit member shape (it was
  `Type`), matching the group member shape. `Type` remains as an alias.
- Access review decisions store `PrincipalDisplayName`, `ResourceDisplayName`,
  `ReviewedByDisplayName` and `AppliedByDisplayName`; access package assignments store
  `AccessPackageDisplayName`. The former bare-noun spellings remain as aliases.
- The role assignment, active role assignment and eligible role assignment shapes store their ARM id
  once under its domain-specific name; `Id` is now an alias of that value rather than a second copy.
- `New-OERAccessPackageAssignment` exposes the created request id as `RequestId` and deliberately no
  longer emits a bare `Id`. The id identifies the REQUEST, not the resulting assignment, and a bare
  `Id` would invite a caller to hand-write `Remove-OERAccessPackageAssignment -AssignmentId $r.Id` --
  the same footgun `ConvertTo-OERSubscription` and `ConvertTo-OERResource` already avoid with
  `ResourceId`. (`Invoke-OERGraphRequest` returns a `Hashtable`, which does not bind
  `ValueFromPipelineByPropertyName` at all, so the old raw response never actually bound
  `-AssignmentId` through pipeline binding either -- the risk was always the hand-written case, not an
  automatic one.) Back-compat cost: a script that used to read `$r = New-OERAccessPackageAssignment
  ...; $r.id` directly now gets `$null` back and must switch to `$r.RequestId`.

### Fixed

- `Set-OERGroupPimPolicy` writes a non-terminating `PolicyRulesRejected` error (in addition to the
  summary object) when Graph rejects one or more rules, so a partially applied high-privilege PIM policy
  change is detectable with `-ErrorAction Stop` and by `Invoke-OERStructure`. The rejection count is now
  reported against the rules actually sent to Graph this run, not the rules built -- a rule declined at
  an interactive `-Confirm` prompt was never sent, so it must not inflate the denominator.
- A 401 force-refresh and the ACRS claims-challenge step-up (`Invoke-OERGraphRequest` and
  `Invoke-OERArmRequest`) now forward the cached `ClientId`, so a user-assigned managed identity
  re-acquires the same principal instead of silently falling back to the system-assigned identity.
- `Get-OERAccessReviewInstance -Instance` reports a missing instance as `AccessReviewInstanceNotFound`
  instead of surfacing the raw Graph failure, matching how it already reports a missing definition. The
  detection is a strict allowlist of Graph not-found error codes and deliberately never consults the
  failure message text: Graph uses existence-ambiguous wording for some authorization failures
  specifically so it does not confirm existence to an unauthorized caller, and a 403 must never be
  reported as a missing instance.
- A catalog that cannot be derived from an access package now reports `CatalogDerivationFailed` naming
  the package, instead of a `CatalogNotFound` carrying the access package's name.
- `-EndDate` together with `-Occurrences` on `New-`/`Set-OERAccessReviewDefinition` is a non-terminating
  `MutuallyExclusiveParameter` error instead of a pipeline-terminating throw.
- `Get-OERAccessPackageAssignment` returned every nested field as `$null` (pre-existing on `main`): it
  now sends `$expand=target,accessPackage` and uses the v1.0 `target/objectId`, `state`, `expiredDateTime`.
- Output tagging is now applied on every create path: `New-OERAccessPackageAssignment` and
  `Add-OERAccessPackageResourceRole` no longer emit raw `Invoke-OERGraphRequest` dictionaries.
- `Get-OERAccessPackageResourceRole` reported the wrong value in `ResourceDisplayName`. Live, Graph's
  `accessPackageResourceScope.scope.displayName` is the display name of the SCOPE, not of the
  resource -- for an Entra group binding it is the literal string `Root`, so two different group
  bindings on the same access package could not be told apart by name. The raw value is now exposed
  honestly as `ScopeDisplayName`; `ResourceDisplayName` is resolved separately by joining the
  binding's `originId` against the access package's catalog resources, and left `$null` when that
  join cannot be completed. `Add-OERAccessPackageResourceRole` previously masked this by synthesizing
  `ResourceDisplayName` from the resolved catalog resource on create only, so create output
  (`Test-Group`) silently disagreed with read output (`Root`) for the same binding; it now re-reads
  the created binding through `Get-OERAccessPackageResourceRole` so create and read agree by
  construction. The `Omnicit.EntraRBAC.AccessPackageResourceRole` table view's `OriginSystem` column
  (constant `AadGroup` for every group binding) is replaced with `OriginId`, the value that actually
  distinguishes two group bindings.

### Security

- New private helper `Remove-OERErrorRecord`, and the correction of the module's mandatory
  bearer-hygiene rule. The idiom documented until now, `$null = $Error.Remove($PSItem)` -- used at 295
  call sites across 100 files -- never actually removed anything: inside module code the automatic
  `$Error` variable resolves to the module's own private list, so the record a catch block swallows is
  never in it, and even against the caller's real `$global:Error` the `ErrorRecord` bound to `$PSItem`
  is a different object instance than the one PowerShell appended there, so a reference-equality
  `.Remove($PSItem)` silently no-ops. Only the record's `.Exception` object is reference-stable across
  that boundary. `Remove-OERErrorRecord -Record $PSItem` scans `$global:Error` and removes the first
  entry whose `.Exception` is reference-identical (never message-equal) to the supplied record's
  `.Exception`; it is defensive against a null record or exception, never throws, and makes no network
  call. All 295 call sites were swept from the old idiom to the helper, and CLAUDE.md's four statements
  of the bearer-hygiene rule were corrected to document the helper and why the old idiom could not work.
- `Convert-GraphHttpException` no longer returns the raw caught record when the failure body is not
  parseable JSON (a genuine transport failure, or an HTML gateway 5xx page). It previously returned the
  original caught record unchanged, and `Invoke-OERGraphRequest` re-threw it, so every public cmdlet's
  catch block scrubbed `$Error` and then re-published that exact record via `WriteError` -- the record
  whose `.Exception` references the `HttpRequestMessage` carrying `Authorization: Bearer <token>` in
  plain text. It now always returns a freshly built `ErrorRecord` with a status-derived (or generic
  `GraphError`) code and the exception's `Message` STRING as the detail text (safe -- only the exception
  OBJECT is dangerous), never chaining the original exception.
- `Get-OERGroupPermanentEligibilityState` guards its rules read: a swallowed failure is scrubbed from
  `$global:Error` before being rethrown, so the helper is safe for reuse rather than safe only because
  its callers (`Add-OERGroupEligibility`, `New-OEREligibleRoleAssignment`, `New-OERActiveRoleAssignment`)
  happen to guard it. The record is rethrown unchanged (not re-converted): `Invoke-OERGraphRequest`
  already routes every non-recoverable failure through `Convert-GraphHttpException` before throwing it,
  so a second conversion pass would destroy the real Graph error code the caller needs.
- `-TenantAlias` is validated before it is used as a file name, and `Resolve-OERProfilePath` proves the
  resolved path stays under the profile base directory. `New-OERConfiguration -TenantAlias
  '../../../evil'` previously wrote a `.psd1` outside the profiles directory (and `Get-`/
  `Remove-OERConfiguration` would read and delete outside it).

## [0.3.0] - 2026-08-12

### Added

- One duration vocabulary across the module (audit PR6): `-DurationDays` binds the access-review
  `-DurationInDays` (`New`/`Set-OERAccessReviewDefinition`, `New-OERAccessReviewStage`), and
  `-DurationDays`/`-DurationHours` bind the access-package `-DurationInDays`/`-DurationInHours`
  (`New`/`Set-OERAccessPackageAssignmentPolicy`). `Add-OERGroupEligibility` gains `-DurationDays`,
  and `Set-OERGroupPimPolicy` gains `-EligibleDurationDays`/`-ActiveDurationDays`.
- New private helper `Resolve-OERDurationInput`: the single owner of "user-supplied duration ->
  canonical ISO 8601", accepting either a bare whole-unit count or an ISO 8601 duration.
- One naming vocabulary for shared concepts: `Connect-OER -BasePath`, `Get`/`Set`/`Remove-OERGroup
  -Group`, `Get-OERAccessReviewInstance -Instance`, `-PrincipalId` on the AU member cmdlets, and
  `-ManagementGroup`/`-Subscription` on `Get-OERManagementGroup`/`Get-OERSubscription`.

### Changed

- `Set-OERRoleManagementPolicy -EligibleDuration`/`-ActiveDuration` now accept either a whole day
  count (as before) or the raw ISO 8601 duration that `Get-OERRoleManagementPolicy` emits, closing
  the `Get`|`Set` round-trip. Both are also bindable as `-EligibleDurationDays`/`-ActiveDurationDays`.
- `Add-OERGroupEligibility -Duration` additionally accepts a raw ISO 8601 duration (for example
  'PT8H'); a bare day count keeps its original meaning.
- `Resolve-OERPolicyRulePatch` encodes `ActivationMaxHours` through `ConvertTo-OERDuration` and
  accepts an already-ISO eligible/active duration.
- `Get-OERGroup`/`Set-OERGroup`/`Remove-OERGroup -Id` (now an alias of the unified `-Group`
  parameter) resolves a non-GUID value by display name instead of sending it verbatim into the
  Graph request URI: before this change that produced a 404, so the practical effect is harmless
  -- a real Entra group object id is always a GUID, and a GUID still resolves exactly as before.

### Fixed

- Regression guards so a piped subscription or management group can never mis-bind a PIM schedule id
  or select the `ByPolicyId` parameter set (`B-subscription-mg-id-collides-id-alias-params`).

**No breaking changes: every previous parameter name still binds as an alias.**

## [0.2.0] - 2026-08-11

### Added

- Round-trip parity part 2 -- schema fidelity and Azure PIM policy depth (audit PR5, theme T3). Every
  change is additive: no parameter or document field was renamed, and every document that validated
  before still validates and applies identically.
  - The `roleManagementPolicies` apply surface now covers the full settable Azure PIM policy instead of
    two fields. `Get-OERInventory` projects `eligibleDurationDays`, `allowPermanentActiveAssignment`,
    `activeDurationDays`, `requireMfaOnActivation`, `requireJustificationOnActivation`,
    `requireTicketOnActivation`, `requireApproval`, `approvers` (`users`/`groups` as object ids),
    `authenticationContextId`, `requireMfaOnActiveAssignment` and
    `requireJustificationOnActiveAssignment`; the schema and the offline validator declare and check
    all of them; and `Invoke-OERStructure` reconciles them through the new pure diff helper
    `Resolve-OERRoleManagementPolicyChange` (`G-rmp-apply-only-two-fields`). `approvers.users` and
    `approvers.groups` are independently optional: declaring only one half in the document carries the
    other half forward from the live policy instead of sending it empty, because Azure Resource Manager
    replaces the whole `primaryApprovers` array on any approver patch, and an un-seeded half would
    silently drop live approvers.
  - `ConvertTo-OERRoleManagementPolicy` (and therefore `Get`/`Set-OERRoleManagementPolicy`) gained
    `EligibleDurationDays` and `ActiveDurationDays`, the maximum lifetimes parsed into whole days
    alongside the existing raw ISO 8601 `EligibleDuration` / `ActiveDuration`.
  - The `accessReviews` schema and validator now describe everything the inventory emits and the apply
    handler consumes: `reviewers`, `fallbackReviewers`, `descriptionForAdmins`,
    `descriptionForReviewers`, `durationInDays`, `startDate`, `endDate`, `occurrences`,
    `mailNotification`, `reminderNotification`, `requireJustification`, `recommendationsEnabled`,
    `autoApplyDecisions` and `defaultDecision` (`G-ar-apply-schema-parity-gap`,
    `G-accessreview-inventory-fields-not-in-schema`). The create path passes the range and settings
    fields through to `New-OERAccessReviewDefinition`.
  - Catalog resources gained an optional `url` field. `Get-OERInventory` projects the SharePoint Online
    site URL (the resource `originId`) there, and `Invoke-OERStructure` onboards and matches a
    SharePoint site by that URL instead of feeding a site title to `-SharePointSite`
    (`G-sharepoint-resource-cannot-roundtrip`).
  - The group schema declares `mailNickname` and `administrativeUnit`, and `Get-OERInventory` projects
    `mailNickname`, so a custom mail nickname survives a round-trip
    (`G-group-mailnickname-no-read-path-in-inventory`). `administrativeUnit` remains create-only and is
    not captured by inventory.
  - New private helpers `Resolve-OERRoleManagementPolicyChange` and `Resolve-OERAccessReviewChange`
    (pure, tenant-free diffs owning the presence semantics and the field-to-parameter mapping for
    their sections).

- `Get-OERInventory` now projects `eligibility[].accessType` and `eligibility[].durationDays`, the
  administrative unit `dynamic` / `membershipRule` / `membershipRuleProcessingState` /
  `hiddenMembership` fields, the access package `hidden` flag, and the role assignment `condition` /
  `conditionVersion` / `description`, so those values survive an inventory-to-apply round-trip
  (audit PR4, theme T3).
- The apply schema (`Get-OERStructureSchemaJson`) and the offline validator
  (`Test-OERStructureSchema`) declare and validate all of the above, including the new
  `member`/`owner` accessType enum, the `On`/`Paused` membershipRuleProcessingState enum, and the
  condition/conditionVersion pairing rules.
- New private helpers `Resolve-OEREligibilityDuration` (recovers a declared eligibility window from a
  schedule instance) and `Resolve-OERGroupEligibilityChange` (pure eligibility diff).
- `Set-OERAccessPackageAssignmentPolicy -RequestorScope` is now optional; omitting it preserves the
  policy's live requestor scope instead of resetting it.
- `Add-OERGroupEligibility -Action` (`adminAssign` | `adminUpdate`, default `adminAssign`) selects the
  Microsoft Graph admin operation for the eligibility schedule request. The `Invoke-OERStructure` apply
  engine (via `Sync-OERStructureGroup`) passes `-Action adminUpdate` when it re-issues an eligibility
  whose declared duration or permanence has drifted from the live schedule instance, since Graph
  rejects an `adminAssign` against a principal that is already eligible.

- `Set-OERRoleAssignment` -- edits the description and ABAC condition/conditionVersion of an existing
  Azure role assignment in place, via a read-modify-write PUT to the same assignment id (ARM
  api-version 2022-04-01). An omitted parameter preserves the live value; `-Condition ''` removes the
  condition and warns, because removing an ABAC condition widens access.
- `Set-OERAdministrativeUnit -MembershipType` -- converts an existing administrative unit between
  Assigned and Dynamic. A conversion to Dynamic carries `-MembershipRule` in the same PATCH, and fails
  with `MembershipRuleRequired` when neither the call nor the live unit supplies a rule. Binding
  `-MembershipType` emits a warning before the PATCH: Microsoft Graph documents that the existing
  membership might change based on the rule supplied for dynamic membership, and on a dynamic unit the
  rule owns the membership -- members can no longer be added or removed manually at all. (The cmdlet's
  `ConfirmImpact` is deliberately unchanged, so an unrelated description edit still does not prompt.)
- `ConvertTo-OERRoleAssignment` -- and therefore `Get-OERRoleAssignment`, `New-OERRoleAssignment` and
  `Set-OERRoleAssignment` -- projects `DelegatedManagedIdentityResourceId`, the Azure Lighthouse /
  cross-tenant delegation link (null when the assignment has none). `Set-OERRoleAssignment` carries that
  property forward verbatim on an edit, so an operator now has a way to verify it survived.

- Argument completers and discoverability (audit PR3, theme T5). Every change is additive: no parameter
  was renamed, no `ValidateSet` was attached, and no request body changed, so free-text values, GUIDs
  and existing apply documents keep binding exactly as before.
  - `-TenantAlias` now tab-completes from the Tenant Profiles stored on disk on `Connect-OER`,
    `Get-OERConfiguration`, `Set-OERConfiguration` and `Remove-OERConfiguration`, honouring a
    `-BasePath`/`-ProfileBasePath` already typed on the same command line. `New-OERConfiguration` is
    deliberately excluded, since the alias it creates must not already exist
    (`E-tenantalias-no-completer`).
  - `-Role` now tab-completes on every cmdlet that takes an Azure RBAC role name, not just the two read
    cmdlets: `New-OERRoleAssignment`, `New`/`Remove`/`Enable`/`Disable-OEREligibleRoleAssignment`,
    `New`/`Remove-OERActiveRoleAssignment`, `Set-OERRoleManagementPolicy` and `Get-OERInventory`
    (`E-role-completer-missing-on-write-cmdlets`,
    `E-role-completer-missing-on-state-changing-cmdlets`). `Add-OERAccessPackageResourceRole -Role` is
    excluded on purpose -- it names an entitlement-management resource role, not an Azure role.
  - `Add`/`Remove-OERAdministrativeUnitScopedRole` accept `-Role` as an alias of `-RoleName`, so the
    spelling learned on the Azure role cmdlets works on the directory-role cmdlets too, and `-RoleName`
    now tab-completes from a curated offline set of the built-in Entra roles that Microsoft documents as
    assignable at administrative-unit scope (`E-role-vs-rolename-inconsistent`). `-RoleName` remains the
    parameter name; custom role names still bind.
  - `-Verbose` is now useful on the high-privilege paths (`E-verbose-output-largely-absent`).
    `Invoke-OERGraphRequest` and `Invoke-OERArmRequest` log the method and URI of every request (method
    and URI only -- never a header, never a body), and 17 create/remove RBAC, PIM, group-membership and
    administrative-unit cmdlets report each resolution step: target scope, resolved role, resolved
    principal, resolved group or unit. `Remove-OERRoleAssignment` is deliberately unchanged -- it only
    regex-validates a received `-Id` and has nothing to resolve, and the wrapper's request-line log
    already carries the id.

- Friendly principal-input parity (audit PR2, themes T1/T5): every principal-taking cmdlet now
  accepts a user principal name, a group display name or a service principal display name in
  addition to a raw object id, and a non-GUID value passed to a raw id parameter produces an
  actionable non-terminating error instead of an opaque Graph 400/404. Additive only -- no parameter
  was renamed and no request body changed; existing calls and apply documents keep working unchanged.
  - `Add`/`Remove-OERGroupMember` gain `-User`, `-GroupPrincipal` and `-ServicePrincipal` (all accept
    multiple values and are unioned with `-PrincipalId`), and `-PrincipalId` is now GUID-guarded
    (`A-groupmember-principalid-guid-only`, `E-group-member-upn-silent-badrequest`). `-GroupPrincipal`
    is the group being added; `-Group` remains the target group.
  - `Add`/`Remove-OERAdministrativeUnitMember` gain `-User` and `-Group`, and `-MemberId` is now
    GUID-guarded with an `InvalidMemberId` error (`A-au-member-memberid-guid-only`,
    `E-group-au-member-forces-guid-no-friendly-input`).
  - `Add`/`Remove-OERAdministrativeUnitScopedRole` gain `-User` and `-Group`, and `-PrincipalId` is
    now GUID-guarded (`A-au-scopedrole-principalid-guid-only`).
  - `Add`/`Remove-OERGroupEligibility` can finally name a group or service principal via
    `-GroupPrincipal`/`-ServicePrincipal`, which the help already documented as valid eligible
    principals (`A-eligibility-principal-user-only-by-name`).
  - `New-OERAccessPackageAssignment` gains `-User`, GUID-guards `-TargetId` with an `InvalidTargetId`
    error, and binds `-TargetId` from the pipeline by property name
    (`A-ap-assignment-target-guid-only`).
  - `-PrincipalId`/`-MemberId`/`-TargetId` are no longer `Mandatory` on the cmdlets above, since a
    principal may now be named instead. Omitting every principal parameter is a non-terminating
    `NoPrincipal` error rather than an interactive prompt, matching the eligibility cmdlets.
  - Every new parameter is declared at the END of its param block so the positional binding of the
    pre-existing parameters is unchanged (the module uses no explicit `Position` attributes, so
    declaration order is what assigns positions). Positional regression tests cover this.

- Pipeline & binding quick wins (audit PR1, theme T1): `Get-* | Set/Remove-*` and the headline
  `Get-OERInventory | Invoke-OERStructure` loop now bind the way an operator expects, and two
  correctness footguns are fixed. Additive only -- every existing call and apply document keeps
  working; new bindings and aliases never rename an existing parameter.
  - **Footgun fix (correctness):** `Get-OERSubscription`/`Get-OERManagementGroup` now expose the ARM
    resource path as `ResourceId` instead of a bare `Id`, so a piped subscription/management group no
    longer mis-binds `Enable-OEREligibleRoleAssignment -RoleEligibilityScheduleId` or selects the
    wrong `ByPolicyId` set on `Get`/`Set-OERRoleManagementPolicy` (`B-subscription-mg-id-collides-id-alias-params`).
  - **Footgun fix (correctness):** `Get-OERGroupMember | Add/Remove-OERGroupMember` now round-trips.
    The group parameter is `-Group` (aliases `Id`/`GroupId`/`DisplayName`, `GroupId`-first so a member
    object binds the group, not the principal); `-PrincipalId` and `-AccessType` bind from the pipeline;
    the `GroupMember` object gains a `PrincipalId` property (`B-groupmember-remove-id-binds-principal-not-group`).
  - `Get-OERInventory | Test-OERStructure` and `Get-OERInventory | Invoke-OERStructure -WhatIf` now
    work directly via a new `-InputObject` (aliases `Inventory`/`Document`) parameter set that reuses the
    existing document read/normalize path -- identical to the old `| ConvertTo-Json | ... -Json`
    round-trip (`B-inventory-cannot-pipe-into-structure`).
  - Pipeline binding added so natural `Get-* | Set/Remove-*` chains bind: `Set/Remove-OERConfiguration`
    (`-TenantAlias`, plus `-TenantId`/`-Naming`/`-Defaults` on Set); `Remove-OERAccessPackageResourceRole`;
    `Remove-OERAdministrativeUnitScopedRole` (`-ScopedRoleMembershipId`/`-PrincipalId`/`-RoleId`);
    `New-OERAccessPackageAssignmentPolicy`, `Add-OERAccessPackageResourceRole`,
    `Get-OERAccessPackageAssignmentPolicy`, `Get-OERAccessPackageAssignment` (`-AccessPackage`);
    `New-OERAccessPackage`, `Add-OERCatalogResource`, `Get-OERCatalogResource`, `Remove-OERCatalogResource`
    (`-Catalog`); `Get-OERGroup` (`-Id`/`GroupId`, `-DisplayName`); and `Connect-OER` (`-TenantAlias`),
    `Set/Remove-OERGroup` and `Set/Remove-OERAdministrativeUnit` (ByName `-DisplayName`). Where a friendly
    alias would collide with an existing parameter name (PowerShell `ParameterNameConflictsWithAlias`),
    the collision-free subset is used (e.g. `Remove-OERCatalogResource -Catalog` aliases only `CatalogId`).
  - Metadata-only "pipeline binding" tests on the Azure PIM cmdlets were replaced/supplemented with real
    end-to-end pipe tests so a future alias-collision regression is caught (`H-pipeline-binding-metadata-only-tests`).

- Granular Access Package assignment policy support: `New-OERAccessPackageRequestorSettings` builds a
  requestor-settings object (AllowSelfRequest, AllowManagerRequest, ManagerLevel, AllowCustomSchedule,
  AllowSelfExtend) for use with `New/Set-OERAccessPackageAssignmentPolicy`. The two policy cmdlets gain
  `-RequestorSettings`, `-RequireApproval`, `-RequireRequestorJustification`,
  `-RequireApprovalForUpdate`, `-DurationInHours`, and `-DisableAssignmentNotifications` parameters.
  `New-OERAccessPackageApprovalStage` gains `-ApproverInfoVisibility` (Default/Visible/NotVisible).
  `Description` now defaults to the policy display name when omitted. `Set-OERAccessPackageAssignmentPolicy`
  is now a read-modify-write (GET then PUT) so the existing `reviewSettings` and `questions` are always
  preserved on update. The full round-trip -- schema, inventory projection, LLM prompt, and apply diff --
  is described in `docs/inventory-to-llm/README.md`. Known limitations (out of scope, preserved
  by the read-modify-write): `reviewSettings` (policy-embedded access reviews) and custom requestor
  `questions` cannot be expressed in an apply document; fallback approvers are preserved when a stage is
  unchanged but are dropped when the stage is rebuilt due to another field change. The "Who can get
  access = None" scope (`allowedTargetScope notSpecified`) round-trips: `New-OERAccessPackageRequestorScope`
  `-Scope` now also accepts `NotSpecified` and `AllConfiguredConnectedOrganizationUsers`, so
  `Invoke-OERStructure` reconciles such a policy instead of failing validation. Added test coverage for
  stage manager-level projection and the assignment-policy approver-default fallback, and guarded the
  schema-validation tests where `Test-Json -Schema` is unavailable.

- PIM for Groups: full member AND owner policy support in the apply document, Set/Get cmdlets, the
  apply engine, the inventory projection, and the embedded schema. `pimPolicy` now accepts nested
  `member` / `owner` blocks covering activation window + enablement, eligible/active expiration +
  permanence, and the three admin notification alert recipient lists. The flat member-only `pimPolicy`
  form remains valid. `Set-OERGroupPimPolicy` patches only the rules whose parameters are supplied.

- Resource-level RBAC: `Get-OERResource` lists Azure resources in a subscription or resource group
  (api-version `2025-04-01`, client-side `-Name`/`-ResourceType` filters) and, with
  `-IncludeRoleAssignments` (optionally `-ResolveNames`), aggregates the role-assignment delegations
  at each resource's scope -- the resource-scope mirror of `Get-OERResourceGroup
  -IncludeRoleAssignments`. Output is tagged `Omnicit.EntraRBAC.Resource` (exposing `SubscriptionId`,
  `ResourceGroup`, `ResourceType`, `ResourceName`, and the full `ResourceId`). `Resolve-OERScope`
  gains `-ResourceType`/`-ResourceName`, and the 10 Azure RBAC and PIM assignment cmdlets
  (`New`/`Get-OERRoleAssignment`, `New`/`Get`/`Remove-OEREligibleRoleAssignment`,
  `New`/`Get`/`Remove-OERActiveRoleAssignment`, `Enable`/`Disable-OEREligibleRoleAssignment`) now
  accept `-Subscription -ResourceGroup -ResourceType -ResourceName` (bound from the pipeline by
  property name) to target a single resource, so a `Get-OERResource` object pipes straight into them
  (e.g. `Get-OERResource -Subscription Prod -ResourceGroup rg-app -Name stgfoo | New-OERRoleAssignment
  -Role Reader -Group role_sec_readers`). A raw resource id via `-Scope` continues to work
  everywhere. `Get-OERInventory` is intentionally unchanged.

- `Get-OERAccessReviewDefinition -All`: unfiltered, paged list-all mode (default page size 100,
  follows `@odata.nextLink`) that returns every access review definition in the tenant without
  requiring an `-Id`, `-DisplayName`, or `-Filter` selector. The existing `ById`, `ByName`, and
  `ByFilter` parameter sets and the `ByName` default-set behavior are unchanged; `-All` is a new
  fourth parameter set. Output is tagged `Omnicit.EntraRBAC.AccessReviewDefinition` -- identical
  to the per-item path -- so all existing format views and pipeline consumers work unmodified.

- Azure Resource Group support: `New-OERResourceGroup`, `Get-OERResourceGroup`,
  `Set-OERResourceGroup`, and `Remove-OERResourceGroup` manage `Microsoft.Resources/resourceGroups`
  through the ARM wrapper (api-version `2025-04-01`). `New` creates/updates with a required `-Location`
  (immutable) and optional `-Tag`; `Set` replaces the tag set via GET-then-PUT (location preserved);
  `Remove` is `ConfirmImpact = High` with an explicit warning (deleting an RG deletes ALL resources in
  it) and an asynchronous delete. `Get-OERResourceGroup -Subscription <s>` lists or (`-Name`) gets
  resource groups and, with `-IncludeRoleAssignments` (optionally `-ResolveNames`), attaches the
  role-assignment delegations on each resource group -- a light aggregator for every delegation on
  every RG under a subscription. Output is tagged `Omnicit.EntraRBAC.ResourceGroup` (exposing
  `SubscriptionId` + `ResourceGroup`). All Azure RBAC and PIM cmdlets that take `-ResourceGroup` now
  bind it from the pipeline by property name (and `Get`/`Set-OERRoleManagementPolicy` likewise bind
  `-Subscription`), so a resource group object pipes straight into them (e.g.
  `Get-OERResourceGroup -Subscription Prod -Name rg-net | New-OERRoleAssignment -Role Reader -Group
  role_sec_readers`). `Get-OERInventory` is intentionally unchanged (no resource groups).

- Friendly integer duration parameters on the Azure PIM assignment-lifetime cmdlets:
  `-DurationDays` on `New-OEREligibleRoleAssignment` and `New-OERActiveRoleAssignment`, and
  `-DurationHours` on `Enable-OEREligibleRoleAssignment` (default 8 hours). The private
  `ConvertTo-OERDuration` gains a `-Hours` parameter set so a single helper owns both day -> ISO
  (`P{n}D`) and hour -> ISO (`PT{n}H`) encoding. The raw ISO `-Duration` remains as a mutually
  exclusive escape hatch (supplying both raises a non-terminating `AmbiguousDuration` error).
- `Get-OERInventory` now emits a COMPLETE, re-appliable desired-state document (round-trip fidelity):
  access packages carry `resourceRoles` (via `Get-OERAccessPackageResourceRole`) and assignment-policy
  internals (`requestorScope`, `approvalStages` with `durationDays`/`manager`, `durationInDays`);
  Azure role assignments and group PIM eligibility principals are emitted as NAMES by default (role
  names, principal display names / UPNs; ids still available under `-IncludeId`), with eligibility and
  reviewer ids batch-resolved through the new private `Resolve-OERPrincipalName`
  (`POST /directoryObjects/getByIds`); access reviews now carry `accessPackage`, `assignmentPolicy`,
  `reviewers`, and `recurrence` so a NEW review round-trips. A role assignment may carry an optional
  `principalType` (`User`/`Group`/`ServicePrincipal`); it is emitted for service principals so they
  round-trip.
- `Test-OERStructureSchema` validates the new optional assignment-policy fields (`requestorScope.scope`,
  `approvalStages[].durationDays`, `durationInDays`) and an optional `roleAssignment.principalType`
  enum (`User`/`Group`/`ServicePrincipal`). A displayName-only policy stays valid.

- A curated common-role set (Reader, Contributor, Owner, User Access Administrator, Role Based Access
  Control Administrator) defined once in the private `Get-OERCommonRoleName` helper and shared by a
  new `-Role` argument completer and a `-CommonRoles` switch, so the two cannot drift. The completer
  (registered in the module loader, additive -- free-text role names and GUIDs are still accepted)
  offers the curated set on `-Role` for `Get-OERRoleManagementPolicy` and `Get-OERRoleDefinition`.
- `Get-OERRoleManagementPolicy` and the `Get-OERInventory` RoleManagementPolicies section gain
  `-CommonRoles` (read the curated set -- 5 targeted policy reads at the scope; a role with no policy
  is skipped with a warning) and `-AllRolesAtScope` (read the policy for every role at the scope from
  a single `roleManagementPolicyAssignments` list-for-scope call -- the list already carries each
  role's policy and effective rules, so it is one paged ARM list rather than one lookup per role).
  Both are mutually exclusive with an explicit `-Role`. `Get-OERRoleAssignment` is intentionally NOT
  given these switches because it already lists every assignment at a scope regardless of role.

- `Test-OERStructure` and `Invoke-OERStructure` -- the apply half of Phase 5 (JSON Orchestration),
  completing the module roadmap. `Test-OERStructure -Path|-Json` validates an orchestration document
  OFFLINE (no tenant call, no auth) against the schema, returning a tagged
  `Omnicit.EntraRBAC.StructureValidation` whose `Errors` point at each offending node.
  `Invoke-OERStructure -Path|-Json` is an idempotent, dependency-ordered apply engine over the
  existing OER cmdlets (groups -> administrative units -> catalogs -> access packages -> access
  reviews -> Azure role assignments -> Azure PIM policies). It upserts declared state
  (Created/Updated/Unchanged), reports undeclared children as Extra, and -- only with the opt-in
  `-Prune` switch -- removes undeclared CHILDREN of declared parents (Removed; never whole top-level
  objects). `-WhatIf` returns the full plan and writes nothing; each item yields one
  `Omnicit.EntraRBAC.StructureResult` (`Section`, `Item`, `Action`, `Detail`, `Error`). A failed
  item never aborts the run. `StructureResult` and `StructureValidation` format views are registered,
  and `docs/examples/example-structure.json` ships as a worked example.

- `Get-OERInventory` -- read-only export of a tenant's RBAC building blocks (Groups,
  AdministrativeUnits, Catalogs, AccessPackages, AccessReviews, RoleAssignments,
  RoleManagementPolicies) into a serializable Omnicit.EntraRBAC.Inventory object that matches the
  Phase 5 JSON document schema (first half of Phase 5: JSON Orchestration).

- Phase 4b-2 (Azure PIM -- policy engine): `Get-OERRoleManagementPolicy` and
  `Set-OERRoleManagementPolicy` read and update the Azure resource role management policies
  (`roleManagementPolicies`, ARM api-version `2020-10-01`) that govern how PIM activation and
  eligibility behave -- activation window, MFA / justification / ticket on activation, approval and
  approvers, authentication context, eligible and active permanence plus max durations, and
  notifications. The policy is identified by `-Role` plus a scope
  (`-Scope`/`-Subscription`/`-ResourceGroup`/`-ManagementGroup`) or directly by `-PolicyId`
  (pipeline from `Get-OERRoleManagementPolicy`). Every requirement toggle is a `[bool]` so a policy
  can be tightened or relaxed; updates are a per-rule read-modify-write that PATCHes only the changed
  rules (the ARM list-for-scope endpoint has no `$filter`, so the role's policy is matched
  client-side on `roleDefinitionId`). The `New-OERPolicyNotificationRule` builder constructs
  notification changes for `Set-OERRoleManagementPolicy -NotificationRule`. Setting
  `-AllowPermanentEligibility $true` (or raising `-EligibleDuration`) is what lets
  `New-OEREligibleRoleAssignment -Permanent` succeed against a policy that otherwise forbids it.
  The full rules set is sent on update (ARM rejects a partial array on a default policy), each rule
  is add-or-set so a default policy's omitted optional fields are tolerated, and the mutually
  exclusive MFA-on-activation and authentication-context settings are reconciled automatically
  (enabling `-AuthenticationContextId` clears the MFA requirement; `-RequireMfaOnActivation $true`
  disables the authentication context).

- Phase 4b-1 (Azure PIM -- assignment lifecycle): public cmdlets for managing eligible and active
  Azure resource role assignments through the ARM Privileged Identity Management schedule-request
  APIs (api-version `2020-10-01`, GA). `New-OEREligibleRoleAssignment` /
  `Remove-OEREligibleRoleAssignment` grant and revoke eligibilities (`roleEligibilityScheduleRequests`,
  requestType AdminAssign/AdminRemove); `New-OERActiveRoleAssignment` /
  `Remove-OERActiveRoleAssignment` grant and revoke time-bound active assignments
  (`roleAssignmentScheduleRequests`); `Enable-OEREligibleRoleAssignment` /
  `Disable-OEREligibleRoleAssignment` self-activate and self-deactivate the caller's own
  eligibilities (SelfActivate with `linkedRoleEligibilityScheduleId` / SelfDeactivate); and
  `Get-OEREligibleRoleAssignment` / `Get-OERActiveRoleAssignment` read current eligibilities and
  active assignments (`roleEligibilitySchedules` / `roleAssignmentSchedules`, with
  `atScope()` / `principalId eq` / `asTarget()` filters). All accept friendly
  `-User`/`-Group`/`-ServicePrincipal`, `-Role` (name/GUID/full id), and scope
  (`-Scope`/`-Subscription`/`-ResourceGroup`/`-ManagementGroup`) parameters with pipeline support;
  schedules are built from `-Duration`/`-EndDateTime`/`-Permanent`; friendly principal/role/scope
  display names come directly from the API's `expandedProperties`. Removal and deactivation cmdlets
  are ConfirmImpact High with a warning. Reuses the Phase 4a ARM foundation
  (`Invoke-OERArmRequest` direct-bearer transport, `Resolve-OERScope`,
  `Resolve-OERRoleDefinitionId`, `Resolve-OERPrincipal`); no new Graph scope is required.
  PIM policy configuration (`roleManagementPolicies` read/update) is deferred to Phase 4b-2.
- Private Azure PIM helpers: `New-OERScheduleInfo` (builds the ARM `scheduleInfo`/`expiration`
  block, AfterDuration/AfterDateTime/NoExpiration), and the converters
  `ConvertTo-OERRoleScheduleRequest`, `ConvertTo-OEREligibleRoleAssignment`, and
  `ConvertTo-OERActiveRoleAssignment` (with pipeline-alias id properties and format views).
- `Get-OERRoleAssignment -ResolveNames` enriches each result with `PrincipalDisplayName`
  (resolved from `PrincipalId` via Microsoft Graph) and `RoleName` (resolved from
  `RoleDefinitionId` via ARM), and tags the output `Omnicit.EntraRBAC.RoleAssignmentResolved`
  so the default table shows the friendly names instead of the raw ids. All id properties are
  retained, lookups are cached per invocation, and an unresolvable principal or role falls back
  to its id.
- Phase 4a (Azure Resources -- inventory + RBAC): public cmdlets `Get-OERManagementGroup`,
  `Get-OERSubscription`, `Get-OERRoleDefinition`, `Get-OERRoleAssignment`,
  `New-OERRoleAssignment` (friendly `-User`/`-Group`/`-ServicePrincipal` and
  `-Role` name-or-GUID-or-id parameters; `principalType` always sent), and
  `Remove-OERRoleAssignment` (ConfirmImpact High, full-resource-id pipeline input).
- Private ARM foundation: `Invoke-OERArmRequest` (single wrapper over Az.Accounts'
  `Invoke-AzRestMethod` with pinned api-versions, nextLink/@nextLink paging, 401
  re-auth retry, and `-WhatIf:$false -Confirm:$false` inner calls),
  `Convert-ArmHttpException`, `Resolve-OERScope`, `Resolve-OERRoleDefinitionId`,
  `Resolve-OERPrincipal`, and converters for ManagementGroup / Subscription /
  RoleDefinition / RoleAssignment with pipeline-alias properties.
- Private helpers `Resolve-OERUserId` (user principal name or id to object id) and
  `Resolve-OERTargetList` (resolves `-User`/`-Group` arrays into Graph approver objects with lazy
  auth), and a GUID short-circuit on `Resolve-OERGroupId -DisplayName`.
- `Get-OERAccessPackageResourceRole` -- lists the resource role bindings configured on an access
  package (accessPackages/{id}?$expand=resourceRoleScopes($expand=role,scope)), tagged
  Omnicit.EntraRBAC.AccessPackageResourceRole and exposing ResourceRoleScopeId so it pipes into
  Remove-OERAccessPackageResourceRole.
- `Get-OERGroupMember` -- lists a group's direct members (or owners with -Owners) as tagged
  Omnicit.EntraRBAC.GroupMember objects.
- `Get-OERGroupEligibility` -- lists a group's current PIM-for-groups eligible assignments as tagged
  Omnicit.EntraRBAC.GroupEligibilitySchedule objects (AccessType, MemberType, and the start/end
  window from the schedule instance; reuses Get-OERGroup -IncludePimEligibility, so a group not
  onboarded to PIM for Groups simply returns nothing).

- `Export-OERInventory`: reads a tenant's RBAC posture into a self-contained bundle (canonical
  `inventory.json`, per-area JSON, read-only `scopeHierarchy.json` / `groupsRoster.json`, a formal
  JSON Schema `schema.json`, a predefined LLM prompt, and a README) for the inventory -> LLM ->
  apply workflow. Walks every management group and subscription for role assignments (and, when
  requested, PIM policies), keeps only RBAC-relevant groups in detail, and self-checks
  `inventory.json` against the apply schema. The bundled `schema.json` (draft-07, mirrors
  `Test-OERStructureSchema`) lets a consumer validate a proposal without the module. See
  `docs/inventory-to-llm/README.md`.

### Changed

- `Invoke-OERStructure` now UPDATES an existing access review definition instead of always reporting
  `Unchanged`. Declared fields are diffed against the live definition and only the differences are sent
  to the read-modify-write `Set-OERAccessReviewDefinition`; reviewer tokens are resolved to object ids
  before the comparison so a tenant display-name change is not mistaken for drift
  (`G-ar-sync-create-only-no-update`, `G-accessreview-no-update-on-existing`). The review scope
  (`accessPackage` / `assignmentPolicy`) is immutable on an existing definition and a declared change
  there is reported as a `Skipped` record with a warning. `reviewers` and `fallbackReviewers` are
  diffed independently, the same presence rule as the PIM policy approvers above: Microsoft Graph
  rebuilds both arrays whenever any reviewer parameter is bound, so declaring only one of them carries
  the other forward from the live definition instead of clearing it. The recurrence range is preserved
  the same way -- a document that only changes the cadence or the start date keeps a live `endDate` or
  occurrence count instead of resetting it to never-ending -- and a `OneTime` review, which has no
  range to diff, is compared on cadence alone, so declaring a `startDate` on one no longer produces a
  write on every apply.
- `Test-OERStructureSchema` reports an unknown per-item key in the `roleAssignments` and
  `roleManagementPolicies` sections as a Warning naming the key, so a field the apply engine cannot
  honour is visible instead of silently dropped (`G-schema-silently-accepts-unsupported-policy-fields`).
  Validation still succeeds -- the finding is Warning severity, never Error.

- `CLAUDE.md` no longer documents a `source/Classes` directory of `IArgumentCompleter` classes, which
  does not exist. It now describes the real mechanism -- `Register-ArgumentCompleter` scriptblocks in
  `source/suffix.ps1`, mirrored in the dev-mode psm1, backed by private `Resolve-*Completion` helpers --
  and the rules for adding one (`E-stale-classes-dir-doc`). Documentation only; no behaviour changed.

- The `-PrincipalId` GUID guard plus `Resolve-OERPrincipal` fan-out that was copy-pasted across six
  PIM cmdlets is now a single private helper, `Resolve-OERPrincipalOrId`, which returns either a
  resolved principal or a routable failure descriptor instead of throwing.
  `Enable`/`Disable-OEREligibleRoleAssignment`, `Remove-OEREligibleRoleAssignment`,
  `Remove-OERActiveRoleAssignment` and `Add`/`Remove-OERGroupEligibility` all route through it, so
  the guard, the error ids and the wording stay in sync (`I-principal-or-id-guard-duplicated`).
  Error ids, categories, control flow and every request body are unchanged on the four Azure PIM
  cmdlets (`Enable`/`Disable-OEREligibleRoleAssignment`, `Remove-OEREligibleRoleAssignment`,
  `Remove-OERActiveRoleAssignment`): a raw object id supplied alongside a friendly parameter still
  wins -- as it always did -- and now also emits a warning naming the parameter it is overriding
  instead of silently discarding it. On `Add`/`Remove-OERGroupEligibility` this is a genuine
  behavior change: previously a raw `-PrincipalId` supplied together with a friendly parameter was
  a hard, non-terminating `AmbiguousPrincipal` error; it is now id-wins plus the same warning --
  except on `Remove-OERGroupEligibility` when objects are piped in (its `-PrincipalId` is
  pipeline-bound), where supplying a friendly parameter alongside piped input remains a hard
  `AmbiguousPrincipal` error, because the named principal would otherwise be silently ignored for
  every piped item. One further deliberate refinement: the friendly-parameter list is now spelled
  the same way in all four guard messages (previously the `InvalidPrincipalId` message used an
  Oxford comma and its neighbours did not).

- `ConvertTo-OERAssignmentPolicy`, `Get-OERInventory`, `Invoke-OERStructure`, and the embedded
  `schema.json` all gain full granular AP assignment policy support, closing the v1.1 approver gap.
  `ConvertTo-OERAssignmentPolicy` now reads and normalises the complete policy: requestor scope
  (specific user/group ids), requestor settings (self/manager request, manager level, custom schedule,
  self-extend), approval toggles (requireApproval, requireRequestorJustification,
  requireApprovalForUpdate), per-stage approver details (users, groups, manager + level,
  internal/external sponsors, alternate users/groups, escalation days, requireApproverJustification,
  approverInfoVisibility), expiration in hours or as a date-time, and the notification-disabled flag.
  `Get-OERInventory` projects all the above fields so policies round-trip through the inventory->LLM->apply
  loop. `Invoke-OERStructure` diffs the FULL policy: the handler builds the desired policy body from
  every declared field, projects it identically to the live read, and compares over only the declared
  fields. A fully-declared, matching policy round-trips to `Unchanged`; any declared field that differs
  reports `Updated` (with the changed field names) and calls `Set-OERAccessPackageAssignmentPolicy`
  with the declared sub-objects/scalars. An absent policy is created from the same desired parts. The
  legacy flat shape (`requestorScope.scope` + `approvalStages{durationDays,manager}` + `durationInDays`)
  keeps working, and the back-compat Tenant Profile `PrimaryApprovers`/`EscalationApprovers` fallback
  is retained for a stage that declares no manager and no explicit approvers.

- `Add-OERGroupEligibility` and `Remove-OERGroupEligibility` now take a single `-Group`
  parameter (display name or object id, resolved via `Resolve-OERGroupId`) and accept a user
  principal via `-User` (UPN or object id). A principal group or service principal is still
  supplied via `-PrincipalId` (GUID); a non-GUID `-PrincipalId` now returns an actionable
  `InvalidPrincipalId` error pointing to `-User`. The legacy `-Id`/`-DisplayName`/`-PrincipalId`
  parameters and pipe-from-`Get-OERGroup` continue to work via aliases. `Remove-OERGroupEligibility`
  additionally binds `-PrincipalId` and `-AccessType` from the pipeline by property name, so
  `Get-OERGroupEligibility | Remove-OERGroupEligibility` revokes the exact eligibility (group,
  principal, and member/owner access) that was read.
- `Get-OERGroupPimPolicy` and `Set-OERGroupPimPolicy` now take a single `-Group` parameter
  (display name or object id) in place of `-Id`/`-DisplayName`, fixing the case where `-Group`
  previously prefix-matched the `GroupId` alias and bound verbatim. The legacy `-Id`/`-DisplayName`
  parameters still bind via aliases.
- `Set-OERGroupPimPolicy` no longer emits a result object under `-WhatIf` (or when every rule is
  declined under `-Confirm`). Previously it returned a summary object with `Applied = true` even
  though no rule was patched, which was misleading; it now reports a summary only for runs that
  actually patched at least one rule, matching `Set-OERRoleManagementPolicy`.

- `New-OEREligibleRoleAssignment`, `New-OERActiveRoleAssignment`, and `Add-OERGroupEligibility` now
  self-heal the governing PIM policy when a permanent grant is requested: if the policy forbids
  permanent assignment they open it first (idempotently, with a loud warning and a separate
  -WhatIf/-Confirm-gated action) before granting. Opening the policy can be declined (-Confirm) or
  fail for lack of policy-write permission, in which case a `PolicyOpenFailed` error is returned and
  no grant is made. A permanent group eligibility on a not-yet-onboarded group returns
  `GroupNotOnboarded` (onboard time-bound first).

- `Get-OERInventory -Include AccessReviews` now lists ALL definitions when `-AccessReviewFilter`
  is omitted (previously it warned and skipped the section entirely). When supplied,
  `-AccessReviewFilter` is now a display-name pattern (wildcards supported, e.g. `AR*`) matched
  CLIENT-SIDE over the full list -- the accessReviews endpoint does not reliably support server-side
  name filtering. A read failure on the access-review endpoint (e.g. 429 throttle or 403 permission
  gap) issues a non-terminating warning and continues the inventory run rather than aborting it.

- `Get-OERAccessReviewDefinition -DisplayName` now matches CLIENT-SIDE over the full (paged) list and
  supports wildcards (e.g. `AR*`, `*demo*`), because the accessReviews definitions endpoint silently
  ignores unsupported server-side `$filter` expressions (such as `startswith(displayName,...)`) and
  returns the whole collection. `-Filter` is retained for the one server-side form the endpoint does
  honor -- `contains(scope/microsoft.graph.accessReviewQueryScope/query, '...')` -- and its help now
  documents that other expressions are ignored by the service.

- All day -> ISO 8601 duration encoding now routes through the private `ConvertTo-OERDuration`
  helper (it is the single owner of whole-unit int -> ISO encoding). The previous inline
  `[System.Xml.XmlConvert]::ToString([timespan]::FromDays(...))` conversions in
  `New-OERAccessPackageApprovalStage` (`-DurationDays`/`-EscalationDays`) and the private
  `ConvertTo-OERPolicyBody` (`-DurationInDays`) were removed in favour of the helper; emitted
  durations are unchanged.
- `Invoke-OERStructure` now UPSERTS access package assignment policies: an existing policy whose
  declared `requestorScope.scope` / `durationInDays` / `approvalStages` (count, per-stage
  `durationDays` and `manager`) differ from the tenant is updated via
  `Set-OERAccessPackageAssignmentPolicy` (reported `Updated`); a match is `Unchanged`. Explicit
  per-approver IDENTITIES are NOT diffed -- the rebuilt body's approvers come from the `manager` flag
  or the Tenant Profile `PrimaryApprovers`/`EscalationApprovers` defaults (a deliberate v1.1 gap).
  `roleAssignments` honour an optional `principalType` to assign a service principal (or to force a
  user/group); when absent the `@`-heuristic is kept. Access review definitions remain
  create-or-exists -- the CREATE path is now fully round-trippable, but an EXISTING review is reported
  `Unchanged` (access-review update is a documented v1.1 gap: throttling + unsafe idempotent update).
- The Entitlement Management `Set-`/`Remove-OER*` cmdlets (catalog, catalog resource, access
  package, assignment policy, assignment) now accept their identifier from the pipeline by property
  name, so `Get-OER* | Remove-OER*` / `Set-OER*` works (mirroring the Administrative Unit cmdlets).
  Where the parameter is not named `Id` (`-ResourceId`, `-AssignmentId`) an `Id` alias binds the
  piped object's `Id` property.
- `New-OERAccessPackageRequestorScope` and `New-OERAccessPackageApprovalStage` now take friendly
  `-User`/`-Group` array parameters (and, for approval stages, `-Manager`/`-ManagerLevel`/
  `-InternalSponsor`/`-ExternalSponsor` switches plus `-AlternateUser`/`-AlternateGroup`), replacing
  the previous `-AllowedRequestor`/`-Approver`/`-AlternateApprover` hashtable parameters. Each
  `-User`/`-Group` value is either a name (user principal name or group display name) or an object id
  (GUID); names are resolved to ids with lazy authentication (a pure-GUID input performs no Graph
  call).

### Fixed

- `Set-OERRoleAssignment -Condition ''` now clears an ABAC condition by OMITTING `condition` and
  `conditionVersion` from the PUT body, instead of sending them as empty strings. Azure Resource
  Manager rejects an empty version outright -- `InvalidCreateOrUpdateRoleAssignmentRequest: The
  specified role assignment ConditionVersion '' is not supported` -- even though the REST documentation
  states that either an empty string or null clears it. Since the PUT replaces the whole property bag,
  omitting both keys is what actually removes the condition, and it is the same body shape
  `New-OERRoleAssignment` sends when no condition is supplied. Found by live testing; the mocked suite
  had encoded the documented-but-rejected shape.
- `Set-OERAdministrativeUnit -Visibility Public` now sends the JSON `null` that Microsoft Graph
  documents as a public unit, instead of the literal string `Public`, which is not a REST value. This
  makes reverting a HiddenMembership unit to public actually work.
- `Invoke-OERStructure` now APPLIES administrative unit `dynamic` and `hiddenMembership` drift, and
  Azure role assignment `condition`/`conditionVersion`/`description` drift, on existing objects instead
  of reporting a `Skipped` record. The role assignment path no longer advises Remove-then-New, which
  briefly revoked a high-privilege grant. `restricted` (isMemberManagementRestricted) is genuinely
  immutable on Graph and is still reported as `Skipped`. The role assignment edit is confined to the
  scope the document declares (see the scope-safety entry below), and a `dynamic` conversion no longer
  drags a doomed member reconciliation behind it (see the dynamic-membership entry below).
- `Invoke-OERStructure` only edits a role assignment DEFINED at the declared scope. The at-scope read
  uses ARM's `atScope()` filter, which also returns assignments inherited from ANCESTOR scopes, and the
  existing-assignment match was on principal + role definition alone. Now that the match feeds a real
  `Set-OERRoleAssignment` PUT, a document entry for `/subscriptions/s/resourceGroups/rg` whose grant is
  actually defined at `/subscriptions/s` would have rewritten the SUBSCRIPTION-level ABAC condition --
  widening or narrowing access far beyond the declared scope -- and reported `Updated` against the
  resource group. An ancestor-owned match is now written in neither direction: it is not edited (that
  would change the ancestor's grant) and it is not duplicated at the child scope (Azure Resource
  Manager would accept the create, since uniqueness is per scope + principal + role, but the extra
  grant would outlive removal of the ancestor one). It is reported as a visible `Skipped` record naming
  the ancestor scope and assignment id, with a warning, instead of a misleading `Updated` or a silent
  `Unchanged`. The scope-wide prune pass already used exactly this predicate.
- An explicit JSON `null` is treated as NOT DECLARED by the `Invoke-OERStructure` administrative unit
  and role assignment handlers, matching the offline validator and the Azure PIM policy / access review
  diffs. Both handlers had been reading presence only, which was inert while the drift was reported
  rather than applied and became a destructive write on this release: `"condition": null` cast to `''`
  and CLEARED a live ABAC condition (widening access), `"dynamic": null` cast to `$false` and converted
  a live dynamic unit to Assigned, `"hiddenMembership": null` reverted a hidden unit to public, and
  `"description": null` wiped a description. `Get-OERInventoryPromptTemplate` instructs the proposal
  model that "an explicit null means the SAME as omitting the key", so a model following that
  instruction was the likely author of exactly those documents. An explicitly empty ARRAY is unchanged:
  `"members": []` still means "no members declared", which is what `-Prune` removes against.
- `Invoke-OERStructure` no longer tries to manage the members of a DYNAMIC administrative unit.
  Microsoft Graph disables manual member management on a dynamic unit -- the rule for dynamic membership
  groups retains sole ownership of adding and removing members -- and switching a unit to dynamic can
  change its existing membership on its own, which also invalidated the member list the handler had read
  before the conversion PATCH. Declared members were therefore diffed against a stale list, reported
  `Unchanged` for members Graph had just dropped, and fed `Add-OERAdministrativeUnitMember` (and, with
  `-Prune`, `Remove-OERAdministrativeUnitMember`) calls Graph rejects -- and `Get-OERInventory` emits
  `members[]` for every unit including dynamic ones, so a round-tripped document always supplied that
  list. Each declared member is now reported as a visible `Skipped` record explaining that the
  membership rule owns the membership, the Extra/prune pass does not run, and a unit with a live
  membership but no declared members gets one summary `Skipped` record so the inaction is visible under
  `-Prune` too. This covers a unit that was ALREADY dynamic (a pre-existing bug) as well as one the run
  just converted. Scoped roles are unaffected -- only member management is disabled -- and are still
  reconciled on either kind of unit. A conversion in the other direction (Dynamic to Assigned) re-reads
  the member list after the PATCH before reconciling it.
- The `Invoke-OERStructure` administrative unit handler drops the force-carried membership rule keys
  when it abandons a conversion to Dynamic for want of a rule. It removed only `MembershipType`, so a
  document declaring `membershipRuleProcessingState` without `membershipRule` still PATCHed that
  processing state onto a unit that stayed Assigned (where it is meaningless) and reported `Updated`
  next to the `Failed`.
- `ConvertTo-OERRoleScheduleRequest` keeps `TicketNumber`/`TicketSystem` null when the request carries a
  `ticketInfo` object whose fields are null, instead of projecting empty strings, matching the
  null-preserving `Justification`/`Condition`/`ConditionVersion` fields beside them.
- Documentation corrected for the in-place update paths: the `Get-OERInventoryPromptTemplate`
  `roleAssignments[]` contract no longer tells the proposal model that the engine "reports drift on them
  instead of updating in place" (it now describes the in-place update, the defining-scope rule and the
  `""`-not-null way to remove a condition), the `administrativeUnits[]` contract states that `members[]`
  is only reconciled on an assigned unit, the `Test-OERStructureSchema` finding for `dynamic` without
  `membershipRule` no longer claims the unit "would be created with an empty rule" (it names the real
  outcome -- a create is rejected and a conversion is reported `Failed` -- and stays a Warning, because
  an already-dynamic unit whose rule is managed outside the document does apply cleanly and an Error
  would abort the whole document), and `Get-OERRoleAssignment` / `ConvertTo-OERRoleAssignment` mention
  that their output also pipes into `Set-OERRoleAssignment`.
- The PIM readers (`Get-OEREligibleRoleAssignment`, `Get-OERActiveRoleAssignment`, and the schedule
  request objects) now expose `Condition`/`ConditionVersion`, and the schedule request additionally
  exposes `TicketNumber`/`TicketSystem`. These were write-only before, so an ABAC condition set on an
  eligibility could not be read back.
- `Set-OERRoleAssignment` carries `delegatedManagedIdentityResourceId` forward from the live
  assignment. Azure Resource Manager replaces the whole property bag on an edit, so omitting it would
  have silently destroyed an Azure Lighthouse / cross-tenant delegation on an otherwise harmless
  description edit.

- An explicit JSON `null` in an apply document is now treated as NOT DECLARED by the Azure PIM policy
  and access review diffs, exactly as the offline validator already treated it. The two layers had
  disagreed, so `"authenticationContextId": null` disabled a live conditional-access authentication
  context, `"requireMfaOnActivation": null` disabled MFA on activation, and `"mailNotification": null`
  or `"descriptionForAdmins": null` overwrote the live access review settings. An explicit `null` now
  means the same as omitting the key -- leave the live setting untouched -- while an empty string
  remains the documented "disable the authentication context" value.
- An access review whose document declares `"reviewers": null` is no longer silently converted into a
  self-review with its fallback reviewers wiped. The `Invoke-OERStructure` access review update path
  gated on the key being present, not on it carrying a value, so an explicit null resolved to an empty
  reviewer list and took the empty-list-means-self-review branch --  and because
  `Set-OERAccessReviewDefinition` rebuilds both reviewer arrays whenever any reviewer parameter binds,
  the live reviewers and fallbacks were both replaced. An explicit null on `reviewers` or
  `fallbackReviewers` now means the same as omitting the key (leave that half alone); an explicitly
  empty list still means a self review.
- `Invoke-OERStructure` no longer re-enables PIM approval on a policy whose document says
  `"requireApproval": false`. Azure Resource Manager sets `isApprovalRequired = true` unconditionally
  whenever approvers are written, so a document declaring `requireApproval: false` together with an
  `approvers` block silently turned approval ON. The approvers are now dropped in favour of the
  explicit `requireApproval: false`, the drop is named in the result detail, and
  `Test-OERStructure` reports the combination as a Warning up front. `Get-OERInventory` could produce
  exactly that document, since the read projects `primaryApprovers` regardless of `isApprovalRequired`.
- `Set-OERAccessReviewDefinition` carries the live `instanceEnumerationScope` and
  `additionalNotificationRecipients` forward into its full-replace PUT, so the access review update
  path (reachable from `Invoke-OERStructure` since existing reviews became reconcilable) no longer
  clears the two writable top-level properties the module does not model. The carry-forward is by
  name, never a blanket copy, so read-only properties are still never sent back.
- `Get-OERInventory` omits `requireMfaOnActivation` from a role management policy projection that
  carries an `authenticationContextId`. Azure PIM treats the two as mutually exclusive and the offline
  validator rejects a document declaring both, so a live policy with an enabled authentication context
  and MFA on activation previously produced an inventory that failed its own validation and the
  `Export-OERInventory` schema self-check.

- An administrative unit scoped role whose directory role name could not be resolved (the role map is
  best-effort and covers activated roles only) no longer round-trips as `role: null`.
  `Get-OERInventory` falls back to the role id, and `Invoke-OERStructure` passes a GUID role through
  `Add-OERAdministrativeUnitScopedRole -RoleId` and matches it against the live membership `RoleId`
  (`G-au-scopedrole-null-rolename-breaks-roundtrip`).

- A time-bound PIM-for-groups eligibility no longer degrades to permanent, and an owner eligibility is
  no longer lost, on an inventory-to-apply round-trip
  (`G-group-eligibility-durationdays-not-inventoried`, `G-eligibility-accesstype-not-in-schema-or-sync`).
- `Invoke-OERStructure` reconciles eligibility on the (principal, accessType) pair and diffs the
  declared window, so a changed `durationDays` or a member/owner switch is re-applied instead of being
  reported `Unchanged` (`G-sync-eligibility-diff-principalid-only`).
- The inventory `pimPolicy` block is emitted whenever any field is customized, not only when
  `activationMaxHours` parsed (`G-pim-projection-gated-on-activationmaxhours`).
- A dynamic or HiddenMembership administrative unit no longer degrades to static/public on apply;
  immutable drift and the unsupported HiddenMembership-to-public transition are reported as `Skipped`
  with a warning (`G-au-dynamic-visibility-not-roundtrippable`).
- A hidden access package no longer becomes visible through the apply loop
  (`G-ap-ishidden-no-apply-path`).
- `Set-OERAccessPackageAssignmentPolicy` no longer rewrites a live policy description to its display
  name when `-Description` is omitted (`G-set-policy-description-overlay-not-preserved`).
- A live `SpecificDirectoryUsers` requestor scope is no longer reset to `AllMemberUsers` when an apply
  document changes an unrelated policy field (`G-requestorscope-specific-targets-clobber-on-scope-change`).
- Azure role assignment ABAC `condition`, `conditionVersion` and `description` are written on create
  and their drift on an existing assignment is surfaced instead of being reported `Unchanged`
  (`G-roleassignment-condition-description-dropped`).

- A `manager` access-review reviewer now requires (and round-trips) a fallback reviewer. Microsoft
  Graph rejects an access review whose reviewers include the manager scope but whose
  `fallbackReviewers` is empty -- with the same opaque `Policy is invalid due to invalid criteria`
  error. `New-OERAccessReviewDefinition` now fails fast with a clear `ManagerFallbackRequired` error
  when `-Manager` is used without `-FallbackReviewer`/`-FallbackReviewerGroup`. The orchestration
  document gains an optional `fallbackReviewers` array on accessReviews entries (UPN -> user, other ->
  group); `Invoke-OERStructure` maps it through and reports a clear `Failed` (instead of the opaque
  Graph error) when a manager review declares no fallback. `Get-OERInventory` projects
  `fallbackReviewers` and `ConvertTo-OERAccessReviewDefinition` surfaces `FallbackReviewers`, so a
  manager-based access review captured from a tenant re-applies cleanly. The shipped
  `docs/examples/example-structure.json` review now declares a `fallbackReviewers` entry.
- Access review creation (`New-OERAccessReviewDefinition`, and therefore `Invoke-OERStructure`'s
  accessReviews section) no longer fails with `BadRequest: Policy is invalid due to invalid criteria`.
  The access-package scope query targeted the beta collection name
  `/identityGovernance/entitlementManagement/accessPackageAssignments` with scalar
  `accessPackageId`/`assignmentPolicyId`/`catalogId` filter properties, which do not exist on v1.0
  (a direct GET returns `Resource not found for the segment 'accessPackageAssignments'`), so the
  access review service rejected the stored query. The scope query now uses the v1.0 `assignments`
  collection with a relationship filter (`accessPackage/id eq '..' and assignmentPolicy/id eq '..'`);
  the package id pins the scope, so the catalog id is no longer part of the filter.
  `ConvertTo-OERAccessReviewDefinition` parses both the new relationship form and the legacy scalar
  form so reviews created before this fix still round-trip. (Surfaced by live testing; access review
  creation was never confirmed end-to-end in Phase 3b because live tests were blocked by 403/429.)
- `Invoke-OERStructure` no longer reports inherited Azure role assignments as `Extra`. The scope-wide
  reconcile pass reads `atScope()` (which returns assignments at AND above the scope), but it only knew
  the assignments declared at that exact scope -- so an assignment inherited from a parent management
  group (which a round-trip document declares under the ancestor scope, and which cannot be removed at
  the child scope anyway) was flagged as an undeclared extra at every descendant. The pass now
  considers only assignments DEFINED at the reconcile scope (`assignment.Scope == scope`), and each
  genuine extra now carries its own identity (`role -> principal @ scope`) in the result `Item` instead
  of repeating the triggering declared item's label (which made distinct extras look like duplicates).
- Principal/object lookups (`Resolve-OERUserId`, `Resolve-OERGroupId`, `Resolve-OERApplicationId`)
  now percent-encode the OData `$filter` value, so guest (B2B) users resolve. A guest user principal
  name carries the `#EXT#` marker, and the unencoded `#` is a URL fragment delimiter -- everything
  after it was dropped before the request reached Graph, producing
  `BadRequest: Invalid filter clause: There is an unterminated string literal`. The value is now
  doubled-quoted (OData) and then `[uri]::EscapeDataString`-encoded (`#` -> `%23`, etc.), which also
  hardens display-name lookups against `&`, `+`, and spaces. (Surfaced by `Invoke-OERStructure`
  resolving guest members on a real tenant.)
- `Get-OERInventory` access-package `resourceRoles` now project the resource's real display name
  instead of the scope label. The binding's scope display name is commonly `Root` (the whole-resource
  scope), not the resource name, so `Invoke-OERStructure` could not resolve the resource
  (`could not resolve resource 'Root' to an origin id`) and reported the live binding as Extra. The
  export now joins each binding's `OriginId` to the catalog resource set (the same source the apply
  engine resolves against) to recover the resource name, falling back to the scope label only when no
  catalog resource matches.
- `Get-OERInventory` no longer projects a `pimPolicy` for a group whose policy has no activation
  duration (null `ActivationMaxHours`). A group that is not truly PIM-onboarded still returns a policy
  object with a null activation max; emitting it made `Invoke-OERStructure` substitute the 8h default
  and (re-)set a policy the tenant never had -- breaking round-trip idempotency (the group showed
  `would set pimPolicy` instead of `Unchanged`).
- `Get-OERAccessPackageAssignmentPolicy -AccessPackage` used an invalid OData filter
  (`accessPackageId`), which Graph rejected with "Invalid filter clause". It now filters on the
  relationship `accessPackage/id`.
- Assignment policy create/update bodies used the beta-era `accessPackageId` scalar, which is not a
  property of the v1.0 `accessPackageAssignmentPolicy` resource. They now reference the package via
  the `accessPackage` relationship (`accessPackage = @{ id = '<id>' }`). Reads (`Get`, and the
  `Set` cmdlet's lookup of the existing policy's package) now request `$expand=accessPackage` and
  read `accessPackage.id`, so the returned `AccessPackageId` is populated correctly on v1.0.
- Assignment policy approval stages emitted beta-era fields (`approvalStageTimeOutInDays`,
  `escalationTimeInMinutes` as integers) and the policy body emitted `canExtend`, which Graph
  rejected with `InvalidModel` on v1.0. Stages now emit the ISO 8601 durations
  `durationBeforeAutomaticDenial` and `durationBeforeEscalation` plus the required
  `fallbackPrimaryApprovers`/`fallbackEscalationApprovers` arrays, and the invalid `canExtend`
  property (and the corresponding `-CanExtend` parameter on `New`/`Set-OERAccessPackageAssignmentPolicy`)
  has been removed.
- `Get-OERInventory` no longer fails or floods the host on a real tenant. The AdministrativeUnits
  section used the invalid filter `startswith(displayName,'')` (rejected by Graph with
  `Request_UnsupportedQuery`), so no administrative units were captured; it now lists all units via
  the new no-selector mode of `Get-OERAdministrativeUnit`. The Groups section read PIM eligibility
  and the PIM policy for every security group, which made the beta PIM endpoints return 400
  `ResourceTypeNotSupported` (and a warning, or polluted `$Error`) for each group not onboarded to
  PIM for Groups; those expected failures are now treated quietly as "no PIM data".
- `Get-OERAdministrativeUnit` gains a list-all mode: called with no `-Id`, `-DisplayName`, or
  `-Filter`, it returns every administrative unit in the tenant (an empty tenant is not an error).
- `Get-OERGroup -IncludePimEligibility` and `Get-OERGroupPimPolicy` now treat the beta PIM endpoints'
  400 `ResourceTypeNotSupported` (the response for a group not onboarded to PIM for Groups) as
  "no eligibility / no policy" without warning or leaving the error in `$Error`.
- `Resolve-OERCatalogResource -IncludeRoles` (which backs `Add-OERAccessPackageResourceRole`) now
  reads a resource's roles from the catalog's dedicated `resourceRoles` endpoint
  (`catalogs/{id}/resourceRoles?$filter=(originSystem eq '...' and resource/id eq '...')`) instead of
  the resource's `$expand=roles` navigation property. The previous code used the beta-only
  `$expand=accessPackageResourceRoles` (rejected by v1.0 with `BadRequest: Could not find a property
  named 'accessPackageResourceRoles'`); switching to the v1.0 `$expand=roles` removed the 400 but
  that navigation property returns an EMPTY roles collection for role-assignable
  (`isAssignableToRole`) and PIM-managed groups, so binding a group's Member/Owner role through an
  access package still failed with `Role 'Member' not found on resource`. The `resourceRoles`
  endpoint is the authoritative v1.0 method (the one used by Microsoft's own samples) and returns the
  active and PIM-eligible role variants for every supported resource type.
- `Remove-OERCatalogResource` now includes the containing catalog in the `adminRemove`
  `resourceRequest` body and gains a mandatory `-Catalog` parameter (id or display name). The v1.0
  contract requires the `catalog` reference; without it Graph rejected the request with
  `UnAuthorized ... Reason: Unauthorized` even for a Global Administrator (while `adminAdd`, which
  already sent the catalog, succeeded).
- `Get-OERCatalogResource -IncludeRoles` returned no roles: it used the unreliable $expand=roles
  navigation property (empty for role-assignable / PIM-managed groups) and the converter dropped roles
  entirely. It now reads roles from the dedicated catalogs/{id}/resourceRoles endpoint (via the shared
  private Get-OERCatalogResourceRole helper) and surfaces them as a Roles property.
- `Get-OEREligibleRoleAssignment` / `Get-OERActiveRoleAssignment` with -User/-Group/-ServicePrincipal
  returned empty when the principal's assignment was inherited via group membership: the ARM filter now
  uses assignedTo('{id}') (group-transitive) instead of principalId eq '{id}' (direct only).
- `Enable-OEREligibleRoleAssignment`, `Disable-OEREligibleRoleAssignment`,
  `Remove-OEREligibleRoleAssignment`, and `Remove-OERActiveRoleAssignment` now reject a non-GUID
  value passed to `-PrincipalId` with a clear, non-terminating `InvalidPrincipalId` error that
  points to `-User`/`-Group`/`-ServicePrincipal` for name lookups. Previously a UPN or display name
  bound to `-PrincipalId` (PowerShell prefix-matches `-Principal` to `-PrincipalId`) reached ARM as
  a `principalId eq '<name>'` filter and returned a confusing `InvalidFilter` error, or built a
  request against a non-existent principal id. The new private `Test-OERGuid` predicate backs the
  guard and also replaces the duplicate GUID regex in `Resolve-OERPrincipal`. The valid-GUID
  pipe-from-`Get-OER*RoleAssignment` path and the `-User`/`-Group`/`-ServicePrincipal` resolution
  path are unchanged.

- Phase 0 foundation: module scaffold, AzAuth-based `Connect-OER`/`Disconnect-OER`,
  `Invoke-OERGraphRequest`, Tenant Profile configuration CRUD, and the `Resolve-OERName`
  naming engine.
- Phase 1 Groups & PIM: `New`/`Get`/`Set`/`Remove-OERGroup` (static, `-RoleAssignable`, or
  `-Dynamic -MembershipRule`; PIM-for-groups is layered on via `Add-OERGroupEligibility`),
  `Add`/`Remove-OERGroupMember` (member/owner), `Add`/`Remove-OERGroupEligibility` (PIM-for-groups
  onboarding), and `Get`/`Set-OERGroupPimPolicy` (activation template with partial-failure
  reporting). Private helpers `Resolve-OERGroupId`, `ConvertTo-OERGroup`,
  `New-OERGroupEligibilityBody`, `New-OERPimRuleSet`, `Get-OERPimGroupPolicyId`. Format views for
  the new tagged types and the `TenantConfiguration` view.

- `Set-OERGroupPimPolicy` gains `-AllowPermanentEligibility` and `-AllowPermanentActive` switches that
  set `isExpirationRequired = false` on the eligibility / active-assignment rules, so a group can permit
  permanent eligible assignments (after which `Add-OERGroupEligibility` without `-Duration` succeeds).
- Assignment lifetimes are now expressed in whole days instead of ISO 8601: `Add-OERGroupEligibility
  -Duration`, and `Set-OERGroupPimPolicy -EligibleDuration`/`-ActiveDuration`, take an integer day count
  (e.g. `365`) converted internally by the new private `ConvertTo-OERDuration` helper. `-ActivationMaxHours`
  remains in hours.
- `Set-OERGroupPimPolicy -AuthenticationContextId` is now optional; when omitted the
  authentication-context activation rule is disabled (no authentication context required).
- Phase 2 Administrative Units: `New`/`Get`/`Set`/`Remove-OERAdministrativeUnit` (regular,
  `-Restricted` restricted-management, and `-Dynamic -MembershipRule` units; `-HiddenMembership`),
  `Add`/`Remove-OERAdministrativeUnitMember` (users/groups/devices), and
  `Add`/`Get`/`Remove-OERAdministrativeUnitScopedRole` (directory roles scoped to a unit, with
  role-name resolution). `New-OERGroup` gains `-AdministrativeUnit` to create a group directly inside
  a (restricted) unit. Private helpers `Resolve-OERAdministrativeUnitId`, `ConvertTo-OERAdministrativeUnit`,
  `Resolve-OERDirectoryRoleId`, `ConvertTo-OERScopedRoleMember`, the `AdministrativeUnit.ReadWrite.All`
  delegated Graph scope, and format views for the new tagged types.

- Phase 3b Access Reviews (scoped to access packages): access review definitions
  (`New`/`Get`/`Set`/`Remove-OERAccessReviewDefinition`) with single-stage and multi-stage support
  (stage builder `New-OERAccessReviewStage`), review instances (`Get-OERAccessReviewInstance`),
  instance decisions (`Get-OERAccessReviewInstanceDecision`), and admin actions
  (`Stop-OERAccessReviewInstance`, `Invoke-OERAccessReviewInstanceDecision`,
  `Send-OERAccessReviewReminder`). Private helpers `Resolve-OERAccessReviewDefinitionId`,
  `Resolve-OERReviewerScope`, `Resolve-OERAccessReviewScopeQuery`, `Resolve-OERRecurrencePattern`,
  `ConvertTo-OERAccessReviewDefinition`, `ConvertTo-OERAccessReviewInstance`,
  `ConvertTo-OERAccessReviewStage`, `ConvertTo-OERAccessReviewDecision`. Format views for all four
  new tagged types (`AccessReviewDefinition`, `AccessReviewInstance`, `AccessReviewStage`,
  `AccessReviewDecision`).

- Phase 3a Entitlement Management core: catalogs (`New`/`Get`/`Set`/`Remove-OERCatalog`), catalog
  resources -- groups, applications, and SharePoint sites -- (`Add`/`Get`/`Remove-OERCatalogResource`),
  access packages (`New`/`Get`/`Set`/`Remove-OERAccessPackage`) and resource-role bindings
  (`Add`/`Remove-OERAccessPackageResourceRole`), assignment policies via builder cmdlets
  `New-OERAccessPackageApprovalStage` and `New-OERAccessPackageRequestorScope` plus full CRUD
  `New`/`Get`/`Set`/`Remove-OERAccessPackageAssignmentPolicy`, and admin-driven assignments
  (`New`/`Get`/`Remove-OERAccessPackageAssignment`). Private helpers `Resolve-OERCatalogId`,
  `Resolve-OERAccessPackageId`, `Resolve-OERCatalogResource`, `ConvertTo-OERCatalog`,
  `ConvertTo-OERCatalogResource`, `ConvertTo-OERAccessPackage`, `ConvertTo-OERAssignmentPolicy`,
  `ConvertTo-OERAssignment`, `ConvertTo-OERPolicyBody`, `New-OERApproverObject`. Adds the
  `EntitlementManagement.ReadWrite.All` delegated Graph scope and format views for all new tagged
  types.

## [0.1.0] - 2026-06-05

### Changed

- `Invoke-OERGraphRequest` now emits a clear, structured error on an app-only (ClientSecret/
  ClientCertificate) session when Graph returns an ACRS claims challenge or rejects the token,
  instead of attempting an impossible interactive step-up.
- `Initialize-OERAuth` reuses an existing session when no `-AuthMethod` is explicitly passed and a
  valid cached Graph token exists, so group cmdlets ensure connectivity without re-prompting.
- Group sub-cmdlets (`Set`/`Remove-OERGroup`, `Add`/`Remove-OERGroupMember`,
  `Add`/`Remove-OERGroupEligibility`, `Get`/`Set-OERGroupPimPolicy`) accept the group `-Id` from the
  pipeline by property name (with a `GroupId` alias), so `Get-OERGroup | Set-OERGroup`,
  `Get-OERGroup | Add-OERGroupMember -PrincipalId ...`, and similar chains work.

### Fixed

- Security: `Convert-GraphHttpException` no longer chains the raw Graph SDK exception as the
  InnerException of the converted error. The raw exception references the HttpRequestMessage whose
  Authorization header carries the bearer token in plain text, so a failed Graph call could surface
  the token in the console/logs. The Graph error code and message are still preserved.
