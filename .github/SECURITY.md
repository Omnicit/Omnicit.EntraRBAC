# Security Policy

## Why this matters

`Omnicit.EntraRBAC` manages Entra ID groups, PIM (eligibility and activation), Administrative
Units, Entitlement Management (catalogs, access packages, assignments), Access Reviews, and Azure
RBAC across customer tenants. Used as intended, it operates with Global-Admin-class privilege in
every tenant it is pointed at. A vulnerability here -- an authentication bypass, a token leak, a
scope-widening bug in the apply engine, or anything that lets it act against the wrong tenant -- is
a tenant-compromise vulnerability, not an ordinary bug.

## Reporting a vulnerability

**Do not open a public GitHub issue for a security vulnerability.**

Report it privately using one of:

- GitHub's private vulnerability reporting on this repository (the repository's Security tab ->
  "Report a vulnerability"). This is the intended channel for this repository.
- Contact the maintainer, [@PhilipHaglund](https://github.com/PhilipHaglund), directly through
  GitHub. No response-time commitment is made for either channel.

## What to include

- The cmdlet(s) or code path involved, and the module version or commit you tested against.
- Steps to reproduce, and what you expected versus what actually happened.
- The impact: what could an attacker do with it (for example: read another tenant's data, escalate
  a role, or bypass a `ShouldProcess`/`-WhatIf` guard).

## What never to include, in a private report or anywhere else

- No access tokens or client secrets.
- No unredacted console output. `Remove-OERErrorRecord` exists specifically because a raw failed
  Graph or ARM call carries a bearer token in plain text inside its `HttpRequestMessage` -- do not
  work around that by pasting it anyway.
- **Tenant ids, subscription ids and object ids are identifiers, not credentials.** They are not
  rotated, and disclosing one is not itself a credential compromise. They are still treated as
  sensitive in this repository because they are correlatable to a real customer tenant, which is
  why they are redacted from tracked files -- but including one in a report does not require the
  rotation a leaked token or secret would.

## Supported versions

The first public release is `1.0.0`, and the built version is held in the `1.x` line (see
`CLAUDE.md` "CHANGELOG and Version"). Only the current `main` branch is supported; there are no
maintained release branches to backport a fix to.
