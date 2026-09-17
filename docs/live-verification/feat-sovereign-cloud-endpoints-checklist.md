# Live verification checklist -- feat/sovereign-cloud-endpoints (issue #81)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an UNRUN one. If a check turns out to be impossible to
run, write "cannot be verified, and therefore we do not know" on its result line and say why; do not
leave it blank and do not tick it.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened. A recorded observation is the deliverable there -- do
not substitute a guess, and do not tick the box because the number you got looked plausible.

**Redaction.** Read `docs/live-verification/README.md` before pasting anything from a console.
Object ids become `00000000-0000-0000-0000-0000000000NN`, counting up per distinct id in
first-appearance order; email addresses become `person1@example.com`, `person2@example.com`. The
mapping from a real value to its placeholder is never written down anywhere in this repository.
`tests/QA/dochygiene.tests.ps1` fails the gate on any tracked `.md` in this folder that breaks
either rule -- including a GUID-shaped literal that does not start with `00000000-0000-0000-`, which
is why every fabricated tenant identifier used below is a DOMAIN name, never a made-up GUID.

---

## 0. What this checklist can and cannot prove

**A GCC High tenant IS available; DoD and China are not.** That changed after this checklist was
first written, and section 4 was added for it. The GCC High run is deliberately small -- connect,
and export an inventory -- so it is a real end-to-end proof of the sovereign path, not a full
regression pass of the module against a second cloud. DoD and China remain untested by anything
except the offline mapping in section 2, and this checklist does not pretend otherwise anywhere
below.

Four tiers, run in this order:

1. **Section 1 -- the public path is unchanged.** This is the section that actually protects
   someone today: every current user of this module is on the worldwide commercial cloud, and nothing
   about this sprint may be allowed to change what happens when nobody names a cloud. This runs
   against Philip's ordinary tenant, for real, exactly as before this sprint.
2. **Section 2 -- the mapping is what it claims.** Entirely offline: no Graph or Azure call of any
   kind. It inspects the fixed endpoint table and the derivation that reads it, and proves the
   Tenant Profile round-trip, all without touching a network.
3. **Section 3 -- the authority actually moves, without naming any real tenant.** A device-code
   sign-in against a tenant that does not exist, read from the authority host printed in the
   device-code URL. That sign-in CAN still complete against your own home tenant -- the verification
   page is tenant-independent -- so the section is read-only against your own tenant, not free of
   tenants altogether. **Section 4 supersedes this as evidence**: a successful GCC High sign-in
   proves the authority moved far more directly. Section 3 is kept because it is free, needs no
   sovereign tenant, and stays runnable by anyone who does not have one -- and because if section 4
   fails, section 3 is what tells you whether the failure was the authority or something further up.
4. **Section 4 -- GCC High, live.** Connect to the real GCC High tenant and export an inventory.
   Small on purpose. This is the section that turns "proved by mocked tests plus static analysis"
   into "observed working", and it is also the only place the PIM-for-Groups `beta` question in US
   Government gets a real answer.

**If section 4 is skipped**, that must be said plainly in the PR: the sovereign path then stands
proved only by mocked unit tests, static source-hygiene checks, and the authority host section 3
observed in a device-code URL -- never by a completed sign-in to a real sovereign tenant.

**What this checklist still never attempts:** any sign-in to a DoD or China tenant; any write of any
kind in any sovereign cloud (section 4 is read-only throughout); and any exercise of the AzAuth
`-Force` credential-cache-clear across two SUCCESSFUL sign-ins in different clouds -- section 4.7
covers that case only if you choose to run it. Section 5 below is the complete, itemized list of
what stays unproven regardless of what gets ticked.

---

## Setup, once

Nothing in this checklist creates, modifies or deletes a real tenant object. Section 1 reads
Philip's ordinary tenant (no writes). Section 2 is offline. Section 3 only ever names a tenant that
does not exist. **Section 4 reads the real GCC High tenant and writes nothing to it** -- but it does
write an inventory export to local disk, and that file carries live tenant data, so `$Work` below is
where it goes and check 4.6 says why that matters.

The other thing worth a scratch location is the throwaway Tenant Profile files sections 2 and 3
write to disk -- deliberately **never** the real profile directory, so a mistake here cannot corrupt
a profile Philip actually uses day to day.

```powershell
$Work = Join-Path ([System.IO.Path]::GetTempPath()) 'oer-sov'
New-Item -ItemType Directory -Path $Work -Force | Out-Null

# A syntactically valid but nonexistent verified domain, never a GUID -- a GUID-shaped literal that
# does not start with '00000000-0000-0000-' trips the dochygiene gate this checklist is itself
# subject to (see the Redaction note above), and a domain name is authenticated exactly like a GUID
# tenant id by both AzAuth and Connect-OER's -TenantId/-TenantAlias paths.
$FakeTenant = 'oer-sovereign-verify-doesnotexist.onmicrosoft.com'
```

Build and import the module under test before starting:

```powershell
cd C:\Git\Omnicit.EntraRBAC
./build.ps1 -Tasks build
$env:PSModulePath = (Resolve-Path ./output/module).Path + [IO.Path]::PathSeparator + (Resolve-Path ./output/RequiredModules).Path + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module Omnicit.EntraRBAC -Force
```

## The helper block

Paste this once per session. `Get-OERCloudEndpoint` and `Get-OERGraphServiceRoot` are private, so
reaching them from outside the module needs the module-invocation form below rather than
`InModuleScope` (which only exists inside a Pester run).

```powershell
# Peek at the module's own auth-state cache without ever authenticating.
function Get-OERAuthStateForCheck {
    & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState }
}

# OFFLINE ONLY. Simulates "a session already exists for cloud X" by writing the module's private
# state directly, so Get-OERGraphServiceRoot's per-cloud derivation can be checked for all four
# clouds without ever calling Connect-OER against a cloud with no real tenant behind it. Never use
# this to fake a check that is supposed to prove something about a REAL session -- section 2.5 and
# all of section 3 use a real Connect-OER call instead, on purpose.
function Set-OERAuthStateEnvironmentForCheck {
    param([string]$Environment)
    & (Get-Module Omnicit.EntraRBAC) { param($Env) $script:_OERAuthState = @{ Environment = $Env } } $Environment
}

function Clear-OERAuthStateForCheck {
    & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState = $null }
}

function Invoke-OERPrivateForCheck {
    param([string]$Name, [hashtable]$Parameters = @{})
    & (Get-Module Omnicit.EntraRBAC) { param($N, $P) & $N @P } $Name $Parameters
}
```

