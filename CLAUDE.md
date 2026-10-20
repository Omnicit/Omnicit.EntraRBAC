# Omnicit.EntraRBAC - CLAUDE.md

Working rules for this repo. The history behind each rule lives in
[docs/development/rationale.md](docs/development/rationale.md), linked per rule as
`Why: ...#anchor`. Read the anchor before "simplifying" a rule.

Do not restate project status, roster or release history here: `README.md` owns the cmdlet list,
`CHANGELOG.md` owns release history, and the GitHub issue tracker owns open work.

---

## Branch Policy -- ALWAYS CHECK FIRST

**`main` is protected: a direct push is REJECTED BY THE SERVER and is not a lock to work around, and
a user cannot consent to "continue on the current branch" on `main`.** Every change reaches `main`
through a pull request. `Why: docs/development/rationale.md#branch-policy`

**Before any code change, Claude must:**

1. Determine the current branch (`git branch --show-current`).
2. On `main`: create a feature branch before touching any files (`git checkout -b <branch-name>`,
   named from the table below); propose the name and say what it is for, and do not wait for
   permission to leave `main`.
3. On any OTHER shared branch: stop and ask the user which branch to use.
4. Open a pull request against `main` when the work is ready. Never merge it without being asked to.

**Merge requirements on `main`:**

- **Four status checks are required: `ubuntu-latest`, `windows-latest`, `macos-latest` and
  `package`.** The first three are the matrix's `name: ${{ matrix.os }}`, so the job name IS the
  check name: renaming the job or changing the matrix orphans the protection rule and blocks every
  open PR until the rule is renamed to match. `package` is the `package` job's `name: package`
  (`needs: build-and-test`); renaming its `name:` (or, with `name:` removed, its job id) orphans its
  rule the same way. Change both together.
- **`package` never holds the gate alone:** it has no `if:` of its own, so when a leg fails or is
  skipped GitHub skips `package` too, and a skipped check counts as passed. Never drop the three leg
  checks from the rule in favour of `package`.
- **The branch must be up to date with `main` before it can merge** (strict): a branch that has
  fallen behind is rebased onto `main` and force-pushed, and the checks re-run on the rebased tip.
- **Linear history is required:** a merge commit is refused; squash merge is the convention.
- **Every conversation on the PR must be resolved** before merge.
- **The rule binds administrators too** (`enforce_admins` is on).

**Branch naming convention:**

| Change type | Prefix | Example |
|---|---|---|
| Bug fix | `fix/` | `fix/acrs-bearer-token-leak` |
| New feature | `feat/` | `feat/phase1-group-cmdlets` |
| Tests / QA | `test/` | `test/fix-auth-mocks` |
| Documentation | `docs/` | `docs/publish-without-approval` |
| Chore | `chore/` | `chore/dependency-cleanup` |
| Refactor | `refactor/` | `refactor/simplify-error-handling` |
| Build / CI pipeline | `ci/` | `ci/publish-on-merge` |

---

## Project Overview

`Omnicit.EntraRBAC` is a PowerShell 7.2+ (Core-only) module by Omnicit AB, MIT licensed and published
on the **public PowerShell Gallery**; it publishes itself -- see **Publishing** below. It
manages RBAC building blocks across many Entra ID and Azure tenants: Entra ID groups, PIM,
Administrative Units, Entitlement Management, Access Reviews, Azure resources and RBAC, plus a JSON
inventory and a declarative apply engine. Command prefix is `OER`.

**The canonical working tree is the clone whose `origin` is
`github.com/Omnicit/Omnicit.EntraRBAC`**; identify it with `git remote get-url origin`, never by its
directory. Do not commit to the older clone (its `origin` is the private repository, to be archived)
and do not treat a change made there as made. `Why: docs/development/rationale.md#project-overview`

The phase roadmap (phases 0-5) is **complete**; the module is feature-complete. See `CHANGELOG.md`
for what each release delivered.

---

## Module Layout

```
source/
  Omnicit.EntraRBAC.psd1      # Manifest -- source of truth for exports and RequiredModules
  Omnicit.EntraRBAC.psm1      # Dev-mode loader ONLY (Private -> Public); see Common Pitfalls
  suffix.ps1                  # Update-TypeData -Force + Register-ArgumentCompleter, each mirrored verbatim in the dev-mode psm1
  Private/                    # Internal helpers, one function per file
  Public/                     # Exported cmdlets, one per file, filename == function name
  Formats/                    # Omnicit.EntraRBAC.Format.ps1xml (type data is inline in suffix.ps1)
  en-US/                      # about_Omnicit.EntraRBAC.help.txt
tests/
  QA/                         # Seven gate files (below), all run by ./build.ps1 -Tasks test
  Unit/Private/, Unit/Public/ # One *.Tests.ps1 per source file, plus the named exceptions below
  Unit/Formats/               # FormatViews.Tests.ps1 -- format-view rendering checks
  Unit/TestHelpers/           # OERConfirmHost.ps1 (runspace whose PSHost answers ShouldProcess prompts:
                              #   genuine DECLINE, prompt/target text, order of warnings, 'What if:' lines
                              #   and prompts); OERTransportTripwire.ps1 (installed by every unit test
                              #   file); OERTransportTripwire.Tests.ps1 (its known-answer suite)
  Workflow/                   # PublishJob.Tests.ps1 -- the publish job's tag guard, proven offline:
                              #   PublishArtefact.ps1 called directly, step text run in pwsh against a
                              #   fake Gallery and a fake GitHub
build.yaml, build.ps1         # Sampler/ModuleBuilder config and bootstrap entry point
RequiredModules.psd1          # Build-time dependency resolver (NOT the runtime pin; see Dependencies)
azure-pipelines.yml           # Build + Test only, no Deploy stage -- it never publishes
.github/workflows/build-and-test.yml  # Build + Test, then package and publish; the ONLY path that publishes
.github/scripts/PublishArtefact.ps1   # -Record / -Verify / -Compare: the published bytes are the tested
                              #   bytes and the Gallery package is this commit's build. Single owner of
                              #   all three; do not split it.
```

There is **no `source/Classes` directory**; the loader iterates one, but argument completion is
scriptblock-based. `Why: docs/development/rationale.md#completers`, `Why: docs/development/rationale.md#module-layout`

**The build-and-test job's `if:` is wired to the merge gate** (not a billing guard alone; never
reason from GitHub's rule for skipped jobs):
`if: ${{ !github.event.repository.private || github.event_name == 'workflow_dispatch' }}` decides
whether `ubuntu-latest`, `windows-latest` and `macos-latest` (with `package`, the four REQUIRED
checks on `main`) exist; `package` follows via `needs: build-and-test`. **The mechanism is the
MATRIX, not the skip:** a job-level `if:` is evaluated BEFORE the matrix expands, so the legs are
never created and a required check that never reports stays pending forever (`package` skipped
counts as passed, but the three matrix names still never report). Turning the repository private
is therefore a change to this condition, or to the protection rule, made in the SAME change and
never afterwards. **Never rewrite the workflow as three jobs without a matrix** unless the required
checks become something a skipped job cannot satisfy: their skipped `if:` reports Success and the
gate goes GREEN with no test run, `package` included.
`Why: docs/development/rationale.md#required-checks-and-the-matrix`

**Do not maintain a function roster in this file;** read it from the tree:

```powershell
Get-ChildItem source/Public  -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
Get-ChildItem source/Private -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
```

`README.md` section "Available Cmdlets" is the maintained, cohort-grouped list of every exported
cmdlet; `Get-OERRequiredScope` reports the Graph/Azure permissions each needs.

**The seven QA gates** (`tests/QA/`): `module.tests.ps1` (manifest, changelog, help, README,
per-function PSScriptAnalyzer, a unit test file for every exported function); `about.tests.ps1`
(about topic byte-identical to source, ASCII/BOM-free, names every exported cmdlet and no other);
`requiredscope.tests.ps1` (`Get-OERRequiredScopeMap` vs the module's own call graph);
`sourcehygiene.tests.ps1` (the ten static source gates,
`Why: docs/development/rationale.md#static-source-gates`); `dochygiene.tests.ps1` (no unredacted
tenant object ids, tenant domains outside a four-label allowlist, non-documentation email addresses
or credentials in any tracked file under `docs/`, `specs/`, `source/`, `tests/`, listed with
`git ls-files` and read from disk; the placeholder register in `docs/live-verification/README.md`
must agree with itself and with every placeholder used; no angle bracket GitHub would render as a
tag in tracked Markdown under `docs/`, `specs/`, `README.md`, `CHANGELOG.md`); `docsync.tests.ps1`
(binds `README.md` to the about topic, and both to the manifest's cmdlet count); and
`testhygiene.tests.ps1` (every unit test file that imports the module installs, checks and
uninstalls the transport tripwire; read statically, importing nothing).

**`dochygiene.tests.ps1` applies TWO object-id rules, split by what the file is.** `docs/` and
`specs/`: a GUID is prose and must be a `00000000-0000-0000-0000-0000000000NN` placeholder. `source/` and
`tests/`: a GUID is a fixture and must not have **version-4 shape**; exactly three v4 values are
pinned by name (the module's manifest GUID, the Microsoft Graph Command Line Tools app id, the Reader
built-in role definition id). **Do not add a fourth: allocate a placeholder** from the register in
`docs/live-verification/README.md` (it records the next free `...NNN` and `personN`), adding its row
in the same commit that uses the slot. The gate is red on: a placeholder used in `source/`,
`tests/`, `docs/examples/` or `docs/development/` without a row marked taken; a register with
overlapping rows, a repeated slot description, no or several FREE rows, an "Allocate from" sentence
disagreeing with the FREE rows, a slot taken at or above a FREE start that is not a named outlier,
or a placeholder cell it cannot read. **Tenant domains** (`.onmicrosoft.com`, `.onmicrosoft.us`,
`.onmschina.cn`) are held to `contoso`, `fabrikam`, `other`, `oer-sovereign-verify-doesnotexist`
(`%40` read as `@`, `\.` as `.`): replace a real label with `contoso`, never widen the list. A
credential-shaped test literal (the bearer-scrub fixtures) carries `NOT-A-REAL-TOKEN` inside the
VALUE; `REDACTED` works too. `Why: docs/development/rationale.md#bearer-scrub-tests`

**`dochygiene.tests.ps1` also reads Markdown as GitHub renders it:** in tracked `.md` under `docs/`
and `specs/` and in `README.md` and `CHANGELOG.md`, no tag-like angle bracket (`<word>`, `</word>`,
`<!...>`, `<?...>`, autolink `<https://...>`, inline `<br>`) outside code. Use backticks (or `\<id>`
where a backtick would close a code span the line already has; quotes do not escape); a bare URL,
not an autolink; in `CHANGELOG.md` backticks only, never a backslash. Code is skipped by the
algorithm in `ConvertTo-DocHygieneMarkdownProse`'s `.DESCRIPTION` in `tests/QA/dochygiene.tests.ps1`:
the maintainer's `Test-MdAngleBrackets.py` (kept outside this repository), which the gate follows where the two differ, deliberately
not CommonMark's. Never "correct" it towards CommonMark; carry a change on either side to the other,
so they agree hit for hit. `Why: docs/development/rationale.md#qa-gates`

**`docsync.tests.ps1` holds `README.md` and the about topic against each other:** roster scoped to
`## Available Cmdlets` and `COMMAND COHORTS`; each `### Cohort (N)` count against the cmdlets that
cohort is the FIRST to name; word-for-word agreement on the tenant-switch verdict per sign-in type
and the device-code known limitation; every sentence in either whole document saying "all N
cmdlets" or "all N exported cmdlets" (README introduction and `## Available Cmdlets`, about topic
LONG DESCRIPTION) held to the count of `FunctionsToExport`, with a floor on the matches so rewording
cannot make it vacuous. Does NOT see a count written another way ("98 cmdlets" with no "all", a
spelled-out number); deliberately does NOT bind the surrounding prose (the sovereign-cloud,
tenant-profile and permissions sections are rewritten per medium).

**Test files named after no single function.** Ten cross-cutting suites exist; do **NOT** delete any
of them as an orphan when auditing the one-test-file-per-function invariant
(`Why: docs/development/rationale.md#qa-gates`):

- `Unit/Private/BasePathDefault.Cohort.Tests.ps1` -- all seven `-BasePath`/`-ProfileBasePath` default
  carriers resolve cross-platform; do not move it.
- `Unit/Public/AccessReview.Pipeline.Tests.ps1` -- cross-cmdlet pipeline suite.
- `Unit/Public/AmbiguousName.Guard.Tests.ps1` -- every public call site of an ambiguity-refusing
  `Resolve-OER*Id` helper surfaces the candidate ids, not a first match.
- `Unit/Public/NothingToUpdate.Cohort.Tests.ps1` -- every `Set-OER*` cmdlet (all twelve) reports the
  no-updatable-property condition as `NothingToUpdate`; `Set-OERRoleManagementPolicy`'s "no rule
  differs" case keeps its distinct `NoChange` id.
- `Unit/Public/GroupAliasOrder.Cohort.Tests.ps1` -- AST-driven: every `source/Public/*Group*.ps1`
  file declaring `-Group` lists the `GroupId` alias before the generic `Id`.
- `Unit/Public/AdministrativeUnitAliasOrder.Cohort.Tests.ps1` -- the same AST-driven check for every
  `-AdministrativeUnit` parameter, so a piped member's own `Id`/`DisplayName` can never mis-bind as the
  parent unit.
- `Unit/Public/TenantIdNotEmpty.Cohort.Tests.ps1` -- AST-driven: every public cmdlet declaring
  `-TenantId` carries `[ValidateNotNullOrEmpty()]`, except `Connect-OER` (no validation, so its own
  `InvalidTenantId` refusal runs after the session-uncertain marker is set); drives the binding
  refusal for the cmdlets the live checklist uses; installs the tripwire.
- `Unit/Public/DirectoryRoleInventory.RoundTrip.Tests.ps1` -- exports
  `directoryRoleManagementPolicies` and `directoryRoleAssignments` from a mocked live state with
  `Get-OERInventory`, applies them back through `Invoke-OERStructure` with and without `-Prune`:
  every row `Unchanged`. Runs with a session (state set for one tenant, `Initialize-OERAuth`
  mocked), so the export names that tenant (`tenantId`); applied under another tenant it is refused
  with `DocumentTenantMismatch`, reading and writing nothing.
- `Unit/Public/WarningBeforeConfirmation.Cohort.Tests.ps1` -- AST-driven: no `source/Public/*.ps1`
  file writes `Write-Warning` after its first `$PSCmdlet.ShouldProcess`, except allowlisted warnings
  (each with a reason; an entry matching none or two fails); pins by name and text the twenty cmdlets
  that warn before their gate; proves at run time on `OERConfirmHost` that each moved warning
  precedes the `What if:` line and the `-Confirm` prompt, with no write request.
  `OER_COHORT_SOURCE_ROOT` points its AST parts at a mutated copy of `source/`, never set in CI (also
  read by the cadence scan in `Get-OERAccessReviewCadence.Tests.ps1`, the `TenantIdNotEmpty` cohort
  and the scan in `Get-OERGroupRelation.Tests.ps1`); installs the tripwire.
- `Unit/TestHelpers/OERTransportTripwire.Tests.ps1` -- the tripwire's known-answer suite: the six
  names, module-scope resolution, parameter parity, mock precedence, the record and the refusal, a
  re-import, the `AfterAll` check, the answering runspace, the uninstall.

---

## Build and Test Commands

```powershell
# Bootstrap build dependencies (first time or after a clean clone)
./build.ps1 -ResolveDependency -Tasks noop

# If that fails with "Requested value 'V2' was not found" (PSResourceGet compat error), add:
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast

# Build the module (output lands in output/module/Omnicit.EntraRBAC/<ver>/)
./build.ps1 -Tasks build

# Full test suite, the authoritative CI gate: QA tests + Unit Pester + PSScriptAnalyzer + 80% code coverage
./build.ps1 -Tasks test

# Import from source (needs AzAuth, Microsoft.Graph.Authentication on PSModulePath;
#  prepend output/RequiredModules if needed)
Import-Module ./source/Omnicit.EntraRBAC.psd1 -Force

# Import the built module
Import-Module ./output/module/Omnicit.EntraRBAC/<ver>/Omnicit.EntraRBAC.psd1 -Force
```

Coverage is measured against the **built** module, not `source/`: run `-Tasks build` before
`-Tasks test` after changing source files, and never build while the gate is running.
`Why: docs/development/rationale.md#build-and-test-commands`

**Under `latest`, LOCAL GREEN IS NOT CI GREEN:** `RequiredModules.psd1` asks for the newest release
of every module (`Why: docs/development/rationale.md#dependencies`); a local `output/RequiredModules`
is resolved once and goes stale, while CI resolves afresh on every run, so a full local pass proves
the suite against what is on disk, not what the merge gate runs. Refresh before trusting a local
run, especially before opening or updating a PR:
`./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast` (a different resolver from CI's, whose
tree may also hold unpacked `.nupkg` directories `_manifest`, `_rels`, `dependencies`, `package`; the
CI dependency-report step is the authority on what the gate tested). A refresh adds versions and
removes none: PowerShell loads the HIGHEST version, so a refreshed tree tests the new one; the
directory is a growing record, not a picture of what is requested. Confirm the version under test
with `Get-Module <name> -ListAvailable`, not the folder listing; delete the directory for a clean
resolve.

---

## Publishing

**Every merge to `main` publishes a new preview to the public PowerShell Gallery, and that is
PERMANENT.** The Gallery can unlist a version but cannot delete one. There is no staging step and
no deployment approval between merge and publish: merging the pull request is the decision to
publish it.

- **Publishing lives only in the `publish` job of `.github/workflows/build-and-test.yml`.**
  `./build.ps1 -Tasks publish` must stay undefined (no local publishing path); do NOT restore
  Sampler's `Publish_Release_To_GitHub` / `publish_module_to_gallery` tasks in `build.yaml`.
  `Why: docs/development/rationale.md#publish-on-merge`
- **A documentation-only merge publishes a preview too:** the workflow has no path filter and must
  not be given one. `Why: docs/development/rationale.md#publishing`
- **`paths-ignore` must never be added to the `pull_request` trigger**, for the reason the matrix
  exists: a run that never happens never reports the four required checks, and a required check
  that never reports stays Pending forever.
- **The publish job tags every publish, and the tag is load-bearing:** `GitVersion.yml`'s
  `mode: ContinuousDelivery` advances the preview counter on a TAG, not per commit, so merges with
  no tag between them build the SAME version; the later run finds it on the Gallery, skips its
  publish, and tags it only when its tested build is the package there (below).
  `Why: docs/development/rationale.md#publish-on-merge`
- **The tag step tags only the commit whose tested build IS the package on the Gallery.** Except on
  a `v` tag run it first runs `PublishArtefact.ps1 -Compare` (reads the package back with
  `Save-PSResource`, compares it file by file and SHA-256 by SHA-256 with the tested artefact); a
  different build or a failed read refuses the step before anything is tagged or released, as does
  a tag already naming another commit (`gh release create` ignores `--target` for an existing tag).
  Repair:
  - **Tag step failed, or publish step failed although the upload arrived:** re-run the FAILED job
    of that same run (it reuses the tested artefact, matches and tags).
  - **Run refused** (a later merge, same version, different build; a byte-identical build IS the
    package and is tagged): push the missing tag by hand onto the commit that published the
    version, then re-run ALL jobs of the newest refused run (it counts up from that tag and
    publishes it); re-running only its failed jobs reuses its own build and is refused again. The
    refusal names the steps. A preview tag on the wrong commit is named in either refusal -- by
    the tag check when the run's own build is the package, and in the comparison's repair text
    otherwise: delete it with `git push origin :refs/tags/v<version>` before tagging the right
    commit.
  - **Never loosen the comparison to turn a refused run green.** A later-day rebuild is a different
    build too (the release notes carry the build date), so re-running ALL jobs of the run that
    published is refused as well; re-run only its failed jobs.

  `Why: docs/development/rationale.md#the-tag-step-tags-only-the-build-that-was-published`
- **Never create a version tag by hand outside that repair or a deliberate release.** The existing
  rule under **CHANGELOG and Version** still holds, and now has teeth: a stray tag changes what
  gets PUBLISHED.
- **No approval stands between a merge or a `v` tag and the Gallery** (Philip, 2026-09-23). The
  `Entra RBAC` environment has no required reviewers, scopes `GALLERYAPITOKEN` to the `publish` job
  and admits only branch `main` and the stable `v<X.Y.Z>` tag patterns. A preview is gated by the
  pull request and its required checks, a full release by the tag, which only the `Stable Version`
  tag ruleset's bypass list can create, move or delete; both are repository SETTINGS on purpose,
  never workflow checks. Never widen an environment tag pattern past the ruleset (every pattern
  starts with `v` and admits no hyphen; `v*` was removed). Accepted residual: whoever can merge a
  pull request can publish a preview, until `Require approvals` is on with a second reviewer.
  `Why: docs/development/rationale.md#publish-on-merge`
- **The workflow must never create, move or delete a stable tag.** The ruleset refuses
  `GITHUB_TOKEN` all three, so a stable run that tried would fail in its last step, AFTER the
  publish. On a `v` tag run the release step attaches the release to the tag already there; the
  only tag the workflow ever writes is a hyphenated preview tag, which the ruleset excludes.
- **The publish job refuses a version its ref does not call for**, straight after the artefact is
  verified and before anything is published: on a `v` tag the built version must equal the tag exactly and
  the tagged commit must be on `main`; on `main` the build must carry a prerelease label; any other
  ref is refused. It guards against MISTAKES, not an adversary; the gate stays in the settings.
  **A refused or misplaced stable tag stays where it is**, and nothing removes it for you: someone
  on the bypass list deletes it with `git push origin :refs/tags/v<X.Y.Z>` and, for a misplaced
  one, pushes it again on the `main` commit it was meant for.
  `Why: docs/development/rationale.md#publish-on-merge`

**To cut a full release:**

1. Push `v<X.Y.Z>` on the `main` tip once its four required checks are green. Only the
   `Stable Version` ruleset's bypass list can create that tag; the push IS the release decision,
   with no approval after it. A tag outside the `Entra RBAC` environment's patterns (a major of 10
   or more, a minor or patch of 100 or more) is refused by the environment and publishes nothing;
   the repair is a new pattern the ruleset also covers, never a return to `v*`.
