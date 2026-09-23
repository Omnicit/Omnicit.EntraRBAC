# Verification checklist -- chore/version-cap-and-changelog-budget

**This branch does not merge until every box below has a written result.** A box with no result line
filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible to run,
write "cannot be verified, and therefore we do not know" on its result line and say why; do not leave
it blank and do not tick it.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in advance.
Write down what actually happened rather than what looked plausible.

**Status as of 2026-08-28.** Ten checks are ticked and carry a written result: 1.1, 1.2, 1.3, 1.4,
2.1, 2.2, 2.3, 3.1, 3.2 and T.1. Each result line says whether it was observed by the fix-wave
session that filled this in or recorded from the earlier build and gate runs. **Two checks are
genuinely outstanding** -- **1.5** (does CI compute a `0.x` version) and **3.3** (the
`next-version: 1.0.0` round trip, which proves the `GitVersion.yml` -> build -> gate wiring rather
than the assertion itself). Their result lines say exactly what remains unknown. **4.1 and 4.2 are
release-time records, not checks**, and stay unticked on purpose -- running either would breach the
cap.

## This branch makes NO tenant call

Nothing here reaches Microsoft Graph or Azure Resource Manager. **No Entra ID access, no Azure
access, no tenant, no consent and no `Connect-OER` is required to run this checklist**, and none of
the checks below signs in to anything. The branch changes three things and nothing else:

- `GitVersion.yml` -- `next-version: 0.8.0` and `major-version-bump-message: '(?!)'`, plus the local
  annotated tag `v1.0.0` deleted from this machine.
- `CHANGELOG.md` -- the accumulated `[Unreleased]` body archived under a new
  `## [0.7.0] - 2026-08-28` heading, and `[Unreleased]` rewritten as a release-note summary
  (7,969 -> 1,705 characters).
- `tests/QA/module.tests.ps1` -- four gates enforcing the above, plus this documentation.

`source/` is untouched, so the shipped module's behaviour is byte-identical to `main`. What needs
verifying is therefore **build and version mechanics**: what version the build computes, what text
reaches the built manifest, and that the gates hold. This document exists because none of that is
provable from reading the diff -- it is only provable by building.

## Setup, once

You need a clone of this repository on branch `chore/version-cap-and-changelog-budget`, a working
`./build.ps1 -ResolveDependency` bootstrap, and nothing else. Run every command from the repository
root.

```powershell
git rev-parse --abbrev-ref HEAD    # expect: chore/version-cap-and-changelog-budget
git status --short                 # expect: clean, or only files you are editing
```

**Run section 1 before section 2.** Section 2 measures the artefact that section 1's build produces,
and section 3 measures the gates against that same artefact. Section 4 is a record for release time
and is deliberately NOT run now.

---

### 1. Version mechanics

