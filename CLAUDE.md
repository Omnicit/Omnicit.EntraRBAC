# Omnicit.EntraRBAC - CLAUDE.md

Working rules for this repo. This file carries **rules**; the history behind them lives in
[docs/development/rationale.md](docs/development/rationale.md), linked per rule as
`Why: ...#anchor`. Read the anchor before "simplifying" a rule -- most of them exist because the
obvious simplification was already tried here and silently failed.

Do not restate project status, roster or release history here: `README.md` owns the cmdlet list,
`CHANGELOG.md` owns release history, and the GitHub issue tracker owns open work.

---

## Branch Policy -- ALWAYS CHECK FIRST

**`main` is protected on GitHub and a direct push to it is REJECTED BY THE SERVER.** That is
deliberate. It is not a lock to be worked around, and "continue on the current branch" is no longer
an option a user can consent to on `main` -- consent does not move a server-side rule. Every change
reaches `main` through a pull request.

**Before making any code change, Claude must:**

1. Determine the current branch (`git branch --show-current`).
2. If the current branch is `main`, create a feature branch before touching any files:
   `git checkout -b <branch-name>`, named from the table below. Propose the name and say what it is
   for; do not stop and wait for permission to leave `main`, since staying there cannot produce a
   push.
3. If the current branch is some OTHER shared branch, stop and ask the user which branch to use --
   there the old rule still holds, because the push would succeed.
4. Open a pull request against `main` when the work is ready. Never merge it without being asked to.

**Merge requirements, enforced by GitHub on `main` (as measured on 2026-10-08):**

- **Four status checks are required: `ubuntu-latest`, `windows-latest`, `macos-latest` and
  `package`.** The first three come from the build-and-test matrix's `name: ${{ matrix.os }}`, so
  the job name IS the required check name -- renaming the job, or changing the matrix, orphans the
  protection rule and blocks every open PR until the rule is renamed to match. `package` is the
  `package` job's own `name: package` in the same workflow: the job that runs after all three legs
  (`needs: build-and-test`) and proves on the pull request that the artefact is publishable,
  without publishing it. Renaming its `name:` (or, with `name:` removed, its job id, which the check
  name then falls back to) orphans the fourth rule the same way. Change both together.