2. Make the close-out the FIRST merge after the tag, as the **close-out after a stable release**
   rule under **CHANGELOG and Version** describes; check it against
   `git show v<X.Y.Z>:CHANGELOG.md` -- the dated section must say what that tag actually shipped.
   `Why: docs/development/rationale.md#publishing`

---

## CHANGELOG and Version

`CHANGELOG.md`'s `[Unreleased]` section **is** the next release's published `ReleaseNotes`, not a
per-PR log. The build rewrites its heading to `## [<version>] - <date>` and copies the section
verbatim into the built manifest's `PrivateData.PSData.ReleaseNotes`.

- **Write `[Unreleased]` in release-note voice** -- product-level, user-visible: what this version
  is and what changed for a consumer. Budget **4,000 characters**, gated in
  `tests/QA/module.tests.ps1` on the section's `RawData`, which includes the `## [Unreleased]`
  heading and so reads slightly SHORT of what is published -- do not spend the difference.
- **The floor is on the BODY: 50 characters, about one sentence** -- the section after its heading
  line, trimmed, in the source and in the built manifest alike. It catches a MECHANICAL failure (an
  emptied or hand-converted section publishing `ReleaseNotes` of length 0), not poor text: review
  judges that. Never pad the section to get past it -- every merge publishes the padding for good.
- **Close-out after a stable release** is the FIRST merge after a `v<X.Y.Z>` tag: add
  `## [X.Y.Z] - <date>` directly above the previous dated heading, move the released notes under
  it, and leave `[Unreleased]` holding exactly this sentence and nothing else (`X.Y.Z` = the
  version just released):

  ```text
  No changes to the module since X.Y.Z. A preview published from this point differs from X.Y.Z only in documentation, tests or the build.
  ```

  **The first change under `source/` after a close-out REPLACES the sentence** with a note of its
  own; it never adds one after it. Wrapping the sentence across lines is fine.
  `tests/QA/module.tests.ps1` holds both halves: while the sentence stands it must be exactly that
  sentence for the latest dated section in `CHANGELOG.md`, and it must not survive a diff that
  touches `source/`.
- **Per-PR engineering detail belongs in the PR body and the commit message**, not in
  `CHANGELOG.md`.
- **When `[Unreleased]` approaches the budget, close the detail out.** Add a NEW dated
  `## [<version>] - <date>` heading directly above the previous dated one, move the accumulated
  detail under it, and rewrite `[Unreleased]` as a summary of the release as a whole.
- **Never convert, rename or delete the `## [Unreleased]` heading itself.** The build does that at
  release time against its own OUTPUT copy; the source file is never modified by a build.
- **A PR that changes nothing under `source/` is not required to touch `CHANGELOG.md`:** the
  changed-file gate fires only on a path matching `^source/`.
- **The two gates that read the BUILT artefact need a build** (`build.yaml`'s `test` workflow does
  not include `build`, so both measure what is already in `output/module/`): the published-notes
  gate also compares it with the CURRENT `CHANGELOG.md`, so a build older than the `CHANGELOG.md` edit turns it red; the
  version cap reads only the artefact's own version, so it reddens on staleness only if nothing
  resolves or the stale build is outside the `1.x` line. Build before test, as
  `## Build and Test Commands` requires. Both resolve the module with
  `Get-Module -ListAvailable | Select-Object -First 1`, so they measure whichever copy ranks first
  on `PSModulePath` (the built module under `./build.ps1 -Tasks test`; a globally installed copy
  would be measured instead).

`Why: docs/development/rationale.md#changelog-budget`

**The computed module version is held in the `1.x` line** by `GitVersion.yml`: `next-version`
(`1.0.0`) is the base when no tag outranks it; `major-version-bump-message` carries BOTH halves of
its pattern, restored deliberately -- the explicit `+semver: breaking|major` token AND the
conventional-commit `^[a-z]+(\(.+\))?!:` subject form. `GitVersion.yml` is the truth here;
`minor-version-bump-message` and `patch-version-bump-message` are working.

**How the version is computed.** The base is the greatest of the highest reachable version tag,
`next-version` and the `x.y.z` of a `release/x.y.z` branch name (the branch built, or one a standard
merge commit message names); a tag on HEAD is returned verbatim and outranks every other tag and
`next-version`, though a higher `release/x.y.z` still beats it. **At most ONE increment**, from the
commits since the NEAREST reachable tag (all of them when there is none): a TAG base not on HEAD
takes the greater of the branch default (Patch on `main` and every branch prefix this repo uses) and
the highest `+semver:` level in that window; a `release/*` branch has no branch default (`increment: None`). A
`next-version` or `release/x.y.z` base takes no default increment, so it is used as written unless a
`+semver:` commit is in the window. A PRERELEASE-labelled tag (`v0.9.0-preview.1`) takes no
`MajorMinorPatch` increment at all, and no `+semver:` message moves it.

**Do not create a version tag, or a `release/x.y.z` branch, outside a deliberate release.** Any tag
at or above `next-version` becomes the base, one sitting on HEAD ships verbatim whatever its value,
and a branch named `release/2.0.0` builds `2.0.0` with no tag involved. `release/` is not one of the
prefixes in the branch-naming table above. With no reachable tag the base is `1.0.0` and at most one
increment applies: one `+semver: fix` builds `1.0.1`, one `+semver: minor` `1.1.0`, one
`+semver: major` `2.0.0` -- and so does a `!:` subject, through the other half of the pattern.
`tests/QA/module.tests.ps1` holds the built version at or above `1.0.0` and below `2.0.0`,
independently of `GitVersion.yml`; lift both together when `2.0.0` is called, and never raise that
assertion just to make a build pass.

**Two shapes move the version from a message; keep both out of commit messages, PR titles and PR
bodies.**

1. **Never quote a bump token** -- name it in words ("the semver major token"). Quoting the major
   token builds `2.0.0`; quoting the minor or fix token moves the version silently.
2. **Never write a conventional-commit `!:` subject.** `fix!: ...`, `feat(x)!: ...` and every other
   `<verb>!:` or `<verb>(<scope>)!:` form matches the second half of `major-version-bump-message`
   and builds `2.0.0`. This half is LIVE; do not rely on any older note saying it is disabled.

GitVersion reads every reachable commit message and a squash merge copies the PR title and body
into `main`, so a squash title of `fix!: ...` suffices. File content is never read and may quote
either shape freely.

**Every merge to `main` publishes, so the shapes split by level and only one level is caught:**

- **Major** (`!:`, or the quoted major token). `tests/QA/module.tests.ps1` caps the built version
  below `2.0.0` independently of `GitVersion.yml`, so the merge turns `main` RED, `package` and
  `publish` never run, and nothing is published.
- **Minor or fix.** Nothing caps these. `main` carries `tag: preview`, so the merge publishes, for
  example, `1.1.0-preview0001` in place of `1.0.1-preview0001` -- a real version, on the public
  Gallery, that cannot be deleted, and a version line that was never chosen. There is no gate
  behind this one: the rule about what you type IS the control.

`Why: docs/development/rationale.md#version-cap`,
`docs/development/rationale.md#publish-on-merge`

---

## Authentication Architecture

**Public:** `Connect-OER`, `Disconnect-OER`. **Private:** `Initialize-OERAuth` (single entry point).

Every public cmdlet calling Graph or Azure invokes `Initialize-OERAuth` at the start of its
`begin`/`process` block, with `-IncludeARM` when it needs ARM; `Connect-OER` is an optional pre-auth
shortcut -- all cmdlets authenticate automatically on first use. Auth uses AzAuth's `Get-AzToken` for every credential type; state in
`$script:_OERAuthState`, keyed on tenant, auth identity, **and cloud**, carries `SignedInObjectId`
(Graph token `oid` claim), never the token. `Why: docs/development/rationale.md#auth-state`

