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

**Merge requirements, enforced by GitHub on `main`:**

- **Three status checks are required: `ubuntu-latest`, `windows-latest` and `macos-latest`.** Those
  names come from the build-and-test matrix's `name: ${{ matrix.os }}`, so the job name IS the
  required check name -- renaming the job, or changing the matrix, orphans the protection rule and
  blocks every open PR until the rule is renamed to match. Change both together.
- **The branch must be up to date with `main` before it can merge.** A branch that has fallen
  behind is rebased onto `main` and force-pushed; the checks then re-run against the rebased tip.
- **Linear history is required**, so a merge commit is refused. Squash merge is the convention here.
- **Every conversation on the PR must be resolved** before merge.

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

`Omnicit.EntraRBAC` is a PowerShell 7.2+ (Core-only) module built by Omnicit AB for its own and its
customers' tenants. MIT licensed and **published on the public PowerShell Gallery**: 1.0.0 went out
by hand on 2026-09-18, and everything since publishes itself -- see **Publishing** below.

It manages RBAC building blocks across many Entra ID and Azure tenants: Entra ID groups, PIM,
Administrative Units, Entitlement Management, Access Reviews, Azure resources and RBAC, plus a JSON
inventory and a declarative apply engine. Command prefix is `OER`.

**The canonical working tree is `C:\Git\Omnicit.EntraRBAC.public`, tracking
`github.com/Omnicit/Omnicit.EntraRBAC`.** The older clone is the private repository's working copy
and is to be archived; do not commit to it, and do not treat a change made there as made. Two live
clones of one module is how a fix lands in the wrong repository -- that has already happened here.

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
  QA/                         # Six gate files (below), all run by ./build.ps1 -Tasks test
  Unit/Private/, Unit/Public/ # One *.Tests.ps1 per source file, plus the named exceptions below
  Unit/Formats/               # FormatViews.Tests.ps1 -- format-view rendering checks
  Unit/TestHelpers/           # Not a Pester directory. OERConfirmHost.ps1 hosts a runspace whose
                              #   PSHost answers ShouldProcess prompts -- the only way to test a
                              #   genuine DECLINE or to read the prompt/target text.
build.yaml, build.ps1         # Sampler/ModuleBuilder config and bootstrap entry point
RequiredModules.psd1          # Build-time dependency resolver (NOT the runtime pin -- see Dependencies)
azure-pipelines.yml           # Build + Test only, no Deploy stage -- it never publishes
.github/workflows/build-and-test.yml  # Build + Test on Linux, Windows, macOS, then package and
                              #   publish. The ONLY path that publishes -- see Publishing.
.github/scripts/PublishArtefact.ps1   # -Record / -Verify: proves the published bytes are the
                              #   tested bytes. Single owner of both halves; do not split it.
```

There is **no `source/Classes` directory**. The loader iterates one, but argument completion is
scriptblock-based instead. `Why: docs/development/rationale.md#completers`

**The build-and-test job's `if:` condition is now wired to the merge gate -- do not read it as a
billing guard alone, and do not reason about it from GitHub's general rule for skipped jobs.** The
job is declared
`if: ${{ !github.event.repository.private || github.event_name == 'workflow_dispatch' }}`, because
standard runners are free and unmetered only on a PUBLIC repository. `ubuntu-latest`,
`windows-latest` and `macos-latest` are REQUIRED checks on `main`, and that condition decides
whether those three checks ever come into existence.