- **`package` never holds the gate alone.** It has no `if:` of its own, so when a leg fails or is
  skipped GitHub skips `package` too, and a skipped check counts as passed ("Troubleshooting
  required status checks": successful statuses are `success`, `skipped` and `neutral`). The three
  leg checks are what stop a red pull request, so never drop them from the rule in favour of
  `package`.
- **The branch must be up to date with `main` before it can merge** (the rule is strict). A branch
  that has fallen behind is rebased onto `main` and force-pushed; the checks then re-run against the
  rebased tip.
- **Linear history is required**, so a merge commit is refused. Squash merge is the convention here.
- **Every conversation on the PR must be resolved** before merge.
- **The rule binds administrators too** (`enforce_admins` is on), so no account merges past it.

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

`Omnicit.EntraRBAC` is a PowerShell 7.2+ (Core-only) module built and maintained by Omnicit AB. MIT
licensed and **published on the public PowerShell Gallery for anyone to use**: 1.0.0 went out by
hand on 2026-09-18, and everything since publishes itself -- see **Publishing** below.

It manages RBAC building blocks across many Entra ID and Azure tenants: Entra ID groups, PIM,
Administrative Units, Entitlement Management, Access Reviews, Azure resources and RBAC, plus a JSON
inventory and a declarative apply engine. Command prefix is `OER`.

**The canonical working tree is the clone whose `origin` is
`github.com/Omnicit/Omnicit.EntraRBAC`**, wherever it sits on disk. The local path differs from
machine to machine, so identify it with `git remote get-url origin`, never by its directory. The
older clone, whose `origin` is the private repository, is to be archived; do not commit to it, and
do not treat a change made there as made. Two live clones of one module is how a fix lands in the
wrong repository -- that has already happened here.

The phase roadmap (phases 0-5) is **complete** -- the module is feature-complete. See `CHANGELOG.md`
for what each release delivered.

---

## Module Layout

```
source/
  Omnicit.EntraRBAC.psd1      # Manifest -- source of truth for exports and RequiredModules
  Omnicit.EntraRBAC.psm1      # Dev-mode loader ONLY (Private -> Public). ModuleBuilder replaces
                              #   it at build time; see Common Pitfalls.
  suffix.ps1                  # Update-TypeData -Force blocks + Register-ArgumentCompleter calls,
                              #   each mirrored verbatim in the dev-mode psm1
  Private/                    # Internal helpers, one function per file
  Public/                     # Exported cmdlets, one per file, filename == function name
  Formats/                    # Omnicit.EntraRBAC.Format.ps1xml (type data is inline in suffix.ps1)
  en-US/                      # about_Omnicit.EntraRBAC.help.txt
tests/
  QA/                         # Seven gate files (below), all run by ./build.ps1 -Tasks test
  Unit/Private/, Unit/Public/ # One *.Tests.ps1 per source file, plus the named exceptions below
  Unit/Formats/               # FormatViews.Tests.ps1 -- format-view rendering checks
  Unit/TestHelpers/           # Two helpers and one suite. OERConfirmHost.ps1 hosts a runspace whose
                              #   PSHost answers ShouldProcess prompts -- the only way to test a
                              #   genuine DECLINE, to read the prompt/target text, or to see the
                              #   order of warnings, 'What if:' lines and prompts.
                              #   OERTransportTripwire.ps1 is the transport tripwire every unit test
                              #   file installs; OERTransportTripwire.Tests.ps1 is its known-answer
                              #   suite.
  Workflow/                   # PublishJob.Tests.ps1 -- the publish job's tag guard, proven offline:
                              #   PublishArtefact.ps1 called directly, and the job's own step text
                              #   run in pwsh against a fake Gallery and a fake GitHub.
build.yaml, build.ps1         # Sampler/ModuleBuilder config and bootstrap entry point
RequiredModules.psd1          # Build-time dependency resolver (NOT the runtime pin -- see Dependencies)
azure-pipelines.yml           # Build + Test only, no Deploy stage -- it never publishes
.github/workflows/build-and-test.yml  # Build + Test on Linux, Windows, macOS, then package and
                              #   publish. The ONLY path that publishes -- see Publishing.
.github/scripts/PublishArtefact.ps1   # -Record / -Verify / -Compare: proves the published bytes
                              #   are the tested bytes, and that the package on the Gallery is
                              #   this commit's build before the tag step tags it. Single owner of
                              #   all three; do not split it.
```

There is **no `source/Classes` directory**. The loader iterates one, but argument completion is
scriptblock-based instead. `Why: docs/development/rationale.md#completers`

**The build-and-test job's `if:` condition is now wired to the merge gate -- do not read it as a
billing guard alone, and do not reason about it from GitHub's general rule for skipped jobs.** The
job is declared
`if: ${{ !github.event.repository.private || github.event_name == 'workflow_dispatch' }}`, because
standard runners are free and unmetered only on a PUBLIC repository. `ubuntu-latest`,
`windows-latest`, `macos-latest` and `package` are the four REQUIRED checks on `main`, and that
condition decides whether the first three ever come into existence; `package` follows them through
`needs: build-and-test`.

**The mechanism is the MATRIX, not the skip.** GitHub documents the opposite of what happens here:
a job skipped by a condition reports Success and does NOT block a pull request ("Troubleshooting
required status checks"). That rule does not rescue this workflow, because `build-and-test` is a
matrix job and a job-level `if:` is evaluated BEFORE the matrix expands. The three legs are
therefore never created, so nothing ever reports the three check names -- and a required check that
never reports stays pending forever instead of passing (community discussion #9141). The fourth
check does not change that: `package` is skipped with the job it needs, and a skipped check counts
as passed, but the three matrix names still never report. Make this repository private again and
every pull request blocks permanently, including the pull request that would fix it. Turning the
repository private is therefore a change to this condition, or to the protection rule, made in the
SAME change and never afterwards.

**Rewriting this workflow as three separate jobs without a matrix INVERTS the failure, into the
worse one.** Without a matrix there is nothing to expand: the job-level `if:` would then skip three
jobs that do exist, each would report Success under the documented rule, and the merge gate would
go GREEN having run not one test -- `package` included, since it would be skipped with them. The
matrix is what makes a skip fail loudly here, so keep it -- or, if the jobs are ever split, make the
required checks something a skipped job cannot satisfy.

**Do not maintain a function roster in this file.** Read it from the tree instead:

```powershell
Get-ChildItem source/Public  -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
Get-ChildItem source/Private -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
```

`README.md` section "Available Cmdlets" is the maintained, cohort-grouped list of every exported
cmdlet; `Get-OERRequiredScope` reports the Graph/Azure permissions each one needs.

**The seven QA gates** (`tests/QA/`): `module.tests.ps1` (manifest, changelog, help, README,
per-function PSScriptAnalyzer, and a unit test file for every exported function),
`about.tests.ps1` (the about topic is byte-identical to source, ASCII/BOM-free, and names every
exported cmdlet and no other), `requiredscope.tests.ps1` (`Get-OERRequiredScopeMap` vs the module's
own call graph), `sourcehygiene.tests.ps1` (the ten static source gates --
`Why: docs/development/rationale.md#static-source-gates`), `dochygiene.tests.ps1` (keeps unredacted
tenant object ids, tenant domains outside a fixed allowlist of four labels, non-documentation email
addresses and credentials out of every tracked file under `docs/`, `specs/`, `source/` and
`tests/`, enumerating tracked files with `git ls-files` and reading their content from disk; reads
the placeholder register in `docs/live-verification/README.md`, failing on a register at odds
with itself or a placeholder used without a row; and also checks that tracked Markdown under
`docs/`, `specs/`, `README.md` and `CHANGELOG.md` holds no angle bracket GitHub would render as a tag),
`docsync.tests.ps1` (binds `README.md` to the about topic), and `testhygiene.tests.ps1` (every unit
test file that imports the module installs, checks and uninstalls the transport tripwire; read
statically, importing nothing).

**`dochygiene.tests.ps1` applies TWO object-id rules, split by what the file is.** Under `docs/` and
`specs/` a GUID is prose, so it must be a `00000000-0000-0000-0000-0000000000NN` placeholder. Under
`source/` and `tests/` a GUID is a fixture, so the rule is that it must not have **version-4 shape**:
every Entra ID and ARM object id is v4 and no invented fixture needs to be, which leaves the roughly
seventy existing `1111...`/`aaaa...` fixtures untouched and still readable. Exactly three v4 values
are pinned by name -- the module's own manifest GUID, the Microsoft Graph Command Line Tools app id,
and the Reader built-in role definition id. **Do not add a fourth: allocate a placeholder instead**,
from the register in `docs/live-verification/README.md`, which also records the next free
`...NNN` and `personN`. **The gate reads that register**, so it is red on a placeholder used in
`source/`, `tests/`, `docs/examples/` or `docs/development/` without a row marked taken, and on a
register that disagrees with itself -- overlapping rows, a repeated slot description, a table without
exactly one FREE row, an "Allocate from" sentence that disagrees with the FREE rows, a slot taken
at or above a FREE start that is not a named outlier, or a placeholder cell it cannot read. Add the
row in the same commit that uses the slot. **It also holds tenant domains** (`.onmicrosoft.com`, `.onmicrosoft.us`, `.onmschina.cn`) to a
fixed allowlist of four labels, `contoso`, `fabrikam`, `other` and
`oer-sovereign-verify-doesnotexist`, reading `%40` as `@` and `\.` as `.`, so a URL-encoded UPN and a
regex-form domain are caught too. Replace a real label with `contoso`; never widen the allowlist to
make the gate green. A credential-shaped literal that a test needs (the bearer-scrub fixtures)
must carry `NOT-A-REAL-TOKEN` inside the VALUE; `REDACTED` works the same way.
`Why: docs/development/rationale.md#bearer-scrub-tests`

**`dochygiene.tests.ps1` also reads Markdown the way GitHub renders it.** In every tracked `.md`
under `docs/` and `specs/`, and in `README.md` and `CHANGELOG.md` at the root, no angle bracket
that looks like a tag (`<word>`, `</word>`, `<!...>`, `<?...>`) may stand outside code: GitHub
renders it as nothing, so a redacted `<id>` stand-in vanishes from the record. `CHANGELOG.md`'s
`[Unreleased]` also becomes the GitHub release body (the publish job's `gh release create
--notes-file`), which GitHub renders the same way and hides the bracket too -- but the PowerShell
Gallery shows those same notes as HTML-encoded plain text, where a bracket is SHOWN, not hidden,
and a backslash escape would show there too, permanently. So in `CHANGELOG.md` use backticks only,
never a backslash. Elsewhere, write the token inside backticks, or as `\<id>` where a backtick
would close a code span the line already has; quotes alone do not escape it. An autolink
(`<https://...>`) or deliberate inline HTML (`<br>`) is refused the same way, since the check is
exactly the reference algorithm -- write a bare URL instead, or put the markup in backticks. Fenced
blocks and code spans are skipped with the algorithm documented in
`ConvertTo-DocHygieneMarkdownProse`'s own `.DESCRIPTION`, in `tests/QA/dochygiene.tests.ps1`. That
algorithm is the maintainer's `Test-MdAngleBrackets.py`, a script kept outside this repository that
the gate follows where the two differ (the gate's own comment says so), and deliberately not
CommonMark's: never "correct" it towards CommonMark, and carry a change made on either side to the
other, so the two keep agreeing hit for hit.

**`docsync.tests.ps1` holds `README.md` and the about topic against each other.** Each already had
its own "names every exported cmdlet" check, but both matched the whole FILE, so a cmdlet mentioned
only in a Quick Start snippet passed while missing from the roster. This gate scopes the roster to
`## Available Cmdlets` and `COMMAND COHORTS`, checks each `### Cohort (N)` count against the cmdlets
that cohort is the FIRST to name, and requires the two documents to agree word for word on the
tenant-switch verdict per sign-in type and on the device-code known limitation. It deliberately does
NOT bind the surrounding prose -- the sovereign-cloud, tenant-profile and permissions sections are
rewritten per medium on purpose.

**Test files named after no single function.** Ten cross-cutting suites exist. Do **NOT** delete
any of them as an orphan when auditing the one-test-file-per-function invariant:

- `Unit/Private/BasePathDefault.Cohort.Tests.ps1` -- asserts all seven `-BasePath`/`-ProfileBasePath`
  default carriers resolve cross-platform (issue #40). It sits under `Private/` because five of the
  seven carriers are public and two are private, so it belongs to neither cohort exclusively. Do not
  "fix" its location by moving it.
- `Unit/Public/AccessReview.Pipeline.Tests.ps1` -- cross-cmdlet pipeline suite.
- `Unit/Public/AmbiguousName.Guard.Tests.ps1` -- asserts every public call site of an
  ambiguity-refusing `Resolve-OER*Id` helper surfaces the candidate ids instead of a first match.
- `Unit/Public/NothingToUpdate.Cohort.Tests.ps1` -- asserts every `Set-OER*` cmdlet (all twelve)
  reports the no-updatable-property condition as `NothingToUpdate`, and that
  `Set-OERRoleManagementPolicy`'s separate "no rule differs" case keeps its distinct `NoChange` id.
- `Unit/Public/GroupAliasOrder.Cohort.Tests.ps1` -- AST-driven: asserts every `source/Public/*Group*.ps1`
  file declaring a `-Group` parameter lists the `GroupId` alias before the generic `Id` alias, so a
  piped principal can never mis-bind as the piped group.
- `Unit/Public/AdministrativeUnitAliasOrder.Cohort.Tests.ps1` -- the same AST-driven pattern for every
  `-AdministrativeUnit` parameter, so a piped member's own `Id`/`DisplayName` can never mis-bind as
  the piped parent unit.
- `Unit/Public/TenantIdNotEmpty.Cohort.Tests.ps1` -- AST-driven: asserts every public cmdlet that
  declares `-TenantId` carries `[ValidateNotNullOrEmpty()]` on it, except `Connect-OER`, whose
  `-TenantId` must carry no validation so its own `InvalidTenantId` refusal runs after the
  session-uncertain marker is set (A12, BL-94); it also drives the binding refusal for the cmdlets
  the live checklist uses. It imports the module, so it installs the transport tripwire.
- `Unit/Public/DirectoryRoleInventory.RoundTrip.Tests.ps1` -- exports the two directory sections
  (`directoryRoleManagementPolicies`, `directoryRoleAssignments`) from a mocked live state with
  `Get-OERInventory` and applies them back through `Invoke-OERStructure`, with and without `-Prune`,
  asserting every row is `Unchanged`.
- `Unit/Public/WarningBeforeConfirmation.Cohort.Tests.ps1` -- AST-driven: asserts no
  `source/Public/*.ps1` file writes a `Write-Warning` after its first `$PSCmdlet.ShouldProcess`,
  except the warnings its allowlist names with a reason (an entry matching no warning, or two, fails
  too); pins by name and text the twenty cmdlets that warn before their gate; and proves each moved
  warning at run time on `OERConfirmHost`, before the `What if:` line and before the `-Confirm`
  prompt, with no write request. `OER_COHORT_SOURCE_ROOT` points its AST parts at a mutated copy of
  `source/` and is never set in CI. It imports the module, so it installs the transport tripwire.
- `Unit/TestHelpers/OERTransportTripwire.Tests.ps1` -- the transport tripwire's known-answer suite:
  the six names, resolution from the module scope, parameter parity, mock precedence, the record
  and the refusal, a re-import, the `AfterAll` check, the answering runspace and the uninstall.

---

## Build and Test Commands

```powershell
# Bootstrap build dependencies (first time or after a clean clone)
./build.ps1 -ResolveDependency -Tasks noop

# If that fails with "Requested value 'V2' was not found" (PSResourceGet compat error), add:
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast

# Build the module (output lands in output/module/Omnicit.EntraRBAC/<ver>/)
./build.ps1 -Tasks build

# Full test suite -- the authoritative CI gate.
# QA tests + Unit Pester + PSScriptAnalyzer + 80% code coverage enforcement
# (measured 2026-10-08: 94.89% over 18,579 commands, locally on Windows and on all three CI
#  runners of PR #34; macOS measured 94.88% on main's run of bfe1b1a, whose source is the same)
./build.ps1 -Tasks test

# Import from source for quick local development
# (needs AzAuth, Microsoft.Graph.Authentication on PSModulePath;
#  prepend output/RequiredModules if needed)
Import-Module ./source/Omnicit.EntraRBAC.psd1 -Force

# Import the built module
Import-Module ./output/module/Omnicit.EntraRBAC/<ver>/Omnicit.EntraRBAC.psd1 -Force
```

The Sampler test task measures coverage against the **built** module output, not `source/`. Always
run `-Tasks build` before `-Tasks test` after changing source files -- and never build while the
gate is running.

**Under `latest`, a local `output/RequiredModules` goes stale and LOCAL GREEN IS NOT CI GREEN.**
`RequiredModules.psd1` asks for the newest release of every module
(`Why: docs/development/rationale.md#dependencies`), but a local tree is resolved once and then left
alone, while every CI run resolves afresh on a clean runner. Measured on 2026-09-21: a local tree
held `Microsoft.Graph.Authentication 2.36.0` while CI resolved `2.40.0` on the same commit. So a
full local pass proves the suite against whatever happens to be on disk, not against what the merge
gate will run. Refresh before trusting a local run, especially before opening or updating a PR:

```powershell
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast
```

`-UseModuleFast` is the same flag the V2 note above prescribes, and it is the resolver that works
here. Note that it is a DIFFERENT resolver from CI's, so the two trees can still differ in shape --
a tree resolved without it also carries the unpacked `.nupkg` directories (`_manifest`, `_rels`,
`dependencies`, `package`) beside a module's version folder. The CI workflow's dependency-report
step prints the versions each run actually resolved, and is the authority on what the gate tested.

**A refresh ADDS versions and removes nothing.** After the 2026-09-21 refresh the local tree held
`Microsoft.Graph.Authentication` at both `2.36.0` and `2.40.0`, and still held an `Az.Resources`
that `RequiredModules.psd1` no longer asks for at all. That is usually harmless, since PowerShell
loads the HIGHEST version available when importing by name, so a refreshed tree does test the new
one -- but it means the directory is a growing record of every version ever resolved, not a picture
of what is currently requested. Confirm the version under test with
`Get-Module <name> -ListAvailable` rather than by reading the folder listing, and delete the
directory outright if a genuinely clean resolve is needed.

---

## Publishing

**Every merge to `main` publishes a new preview to the public PowerShell Gallery, and that is
PERMANENT.** The Gallery can unlist a version but cannot delete one. There is no staging step and
no deployment approval between merge and publish: merging the pull request is the decision to
publish it.

- **Publishing lives in `.github/workflows/build-and-test.yml`, in its `publish` job.** That job
  is the only thing in this repository that can publish. `./build.ps1 -Tasks publish` is
  deliberately undefined and must stay that way, so there is no local publishing path at all. Do
  NOT restore Sampler's `Publish_Release_To_GitHub` / `publish_module_to_gallery` tasks in
  `build.yaml`; the measured reasons are in that file's comment and in
  `Why: docs/development/rationale.md#publish-on-merge`.
- **A merge that changes only documentation publishes a new preview too.** The workflow has no
  path filter and must not be given one. Accepted in Decision 4 -- a preview per merge is the
  price of the merge-to-main trigger, not a defect to be filtered away.
- **`paths-ignore` must never be added to the `pull_request` trigger**, for the reason the matrix
  exists: a run that never happens never reports the four required checks, and a required check
  that never reports stays Pending forever.
- **The publish job tags every publish, and the tag is load-bearing.** `GitVersion.yml` runs
  `mode: ContinuousDelivery`, where the preview counter advances on a TAG and not per commit:
  measured, two merges with no tag between them build the SAME version and the second publish is
  refused by the Gallery. `Why: docs/development/rationale.md#publish-on-merge`
- **The tag step tags only the commit whose tested build IS the package on the Gallery (A16,
  BL-114).** On every run but a `v` tag run it first runs `PublishArtefact.ps1 -Compare`, which
  reads the package back with `Save-PSResource` and compares it with the run's tested artefact,
  file by file and SHA-256 by SHA-256; a different build, or a read that fails, refuses the step
  before anything is tagged or released. So does a tag that already names another commit:
  `gh release create` ignores `--target` for an existing tag, so a preview tag pushed by hand onto
  the wrong commit would otherwise receive the release. Before this guard, a publish that no tag
  followed made the NEXT merge compute the same version, skip the publish and tag ITS OWN commit
  over the previous commit's package. Now:
  - **A publish whose tag step failed, or whose publish step failed although the upload arrived:**
    re-run the FAILED job of that same run. It reuses the tested artefact, matches and tags, as
    the re-run after the Gallery's 500 on 2026-10-08 did.
  - **A run that was refused** (a later merge whose build differs, carrying the same version; one
    whose build is byte-identical IS the package and is tagged): push the missing tag by hand onto
    the commit that published the version, then re-run ALL jobs of the newest refused run, which
    counts up from that tag and publishes it. A re-run of only its failed jobs reuses its own
    build and is refused again. The refusal message names the steps. A preview tag pushed onto the
    wrong commit is named in either refusal -- by the tag check when the run's own build is the
    package, and in the comparison's repair text otherwise: delete it with
    `git push origin :refs/tags/v<version>` before tagging the right commit.
  - **Never loosen the comparison to turn a refused run green.** A rebuild of the published commit
    on a later day is a different build too (the release notes carry the build date), so
    re-running ALL jobs of the run that published is refused as well; re-run only its failed jobs
    instead.

  `Why: docs/development/rationale.md#the-tag-step-tags-only-the-build-that-was-published`
- **Never create a version tag by hand outside that repair or a deliberate release.** The existing
  rule under **CHANGELOG and Version** still holds, and now has teeth: a stray tag changes what
  gets PUBLISHED.
- **No approval stands between a merge or a `v` tag and the Gallery** (Philip's decision,
  2026-09-23). The `Entra RBAC` environment has no required reviewers: it scopes `GALLERYAPITOKEN`
  to the `publish` job and admits only branch `main` and the stable `v<X.Y.Z>` tag patterns. The
  gate for a preview is the pull request and its required checks; the gate for a full release is
  the tag, which only the `Stable Version` tag ruleset's bypass list can create, move or delete.
  Both closures are repository SETTINGS on purpose: a tag push runs the workflow file at the tagged
  commit, so a check in the workflow is removed by the same commit that abuses it. Never widen an
  environment tag pattern past what the ruleset covers -- every pattern starts with `v` and admits
  no hyphen, which is why `v*` was removed. Accepted residual: whoever can merge a pull request can
  publish a preview, until `Require approvals` is switched on with a second reviewer.
  `Why: docs/development/rationale.md#publish-on-merge`
- **The workflow must never create, move or delete a stable tag.** The ruleset refuses
  `GITHUB_TOKEN` all three, so a stable run that tried would fail in its last step, AFTER the
  publish. On a `v` tag run the release step attaches the release to the tag already there; the
  only tag the workflow ever writes is a hyphenated preview tag, which the ruleset excludes.
- **The publish job refuses a version its ref does not call for**, straight after the artefact is
  verified and before anything is published: on a `v` tag the built version must equal the tag
  exactly and the tagged commit must be on `main`; on `main` the build must carry a prerelease
  label; any other ref is refused. It guards against MISTAKES, not an adversary -- the gate stays in
  the settings, since a changed workflow writes the step away. **A refused or misplaced stable tag
  stays where it is**, and nothing removes it for you: someone on the bypass list deletes it with
  `git push origin :refs/tags/v<X.Y.Z>` and, for a misplaced one, pushes it again on the `main`
  commit it was meant for. `Why: docs/development/rationale.md#publish-on-merge`

**To cut a full release:**

1. Push `v<X.Y.Z>` on the `main` tip, once that commit's four required checks are green. Only the
   `Stable Version` ruleset's bypass list can create that tag -- as measured on 2026-10-08, the
   Repository admin role and the user PhilipHaglund -- and the push IS the release decision: nothing
   asks for an approval after it. A tag outside the `Entra RBAC` environment's patterns (a major of
   10 or more, or a minor or patch of 100 or more) is refused by the environment, visibly, and
   publishes nothing; the repair is a new pattern the ruleset also covers, never a return to `v*`.
2. Make the close-out the FIRST merge after the tag, exactly as the **close-out after a stable
   release** rule under **CHANGELOG and Version** describes. The invariant to check it against is
   `git show v<X.Y.Z>:CHANGELOG.md` -- the dated section must say what that tag actually shipped.

---

## CHANGELOG and Version

`CHANGELOG.md`'s `[Unreleased]` section **is** the next release's published `ReleaseNotes`, not a
per-PR log. The build rewrites its heading to `## [<version>] - <date>` and copies the section
verbatim into the built manifest's `PrivateData.PSData.ReleaseNotes`.

- **Write `[Unreleased]` in release-note voice** -- product-level and user-visible: what this
  version is, and what changed for someone consuming the module. Budget **4,000 characters**,
  gated in `tests/QA/module.tests.ps1` on the section's `RawData`, which includes the
  `## [Unreleased]` heading and therefore reads slightly SHORT of what is actually published -- do
  not spend the difference.
- **The floor is on the BODY and is 50 characters -- about one sentence.** The section after its
  heading line, trimmed, must reach it, in the source and in the built manifest alike. It is there
  to catch a MECHANICAL failure, an emptied or hand-converted section that publishes `ReleaseNotes`
  of length 0 while the build reports success, and it does not judge the text: whether a note says
  enough is decided in review. Never pad the section to get past it -- every merge publishes the
  padding to the Gallery for good.
- **Close-out after a stable release.** The close-out is the FIRST merge after a `v<X.Y.Z>` tag. It
  adds `## [X.Y.Z] - <date>` directly above the previous dated heading, moves the released notes
  under it, and leaves `[Unreleased]` holding exactly this sentence and nothing else, with `X.Y.Z`
  the version just released:

  ```text
  No changes to the module since X.Y.Z. A preview published from this point differs from X.Y.Z only in documentation, tests or the build.
  ```

  It has to come first because every merge publishes `[Unreleased]` as a preview's `ReleaseNotes`:
  a merge landing between the tag and the close-out publishes a preview whose notes describe the
  previous release's changes as new. **The first change under `source/` after a close-out REPLACES
  the sentence** with a note of its own; it never adds the note after it. Wrapping the sentence
  across lines is fine. `tests/QA/module.tests.ps1` holds both halves: while the sentence stands it
  must be exactly that sentence for the latest dated section in `CHANGELOG.md`, and it must not
  survive a diff that touches `source/`.
- **Per-PR engineering detail belongs in the PR body and the commit message**, not in
  `CHANGELOG.md`. The published note is read by module consumers, not by reviewers.
- **When `[Unreleased]` approaches the budget, close the detail out.** Add a NEW dated
  `## [<version>] - <date>` heading directly above the previous dated one, move the accumulated
  detail under it, and rewrite `[Unreleased]` as a summary of the release as a whole.
- **Never convert, rename or delete the `## [Unreleased]` heading itself.** The build does that at
  release time against its own OUTPUT copy; the source file is never modified by a build. A
  hand-converted section leaves the source `[Unreleased]` empty, and the next build then publishes
  `ReleaseNotes` of length 0 while reporting success.
- **A PR that changes nothing under `source/` is not required to touch `CHANGELOG.md`.** The
  changed-file gate fires only on a path matching `^source/`.
- **The two gates that read the BUILT artefact need a build.** `build.yaml`'s `test` workflow does
  not include `build`, so both measure whatever is already in `output/module/`. The published-notes
  gate also compares that artefact against the CURRENT `CHANGELOG.md`, so a build older than your
  changelog edit turns it red -- the right direction of failure, not a bug, since that is exactly
  the state in which the source-side gates are green and the published note is wrong. The version
  cap reads only the artefact's own version, so it reddens on staleness only if nothing resolves or
  the stale build was itself outside the `1.x` line. Either way: build before test, exactly as
  `## Build and Test Commands` already requires. Both gates resolve the module under test with
  `Get-Module -ListAvailable | Select-Object -First 1`, so they measure whichever copy ranks first on
  `PSModulePath` -- under `./build.ps1 -Tasks test` that is the built module, but a globally
  installed copy would be measured instead.

`Why: docs/development/rationale.md#changelog-budget`

**The computed module version is held in the `1.x` line.** Issue #55 capped it below `1.0.0`;
issue #62 lifted the cap to `1.0.0` on 2026-09-13 for the first public release. The two levers are
both in `GitVersion.yml`: `next-version` (`1.0.0`), which supplies the base version when no tag
outranks it (a `release/x.y.z` branch name is a third candidate -- see below), and
`major-version-bump-message`, which carries BOTH halves of its original pattern: the explicit
`+semver: breaking|major` token AND the conventional-commit `^[a-z]+(\(.+\))?!:` subject form. The
`!:` half was disabled only for the duration of the private pre-1.0.0 history, where two reachable
commits (`5816e87`, `715fb6d`) carried a `!:` subject and, with no tag to bound the increment
window, made the original pattern build `2.0.0` (measured). **This repository is seeded from a clean
tree without those commits and carries `v1.0.0` from its first commit, so neither condition can
apply and P5 restored the original pattern deliberately.** `GitVersion.yml` is the truth here;
`minor-version-bump-message` and `patch-version-bump-message` are working, so intent stays recorded
in history.

**How the version is computed.** The base is the greatest of three candidates: the highest reachable
version tag, `next-version`, and the `x.y.z` of a `release/x.y.z` branch name -- either the branch
being built, or one named by a standard merge commit message. One exception: a tag sitting on HEAD
is returned verbatim and outranks every other tag and `next-version` however high they are, though a
higher `release/x.y.z` still beats it. From the base comes **at most ONE increment**, never one per
commit, sized from the commits since the NEAREST reachable tag -- every reachable commit when there
is no tag at all. A TAG base not on HEAD takes an increment on any branch whose config sets a
default one, and every branch this repo's convention produces does: it is the greater of the branch
default (Patch on `main` and on every branch prefix this repo's convention uses) and the highest
`+semver:` level in that window. A `release/*` branch is the exception, since the inherited
`release:` block sets `increment: None` -- measured, `v3.0.0` on HEAD~1 builds `3.0.1` on `main` and
`3.0.0` on `release/2.0.0`. A `next-version` or `release/x.y.z` base takes no default
increment, so with no `+semver:` commit in the window it is used exactly as written -- but one
`+semver: fix` there still makes `1.0.0` build `1.0.1`, and one `+semver: minor` makes it `1.1.0`. A
PRERELEASE-labelled tag (`v0.9.0-preview.1`) is the exception to all of that: it takes no
`MajorMinorPatch` increment at all, and no `+semver:` message moves it.

**Do not create a version tag, or a `release/x.y.z` branch, outside a deliberate release.** Any tag
at or above `next-version` becomes the base, one sitting on HEAD ships verbatim whatever its value,
and a branch named `release/2.0.0` builds `2.0.0` on its own with no tag involved anywhere.
`release/` is not one of the prefixes in the branch-naming table above. Bump messages now move the
version: with no reachable tag the base is `1.0.0` and at most one increment applies, so one
`+semver: fix` builds `1.0.1`, one `+semver: minor` builds `1.1.0`, one `+semver: major` builds
`2.0.0` -- and so does a `!:` subject, through the other half of the same pattern.
`tests/QA/module.tests.ps1` holds the built version at or
above `1.0.0` and below `2.0.0`, independently of `GitVersion.yml` -- lift both together when
`2.0.0` is called, and never raise that assertion just to make a build pass.

**Two different shapes move the version from a message, and both must be kept out of commit
messages, PR titles and PR bodies.**

1. **Never quote a bump token** -- name it in words ("the semver major token"). A message that
   merely quotes the major token builds `2.0.0`, and one that quotes the minor or fix token moves
   the version silently.
2. **Never write a conventional-commit `!:` subject.** `fix!: ...`, `feat(x)!: ...` and every other
   `<verb>!:` or `<verb>(<scope>)!:` form matches the second half of `major-version-bump-message`
   and builds `2.0.0`. This half is LIVE -- see the paragraph above, and do not rely on any older
   note saying it is disabled.

GitVersion reads every reachable commit message, and a squash merge copies the PR title and body
into `main`, so a squash title of `fix!: ...` is enough on its own to do it. File content is never
read and may quote either shape freely.

**Since every merge to `main` publishes, this is no longer a rule about a number in a build log.**
What one of those shapes does now splits by level, and only one level is caught:

- **Major** (`!:`, or the quoted major token). `tests/QA/module.tests.ps1` caps the built version
  below `2.0.0` independently of `GitVersion.yml`, so the merge turns `main` RED, `package` and
  `publish` never run, and nothing is published. The repair then happens on `main` under a broken
  required check instead of in an open PR, which is bad enough on its own.
- **Minor or fix.** Nothing caps these. `main` carries `tag: preview`, so the merge publishes, for
  example, `1.1.0-preview0001` in place of `1.0.1-preview0001` -- a real version, on the public
  Gallery, that cannot be deleted, and a version line that was never chosen. There is no gate
  behind this one: the rule about what you type IS the control.

`Why: docs/development/rationale.md#version-cap`,
`docs/development/rationale.md#publish-on-merge`

---

## Authentication Architecture

**Public:** `Connect-OER`, `Disconnect-OER`. **Private:** `Initialize-OERAuth` (single entry point).

Every public cmdlet that calls Graph or Azure invokes `Initialize-OERAuth` at the start of its
`begin`/`process` block, passing `-IncludeARM` when it needs ARM. `Connect-OER` is an optional
pre-auth shortcut -- all cmdlets authenticate automatically on first use. Auth uses AzAuth's
`Get-AzToken` for every credential type; state is cached in `$script:_OERAuthState`, keyed on tenant,
auth identity, **and cloud**. The state also carries `SignedInObjectId`, the signed-in identity's
object id read from the Graph token's `oid` claim -- never the token itself.
`Why: docs/development/rationale.md#auth-state`

**The state also carries `GraphSessionFingerprint`**, which records the Microsoft Graph PowerShell
SDK session the module's own `Connect-MgGraph` left in the process -- never a token, never the
context object, and never written to any stream. `Get-OERGraphSessionFingerprint` is the single
owner of the fingerprint and `Get-OERGraphSessionState` of the comparison. Every
`Initialize-OERAuth` entry that gets past its BL-74 check (below) checks it, the cached return
included, and so does `Invoke-OERGraphRequest` before every Graph call; a session another
`Connect-MgGraph` started is refused with `GraphSessionChanged`. Only `Connect-OER` passes
`-ReclaimGraphSession`, which takes the session back. Never add a second reclaim caller, and never
make the module switch the session back by itself: either one moves the other session's Graph calls
to this module's tenant. Since A10 the switch also gets past the session-uncertain refusal and clears
that marker without a tenant, so gate 10 of `tests/QA/sourcehygiene.tests.ps1` holds the NAME
`ReclaimGraphSession` to `Connect-OER.ps1` and `Initialize-OERAuth.ps1`.
`Why: docs/development/rationale.md#auth-state`

**A command whose sign-in is refused sends nothing -- no Graph and no ARM request.** A terminating
error from `Initialize-OERAuth` ends only `Initialize-OERAuth`: outside any `try` the cmdlet that
called it carries on, and used to send its calls under the session an earlier sign-in left -- for
`Invoke-OERStructure -TenantId B -Prune`, B's document applied to A. So `Initialize-OERAuth` latches
its calling command (`Lock-OERSignIn`) directly after its BL-74 check below and releases it only on
success (`Unlock-OERSignIn`: the cached return, or a new connection that went the whole way); both
are called only there. Every refusal, terminating error and early return leaves the command
latched, `ArmTokenAcquisitionFailed` included, so that command's Graph calls are refused too
although its Graph half connected -- except the BL-74 refusal, which comes before `Lock-OERSignIn`
and latches nothing of its own: the latched outer command it found covers the caller. Both
transports ask `Get-OERSignInRefusal` before every request and refuse it while any frame on the
call stack is latched, with `SignInRefused` (`New-OERSignInRefusedError` owns the id and the
message) -- the Graph wrapper after its session gate, so a changed session still reads
`GraphSessionChanged`, and after a `GraphSessionChanged` refusal at the cmdlet's entry its ARM calls
read `SignInRefused`. The latch is keyed weakly on the calling command's INVOCATION, never a module
boolean: a pipeline neighbour's successful sign-in releases only its own entry. A refused command's
nested sign-ins are refused before they are made (BL-74): a refused command carries on and calls
cmdlets that sign in again, and near the cached token's expiry one of them reached `Get-AzToken` --
a browser or device code prompt -- for a command that sends nothing. So before `Lock-OERSignIn`,
`Initialize-OERAuth` asks `Get-OERSignInRefusal -OutsideCaller` and, when a command OUTSIDE its
caller is latched -- the caller is a cmdlet that command calls, or signs in inside that command's
output -- raises a terminating `SignInRefused` naming that command, with no token call, no
`Connect-MgGraph` and no latch of its own. The caller's own latched frame does not count, so a
command whose sign-in was refused earlier in the same invocation -- `Invoke-OERStructure` for its
next piped document -- may sign in again. Only `Initialize-OERAuth` passes `-OutsideCaller`; never
make that check walk the whole stack. A finished command is on no call stack, so the next command,
or `Connect-OER`, sends again. An ARM call of a command whose entry was not refused still goes out
with the module's own token: ARM has no session gate. Never write that the cmdlet stops -- it
carries on and sends nothing -- and never call `Lock-OERSignIn` or `Unlock-OERSignIn` outside
`Initialize-OERAuth`. Call `Initialize-OERAuth` directly in the command's own block, never from a
nested function, `& { }` or any other scriptblock: the latch is keyed on the frame that calls it,
and such a frame ends at once (the transports' own refreshes, in `Invoke-GraphSingle` and
`Invoke-ArmCallWithRefresh`, are the one exception).
`Why: docs/development/rationale.md#auth-state`

**A command sends nothing under a sign-in a later command replaced.** In a pipeline every `begin`
block runs first, so an upstream command's `process` block would act under the session a downstream
command's sign-in switched to: `New-OERGroup -TenantId A ... | Add-OERGroupMember -TenantId B`
created the group in B. Both sign-ins succeed, so neither the latch nor the session gate sees it. So
where `Initialize-OERAuth` succeeds -- exactly where `Unlock-OERSignIn` releases the latch --
`Register-OERSignInIdentity` remembers, keyed weakly on the calling command's invocation, the
identity the state carries: tenant, method, client and cloud, never a token. `Get-OERSignInIdentity`
is the single owner of that identity. Both
transports ask `Get-OERSignInSupersession` before every request and refuse it with
`SignInSuperseded` (`New-OERSignInSupersededError` owns the id and the message) while ANY frame on
the call stack remembers another identity than the state now carries. So an outer command whose
nested cmdlets inherited the switched state is refused too, and so is a downstream command's request
made inside the upstream command's output call, where the upstream frame is still on the stack.
`Invoke-OERStructure` and `Connect-OER` sign in in `process`, not `begin`, and a downstream
command's `begin` runs first, even when it takes no pipeline input. When they name a tenant, their
own sign-in switches the state back to it, so downstream of them it is the downstream command that
is refused. WITHOUT `-TenantId` a sign-in in `process` inherits the state the downstream command's
`begin` left and remembers it, so no gate would see the switch: `Invoke-OERStructure`'s document,
`-Prune` included, applied to the downstream command's tenant (BL-76), and the three builders that
sign in only to look up a name -- `New-OERAccessPackageApprovalStage`,
`New-OERAccessPackageRequestorScope` (through `Resolve-OERTargetList`) and
`New-OERAccessReviewStage` (through `Resolve-OERReviewerScope`) -- looked it up there (BL-81). So
those four commands take a snapshot of the session in `begin` and, without `-TenantId`, compare it in
`process` directly before that sign-in or lookup -- `Invoke-OERStructure` after the document is
read and validated, the builders after their argument checks -- refusing with `SignInSuperseded`
and sending nothing when the identity changed, or when the module held no session and now holds
one. `Checkpoint-OERSignIn` is the single owner of the session a command began with: it builds the
snapshot only through `Get-OERSignInIdentity`, so its terms are the memory's. `Invoke-OERStructure`
takes it again after every sign-in, refused or not, so its next piped document is compared with
the session that sign-in left; the builders take no pipeline input and never take it again. A new
command that signs in only in `process`, directly or through a helper, without `-TenantId` takes
the same snapshot. Never name the tenant the command began with as `-TenantId` in `process`
instead: a `-TenantId` other than the state's inherits nothing, so an app-only session would get a
browser prompt (A6). The snapshot is taken when the command's own `begin` runs, so it covers a
command that stands in the pipeline itself and not one called inside a script block or a function
in a pipeline -- `ForEach-Object { Invoke-OERStructure ... }`. Such a command begins only when the
block runs, after every `begin` block of the outer pipeline, so it takes a downstream command's
sign-in for the session it began with. The gap this leaves is closed for a document that names its
tenant (BL-88; `tenantId`, which `Get-OERInventory` and `Export-OERInventory` write):
`Get-OERDocumentTenantMismatch` refuses the document in any other tenant with
`DocumentTenantMismatch`, whatever session the command began with. It stays open, older than BL-76,
for a document without `tenantId` -- applied, `-Prune` included, in the downstream command's
tenant -- and for the builders, which look their names up there. So never call a name-looking
builder, or `Invoke-OERStructure` with a document that carries no `tenantId`, without `-TenantId`
inside a script block or function in a pipeline that signs in to another tenant or identity. The
identity's tenant term is the tenant the Graph token was issued for (`TokenTenantId`) when that is a
GUID, and the tenant as NAMED otherwise, never the ARM token's (BL-77): since a named tenant is
checked against that token (within `TenantMismatch`'s limits, below), one tenant named by GUID on one
command and by domain on another -- or not named at all -- is ONE identity, to the snapshot as to the
memory, whenever the token reports a GUID tenant. Never key the identity on the name again, and never
on the ARM tenant, which is not always acquired. The session CACHE is still
keyed on the tenant as named, so a command naming its tenant differently from the session inherits
nothing and signs in again -- interactively when it names no credential, a browser prompt on an
app-only session and an identity that differs in method -- which is why README's "Name the tenant
explicitly and consistently", and the about topic's equivalent under SOVEREIGN CLOUDS, stand. The
order is fixed: in the Graph wrapper the session gate, then
the latch gate, then the supersession gate; in the ARM wrapper the latch gate, then the
supersession gate. A command with no memory is not compared by that gate. A pipeline must not span
tenants or identities: run the commands as separate statements, for example collecting into a
variable first.
Never call `Register-OERSignInIdentity` outside `Initialize-OERAuth` or anywhere but directly after
an `Unlock-OERSignIn` with the same invocation, and never read the supersession outside the two
transports.
`Why: docs/development/rationale.md#auth-state`

**A tenant named by domain is looked up before any token request, and checked like a GUID
(BL-12).** `Initialize-OERAuth` resolves every requested tenant that is neither a GUID nor
`organizations` through `Resolve-OERTenantDomain` -- after the cached return and the credential
checks, before the AzAuth trackers move and before any token call -- and both `TenantMismatch`
checks, Graph and ARM, compare the granted tenant with the tenant ID it returns (a granted tenant
that is not a GUID is not compared, the limit below). A failed lookup
refuses the sign-in with `TenantResolutionFailed` (raised after the lookup's `try`, never inside its
`catch`), and no token is requested; `common` names no tenant and is refused the same way. The token
request still names the tenant as given. `organizations` is never looked up or compared. Never call
`Resolve-OERTenantDomain` outside `Initialize-OERAuth`, never move the lookup above the cached return
or the credential checks, and never exempt another non-GUID value the way `organizations` is.
`Why: docs/development/rationale.md#switching-tenants-in-one-process`

**A refused sign-in leaves the session uncertain (A10, BL-89).** A sign-in that fails or is refused
leaves the previous tenant's session in place, and outside any `try` the script carries on: the next
command, naming no tenant, used to act on the previous tenant -- in a loop of
`Connect-OER -TenantAlias X` and `Invoke-OERStructure -Prune`, X's document applied to the tenant
before it. So `Initialize-OERAuth` sets the marker directly after `Lock-OERSignIn`, and refuses with
`SignInRefused` (`New-OERSignInRefusedError -SessionUncertain`), after the `GraphSessionChanged`
refusal and before the cached return and every token call, a call that names no tenant -- no
`-TenantId`, or `-TenantId organizations` -- while the marker it found was set, unless the call is
`Connect-OER`'s (`-ReclaimGraphSession`). The caller stays latched, so it sends nothing. At each
success end, directly after `Register-OERSignInIdentity`, it clears the marker when the call named
its tenant and is not a transport's own refresh (`-ForceRefresh` or `-ClaimsChallenge`), or is
`Connect-OER`'s, and otherwise puts back the value it found. `Connect-OER` sets the marker first
thing in `process`, so its own refusals before any sign-in count; `Disconnect-OER` clears it inside
its `ShouldProcess`.
`Set-OERSessionUncertain` is the single owner of `$script:_OERSessionUncertain`: never read or write
the variable anywhere else, never call the helper outside `Initialize-OERAuth`, `Connect-OER` and
`Disconnect-OER`, never let a transport's refresh clear the marker, and never count `organizations`
as naming a tenant. A command that names its tenant is never refused by the marker; a parameter
binding error of `Connect-OER` never reaches it (known limit). `Connect-OER` sends every BOUND
`-TenantAlias` to its alias check, so an empty, whitespace or `$null` alias is refused with
`InvalidTenantAlias` and leaves the marker set, and every BOUND `-TenantId` that is empty, whitespace
or `$null` is refused the same way, in `process` after the marker is set, with `InvalidTenantId`
(A12, BL-94); never test either for truthiness there, and never give either
`[ValidateNotNullOrEmpty()]`, whose binding error marks nothing. Every OTHER public cmdlet that
declares `-TenantId` carries `[ValidateNotNullOrEmpty()]` on it, so an empty value stops that
command at parameter binding and it sends nothing, instead of acting on the current session's tenant
as no tenant named. `tests/Unit/Public/TenantIdNotEmpty.Cohort.Tests.ps1` holds both halves, with
`Connect-OER` the one named exception; a new public `-TenantId` takes the attribute.
`New-OERConfiguration` and `Set-OERConfiguration`, whose `-TenantId` is stored rather than signed in
to, also refuse a value of white space only at binding, with a `[ValidateScript()]` declared above
that attribute (BL-96); a stored blank `TenantId` is still read as it is, and an update that names
no `-TenantId` keeps it. The `(BL-96)` Contexts of
`tests/Unit/Public/New-OERConfiguration.Tests.ps1` and `Set-OERConfiguration.Tests.ps1` hold it. An
internal call passes `-TenantId` on only when it is set (`if ($TenantId) { ... }`), never an empty
value -- except `Connect-OER`'s own call of `Initialize-OERAuth`, which passes `''` when neither
`-TenantId` nor `-TenantAlias` is bound, and which `Initialize-OERAuth` reads as no tenant named.
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
sovereign cloud -- `Global` (default), `USGov`, `USGovDoD` or `China`). The cloud joins tenant and
auth identity in the `$script:_OERAuthState` cache key, so naming a different cloud always
re-authenticates rather than reusing a token minted at the previous cloud's authority. **Microsoft
365 GCC runs on the commercial (`Global`) endpoints and needs no `-Environment` at all** -- only GCC
High (`USGov`), DoD (`USGovDoD`) and a 21Vianet tenant (`China`) are separate cloud boundaries.
`Disconnect-OER` clears `$script:_OERAuthState` and calls `Disconnect-MgGraph` only when
`Get-OERGraphSessionState` reports `Own` (A4, BL-67): a session the module did not connect, or has no
record of connecting, is left, with a warning written before its `ShouldProcess`. It deliberately
does NOT call `Disconnect-AzAccount`: the module establishes no Az context, so any Az session on the
machine is the operator's own (Philip's decision, 2026-09-21).
`Why: docs/development/rationale.md#sovereign-clouds`

**IMPORTANT:** `-ClientSecret` is a `[securestring]`. Never accept or store client secrets as plain
strings.

**Same-session tenant switch is limited by sign-in type.** AzAuth keeps ONE credential for the
whole process, and `Get-AzToken -Tenant` is not honoured by every credential type: the device code
and managed identity requests do not carry the named tenant at all (measured), with a device-code
credential reused after a successful sign-in passing it on for a silent re-acquisition instead
(inferred; since A17 the module never reuses one, below), and a client secret credential refuses a
different tenant until `-Force` rebuilds it
(or, with `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH` set, silently requests the token from the previous
tenant; measured).
`Initialize-OERAuth` refuses, with `TenantMismatch`, a token issued for another tenant than the one
named -- by GUID or, through the lookup above, by domain -- so a switch that did not take effect does
not become a session, within two limits: a token whose tenant AzAuth does not report as a GUID (one
without a `tid` claim) is not compared, and `organizations` names no tenant, so its tokens are
compared with no requested tenant -- an ARM token a sign-in acquires under it is compared with the
session's Graph token (`TokenTenantId`) instead, when both are GUIDs, and refused with the same
`TenantMismatch` when they differ. A state rebuild -- a renewal of the Graph token, or a transport's
refresh -- carries the cached ARM token into the new state only when, besides the unchanged tenant
label, identity and cloud (`$ArmIdentityUnchanged`), its `ArmTokenTenantId` equals the new Graph
token's tenant, both GUIDs (`$ArmTokenKept`, A13, BL-95); otherwise it is dropped, the ARM step of
that same call runs under `-IncludeARM`, and the new ARM token is compared as above. Never carry it
on the label alone: `organizations` stays `organizations` when a renewal is answered from another
tenant (`Why: docs/development/rationale.md#requested-tenant-vs-granted-tenant`). Before the
call it only
warns, for a client secret switch it can predict will not take effect (a
`-WarningAction Stop`/`$WarningPreference = 'Stop'` caller is stopped at that `Write-Warning`, before
any token request). The post-call warning that compared granted tenants is
retired with its tracker; do not bring it back. `Connect-OER -Force` is the only public lever that
makes a switch take effect. **Every device code token request, Graph and ARM, carries `Force`**
(A17, BL-112, Philip's decision 2026-10-09): a device code request without it that reuses the
credential AzAuth stored for the same client id never returns -- no code, no error (decompiled;
measured live for a tenant switch) -- and `Force` makes AzAuth build a new credential, which prints
a new code. `$DeviceCodeForced` in `Initialize-OERAuth` is the single owner of that decision, read
only by the `Force` condition and by the removal of `Force` after a Graph acquisition, and it is
NOT a cache term: `$GraphCached`, `$ArmCached` and `$ClearsUncertainty` never read it, so a device
code session whose tokens are still valid answers from the cached return with no token request.
Never add an automatic `-Force` to any other sign-in type without a new decision, and never make
the device code `Force` bypass the cached return.
`Why: docs/development/rationale.md#auth-state`,
`docs/development/rationale.md#switching-tenants-in-one-process`,
`docs/development/rationale.md#every-device-code-sign-in-is-forced`

---

## Tenant Profile Config

Per-tenant configuration is stored as PSD1 files under
`<home>/.config/Omnicit.EntraRBAC/Profiles/<alias>.psd1`. Never write `$env:USERPROFILE` to build
that path -- it is Windows-only and this module is `CompatiblePSEditions = 'Core'`. Path derivation
and the profile schema: `Why: docs/development/rationale.md#profile-path`

| Cmdlet | Operation | Notes |
|---|---|---|
| `New-OERConfiguration` | Create | Mandatory `-TenantAlias`, `-TenantId`. Non-terminating error if alias exists; directs to `Set-OERConfiguration`. |
| `Get-OERConfiguration` | Read | Optional `-TenantAlias` filter. Returns `Omnicit.EntraRBAC.TenantConfiguration` objects. |
| `Set-OERConfiguration` | Update | Mandatory `-TenantAlias`. Non-terminating error if alias missing. Preserves sections not specified. |
| `Remove-OERConfiguration` | Delete | Mandatory `-TenantAlias`. `ConfirmImpact = Medium`. |

A profile's optional `Environment` key names the sovereign cloud that tenant lives in (`Global`,
`USGov`, `USGovDoD` or `China`). `Connect-OER -TenantAlias` reads it automatically when the command
line names no `-Environment` of its own, so an operator managing both commercial and sovereign-cloud
tenants does not have to remember, and pass, which is which on every call; an explicit `-Environment`
on the command line always overrides it.

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

1. **Never attach a `ValidateSet`.** Completion is purely additive -- free text, GUIDs and custom
   role names must keep binding. A curated list is a hint, not a constraint.
2. **Completers must be fast and offline.** No Graph or ARM call: they run on the interactive prompt
   path.
3. **Never throw and never write an error record** from a completer -- return no results instead.
4. **Register in `suffix.ps1` AND mirror it in the dev-mode psm1.** Drift means completion works from
   the built module but not from source, or vice versa.
5. **Quote values containing whitespace** in `CompletionText` so the inserted argument is valid as
   typed, while `ListItemText` and the tooltip keep the raw value.
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
  screen; written inside the gate it prints only after the answer, and never under `-WhatIf`. A
  warning that needs a value computed only inside the gate moves out with that computation, or is
  named, with its reason, in the allowlist of `tests/Unit/Public/WarningBeforeConfirmation.Cohort.Tests.ps1`
  -- an outcome warning, one that depends on what the operator confirmed, or one not about the action
  at all. That cohort fails every other `Write-Warning` after a public cmdlet's first
  `$PSCmdlet.ShouldProcess`. In the apply engine a `Sync-OERStructure*` handler writes the same
  warning before `$Caller.ShouldProcess` only when the cmdlet it calls will not write it, so the plan
  shows it and a real run never warns twice: under `-WhatIf`, where the cmdlet is never called, and
  in both modes for the group PIM MFA / authentication-context pair the diff reconciles, since
  `Set-OERGroupPimPolicy`, given the reconciled parameters, writes none. The handler's tests run each
  such case as a plan and as a real run with the real cmdlet, from one live state, and hold the same
  text and exactly one warning in the run.
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
- **Property naming:** an identifier is `<Noun>Id`, a display name is `<Noun>DisplayName`. A bare
  noun must never hold a display name. Keep a historical spelling as an `AliasProperty`
  (`Update-TypeData -Force` in `suffix.ps1`) rather than storing the value twice. An ARM-scoped
  object (`Resource`, `ResourceGroup`, `Subscription`, `ManagementGroup`, `RoleDefinition`) exposes
  the ARM path as `ResourceId`, never a bare `Id` -- `Id` is already claimed elsewhere by
  `-PolicyId`/`-RoleEligibilityScheduleId`, and a bare `Id` on one of these five would mis-bind
  those parameters from the pipeline. `RoleDefinition` stores the path as `RoleDefinitionId` and
  exposes `ResourceId` as an `AliasProperty` of it; the other four store `ResourceId` directly --
  either way, no ARM-scoped shape stores the path twice.
  `Why: docs/development/rationale.md#property-naming`
- **Alias declaration order:** in a parameter's `[Alias()]` list, the specific `<Noun>Id` form comes
  before the generic `Id`. `ValueFromPipelineByPropertyName` resolves the parameter NAME first, then
  the aliases in DECLARATION ORDER, first match wins -- so an `Id`-first list on a `-Group` or
  `-AdministrativeUnit` parameter binds a piped MEMBER's own id where the parent object's id was
  meant, and on a `Remove-*` cmdlet that deletes the wrong tenant object. Two AST cohort suites
  machine-check this: `Unit/Public/GroupAliasOrder.Cohort.Tests.ps1` and
  `Unit/Public/AdministrativeUnitAliasOrder.Cohort.Tests.ps1`.
  `Why: docs/development/rationale.md#alias-declaration-order`
- **`-Scope` binds from the pipeline only where the piped OBJECT is assignment-shaped, never where
  it is scope-DEFINING** -- this is a split by object shape, not a blanket rule per cmdlet.
  Assignment-shaped objects (`RoleAssignment` and its PIM siblings) carry `Scope` and feed the four
  cmdlets that actually bind it: `Enable-`/`Disable-OEREligibleRoleAssignment` and
  `Remove-OERActiveRoleAssignment`/`Remove-OEREligibleRoleAssignment`. `Set-OERRoleAssignment` and
  `Remove-OERRoleAssignment` have NO `-Scope` parameter at all -- they act on `-Id` alone, which
  already embeds the scope; do not add one. Scope-DEFINING objects (`Resource`, `ResourceGroup`,
  `Subscription`, `ManagementGroup`, `RoleDefinition`) carry only friendly properties and never
  `Scope` or a bare `Id`, and feed the create/read cmdlets (`New-`/`Get-`) by those friendly
  properties (`Subscription`, `ResourceGroup`, `ManagementGroup`, `ResourceType`, `ResourceName`)
  instead.
  `Why: docs/development/rationale.md#scope-pipeline-binding`
- **`ConvertTo-OERODataFilterValue` is the single owner of OData filter-value escaping.** Any Graph
  display-name lookup interpolating a caller-supplied value into a `$filter=... eq '...'` URL must
  escape through it. Four deliberate exceptions exist; a new unescaped site is a bug, not the house
  style. `Why: docs/development/rationale.md#odata-escaping`
- **A resolver on the cohort's list publishes its failure as itself and an ambiguous name as
  `Ambiguous*`, never as `*NotFound` -- a COHORT check holds that, not a helper.** The principal
  and Azure role definition lookups are the decided exception, still publishing a failed read as
  `PrincipalNotFound` or `RoleDefinitionNotFound` -- never "fix" one of them into a changed
  published ErrorId. The PIM approver lookups follow the rule: an ambiguous approver name is
  `AmbiguousApproverName`, a failed lookup is published as itself, and `ApproverNotFound` means only
  an approver that matches nothing, in the three policy cmdlets and the three apply handlers alike.
  They tell the three apart by the internal ids `PrincipalUnresolved` and `ApproverUnresolved`,
  which no cmdlet or handler publishes.
  `Why: docs/development/rationale.md#approver-lookup`
  `tests/Unit/Public/AmbiguousName.Guard.Tests.ps1` runs every call site on its hand-kept
  `$script:GuardCases` list with an ambiguous name and with a 403 -- the approver lookups of
  `Set-OERGroupPimPolicy`, `Set-OERDirectoryRoleManagementPolicy` and `Set-OERRoleManagementPolicy`
  included -- so a new public call site of an ambiguity-refusing `Resolve-OER*Id` helper, an
  approver lookup among them, joins that list. The 403 case narrows to the cmdlet's own record:
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **`Resolve-OERReviewerScopeQuery` is the single owner of the access review reviewer scope query
  grammar.** Never re-implement the `/users/` and `/groups/` regex pair inline; `./manager` is
  matched FIRST, always, and an `Unparsed` scope is NOT the same as an empty reviewers collection.
  `Why: docs/development/rationale.md#reviewer-scope-query`
- **`Test-OERGuid` is the single GUID predicate.** Never re-implement the canonical GUID regex
  inline. The wider `-as [guid]` cast in `Get-OERInventory` and `New-OERGroup` is a deliberate
  exception -- do not migrate those two -- and so are the two places that read a group's
  `administrativeUnit` the way `New-OERGroup` does: the created-membership match in
  `Sync-OERStructureAdministrativeUnit` and the unit placement check in `Test-OERStructureSchema`.
  `Why: docs/development/rationale.md#guid-predicate`
- **`ConvertTo-OERCanonicalScope` is the single owner of how a document scope is compared, and
  `ConvertTo-OERScopeSplat` of the `sub:`/`subscription:`/`mg:` scope syntax** -- never re-implement
  either inline; the first is pure, since the offline validator uses it. A document scope that
  ends with `/` (other than `/`) or contains `//` is REFUSED by the validator, not merged by the
  helper's trim: never drop that rule in favour of the trim, which would make such a scope prune.
  `Why: docs/development/rationale.md#role-assignment-key`
- **`Resolve-OERPimActivationConflict` is the single owner of the MFA / authentication-context
  mutual-exclusion rule.** An enabled authentication context and `MultiFactorAuthentication` on
  activation cannot both be in force. All call sites -- the Graph group write path, the apply
  diff, and the shared rule-patch builder (`Resolve-OERPolicyRulePatch`) -- take the DECISION from
  this helper and apply it in their own idiom. Never re-implement the check inline. The rule-patch
  builder is shared by two callers that pass a different `-ResolveUnrequestedConflict`: the Azure
  (ARM) policy path passes `$true` because ARM PATCHes the full rule set, so every apply run
  re-validates a combination even when this call did not touch either side of it; the directory-role
  (Graph) path passes `$false` because it patches one rule at a time and leaves an untouched
  combination alone. `Get-OERPimRulePatchOrder` is the single owner of the authentication-context
  PATCH order this conflict resolution requires, called by both `Set-OERGroupPimPolicy` and
  `Set-OERDirectoryRoleManagementPolicy`.
  `Why: docs/development/rationale.md#mfa-authcontext-exclusion`
- **`ConvertFrom-OERGraphApprover` is the single reader of a Graph approver, and
  `Resolve-OERApproverInput` / `Resolve-OERGraphApproverSet` are the single owners of the Graph
  approver-side semantics shared by `Set-OERGroupPimPolicy` and `Set-OERDirectoryRoleManagementPolicy`
  -- never re-implement the carry/count/ApproverRequired decision inline.** `-RequireApproval $false`
  beside a bound `-ApproverUser` or `-ApproverGroup` (an empty list included) is refused with
  `MutuallyExclusiveParameter` by the three policy cmdlets -- those two and `Set-OERRoleManagementPolicy`
  -- before any lookup or request, and `Resolve-OERGraphApproverSet` throws the same id as a backstop;
  never let that combination reach a request.
- **`Send-OERPimRulePatch` is the single owner of sending a Microsoft Graph PIM rule set, one PATCH
  per rule.** That covers the pair put-back -- when Graph accepts the first rule of the MFA /
  authentication-context pair and rejects the second, the first is PATCHed straight back to its live
  version -- and the rule that no warning is written between the first PATCH and the last put-back:
  the helper returns its messages and the caller writes them after it returns, since a
  `-WarningAction Stop` caller is otherwise stopped before the put-back. It is called by
  `Set-OERGroupPimPolicy` and `Set-OERDirectoryRoleManagementPolicy`, which confirm first and order
  the rules with `Get-OERPimRulePatchOrder`. Never PATCH a rule from either cmdlet directly, and
  never write a warning inside the helper. Held by the AST check in
  `tests/Unit/Private/Send-OERPimRulePatch.Tests.ps1` and, for the caller-side half (the messages
  written only after the last request), by the `-WarningAction Stop` tests in
  `tests/Unit/Public/Set-OERGroupPimPolicy.Tests.ps1` and
  `tests/Unit/Public/Set-OERDirectoryRoleManagementPolicy.Tests.ps1`, in a `try` and in a script with
  no `try`; `tests/QA/requiredscope.tests.ps1` counts a call to it as a Graph write by the caller, since
  the helper carries no path literal of its own.
  `Why: docs/development/rationale.md#pim-rule-pair-put-back`
- **`Test-OERScheduleRequestFailed` is the single owner of which PIM schedule request status is an
  error: the Failed family, meaning `Failed`, `FailedAsResourceIsLocked` and any later status that
  starts with `Failed`, compared case-insensitively, and nothing else** -- `Revoked` is a removal's
  success, and `Denied`, `Canceled` and the `Pending*` values are not errors. It is called by the
  twelve cmdlets that send a schedule request -- `Add-`/`Remove-OERGroupEligibility`, `New-`/
  `Remove-OEREligibleDirectoryRoleAssignment`, `New-`/`Remove-OERActiveDirectoryRoleAssignment`,
  `New-`/`Remove-OEREligibleRoleAssignment`, `New-`/`Remove-OERActiveRoleAssignment` and
  `Enable-`/`Disable-OEREligibleRoleAssignment` -- and by the two new-group replication waits in
  `Sync-OERStructureGroup`. A cmdlet emits the request object FIRST and then writes the non-terminating
  `EligibilityRequestFailed` (group, directory role and Azure eligibility requests) or
  `AssignmentRequestFailed` (active assignment, activation and deactivation requests), so a caller
  under `-ErrorAction Stop` still receives the object. Never compare a status to a `Failed` literal
  anywhere else. The cohort check in `tests/Unit/Private/Test-OERScheduleRequestFailed.Tests.ps1`
  holds that the twelve cmdlet files call the owner and that no other file under `source/` compares a
  status to a `Failed` literal in the shapes it scans; it does NOT hold the two engine waits, whose
  behaviour tests in `tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` do.
  `Why: docs/development/rationale.md#failed-schedule-request`
- **`Get-OERCloudEndpoint` is the single owner of the cloud-to-endpoint table.** Every Graph
  resource/audience, Graph service root, ARM resource/host and authority (STS) host for a sovereign
  cloud is read from it; never hardcode one of those hosts a second time. `source/Private/Invoke-OERArmRequest.ps1`
  keeps one documented public-cloud fallback for the no-auth-state case, exempted by name rather than
  deleted. `tests/QA/sourcehygiene.tests.ps1` machine-checks this the same way it checks the other
  single-owner rules above. `Why: docs/development/rationale.md#sovereign-clouds`
- **`Select-OERManagedDirectoryRoleAssignment` is the single owner of which live directory role
  assignment the apply engine may match or prune** (tenant scope, `memberType` Direct, Active only
  `assignmentType` Assigned), and `Get-OERTokenObjectId` the single owner of reading the signed-in
  identity's object id (the token's `oid` claim, delegated and app-only alike; never `/me`). Never
  re-implement either inline. `Why: docs/development/rationale.md#directory-role-assignments`
- **`Test-OERGroupPimInUse` is the single owner of whether a group uses PIM for Groups** -- PIM
  eligibility, or a PIM-for-Groups policy with a non-empty `lastModifiedDateTime`, `lastModifiedBy.id`
  or `lastModifiedBy.displayName`. Graph lists those policies for EVERY group, so a listed policy is
  not evidence of use. `Get-OERInventory` exports `pimPolicy` only for a group found in use (a
  criterion it could not read, or a "not in use" reached while the group's eligibility was unread,
  omits `pimPolicy` AND reports it unread), and `Sync-OERStructureGroup` warns, never blocks, before
  a changed policy onboards an existing group. Never re-implement the check inline. The criterion is
  documented, not yet measured live, and misses a group used only through PIM active assignments.
  `Why: docs/development/rationale.md#pim-in-use-criterion`
- **`Test-OERGroupOnPremisesSynced` is the single owner of whether a live group is synchronized from
  on-premises** -- `OnPremisesSyncEnabled` (Graph's `onPremisesSyncEnabled`, carried by
  `ConvertTo-OERGroup`) is the boolean true; false (no longer synced) and empty (never synced, or its
  source of authority converted to the cloud) are not. `Sync-OERStructureGroup` writes nothing to such
  a group, deciding on its LIVE read and never on the document's `onPremisesSynced` key: every
  property, member, owner, eligibility or `pimPolicy` change is `Skipped` with no `ShouldProcess`
  call, one warning per item, and each prune candidate is withheld
  (`ConvertTo-OERPruneWithheldResult -SyncedGroup`). `Get-OERInventory` writes the document key
  `onPremisesSynced` only as true, and `Export-OERInventory` the roster flag (a boolean on every row)
  from the same predicate; the key is information only and never sent.
  Never read `OnPremisesSyncEnabled` anywhere else -- the cohort check in
  `tests/Unit/Private/Test-OERGroupOnPremisesSynced.Tests.ps1` holds it.
  `Why: docs/development/rationale.md#synced-groups`
- **`Resolve-OERTenantDomain` is the single owner of the module's one network call outside the
  Microsoft Graph and Azure Resource Manager transports** -- the deliberately unauthenticated OpenID
  discovery lookup of a tenant named by domain at the cloud's Microsoft Entra ID authority, the host
  read from `Get-OERCloudEndpoint` -- and the only caller of `Invoke-RestMethod`.
  The call carries `-Uri`, `-Method`, `-TimeoutSec` and `-ErrorAction` and nothing else: never a
  header, a credential or a splat, never a second sender. It caches a tenant ID per cloud and
  lower-cased domain for the process and never caches a failure.
  `Why: docs/development/rationale.md#switching-tenants-in-one-process`
- **`Set-OERSessionUncertain` is the single owner of the session-uncertain marker**
  (`$script:_OERSessionUncertain`), called only by `Initialize-OERAuth`, `Connect-OER` and
  `Disconnect-OER` (see **Authentication Architecture**).
  `Why: docs/development/rationale.md#a-refused-sign-in-leaves-the-session-uncertain`
- **`Get-OERDocumentTenantMismatch` is the single owner of the comparison of a structure document's
  `tenantId`** with the tenant `Invoke-OERStructure` acts in, and of the `DocumentTenantMismatch` id
  and message (BL-88, A14); `Get-OERInventoryTenantId` is the single owner of which tenant an export
  names -- the Graph token's granted tenant (`TokenTenantId`) when it is a GUID, never the tenant as
  named, and otherwise no key at all, with no warning. `Get-OERInventory` and `Export-OERInventory`
  call it in `begin`, directly after their own sign-in. `Invoke-OERStructure` calls the comparison
  twice per document: before the sign-in whenever `-TenantId` is bound -- where the owner compares
  only a canonical GUID and leaves any other name (a domain, `organizations`) to the second call;
  keep that GUID test in the owner, never in the caller -- and after the sign-in against
  `TokenTenantId` (and `ArmTokenTenantId` when ARM is used), directly after the snapshot is taken
  again and before anything is read or written for the document. A present `tenantId` that is
  not a canonical GUID, `null` included, fails validation; a document without the key is applied
  exactly as before. Never sign in WITH the document's tenant (A6), never compare it inline, and
  never read a missing or non-GUID token tenant as a match. Gate 10 holds the comparison to
  `Invoke-OERStructure`, in a row with an `It` of its own; nothing machine-checks who calls
  `Get-OERInventoryTenantId`. `Why: docs/development/rationale.md#a-document-names-the-tenant-it-was-exported-from`

---

## CRITICAL: ASCII-Only Source Files

Authored `.ps1` files are UTF-8 **without BOM**. They **must contain only ASCII characters** --
no em-dashes, no box-drawing characters, no smart quotes, no curly apostrophes.

Without a BOM, PowerShell and PSScriptAnalyzer treat the file as ASCII. A non-ASCII character in
a BOM-less file fails the QA `PSUseBOMForUnicodeEncodedFile` PSScriptAnalyzer gate.

The only acceptable exception is a helper file that was verbatim-copied from a source that
already carries a UTF-8 BOM.

Use `--` (two hyphens) for em-dash contexts in comments and help text. Use straight quotes `'`
and `"` only.

---

## Error Handling

- **Non-terminating errors** in public functions: `$PSCmdlet.WriteError()` followed by `return` (in
  a `process` block) or `continue` (inside a `foreach` loop over multiple items). Never use bare
  `throw` in a public function -- it terminates the pipeline and prevents
  `-ErrorAction SilentlyContinue` from working.
- **Private pure helpers** such as `Resolve-OERName` may `throw` on caller error: they have no
  `$PSCmdlet`, and the caller is responsible for catching and routing the error.
- **Every Graph or ARM `catch` block** must call `Remove-OERErrorRecord -Record $PSItem` as its
  **first** statement. The raw `HttpRequestMessage` in `$Error` carries the bearer token in plain
  text. The older `$null = $Error.Remove($PSItem)` idiom looks equivalent but is **inert** -- it
  never removed anything. `Why: docs/development/rationale.md#bearer-scrub`
- **`Write-CmdletError -Message`** expects an `[Exception]`, not a string. Always wrap bare strings:
  `[System.Exception]::new('message')`.
- **`ErrorDetails` must be set via the constructor** -- plain string assignment is silently ignored
  in some PowerShell versions:
  ```powershell
  $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('Your message here.')
  ```
- **Error flow patterns:**
  ```powershell
  # In process blocks (single-item cmdlets): use return
  try { ... } catch {
      $PSCmdlet.WriteError($Err)
      return
  }

  # In foreach loops (multi-item cmdlets): use continue
  foreach ($Item in $Items) {
      try { ... } catch {
          $PSCmdlet.WriteError($Err)
          continue
      }
  }
  ```

---

## Graph Requests

**All Graph calls go through `Invoke-OERGraphRequest`.** The only place that calls raw
`Invoke-MgGraphRequest` is the wrapper itself (with `-Verbose:$false -ErrorAction Stop`). Never call
`Invoke-MgGraphRequest` from any other function.

The wrapper owns bearer-token scrubbing, ACRS claims-challenge retry, token-rejected retry, and
structured error conversion. `Why: docs/development/rationale.md#graph-wrapper`

`Connect-MgGraph -Environment` is passed only when the session's cloud is not `Global`, so the
public-cloud path stays byte-identical to what it has always been; the environment name comes from
`Get-OERCloudEndpoint`, never a literal. `Why: docs/development/rationale.md#sovereign-clouds`

**PIM-for-Groups is deliberately pinned to the Graph `beta` endpoint.** All sixteen call sites, in eleven
source files, route through the private `Get-OERPimGroupsGraphPath`, which owns the version constant.
`tests/Unit/Private/Get-OERPimGroupsGraphPath.Tests.ps1` names every one of those files and fails
when a new caller is not added to its list. Never hardcode `beta/` at a call site -- change the
constant in the helper. The eligibility paths and the four policy paths migrate as ONE unit.
`Why: docs/development/rationale.md#pim-beta-pin` Beta endpoint availability in US Government and
China clouds is not established -- a standing risk, not a bug -- recorded at
`Why: docs/development/rationale.md#sovereign-clouds`.

**Microsoft Entra directory-role PIM policies are the opposite: pinned to Graph `v1.0`.** Every
directory-role policy path is a string literal starting with `v1.0/`, routed through
`Invoke-OERGraphRequest`, and never through `Get-OERPimGroupsGraphPath` -- that helper owns the
PIM-for-Groups `beta` constant only, and a directory-role call site must not borrow it.

---

## ARM Requests

**All ARM calls go through `Invoke-OERArmRequest`.** The module deliberately does NOT use
`Connect-AzAccount`/`Invoke-AzRestMethod`: Az.Accounts cannot reliably reuse an externally acquired
AzAuth token. `Initialize-OERAuth -IncludeARM` caches the ARM bearer token as a SecureString and the
wrapper sends it directly, materializing the plaintext only at the request boundary and clearing it
in a `finally`. The ARM host is read from the session's cloud (`Get-OERCloudEndpoint`'s `ArmResource`
field via `-Environment`), not hardcoded to public-cloud ARM; `Invoke-OERArmRequest` keeps
`https://management.azure.com` as a documented fallback for a call made before any auth state exists,
so it fails on the missing token rather than on a null host -- do not delete that fallback. Since
Sprint 10 step 3 (BL-65, BL-96) a state without `ArmResourceUrl` takes its cloud's ARM host from
`Get-OERCloudEndpoint`, and the wrapper never sends a request without an ARM token: it refuses it
after its two gates, before the send, with the existing `ArmTokenAcquisitionFailed` -- the no-state
fallback is therefore refused too.

A 429, and a 503 carrying `Retry-After`, are retried with a bounded backoff whose constants mirror
the Graph wrapper's name for name (`ThrottleWaitBudgetSeconds` 300 per request/page,
`CallDeadlineSeconds` 900 per call, `ThrottleRetryHardCap` 10, single waits clamped to 1..120 s).
**The two transports are deliberately MIRRORED, never shared** -- their error shapes differ, and a
helper covering both would fit neither; the cost is that a wrong comment copied across is wrong
twice, so correct both files together. The bounds are enforced at the decision to wait and never by
stopping a paging loop part-way, which is also the LIMIT of what `CallDeadlineSeconds` bounds: it
caps a THROTTLED call only, and a never-throttled `-All` walk never consults it.
The ARM `Retry-After` header is read in exactly one place, `Get-ArmRetryAfterHeaderValue`, and the
header collection never leaves the wrapper. That is a convention this file states, **not** one of
the machine-checked single-owner rules above it: no gate in `tests/QA/sourcehygiene.tests.ps1`
enforces it, and none should be added that checks something weaker than the rule -- a gate green on
a second header read added elsewhere is itself a guard-shaped-but-inert test. Keep it by review.

`roleDefinitionId` in a role assignment body is always the FULL ARM resource id, never a bare GUID.
Pinned api-versions, paging behaviour and retry semantics:
`Why: docs/development/rationale.md#arm-transport`. Sovereign-cloud ARM endpoints and the spike
evidence behind the whole design: `Why: docs/development/rationale.md#sovereign-clouds`

**`Get-OERManagementGroupParent` is the single owner of the Entities - List call**
(`POST /providers/Microsoft.Management/getEntities`, api-version `2020-05-01`, `$view=GroupsOnly`,
`-All`), which `Get-OERManagementGroup` sends at most once per list to fill the parent of every
listed group, since the Management Groups - List answer carries none. The inventory walk
(`Resolve-OERInventoryScopeTree`) lists management groups through `Get-OERManagementGroupList`,
converts them itself and never calls `Get-OERManagementGroup` without `-Name`, so the parent read
can never add a failure mode to an export. `Get-OERManagementGroupList` is NOT the single owner of
the list call -- `Resolve-OERScope` still sends its own -- so never describe it as one.
`Why: docs/development/rationale.md#management-group-parents`

---

## PSScriptAnalyzer

The QA gate requires **0 findings** per function file. Targeted suppressions are acceptable for
known false positives (e.g. `PSReviewUnusedParameter` on parameter-set discriminator switches)
**if and only if** a `Justification` string is provided. Never suppress a rule that hides a real
bug.

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MySwitch',
    Justification = 'Switch is a parameter-set discriminator; ParameterSetName is used instead.')]