**The state also carries `GraphSessionFingerprint`** (the Graph SDK session the module's own
`Connect-MgGraph` left; never a token or the context object, never written to any stream). Owners:
`Get-OERGraphSessionFingerprint` (fingerprint), `Get-OERGraphSessionState` (comparison). Checked by
every `Initialize-OERAuth` entry past its nested-sign-in check, cached return included, and by
`Invoke-OERGraphRequest` before every Graph call; a session another `Connect-MgGraph` started is
refused with `GraphSessionChanged`. Only `Connect-OER` passes `-ReclaimGraphSession` (takes the
session back, passes the session-uncertain refusal, clears that marker without a tenant); never add
a second reclaim caller, never make the module switch the session back by itself. Gate 10 of
`tests/QA/sourcehygiene.tests.ps1` holds the NAME `ReclaimGraphSession` to `Connect-OER.ps1` and
`Initialize-OERAuth.ps1`. `Why: docs/development/rationale.md#auth-state`

**A command whose sign-in is refused sends nothing -- no Graph and no ARM request.**
`Initialize-OERAuth` latches its calling command (`Lock-OERSignIn`) directly after the
nested-sign-in check; releases only on success (`Unlock-OERSignIn`: cached return, or a new
connection that went the whole way); both called only there. Every refusal, terminating error and
early return leaves it latched, `ArmTokenAcquisitionFailed` included, so its Graph calls are refused
although its Graph half connected. Exception: the nested-sign-in refusal, before `Lock-OERSignIn`,
latches nothing of its own (the latched outer command it found covers the caller). The latch is
keyed weakly on the calling command's INVOCATION, never a module boolean (a pipeline neighbour's
successful sign-in releases only its own entry).

Both transports ask `Get-OERSignInRefusal` before every request and refuse while any call-stack
frame is latched, with `SignInRefused` (`New-OERSignInRefusedError` owns id and message): Graph
wrapper after its session gate (a changed session still reads `GraphSessionChanged`); after a
`GraphSessionChanged` refusal at the cmdlet's entry, ARM calls read `SignInRefused`.