- [x] **1.1 No version tag, and no `release/x.y.z` name, is reachable from this branch.**

  ```powershell
  git tag -l
  git describe --tags --abbrev=0 2>&1
  git branch --show-current

  # Every merge, not a sample: one release-naming merge anywhere in history keeps supplying the
  # base indefinitely, so a bounded `git log -20` cannot answer this question.
  git log --merges --format='%h %s' | Select-String -Pattern 'release'

  # ...and the decisive form: only these two shapes make GitVersion parse a base out of a merge
  # message. Names that merely CONTAIN 'release' are matched by the broad grep above and are
  # harmless; this one matches nothing but a real hazard.
  $Hazard = "^[0-9a-f]+ Merge (branch 'releases?[/-]" +
            "|pull request #\d+ from releases?[/-])"
  git log --merges --format='%h %s' | Select-String -Pattern $Hazard
  ```

  **Expect:** `git tag -l` prints nothing at all. `git describe` fails with "No names found, cannot
  describe anything" or similar. The branch name does not begin `release/`, `releases/` or
  `release-`. The broad grep prints THREE rows today -- `chore/changelog-releasenotes-budget`,
  `docs/release-documentation` and `chore/release-blockers` -- and all three are benign: they are
  names that merely CONTAIN `release`, behind the owner prefix, and the `release:` regex is anchored
  at the start of the branch name. Do not read them as a failure. The precise detector is the one
  that must print NOTHING. GitVersion takes the greatest of the
  highest reachable version tag, `next-version`, and the `x.y.z` in a `release/x.y.z` branch name,
  so any tag at or above `0.8.0` would override `next-version` -- and a tag sitting on HEAD is
  returned verbatim whatever its value, unless a higher `release/x.y.z` name is also in play. That
  is cause 1 from `docs/development/rationale.md#version-cap`, and the reason the local `v1.0.0` tag
  was deleted rather than moved. Two things make this narrower than it sounds, both measured: the
  `release:` regex is ANCHORED at the start of the name, so `chore/release-blockers` and
  `docs/release-documentation` -- real branches from this repo -- are unaffected; and all 53 merges
  reachable here are the GitHub owner-prefixed form (`Merge pull request #77 from
  PhilipHaglund/fix/graph-retry-after`), which does NOT feed the release route.
  **Failure looks like:** any tag listed, especially `v1.0.0`. Do not delete a tag you did not create
  in this exercise -- stop and check whether it was ever pushed first. Or a `release/x.y.z` branch
  name, which needs no tag to breach the cap: measured, `release/1.0.0` builds `1.0.0` outright. The
  merge-message form is narrow -- `Merge branch 'release/2.0.0' into main` and `Merge pull request
  #99 from release/2.0.0` both trigger it, while the owner-prefixed form GitHub actually writes
  (`... from PhilipHaglund/release/2.0.0`) does not -- so read the messages, do not assume.
  **Result:** PASS -- verified 2026-08-28 by the fix-wave session. `git tag -l` printed nothing.
  `git describe --tags --abbrev=0` returned `fatal: No names found, cannot describe anything.`
  Branch is `chore/version-cap-and-changelog-budget`. 53 reachable merges, and every one of them is
  the owner-prefixed GitHub form `Merge pull request #N from PhilipHaglund/<branch>` (checked by
  negation: zero merge subjects fail to match that shape). The broad `release` grep returned the
  three benign rows named above. The precise detector returned nothing, and was falsified in the
  same session against all four hazard spellings (`Merge branch 'release/2.0.0' into main`,
  `Merge pull request #99 from release/2.0.0`, `releases/2.0.0`, `release-2.0.0` -- all matched) and
  against all four benign ones including the owner-prefixed `release/2.0.0` -- none matched. So the
  detector is not vacuous.

- [x] **1.2 Clear the GitVersion cache before measuring anything.**

  ```powershell
  Remove-Item .git/gitversion_cache -Recurse -Force -ErrorAction SilentlyContinue
  Test-Path .git/gitversion_cache
  ```

  **Expect:** `False`. This is not optional housekeeping. The cache is stale after any tag change and
  makes the very build you are about to run report the OLD version -- it has already cost one session
  in this repo. Every measurement in section 1 and section 2 is meaningless without it.
  **Failure looks like:** the path still exists (a file lock, or the build re-created it before you
  looked). Re-run the removal.
  **Result:** PASS -- 2026-08-28, recorded from the build session that produced the artefact, not
  re-run by the fix-wave session. The cache was removed and `Test-Path` returned `False` before the
  build in 1.3; that build is the one whose artefact sections 2 and 3 measure, and its reported
  version (`0.8.0-chore`) is itself the evidence that no stale cache was in play.