**The mechanism is the MATRIX, not the skip.** GitHub documents the opposite of what happens here:
a job skipped by a condition reports Success and does NOT block a pull request ("Troubleshooting
required status checks"). That rule does not rescue this workflow, because `build-and-test` is a
matrix job and a job-level `if:` is evaluated BEFORE the matrix expands. The three legs are
therefore never created, so nothing ever reports the three check names -- and a required check that
never reports stays pending forever instead of passing (community discussion #9141). Make this
repository private again and every pull request blocks permanently, including the pull request that
would fix it. Turning the repository private is therefore a change to this condition, or to the
protection rule, made in the SAME change and never afterwards.

**Rewriting this workflow as three separate jobs without a matrix INVERTS the failure, into the
worse one.** Without a matrix there is nothing to expand: the job-level `if:` would then skip three
jobs that do exist, each would report Success under the documented rule, and the merge gate would
go GREEN having run not one test. The matrix is what makes a skip fail loudly here, so keep it --
or, if the jobs are ever split, make the required checks something a skipped job cannot satisfy.

**Do not maintain a function roster in this file.** Read it from the tree instead:

```powershell
Get-ChildItem source/Public  -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
Get-ChildItem source/Private -Filter '*.ps1' | Select-Object -ExpandProperty BaseName | Sort-Object
```

`README.md` section "Available Cmdlets" is the maintained, cohort-grouped list of every exported
cmdlet; `Get-OERRequiredScope` reports the Graph/Azure permissions each one needs.

**The six QA gates** (`tests/QA/`): `module.tests.ps1` (manifest, changelog, help, README,
per-function PSScriptAnalyzer, and a unit test file for every exported function),
`about.tests.ps1` (the about topic is byte-identical to source, ASCII/BOM-free, and names every
exported cmdlet and no other), `requiredscope.tests.ps1` (`Get-OERRequiredScopeMap` vs the module's
own call graph), `sourcehygiene.tests.ps1` (the eight static source gates --
`Why: docs/development/rationale.md#static-source-gates`), `dochygiene.tests.ps1` (keeps unredacted
tenant object ids, non-documentation email addresses and credentials out of every tracked file under
`docs/`, `specs/`, `source/` and `tests/`, enumerating tracked files with `git ls-files` and reading
their content from disk), and `docsync.tests.ps1` (binds `README.md` to the about topic).

**`dochygiene.tests.ps1` applies TWO object-id rules, split by what the file is.** Under `docs/` and
`specs/` a GUID is prose, so it must be a `00000000-0000-0000-0000-0000000000NN` placeholder. Under
`source/` and `tests/` a GUID is a fixture, so the rule is that it must not have **version-4 shape**:
every Entra ID and ARM object id is v4 and no invented fixture needs to be, which leaves the roughly
seventy existing `1111...`/`aaaa...` fixtures untouched and still readable. Exactly three v4 values
are pinned by name -- the module's own manifest GUID, the Microsoft Graph Command Line Tools app id,
and the Reader built-in role definition id. **Do not add a fourth: allocate a placeholder instead**,
from the register in `docs/live-verification/README.md`, which also records the next free
`...NNN` and `personN`. A credential-shaped literal that a test needs (the bearer-scrub fixtures)
must carry `NOT-A-REAL-TOKEN` inside the VALUE; `REDACTED` works the same way.
`Why: docs/development/rationale.md#bearer-scrub-tests`

**`docsync.tests.ps1` holds `README.md` and the about topic against each other.** Each already had
its own "names every exported cmdlet" check, but both matched the whole FILE, so a cmdlet mentioned
only in a Quick Start snippet passed while missing from the roster. This gate scopes the roster to
`## Available Cmdlets` and `COMMAND COHORTS`, checks each `### Cohort (N)` count against the cmdlets
that cohort is the FIRST to name, and requires the two documents to agree word for word on the
tenant-switch verdict per sign-in type and on the device-code known limitation. It deliberately does
NOT bind the surrounding prose -- the sovereign-cloud, tenant-profile and permissions sections are
rewritten per medium on purpose.

**Test files named after no single function.** Six cross-cutting suites exist. Do **NOT** delete
any of them as an orphan when auditing the one-test-file-per-function invariant:

- `Unit/Private/BasePathDefault.Cohort.Tests.ps1` -- asserts all seven `-BasePath`/`-ProfileBasePath`
  default carriers resolve cross-platform (issue #40). It sits under `Private/` because five of the
  seven carriers are public and two are private, so it belongs to neither cohort exclusively. Do not
  "fix" its location by moving it.
- `Unit/Public/AccessReview.Pipeline.Tests.ps1` -- cross-cmdlet pipeline suite.
- `Unit/Public/AmbiguousName.Guard.Tests.ps1` -- asserts every public call site of an
  ambiguity-refusing `Resolve-OER*Id` helper surfaces the candidate ids instead of a first match.
- `Unit/Public/NothingToUpdate.Cohort.Tests.ps1` -- asserts every `Set-OER*` cmdlet (all eleven)
  reports the no-updatable-property condition as `NothingToUpdate`, and that
  `Set-OERRoleManagementPolicy`'s separate "no rule differs" case keeps its distinct `NoChange` id.
- `Unit/Public/GroupAliasOrder.Cohort.Tests.ps1` -- AST-driven: asserts every `source/Public/*Group*.ps1`
  file declaring a `-Group` parameter lists the `GroupId` alias before the generic `Id` alias, so a
  piped principal can never mis-bind as the piped group.
- `Unit/Public/AdministrativeUnitAliasOrder.Cohort.Tests.ps1` -- the same AST-driven pattern for every
  `-AdministrativeUnit` parameter, so a piped member's own `Id`/`DisplayName` can never mis-bind as
  the piped parent unit.

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
# (measured 91.97% over 13,757 commands on a clean tree -- identical locally and on all three
#  CI runners)
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
  exists: a run that never happens never reports the three required checks, and a required check
  that never reports stays Pending forever.
- **The publish job tags every publish, and the tag is load-bearing.** `GitVersion.yml` runs
  `mode: ContinuousDelivery`, where the preview counter advances on a TAG and not per commit:
  measured, two merges with no tag between them build the SAME version and the second publish is
  refused by the Gallery. If a publish succeeds but the tag step fails, the next merge publishes
  nothing (the idempotence check skips it); push the missing tag by hand onto the commit that was
  published. `Why: docs/development/rationale.md#publish-on-merge`
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

1. Push `v<X.Y.Z>` on the `main` tip, once that commit's three checks are green. Only the
   `Stable Version` ruleset's bypass list can create that tag -- today the users PhilipHaglund and
   M2ckan, plus the Repository admin role -- and the push IS the release decision: nothing asks for
   an approval after it. A tag outside the `Entra RBAC` environment's patterns (a major of 10 or
   more, or a minor or patch of 100 or more) is refused by the environment, visibly, and publishes
   nothing; the repair is a new pattern the ruleset also covers, never a return to `v*`.
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
auth identity, **and cloud**. `Why: docs/development/rationale.md#auth-state`

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
`Disconnect-OER` clears `$script:_OERAuthState` and calls `Disconnect-MgGraph`. It deliberately does
NOT call `Disconnect-AzAccount`: the module establishes no Az context, so any Az session on the
machine is the operator's own (Philip's decision, 2026-09-21).
`Why: docs/development/rationale.md#sovereign-clouds`

**IMPORTANT:** `-ClientSecret` is a `[securestring]`. Never accept or store client secrets as plain
strings.

**Same-session tenant switch is limited by sign-in type.** AzAuth keeps ONE credential for the
whole process, and `Get-AzToken -Tenant` is not honoured by every credential type: the device code
and managed identity requests do not carry the named tenant at all (measured), with a device-code
credential reused after a successful sign-in passing it on for a silent re-acquisition instead
(inferred), and a client secret credential refuses a different tenant until `-Force` rebuilds it
(or, with `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH` set, silently requests the token from the previous
tenant; measured).
`Initialize-OERAuth` warns when it can see a switch did not take effect and never refuses the
sign-in itself (a `-WarningAction Stop`/`$WarningPreference = 'Stop'` caller does still stop it, at
the `Write-Warning` call); `Connect-OER -Force` is the only public lever. Never "fix" a switch by
adding an automatic `-Force` without a new decision -- and weigh one knowing that, measured, a
device-code sign-in without `-Force` that reuses a credential which has already completed a sign-in
and names a different tenant never returns.
`Why: docs/development/rationale.md#auth-state`,
`docs/development/rationale.md#switching-tenants-in-one-process`

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
- **`Resolve-OERReviewerScopeQuery` is the single owner of the access review reviewer scope query
  grammar.** Never re-implement the `/users/` and `/groups/` regex pair inline; `./manager` is
  matched FIRST, always, and an `Unparsed` scope is NOT the same as an empty reviewers collection.
  `Why: docs/development/rationale.md#reviewer-scope-query`
- **`Test-OERGuid` is the single GUID predicate.** Never re-implement the canonical GUID regex
  inline. The wider `-as [guid]` cast in `Get-OERInventory` and `New-OERGroup` is a deliberate
  exception -- do not migrate those two. `Why: docs/development/rationale.md#guid-predicate`
- **`Resolve-OERPimActivationConflict` is the single owner of the MFA / authentication-context
  mutual-exclusion rule.** An enabled authentication context and `MultiFactorAuthentication` on
  activation cannot both be in force. All three call sites -- the Graph group write path, the apply
  diff, and the ARM patch builder -- take the DECISION from this helper and apply it in their own
  idiom. Never re-implement the check inline. The ARM transport additionally passes
  `-ResolveUnrequestedConflict` because it PATCHes the full rule set.
  `Why: docs/development/rationale.md#mfa-authcontext-exclusion`
- **`Get-OERCloudEndpoint` is the single owner of the cloud-to-endpoint table.** Every Graph
  resource/audience, Graph service root, ARM resource/host and authority (STS) host for a sovereign
  cloud is read from it; never hardcode one of those hosts a second time. `source/Private/Invoke-OERArmRequest.ps1`
  keeps one documented public-cloud fallback for the no-auth-state case, exempted by name rather than
  deleted. `tests/QA/sourcehygiene.tests.ps1` machine-checks this the same way it checks the other
  single-owner rules above. `Why: docs/development/rationale.md#sovereign-clouds`

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

**PIM-for-Groups is deliberately pinned to the Graph `beta` endpoint.** All eight call sites route
through the private `Get-OERPimGroupsGraphPath`, which owns the version constant. Never hardcode
`beta/` at a call site -- change the constant in the helper. The eligibility paths and the four
policy paths migrate as ONE unit. `Why: docs/development/rationale.md#pim-beta-pin` Beta endpoint
availability in US Government and China clouds is not established -- a standing risk, not a bug --
recorded at `Why: docs/development/rationale.md#sovereign-clouds`.

---

## ARM Requests

**All ARM calls go through `Invoke-OERArmRequest`.** The module deliberately does NOT use
`Connect-AzAccount`/`Invoke-AzRestMethod`: Az.Accounts cannot reliably reuse an externally acquired
AzAuth token. `Initialize-OERAuth -IncludeARM` caches the ARM bearer token as a SecureString and the
wrapper sends it directly, materializing the plaintext only at the request boundary and clearing it
in a `finally`. The ARM host is read from the session's cloud (`Get-OERCloudEndpoint`'s `ArmResource`
field via `-Environment`), not hardcoded to public-cloud ARM; `Invoke-OERArmRequest` keeps
`https://management.azure.com` as a documented fallback for a call made before any auth state exists,
so it fails on the missing token rather than on a null host -- do not delete that fallback.

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