A refused command's nested sign-ins are refused before they are made: before `Lock-OERSignIn`,
`Initialize-OERAuth` asks `Get-OERSignInRefusal -OutsideCaller`; when a command OUTSIDE its caller
is latched (the caller is a cmdlet that command calls, or signs in inside that command's output) it
raises a terminating `SignInRefused` naming that command -- no token call, no `Connect-MgGraph`, no latch of its own. The caller's
own latched frame does not count: a command refused earlier in the same invocation
(`Invoke-OERStructure`, next piped document) may sign in again. Only `Initialize-OERAuth` passes
`-OutsideCaller`; never make that check walk the whole stack. A finished command is on no call
stack: the next command, or `Connect-OER`, sends again. An ARM call of a command whose entry was
not refused still goes out with the module's own token.

Never write that the cmdlet stops -- it carries on and sends nothing -- except `Export-OERInventory`
(below). Never call `Lock-OERSignIn` or `Unlock-OERSignIn` outside `Initialize-OERAuth`. Call
`Initialize-OERAuth` directly in the command's own block, never from a nested function, `& { }` or
any scriptblock; the transports' own refreshes, in `Invoke-GraphSingle` and
`Invoke-ArmCallWithRefresh`, are the one exception.
`Why: docs/development/rationale.md#auth-state`

**`Export-OERInventory` stops on a refused sign-in and writes nothing -- the one public cmdlet that
does.** `begin` calls `Initialize-OERAuth` directly in a `try` (not a script block or nested
function; gate 10 allows it) with `-ErrorVariable SignInErrors`. A terminating refusal is caught,
scrubbed first, re-raised with `$PSCmdlet.ThrowTerminatingError` (the sign-in's own record and
ErrorId; a caller's `try` still catches it and, outside one, only that statement ends); never
`WriteError`. The one refusal written without
terminating, `ArmTokenAcquisitionFailed`, is found in `SignInErrors` by the first comma segment of
its `FullyQualifiedErrorId`, compared whole and ordinally, never searched for; the export marks
itself refused and raises nothing (a caller's `try` catches it only under a Stop error preference).
Under `-ErrorAction Ignore` or `$ErrorActionPreference = 'Ignore'`, which add a record to no
`-ErrorVariable`, the call is pinned to `SilentlyContinue`, under no other preference. A refused
export asks for no tenant ID, reads nothing, writes no folder, returns no object, under every error
preference. Every other command keeps the rule above; `Get-OERInventory` keeps its behaviour.
`Why: docs/development/rationale.md#a-command-whose-sign-in-is-refused-sends-nothing`

**A command sends nothing under a sign-in a later command replaced.** Where `Initialize-OERAuth`
succeeds -- exactly where `Unlock-OERSignIn` releases the latch -- `Register-OERSignInIdentity`
remembers, keyed like the latch, the identity the state carries: tenant, method, client, cloud,
never a token. `Get-OERSignInIdentity` is its single owner. Both transports ask
`Get-OERSignInSupersession` before every request and refuse with `SignInSuperseded`
(`New-OERSignInSupersededError` owns id and message) while ANY frame on the call stack remembers
another identity than the state now carries: an outer command whose nested cmdlets inherited the
switched state is refused too, as is a downstream command's request made inside the upstream
command's output call.

`Invoke-OERStructure` and `Connect-OER` sign in in `process`, not `begin`; a downstream command's
`begin` runs first, even with no pipeline input. When they name a tenant, their own sign-in switches
the state back, so the downstream command is refused. WITHOUT `-TenantId` a sign-in in `process`
inherits the state the downstream command's `begin` left and remembers it, so no gate sees the
switch: `Invoke-OERStructure`'s document, `-Prune` included, would apply to the downstream command's
tenant, as would the name lookups of the three builders that sign in only to look up a name --
`New-OERAccessPackageApprovalStage`, `New-OERAccessPackageRequestorScope` (through
`Resolve-OERTargetList`), `New-OERAccessReviewStage` (through `Resolve-OERReviewerScope`). So those
four commands take a snapshot of the session in `begin` and, without `-TenantId`, compare it in
`process` directly before that sign-in or lookup (`Invoke-OERStructure` after the document is read
and validated, the builders after their argument checks), refusing with `SignInSuperseded` and
sending nothing when the identity changed, or when the module held no session and now holds one.

`Checkpoint-OERSignIn` is the single owner of the session a command began with; it builds the
snapshot only through `Get-OERSignInIdentity`, so its terms are the memory's. `Invoke-OERStructure`
takes it again after every sign-in, refused or not, so its next piped document is compared with the
session that sign-in left; the builders take no pipeline input and never take it again. A new
command that signs in only in `process`, directly or through a helper, without `-TenantId` takes the
same snapshot. Never name the tenant the command began with as `-TenantId` in `process` instead: a
`-TenantId` other than the state's inherits nothing.

The snapshot is taken in the command's own `begin`: it covers a command standing in the pipeline
itself, not one called inside a script block or function in a pipeline --
`ForEach-Object { Invoke-OERStructure ... }` begins after every `begin` of the outer pipeline, so
takes a downstream command's sign-in for the session it began with. Closed for a document naming its
tenant (`tenantId`, which `Get-OERInventory` and `Export-OERInventory` write):
`Get-OERDocumentTenantMismatch` refuses it in any other tenant with `DocumentTenantMismatch`,
whatever session the command began with. Still open for a document without `tenantId` (applied,
`-Prune` included, in the downstream command's tenant) and for the builders, which look names up
there. So never call a name-looking builder, or `Invoke-OERStructure` with a document that carries
no `tenantId`, without `-TenantId` inside a script block or function in a pipeline that signs in to
another tenant or identity.

The identity's tenant term is the tenant the Graph token was issued for (`TokenTenantId`) when a
GUID, else the tenant as NAMED, never the ARM token's: one tenant named by GUID, by domain or not at
all is ONE identity, to the snapshot as to the memory, whenever the token reports a GUID tenant.
Never key the identity on the name again, nor on the ARM tenant. The session CACHE stays keyed on the
tenant as named: a command naming its tenant differently from the session inherits nothing and signs
in again, so README.md's "Name the tenant explicitly and consistently" and the about topic's
equivalent under SOVEREIGN CLOUDS stand.

The order is fixed: Graph wrapper session gate, latch gate, supersession gate; ARM wrapper latch
gate, supersession gate. A command with no memory is not compared by that gate. A pipeline must not
span tenants or identities: run the commands as separate statements, for example collecting into a
variable first. Never call `Register-OERSignInIdentity` outside `Initialize-OERAuth` or anywhere but
directly after an `Unlock-OERSignIn` with the same invocation; never read the supersession outside
the two transports. `Why: docs/development/rationale.md#auth-state`

**A tenant named by domain is looked up before any token request, and checked like a GUID.**
`Initialize-OERAuth` resolves every requested tenant that is neither a GUID nor `organizations`
through `Resolve-OERTenantDomain` -- after the cached return and the credential checks, before the
AzAuth trackers move and before any token call; both `TenantMismatch` checks, Graph and ARM, compare
the granted tenant with the tenant ID it returns (a granted tenant that is not a GUID is not
compared: the limit below). A failed lookup refuses the sign-in with `TenantResolutionFailed` (raised
after the lookup's `try`, never inside its `catch`), no token requested; `common` names no tenant and
is refused the same way. The token request still names the tenant as given. `organizations` is never
looked up or compared. Never call `Resolve-OERTenantDomain` outside `Initialize-OERAuth`, never move
the lookup above the cached return or the credential checks, never exempt another non-GUID value as
`organizations` is. `Why: docs/development/rationale.md#switching-tenants-in-one-process`

**A refused sign-in leaves the session uncertain.** `Initialize-OERAuth` sets the marker directly
after `Lock-OERSignIn` and, after the `GraphSessionChanged` refusal and before the cached return and
every token call, refuses with `SignInRefused` (`New-OERSignInRefusedError -SessionUncertain`) a call
that names no tenant (no `-TenantId`, or `-TenantId organizations`) while the marker it found was
set, unless the call is `Connect-OER`'s (`-ReclaimGraphSession`); the caller stays latched. At each
success end, directly after `Register-OERSignInIdentity`, it clears the marker when the call named
its tenant and is not a transport's own refresh (`-ForceRefresh` or `-ClaimsChallenge`), or is
`Connect-OER`'s, else puts back the value it found. `Connect-OER` sets the marker first thing in
`process`, so its own refusals before any sign-in count; `Disconnect-OER` clears it inside its
`ShouldProcess`. `Set-OERSessionUncertain` is the single owner of `$script:_OERSessionUncertain`:
never read or write the variable elsewhere, never call the helper outside `Initialize-OERAuth`,
`Connect-OER` and `Disconnect-OER`, never let a transport's refresh clear the marker, never count
`organizations` as naming a tenant. A command that names its tenant is never refused by the marker;
a parameter binding error of `Connect-OER` never reaches it (known limit).

`Connect-OER` sends every BOUND `-TenantAlias` to its alias check: an empty, whitespace or `$null`
alias is refused with `InvalidTenantAlias` and leaves the marker set; a BOUND `-TenantId` that is
empty, whitespace or `$null` is refused the same way, in `process` after the marker is set, with
`InvalidTenantId`. Never test either for truthiness there, never give either
`[ValidateNotNullOrEmpty()]`. Every OTHER public cmdlet declaring `-TenantId` carries
`[ValidateNotNullOrEmpty()]` on it, so an empty value stops it at parameter binding and it sends
nothing; `tests/Unit/Public/TenantIdNotEmpty.Cohort.Tests.ps1` holds both
halves, `Connect-OER` the one named exception; a new public `-TenantId` takes the attribute.
`New-OERConfiguration` and `Set-OERConfiguration`, whose `-TenantId` is stored rather than signed in
to, also refuse a value of white space only at binding, with a `[ValidateScript()]` declared above
that attribute; a stored blank `TenantId` is still read as it is, and an update naming no
`-TenantId` keeps it. The `(BL-96)` Contexts of `tests/Unit/Public/New-OERConfiguration.Tests.ps1`
and `Set-OERConfiguration.Tests.ps1` hold it.

An internal call passes `-TenantId` on only when it is set (`if ($TenantId) { ... }`), never an
empty value -- except `Connect-OER`'s own call of `Initialize-OERAuth`, which passes `''` when
neither `-TenantId` nor `-TenantAlias` is bound (read as no tenant named). Gate 10 of
`tests/QA/sourcehygiene.tests.ps1` holds it for a `-TenantId` parameter, or a `TenantId` key the
calling function writes into a splatted hashtable, on a call of a command that signs in, with
`Connect-OER`'s call and the two transports' refreshes as its named exemptions, and refuses any
positional argument on a call of `Initialize-OERAuth` (`-TenantId` binds by position 0), after a
switch too, `-Verbose` and `-Debug` (`-vb`, `-db`) among them; what it cannot see is listed in
`docs/development/rationale.md#static-source-gates`.
`Why: docs/development/rationale.md#a-refused-sign-in-leaves-the-session-uncertain`

| Parameter set | Key parameters | Use case |
|---|---|---|
| `Interactive` (default) | `-TenantId`, `-Interactive` | Admin at a keyboard (system browser) |
| `DeviceCode` | `-TenantId`, `-DeviceCode` | Headless / SSH |
| `ClientSecret` | `-TenantId`, `-ClientId`, `-ClientSecret` (SecureString) | Automation |
| `ClientCertificate` | `-TenantId`, `-ClientId`, `-Certificate` or `-CertificatePath` | Automation (recommended) |
| `ManagedIdentity` | `-ManagedIdentity`, `[-ClientId]` | Azure-hosted / pipeline |
| `ByAlias` | `-TenantAlias` | Resolve TenantId from a stored Tenant Profile |

Common optional: `-IncludeARM` (acquire ARM token and connect to Azure); `-Environment` (the
sovereign cloud -- `Global` (default), `USGov`, `USGovDoD` or `China`); the cloud joins tenant and
auth identity in the `$script:_OERAuthState` cache key, so a different cloud always re-authenticates.
Microsoft 365 GCC runs on the commercial (`Global`) endpoints and needs no `-Environment`; only GCC
High (`USGov`), DoD (`USGovDoD`) and a 21Vianet tenant (`China`) are separate cloud boundaries.
`Disconnect-OER` clears `$script:_OERAuthState` and calls `Disconnect-MgGraph` only when
`Get-OERGraphSessionState` reports `Own` (a session the module did not connect, or has no record of
connecting, is left, with a warning written before its `ShouldProcess`); it does NOT call
`Disconnect-AzAccount` (Philip, 2026-09-21).
`Why: docs/development/rationale.md#sovereign-clouds`

**IMPORTANT:** `-ClientSecret` is a `[securestring]`. Never accept or store client secrets as plain
strings.

**Same-session tenant switch is limited by sign-in type.** AzAuth keeps ONE credential for the whole
process and `Get-AzToken -Tenant` is not honoured by every credential type: device code and managed
identity requests do not carry the named tenant at all; a client secret credential refuses a
different tenant until `-Force` rebuilds it (with `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH` set, it
silently requests the token from the previous tenant). `Initialize-OERAuth` refuses, with
`TenantMismatch`, a token issued for another tenant than the one named (by GUID or, through the
lookup above, by domain), within two limits: a token whose tenant AzAuth does not report as a GUID
(no `tid` claim) is not compared; `organizations` names no tenant, so its tokens are compared with no
requested tenant, but an ARM token acquired under it is compared with the session's Graph token
(`TokenTenantId`) when both are GUIDs, and refused with the same `TenantMismatch` when they differ.

A state rebuild (a Graph token renewal, a transport's refresh) carries the cached ARM token into the
new state only when, besides the unchanged tenant label, identity and cloud (`$ArmIdentityUnchanged`),
its `ArmTokenTenantId` equals the new Graph token's tenant, both GUIDs (`$ArmTokenKept`); otherwise
it is dropped, the ARM step of that call runs under `-IncludeARM`, and the new ARM token is compared
as above. Never carry it on the label alone (`organizations` stays `organizations` across a renewal
answered from another tenant). Before the call it only warns, for a client secret switch it can
predict will not take effect (a `-WarningAction Stop`/`$WarningPreference = 'Stop'` caller is
stopped at that `Write-Warning`, before any token request). The post-call warning that compared
granted tenants is retired; do not bring it back. `Connect-OER -Force` is the only public lever that
makes a switch take effect.

**Every device code token request, Graph and ARM, carries `Force`** (Philip, 2026-10-09).
`$DeviceCodeForced` in `Initialize-OERAuth` is the single owner of that decision, read only by the
`Force` condition and by the removal of `Force` after a Graph acquisition; it is NOT a cache term:
`$GraphCached`, `$ArmCached` and `$ClearsUncertainty` never read it, so a device code session whose
tokens are still valid answers from the cached return with no token request. Never add an automatic
`-Force` to any other sign-in type without a new decision, never make the device code `Force`
bypass the cached return. `Why: docs/development/rationale.md#auth-state`,
`docs/development/rationale.md#switching-tenants-in-one-process`,
`docs/development/rationale.md#requested-tenant-vs-granted-tenant`,
`docs/development/rationale.md#every-device-code-sign-in-is-forced`

---

## Tenant Profile Config

Per-tenant configuration is stored as PSD1 files under
`<home>/.config/Omnicit.EntraRBAC/Profiles/<alias>.psd1`. Never write `$env:USERPROFILE` to build
that path (Windows-only; the module is `CompatiblePSEditions = 'Core'`).
`Why: docs/development/rationale.md#profile-path`

| Cmdlet | Operation | Notes |
|---|---|---|
| `New-OERConfiguration` | Create | Mandatory `-TenantAlias`, `-TenantId`. Non-terminating error if alias exists; directs to `Set-OERConfiguration`. |
| `Get-OERConfiguration` | Read | Optional `-TenantAlias` filter. Returns `Omnicit.EntraRBAC.TenantConfiguration` objects. |
| `Set-OERConfiguration` | Update | Mandatory `-TenantAlias`. Non-terminating error if alias missing. Preserves sections not specified. |
| `Remove-OERConfiguration` | Delete | Mandatory `-TenantAlias`. `ConfirmImpact = Medium`. |

A profile's optional `Environment` key names the sovereign cloud of that tenant (`Global`, `USGov`,
`USGovDoD` or `China`). `Connect-OER -TenantAlias` reads it when the command line names no
`-Environment` of its own; an explicit `-Environment` always overrides it.
`Why: docs/development/rationale.md#tenant-profile-config`

The private helper `Export-OERConfiguration` owns PSD1 serialization. Never inline the serialization
logic in a public function -- always call the helper.

---

## Naming Engine

Private `Resolve-OERName -Template '{token}...' -Tokens @{...}` substitutes `{token}` placeholders
(case-insensitive). Any unresolved placeholder is a caller error and throws immediately -- no
malformed name is ever returned. Enforces `-MaxLength` (default 256) and optional `-Strict`
character validation.

Used by every creation cmdlet. Do not duplicate template substitution logic -- always call this
helper.

Naming rules live in a naming standard file that `Test-OERStructure -NamingStandard` checks offline;
`Test-OERNamingStandardName` owns them (see **Code Style**).
`Why: docs/development/rationale.md#naming-standard`

---

## Argument Completion

Tab-completion is **scriptblock-based**: a `Register-ArgumentCompleter` call in `source/suffix.ps1`,
mirrored verbatim in the dev-mode psm1. `Why: docs/development/rationale.md#completers`

| Parameter | Backing helper | Registered on |
|---|---|---|
| `-Role` | `Resolve-OERRoleCompletion` (from `Get-OERCommonRoleName`) | Every cmdlet taking an Azure RBAC role name -- the registered list is in `suffix.ps1` |
| `-RoleName` (alias `-Role`) | `Resolve-OERDirectoryRoleCompletion` (from `Get-OERCommonDirectoryRoleName`) | `Add`/`Remove-OERAdministrativeUnitScopedRole` |
| `-Role` | `Resolve-OERBuiltInDirectoryRoleCompletion` (from `Get-OERBuiltInDirectoryRoleName`, tenant-wide built-in roles) | `Get`/`Set-OERDirectoryRoleManagementPolicy` and the six directory role assignment cmdlets |
| `-TenantAlias` | `Resolve-OERTenantAliasCompletion` (profile `*.psd1` basenames on disk) | `Connect-OER`, `Get`/`Set`/`Remove-OERConfiguration` |

**Rules for adding a completer:**

1. **Never attach a `ValidateSet`.** Completion is additive: free text, GUIDs and custom role names
   must keep binding; a curated list is a hint, not a constraint.
2. **Completers must be fast and offline.** No Graph or ARM call: they run on the interactive prompt
   path.
3. **Never throw and never write an error record** from a completer -- return no results instead.
4. **Register in `suffix.ps1` AND mirror it in the dev-mode psm1**, with no drift between the two.
5. **Quote values containing whitespace** in `CompletionText`; `ListItemText` and the tooltip keep
   the raw value.
6. **Add an end-to-end registration test** driving `TabExpansion2`, not just a unit test of the
   helper.

---

## Code Style

- **PascalCase for all variables, functions, and parameters.** Exceptions: automatic variables
  (`$PSCmdlet`, `$PSItem`, `$_`), preference variables (`$ErrorActionPreference`), boolean/null
  literals (`$null`, `$true`, `$false`), and the module-scope cache variables (`$script:_OER*`).
- **One function per file; filename must equal function name.**
- `[CmdletBinding(SupportsShouldProcess)]` on every state-changing function (create, update, delete).
- **A warning about a deletion or about widened access stands BEFORE the cmdlet's own
  `$PSCmdlet.ShouldProcess`**, so `-WhatIf` shows it and a `-Confirm` prompt is answered with it on
  screen. One needing a value computed only inside the gate moves out with that computation, or is
  named, with its reason, in the allowlist of
  `tests/Unit/Public/WarningBeforeConfirmation.Cohort.Tests.ps1` (outcome warnings, ones depending on
  the operator's answer, ones not about the action); that cohort fails every other `Write-Warning`
  after a public cmdlet's first `$PSCmdlet.ShouldProcess`. In the apply engine a `Sync-OERStructure*`
  handler writes the same warning before `$Caller.ShouldProcess` only when the cmdlet it calls will
  not write it: under `-WhatIf` (cmdlet never called) and, in both modes, for the group PIM MFA /
  authentication-context pair the diff reconciles (`Set-OERGroupPimPolicy`, given the reconciled
  parameters, writes none). The handler's tests run each such case as a plan and as a real run with
  the real cmdlet, from one live state, and hold the same text and exactly one warning in the run.
  `Why: docs/development/rationale.md#warning-before-confirmation`
- `[OutputType([PSCustomObject])]` on every function that returns type-tagged objects.
- **Output tagging is mandatory** -- never return raw hashtables from `Invoke-OERGraphRequest`:
  ```powershell
  $Out = [PSCustomObject]$Response
  $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.SomeTypeName')
  $Out
  ```
- **Never use `*` in `FunctionsToExport`** -- always list explicitly.
- `DefaultCommandPrefix` is NOT used in the manifest. Function names carry the `OER` prefix
  explicitly; adding it would double-prefix to `OEROERFoo`.
- ISO 8601 durations: `[System.Xml.XmlConvert]::ToString([timespan]...)`.
- **Duration vocabulary:** `-Duration` is a raw ISO string, `-DurationDays`/`-DurationHours` are
  whole-unit ints. `ConvertTo-OERDuration` is the sole int-to-ISO encoder, `ConvertFrom-OERDuration`
  the sole ISO-to-int decoder, `Resolve-OERDurationInput` the sole both-forms normalizer. Never
  rename a parameter without leaving the old name as an `[Alias()]`.
  `Why: docs/development/rationale.md#duration-vocabulary`
- **`Test-OERDeclaredProperty`/`Test-OERDeclaredNull` are the single owners of the apply engine's
  declared-value rule.** A property is "declared" when present and not `null`; `""` and `[]` still
  count as declared. Never re-implement `.PSObject.Properties.Name -contains ...` plus a null check
  inline in a `Sync-OERStructure*` handler. `Why: docs/development/rationale.md#declared-property`
- **One output shape, one `ConvertTo-*` owner.** A shape emitted by more than one cmdlet is built in
  a single private `ConvertTo-*` helper, never inline in each caller. A create path routes its
  response through the same converter the read path uses.
- **Property naming:** identifier `<Noun>Id`, display name `<Noun>DisplayName`; a bare noun never
  holds a display name. A historical spelling is an `AliasProperty` (`Update-TypeData -Force` in
  `suffix.ps1`), never a second stored value. An ARM-scoped object (`Resource`, `ResourceGroup`,
  `Subscription`, `ManagementGroup`, `RoleDefinition`) exposes the ARM path as `ResourceId`, never a
  bare `Id`; `RoleDefinition` stores `RoleDefinitionId` with `ResourceId` an `AliasProperty` of it,
  the other four store `ResourceId` directly -- no shape stores the path twice.
  `Why: docs/development/rationale.md#property-naming`
- **Alias declaration order:** in a parameter's `[Alias()]` list the specific `<Noun>Id` precedes
  the generic `Id` (first match in declaration order wins). Two AST cohort suites hold it for
  `-Group` and `-AdministrativeUnit`: `Unit/Public/GroupAliasOrder.Cohort.Tests.ps1` and
  `Unit/Public/AdministrativeUnitAliasOrder.Cohort.Tests.ps1`.
  `Why: docs/development/rationale.md#alias-declaration-order`
- **`-Scope` binds from the pipeline only where the piped OBJECT is assignment-shaped, never where
  it is scope-DEFINING -- a split by object shape, not a blanket rule per cmdlet.** Assignment-shaped (`RoleAssignment` and its PIM siblings) carry `Scope`
  and feed the four cmdlets that bind it: `Enable-`/`Disable-OEREligibleRoleAssignment`,
  `Remove-OERActiveRoleAssignment`/`Remove-OEREligibleRoleAssignment`. `Set-OERRoleAssignment` and
  `Remove-OERRoleAssignment` have NO `-Scope` (they act on `-Id`, which embeds the scope); do not
  add one. Scope-DEFINING (`Resource`, `ResourceGroup`, `Subscription`, `ManagementGroup`,
  `RoleDefinition`) carry only friendly properties, never `Scope` or a bare `Id`, and feed the
  `New-`/`Get-` cmdlets by `Subscription`, `ResourceGroup`, `ManagementGroup`, `ResourceType`,
  `ResourceName`.
  `Why: docs/development/rationale.md#scope-pipeline-binding`
- **`ConvertTo-OERODataFilterValue` is the single owner of OData filter-value escaping:** any Graph
  display-name lookup interpolating a caller-supplied value into a `$filter=... eq '...'` URL must
  escape through it (four deliberate exceptions exist; a new unescaped site is a bug). An operator's
  whole OData expression (`-Filter`, `-GroupFilter`) is never escaped through it;
  `Export-OERInventory -GroupFilter`, ANDed as `securityEnabled eq true and (...)`, is guarded by the
  post-read check that keeps only groups the read shows `securityEnabled` true, never by the
  parentheses. `Why: docs/development/rationale.md#odata-escaping`
- **A resolver on the cohort's list publishes its failure as itself and an ambiguous name as
  `Ambiguous*`, never `*NotFound`; a COHORT check holds that, not a helper.** Decided exception: the
  principal and Azure role definition lookups still publish a failed read as `PrincipalNotFound` or
  `RoleDefinitionNotFound`; never change those ErrorIds. PIM approver lookups follow the rule:
  ambiguous is `AmbiguousApproverName`, a failed lookup is published as itself, `ApproverNotFound`
  means only an approver matching nothing -- in the three policy cmdlets and the three apply
  handlers alike -- told apart by the internal ids `PrincipalUnresolved` and `ApproverUnresolved`
  (published by none) through `Get-OERApproverErrorClass`.
  `Why: docs/development/rationale.md#approver-lookup`
  `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1` runs every call site on its hand-kept
  `$script:GuardCases` list with an ambiguous name and with a 403 (the approver lookups of
  `Set-OERGroupPimPolicy`, `Set-OERDirectoryRoleManagementPolicy` and `Set-OERRoleManagementPolicy`
  included); a new public call site of an ambiguity-refusing `Resolve-OER*Id` helper, an approver
  lookup among them, joins that list. The 403 case narrows to the cmdlet's own record:
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **`Get-OERApproverErrorClass` is the single owner of classifying an approver lookup failure:**
  `Ambiguous` when `Test-OERAmbiguousNameError` says so; `NotFound` when the FullyQualifiedErrorId
  starts, ordinally, with `ApproverUnresolved` or `PrincipalUnresolved`; `Other` otherwise, a null
  record included. The six approver call sites (three policy cmdlets, three apply handlers) switch
  on its answer and keep their own message, target, category and inner exception, so every
  published record stays byte-identical. Never test either
  internal id elsewhere: the cohort in `tests/Unit/Private/Get-OERApproverErrorClass.Tests.ps1`
  fails a string constant naming one as an operand of a comparison operator, an argument of a
  string comparison method or a `switch` clause outside the classifier and the three producers
  (`Resolve-OERPrincipal`, `Resolve-OERApproverInput`, `Resolve-OERDeclaredApprover`); it does NOT
  see an id held in a variable, a command parameter value (`Where-Object ... -like`,
  `Select-String -Pattern`) or a regular-expression method (kept by review).
  `Why: docs/development/rationale.md#approver-lookup`
- **`Resolve-OERReviewerScopeQuery` is the single owner of the access review reviewer scope query
  grammar.** Never re-implement the `/users/` and `/groups/` regex pair inline; `./manager` is
  matched FIRST, always, and an `Unparsed` scope is NOT the same as an empty reviewers collection.
  `Why: docs/development/rationale.md#reviewer-scope-query`
- **`Get-OERAccessReviewCadence` is the single owner of the access review cadence table:** per
  cadence the Graph pattern type and interval (`Weekly` weekly 1; `Monthly`, `Quarterly`,
  `SemiAnnually`, `Annually` absoluteMonthly 1, 3, 6, 12; `OneTime` no pattern), a live pattern read
  back as a cadence, and whether the module can write it back (`Representable`).
  `New-OERAccessReviewRecurrence`, `Resolve-OERAccessReviewChange` and `Get-OERInventory` ask it;
  never spell the interval numbers or an interval `switch` elsewhere. The scan in
  `tests/Unit/Private/Get-OERAccessReviewCadence.Tests.ps1` fails, in any file under `source/` but
  the owner's, an array of exactly 1, 3, 6 and 12, a `switch` clause between those integers and the
  cadence names in either direction, and a `switch` clause on the pattern type; it does NOT see a
  hashtable mapping, an `if` chain, an `-eq` comparison or a table split across variables.
  `OER_COHORT_SOURCE_ROOT` points it at a mutated copy (never set in CI). Cadence NAMES stay with
  `Resolve-OERStructureEnumCasing` and the vocabulary cohort.
  `Why: docs/development/rationale.md#access-review-cadence`
- **`Test-OERGuid` is the single GUID predicate:** never re-implement the canonical GUID regex
  inline. Deliberate exceptions: the wider `-as [guid]` cast in `Get-OERInventory` and `New-OERGroup`
  (do not migrate those two), and the places that read a group's `administrativeUnit` the way
  `New-OERGroup` does -- the created-membership match in `Sync-OERStructureAdministrativeUnit`, and
  in `Test-OERStructureSchema` the unit placement check (Rule 12) and the restricted-unit check
  (Rule 16), which share one local helper.
  `Why: docs/development/rationale.md#guid-predicate`
- **`Test-OERAzureRootScope` is the single owner of whether an Azure role assignment scope addresses
  the root scope `/` (any spelling the ARM transport sends there)**; `Format-OERRootScopeAssignment`
  owns the order, deduplication and list text of the root-scope assignments `Get-OERInventory` and
  `Export-OERInventory` name in their warnings. Azure `roleAssignments` only: never apply it to
  `roleManagementPolicies` or the directory role sections (their `/` is the Entra tenant scope,
  `directoryScopeId`). The export never writes a root-scope assignment, the validator warns on one,
  and `Sync-OERStructureRoleAssignment` skips one before any lookup or request and never prunes the
  root scope.
  `Why: docs/development/rationale.md#root-scope-is-not-in-the-document`
- **`Get-OERAccessReviewTargetMismatch` is the single owner of whether a live access review found by
  display name reviews the access package and assignment policy an `accessReviews[]` entry
  declares**; `Resolve-OERAssignmentPolicyId` owns the assignment policy name lookup it shares with
  creation (`Resolve-OERAccessReviewScopeTarget`). A review that does not is refused with
  `AccessReviewScopeMismatch` before any reviewer lookup or `ShouldProcess`, nothing written to it.
  Never re-implement either check or the policy lookup inline. ONE named deviation, never a second:
  `Get-OERInventory`'s uniqueness check of a review's access package or assignment policy name sends
  the same two lookups as `Resolve-OERAccessPackageId` and `Resolve-OERAssignmentPolicyId` itself,
  so a shared name never raises `AmbiguousName` inside the export; the Context "the export's
  review-reference lookups agree with the resolvers (named deviation)" in
  `tests/Unit/Public/Get-OERInventory.Tests.ps1` holds the two in step.
  `Why: docs/development/rationale.md#access-review-target`,
  `docs/development/rationale.md#roster-identity-and-shared-names`
- **`Resolve-OERStructureRename` is the single owner of the keys of the run's rename map; every
  `accessPackages` entry registers its package there, not only a rename.** An entry that renames
  nothing registers through `-Identified -Id` once it has found the package in its catalog or
  created it there, and through `-Unidentified -Reason` (refused, no ErrorId) until then; it carries
  no previous name. `Sync-OERStructureAccessReview` reads a declared package's name only through the
  map, never in the whole tenant; with `-Include` leaving AccessPackages out every such review is
  refused. Validator Rule 15 refuses a review naming by display name a package two or more
  `accessPackages` entries declare, with or without a rename. Never register a map key outside the
  owner; never let a review resolve a declared package's name past a refusal.
  `Why: docs/development/rationale.md#review-package-in-the-same-run`
- **`ConvertTo-OERCanonicalScope` is the single owner of how a document scope is compared,
  `ConvertTo-OERScopeSplat` of the `sub:`/`subscription:`/`mg:` scope syntax;** never re-implement
  either inline (the first is pure: the offline validator uses it). The validator REFUSES, not
  merges by the helper's trim: a scope ending with `/` (other than `/`) or containing `//`; a path
  with a `.` or `..` segment, `%`, `\`, `?` or `#`; white space at the start or end of the scope or
  of a segment, white space other than a space, or a control character (the
  `mg:`/`sub:`/`subscription:` forms excepted, as `ConvertTo-OERScopeSplat` reads them). A space
  between other characters of a segment is accepted: never widen the white space rule to every
  space. Never drop the rule in favour of the trim, which would make such a scope prune.
  `Why: docs/development/rationale.md#role-assignment-key`
- **`Get-OERScopeSpellingProblem` is the single owner of the two scope spelling rules in the previous bullet** (checks, order,
  message texts) for the `roleAssignments` and `roleManagementPolicies` scopes. The validator's
  `Add-ScopeSlashFinding` and `Add-ScopeSegmentFinding` add one Error per problem it returns and
  decide no spelling; `Get-OERInventory` leaves a role assignment at a scope with any problem out of
  the document (one warning and one `Omnicit.EntraRBAC.UndeclarableScope` record per call), which
  the engine never prunes; `Get-OERSubscriptionHomeTenant` rates such a raw scope (and any other
  non-`mg:` scope with a stray `/`) `Undecided` with `SubscriptionTenantMismatch`, resolving and
  reading nothing, so an `Export-OERInventory -Scope` spelled so is unread. Never decide a scope
  spelling elsewhere. The owner's help is the reference list of the rules and names every text that
  must follow a new one: README.md, the about topic, the two scope descriptions in the schema JSON,
  these two bullets, and `Get-OERInventory`'s words for each rule in the Reason; every other help,
  the bundle README and the prompt point at a list or give an example.
  `Why: docs/development/rationale.md#undeclarable-scope`
- **`Resolve-OERPimActivationConflict` is the single owner of the MFA / authentication-context
  mutual-exclusion rule:** an enabled authentication context and `MultiFactorAuthentication` on
  activation cannot both be in force. Every call site -- the Graph group write path, the apply diff,
  the shared rule-patch builder (`Resolve-OERPolicyRulePatch`) -- takes the DECISION from it and
  applies it in its own idiom; never re-implement it inline. The builder's two callers pass a
  different `-ResolveUnrequestedConflict`: the Azure (ARM) policy path `$true`, since ARM PATCHes the
  full rule set and every apply run re-validates a combination even when this call touched neither
  side; the directory-role (Graph) path `$false`, since it patches one rule at a time and leaves an
  untouched combination alone. `Get-OERPimRulePatchOrder` is the single owner of the
  authentication-context PATCH order this requires, called by `Set-OERGroupPimPolicy` and
  `Set-OERDirectoryRoleManagementPolicy`.
  `Why: docs/development/rationale.md#mfa-authcontext-exclusion`
- **`ConvertFrom-OERGraphApprover` is the single reader of a Graph approver;
  `Resolve-OERApproverInput` / `Resolve-OERGraphApproverSet` are the single owners of the Graph
  approver-side semantics** shared by `Set-OERGroupPimPolicy` and
  `Set-OERDirectoryRoleManagementPolicy`; never re-implement the carry/count/ApproverRequired
  decision inline. `-RequireApproval $false` beside a bound `-ApproverUser` or `-ApproverGroup` (an
  empty list included) is refused with `MutuallyExclusiveParameter` by the three policy cmdlets
  (those two and `Set-OERRoleManagementPolicy`) before any lookup or request, and
  `Resolve-OERGraphApproverSet` throws the same id as a backstop; never let that combination reach a
  request. The apply handlers `Sync-OERStructureGroup` (pimPolicy) and
  `Sync-OERStructureDirectoryRoleManagementPolicy` ask `Resolve-OERGraphApproverSet` too, with the
  live approval rule they read and the parameters their diff binds, and refuse a change needing
  approval by nobody with the cmdlet's own `ApproverRequired` message before their `ShouldProcess`,
  so a `-WhatIf` plan reports the run's row; the cmdlets keep their refusal as the backstop.
  `Why: docs/development/rationale.md#approver-lookup`
- **A public `Set-OER*` cmdlet's own read that decides a written value refuses the call when it
  fails or answers without the value;** never fall back to a parameter default, a declared-only
  write or a warning. In `Set-OERGroupPimPolicy` the two duration reads and the two MFA /
  authentication-context pair reconcile reads publish a thrown read as itself; the approval rule
  read refuses a thrown read as `ApprovalRuleReadFailed`; all five refuse a read answering without
  the value with `PimRuleValueUnknown`, before `ShouldProcess` and every PATCH -- for the approval
  rule only a read returning NO rule (a rule with no stage still takes `New-OERPimRuleSet`'s
  defaults: the documented "no stage yet" case). Two reads only warn, by design, since neither
  decides a written value: the put-back read of the pair's first half (a failure only loses the
  put-back; it warns before any PATCH and writes no default) and the authentication context
  validation read (a failure skips the validation). The apply engine reaches the pair reads when its
  diff binds one half; its row is then `Failed`. It never reaches the duration reads: its diff binds
  both halves of an expiration pair, and when the half the document leaves out has no live value (the
  read gave none, or its `maximumDuration` is not a positive whole number of days) and the declared half does not
  already match, `Resolve-OERGroupPimPolicyChange` names the pair in `UnknownLiveValues`, binds
  neither half, and `Sync-OERStructureGroup` refuses that access type with `PimRuleValueUnknown`
  before `ShouldProcess` -- never a default. Known and NOT fixed, outside this cmdlet (unmeasured): a
  successful read lacking a key makes `Set-OERAccessPackageAssignmentPolicy` write the body builder's default,
  and an empty Azure Resource Manager body makes `Set-OERResourceGroup` send an empty location.
  `Why: docs/development/rationale.md#a-set-cmdlets-own-read-decides-a-written-value`
- **`Send-OERPimRulePatch` is the single owner of sending a Microsoft Graph PIM rule set, one PATCH
  per rule**, including the pair put-back (when Graph accepts the first rule of the MFA /
  authentication-context pair and rejects the second, the first is PATCHed straight back to its
  live version) and the rule that no warning is written between the first PATCH and the last put-back --
  the helper returns its messages, the caller writes them after it returns. Called by
  `Set-OERGroupPimPolicy` and `Set-OERDirectoryRoleManagementPolicy`, which confirm first and order
  the rules with `Get-OERPimRulePatchOrder`. Never PATCH a rule from either cmdlet directly; never
  write a warning inside the helper. Held by the AST check in
  `tests/Unit/Private/Send-OERPimRulePatch.Tests.ps1` and, for the caller-side half (messages only
  after the last request), by the `-WarningAction Stop` tests in
  `tests/Unit/Public/Set-OERGroupPimPolicy.Tests.ps1` and
  `tests/Unit/Public/Set-OERDirectoryRoleManagementPolicy.Tests.ps1`, in a `try` and in a script
  with no `try`; `tests/QA/requiredscope.tests.ps1` counts a call to it as a Graph write by the
  caller (the helper carries no path literal). `Set-OERGroupPimPolicy`'s warning for a split
  `-Confirm` answer to the pair is written after the helper returns and after its messages, by the
  same rule.
  `Why: docs/development/rationale.md#pim-rule-pair-put-back`
- **`Test-OERScheduleRequestFailed` is the single owner of which PIM schedule request status is an
  error: the Failed family -- `Failed`, `FailedAsResourceIsLocked` and any later status starting
  with `Failed`, compared case-insensitively -- and nothing else** (`Revoked` is a removal's
  success; `Denied`, `Canceled` and the `Pending*` values are not errors). Called by the twelve
  cmdlets that send a schedule request -- `Add-`/`Remove-OERGroupEligibility`, `New-`/
  `Remove-OEREligibleDirectoryRoleAssignment`, `New-`/`Remove-OERActiveDirectoryRoleAssignment`,
  `New-`/`Remove-OEREligibleRoleAssignment`, `New-`/`Remove-OERActiveRoleAssignment`, `Enable-`/
  `Disable-OEREligibleRoleAssignment` -- and by the two new-group replication waits in
  `Sync-OERStructureGroup`. A cmdlet emits the request object FIRST, then writes the non-terminating
  `EligibilityRequestFailed` (group, directory role and Azure eligibility requests) or
  `AssignmentRequestFailed` (active assignment, activation and deactivation requests), so a caller
  under `-ErrorAction Stop` still gets the object. Never compare a status to a `Failed` literal
  elsewhere. The cohort check in `tests/Unit/Private/Test-OERScheduleRequestFailed.Tests.ps1`
  derives its cohort from the files (every `source/Public` cmdlet with a string matching
  `ScheduleRequests`; the twelve above are also a control the derivation must still find) and holds
  that each calls the owner and that no other file under `source/` compares a status to a `Failed`
  literal in the shapes it scans. The derivation does NOT see a path built at run time, a path in a
  Private helper (`Send-OERNewGroupEligibilityRequest`) or a file outside `source/Public`; a cmdlet
  that only reads a schedule request resource would join the cohort and fail it (narrow the
  derivation, never hand-list an exemption). The check does NOT hold the two engine waits;
  `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` does.
  `Why: docs/development/rationale.md#failed-schedule-request`
- **`Get-OERCloudEndpoint` is the single owner of the cloud-to-endpoint table:** every Graph
  resource/audience, Graph service root, ARM resource/host and authority (STS) host for a sovereign
  cloud is read from it, never hardcoded a second time. `source/Private/Invoke-OERArmRequest.ps1`
  keeps one documented public-cloud fallback for the no-auth-state case, exempted by name.
  `tests/QA/sourcehygiene.tests.ps1` machine-checks it like the other single-owner rules above.
  `Why: docs/development/rationale.md#sovereign-clouds`
- **`Get-OERDerivedMailNickname` is the single owner of the mail alias `New-OERGroup` derives from a
  display name** (every character outside A-Z, a-z, 0-9, '.', '_' and '-' removed). `New-OERGroup`
  refuses an empty derived alias, or one over 64 characters, with `DerivedMailNicknameInvalid`;
  `Test-OERStructureSchema` compares a renamed group's `mailNickname` with the alias derived from
  its previous name. Never re-implement the derivation inline.
  `Why: docs/development/rationale.md#mail-nickname`
- **`Test-OERNamingStandardName` is the single owner of the naming rules, their order and Detail
  texts; `Read-OERNamingStandard` of reading and refusing the naming standard file;
  `Get-OERNamingStandardSchemaJson` of its schema.** `Test-OERStructureSchema` (Rule 17) adds one
  Warning per object and broken rule, only when `Test-OERStructure -NamingStandard` hands it a
  standard; `Invoke-OERStructure` never passes one (a naming finding is never an Error; applying a
  document is unchanged). Patterns match the whole text; values compare ordinally. A file the reader
  refuses is `InvalidNamingStandard`, once, with no document read or validated. The reader checks
  the file by hand, never via `Test-Json`. `docs/examples/naming-standard.schema.json` is the schema
  function's output, held identical by a test, never edited by hand. Never re-implement a rule, a
  Detail text or the file's validation elsewhere.
  `Why: docs/development/rationale.md#naming-standard`
- **`Test-OERJsonDateKindSupport` is the single owner of whether the running `ConvertFrom-Json` has
  `-DateKind`:** one `Get-Command` of the module-qualified
  `Microsoft.PowerShell.Utility\ConvertFrom-Json`, true when it has the parameter (PowerShell 7.5 or
  later).
  `Read-OERStructureDocument` adds `-DateKind String` to its parse when true, so a structure
  document reaches the validator and the engine as written; on 7.2-7.4 `Test-OERStructureSchema`
  refuses every date value the parse made (Rule 2b), no field exempted. Never ask the question
  elsewhere or "repair" a parsed date into text. A test mocks it in module scope to run the 7.2-7.4
  path on a newer PowerShell. `Why: docs/development/rationale.md#structure-document-text`
- **`Test-OERHostCanConfirm` is the single owner of whether the host can show a confirmation prompt
  that is decidable beforehand; `Test-OERConfirmPromptFailure` of whether a caught record is a
  `ShouldProcess` that failed because the host could not ask.** The first is
  `$Host.Name -ne 'Default Host'`, the only host found safely decidable; when false,
  `Invoke-OERStructure` refuses with `ConfirmationUnavailable`, before the sign-in, a document whose
  run would prompt (not `-WhatIf`, `$ConfirmPreference` not `None`). The second is true only for a
  `MethodInvocationException` whose inner exception is a `HostException`,
  `PSInvalidOperationException` or `NullReferenceException` (or derives from one) and whose message
  names `ShouldProcess` (ordinal); the engine's two handler-error catches word the Detail through
  it. Never decide either elsewhere. `Why: docs/development/rationale.md#confirmation-unavailable`
- **`Select-OERManagedDirectoryRoleAssignment` is the single owner of which live directory role
  assignment the apply engine may match or prune** (tenant scope, `memberType` Direct, Active only
  `assignmentType` Assigned); `Get-OERTokenObjectId` of reading the signed-in identity's object id
  (the token's `oid` claim, delegated and app-only alike; never `/me`). Never re-implement either
  inline. `Why: docs/development/rationale.md#directory-role-assignments`
- **`Test-OERGroupPimInUse` is the single owner of whether a group uses PIM for Groups:** PIM
  eligibility, or a PIM-for-Groups policy with a non-empty `lastModifiedDateTime`,
  `lastModifiedBy.id` or `lastModifiedBy.displayName`. `Get-OERInventory` exports `pimPolicy` only
  for a group found in use; a criterion it could not read, or a "not in use" reached while the
  group's eligibility was unread, omits `pimPolicy` AND reports it unread. `Sync-OERStructureGroup`
  warns, never blocks, before a changed policy onboards an existing group. Never re-implement the
  check inline. The criterion is documented, not yet measured live, and misses a group used only
  through PIM active assignments. `Why: docs/development/rationale.md#pim-in-use-criterion`
- **`Test-OERGroupOnPremisesSynced` is the single owner of whether a live group is synchronized from
  on-premises:** `OnPremisesSyncEnabled` (Graph's `onPremisesSyncEnabled`, carried by
  `ConvertTo-OERGroup`) is the boolean true; false (no longer synced) and empty (never synced, or
  source of authority converted to the cloud) are not. `Sync-OERStructureGroup` writes nothing to
  such a group, deciding on its LIVE read, never the document's `onPremisesSynced` key: every
  property, member, owner, eligibility or `pimPolicy` change is `Skipped` with no `ShouldProcess`
  call, one warning per item; each prune candidate is withheld
  (`ConvertTo-OERPruneWithheldResult -SyncedGroup`). `Get-OERInventory` writes the document key
  `onPremisesSynced` only as true, `Export-OERInventory` the roster flag (a boolean on every row)
  from the same predicate; the key is information only, never sent. Never read
  `OnPremisesSyncEnabled` elsewhere: the cohort check in
  `tests/Unit/Private/Test-OERGroupOnPremisesSynced.Tests.ps1` holds the member-access form
  (`.OnPremisesSyncEnabled` as a constant member name, outside `ConvertTo-OERGroup` and the helper);
  it does NOT hold a read through `Select-Object`, `Where-Object` or `PSObject.Properties[...]`
  (kept by review). `Why: docs/development/rationale.md#synced-groups`
- **`Get-OERInventoryGroup` is the single reader of the inventory's Groups section.**
  `Get-OERInventory` calls it in full mode (one `Get-OERGroup` call with the three include switches;
  output unchanged). `Export-OERInventory` calls it with `-RelevantOnly` unless
  `-AllGroupsDetailed`, always with `-ExcludeSharedName`, `-SecurityEnabledOnly` and
  `-ProgressActivity`: relevance first, from the group's PIM eligibility, then
  `Test-OERGroupPimInUse`, so a group found not relevant costs exactly two requests and is never
  read further; a group whose relevance could not be read is read in full. The export's keep filter
  on the projections stays the final say. The reader never writes an error record; it returns
  `Groups`, `Unread`, raw `Causes`, `PimLeftOut`, `DynamicMembers`, `SharedNames`. Both callers
  catch a reader that stops and report the section unread, never empty. Never read the Groups
  section, or decide relevance before a full read, elsewhere. **A dynamic group's `members` is an
  EXPLICIT null, never an omitted key and never a list:** the null is no gap, so it is named unread
  nowhere, and a failed read of those members records no cause. Members are still read, for a group read
  in full, and counted per group in `DynamicMembers` (beside `PimLeftOut`), so the roster keeps a
  `memberCount`. `Sync-OERStructureGroup` writes no aggregate member row for an explicit null; a
  declared list, `[]` and an omitted key keep their rows. Never write a dynamic group's members or
  name their failed read unread. `Why: docs/development/rationale.md#export-group-selection`
- **`Get-OEROrderedInventoryEntry` is the single owner of the order the inventory writes its lists
  in:** a group's `members`, `owners`, `eligibility` and an administrative unit's `members`. Text by
  `[System.StringComparer]::OrdinalIgnoreCase`, ties by `[System.StringComparer]::Ordinal`, so the
  order is total and culture independent; eligibility by `principal`, `accessType`, `durationDays`
  (absent first, then ascending), `id`. `Get-OERInventoryGroup` orders the three group lists,
  `Get-OERInventory` the unit members; never order such a list elsewhere. Its LINQ calls take
  generic arguments by INFERENCE, never written out (an explicit type argument is PowerShell 7.3
  syntax, a parse error under the 7.2 floor). CI runs a current PowerShell only, so nothing but the
  helper's own test (an AST check of its file) would show it.
  `Why: docs/development/rationale.md#export-group-selection`
- **`Read-OERGroupCollection` is the single owner of the three per-group collection reads
  `Get-OERGroup` attaches and the inventory's group reader uses** (members, owners, PIM eligibility)
  **and of wording their failure** exactly as `Get-OERGroup` publishes it. It returns the read or
  its failure, never an error record; `Get-OERGroup` and `Get-OERInventoryGroup` call it and neither
  reads one of the three inline. `Get-OERGroupRelation` stays the single reader of the members and
  owners requests: `Read-OERGroupCollection` calls it, `Get-OERGroupMember` calls it directly.
  `Why: docs/development/rationale.md#export-group-selection`
- **`Get-OERGroupPimHeldAccess` is the single owner of which PIM-for-Groups instance holds a
  member's or owner's access:** held unless `assignmentType` is `assigned` (any letter case) AND
  `endDateTime` is empty; every eligibility instance is held as Eligible; `memberType` is never
  consulted; access is matched per access type. `Read-OERGroupPimAssignment` is the single reader of
  `assignmentScheduleInstances` (`ResourceTypeNotSupported` is an empty answer, a thrown failure is
  unread); `Read-OERGroupPimHold` is the apply engine's one read of the hold state. The export
  leaves out of `members`/`owners` a member or owner held by an assignment kind (eligibility alone
  decides only when the assignment read failed); the engine adds and prunes none, Eligible included.
  Never re-implement the rule inline.
  `Why: docs/development/rationale.md#pim-activation-is-not-membership`
- **`Format-OERUnreadCauseClause` is the single owner of the causes clause of an inventory's
  `InventoryPartial` message** (deduplication with the failing object's id normalised away, the cap,
  the wording); `Get-OERSharedNameCause` of the text for objects left out because two of them share
  a name, carrying how many live objects share it (`-Count`). The clause is built by
  `Get-OERInventory` and `Export-OERInventory`, the shared-name text by `Get-OERInventory` and
  `Get-OERInventoryGroup`; never word either inline. A cause registered with a BLANK `Target` is
  keyed on its full text, not a normalised one: shared-name causes carry none, so two names sharing
  one count are two causes and one name is stated once.
  `Why: docs/development/rationale.md#export-group-selection`,
  `docs/development/rationale.md#roster-identity-and-shared-names`
- **`Get-OERGroupNameIndex` is the single owner of which groups in the tenant carry a display
  name:** from the groups given (`-Group`, the export's roster) with no request, or from ONE paged
  listing `v1.0/groups?$select=id,displayName&$top=999`, read by `Get-OERInventory` at most once per
  invocation and by `Export-OERInventory` at most once per export through its run context. It never
  throws and never writes an error record; it returns `Read`, `IdsByName` (a name, compared ignoring
  letter case, to the lower-cased ids carrying it; `$null` when the listing failed, never an empty
  index) and `Message`. **`Get-OERGroupReference` is the single owner of how the export names a
  group it references as the principal of a role assignment or a directory role assignment:** its
  display name only when the index was read and exactly this group carries the name, else its object
  id, written with `principalType` `Group` in `roleAssignments` and `directoryRoleAssignments`. A
  group named as an eligibility principal, a reviewer, a catalog resource or a resource role is
  outside it and keeps its display name. Never re-implement either inline.
  `Why: docs/development/rationale.md#roster-identity-and-shared-names`
- **`Export-OERInventory` is the only command that sets and clears the export run context
  (`$script:_OERInventoryRunContext`),** the one object its `Get-OERInventory` calls share: group
  name index, principal names the group read looked up, `PrincipalNameCache`, deleted items answers,
  role assignment principals that could not be read, subscription home tenant answers
  (`SubscriptionTenant`). `Get-OERInventory` fills its members; `Get-OERDeletedPrincipalStatus`
  fills through the `PrincipalStatus` dictionary it is handed;
  `Get-OERSubscriptionHomeTenant -Cache` fills `SubscriptionTenant`, which the export hands to
  `Resolve-OERInventoryScopeTree -Cache` and `Get-OERInventory` to the owner the same way (a context
  without the member reads as none). Created in ONE place, directly before the export's Entra ID
  `Get-OERInventory` call, with `Owner` set to its own `$MyInvocation`; set back to `$null` with a
  plain statement directly after the Azure walk, never in a `finally`. `Get-OERInventory` reads it
  once per invocation and uses it only while its `Owner` is the `InvocationInfo` of a frame of the
  current call stack (`Microsoft.PowerShell.Utility\Get-PSCallStack`, compared by reference), else
  behaves standalone. Never read or write it elsewhere, never replace it by a public parameter; add
  a member to it, not a second module variable. `PrincipalNameCache` is a `[hashtable]`, id to name,
  created by the export before its group read and handed, the very same object, to
  `Get-OERInventoryGroup -PrincipalNameCache` and to the context; `Get-OERInventory` takes it, read
  through `PSObject.Properties` as `SubscriptionTenant` is, only when the context is its own and the
  member is a `[hashtable]` (its consumers bind one and call `ContainsKey`), else keeps its own.
  Known limit: a lookup that failed in the group read is not retried (the map
  `Resolve-OERPrincipalName` returns answers the id as the name).
  `Why: docs/development/rationale.md#export-run-context`
- **`Get-OERDeletedPrincipalStatus` is the single read of `directory/deletedItems`;
  `Resolve-OERPrincipalName -Detailed` is the lookup that tells a principal the directory returned
  from one it did not return and from one whose lookup failed.** Only the `roleAssignments` section
  of `Get-OERInventory` uses both; `-Detailed` alone has two more callers, neither reading the
  deleted items: the `administrativeUnits` section's scoped role type lookup and
  `Get-OERServicePrincipalAccess`. In `roleAssignments` a principal not returned is written by its
  object id with `principalStatus` `Deleted` or `Unresolved`; a failed lookup or deleted items read
  is never a fact: it is named unread (`.../principal`, `.../principalStatus`; the second still
  written `Unresolved`, never as a principal that exists). The read never throws, never writes an
  error record, caches only an answer that was read. `Sync-OERStructureRoleAssignment` looks no
  principal up for an entry that declares `principalStatus` and never creates its assignment
  (`Skipped`, no `ShouldProcess`). The other sections keep `Resolve-OERPrincipalName`'s unchanged
  default map. Never read `directory/deletedItems` elsewhere.
  `Why: docs/development/rationale.md#unresolved-principals`
- **`Get-OERServicePrincipalAccess` is the single reader of what `servicePrincipalAccess.json`
  holds:** the service principal list with `$expand=appRoleAssignments` (application permissions,
  read client side), the service principal and app registration lists with `$expand=owners(...)`,
  and one paged `oauth2PermissionGrants` list whose users it looks up with ONE
  `Resolve-OERPrincipalName -Detailed` call. An object whose expanded collection holds 20 or more
  entries, or one of whose expanded entries lacks the id its row needs (an app role assignment
  without `resourceId` or `appRoleId`, an owner without `id`), is read again in full with a paged
  read of its own; an app role assignment the full read still returns without them leaves only
  `applicationPermissions` unread. A part is read whole or not at all: any failure inside it leaves
  it `$null`, never `[]`, and names it `servicePrincipalAccess/<part>`; the grants are not read when
  the service principal list was not. It never throws, never writes an error record or a warning,
  and sends GET requests only, with no `-Method` (the requiredscope gate would judge every literal
  of a function that writes as a write). `Export-OERInventory` calls it once, only with
  `-IncludeServicePrincipalAccess`; nothing reads the file back: never add its content to
  `inventory.json`, `schema.json` or the apply engine. **`ConvertTo-OERPrincipalType` is the single
  owner of mapping a Microsoft Graph object type to the document's principal type** (`User`, `Group`
  or `ServicePrincipal`, the `#microsoft.graph.` prefix optional, letter case ignored; anything else
  `$null`, never guessed), used for the owner rows and for the `principalType` `Get-OERInventory`
  writes on an `administrativeUnits[].scopedRoles` row whose principal the directory returned.
  `ConvertTo-OERDirectoryRoleAssignment` keeps its own earlier mapping (a named exception, not a
  precedent); never map a Graph type inline elsewhere. The validator holds the scoped role
  `principalType` to the enum and `Read-OERStructureDocument` canonicalises it;
  `Sync-OERStructureAdministrativeUnit` never uses it to match or write.
  `Why: docs/development/rationale.md#service-principal-access`,
  `docs/development/rationale.md#scoped-role-principal-type`
- **A group that uses PIM for Groups in a restricted management administrative unit is a Warning,
  never an Error or a refusal:** `Export-OERInventory` warns before its `ShouldProcess` (with
  `Groups` and `AdministrativeUnits` included, from what it read, with no request) and lists the
  groups in the bundle README; validator Rule 16 warns on a document that places such a group in a
  restricted unit it declares. State the limit as Microsoft Learn documents it, as fact, and state
  what Microsoft Graph answers to the engine's PIM writes for such a group as unmeasured until a
  live run measures it. `Why: docs/development/rationale.md#restricted-unit-pim`
- **`Test-OERRolePolicyModified` is the single owner of whether an Azure role management policy has
  been changed:** the list row's `policyAssignmentProperties.policy` (carried as `PolicyMetadata` by
  `Get-OERRoleManagementPolicyForScope`, with no request of its own) with a non-empty
  `lastModifiedDateTime`, `lastModifiedBy.id` or `lastModifiedBy.displayName`, the three fields
  `Test-OERGroupPimInUse` reads. An empty `lastModifiedBy` object is not a change,
  `isOrganizationDefault` is no signal, and a row with no policy object returns `$null`, which a
  caller never reads as "not changed". Never re-implement the check inline.
  `Why: docs/development/rationale.md#export-role-policy-selection`
- **`Select-OERInventoryRolePolicy` is the single owner of which Azure role management policies
  `Export-OERInventory` keeps without `-AllRolePolicies`** -- pure, every side keyed on the
  canonical scope and the role definition guid. Kept: a policy whose role has a role assignment or
  an eligibility EXACTLY at its scope, or that has been changed. One that cannot be judged (no
  policy object, no role definition id, or a scope whose role assignment or eligibility read failed)
  is kept AND its scope named, as `roleManagementPolicies/role selection at <scope>` last in
  `IncompleteReads`, with an `InventoryPartial` clause of its own. Anything else is omitted. The
  export reads the candidates through `Get-OERInventoryRolePolicy` (the same one paged list and
  converters as `Get-OERInventory -AllRolesAtScope`) and the assignments with one extra
  `Get-OERRoleAssignment -AtScope` list per scope, read before the policy list; `-AllRolePolicies`
  makes the per-scope call earlier versions made and selects nothing. Never decide the selection elsewhere, except
  the export's fallback when the selection itself stops, which keeps every candidate and names each
  distinct scope among them as not judged; never drop a policy that cannot be judged, never add a
  request per policy. `Why: docs/development/rationale.md#export-role-policy-selection`
- **`Resolve-OERTenantDomain` is the single owner of the module's one network call outside the
  Microsoft Graph and Azure Resource Manager transports** -- the deliberately unauthenticated OpenID
  discovery lookup of a tenant named by domain at the cloud's Microsoft Entra ID authority, the host
  read from `Get-OERCloudEndpoint` -- and the only caller of `Invoke-RestMethod`. The call carries
  `-Uri`, `-Method`, `-TimeoutSec` and `-ErrorAction` and nothing else: never a header, a credential
  or a splat, never a second sender. It caches a tenant ID per cloud and lower-cased domain for the
  process, never a failure. Its place in the sign-in and the refusals: see **Authentication
  Architecture**. `Why: docs/development/rationale.md#switching-tenants-in-one-process`
- **`Set-OERSessionUncertain` is the single owner of the session-uncertain marker**
  (`$script:_OERSessionUncertain`), called only by `Initialize-OERAuth`, `Connect-OER` and
  `Disconnect-OER` (see **Authentication Architecture**).
  `Why: docs/development/rationale.md#a-refused-sign-in-leaves-the-session-uncertain`
- **`Get-OERDocumentTenantMismatch` is the single owner of the comparison of a structure document's
  `tenantId` with the tenant `Invoke-OERStructure` acts in, and of the `DocumentTenantMismatch` id
  and message** (the refusal itself: see **Authentication Architecture**);
  **`Get-OERInventoryTenantId` is the single owner of which tenant an export's `inventory.json`
  names** -- the Graph token's granted tenant (`TokenTenantId`) when it is a GUID, never the tenant
  as named, otherwise no key at all, with no warning. `Get-OERInventory` and `Export-OERInventory`
  call it in `begin`, directly after their own sign-in (the export not at all when that sign-in was
  refused). It is also the second term of the bundle folder's label: the export names the folder,
  and the summary's `TenantId`, after the tenant the session names unless that is blank or
  `organizations` (letter case ignored), else after that granted tenant ID, else after `-TenantId`
  as given, else `tenant`. `Invoke-OERStructure` calls the comparison twice per document: before the
  sign-in whenever `-TenantId` is bound (the owner compares only a canonical GUID there and leaves
  any other name -- a domain, `organizations` -- to the second call; keep that GUID test in the
  owner, never in the caller), and after the sign-in against `TokenTenantId` (and `ArmTokenTenantId`
  when ARM is used), directly after the snapshot is taken again and before anything is read or
  written for the document. A present `tenantId` that is not a canonical GUID, `null` included,
  fails validation; a document without the key is applied exactly as before. Never sign in WITH the
  document's tenant, never compare it inline, never read a missing or non-GUID token tenant as a
  match. Gate 10 holds the comparison to `Invoke-OERStructure`, in a row with an `It` of its own;
  nothing machine-checks who calls `Get-OERInventoryTenantId`.
  `Why: docs/development/rationale.md#a-document-names-the-tenant-it-was-exported-from`
- **`Get-OERSubscriptionHomeTenant` is the single owner of whether a subscription's home tenant is
  the session's tenant:** ARM's subscription `tenantId` (Subscriptions - Get or List, api-version
  `2022-12-01`) against `Get-OERInventoryTenantId`, ignoring letter case, only when both are
  canonical GUIDs. Called only by `Resolve-OERInventoryScopeTree`, `Invoke-OERStructure` and
  `Get-OERInventory` (gate 10), never by another public cmdlet. `Get-OERInventory` checks each given
  `-Scope` and `-Subscription` (as `sub:<value>`) ONCE per invocation, before the first read of
  RoleAssignments or RoleManagementPolicies; `-ManagementGroup` is never checked. The check reads
  through the ARM transport, so `begin` asks for the ARM token in its one `Initialize-OERAuth` call,
  exactly as `-IncludeARM` does, whenever RoleAssignments, or RoleManagementPolicies with exactly
  one of `-Role`, `-CommonRoles`, `-AllRolesAtScope` (the rule that section reads by, from the one
  `$RoleSources` list), is included with a non-blank `-Scope` or `-Subscription`; a
  `-ManagementGroup` alone keeps the readers' acquisition on first use, and a call with neither
  section asks for none. A foreign subscription is read for nothing: each included section empty,
  the owner's `SubscriptionTenantMismatch` record written once (the first foreign verdict's), after
  the inventory, not unread. An undecided one is read for nothing too, each included section named
  unread by its own name through `InventoryPartial`. Inside an export the answers are shared through
  the run context's `SubscriptionTenant`, which the tree fills (`-Cache`, the listed facts
  included): no extra request. `Export-OERInventory`'s walk enters only a subscription of the
  session's tenant, warns once for one of another tenant (and names it in its README), and names one
  it cannot decide in `IncompleteReads` (partial). The engine checks once per subscription and
  document, before the first read or write of a `roleAssignments` or `roleManagementPolicies` scope
  there, and refuses the entry `Failed` with `SubscriptionTenantMismatch` (or the read's or the
  resolver's own record when that failed), reading no role assignment or policy there, writing
  nothing, never pruning there. Never decide a subscription's tenant elsewhere.
  `Why: docs/development/rationale.md#home-tenant-subscriptions`

---

## CRITICAL: ASCII-Only Source Files

Authored `.ps1` files are UTF-8 **without BOM** and **must contain only ASCII characters** -- no
em-dashes, box-drawing characters, smart quotes or curly apostrophes. A non-ASCII character in a
BOM-less file fails the QA `PSUseBOMForUnicodeEncodedFile` PSScriptAnalyzer gate. The only exception
is a helper file verbatim-copied from a source that already carries a UTF-8 BOM. Use `--` (two
hyphens) for em-dash contexts in comments and help text, and straight quotes `'` and `"` only.
`Why: docs/development/rationale.md#ascii-only-source-files`

---

## Error Handling

- **Non-terminating errors** in public functions: `$PSCmdlet.WriteError()` followed by `return` (in a
  `process` block, single-item cmdlets) or `continue` (inside a `foreach` loop over multiple items):
  `try { ... } catch { $PSCmdlet.WriteError($Err); return }`, with `continue` in place of `return` in
  a loop. Never use bare `throw` in a public function -- it terminates the pipeline and defeats
  `-ErrorAction SilentlyContinue`.
- **Private pure helpers** such as `Resolve-OERName` may `throw` on caller error (they have no
  `$PSCmdlet`); the caller catches and routes it.
- **Every Graph or ARM `catch` block** must call `Remove-OERErrorRecord -Record $PSItem` as its
  **first** statement. The older `$null = $Error.Remove($PSItem)` idiom looks equivalent but is
  **inert** -- it never removed anything. `Why: docs/development/rationale.md#bearer-scrub`
- **`Write-CmdletError -Message`** expects an `[Exception]`, not a string: wrap bare strings in
  `[System.Exception]::new('message')`.
- **`ErrorDetails` must be set via the constructor** (plain string assignment is silently ignored in
  some PowerShell versions):
  `$Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Your message here.')`.
  `Why: docs/development/rationale.md#error-handling`

---

## Graph Requests

**All Graph calls go through `Invoke-OERGraphRequest`.** Only the wrapper calls raw
`Invoke-MgGraphRequest` (with `-Verbose:$false -ErrorAction Stop`); never call it from any other
function. The wrapper owns bearer-token scrubbing, ACRS claims-challenge retry, token-rejected retry
and structured error conversion. `Why: docs/development/rationale.md#graph-wrapper`

`Connect-MgGraph -Environment` is passed only when the session's cloud is not `Global` (the
public-cloud path stays byte-identical); the environment name comes from `Get-OERCloudEndpoint`,
never a literal. `Why: docs/development/rationale.md#sovereign-clouds`

**PIM-for-Groups is deliberately pinned to the Graph `beta` endpoint.** All seventeen call sites, in
twelve source files, route through the private `Get-OERPimGroupsGraphPath`, which owns the version
constant: never hardcode `beta/` at a call site, change the constant in the helper.
`tests/Unit/Private/Get-OERPimGroupsGraphPath.Tests.ps1` names every one of those files and fails
when a new caller is not added to its list. The eligibility paths and the four policy paths migrate
as ONE unit. Beta availability in US Government and China clouds is not established -- a standing
risk, not a bug. `Why: docs/development/rationale.md#pim-beta-pin`,
`docs/development/rationale.md#sovereign-clouds`

**Microsoft Entra directory-role PIM policies are the opposite: pinned to Graph `v1.0`.** Every
directory-role policy path is a string literal starting with `v1.0/`, routed through
`Invoke-OERGraphRequest`, and never through `Get-OERPimGroupsGraphPath` -- that helper owns the
PIM-for-Groups `beta` constant only, and a directory-role call site must not borrow it.

---

## ARM Requests

**All ARM calls go through `Invoke-OERArmRequest`.** The module deliberately does NOT use
`Connect-AzAccount`/`Invoke-AzRestMethod`. `Initialize-OERAuth -IncludeARM` caches the ARM bearer
token as a SecureString; the wrapper sends it directly, materializing the plaintext only at the
request boundary and clearing it in a `finally`. The ARM host is read from the session's cloud
(`Get-OERCloudEndpoint`'s `ArmResource` field via `-Environment`), never hardcoded to public-cloud
ARM; a state without `ArmResourceUrl` takes its cloud's ARM host from `Get-OERCloudEndpoint`.
`Invoke-OERArmRequest` keeps `https://management.azure.com` as a documented fallback for a call made
before any auth state exists -- do not delete it. The wrapper never sends a request without an ARM
token: it refuses it after its two gates, before the send, with the existing
`ArmTokenAcquisitionFailed`, so the no-state fallback is refused too.
`Why: docs/development/rationale.md#arm-requests`

A 429, and a 503 carrying `Retry-After`, are retried with a bounded backoff whose constants mirror
the Graph wrapper's name for name (`ThrottleWaitBudgetSeconds` 300 per request/page,
`CallDeadlineSeconds` 900 per call, `ThrottleRetryHardCap` 10, single waits clamped to 1..120 s). The
bounds are enforced at the decision to wait, never by stopping a paging loop part-way -- which is
also the LIMIT of what `CallDeadlineSeconds` bounds: it caps a THROTTLED call only, and a
never-throttled `-All` walk never consults it. The two transports are deliberately MIRRORED, never
shared -- their error shapes differ, and a helper covering both would fit neither; correct a wrong
comment in both files together. The ARM `Retry-After` header is read in exactly one place,
`Get-ArmRetryAfterHeaderValue`, and the header collection never leaves the wrapper. That is a
convention kept by review, not a machine-checked rule: no gate in `tests/QA/sourcehygiene.tests.ps1`
enforces it, and none should be added that checks something weaker than the rule (a gate green on a
second header read elsewhere is guard-shaped but inert). Keep it by review.
`Why: docs/development/rationale.md#arm-requests`

`roleDefinitionId` in a role assignment body is always the FULL ARM resource id, never a bare GUID.
Pinned api-versions, paging and retry semantics: `Why: docs/development/rationale.md#arm-transport`;
sovereign-cloud ARM endpoints: `Why: docs/development/rationale.md#sovereign-clouds`

**`Get-OERManagementGroupParent` is the single owner of the Entities - List call**
(`POST /providers/Microsoft.Management/getEntities`, api-version `2020-05-01`, `$view=GroupsOnly`,
`-All`), which `Get-OERManagementGroup` sends at most once per list to fill the parent of every
listed group (the Management Groups - List answer carries none). The inventory walk
(`Resolve-OERInventoryScopeTree`) lists management groups through `Get-OERManagementGroupList`,
converts them itself and never calls `Get-OERManagementGroup` without `-Name`, so the parent read
cannot add a failure mode to an export. `Get-OERManagementGroupList` is NOT the single owner of the
list call (`Resolve-OERScope` still sends its own): never describe it as one.
`Why: docs/development/rationale.md#management-group-parents`

---

## PSScriptAnalyzer

The QA gate requires **0 findings** per function file. A targeted suppression is acceptable for a
known false positive (e.g. `PSReviewUnusedParameter` on a parameter-set discriminator switch) if and
only if a `Justification` string is provided. Never suppress a rule that hides a real bug.

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MySwitch',
    Justification = 'Switch is a parameter-set discriminator; ParameterSetName is used instead.')]
```

`Why: docs/development/rationale.md#psscriptanalyzer`

---

## Testing Conventions

- **Tests are written in Pester 5 syntax** under `tests/Unit/{Private,Public}/`, one `*.Tests.ps1`
  per source file. The QA gate (`tests/QA/module.tests.ps1`) requires a unit test file for every
  exported function. `Why: docs/development/rationale.md#testing-conventions`
- **Import by module name, not by path**, in every `BeforeAll` (importing by path breaks the Sampler
  coverage measurement, which targets the built module). Every unit test file that imports the module
  starts with this root shape (the tripwire lines are explained below), and
  `tests/QA/testhygiene.tests.ps1` fails a file without them:
  ```powershell
  BeforeAll {
      Import-Module Omnicit.EntraRBAC -Force
      . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
      Install-OERTransportTripwire
  }

  AfterAll {
      try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
  }
  ```
- **Mock at the module boundary:** `Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }` and
  `Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }`.
- **Private functions** must be tested inside `InModuleScope Omnicit.EntraRBAC { ... }`.
- **Reset auth state** in `BeforeEach` when testing anything that touches auth:
  `BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }`.
- **Always mock `Initialize-OERAuth`**: every public cmdlet that touches Graph or Azure calls it at
  entry, so without a mock the test attempts real authentication.
- **Mock `Invoke-OERGraphRequest`, not `Invoke-MgGraphRequest`**: it keeps the test at the module
  boundary and away from the wrapper's own retry, scrub and conversion logic. A
  `Mock -ModuleName Omnicit.EntraRBAC Invoke-MgGraphRequest` does win from the module scope; mock the
  raw SDK call only where the test is about the wrapper itself (`Invoke-OERGraphRequest.Tests.ps1`)
  or drives the real wrapper on purpose to observe what it does with a failure (the records it builds
  or leaves, its retries), as parts of `Get-OERGroup.Tests.ps1` do.
- **Every unit test file that imports the module installs the transport tripwire:** in its root
  `BeforeAll`, directly after `Import-Module`, it dot-sources `TestHelpers/OERTransportTripwire.ps1`
  and calls `Install-OERTransportTripwire`; it ends with a root
  `AfterAll { try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire } }`. An
  unmocked call that still reaches one of the six names of **SECURITY** rule 2 (`Invoke-RestMethod`
  being the tenant lookup) is recorded and refused, and fails the file even when module code
  swallowed the refusal. A test that reaches the real `Initialize-OERAuth` with a tenant named by
  domain mocks `Resolve-OERTenantDomain` (or `Invoke-RestMethod` in module scope).
  `tests/QA/testhygiene.tests.ps1` holds it. Never delete a transport-named function with an
  unqualified `Remove-Item 'function:...'` unless the local stub is certain to exist (with none left
  it removes the global replacement); a scope-qualified path (`function:script:...`,
  `function:global:...`) removes nothing at all.
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **A `Mock -ModuleName` covers only calls made from inside the module.** A command the test body
  calls itself runs for real unless it has its own test-scope `Mock`. No test may reach the real
  profile directory: a test of a `-BasePath` default intercepts `Test-Path` in module scope instead.
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **Pin `-ErrorAction` on any call whose non-terminating error the test observes or has to survive**
  (module code reads the GLOBAL `$ErrorActionPreference`; a test-local one does not pin it).
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **Never write the word "because" inside a `-Because` string:** Pester deletes EVERY occurrence of
  `because` plus the whitespace after it from the rendered message. Use "since", or restructure the
  sentence. `Why: docs/development/rationale.md#bearer-scrub-tests`
- **A bearer-scrub regression test needs a different proof depending on how the catch re-throws**,
  since the wrong proof passes with the scrub deleted. Same for `-ErrorVariable` assertions and
  `Should -Invoke -Times N` (at-least semantics -- add `-Exactly`). **That trap applies for `N >= 1`
  only: `-Times 0` already means EXACTLY zero**, since Pester implies `-Exactly` at zero. Do not
  "fix" a bare `-Times 0`, and never justify adding `-Exactly` at zero by calling the bare form
  vacuous. `Why: docs/development/rationale.md#bearer-scrub-tests`
- **Eight rules in this file are machine-checked** by `tests/QA/sourcehygiene.tests.ps1` (ten
  `Describe` blocks in total); the tripwire rule is checked separately, by
  `tests/QA/testhygiene.tests.ps1`. When a new catch trips the scrub gate, add the scrub -- do not
  add an exemption. The gate holds:
  - ASCII/BOM encoding; bearer-scrub-first in every transport-reaching catch;
    `ConvertTo-OERDuration` as the sole int-to-ISO encoder; the `suffix.ps1`/dev-mode-psm1 mirroring;
    `Get-OERCloudEndpoint` as the sole owner of the cloud-to-endpoint table; no Az cmdlet that could
    establish or mutate an Az PowerShell context (see **Dependencies**);
  - `Test-OERDeclaredProperty`/`Test-OERDeclaredNull` as the single owners of the apply engine's
    declared-value rule: no direct read of a node's `PSObject.Properties.Name` in a
    `Sync-OERStructure*` handler outside the named, reasoned allowlist, flagged on the read itself
    and not on the `-contains`-family operator that might consume it;
  - the transport gates (the rules and their owners: **Authentication Architecture** and **Code
    Style**). Call sites: `Get-MgContext` only in `Get-OERGraphSessionFingerprint`;
    `Lock-OERSignIn`, `Unlock-OERSignIn` and `Register-OERSignInIdentity` only in
    `Initialize-OERAuth`; `Get-OERSignInRefusal` only in the two transport wrappers and
    `Initialize-OERAuth` (its one call there, before `Lock-OERSignIn`, is placed by its unit tests;
    this gate checks the file only); `Get-OERSignInSupersession` only in the two transport wrappers;
    `Get-OERSignInIdentity` only in `Register-OERSignInIdentity`, `Get-OERSignInSupersession` and
    `Checkpoint-OERSignIn`; `Invoke-MgGraphRequest` only in the Graph wrapper; `Invoke-WebRequest`
    only in the ARM wrapper; `Invoke-RestMethod` only in `Resolve-OERTenantDomain`, and
    `Resolve-OERTenantDomain` only in `Initialize-OERAuth`; `Set-OERSessionUncertain` only in
    `Initialize-OERAuth`, `Connect-OER` and `Disconnect-OER`; `Get-OERDocumentTenantMismatch` only in
    `Invoke-OERStructure`; `Get-OERSubscriptionHomeTenant` only in `Resolve-OERInventoryScopeTree`,
    `Invoke-OERStructure` and `Get-OERInventory`; every listed owner really calling it;
  - the tenant lookup's one `Invoke-RestMethod` call carrying only `-Uri`, `-Method`, `-TimeoutSec`
    and `-ErrorAction`, with no splat;
  - `$script:_OERSessionUncertain` read and written only in `Set-OERSessionUncertain`, and in
    `Initialize-OERAuth` exactly three `Set-OERSessionUncertain` calls: the statement directly after
    the `Lock-OERSignIn` assignment and the statement directly after each
    `Register-OERSignInIdentity`;
  - the name `ReclaimGraphSession` (a parameter, a prefix of it on an `Initialize-OERAuth` call, a
    variable, a member, a hashtable key, any string, or a prefix of it as a key the calling
    function writes into a hashtable it splats into `Initialize-OERAuth`) only in `Connect-OER` and `Initialize-OERAuth`, both really naming it, and
    no file under `source/` calling `Connect-OER`, which passes it on its own;
  - every `Register-OERSignInIdentity` call the statement directly after an `Unlock-OERSignIn` call
    with the same `-Invocation`, as many of the one as of the other;
  - every send a wrapper makes in the body of a try that holds exactly one call path (Graph: one
    `Invoke-MgGraphRequest` and one `Invoke-GraphAttempt`; ARM: one `Invoke-WebRequest`), that try
    preceded, in the very block that holds it and in this order, by its session gate (Graph only),
    its latch gate and its supersession gate, each a throw followed by a return, with no
    `Initialize-OERAuth` or `Start-Sleep` between the earliest gate and any request, the ARM bearer
    token (`.ArmToken` or `['ArmToken']`) materialized only after the last gate, and the transport
    statements counted exactly (three Graph, one ARM) so a new send path cannot escape the scan;
  - every `Initialize-OERAuth` call standing directly in its file's own function (in the two
    wrappers, in `Invoke-GraphSingle` and `Invoke-ArmCallWithRefresh`), never in a nested function or
    a scriptblock inside it;
  - every `-TenantId` an internal call passes on to a command that signs in (`Initialize-OERAuth` and
    every module function that reaches it) -- a parameter whose name is a prefix of it, or a
    `TenantId` key the calling function writes into a splatted hashtable -- a non-empty literal or a
    variable written under an `if` on that same variable, with `Connect-OER`'s call and the three
    transport refreshes as named exemptions that must each match exactly one site; and no positional
    argument written on any `Initialize-OERAuth` call, after a switch included (`-Verbose` and
    `-Debug` among them).

  Two further gates in the same file check rules stated only in `docs/development/rationale.md`
  (every ARM api-version is documented under `#arm-transport`) or in no rule at all (every
  `Verb-OER...` token in `source/` resolves to a real function).
  `Why: docs/development/rationale.md#static-source-gates`

