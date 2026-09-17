# Contributing to Omnicit.EntraRBAC

This is a short pointer, not a restatement. The full rules live in
[`CLAUDE.md`](../CLAUDE.md) at the repository root -- read it before your first PR. Below are the
rules an outside contributor is most likely to trip over.

## First clone

```powershell
./build.ps1 -ResolveDependency -Tasks noop
```

If that fails with `Requested value 'V2' was not found` (a PSResourceGet compatibility error), add
`-UseModuleFast`:

```powershell
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast
```

## Before you open a PR

- **Never commit directly to `main`.** Branch first -- `fix/`, `feat/`, `test/`, `chore/`, or
  `refactor/` -- and open a PR. See `CLAUDE.md` "Branch Policy".
- **Build, then test, in that order:**
  ```powershell
  ./build.ps1 -Tasks build
  ./build.ps1 -Tasks test
  ```
  The test task measures coverage against the module under `output/module/`, not against
  `source/` directly, so an unbuilt change is measured stale. Build before every test run after
  changing source files.
- **80 percent code coverage is a hard floor**, enforced by the build.
- **CI runs the same two commands on three platforms.** Every pull request to `main` runs
  `./build.ps1 -ResolveDependency -Tasks build` and then `./build.ps1 -Tasks test` on Linux,
  Windows and macOS (`.github/workflows/build-and-test.yml`). Expect review once all three are
  green.
- **PowerShell 7.2+, Core only.** Never write `$env:USERPROFILE` -- it is Windows-only and this
  module targets `CompatiblePSEditions = 'Core'`.

## Source file rules

- **One function per file, and the filename must equal the function name** --
  `source/Public/Verb-OERNoun.ps1` or `source/Private/Verb-OERNoun.ps1`.
- **Public functions are listed explicitly in `FunctionsToExport`** in
  `source/Omnicit.EntraRBAC.psd1` -- never `*`.
- **Authored `.ps1` files are UTF-8 without BOM, and ASCII-only.** No em-dashes, no smart quotes,
  no box-drawing characters. Use `--` for an em-dash and straight quotes only.
- **PSScriptAnalyzer must report zero findings per function file.** A targeted suppression is only
  acceptable with a `Justification` string, for a known false positive -- never to hide a real
  finding.

## Tests

- **Pester v5**, one `*.Tests.ps1` file per source file under `tests/Unit/{Private,Public}/`. The
  QA gate requires a unit test file for every exported function.
- **Import the module by name, not by path**, in every `BeforeAll`:
  ```powershell
  BeforeAll { Import-Module Omnicit.EntraRBAC -Force }
  ```
  Importing by path breaks the Sampler coverage measurement, which targets the built module.
- **Mock `Initialize-OERAuth` and `Invoke-OERGraphRequest`** at the module boundary in every test
  that touches auth, Graph, or Azure. Nothing in CI or in tests authenticates for real.

## Everything else

Error handling, the Graph/ARM transport wrappers, argument completion, the naming engine, and the
CHANGELOG/version mechanics each have their own rules in `CLAUDE.md`. Read the section that
matches what you are touching before you touch it.