- [x] **1.3 A cache-cleared build computes a version below `1.0.0`.**

  ```powershell
  ./build.ps1 -Tasks build
  ```

  **Expect:** the build succeeds and the version it reports starts with `0.8.0-`. It is `0.8.0`
  exactly, and here is how to predict that: no version tag is reachable (check 1.1), so the base is
  `next-version`, and a `next-version` base takes no default increment; and no commit reachable from
  this branch carries a `+semver:` token, so nothing raises it either. `git log --grep='+semver:'
  --fixed-strings HEAD` returned zero commits on 2026-08-28. A single reachable `+semver: fix`
  commit would make it `0.8.1` and a `+semver: minor` would make it `0.9.0` -- ONE step each,
  however many such commits there are -- so a `0.8.1` or `0.9.0` reading is a bump message someone
  wrote, not a breach of the cap. See `docs/development/rationale.md#version-cap` for the measured
  tables. On `main` the prerelease label is `preview`, so a build there reads `0.8.0-preview<NNNN>`.
  On this `chore/` branch the label is derived from the branch NAME, not from a branch config:
  measured on 2026-08-28, `.git/gitversion_cache` held `NuGetVersionV2: 0.8.0-chore-version-ca0001`
  and `FullSemVer: 0.8.0-chore-version-cap-and-changelog-budget.1+924`, which Sampler split into
  `ModuleVersion = 0.8.0` plus `Prerelease = chore` in the built manifest. Do not expect a tidy
  `0.8.0-chore0001`; expect the branch name in it. The output directory is
  `output/module/Omnicit.EntraRBAC/0.8.0/`.
  **Failure looks like:** `2.0.0-preview0001`, or any version at or above `1.0.0`. That means one of
  four things: a `v1.0.0`-class tag is reachable again (see 1.1), or the branch you are on is named
  `release/x.y.z` -- or you merged one, and the merge message names it -- which computes `x.y.z`
  with no tag involved at all (also 1.1), or `major-version-bump-message` has been restored, or the
  cache was not cleared (see 1.2). Check those four in that order.
  **Result:** PASS -- 2026-08-28, from the same build session as 1.2; the manifest values below were
  re-read independently by the fix-wave session. The cache-cleared `./build.ps1 -Tasks build`
  succeeded and reported `Module Version = '0.8.0-chore'`. The artefact landed at
  `output/module/Omnicit.EntraRBAC/0.8.0/`, and its manifest carries `ModuleVersion = '0.8.0'` with
  `Prerelease = 'chore'` -- re-read directly from
  `output/module/Omnicit.EntraRBAC/0.8.0/Omnicit.EntraRBAC.psd1` in the fix-wave session, see 2.1.
  `0.8.0` is below `1.0.0`, so the cap held.

- [x] **1.4 Both levers are still in `GitVersion.yml`, and only the major one is disabled.**

  ```powershell
  Select-String -Path GitVersion.yml -Pattern '^(next-version|(major|minor|patch)-version-bump-message):' |
      ForEach-Object { $_.Line }
  ```

  **Expect:** exactly four lines --

  ```
  next-version: 0.8.0
  major-version-bump-message: '(?!)'
  minor-version-bump-message: '\+semver:\s?(feature|minor)'
  patch-version-bump-message: '\+semver:\s?(fix|patch)'
  ```

  `'(?!)'` is an empty negative lookahead: it always fails in .NET regex, so no commit message can
  trigger a major bump. Minor and patch are left working on purpose, so intent stays recorded in
  history, and they cannot reach `1.0.0` from here. With no reachable tag the base is `next-version`
  (`0.8.0`) and GitVersion applies AT MOST ONE increment, at the highest reachable `+semver:` level:
  `0.8.0`, `0.8.1` and `0.9.0` are the whole set of versions a `+semver:` BUMP MESSAGE can produce,
  and a second `+semver: minor` commit does not take it any further. Bumps only accumulate across
  RELEASES, once each release leaves a tag behind to be the next base -- and a minor increment never
  carries into major there either (`v0.9.0` plus `+semver: minor` measures `0.10.0`, `v0.99.0`
  measures `0.100.0`). Note the scope: this bounds the BUMP LEVERS only. A branch named
  `release/x.y.z`, or a standard merge message naming one, computes `x.y.z` with no tag and no bump
  message involved -- see 1.1 and the base table in `docs/development/rationale.md#version-cap`.
  **Failure looks like:** a restored major pattern, or a missing `next-version`. Either one re-opens
  the cap.
  **Result:** PASS -- verified 2026-08-28 by the fix-wave session, command run verbatim. Exactly the
  four expected lines came back, byte-for-byte as printed above: `next-version: 0.8.0`,
  `major-version-bump-message: '(?!)'`, `minor-version-bump-message: '\+semver:\s?(feature|minor)'`,
  `patch-version-bump-message: '\+semver:\s?(fix|patch)'`.