---

## SECURITY (Hard Rules - High Privilege)

This module manages **very high Entra ID privileges** across customer tenants. These rules are
non-negotiable:

1. **Claude never makes live calls against a customer tenant, and CI never authenticates.** Claude
   may run a live-verification checklist against the operator's designated test tenant only as the
   dedicated app identity whose only credential is a non-exportable certificate, only while the
   operator has enabled that identity for the run, and never with any other sign-in.
2. **Every unit test that reaches authentication or one of the module's transport wrappers mocks it
   at the module boundary, and the transport tripwire records and refuses the rest: any call that
   still reaches `Get-AzToken`, `Connect-MgGraph`, `Disconnect-MgGraph`, `Invoke-MgGraphRequest`,
   `Invoke-WebRequest` or `Invoke-RestMethod`.** Nothing in CI or tests authenticates for real, and
   no test sends the tenant lookup either.
3. **Destructive cmdlets must support `-Confirm` and `-WhatIf`** via
   `[CmdletBinding(SupportsShouldProcess)]`.
4. **Deletions of high-value objects** (groups, access packages, etc.) use
   `ConfirmImpact = High` with an explicit `Write-Warning` before the destructive call.
5. **Client secrets are always `[securestring]`.** Never accept, store, or log a plain-text
   secret anywhere in the code.