---

### 1. The public path is unchanged (checks 1.x)

Run in a fresh session with `AZURE_AUTHORITY_HOST` unset. Confirm that first:

```powershell
Test-Path Env:AZURE_AUTHORITY_HOST
```

**Expect:** `False`. If `True`, clear it (`Remove-Item Env:AZURE_AUTHORITY_HOST`) before starting --
an ambient value left over from a previous session would contaminate every check in this section.
**Result:**

- [ ] **1.1 A plain `Connect-OER`, no `-Environment` at all, against your ordinary tenant.**

  ```powershell
  Connect-OER -TenantId '<your ordinary tenant id or domain>' -Interactive
  ```

  **Expect:** signs in exactly as it always has -- no new prompt, no new output, nothing naming a
  cloud at all. **Failure looks like:** any mention of "Environment", "cloud" or an authority host
  in the console output, or the sign-in behaving differently from how it did before this sprint.
  **Result:**

- [ ] **1.2 `$script:_OERAuthState.Environment` reports `Global`.**

  ```powershell
  (Get-OERAuthStateForCheck).Environment
  ```

  **Expect:** `Global`. This is the value every later cmdlet in the session reads to decide which
  cloud to call, so if this is wrong everything downstream is wrong regardless of what it looks
  like on the surface. **Result:**

- [ ] **1.3 `AZURE_AUTHORITY_HOST` is still not set after a Global sign-in.**

  ```powershell
  Test-Path Env:AZURE_AUTHORITY_HOST
  ```

  **Expect:** `False`. The Global path is documented to write NOTHING to this variable -- not even
  the public authority -- because writing it at all would only be a no-op with a side effect, and
  the byte-identical-public-path claim is provable only if there is no write to prove away.
  **Failure looks like:** `True` -- the module wrote something on a path that is supposed to touch
  nothing. **Result:**

- [ ] **1.4 A couple of ordinary reads are unaffected.**

  ```powershell
  Get-OERGroup -Group '<a group you already have>' | Format-List DisplayName, Id
  Get-OERAdministrativeUnit | Select-Object -First 3 DisplayName, Id
  ```

  **Expect:** the same output you would have gotten from this module before this sprint existed --
  no new properties, no new warnings, no new errors. **Result:**

- [ ] **1.5 `Get-OERInventory` is unaffected.**

  ```powershell
  $Inv = Get-OERInventory -Include Groups -ErrorVariable Err
  @($Inv.Groups).Count
  @($Err).Count
  ```

  **Expect:** a normal inventory read, zero errors, exactly as before. This is the end-to-end
  control: auth, Graph reads and inventory projection all unaffected by a sprint that added an
  entire parameter nobody here is using. **Result:**

- [ ] **1.6 An ambient `AZURE_AUTHORITY_HOST` on a Global sign-in warns, names the variable, and is
  NOT overwritten.**

  Do this LAST in this section -- it deliberately breaks the next sign-in attempt on purpose, and
  the failure is the point.

  ```powershell
  Disconnect-OER -ErrorAction SilentlyContinue
  $env:AZURE_AUTHORITY_HOST = 'https://login.microsoftonline.us/'
  try {
      Connect-OER -TenantId '<your ordinary tenant id or domain>' -Interactive -WarningVariable Warn -ErrorAction Stop
      'SUCCEEDED'
  } catch {
      "FAILED: $($_.Exception.Message)"
  }
  $Warn
  $env:AZURE_AUTHORITY_HOST
  ```

  **Expect:** the sign-in FAILS (Azure.Identity follows the ambient variable to the US Government
  authority even though this module computed the effective cloud as `Global` and therefore wrote
  nothing itself, so the request goes to the wrong authority for this tenant and the STS refuses
  it -- by design this is not a terminating error the module raises on purpose, it is the ambient
  setting sending a commercial-tenant sign-in to the wrong place). `$Warn` contains a warning naming
  `AZURE_AUTHORITY_HOST` and stating that Omnicit.EntraRBAC does not change the variable on the
  Global cloud. `$env:AZURE_AUTHORITY_HOST` afterwards is STILL
  `'https://login.microsoftonline.us/'` -- unchanged, not cleared, not overwritten to the commercial
  authority. **Failure looks like:** no warning at all (the operator gets an opaque STS error with
  no explanation), or the variable coming back cleared or rewritten (the module silently overrode an
  operator's deliberate setting on the one cloud where CLAUDE.md and this sprint both insist on
  byte-identical behaviour). **Result:**

  Clean up before continuing:

  ```powershell
  Remove-Item Env:AZURE_AUTHORITY_HOST -ErrorAction SilentlyContinue
  Disconnect-OER -ErrorAction SilentlyContinue
  Test-Path Env:AZURE_AUTHORITY_HOST
  ```

  **Expect:** `False`. **Result:**

---

### 2. The mapping is what it claims -- offline (checks 2.x)

No sign-in anywhere in this section, and no Graph or Azure call. Every check below either reads a
fixed table, calls a pure private helper, or writes a PSD1 file to a scratch directory.

- [ ] **2.1 CONTROL -- the default endpoint set is byte-identical to what this module has always
  used for the public cloud.**

  ```powershell
  $Global = Invoke-OERPrivateForCheck -Name Get-OERCloudEndpoint
  $Global.GraphResource -ceq 'https://graph.microsoft.com/'
  $Global.ArmResource   -ceq 'https://management.azure.com/'
  $Global.AuthorityHost -ceq 'https://login.microsoftonline.com/'
  ```

  **Expect:** all three `True`, using CASE-SENSITIVE comparison (`-ceq`). This is the literal string
  every Graph and ARM call in this module used before the cloud table existed; any drift here,
  even in case, changes what every existing session in the world connects to. **Result:**