- [ ] **1.5 CI computes a `0.x` version too.**

  CI never had the local `v1.0.0` tag -- it was never pushed -- so for the pipeline this is purely
  about the `next-version` / `major-version-bump-message` change. `azure-pipelines.yml` runs
  `dotnet-gitversion` on an `ubuntu-latest` agent and sets the build number to `FullSemVer`, then
  passes `NuGetVersionV2` to `./build.ps1 -tasks pack` as `$env:ModuleVersion`. Reproduce that
  locally, or read it off the pipeline run for this branch:

  ```powershell
  dotnet tool install --global GitVersion.Tool --version 5.*   # once, if not already installed
  dotnet-gitversion | ConvertFrom-Json |
      Select-Object FullSemVer, NuGetVersionV2, MajorMinorPatch
  ```

  **Expect:** `MajorMinorPatch` is `0.8.0` and both version strings begin `0.8.0-`. If you read it
  from the pipeline instead, the "Calculate ModuleVersion (GitVersion)" step's build number is the
  same value.
  **Failure looks like:** a `1.x` or `2.x` MajorMinorPatch, which would mean the pipeline is
  resolving a tag or a bump message this repository does not expect.
  **Record:** the exact `FullSemVer` string, and whether you read it locally or from CI.
  **Result:** OUTSTANDING -- deliberately not filled in. This is one of the two checks still to run.
  `azure-pipelines.yml` has never been run for this branch, so there is no pipeline result to read;
  and no fix-wave session ran `dotnet-gitversion` on an `ubuntu-latest` agent either, so the local
  substitute would not have exercised the thing this check is for. CI never had the local `v1.0.0`
  tag -- it was never pushed -- so what is genuinely unverified here is narrow: that the
  `next-version` and `major-version-bump-message` changes compute a `0.x` version on the CI agent
  too. Run it, or read it off the first pipeline run this branch gets, and record the exact
  `FullSemVer` string plus which of the two sources it came from.

---

### 2. What actually reached the built artefact

These read `output/module/Omnicit.EntraRBAC/0.8.0/` -- the artefact produced by check 1.3. Rebuild
before running them if you have edited `CHANGELOG.md` since.

**Superseded thresholds, noted 2026-09-23 (P14).** The 500-character floor and the 400-character
tail comparison in 2.1-2.3 are the gates as this branch built and verified them, and the results
below record exactly that; they are left as measured. The QA gate no longer uses either. It now
holds the body after the heading line to at least 50 characters, in the source and in the built
manifest, compares the whole published body with the source body exactly, and checks that the
published heading names the built version. Re-running 2.1-2.3 as written tests the old thresholds,
not the current gate. `Why: docs/development/rationale.md#changelog-budget`

- [x] **2.1 Read the built manifest's version and release notes.**

  ```powershell
  $Manifest = Import-PowerShellDataFile ./output/module/Omnicit.EntraRBAC/0.8.0/Omnicit.EntraRBAC.psd1
  $Notes    = $Manifest.PrivateData.PSData.ReleaseNotes
  [pscustomobject]@{
      ModuleVersion = $Manifest.ModuleVersion
      Prerelease    = $Manifest.PrivateData.PSData.Prerelease
      NotesLength   = $Notes.Length
      FirstLine     = ($Notes -split "`n")[0]
  } | Format-List
  ```

  **Expect:** `ModuleVersion` is `0.8.0` and is below `1.0.0`; `Prerelease` is the branch-derived
  label; `NotesLength` is between 500 and 10,000 and NOT exactly 10,000 (exactly 10,000 is Sampler's
  truncation signature -- it cuts with `.Substring(0, 10000)`); `FirstLine` is the rewritten dated
  heading `## [0.8.0-chore] - 2026-08-28` and NOT `## [Unreleased]`. Measured on 2026-08-28:
  `NotesLength` 1719.
  **Failure looks like:** an empty or absent `ReleaseNotes` -- that is the issue #39 defect itself, a
  release shipped with no notes -- or a `## [Unreleased]` first line, which would mean
  `Create_changelog_release_output` did not run.
  **Result:** PASS -- verified 2026-08-28 by the fix-wave session, command run verbatim against
  `output/module/Omnicit.EntraRBAC/0.8.0/Omnicit.EntraRBAC.psd1`. `ModuleVersion : 0.8.0`,
  `Prerelease : chore`, `NotesLength : 1719`, `FirstLine : ## [0.8.0-chore] - 2026-08-28`. So the
  version is below `1.0.0`, the notes sit between the 500 floor and the 10,000 ceiling and are not
  the exactly-10,000 truncation signature, and the heading was rewritten from `## [Unreleased]`.

