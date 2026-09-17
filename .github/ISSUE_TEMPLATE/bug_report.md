---
name: Bug report
about: Report unexpected behavior from a cmdlet or the module
title: "[Bug]: "
labels: bug
---

## Environment

- PowerShell version (the module requires 7.2 or later, Core only -- run `$PSVersionTable.PSVersion`):
- Omnicit.EntraRBAC module version (`Get-Module -ListAvailable Omnicit.EntraRBAC`, showing the
  version, or the commit if you built from source):
- OS (Windows / Linux / macOS):

## Cmdlet

Which `OER` cmdlet, and the parameters used (redact any id -- see below):

## Expected behavior

## Actual behavior

## Error record and -Verbose output

Re-run the failing command with `-Verbose` and paste the resulting error record below.

```
<paste here>
```

## Before you paste anything, redact

- **Never paste a tenant id, subscription id, or object id.** Replace every one with
  `00000000-0000-0000-0000-000000000001`.
- **Never paste an access token or a client secret.**
- **Never paste a full `$Error[0]`.** A raw failed Graph or ARM call carries the bearer token in
  plain text inside its `HttpRequestMessage`. Paste the error record's `.Exception.Message` and
  `.ErrorDetails.Message` instead of the whole record.

If this looks like it might be a security-relevant leak rather than a plain bug -- for example a
token or secret written to output or logs -- do not file it here. See `.github/SECURITY.md`
instead.