- [ ] **2.2 The full four-cloud table matches the design exactly.**

  ```powershell
  foreach ($Cloud in 'Global', 'USGov', 'USGovDoD', 'China') {
      Invoke-OERPrivateForCheck -Name Get-OERCloudEndpoint -Parameters @{ Environment = $Cloud } |
          Select-Object Environment, GraphResource, GraphEnvironment, GraphServiceRoot, ArmResource, ArmHost, AuthorityHost |
          Format-List
  }
  ```

  **Expect**, compared against this table (from `Get-OERCloudEndpoint.ps1`, not re-derived):

  | Environment | GraphResource | GraphServiceRoot | ArmResource | ArmHost | AuthorityHost |
  |---|---|---|---|---|---|
  | Global | `https://graph.microsoft.com/` | `https://graph.microsoft.com/v1.0` | `https://management.azure.com/` | `https://management.azure.com` | `https://login.microsoftonline.com/` |
  | USGov | `https://graph.microsoft.us/` | `https://graph.microsoft.us/v1.0` | `https://management.usgovcloudapi.net/` | `https://management.usgovcloudapi.net` | `https://login.microsoftonline.us/` |
  | USGovDoD | `https://dod-graph.microsoft.us/` | `https://dod-graph.microsoft.us/v1.0` | `https://management.usgovcloudapi.net/` | `https://management.usgovcloudapi.net` | `https://login.microsoftonline.us/` |
  | China | `https://microsoftgraph.chinacloudapi.cn/` | `https://microsoftgraph.chinacloudapi.cn/v1.0` | `https://management.chinacloudapi.cn/` | `https://management.chinacloudapi.cn` | `https://login.chinacloudapi.cn/` |

  `GraphEnvironment` equals `Environment` on every row. These are public, non-secret Microsoft
  endpoint hostnames, not tenant data -- no redaction applies to this table.
  **Failure looks like:** any cell differing, including a trailing slash, from the table above.
  **Result:**

- [ ] **2.3 `GraphServiceRoot` and `GraphResource` are deliberately different strings, on every
  row.**

  ```powershell
  foreach ($Cloud in 'Global', 'USGov', 'USGovDoD', 'China') {
      $E = Invoke-OERPrivateForCheck -Name Get-OERCloudEndpoint -Parameters @{ Environment = $Cloud }
      [PSCustomObject]@{
          Environment           = $Cloud
          ResourceEndsInSlash   = $E.GraphResource.EndsWith('/')
          ServiceRootEndsInSlash = $E.GraphServiceRoot.EndsWith('/')
          ArmHostEndsInSlash    = $E.ArmHost.EndsWith('/')
      }
  }
  ```

  **Expect:** `ResourceEndsInSlash` is `True` and `ServiceRootEndsInSlash`/`ArmHostEndsInSlash` are
  both `False`, on all four rows. This is the exact defect class the sprint's own design notes
  worried about: concatenating a path onto the wrong one of these two strings emits a double slash
  in every `@odata.id` bind reference the module builds. **Result:**

- [ ] **2.4 `Get-OERGraphServiceRoot` -- the single derivation both member-add cmdlets call --
  resolves correctly per cloud, with zero network calls.**

  ```powershell
  Clear-OERAuthStateForCheck
  Invoke-OERPrivateForCheck -Name Get-OERGraphServiceRoot    # no session at all yet

  foreach ($Cloud in 'Global', 'USGov', 'USGovDoD', 'China') {
      Set-OERAuthStateEnvironmentForCheck -Environment $Cloud
      '{0}: {1}' -f $Cloud, (Invoke-OERPrivateForCheck -Name Get-OERGraphServiceRoot)
  }
  Clear-OERAuthStateForCheck
  ```

  **Expect:** with no session at all, `https://graph.microsoft.com/v1.0` (the documented no-session
  default). With a simulated session, each cloud's line matches its `GraphServiceRoot` cell in
  2.2's table exactly. This is the exact function `Add-OERGroupMember` and
  `Add-OERAdministrativeUnitMember` call to build their `@odata.id` request body, so this check
  covers both cmdlets' derivation for all four clouds without ever needing a sovereign tenant.
  **Result:**

- [ ] **2.5 LIVE, Global only -- the derivation holds under a real session, and both member-add
  cmdlets complete cleanly with it.**

  This is the one cloud with a real tenant behind it, so exercise the full public cmdlet, not just
  the private helper.

  ```powershell
  Connect-OER -TenantId '<your ordinary tenant id or domain>' -Interactive
  Invoke-OERPrivateForCheck -Name Get-OERGraphServiceRoot
  Add-OERGroupMember -Group '<a group you already have>' -User '<a user you already have>' -WhatIf
  Add-OERAdministrativeUnitMember -AdministrativeUnit '<an AU you already have>' -User '<a user you already have>' -WhatIf
  ```

  **Expect:** the helper call returns `https://graph.microsoft.com/v1.0`; both `-WhatIf` calls print
  a "What if:" line naming the resolved group/AU and principal, with no exception and `$?` true
  afterward. **Failure looks like:** either cmdlet throwing while resolving the group, AU or
  principal -- the derivation itself is a single line of code and unlikely to be the cause, but a
  failure here would still mean the two call sites cannot reach it. **Result:**