- [x] **2.2 The published notes end where the source `[Unreleased]` section ends.**

  Truncation always removes the END, so comparing tails is what proves nothing was cut. This is the
  same comparison the QA gate makes, run by hand so you can read both strings.

  ```powershell
  Import-Module ./output/RequiredModules/ChangelogManagement -Force
  $Source = (Get-ChangelogData -Path ./CHANGELOG.md).Unreleased.RawData
  $Notes  = (Import-PowerShellDataFile ./output/module/Omnicit.EntraRBAC/0.8.0/Omnicit.EntraRBAC.psd1).PrivateData.PSData.ReleaseNotes
  [pscustomobject]@{
      SourceLength = $Source.Length
      NotesLength  = $Notes.Length
      Gap          = $Notes.Length - $Source.Length
      TailsMatch   = $Notes.TrimEnd().Substring($Notes.TrimEnd().Length - 400) -ceq
                     $Source.TrimEnd().Substring($Source.TrimEnd().Length - 400)
  } | Format-List
  $Notes.TrimEnd().Substring($Notes.TrimEnd().Length - 120)
  ```

  **Expect:** `TailsMatch` is `True`, and the last 120 characters printed are the final sentence of
  `CHANGELOG.md`'s `[Unreleased]` section, complete, ending in a full stop -- not cut mid-word.
  `SourceLength` is 1705 and `NotesLength` 1719 as measured on 2026-08-28; the `Gap` is the
  heading-length difference (`## [0.8.0-chore] - 2026-08-28` is 29 characters against 15 for
  `## [Unreleased]`, minus the same 2 trimmed trailing characters on both sides = 14) and it grows
  with a longer version label. The absolute lengths will drift as the section is edited; the `Gap`
  being small and positive, and `TailsMatch` being `True`, are the durable expectations.
  **Failure looks like:** `TailsMatch` `False` with a complete-looking note -- then `output/module/`
  is stale, so rebuild and re-measure. `TailsMatch` `False` with a note that stops mid-sentence is
  the real defect.
  **Result:** PASS -- verified 2026-08-28 by the fix-wave session, command run verbatim.
  `SourceLength : 1705`, `NotesLength : 1719`, `Gap : 14`, `TailsMatch : True`. The last 120
  characters printed were: "reports a `0.x` version. The cap is a release decision, not a
  downgrade, and is / lifted when that release is published." -- a complete final sentence ending in
  a full stop, not a mid-word cut. The `Gap` of 14 is exactly the predicted heading difference
  (29 - 15 = 14).

- [x] **2.3 The source `[Unreleased]` section is inside its budget, with room to spare.**

  ```powershell
  $Source = (Get-ChangelogData -Path ./CHANGELOG.md).Unreleased.RawData
  "{0} characters; floor 500, ceiling 4000; headroom {1}" -f $Source.Length, (4000 - $Source.Length)
  (Get-ChangelogData -Path ./CHANGELOG.md).Released[0].RawData.Substring(0, 40)
  ```

  **Expect:** a length comfortably between 500 and 4,000 (measured 2026-08-28: 1,705, headroom
  2,295), and the newest released section beginning `## [0.7.0] - 2026-08-28`. The point of the
  archive is that the headroom is real again: issue #61 was 31 characters of it.
  **Failure looks like:** a length near either bound, or a newest dated heading that is still
  `## [0.6.0] - 2026-08-20`, which would mean the archive heading was not added.
  **Result:** PASS -- verified 2026-08-28 by the fix-wave session, commands run verbatim.
  `1705 characters; floor 500, ceiling 4000; headroom 2295`, and the newest released section begins
  `## [0.7.0] - 2026-08-28`. `Get-ChangelogData ... .Released` parses cleanly into seven sections
  with their original dates: 0.7.0 (2026-08-28), 0.6.0 (2026-08-20), 0.5.0 (2026-08-15), 0.4.0
  (2026-08-14), 0.3.0 (2026-08-12), 0.2.0 (2026-08-11) and 0.1.0 (2026-06-05) -- so the archive
  added a heading rather than rewriting or losing any existing one.

