## Summary

<!-- What does this PR change, and why. -->

## What a reviewer should look at first

<!-- Point at the one file or change that matters most; do not make the reviewer guess. -->

## Checklist

- [ ] Branch is not `main`, and follows the naming convention: `fix/`, `feat/`, `test/`, `docs/`,
      `chore/`, `refactor/`, or `ci/` (see `CLAUDE.md` "Branch Policy").
- [ ] `CHANGELOG.md` `[Unreleased]` is updated if anything under `source/` changed. The
      changed-file gate fires only on a path matching `^source/`, so a PR that touches nothing
      under `source/` is not required to touch the changelog. The `[Unreleased]` heading itself is
      never converted or renamed by hand -- the build does that at release time. The FIRST merge
      after a stable `v<X.Y.Z>` tag is the close-out: it moves the released notes under a new
      `## [X.Y.Z] - <date>` heading and leaves `[Unreleased]` holding only the fixed close-out
      sentence for X.Y.Z (see `CLAUDE.md` "CHANGELOG and Version"). The first change under
      `source/` after a close-out REPLACES that sentence with a note of its own, never adds to it.
- [ ] `./build.ps1 -Tasks build` was run, then `./build.ps1 -Tasks test`. Write the actual numbers
      below, not just a checkmark:
  - Test pass / fail counts:
  - Coverage percentage:
- [ ] The live-verification checklist for this change is attached (under
      `docs/live-verification/`), or this PR is explicitly marked not applicable to live
      verification, with the reason stated here:
  - Live verification: N/A because ...