6. **Never log or write access tokens.** The `Remove-OERErrorRecord -Record $PSItem` call in every
   Graph catch block is mandatory, not optional (see **Error Handling**). It replaces the inert
   `$null = $Error.Remove($PSItem)` idiom and matches on the one part of the record that IS
   reference-stable: its `.Exception` object.
   `Why: docs/development/rationale.md#security-hard-rules`

---

## Language

All code, comment-based help, and command output must be in **English**. Chat and communication
with the team may be in Swedish.

---

## Dependencies

| Module | Floor | Purpose |
|---|---|---|
| `AzAuth` | 2.9.0 | Token acquisition for all auth methods via `Get-AzToken` |
| `Microsoft.Graph.Authentication` | 2.36.0 | `Connect-MgGraph -AccessToken`, `Invoke-MgGraphRequest` (inside wrapper) and `Get-MgContext` (the Graph SDK session check) |

That column is the **runtime FLOOR** declared in `source/Omnicit.EntraRBAC.psd1`: a manifest
`ModuleVersion` is always a minimum, never an exact pin. `RequiredModules.psd1` is the build-time
resolver, and by decision (2026-09-21) every entry in it is `latest` -- **nothing there is pinned**.
Do not reconcile the two in either direction: no version number goes into `RequiredModules.psd1`,
and no `latest` goes into the manifest. The accepted cost: CI tests the newest combination (what a
new consumer gets) while **nothing tests the declared floors any more**.
`Why: docs/development/rationale.md#dependencies`