---

### 3. The gates

- [x] **3.1 The full gate is green and coverage holds.**

  ```powershell
  ./build.ps1 -Tasks test
  ```

  **Expect:** 0 failed tests and code coverage at or above the 80% threshold in `build.yaml`
  (the tree has been running around 91-92%). Note that `build.yaml`'s `test` workflow does NOT
  include `build`, so this must be run AFTER check 1.3 and after any `CHANGELOG.md` edit -- the two
  artefact-side gates compare the built manifest against the current `CHANGELOG.md`, and a stale
  `output/module/` turns them red. That is the intended direction of failure, not a bug.
  **Record:** the passed/failed counts and the coverage percentage.
  **Result:** PASS -- run 2026-08-28, before the documentation fix wave. 4813 passed, 0 failed,
  0 skipped, 0 NotRun; code coverage 91.98% against the 80% threshold in `build.yaml`. That run
  wrote `output/testResults/NUnitXml_Omnicit.EntraRBAC_v0.8.0-chore.Windows.PSv.7.6.5.xml`, which is
  the file check 3.2 reads. The fix wave that followed changed only comments, `-Because` message
  text and Markdown, so it cannot move these counts; the two QA files were nevertheless re-run
  afterwards and stayed green (see 3.2).

- [x] **3.2 The four release gates are present and each one passed.**

  Read this off the NUnit XML that Sampler always writes, NOT by filtering the console output.
  Pester renders its `Detailed` output to the HOST, not to the success or error stream, so
  `./build.ps1 -Tasks test 2>&1 | Select-String ...` captures **nothing at all** while the test
  names print on screen -- measured in this repo: `Invoke-Pester -Output Detailed 2>&1` yields zero
  objects. An operator who filtered the console output would record a false failure on a run that
  actually passed.

  ```powershell
  ./build.ps1 -Tasks test

  ([xml](Get-Content ./output/testResults/NUnitXml_*.xml)).SelectNodes('//test-case') |
      Where-Object { $_.name -match 'Changelog|version below 1\.0\.0|ReleaseNotes' } |
      Select-Object name, result
  ```

  The XML is written per built version, so the glob resolves to
  `NUnitXml_Omnicit.EntraRBAC_v<version>.<platform>.PSv<psversion>.xml`. If the glob matches more
  than one file, delete the stale ones or name the current one explicitly -- `[xml]` over a
  concatenation of two documents throws.

  **Expect:** exactly six rows, every `result` reading `Success`, with these `name` values --

  ```
  Changelog Management.Changelog has been updated                                          Success
  Changelog Management.Changelog format compliant with keepachangelog format               Success
  Changelog Management.Changelog should have an Unreleased header                          Success
  Changelog Management.Changelog Unreleased section fits the published ReleaseNotes budget Success
  Changelog Management.Built manifest ReleaseNotes is populated and not truncated          Success
  Release version cap.Should build a version below 1.0.0                                   Success
  ```

  The last three are the ones this branch added or changed. `Changelog has been updated` does not
  require a `CHANGELOG.md` entry from a PR that changes nothing under `source/`; this branch does
  change `CHANGELOG.md`, so it is satisfied either way.
  **Failure looks like:** fewer than six rows -- a test missing from the run is a `-Skip` that
  fired or a Describe that did not discover, and that is indistinguishable from a pass in the
  summary counts, which is the whole reason for reading names rather than totals. Or any `result`
  other than `Success`. A `Get-Content` error instead of rows means no gate run has happened since
  the last clean, so run `./build.ps1 -Tasks test` first.
  **Result:** PASS -- verified 2026-08-28 by the fix-wave session. The query was run against the
  existing `output/testResults/NUnitXml_Omnicit.EntraRBAC_v0.8.0-chore.Windows.PSv.7.6.5.xml`
  written by the 3.1 gate run, and returned exactly the six rows listed above, all
  `result="Success"`. The glob matched that one file only. The old console-filtering command was
  replaced as part of this session after being measured to capture zero lines.