- [ ] **2.6 Tenant Profile round-trip with an `Environment` key.**

  Use the SCRATCH `-BasePath` from Setup -- never your real profile directory.

  ```powershell
  New-OERConfiguration -TenantAlias 'oer-sov-a' -TenantId $FakeTenant -Environment USGov -BasePath $Work -Confirm:$false
  (Get-OERConfiguration -TenantAlias 'oer-sov-a' -BasePath $Work).Environment

  Set-OERConfiguration -TenantAlias 'oer-sov-a' -Environment China -BasePath $Work -Confirm:$false
  (Get-OERConfiguration -TenantAlias 'oer-sov-a' -BasePath $Work).Environment

  New-OERConfiguration -TenantAlias 'oer-sov-b' -TenantId $FakeTenant -BasePath $Work -Confirm:$false
  (Get-OERConfiguration -TenantAlias 'oer-sov-b' -BasePath $Work).Environment
  Select-String -Path (Join-Path $Work 'oer-sov-b.psd1') -Pattern 'Environment'
  ```

  **Expect:** the first read reports `USGov`; after `Set-OERConfiguration -Environment China`, the
  second read reports `China` (the round trip survives an update, not just a create). The THIRD
  profile, created with no `-Environment` at all, reports `$null` from `Get-OERConfiguration`, and
  the `Select-String` against its raw PSD1 file returns NOTHING -- no `Environment` key is written
  to disk at all when the parameter is omitted, not even as an empty or null value.
  **Failure looks like:** the third profile carrying an `Environment` key of any kind -- that would
  mean every profile ever created before this sprint, none of which named a cloud, now carries a
  new key on next `Set-OERConfiguration`. **Result:**

- [ ] **2.7 A hand-corrupted `Environment` value is reported, not silently downgraded to `Global`,
  and is repairable.**

  ```powershell
  (Get-Content (Join-Path $Work 'oer-sov-a.psd1') -Raw) -replace "Environment\s*=\s*'China'", "Environment = 'Mordor'" |
      Set-Content (Join-Path $Work 'oer-sov-a.psd1') -Encoding utf8

  $E = Get-OERConfiguration -TenantAlias 'oer-sov-a' -BasePath $Work -ErrorVariable Err
  $E
  @($Err)[0].FullyQualifiedErrorId
  @($Err)[0].Exception.Message

  Set-OERConfiguration -TenantAlias 'oer-sov-a' -Environment USGov -BasePath $Work -Confirm:$false
  (Get-OERConfiguration -TenantAlias 'oer-sov-a' -BasePath $Work).Environment
  ```

  **Expect:** `Get-OERConfiguration` returns NOTHING for this alias (the profile is skipped, not
  returned with a `Global`-defaulted or empty `Environment`), and writes a `TenantProfileMalformed`
  error naming the alias, the bad value, and the four valid ones. `Set-OERConfiguration -Environment
  USGov` then repairs it, and the final read reports `USGov` again. **Failure looks like:** the
  corrupted profile being returned at all, with `Environment` silently read as `Global`, `$null`, or
  the literal bad string -- any of those would mean a hand-edited or pre-migration profile file
  could silently sign an operator in against the wrong cloud boundary. **Result:**

- [ ] **2.8 `Get-OERConfiguration | Set-OERConfiguration` round-trips a profile that stores NO
  `Environment`, and one that does.**

  The final whole-branch review found this broken for every profile created before the `Environment`
  key existed -- which is all of them. `ConvertTo-OERTenantConfiguration` always emits an
  `Environment` property, an unbound `[string]` parameter bound from it is `''` rather than absent,
  and the `ValidateSet` on `Set-OERConfiguration -Environment` refused the whole call. The fix drops
  pipeline binding from that one parameter; a stored cloud is preserved from the file on disk
  instead. Scratch `-BasePath` only, as above -- never your real profile directory.

  ```powershell
  New-OERConfiguration -TenantAlias 'oer-sov-c' -TenantId $FakeTenant -BasePath $Work -Confirm:$false
  $Error.Clear()
  Get-OERConfiguration -TenantAlias 'oer-sov-c' -BasePath $Work |
      Set-OERConfiguration -Defaults @{ ActivationMaxHours = 4 } -BasePath $Work -Confirm:$false
  @($Error).Count
  $C = Get-OERConfiguration -TenantAlias 'oer-sov-c' -BasePath $Work
  $C.Defaults.ActivationMaxHours
  $null -eq $C.Environment

  New-OERConfiguration -TenantAlias 'oer-sov-d' -TenantId $FakeTenant -Environment USGov -BasePath $Work -Confirm:$false
  $Error.Clear()
  Get-OERConfiguration -TenantAlias 'oer-sov-d' -BasePath $Work |
      Set-OERConfiguration -Defaults @{ ActivationMaxHours = 6 } -BasePath $Work -Confirm:$false
  @($Error).Count
  Get-OERConfiguration -TenantAlias 'oer-sov-d' -BasePath $Work |
      Select-Object Environment, @{ n = 'Hours'; e = { $_.Defaults.ActivationMaxHours } }
  ```

  **Expect:** each round trip emits an updated profile object and reports `@($Error).Count` of `0`.
  For `oer-sov-c` the re-read reports `ActivationMaxHours` of `4` and `True` for the null check --
  the update reached disk and no cloud was invented where the profile never had one. For
  `oer-sov-d` the final line reports `USGov` and `6` together -- a stored cloud survives a round
  trip that never names `-Environment` on the command line, preserved from the file rather than
  bound from the piped object.

  **Failure looks like:** `@($Error).Count` of `1` carrying
  `ParameterArgumentValidationError,Set-OERConfiguration` and the text `The argument "" does not
  belong to the set "Global,USGov,USGovDoD,China"`, with `ActivationMaxHours` unchanged on disk --
  the update silently lost. Read `$Error` and the re-read values, NOT `-ErrorVariable`: a parameter
  binding validation failure on PIPELINE input is raised before the common parameters it would
  populate are in force, so `-ErrorVariable` stays EMPTY for this defect and an `-ErrorVariable`
  check alone would report success while the profile went unmodified. Measured, not assumed --
  see `final-fix-report.md`. **Result:**

  Clean up:

  ```powershell
  Remove-Item (Join-Path $Work 'oer-sov-a.psd1'), (Join-Path $Work 'oer-sov-b.psd1'),
              (Join-Path $Work 'oer-sov-c.psd1'), (Join-Path $Work 'oer-sov-d.psd1') -Force -ErrorAction SilentlyContinue
  ```

---

### 3. The authority actually moves -- the one network-provable fact (checks 3.x)