- **Pester v5** under `tests/Unit/{Private,Public}/`. One `*.Tests.ps1` per source file. The QA gate
  (`tests/QA/module.tests.ps1`) requires a unit test file for every exported function.
- **Import by module name, not by path**, in every `BeforeAll` -- importing by path breaks the
  Sampler coverage measurement, which targets the built module:
  ```powershell
  BeforeAll { Import-Module Omnicit.EntraRBAC -Force }
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
- **Mock `Invoke-OERGraphRequest`, not `Invoke-MgGraphRequest`** -- the call stack goes through the
  wrapper, so mocking the raw SDK call has no effect.
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
- **Six rules in this file are machine-checked** by `tests/QA/sourcehygiene.tests.ps1`: ASCII/BOM
  encoding; bearer-scrub-first in every transport-reaching catch; `ConvertTo-OERDuration` as the sole
  int-to-ISO encoder; the `suffix.ps1`/dev-mode-psm1 mirroring; `Get-OERCloudEndpoint` as the sole
  owner of the cloud-to-endpoint table; and `Test-OERDeclaredProperty`/`Test-OERDeclaredNull` as the
  single owners of the apply engine's declared-value rule (no direct read of a node's
  `PSObject.Properties.Name` in a `Sync-OERStructure*` handler outside the named, reasoned
  allowlist -- flagged on the read itself, not on the `-contains`-family operator that might later
  consume it, so an intermediate variable cannot hide the same defect). Two further gates in the
  same file check rules stated only in
  `docs/development/rationale.md` (every ARM api-version is documented under `#arm-transport`) or in
  no rule at all (every `Verb-OER...` token in `source/` resolves to a real function) -- eight
  `Describe` blocks in total. When a new catch trips the scrub gate, add the scrub -- do not add an
  exemption.
  `Why: docs/development/rationale.md#static-source-gates`

