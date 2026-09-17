## Summary

<!-- What does this PR change, and why. -->

## What a reviewer should look at first

<!-- Point at the one file or change that matters most; do not make the reviewer guess. -->

## Checklist

- [ ] Branch is not `main`, and follows the naming convention: `fix/`, `feat/`, `test/`, `chore/`,
      or `refactor/` (see `CLAUDE.md` "Branch Policy").
- [ ] `CHANGELOG.md` `[Unreleased]` is updated if anything under `source/` changed. The
      changed-file gate fires only on a path matching `^source/`, so a PR that touches nothing
      under `source/` is not required to touch the changelog. The `[Unreleased]` heading itself is
      never converted or renamed by hand -- the build does that at release time.
- [ ] `./build.ps1 -Tasks build` was run, then `./build.ps1 -Tasks test`. Write the actual numbers
      below, not just a checkmark:
  - Test pass / fail counts:
  - Coverage percentage:
- [ ] The live-verification checklist for this change is attached (under
      `docs/live-verification/`), or this PR is explicitly marked not applicable to live
      verification, with the reason stated here:
  - Live verification: N/A because ...