**No command below writes anything, anywhere.** Every command names `$FakeTenant`, the nonexistent
domain from Setup, so no real tenant is named. But a device-code sign-in **can still succeed**: the
verification page is tenant-independent, and completing it with your own account mints a token for
**your own home tenant** even though the command named a tenant that does not exist. That was
measured, not predicted -- see the note under 3.1. So treat this section as read-only against your
own tenant, not as touching no tenant at all, and do not run it with a privileged account you would
not otherwise sign in with.

Confirm the precondition first:

```powershell
Disconnect-OER -ErrorAction SilentlyContinue
Test-Path Env:AZURE_AUTHORITY_HOST
```

**Expect:** `False`. If `True`, clear it before continuing -- section 1.6 leaves it cleared on its
own, but do not assume that ran first in this session. **Result:**

- [ ] **3.1 Baseline -- which authority host a commercial device-code sign-in prints.**

  No `-Environment`, no `AZURE_AUTHORITY_HOST` override.

  **This check used to expect an `AADSTS90002` "tenant not found" rejection, and to call a success
  a failure. That was wrong, and a live run disproved it:** completing the device-code page with a
  real account returns a working session even though the named tenant does not exist, since the
  verification page is tenant-independent. The decisive observation here is therefore **the
  authority host in the device-code URL the module prints**, not the error text -- that host is
  what actually distinguishes the clouds, and it is printed before anything is signed in to.

  A `try`/`catch` is a STATEMENT and cannot be piped -- `try { } catch { } | Tee-Object` is a parse
  error ("An empty pipe element is not allowed"). Wrap it in `$( )` so the whole thing is an
  expression whose output can be captured:

  ```powershell
  $BaselineCapture = $(
      try {
          Connect-OER -TenantId $FakeTenant -DeviceCode -ErrorAction Stop
          'SUCCEEDED'
      } catch {
          $_.Exception.Message
          $_.FullyQualifiedErrorId
          $_.Exception | Format-List * -Force | Out-String
      }
  )
  $BaselineCapture
  ```

  This is a device-code sign-in, so it prints a URL and a one-time code and then **blocks** waiting
  for you to complete it. **Read the printed URL and write its host down before doing anything
  else** -- that is the whole point of the check. Then either complete the sign-in with your own
  account or let it time out; both are acceptable outcomes here. Do not press Ctrl+C: interrupting
  leaves AzAuth's cached credential mid-flow, and the next device-code attempt in the same process
  may not print a new code at all.

  If you completed it, inspect what the session actually holds:

  ```powershell
  & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState } |
      Select-Object TenantId, TokenTenantId, Environment, AuthMethod
  ```

  **Expect:** a commercial authority host in the printed URL (`login.microsoft.com`, or whatever
  commercial host MSAL prints on the day -- record it verbatim). If you completed the sign-in,
  expect `SUCCEEDED`, `TenantId` = the fictitious domain that was asked for, and `TokenTenantId` =
  **your own home tenant GUID**, which is the granted-tenant field this branch added; the two
  disagreeing is exactly what it exists to make visible, and no `TenantMismatch` fires here since a
  domain cannot be compared against a GUID. **Record:** the printed URL's host, the full captured
  text, and the four state fields. **Redact `TokenTenantId`** -- it is your real tenant -- as
  `00000000-0000-0000-0000-0000000000NN` per the Redaction rule above. The `$FakeTenant` domain
  itself needs no redaction; it is fictitious and names no real object. **Failure looks like:** the
  printed URL naming a sovereign host (`.us`) on a run with no `-Environment`, or `TokenTenantId`
  absent from the state object. **Result:**

- [ ] **3.2 Independent proof, no module involved, that the two authorities are live and
  distinguishable.**

  This does not go through Omnicit.EntraRBAC at all -- it is here so the comparison in 3.3 has an
  external anchor even if the module's own error text turns out identical on both clouds.

  ```powershell
  (Invoke-RestMethod "https://login.microsoftonline.com/$FakeTenant/v2.0/.well-known/openid-configuration").issuer
  (Invoke-RestMethod "https://login.microsoftonline.us/$FakeTenant/v2.0/.well-known/openid-configuration").issuer
  ```

  **Expect:** both calls succeed (the OpenID discovery document exists for any syntactically valid
  tenant identifier -- it does not validate that the tenant is real), and the two `issuer` values
  differ by host: one names `login.microsoftonline.com`, the other `login.microsoftonline.us`. This
  is Microsoft's own infrastructure proving the two authorities are genuinely separate services
  before the module's own plumbing is even in the picture. **Failure looks like:** either call
  failing outright (a corporate network path may block one host and not the other -- **Record** that
  if so, since it also answers the question, just not the way this check expects), or both `issuer`
  values naming the same host. **Result:**