- [ ] **3.3 The version cap fails when it should.** Optional but recommended; it is the only way to
  see the gate is not inert.

  Temporarily edit `GitVersion.yml` to `next-version: 1.0.0`, clear `.git/gitversion_cache`, rebuild,
  and run just the release gates:

  ```powershell
  ./build.ps1 -Tasks build

  # Required. Outside ./build.ps1 nothing puts the built module or the build-time
  # dependencies on PSModulePath, so a bare Invoke-Pester here fails 5 of the 6 gates
  # on resolution -- Get-ChangelogData not found, and the cap failing with "must resolve
  # from PSModulePath" rather than with a version. That reads exactly like the
  # falsification succeeding when it has not run at all.
  $Sep = [System.IO.Path]::PathSeparator
  $env:PSModulePath = "$PWD/output/RequiredModules$Sep$PWD/output/module$Sep$env:PSModulePath"
  Import-Module Pester -MinimumVersion 5.7.1 -Force

  Invoke-Pester -Path ./tests/QA/module.tests.ps1 -TagFilter Changelog -Output Detailed
  ```

  Discovery over this file dominates the wall time -- it enumerates all 1,344 tests in the file
  before the tag filter narrows them to six. Measured 2026-08-28: 28.1s of discovery on a cold run
  and 2.7s on an immediately repeated one, so expect anything from a few seconds to about half a
  minute. That is normal, not a hang. `./build.ps1 -Tasks test` does the same job without the path
  setup, if you would rather wait for the whole suite.

  **Expect:** exactly one failure, `Should build a version below 1.0.0`, and its message names the
  version that was built (`the module built 1.0.0...`). The other five stay green. Then restore
  `GitVersion.yml`, clear the cache again, rebuild, and confirm all six pass.
  **Failure looks like:** it still passes at 1.0.0 -- the gate is inert and must be fixed before
  merge. Or several gates fail with resolution errors instead of assertion messages, which means the
  `PSModulePath` line above did not take: that is a broken harness, not a falsified cap, and it must
  not be recorded as one.
  **Result:** OUTSTANDING -- deliberately not filled in. This is the second of the two checks still
  to run, and it is worth being precise about what it would add. The version-cap assertion HAS been
  falsified, but by a different route: a fabricated `1.0.0` module was put on `PSModulePath` and the
  gate went red with the expected message, which proves the assertion is not inert. What that does
  NOT prove is the loop this check exercises end to end -- that editing `next-version: 1.0.0` in
  `GitVersion.yml` actually propagates through a cache-cleared `./build.ps1 -Tasks build` into the
  built artefact's version, and that the gate then reads THAT version and fails on it. In other
  words: the assertion is known good, the `GitVersion.yml` -> build -> gate wiring is not. Run it if
  you want the wiring proven too.

  **After restoring:** confirm `git diff GitVersion.yml` is empty and the rebuilt version is back to
  `0.8.0-*`.
  **Result:** OUTSTANDING -- nothing to restore, since 3.3 was not run. `git diff GitVersion.yml`
  was confirmed empty at the end of the fix-wave session regardless, and the built artefact is
  `0.8.0`.

---

### 4. Release-time record -- do NOT run any of this now

This section is a record, not a set of checks to perform on this branch. Running it would re-breach
the cap that this branch exists to hold.