**No Az module is a dependency of this module, and no Az cmdlet is invoked at run time at all.**
ARM is called directly with an AzAuth token (`Invoke-OERArmRequest`).
`tests/QA/sourcehygiene.tests.ps1` proves this from the source with an AST walk, independently of
what is installed. `RequiredModules.psd1` still resolves `Az.Accounts`, for the TEST environment
only (Pester's `Mock` requires a command to exist; two negative assertions depend on it:
`Connect-AzAccount` `-Times 0` in `Initialize-OERAuth.Tests.ps1` and `Disconnect-AzAccount`
`-Times 0` in `Disconnect-OER.Tests.ps1`); that is not a runtime need, so it is absent from the
table. `Why: docs/development/rationale.md#no-az-dependency`

Do not add other `Microsoft.Graph.*` SDK modules. The module intentionally uses raw
`Invoke-MgGraphRequest` (via `Invoke-OERGraphRequest`) to avoid typed SDK coupling and version drift.

---

## Checklist: Adding a New Function

1. **Create the file:** `source/{Public|Private}/Verb-OERNoun.ps1`. Filename must match function
   name exactly.
2. **If public:** add to `FunctionsToExport` in `source/Omnicit.EntraRBAC.psd1`.
3. **If public, update the surrounding cohorts and gates the new export joins:**
   - README's `## Available Cmdlets` cohort (its `(N)` count and the "All NN exported cmdlets"
     sentence) and the about topic's `COMMAND COHORTS` entry, held against each other by
     `docsync.tests.ps1`/`about.tests.ps1`. The same number is stated twice more -- README's
     introduction ("All NN cmdlets carry the `OER` command prefix") and the about topic's
     LONG DESCRIPTION ("list all NN cmdlets") -- and `docsync.tests.ps1` holds all three sentences
     to `FunctionsToExport`, so a new export moves them all.
   - A `Get-OERRequiredScopeMap` row naming the LEAST-privilege scope the new cmdlet needs, gated by
     `requiredscope.tests.ps1` -- a new Graph path may also need a new endpoint rule there.
   - A `Set-OER*` cmdlet joins `NothingToUpdate.Cohort.Tests.ps1`.
   - A `-TenantId` parameter carries `[ValidateNotNullOrEmpty()]`, which
     `TenantIdNotEmpty.Cohort.Tests.ps1` holds, and its count of carriers moves by one.
   - A public call site of an ambiguity-refusing `Resolve-OER*Id` helper joins
     `AmbiguousName.Guard.Tests.ps1`.
   - A new `Sync-OERStructure*` handler, or a `Resolve-*Change` helper taking a `-Declared` document
     node, joins the named file list in `tests/QA/sourcehygiene.tests.ps1` gate 8 -- the glob that
     gate scans alone does not make a drop visible; the file must be named.