- [ ] **3.3 The module-routed sovereign attempt.**

  Same `$( )` wrapping as 3.1, and the same "let it block, do not Ctrl+C" note applies:

  ```powershell
  $SovereignCapture = $(
      try {
          Connect-OER -TenantId $FakeTenant -Environment USGov -DeviceCode -ErrorAction Stop
          'SUCCEEDED'
      } catch {
          $_.Exception.Message
          $_.FullyQualifiedErrorId
          $_.Exception | Format-List * -Force | Out-String
      }
  )
  $SovereignCapture
  ```

  **The device-code URL the module prints is the decisive observation in this check, and the only
  one that distinguishes the clouds.** Watch the line printed as the flow starts: it names the
  authority the request is actually going to. `login.microsoftonline.us` here versus the commercial
  host recorded in 3.1 is the sovereign routing proved directly, in one line -- a live run observed
  exactly `https://login.microsoftonline.us/device`.

  Then, as in 3.1, either complete the sign-in or let it time out, and if you completed it inspect
  the session:

  ```powershell
  & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState } |
      Select-Object TenantId, TokenTenantId, Environment, AuthMethod
  ```

  **Expect:** the printed URL names a `.us` host, and `Environment` reads `USGov`. **A completed
  sign-in that SUCCEEDS is an expected outcome, not a failure** -- the earlier wording here demanded
  an `AADSTS90002`-shaped rejection and called success a failure, and a live run disproved it: the
  device-code verification page is tenant-independent, so a real account completes it whatever
  tenant was named. **Record:** the printed URL's host verbatim, the full captured text, and the
  four state fields, with `TokenTenantId` redacted as `00000000-0000-0000-0000-0000000000NN`. Also
  search the ENTIRE captured text of both runs (not just the top-level message) for a host, since
  MSAL's own wording is generic across clouds by design and may name none:

  ```powershell
  ($SovereignCapture -join "`n") -match 'microsoftonline\.us'
  ($BaselineCapture -join "`n") -match 'microsoftonline\.com'
  ```

  Neither capture naming a host is NOT a failure -- the printed URL already answered the question,
  and 3.2 and 3.4 corroborate it. **Failure looks like:** the printed URL naming a commercial host
  on a run that passed `-Environment USGov` (the cloud selection did not reach the authority), or
  `Environment` in the state reading anything but `USGov`. **Result:**

- [ ] **3.4 `AZURE_AUTHORITY_HOST` is restored to absent after the sovereign attempt.**

  ```powershell
  Test-Path Env:AZURE_AUTHORITY_HOST
  ```

  **Expect:** `False`, whichever way 3.3 ended. `Initialize-OERAuth` sets this variable only for the
  duration of the token calls and restores it in a `finally` block documented to run on the
  terminating error paths as well as on success. If 3.3 ended in an error, this checks that claim
  against a real failure rather than a mocked one; if 3.3 succeeded, it checks the success path,
  which matters just as much. **Failure looks like:** `True` -- the sovereign sign-in would leave
  every later Global call in the same process pointed at the wrong authority until a restart.
  **Result:**

- [ ] **3.5 A Tenant Profile's stored `Environment` reaches the same place as an explicit
  `-Environment`, and an explicit value still wins.**

  **As in 3.1 and 3.3, the decisive observation in both runs is the authority host in the printed
  device-code URL, and a completed sign-in that succeeds is an expected outcome.** The earlier
  wording expected both runs to fail; a live run disproved it, and a stored `Environment` is proved
  by where the flow is ROUTED, not by how it ends.

  ```powershell
  New-OERConfiguration -TenantAlias 'oer-sov-c' -TenantId $FakeTenant -Environment USGov -BasePath $Work -Confirm:$false

  # (a) omit -Environment; the profile's USGov should be used, so expect the SAME host as 3.3.
  try {
      Connect-OER -TenantAlias 'oer-sov-c' -BasePath $Work -DeviceCode -ErrorAction Stop
      'SUCCEEDED'
  } catch {
      $_.Exception.Message
  }

  # (b) explicit -Environment Global overrides the stored USGov; expect the SAME host as 3.1.
  try {
      Connect-OER -TenantAlias 'oer-sov-c' -Environment Global -BasePath $Work -DeviceCode -ErrorAction Stop
      'SUCCEEDED'
  } catch {
      $_.Exception.Message
  }

  Test-Path Env:AZURE_AUTHORITY_HOST
  Remove-Item (Join-Path $Work 'oer-sov-c.psd1') -Force -ErrorAction SilentlyContinue
  ```

  **Expect:** (a) prints a `.us` authority host, the same one 3.3 printed -- the profile's stored
  `USGov` was picked up with no `-Environment` on the command line. (b) prints the commercial host
  recorded in 3.1 -- an explicit `-Environment Global` overrides the profile's stored value, exactly
  as `Connect-OER`'s own help text documents. The final `Test-Path` is `False` either way.
  **Record:** both printed hosts verbatim, and if you completed either sign-in, its
  `TenantId`/`TokenTenantId`/`Environment` from the same `& (Get-Module ...)` one-liner used in 3.1,
  with `TokenTenantId` redacted as `00000000-0000-0000-0000-0000000000NN`. **Failure looks like**:
  (a) printing the commercial host (the profile's `Environment` was never read), or (b) printing the
  `.us` host (an explicit parameter lost to a stored default, the opposite of every other precedence
  rule in this module). **Result:**

- [ ] **3.6 If any box in this section is unticked, say so in the PR, in these words.**

  No command to run. This is a statement, not a check, and it is part of the deliverable.

  **If 3.1-3.5 were skipped or could not be run:** the sovereign authentication path (the
  `AZURE_AUTHORITY_HOST` plumbing in `Initialize-OERAuth`, and the cloud precedence in `Connect-OER`)
  is proved ONLY by mocked unit tests and static source-hygiene checks in this sprint, never by a
  real network round trip to any Microsoft Entra ID authority. That must be written into the PR
  description in those terms, not implied by an empty checklist section. **Result:**

---

### 4. GCC High, live (checks 4.x)

**Read-only throughout. Nothing here creates, modifies or deletes a tenant object.** The one write
is a JSON file on your own disk, and check 4.6 governs where it may go.

**Before you start, two things that are not optional.**

**The export file contains live GCC High tenant data.** `Export-OERInventory` writes display names,
and with `-IncludeId` object ids, for real groups, administrative units, catalogs and access
packages. It must be written to `$Work` (a temp directory), never anywhere under
`C:\Git\Omnicit.EntraRBAC`, and **its contents must never be pasted into this file unredacted** --
the redaction rules at the top of this checklist apply to anything you quote from it. If you want to
keep the raw file, `docs/live-verification/raw/` is git-ignored for exactly this purpose.

**The most likely first failure is the client, not the cloud.** Delegated sign-in defaults to the
Microsoft first-party app **Microsoft Graph Command Line Tools** -- its client id is the
`$DefaultGraphClientId` constant in `source/Private/Initialize-OERAuth.ps1`, deliberately named here
rather than quoted, since this file's own redaction gate fails on any GUID-shaped literal and does
not special-case Microsoft's public app ids. If that app is not present or not consented in the GCC
High tenant, 4.1 fails with an AADSTS error naming the *application*, not the authority --
`AADSTS700016` (application not found in directory) or `AADSTS65002` (consent). **That is not a
defect in this sprint.** Retry with your own app registration in that tenant via `-ClientId`, and
record which one you used.

```powershell
$GccTenant = Read-Host 'GCC High tenant id or verified domain'
```

- [ ] **4.1 Connect to GCC High.**

  ```powershell
  Disconnect-OER -ErrorAction SilentlyContinue
  Connect-OER -TenantId $GccTenant -Environment USGov -Interactive -Verbose
  ```

  **Expect:** the browser opens at **`login.microsoftonline.us`**, not `login.microsoftonline.com`.
  Check the address bar before you authenticate -- that single observation is the decisive proof
  that `AZURE_AUTHORITY_HOST` moved the authority, which is the one thing the spike could not settle
  statically. The command completes without error.

  **Failure looks like:** an AADSTS error naming the application -- see the note above, retry with
  `-ClientId <your app>`. A browser at `login.microsoftonline.com` instead means the authority did
  NOT move: stop, and record it, since that falsifies the sprint's central mechanism.

  **Record:** which authority host the browser showed, and which `-ClientId` you used (default or
  your own). **Result:**

- [ ] **4.2 The session names the sovereign cloud, and the environment variable was put back.**

  ```powershell
  Get-OERAuthStateForCheck | Select-Object TenantId, Environment, ArmResourceUrl
  (Get-MgContext).Environment
  Test-Path Env:AZURE_AUTHORITY_HOST
  ```

  **Expect:** `Environment` is `USGov` and `ArmResourceUrl` is
  `https://management.usgovcloudapi.net/` in the auth state; `(Get-MgContext).Environment` is
  **`USGov`**, which proves `Connect-MgGraph -Environment` was passed and took effect;
  `Test-Path Env:AZURE_AUTHORITY_HOST` is **`False`**, which proves the `finally` restore ran and the
  module left no process-global state behind.

  **Failure looks like:** `Test-Path` returning `True` -- the variable leaked, which is a real defect
  even though the sign-in worked. **Result:**