- [ ] **4.1 The deleted `v1.0.0` tag, and how to recreate it when the release is actually called.**

  The tag deleted from this machine was:

  | Field | Value |
  |---|---|
  | Name | `v1.0.0` (annotated) |
  | Commit | `778601a22d5b4e9188d71af6f3014f04f55d799e` |
  | Tagger | Philip Haglund, `1787085997 +0200` (email address deliberately omitted -- see below) |
  | Message | `Omnicit.EntraRBAC 1.0.0` |

  It was never pushed, and nothing was ever published from it. Recreation command:

  ```powershell
  git tag -a v1.0.0 778601a22d5b4e9188d71af6f3014f04f55d799e -m 'Omnicit.EntraRBAC 1.0.0'
  ```

  Three things to know before anyone runs it. First, exactly one field is withheld above: the
  tagger's **email address**. The tagger name and the raw date are kept, since both are needed to
  reproduce the tag faithfully. The address is the author ident on every commit on this branch, so
  nothing is hidden by dropping it, but PR #50 exists because tracked documents accumulated
  identifiers that did not need to be there. Second, **the command above does not reproduce the
  original tagger date on its own**: git stamps the current time unless `GIT_COMMITTER_DATE` and
  `GIT_TAGGER_DATE` are exported from the recorded `1787085997 +0200` first. That hardly matters,
  because of the third point: **recreating this tag at all would re-breach the cap**, since
  `v1.0.0` is above `next-version` and a reachable tag that high becomes GitVersion's increment
  base. It belongs at real release time, on the commit
  that actually ships -- which will not be `778601a`, as that commit is now many commits behind
  `main`, and which will want its own tagger date anyway.
  **Expect:** this box stays unticked and its result line reads that nothing was run.
  **Result:** NOT RUN, deliberately -- 2026-08-28. This is a release-time record, not a check. No
  tag was created, deleted or moved in this repository by the fix-wave session; `git tag -l` is
  still empty (see 1.1). Running the recreation command now would put a reachable `v1.0.0` back in
  play as GitVersion's base and re-breach the cap this branch exists to hold.

- [ ] **4.2 The full list of what must be lifted together at release time.**

  For the record, so it is not done piecemeal:

  1. `GitVersion.yml` -- restore `major-version-bump-message` to
     `'(\+semver:\s?(breaking|major))|(^[a-z]+(\(.+\))?!:)'` (the original is quoted in the file's own
     comment) and set `next-version` to the real release number.
  2. Delete `.git/gitversion_cache`, rebuild, and confirm the computed version.
  3. Create the annotated tag on the commit that ships.
  4. Raise the `Should build a version below 1.0.0` assertion in `tests/QA/module.tests.ps1` to match
     the new policy -- **never on its own, and never merely to make a build pass**.
  5. Restore the `publish:` workflow in `build.yaml`, which is deliberately absent and is the only
     brake that lives in the repository.

  This list is the authority for the release-time lift; the closing paragraph of
  `docs/development/rationale.md#version-cap` names the same steps in prose and points here.

  **Expect:** this box stays unticked until that day.
  **Result:** NOT RUN, deliberately -- 2026-08-28. Every step here raises the version or removes a
  brake, so running any of them now would breach the cap this branch exists to hold. Recorded so the
  lift happens as one deliberate act rather than piecemeal.

---

### Teardown

- [x] **T.1 Nothing to undo in any tenant.** No sign-in happened, no directory object was read or
  written, and no consent was granted. The only local side effects are `output/` (a build artefact,
  git-ignored) and `.git/gitversion_cache` (regenerated on demand). If check 3.3 was run, confirm
  `git diff GitVersion.yml` is empty.
  **Result:** PASS -- verified 2026-08-28 by the fix-wave session. Nothing to undo in any tenant: no
  sign-in, no directory object read or written, no consent. `git diff GitVersion.yml` is empty
  (check 3.3 was not run, so there was nothing to restore). `git tag -l` returns nothing and
  `refs/tags` is empty -- no tag was created, deleted or moved in this repository. `output/` and
  `.git/gitversion_cache` are present and both git-ignored. The throwaway GitVersion repositories
  used to re-measure the increment rules were built under the session scratchpad, never inside this
  repository, and were deleted afterwards. The only tracked files modified are `CLAUDE.md`,
  `docs/development/rationale.md`, this checklist and `tests/QA/module.tests.ps1`.