```

---

## Testing Conventions

- **Tests are written in Pester 5 syntax** under `tests/Unit/{Private,Public}/`. The build resolves
  the newest Pester, and CI resolves it afresh on every run, so no version is a standing fact here;
  6.2.0 was the newest when measured on 2026-10-05. One `*.Tests.ps1` per source file. The QA gate
  (`tests/QA/module.tests.ps1`) requires a unit test file for every exported function.
- **Import by module name, not by path**, in every `BeforeAll` -- importing by path breaks the
  Sampler coverage measurement, which targets the built module. Every unit test file that imports
  the module starts with this root shape (the tripwire lines are explained below, and
  `tests/QA/testhygiene.tests.ps1` fails a file without them):
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
- **Mock at the module boundary:**
  ```powershell
  Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
  Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
  ```
- **Private functions** must be tested inside `InModuleScope Omnicit.EntraRBAC { ... }`.
- **Reset auth state** in `BeforeEach` when testing anything that touches auth:
  ```powershell
  BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
  ```
- **Always mock `Initialize-OERAuth`** -- every public cmdlet that touches Graph or Azure calls it at
  entry, so without a mock the test attempts real authentication.
- **Mock `Invoke-OERGraphRequest`, not `Invoke-MgGraphRequest`** -- mocking the wrapper keeps the
  test at the module boundary and away from the wrapper's own retry, scrub and conversion logic. A
  `Mock -ModuleName Omnicit.EntraRBAC Invoke-MgGraphRequest` does win from the module scope, so it
  works; mock the raw SDK call only where the test is about the wrapper itself, as
  `Invoke-OERGraphRequest.Tests.ps1` is, or drives the real wrapper on purpose to observe what it
  does with a failure (the records it builds or leaves, its retries), as parts of
  `Get-OERGroup.Tests.ps1` do.
- **Every unit test file that imports the module installs the transport tripwire.** In its root
  `BeforeAll`, directly after `Import-Module`, it dot-sources `TestHelpers/OERTransportTripwire.ps1`
  and calls `Install-OERTransportTripwire`; it ends with a root
  `AfterAll { try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire } }`. An
  unmocked call that still reaches one of the six names -- `Get-AzToken`, `Connect-MgGraph`,
  `Disconnect-MgGraph`, `Invoke-MgGraphRequest`, `Invoke-WebRequest` or `Invoke-RestMethod` (the
  tenant lookup) -- is recorded and refused, and fails the file even when module code swallowed the
  refusal. A test that reaches the real `Initialize-OERAuth` with a tenant named by domain mocks
  `Resolve-OERTenantDomain` (or `Invoke-RestMethod` in module scope).
  `tests/QA/testhygiene.tests.ps1` holds it. Never delete a transport-named function with an
  unqualified `Remove-Item 'function:...'` unless the local stub is certain to exist -- with none
  left, it walks up and removes the global replacement. A scope-qualified path
  (`function:script:...`, `function:global:...`) removes nothing at all.
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **A `Mock -ModuleName` covers only calls made from inside the module.** A command the test body
  calls itself runs for real unless it has its own test-scope `Mock`. No test may reach the real
  profile directory: a test of a `-BasePath` default intercepts `Test-Path` in module scope instead.
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **Pin `-ErrorAction` on any call whose non-terminating error the test observes or has to survive.**
  Module code reads the GLOBAL `$ErrorActionPreference`, which GitHub Actions, Azure Pipelines and
  many operator profiles set to Stop, and a test-local `$ErrorActionPreference` does not pin it.
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **Never write the word "because" inside a `-Because` string.** Pester deletes EVERY occurrence of
  `because` plus the whitespace after it from the rendered message, not just a leading one, so the
  failure reads as scrambled prose. Use "since", or restructure the sentence. This is the same
  family of problem as a guard-shaped-but-inert test: the assertion works, the explanation it prints
  does not. `Why: docs/development/rationale.md#bearer-scrub-tests`