- [ ] **4.3 A Graph read reaches `graph.microsoft.us`.**

  Entra sections only, so no ARM token is involved yet and a failure here is unambiguously the Graph
  half:

  ```powershell
  $Inv = Get-OERInventory -Include Groups, AdministrativeUnits -Verbose
  $Inv.groups.Count
  $Inv.administrativeUnits.Count
  ```

  **Expect:** the call completes and returns the tenant's real groups and administrative units. Any
  success at all proves the Graph service root followed the cloud -- a token minted at
  `login.microsoftonline.us` for `graph.microsoft.us` would be rejected by the commercial root, so a
  working read cannot happen against the wrong one.

  **Failure looks like:** `401`/`InvalidAuthenticationToken` -- token and endpoint disagree, i.e. the
  Graph resource or the Graph environment did not follow the cloud. Record the full error, with any
  bearer token redacted per the rules at the top of this file. **Result:**

- [ ] **4.4 The PIM-for-Groups `beta` surface in US Government -- the open question.**

  This is the known risk the CHANGELOG and README both state, and this check is the first real
  evidence either way. The Groups section reads each detailed group's PIM policy through the `beta`
  endpoint.

  A PIM policy the export could not read is now reported the same way any other unread collection
  is: not as a per-group warning, but as entries in the single `InventoryPartial` error the run
  ends with. Re-run 4.3 capturing that error and read the entries out of it:

  ```powershell
  $PimErr = $null
  $Inv = Get-OERInventory -Include Groups -ErrorAction SilentlyContinue -ErrorVariable PimErr
  @($PimErr | Where-Object { $_.FullyQualifiedErrorId -like 'InventoryPartial*' }) |
      ForEach-Object { ($_.Exception.Message -split 'Unread: ')[-1] }
  @($Inv.groups | Where-Object { $_.PSObject.Properties.Name -contains 'pimPolicy' }).Count
  ```

  **Expect:** no strong expectation -- **both outcomes are a valid result and both are worth
  writing down.** No `InventoryPartial` at all (or one naming no `pimPolicy/...` entry), and `beta`
  works in US Gov for these paths. A `pimPolicy/member` and `pimPolicy/owner` entry for every group,
  and it does not, which means a GCC High customer gets the module's Entra surface but not its PIM
  surface.

  Note what the entries do NOT mean: a group that is simply not onboarded to PIM for Groups produces
  no entry and no error at all. Every `pimPolicy/...` entry is a read that FAILED.

  **Record:** how many `pimPolicy/...` entries the `InventoryPartial` message named versus how many
  groups were read, plus the `Causes:` clause of that message verbatim. **Result:**

- [ ] **4.5 The ARM half: token, then host.**

  These are two separate facts and a failure means different things, so read them separately.

  ```powershell
  Connect-OER -TenantId $GccTenant -Environment USGov -IncludeARM
  (Get-OERAuthStateForCheck).ArmResourceUrl
  Get-OERSubscription -Verbose
  ```

  **Expect:** the ARM token is acquired without error and `ArmResourceUrl` is
  `https://management.usgovcloudapi.net/` -- that alone proves the ARM *resource* and *authority*
  followed the cloud. `Get-OERSubscription` then proves the ARM *host*: it returns the tenant's
  subscriptions, or an empty list if the tenant has none.

  **Failure looks like:** a token acquired but every ARM call returning a DNS or 404 failure --
  that would mean the host did not follow. **An empty subscription list is NOT a failure** if the
  tenant genuinely has no Azure subscriptions; note which case applies, since it decides whether the
  ARM host is proven or merely not disproven. **Result:**