---

## SECURITY (Hard Rules - High Privilege)

This module manages **very high Entra ID privileges** across customer tenants. These rules are
non-negotiable:

1. **Claude and CI must never make sharp/live calls against a real tenant.** All live testing is
   performed manually by the user with extreme care.
2. **Every test mocks `Get-AzToken`, `Connect-MgGraph`, `Connect-AzAccount`, and
   `Invoke-OERGraphRequest`.** Nothing in CI or tests authenticates for real.
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
| `Microsoft.Graph.Authentication` | 2.36.0 | `Connect-MgGraph -AccessToken` and `Invoke-MgGraphRequest` (inside wrapper) |

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
3. **Call `Initialize-OERAuth`** at the entry point (`begin` block or top of `process`) for any
   function that calls Graph or Azure. Pass `-IncludeARM` for functions that call ARM.
4. **Route all Graph calls through `Invoke-OERGraphRequest`.** Never call `Invoke-MgGraphRequest`
   directly.
5. **Tag output:** convert the response to `[PSCustomObject]`, insert a type name, add a `<View>`
   in `source/Formats/Omnicit.EntraRBAC.Format.ps1xml`, and -- if a ScriptProperty member is needed
   -- register it inline with `Update-TypeData -Force` in `source/suffix.ps1` (and mirror it in the
   dev-mode `source/Omnicit.EntraRBAC.psm1` loader).
6. **Add full comment-based help:** `.SYNOPSIS`, `.DESCRIPTION`, one `.PARAMETER` per parameter,
   at least one `.EXAMPLE`.
7. **Add a unit test file:** `tests/Unit/{Public|Private}/Verb-OERNoun.Tests.ps1`. Import by
   module name in `BeforeAll`. Mock `Initialize-OERAuth` and `Invoke-OERGraphRequest`.
8. **Keep the file ASCII-only** and UTF-8 without BOM.
9. **Run `./build.ps1 -Tasks test`** before committing -- it is the authoritative gate.

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