- **A bearer-scrub regression test needs a different proof depending on how the catch re-throws**,
  and the wrong proof passes with the scrub deleted. Same for `-ErrorVariable` assertions and
  `Should -Invoke -Times N` (at-least semantics -- add `-Exactly`). **That trap applies for
  `N >= 1` only: `-Times 0` already means EXACTLY zero**, since Pester implies `-Exactly` at zero
  (its own help says so, and `Pester.psm1` decides with `($Exactly -or ($Times -eq 0))`; verified by
  execution against 5.7.1 and 6.2.0). Roughly 400 bare `-Times 0` assertions in this suite are
  therefore sound negative proofs -- do not "fix" them, and never justify adding `-Exactly` at zero
  by calling the bare form vacuous.
  `Why: docs/development/rationale.md#bearer-scrub-tests`
- **Eight rules in this file are machine-checked** by `tests/QA/sourcehygiene.tests.ps1`: ASCII/BOM
  encoding; bearer-scrub-first in every transport-reaching catch; `ConvertTo-OERDuration` as the sole
  int-to-ISO encoder; the `suffix.ps1`/dev-mode-psm1 mirroring; `Get-OERCloudEndpoint` as the sole
  owner of the cloud-to-endpoint table; `Test-OERDeclaredProperty`/`Test-OERDeclaredNull` as the
  single owners of the apply engine's declared-value rule (no direct read of a node's
  `PSObject.Properties.Name` in a `Sync-OERStructure*` handler outside the named, reasoned
  allowlist -- flagged on the read itself, not on the `-contains`-family operator that might later
  consume it, so an intermediate variable cannot hide the same defect); the module never calling
  an Az cmdlet that could establish or mutate an Az PowerShell context (see **Dependencies** above);
  and the transport gates -- `Get-MgContext` called only in `Get-OERGraphSessionFingerprint`,
  `Lock-OERSignIn`, `Unlock-OERSignIn` and `Register-OERSignInIdentity` only in
  `Initialize-OERAuth`, `Get-OERSignInRefusal` only in the two transport wrappers and in
  `Initialize-OERAuth` (whose one call, before `Lock-OERSignIn`, its unit tests place -- this gate
  checks the file only), `Get-OERSignInSupersession` only in the two transport wrappers,
  `Get-OERSignInIdentity` only in `Register-OERSignInIdentity`, `Get-OERSignInSupersession` and
  `Checkpoint-OERSignIn`, `Invoke-MgGraphRequest` only in the Graph wrapper,
  `Invoke-WebRequest` only in the ARM wrapper, `Invoke-RestMethod` only in
  `Resolve-OERTenantDomain` and `Resolve-OERTenantDomain` only in `Initialize-OERAuth`,
  `Set-OERSessionUncertain` only in `Initialize-OERAuth`, `Connect-OER` and `Disconnect-OER`, and
  `Get-OERDocumentTenantMismatch` only in `Invoke-OERStructure`, every listed owner really calling
  it; the tenant lookup's one `Invoke-RestMethod` call carrying only
  `-Uri`, `-Method`, `-TimeoutSec` and `-ErrorAction`, with no splat; `$script:_OERSessionUncertain`
  read and written only in `Set-OERSessionUncertain`, and in `Initialize-OERAuth` exactly three
  `Set-OERSessionUncertain` calls -- the statement directly after the `Lock-OERSignIn` assignment and
  the statement directly after each `Register-OERSignInIdentity`; the name `ReclaimGraphSession`
  (a parameter, a prefix of it on an `Initialize-OERAuth` call, a variable, a member, a hashtable key
  or any string) only in `Connect-OER` and `Initialize-OERAuth`, both really naming it; every
  `Register-OERSignInIdentity` call the statement directly after an `Unlock-OERSignIn` call with the
  same `-Invocation`, as many of the one as of the other; every send a wrapper makes in the body of
  a try that holds exactly one call path (in the Graph transport one `Invoke-MgGraphRequest` and one
  `Invoke-GraphAttempt`; in ARM one `Invoke-WebRequest`), that try preceded, in the very block that
  holds it and in this order, by its session gate (Graph only), its latch gate and its supersession
  gate, each a throw followed by a return, with no `Initialize-OERAuth` or `Start-Sleep` between the
  earliest gate and any request, the ARM bearer token (`.ArmToken` or `['ArmToken']`) materialized
  only after the last gate, and the transport statements counted exactly (three Graph, one ARM) so a
  new send path cannot escape the scan; and every `Initialize-OERAuth` call standing directly in
  its file's own function (in the two wrappers, in `Invoke-GraphSingle` and
  `Invoke-ArmCallWithRefresh`) and never in a nested function or a scriptblock inside it, since the
  sign-in latch is keyed on the frame that calls it.
  Two further gates in the
  same file check rules stated only in
  `docs/development/rationale.md` (every ARM api-version is documented under `#arm-transport`) or in
  no rule at all (every `Verb-OER...` token in `source/` resolves to a real function) -- ten
  `Describe` blocks in total. When a new catch trips the scrub gate, add the scrub -- do not add an
  exemption. The transport tripwire rule under these conventions is machine-checked separately, by
  `tests/QA/testhygiene.tests.ps1`.
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
   Graph catch block is mandatory, not optional. It replaces the older `$null =
   $Error.Remove($PSItem)` idiom, which never removed anything: a module's `$Error` is a private
   list distinct from the caller's, and even against the caller's `$global:Error` the `ErrorRecord`
   bound to `$PSItem` is not the same object instance PowerShell stored there, so reference-equality
   removal silently no-ops. `Remove-OERErrorRecord` instead matches on the one part of the record
   that IS reference-stable across that boundary: its `.Exception` object.

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
`ModuleVersion` is always a minimum, never an exact pin, and there is no manifest syntax for
"newest". `RequiredModules.psd1` is the build-time resolver, and by decision (2026-09-21) every
entry in it is `latest` -- **nothing there is pinned**. The two files therefore differ in KIND, not
in value, so do not reconcile them in either direction: no version number goes into
`RequiredModules.psd1`, and no `latest` goes into the manifest. The accepted cost is that CI tests
the newest combination -- what a new consumer actually gets -- while **nothing tests the declared
floors any more**.
`Why: docs/development/rationale.md#dependencies`

**No Az module is a dependency of this module, and no Az cmdlet is invoked at run time at all.**
ARM is called directly with an AzAuth token (`Invoke-OERArmRequest`). `Az.Resources` was declared in
the manifest until 2026-09-21 and was never used; it is gone. `Disconnect-OER` called
`Disconnect-AzAccount` behind a `Get-Command` guard until the same date, when that call was removed
too -- the module establishes no Az context, so it could only ever have reached the operator's own
session. `tests/QA/sourcehygiene.tests.ps1` now proves this from the source with an AST walk,
independently of what is installed.

`RequiredModules.psd1` still resolves `Az.Accounts`, for the TEST environment only: Pester's `Mock`
requires a command to exist, and two negative assertions depend on it -- `Connect-AzAccount`
`-Times 0` in `Initialize-OERAuth.Tests.ps1` and `Disconnect-AzAccount` `-Times 0` in
`Disconnect-OER.Tests.ps1`. That is not a runtime need, which is why it is absent from the table
above.

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
     `docsync.tests.ps1`/`about.tests.ps1`.
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