- [ ] **4.6 The inventory export, written outside the repository.**

  ```powershell
  Export-OERInventory -OutputPath $Work -Verbose
  Get-ChildItem $Work -Filter *.json | Select-Object FullName, Length
  ```

  **Expect:** the export completes and writes `inventory.json` (plus the bundle's other files) under
  `$Work`. Confirm the path is under the temp directory and **not** under
  `C:\Git\Omnicit.EntraRBAC`. Note that the default `-Include` set contains `RoleAssignments`, so
  this export acquires an ARM token and exercises both halves in one command.

  **Failure looks like:** a partial export. This module now reports an unread collection as an
  explicit null rather than as an empty fact, so check the verbose output and the exit signal --
  `$?` is `$False` after a partial inventory -- rather than assuming a written file means a complete
  one.

  **Record:** the file size, the section counts, and whether `$?` was `$True`. **Quote nothing from
  the file itself without redacting it first.** **Result:**

- [ ] **4.7 OPTIONAL -- the cloud switch, the one case no other check reaches.**

  Only worth running if you are already connected and have a minute. It is the single scenario the
  AzAuth `-Force` credential clear exists for, and nothing else in this checklist exercises it with
  two real, successful sign-ins.

  ```powershell
  Connect-OER -TenantId <your ordinary commercial tenant> -Interactive
  (Get-MgContext).Environment
  Get-OERInventory -Include Groups | ForEach-Object { $_.groups.Count }
  ```

  **Expect:** the commercial sign-in succeeds immediately after the GCC High one, and
  `(Get-MgContext).Environment` is `Global`. The read returns your ordinary tenant's groups.

  **Failure looks like:** an AADSTS error naming the tenant rather than the cloud -- that is the
  symptom of a stale credential baked to the US Gov authority being reused, i.e. the `-Force` clear
  not firing. **Result:**

---

### 5. What this checklist does NOT prove

No boxes here. This section is a statement of limits and is part of the deliverable: it is what
lets a later reader tell a verified claim from an assumed one.

**Read this against what section 4 actually returned.** Items 1, 3 and 4 below change meaning
depending on whether section 4 was run, and the wording says which.

1. **DoD and China are never reached.** A GCC High tenant is available and section 4 uses it, so
   `USGov` is proven end to end if section 4 was run. `USGovDoD` and `China` are proven only as far
   as the offline mapping in section 2: their endpoint rows are asserted, and nothing more. They
   share `USGov`'s authority host (`login.microsoftonline.us` for DoD) and its ARM host, so a
   successful `USGov` run raises confidence in DoD, but it is not evidence for it -- DoD's Graph
   service root (`dod-graph.microsoft.us`) is a different host that nothing here calls.
2. **Write paths are not exercised in any sovereign cloud.** Section 4 is read-only by design. No
   group is created, no member added, no PIM policy changed, and no structure document applied
   against GCC High. Check 4.7 exercises the `@odata.id` bind host only as far as the read side.
3. **PIM-for-Groups' `beta` Graph availability**: check 4.4 answers this for **US Government only**,
   and only for the group-policy read paths the inventory touches. China is untested, and so are the
   PIM WRITE paths in every sovereign cloud. If 4.4 was skipped, this stays entirely unestablished,
   exactly as the CHANGELOG and README state.
4. **The AzAuth credential-cache `-Force` clear across two SUCCESSFUL sign-ins in different clouds**
   is exercised only if the optional check 4.7 was run. Sections 3.1, 3.3 and 3.5 name a tenant that
   does not exist, so even when their sign-ins complete they mint tokens for one and the same home
   tenant, and on their own they cannot show a stale credential being reused across clouds.
5. **The `@odata.id` derivation is proven end to end (auth, resolve, construct, `ShouldProcess`)
   only for `Global`.** For the other three clouds, only the private single-owner helper
   (`Get-OERGraphServiceRoot`) is proven, offline, in check 2.4 -- not the full public cmdlet path.
6. **Section 1.6 is the only ambient-`AZURE_AUTHORITY_HOST` scenario covered.** A more elaborate
   multi-cloud automation scenario -- several processes, or several sequential sign-ins across
   clouds in the SAME process beyond what sections 3 and 4.7 do -- is not exercised.
7. **A GCC High run is not a regression pass.** Section 4 is deliberately small: connect, read,
   export. It does not re-run the module's cmdlet surface against a second cloud, so a
   cloud-specific defect in a cmdlet the inventory does not call would not be found here.

---

### Teardown

- [ ] **T.1 Delete the scratch directory.**

  ```powershell
  Get-ChildItem $Work -Recurse -File | Select-Object FullName, Length
  Remove-Item $Work -Recurse -Force
  Test-Path $Work
  ```

  **Expect:** `False`.

  **If section 4 ran, this deletion is not routine hygiene -- it is the point.** `$Work` then holds
  the GCC High inventory export, which carries real display names for that tenant's groups,
  administrative units, catalogs and access packages. Delete it, or move it deliberately to
  `docs/live-verification/raw/` (git-ignored) if you want to keep it. Do not leave it in a temp
  directory you will forget about, and do not copy it anywhere under the repository's tracked tree.
  **Result:**

- [ ] **T.2 `AZURE_AUTHORITY_HOST` is absent and the session is disconnected.**

  ```powershell
  Test-Path Env:AZURE_AUTHORITY_HOST
  Disconnect-OER -ErrorAction SilentlyContinue
  ```

  **Expect:** `False`. **Result:**

- [ ] **T.3 What cannot be undone.**

  - The real reads in section 1 (checks 1.1, 1.4, 1.5) are in your tenant's Graph and sign-in
    telemetry and cannot be removed. Nothing there was a write.
  - Every device-code attempt against `$FakeTenant` in section 3 is also logged, on Microsoft's
    side, against that fictitious tenant identifier -- there is no tenant there to receive the
    telemetry, and no real tenant's logs are touched.
  - Section 1.6's ambient `AZURE_AUTHORITY_HOST` sign-in attempt is a genuine failed sign-in against
    your real tenant and will appear as such in its sign-in log, with a cloud-mismatch-shaped STS
    error.
  - **Section 4's sign-ins and reads are in the GCC High tenant's sign-in and audit logs and cannot
    be removed.** They were all reads, but they are a real administrative session in a government
    tenant: if anyone else monitors that tenant, this is the item to tell them about. If check 4.1
    needed your own app registration, that consent grant persists until you revoke it -- decide
    deliberately whether to leave it in place for future verification or remove it now.

  **Record:** anything that fired, was alerted on, or has to be told to someone:
  **Result:**