4. **Call `Initialize-OERAuth`** at the entry point (`begin` block or top of `process`) for any
   function that calls Graph or Azure. Pass `-IncludeARM` for functions that call ARM. Call it
   directly in the command's own block, never from a nested function, `& { }` or any other
   scriptblock -- the sign-in latch is keyed on the frame that calls it, and gate 10 of
   `tests/QA/sourcehygiene.tests.ps1` fails a call that stands anywhere else.
5. **Route all Graph calls through `Invoke-OERGraphRequest`.** Never call `Invoke-MgGraphRequest`
   directly.
6. **Tag output:** convert the response to `[PSCustomObject]`, insert a type name, add a `<View>`
   in `source/Formats/Omnicit.EntraRBAC.Format.ps1xml`, and -- if a ScriptProperty member is needed
   -- register it inline with `Update-TypeData -Force` in `source/suffix.ps1` (and mirror it in the
   dev-mode `source/Omnicit.EntraRBAC.psm1` loader).
7. **Add full comment-based help:** `.SYNOPSIS`, `.DESCRIPTION`, one `.PARAMETER` per parameter,
   at least one `.EXAMPLE`.
8. **Add a unit test file:** `tests/Unit/{Public|Private}/Verb-OERNoun.Tests.ps1`. Import by
   module name in `BeforeAll`, and install the transport tripwire there with the root `AfterAll`
   that checks and removes it (the shape under **Testing Conventions**). Mock `Initialize-OERAuth`
   and `Invoke-OERGraphRequest`.
9. **Keep the file ASCII-only** and UTF-8 without BOM.
10. **Run `./build.ps1 -Tasks test`** before committing -- it is the authoritative gate.

---

## Common Pitfalls

- **`New-OERConfiguration` is create-only** -- no `-Force` parameter. To update an existing profile
  use `Set-OERConfiguration`.
- **`Export-OERConfiguration` (private) owns PSD1 serialization** -- never inline serialization in a
  public function.
- **The source psm1 is the dev-mode loader only.** ModuleBuilder replaces it during build with a
  merged psm1. Initialization that must survive in the built module belongs in `suffix.ps1`.
- **`TypesToProcess` is intentionally empty; `FormatsToProcess` is active.** Type data is registered
  inline with `Update-TypeData -Force` in `suffix.ps1`, mirrored in the dev-mode psm1.
  `Why: docs/development/rationale.md#type-data`
- **A help line starting with `.word`** is parsed as a help keyword and silently wipes the whole
  comment-based help block. Reword it.
- **Never commit module code directly to `main`.** Always work on a feature branch and PR.
