# Live verification checklist -- the tenant-switch warnings and Connect-OER -Force (finding F12)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened. A recorded observation is the deliverable there -- do
not substitute a guess.

**Three box states, and the middle one is the point of this file.** `- [x]` is a check that ran and
whose evidence supports it. `- [ ]` is a check that has not been run -- or one that ran and FAILED, in
which case its result line says `FAILED` and why, and section S carries it as a defect. `- [~]` is a
check that EXECUTED cleanly and still proves nothing, because the run never reached the condition it
exists to measure -- in this file, most often a sign-in whose token came back issued by a different
tenant than the check needed, so the warning's comparison never had the input it tests. A `- [~]` box
is a debt, not a failure of the code. Sprint 3's run produced three of them and the operator initially
reported them as passes; that is exactly the mistake this state exists to prevent.

**Every `Expect:` in this file was traced to a real line of the code committed on this branch, or to
a MEASURED row of the evidence in `docs/development/rationale.md#switching-tenants-in-one-process`,
before it was written, and the trace is printed under the check as `Traces to:`.** Line numbers are
as of commit `47895b4`, the final state of the code under test; the variable named beside each one is
what to search for if the file has moved since. (They were first pinned at `222c9d9` and re-pinned
mechanically at each later source commit on this branch.) Everything that evidence labels INFERRED or
DECOMPILED -- which tenant a device-code or managed identity token is issued for, whether
`AzToken.TenantId` is the token's `tid` claim, whether a second device code appears -- is a `Record:`,
never an `Expect:`. Where the module's REACTION is code but its INPUT is one of those unmeasured facts,
the check records the input and the `Expect:` is written as a condition on it ("if `TokenTenantId` is
tenant A's id, then ..."). A condition that did not hold is a `- [~]`, not a pass and not a failure.

---

## What the run found

**When, and on what.** The operator ran this checklist on **2026-09-15 and 2026-09-16**. Sections 1-4
and 6 ran on a Windows workstation against **AzAuth 2.9.0** and **PowerShell 7.6.6**. Section 5 ran on
2026-09-16 as three **Azure Automation runbook jobs** on a system-assigned managed identity, against **AzAuth
2.10.0** and **PowerShell 7.6.0-preview.5**. Both versions are recorded in section S, and section 5
says so at its own head.

**Every warning transcript recorded in this file pre-dates commit `91a3c29`**, so none of them
carries the Azure Resource Manager clause the shipped message now emits -- read each one as the
historical output it is, not as the current text. Recorded output is never edited here; the current
wording lives in `source/Private/Initialize-OERAuth.ps1`.

**Totals: 32 verification checks -- 25 `- [x]`, 7 `- [~]`, 0 FAILED.** Sections T and S are cleanup and
sign-off and are read separately; both were completed on 2026-09-17, after 5.5's re-run moved it from
`- [~]` to `- [x]`. Counting T and S in, the file carries 34 `- [x]`, 7 `- [~]` and no unticked box.

**Section 4 answered the blocking question.** `AzToken.TenantId` carries the token's own `tid` claim
and does NOT echo the requested tenant: `PropertyEqualsTid` `True` and `PropertyEchoesRequest` `False`
in 4.1 (a first device-code token), 4.2 (a switched one) and 4.3a (a client secret token), with 2.7b
corroborating it a fourth time on the shape where an echo would have been most misleading. Every
conditional `Expect:` in this file that rested on a decompile now rests on a measurement.

**The run's principal finding: a device-code sign-in can hang forever, and `-Force` is the cure.** A
device-code call that REUSES a credential which has already completed a sign-in, and names a different
tenant, with no `-Force`, never returns -- no device code printed, no error raised. MEASURED twice
independently on a healthy connection: through this module (3.5, where the harness function returned
`$null` and never reached its own return expression) and against raw `Get-AzToken` outside it (4.2).
It is NARROWER than "any device-code tenant switch": 3.2 and 3.3 switched by device code with no
`-Force` and did not hang, both having run straight after an `-IncludeARM` sign-in whose ARM call
builds a fresh credential. `-TimeoutSeconds` does not bound it and is not this module's parameter at
all. The full write-up is at the head of section 3; the evidence is recorded in
`docs/development/rationale.md#switching-tenants-in-one-process`, further finding 1.

**The ARM half is under-reported, and 5.4 measured it.** On a managed identity sign-in with
`-IncludeARM` across a switch that did not take effect, `ArmTokenTenantId` equalled `TokenTenantId`:
the ARM token was in exactly the same wrong state as the Graph token, and the warning named only the
Graph one. `PostCallWarnings` was `1` and not `2`, which is correct arithmetic -- there is one
`Write-Warning` and it fires before the ARM token is acquired. The branch's answer is in the warning's
wording, which now names Azure Resource Manager as affected.

**4.3 measured the default path, not the one it was written for.** Its child process printed an EMPTY
`$env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH`, so 4.3b exercised the default client secret path and got
the default refusal -- the same outcome 2.2, 2.2b and 2.4 already had. The question it exists for was
answered anyway, by **2.7b**, whose child DID print `true`: that sign-in SUCCEEDED and its
`TokenTenantId` came back as the previous tenant's id, not an echo of the requested domain. Both halves
of the MEASURED ClientSecret row are therefore confirmed live.

**The prerequisite that did not hold.** This file requires the signing-in account NOT to be in tenant
B, not even as a guest. It was. Every device-code sign-in that named tenant B came back with a genuine
tenant B token, so five checks executed cleanly while the switch they were meant to catch genuinely
took effect, and the guard was never given the input it tests. That -- and nothing about the code --
is why **3.2, 3.3, 3.4, 3.7 and 6.1** are `- [~]`. A future run needs a tenant the completing account
has no identity in at all, with the completing account recorded.

**What the run leaves unproven live**, and what covers it meanwhile:

- **the post-call warning's `-WarningAction Stop` placement (6.1)** -- unit test **Q10** proves the
  stop is an `ActionPreferenceStopException` carrying the post-call text, raised before
  `Connect-MgGraph`, the state rebuild and the session record, and it is mutation-proved;
- **the warning's own consequence sentence (5.5)** -- that a call in such a session acts on the granted
  tenant while reporting the named one. 5.5's read failed on PERMISSION rather than on tenant, so it
  measured nothing about where the request went; the re-run that would settle it is written out under
  5.5 for the operator.

---

## What this file is

The live-verification checklist for branch `fix/tenant-switch-warning` (finding F12). The branch adds
no tenant writes and no new Graph or ARM call; everything it changes happens inside sign-in. **Nothing
in this file writes to a tenant.** Every check is a sign-in, a sign-out, or a read of this module's
own in-process state.

## Order

The checks depend on process-wide state, so the ORDER and the PROCESS each block runs in are part of
every check. AzAuth keeps one credential for the whole PowerShell process (MEASURED), and this module
keeps two records in its own module scope that survive `Disconnect-OER` by design. A check run in the
wrong process measures the previous check's leftovers.

1. **The launcher, once.** Build, then put the tenant and application ids into the launcher's
   process environment. Every later process is a `pwsh -NoProfile` child started FROM the launcher, so
   it inherits those values and nothing else: no profile, no earlier `Get-AzToken`, no earlier module
   import. `-NoProfile` is load-bearing -- a profile that signs in to Azure would put a credential in
   AzAuth's static field before the first check.
2. **Section 4 FIRST, although it is printed fourth.** It settles whether `AzToken.TenantId` is the
   issued token's `tid` claim. Every post-call warning check in sections 1, 3, 5 and 6 takes its input
   from that value, so until section 4 has a result, their conditional `Expect:` lines rest on a
   decompile.
3. **Sections 1, 2 and 3**, each in its own new child process, exactly where the check says to start
   one.
4. **Section 6**, each check in its own new child process. 6.2 needs section 2's app registration.
5. **Section 5** on an Azure-hosted machine, if one is available.
6. **Section T** is teardown, then **section S** is the sign-off.

## Redact before you commit

Read `docs/live-verification/README.md` first. The rules that bite here:

- Every tenant id, application (client) id, object id and correlation or trace id pasted into a
  `Result:` block becomes `00000000-0000-0000-0000-0000000000NN`, counting up from `01` per DISTINCT
  identifier in first-appearance order, restarting in this file. **The warnings and error messages in
  this file print tenant ids and application ids inside their own text**, so a pasted warning is not
  redacted until every id inside the sentence is replaced. An abbreviated id is redacted too, and is
  written out as the FULL placeholder.
- **Tenant domains are identifiers here too.** Replace your tenants' verified domains with
  `tenant-a.example.com`, `tenant-b.example.com` and `tenant-c.example.com`. The gate does not catch
  a domain; this rule is here because a domain names the tenant as surely as its id does.
- Email addresses outside `example.com`/`contoso.com` become `person1@example.com`,
  `person2@example.com`, ... on the same per-file, first-appearance rule. Entra error text quotes the
  signing-in account's UPN.
- **No credential ever goes in.** Sections 2, 4.3 and 6.2 use a client secret. It is typed at a
  `Read-Host -AsSecureString` prompt and never appears in this file, not even shaped like a
  placeholder. Section 4 holds a real access token in a variable: its snippet prints two derived
  values and nothing else. **Never type `$Token` on its own at the prompt** -- default formatting
  prints the token in full. If a token or a secret is ever seen in output, that is a finding: record
  the FACT, never the value, and rotate the secret that minted it.

`tests/QA/dochygiene.tests.ps1` fails the gate on a GUID outside the placeholder range, an address
outside the two documentation domains, or a credential shape, and reports file and line without
printing the value. It is a backstop, not a substitute for redacting as you write.

### The placeholder table -- fill it in as you go

Write only placeholders here, never a real value, and never the mapping between them. The rows are
pre-allocated in the order the checks first print each value when the file is read top to bottom. If
a value turns out to equal one already allocated (the managed identity living in tenant A, say), it
takes that row's placeholder and its own row is marked NOT ALLOCATED -- the same identifier always gets
the same placeholder within a file. A client id typed in a different letter case (check 2.6) is the
SAME identifier and takes row 02; that is why 2.6 prints booleans rather than the id.

**Filled in after the 2026-09-15/16 run.** The `Allocated?` column records what the run actually
printed, not what the rows were reserved for.

| Placeholder | What it is | First appears in | Allocated? |
|---|---|---|---|
| `00000000-0000-0000-0000-000000000001` | tenant A id -- the signing-in account's HOME tenant | 1.1 | ALLOCATED |
| `00000000-0000-0000-0000-000000000002` | application (client) id of the multi-tenant app registration | 2.1 | ALLOCATED |
| `00000000-0000-0000-0000-000000000003` | tenant B id -- a tenant the signing-in account is NOT in | 2.2 | ALLOCATED |
| `00000000-0000-0000-0000-000000000004` | tenant C id -- a tenant the signing-in account is a GUEST in | 3.6 | **NOT ALLOCATED** -- 3.6 never ran, so no tenant C id was ever printed |
| `00000000-0000-0000-0000-000000000005` | the managed identity's own tenant id, if it is neither A nor B | 5.1 | **NOT ALLOCATED** -- the identity lives in tenant A, so it takes row 01 |
| `00000000-0000-0000-0000-000000000006` | client id of the user-assigned managed identity, if one was used | 5.1 | **NOT ALLOCATED** -- section 5 ran on the SYSTEM-assigned identity; no user-assigned client id was ever printed |

**Rows 07 onwards are appended as they arrive**, in the order they first appear, with the check they
first appear in. The ones most likely to arrive, all quoted inside Entra `AADSTS` error text rather
than printed by this module:

| Likely row | Where it comes from |
|---|---|
| the module's default delegated Microsoft Graph client, Microsoft Graph Command Line Tools | an `AADSTS` message from a device-code Graph sign-in, most likely in 3.5, 3.7 or 4.2 |
| Azure.Identity's default public client, the Azure CLI application | an `AADSTS` message from the ARM half of an `-IncludeARM` device-code sign-in, which passes no client id |
| an Entra `Trace ID` or `Correlation ID` | any `AADSTS` message |

These are Microsoft first-party identifiers and are redacted like any other GUID: the gate matches the
shape, and this file names them only in words. **None of the three arrived:** no `AADSTS` message was
produced anywhere in the run, so no row 07 or beyond was allocated.

| Stand-in | What it is |
|---|---|
| `tenant-a.example.com` | a verified domain of tenant A |
| `tenant-b.example.com` | a verified domain of tenant B |
| `tenant-c.example.com` | a verified domain of tenant C (reserved; never printed, since 3.6 did not run) |
| `person1@example.com` | the account that signs in for sections 1, 3, 4 and 6.1 |

Two NORMALISATIONS were applied on the way in that are not redactions of tenant data, and are recorded
here so a reader is not misled by a repeated value:

| Normalised to | What it replaced |
|---|---|
| `ABCD12345` | every one-time device code the run printed. They are short-lived and single-use, but they repeat here and a distinct code per line would read as meaningful when it is not |
| `operator@workstation` | the operator's own shell prompt fragment. The same prompt line also carried Nerd Font private-use glyphs, terminal decoration rather than output, and those were dropped |

**Four non-ASCII characters are kept on purpose, and they are the only ones in this file.** Section 5's
Azure Automation job output carries the operator's own Swedish `=====` section markers, and four
characters inside them are outside ASCII: two U+00C4 and two U+00F6, the Swedish A-diaeresis and
o-diaeresis. They sit in the markers heading 5.2, 5.4 and 5.5. They are RECORDED OUTPUT, and editing
recorded output is a worse fault than a non-ASCII byte in a markdown file, so they stay, and section 5
glosses every marker in English instead of translating it in place -- which is also why that gloss
names each marker by the check it heads rather than quoting the Swedish back, so it adds none of its
own. Nothing enforces ASCII here: `tests/QA/about.tests.ps1` and `tests/QA/sourcehygiene.tests.ps1`
name `.ps1`/`.psd1`/`.psm1`/`.ps1xml` and the about topic, not `docs/` (verified by reading both
gates), and `fix-graph-retry-after-checklist.md` beside this one already carries two. The distinction
that decides it is content versus decoration: the Nerd Font glyphs above were the terminal drawing a
prompt and were dropped; these four are characters the job actually printed.

**The masking that produced the blocks above was WRAP-TOLERANT, and it had to be.** Section 5's three
Azure Automation job transcripts went through the same masker, 59 further occurrences, when they were
added. Of the 276 occurrences in the console sections, **18 were split across a console line wrap** --
an identifier broken over two lines by the terminal, which a plain string replace does not see at all
(an unwrapped scan finds only 258). On a five-case mutation harness the naive replace leaked 4 of the
5; the wrap-tolerant one leaked none. **Carry that into the next checklist:** pasted console output
wraps, and a redaction pass that matches only unbroken strings will leave real identifiers in the file
while reporting success.

## What changed on this branch, and why a mocked suite cannot settle it

- **`Connect-OER -Force`** (`source/Public/Connect-OER.ps1:288`) forwards `-ForceRefresh` to
  `Initialize-OERAuth`, which puts `Force` on the `Get-AzToken` splat
  (`source/Private/Initialize-OERAuth.ps1:514-516`). That is the only lever that makes AzAuth drop its
  process-wide credential: MEASURED, `Clear-AzTokenCache` (with or without `-Force`) and a re-import of
  AzAuth both leave it in place, and `Disconnect-OER` never touches it.
- **A pre-call warning, client secret only** (`Initialize-OERAuth.ps1:601-620`,
  `$ClientSecretTenantSwitchWithoutForce`). Before a client secret token request with no `Force`, it
  warns when the module's RECORD names a client secret request for a byte-identical client id and a
  different tenant. Its text now begins `This client secret sign-in for application '<client id>'
  names tenant '<new>', but the credential AzAuth holds for that application in this PowerShell session
  was built for tenant '<previous>'.` MEASURED behind it: AzAuth reuses the credential it built for the
  first tenant; by default the reused call refuses before sending anything, with
  "The current credential is not configured to acquire tokens for tenant"; with
  `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH=true` it silently sends the request to the PREVIOUS tenant;
  `-Force` builds a new credential for the new tenant.
- **The record behind it, `$script:_OERLastTokenRequest`, tracks the request that last made AzAuth
  BUILD a credential** (`Initialize-OERAuth.ps1:655-661`, `$AzAuthBuildsNewCredential`). It moves only
  when the call is about to build one: no record yet (`:655`), a different credential type (`:656`), a
  client id that differs case-sensitively (`:657`), or `Force` on the call -- `Connect-OER -Force`, or
  the module's own sovereign-cloud switch (`:658`). **A same-application call without `Force` does NOT
  move it, whether it then succeeds or is refused**, since AzAuth reuses the credential it already has.
  It records the effective client id, which is empty for a device-code sign-in with no `-ClientId`, so
  consecutive device-code sign-ins do not move it either. It is never cleared by `Disconnect-OER`. An
  earlier commit on this branch moved it on every ATTEMPT; that made a sign-in back to the tenant the
  credential was built for warn falsely, and a retried refused switch fall silent. Checks 2.2b and 2.5
  are the live exercise of the change.
- **A post-call warning, every credential type** (`Initialize-OERAuth.ps1:888-910`,
  `$TenantSwitchNotTakenEffect`). After a Graph token has passed the existing GUID `TenantMismatch`
  guard, it warns when the new sign-in names a tenant that differs from the last ESTABLISHED session's
  label, is neither a GUID nor `'organizations'`, and the new token was issued by the same GUID tenant
  that issued the previous session's token. Its input is the record `$script:_OERLastIssuedSession`,
  written only after a session is established (`:1013`) and never cleared by `Disconnect-OER`. Two
  benign shapes satisfy it and the message says so: two names for one tenant, and a previous session
  that named no tenant followed by that tenant's own domain. It does not check the first sign-in in a
  process, nor the first after Omnicit.EntraRBAC is re-imported.
- **Neither warning stops the sign-in**, unless the caller runs with `-WarningAction Stop`: then the
  pre-call warning stops before any token is requested and the post-call warning stops before
  `Connect-MgGraph` and the session rebuild. Section 6 checks both.

**Every unit test on this branch mocks `Get-AzToken`** (`tests/Unit/Private/Initialize-OERAuth.Tests.ps1`,
Describe `Initialize-OERAuth tenant-switch warnings`, P1-P14 and Q1-Q10; `tests/Unit/Public/Connect-OER.Tests.ps1`,
Describe `Connect-OER -Force`). They prove the predicates, the record rule and the text. Two of them prove
where each warning stops a caller running with `-WarningAction Stop`, by calling `Initialize-OERAuth`
directly:
- **P14**, `stops a -WarningAction Stop client secret switch at the pre-call warning, before the token call and both records, in <Environment>`,
  run for `Global` and `USGov`: the stop is an `ActionPreferenceStopException` carrying the pre-call
  warning text, `Get-AzToken` is never invoked for tenant B, and `$script:_OERAuthState`,
  `$script:_OERLastTokenRequest`, `$script:_OERLastAuthorityHost` and `AZURE_AUTHORITY_HOST` are as they
  were before the call.
- **Q10**, `stops a -WarningAction Stop sign-in at the post-call warning, before Connect-MgGraph, the state rebuild and the session record`:
  the stop is an `ActionPreferenceStopException` carrying the post-call warning text, the stopped sign-in
  did reach `Get-AzToken`, `Connect-MgGraph` ran only for the first sign-in, and `$script:_OERAuthState`
  and `$script:_OERLastIssuedSession` are still the previous session's.

They cannot prove what the
real AzAuth and the real token service do: that the refusal still arrives after a SUCCESSFUL first
sign-in (the spike could only measure it after a failed one), that a sign-in back to the tenant the
credential was built for really succeeds, which tenant a real device-code, guest or managed identity
token names, whether `AzToken.TenantId` is the `tid` claim, or whether `-IncludeARM` shows a second
device code. Those are this file's job.

**A known limitation that no check here provokes, on purpose.** MEASURED offline: a device-code
`Get-AzToken` whose device-code request fails at the network level NEVER RETURNS, `-TimeoutSeconds`
included; it waits on a queue only the device-code callback completes. If a device-code check prints
no code at all within two minutes, press Ctrl+C, exit that child process (its AzAuth credential is now
in an unknown state), write "hung before a code was printed" on the result line, and restart the
section in a new child. Do not try to reproduce it.

---

## Open the launcher (once, before section 4)

This block is mechanics, not a check. Run it in an ordinary PowerShell 7 window. It builds the branch,
puts the built module first on `PSModulePath`, and reads the ids into THIS process's environment,
which every child started from here inherits. Nothing is written to disk and nothing is committed.

```powershell
$Repo = 'C:\Git\Omnicit.EntraRBAC'
Set-Location $Repo
git branch --show-current
git log -1 --format='%h %s'
./build.ps1 -Tasks build
$Sep = [System.IO.Path]::PathSeparator
$env:PSModulePath = (Resolve-Path ./output/module).Path + $Sep + (Resolve-Path ./output/RequiredModules).Path + $Sep + $env:PSModulePath

# Identifiers, not secrets: typed here so none of them is ever written into a file.
$env:OER_LIVE_TENANT_A_ID     = Read-Host 'Tenant A id (GUID) -- the signing-in account is a MEMBER created in this tenant'
$env:OER_LIVE_TENANT_A_DOMAIN = Read-Host 'A verified domain of tenant A'
$env:OER_LIVE_TENANT_B_ID     = Read-Host 'Tenant B id (GUID) -- the signing-in account is NOT in this tenant, not even as a guest'
$env:OER_LIVE_TENANT_B_DOMAIN = Read-Host 'A verified domain of tenant B'
$env:OER_LIVE_TENANT_C_DOMAIN = Read-Host 'A verified domain of tenant C, where the signing-in account is a GUEST (Enter to skip 3.6)'
$env:OER_LIVE_APP_ID          = Read-Host 'Client id of a multi-tenant app whose service principal exists in A AND B (Enter to skip section 2, 4.3 and 6.2)'

# Both must be False: either one changes where every sign-in below is sent.
Test-Path Env:AZURE_AUTHORITY_HOST
Test-Path Env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
```

**Expect:** the branch reads `fix/tenant-switch-warning`, the commit is `222c9d9` or later, the build
succeeds, and both `Test-Path` lines print `False`. If either prints `True`, remove it
(`Remove-Item Env:<name>`) before going on.

**Prerequisites, and what to do without them.** One member account (`person1@example.com`) whose home
tenant is A is used everywhere except sections 2, 5 and 6.2. Tenant B must be a tenant that account is
not in at all. Tenant C is optional and is only for 3.6. Section 2, 4.3 and 6.2 need a multi-tenant app
registration with a client secret whose service principal exists in both A and B; no Graph permission
is exercised, since nothing after the sign-in calls Graph. Section 5 needs an Azure-hosted machine with
a managed identity. A check whose prerequisite is missing says "cannot be verified, and therefore we do
not know" and names the missing prerequisite.

**The tenant B prerequisite did NOT hold on the 2026-09-15/16 run.** The account turned out to have an
identity in tenant B as well, so every device-code sign-in that named tenant B came back with a genuine
tenant B token and the post-call warning was never given a failed switch to notice. That is why 3.2,
3.3, 3.4, 3.7 and 6.1 are `- [~]`. Re-running this section usefully needs a tenant the COMPLETING
account has no identity in at all, and the completing account recorded per check.

## Open a child process (paste at the top of EVERY new child)

Start each child from the launcher with `pwsh -NoProfile`, paste this block, and `exit` back to the
launcher when the check tells you to. The block defines the two helpers every check uses.

```powershell
pwsh -NoProfile
```

```powershell
Set-Location 'C:\Git\Omnicit.EntraRBAC'
Import-Module Omnicit.EntraRBAC -Force
'{0} {1} from {2}' -f (Get-Module Omnicit.EntraRBAC).Name, (Get-Module Omnicit.EntraRBAC).Version, (Get-Module Omnicit.EntraRBAC).ModuleBase
'AzAuth {0}' -f (Get-Module AzAuth).Version

$TenantAId     = $env:OER_LIVE_TENANT_A_ID
$TenantADomain = $env:OER_LIVE_TENANT_A_DOMAIN
$TenantBId     = $env:OER_LIVE_TENANT_B_ID
$TenantBDomain = $env:OER_LIVE_TENANT_B_DOMAIN
$TenantCDomain = $env:OER_LIVE_TENANT_C_DOMAIN
$AppId         = $env:OER_LIVE_APP_ID

# Runs one Connect-OER call and captures its warnings on the call itself. A try/catch is a STATEMENT
# and cannot be piped, so it is wrapped in $( ) to make its output capturable.
#
# Only two warnings are this branch's, and each is told apart by a phrase no other warning carries:
# the pre-call warning's 'but the credential AzAuth holds for that application' and the post-call
# warning's 'the same tenant that issued the token for the previous session'. Any other warning --
# AzAuth's, the Graph SDK's, the module's AZURE_AUTHORITY_HOST warning -- lands in OtherWarnings.
function Invoke-OerConnectCheck {
    param([Parameter(Mandatory)][hashtable]$Parameters, [string]$Label = '')
    $PreCallPhrase  = 'but the credential AzAuth holds for that application'
    $PostCallPhrase = 'the same tenant that issued the token for the previous session'
    $Warn = $null
    $Info = $null
    $Outcome = $(
        try {
            Connect-OER @Parameters -WarningVariable Warn -InformationVariable Info -ErrorAction Stop
            'SUCCEEDED'
        } catch {
            $_
        }
    )
    # Both stay $null when parameter binding fails before the command runs, and @($null).Count is 1.
    $AllWarnings = if ($null -eq $Warn) { @() } else { @($Warn | ForEach-Object { [string]$_.Message }) }
    $Err = @($Outcome | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })[0]
    [pscustomobject]@{
        Label              = $Label
        Outcome            = if ($Err) { 'FAILED' } else { 'SUCCEEDED' }
        ErrorId            = if ($Err) { $Err.FullyQualifiedErrorId } else { '' }
        ErrorMessage       = if ($Err) { $Err.Exception.Message } else { '' }
        PreCallWarnings    = @($AllWarnings | Where-Object { $_.Contains($PreCallPhrase) }).Count
        PostCallWarnings   = @($AllWarnings | Where-Object { $_.Contains($PostCallPhrase) }).Count
        OtherWarnings      = @($AllWarnings | Where-Object { -not $_.Contains($PreCallPhrase) -and -not $_.Contains($PostCallPhrase) })
        Warnings           = $AllWarnings
        InformationRecords = if ($null -eq $Info) { 0 } else { $Info.Count }
    }
}

# This module's own in-process evidence. Reads module scope only; never authenticates, and projects
# no token, no account name and no secret.
function Get-OerSwitchEvidence {
    & (Get-Module Omnicit.EntraRBAC) {
        [pscustomobject]@{
            SessionTenantId      = $script:_OERAuthState.TenantId
            SessionAuthMethod    = $script:_OERAuthState.AuthMethod
            TokenTenantId        = $script:_OERAuthState.TokenTenantId
            ArmTokenTenantId     = $script:_OERAuthState.ArmTokenTenantId
            LastIssuedTenantId   = $script:_OERLastIssuedSession.TenantId
            LastIssuedTokenId    = $script:_OERLastIssuedSession.TokenTenantId
            LastRequestMethod    = $script:_OERLastTokenRequest.AuthMethod
            LastRequestClientId  = $script:_OERLastTokenRequest.ClientId
            LastRequestTenantId  = $script:_OERLastTokenRequest.TenantId
        }
    }
}
```

**Expect:** the first tell line's path begins `C:\Git\Omnicit.EntraRBAC\output\module` (in section 5,
the folder you copied the build to). Any other path means another copy of the module was imported, and
nothing below measures this branch.

**How to read the helper's output, in every check below.** Every `Expect:` speaks only of
`PreCallWarnings` and `PostCallWarnings`. **`OtherWarnings` is always a `Record:`** -- write down
anything it holds, and never count it as one of this branch's two warnings.

**Record, once, in the first child you open:** the module version and the AzAuth version the two tell
lines printed. The evidence behind this branch was measured against AzAuth `2.9.0`; the manifest pins
that as a MINIMUM, so a newer AzAuth on `PSModulePath` would load instead, and every MEASURED trace
below would then describe a different binary. If it is not `2.9.0`, say so here and in S.

**Result:**
```powershell
Omnicit.EntraRBAC 1.0.0 from C:\Git\Omnicit.EntraRBAC\output\module\Omnicit.EntraRBAC\1.0.0
AzAuth 2.9.0
```

---

## 1. The public path is unchanged -- interactive sign-in

**Start a NEW child process for this section** and paste the child block. Sign in as
`person1@example.com` every time. Nothing here should warn except the two benign shapes in 1.5 and
1.7, which the warning's own message describes and which are checked here precisely so that an
operator meeting one in daily use can recognise it.

**Why the silent checks carry a condition too.** A check that expects NO warning proves something only
if every other term of the post-call predicate held, so that the one term under test is what kept it
silent. Where that depends on which tenant issued the token, the check says so and names the value to
compare.

- [x] **1.1 A first interactive sign-in, tenant A named by domain, emits no warning.**

  ```powershell
  $R11 = Invoke-OerConnectCheck -Label '1.1' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
  $R11 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `Outcome` `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`. `LastIssuedTenantId`
  reads the tenant A domain, and `LastIssuedTokenId` equals `TokenTenantId`.
  **Record:** `TokenTenantId` (expected to be tenant A's id, row 01 -- an interactive sign-in is sent to
  the tenant it names, but that is DECOMPILED, not measured).
  **Traces to:** pre-call warning requires `EffectiveMethod -eq 'ClientSecret'`
  (`Initialize-OERAuth.ps1:601`, `$ClientSecretTenantSwitchWithoutForce`); post-call warning requires a
  previous established session (`:889`, `[bool]$PreviousSession`), and a fresh module import has none,
  since `:1013` is the only write. Unit tests P5, Q4.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R11 = Invoke-OerConnectCheck -Label '1.1' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
PS C:\Git\Omnicit.EntraRBAC> $R11 | Format-List

Label : 1.1
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-a.example.com
SessionAuthMethod : Interactive
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : tenant-a.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : Interactive
LastRequestClientId :
LastRequestTenantId : tenant-a.example.com

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **1.2 The same call again returns from the cache: no prompt, no warning.**

  ```powershell
  $R12 = Invoke-OerConnectCheck -Label '1.2' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
  $R12 | Format-List
  ```

  **Expect:** no browser prompt, `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`.
  **Traces to:** the cached return (`Initialize-OERAuth.ps1:355-358`, `$GraphCached -and $ArmCached`)
  precedes both warnings (`:608`, `:896`).
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R12 = Invoke-OerConnectCheck -Label '1.2' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
PS C:\Git\Omnicit.EntraRBAC> $R12 | Format-List

Label : 1.2
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **1.3 A same-tenant reconnect that really re-acquires (`-Force`) still emits no warning.**

  1.2 never reached either warning. This one does: `-Force` skips the cache, so the post-call
  predicate is evaluated, and only its label term keeps it silent.

  ```powershell
  $R13 = Invoke-OerConnectCheck -Label '1.3' -Parameters @{ TenantId = $TenantADomain; Interactive = $true; Force = $true }
  $R13 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`, `SessionTenantId` still the
  tenant A domain.
  **Record:** whether a browser prompt appeared, and `TokenTenantId`. **Non-vacuous only if**
  `TokenTenantId` equals the `LastIssuedTokenId` 1.1 printed: then every other post-call term held and
  only the label term kept this silent. If they differ, the silence proves nothing about that term --
  `- [~]`.
  **Traces to:** `Connect-OER.ps1:288` (`-Force` forwards `ForceRefresh`); `Initialize-OERAuth.ps1:313`
  (`-not $ForceRefresh` defeats the cache); post-call term `:890`
  (`$PreviousSession.TenantId -ne $EffectiveTenant` is false for the same label). Unit test Q6.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R13 = Invoke-OerConnectCheck -Label '1.3' -Parameters @{ TenantId = $TenantADomain; Interactive = $true; Force = $true }
PS C:\Git\Omnicit.EntraRBAC> $R13 | Format-List

Label : 1.3
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-a.example.com
SessionAuthMethod : Interactive
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : tenant-a.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : Interactive
LastRequestClientId :
LastRequestTenantId : tenant-a.example.com

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **1.4 The same tenant named by its GUID emits no warning.**

  ```powershell
  $R14 = Invoke-OerConnectCheck -Label '1.4' -Parameters @{ TenantId = $TenantAId; Interactive = $true }
  $R14 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`, `SessionTenantId` tenant A's
  id, `LastIssuedTenantId` tenant A's id.
  **Record:** `TokenTenantId`. **Non-vacuous only if** it equals the `LastIssuedTokenId` 1.3 printed:
  then the label differed, the previous token tenant matched, and only the GUID term kept this silent.
  If they differ, `- [~]`.
  **Traces to:** post-call term `Initialize-OERAuth.ps1:892` (`-not (Test-OERGuid -Value $EffectiveTenant)`)
  excludes a GUID request; `TenantMismatch` (`:756-770`) passes only when the token's GUID equals the
  requested one. Unit test Q3.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R14 = Invoke-OerConnectCheck -Label '1.4' -Parameters @{ TenantId = $TenantAId; Interactive = $true }
PS C:\Git\Omnicit.EntraRBAC> $R14 | Format-List

Label : 1.4
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
SessionAuthMethod : Interactive
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : Interactive
LastRequestClientId :
LastRequestTenantId : tenant-a.example.com

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **1.5 Benign shape 1 -- the same tenant by domain right after it was named by GUID DOES warn,
  and the message says it is expected.**

  ```powershell
  $R15 = Invoke-OerConnectCheck -Label '1.5' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
  $R15 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Record:** `TokenTenantId`.
  **Expect, IF `TokenTenantId` equals the `LastIssuedTokenId` 1.4 printed:** `SUCCEEDED`, `PreCallWarnings`
  `0` and `PostCallWarnings` `1`, the warning beginning `The Microsoft Graph token for tenant
  '<tenant A domain>' was issued by tenant '<tenant A id>', the same tenant that issued the token for the
  previous session, which named '<tenant A id>'.` and containing `If '<tenant A domain>' is a name of
  tenant '<tenant A id>', this is expected.` If the two differ, `PostCallWarnings` must be `0`, and the
  box is `- [~]`.
  **Traces to:** `Initialize-OERAuth.ps1:888-894` (every term holds: previous label is the GUID, the
  domain differs, is neither `'organizations'` nor a GUID, and the granted tenant equals the previous
  token tenant); message `:897-909`. Unit test Q1 pins the text word for word.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R15 = Invoke-OerConnectCheck -Label '1.5' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
WARNING: The Microsoft Graph token for tenant 'tenant-a.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named '00000000-0000-0000-0000-000000000001'. If 'tenant-a.example.com' is a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-a.example.com'. AzAuth does not
send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER -Force to move to ano
ther tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
PS C:\Git\Omnicit.EntraRBAC> $R15 | Format-List

Label : 1.5
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 1
OtherWarnings : {}
Warnings : The Microsoft Graph token for tenant 'tenant-a.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named '00000000-0000-0000-0000-000000000001'. If 'tenant-a.example.com' is a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-a.example.com'. AzAuth does not send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the
same application needs Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-a.example.com
SessionAuthMethod : Interactive
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : tenant-a.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : Interactive
LastRequestClientId :
LastRequestTenantId : tenant-a.example.com

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **1.6 After `Disconnect-OER`, a sign-in that names no tenant emits no warning.**

  ```powershell
  Disconnect-OER
  $R16 = Invoke-OerConnectCheck -Label '1.6' -Parameters @{ Interactive = $true }
  $R16 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`, `SessionTenantId`
  `organizations`, `LastIssuedTenantId` `organizations`.
  **Record:** `TokenTenantId`. **Non-vacuous only if** it equals tenant A's id (the previous session's
  token tenant): then every other post-call term held and only the no-tenant term kept this silent --
  write that down. If it differs, `- [~]`.
  **Traces to:** `Disconnect-OER.ps1:21` clears only `$script:_OERAuthState`; with no state the request
  becomes `'organizations'` (`Initialize-OERAuth.ps1:196-211`); post-call term `:891`
  (`$EffectiveTenant -ne 'organizations'`). Unit test Q9.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC> $R16 = Invoke-OerConnectCheck -Label '1.6' -Parameters @{ Interactive = $true }
PS C:\Git\Omnicit.EntraRBAC> $R16 | Format-List

Label : 1.6
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : organizations
SessionAuthMethod : Interactive
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : organizations
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : Interactive
LastRequestClientId :
LastRequestTenantId : tenant-a.example.com

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **1.7 Benign shape 2 -- a session that named no tenant, then that same tenant's own domain, DOES
  warn.**

  ```powershell
  $R17 = Invoke-OerConnectCheck -Label '1.7' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
  $R17 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Record:** `TokenTenantId`.
  **Expect, IF `TokenTenantId` equals the `TokenTenantId` 1.6 recorded:** `SUCCEEDED` and
  `PostCallWarnings` `1`, naming `'organizations'` as the previous session's label and containing the
  `this is expected` sentence. Otherwise `PostCallWarnings` `0`, and `- [~]`.
  **Traces to:** `Initialize-OERAuth.ps1:888-894` -- `'organizations'` is deliberately NOT excluded as a
  PREVIOUS label (comment `:842-845`); message `:897-909`. Unit test Q7.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R17 = Invoke-OerConnectCheck -Label '1.7' -Parameters @{ TenantId = $TenantADomain; Interactive = $true }
WARNING: The Microsoft Graph token for tenant 'tenant-a.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named 'organizations'. If 'tenant-a.example.com' is a name of te
nant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-a.example.com'. AzAuth does not send the named tenant w
ith a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER -Force to move to another tenant. Name the t
enant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
PS C:\Git\Omnicit.EntraRBAC> $R17 | Format-List

Label : 1.7
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 1
OtherWarnings : {}
Warnings : The Microsoft Graph token for tenant 'tenant-a.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named 'organizations'. If 'tenant-a.example.com' is
a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-a.example.com'. AzAu
th does not send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs
Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-a.example.com
SessionAuthMethod : Interactive
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : tenant-a.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : Interactive
LastRequestClientId :
LastRequestTenantId : tenant-a.example.com

PS C:\Git\Omnicit.EntraRBAC>
  ```

  Then `Disconnect-OER` and `exit` back to the launcher.

---

## 2. Client secret -- one application, two tenants

**Needs:** the multi-tenant app registration from the launcher, with a client secret, whose service
principal exists in tenant A AND tenant B. Without one, write "cannot be verified, and therefore we do
not know -- no multi-tenant app registration consented in two tenants this operator controls" on 2.1
and on every box below, and skip to section 3.

**Start a NEW child process for 2.1-2.6** and paste the child block, then:

```powershell
$Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString
```

All of 2.1-2.6 name both tenants by GUID, so the existing `TenantMismatch` guard stands behind every
one of them, and the post-call warning -- which excludes a GUID request -- cannot fire there.

**Read the `LastRequest...` fields as the tenant AzAuth's credential was BUILT for.** Under the record
rule (`Initialize-OERAuth.ps1:655-661`) they move only on a call that builds a credential, so after a
refused switch they still name the tenant the credential belongs to. Several checks below turn on that.

- [x] **2.1 The first client secret sign-in, tenant A, emits no warning and starts the record.**

  ```powershell
  $R21 = Invoke-OerConnectCheck -Label '2.1' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
  $R21 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `SUCCEEDED`, `PreCallWarnings` `0`, `LastRequestMethod` `ClientSecret`,
  `LastRequestClientId` the app id, `LastRequestTenantId` and `TokenTenantId` both tenant A's id.
  **Traces to:** pre-call term `Initialize-OERAuth.ps1:602` (`$script:_OERLastTokenRequest` is unset in
  a fresh module scope); record move `:655` (`-not $script:_OERLastTokenRequest`) and write `:660`;
  `TenantMismatch` `:756-770` refuses any other GUID. Unit test P9.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString
Client secret of that app registration: ****************************************
PS C:\Git\Omnicit.EntraRBAC> $R21 = Invoke-OerConnectCheck -Label '2.1' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
PS C:\Git\Omnicit.EntraRBAC> $R21 | Format-List

Label : 2.1
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000001
  ```

- [x] **2.2 Tenant B for the same application WITHOUT `-Force`: the pre-call warning, then a refusal.**

  ```powershell
  $R22 = Invoke-OerConnectCheck -Label '2.2' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
  $R22 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:**
  - `PreCallWarnings` `1`, the warning reading `This client secret sign-in for application '<app id>'
    names tenant '<tenant B id>', but the credential AzAuth holds for that application in this
    PowerShell session was built for tenant '<tenant A id>'. AzAuth reuses that credential for the same
    application until it is told to rebuild it, so this sign-in does not reach '<tenant B id>': by
    default it fails with 'The current credential is not configured to acquire tokens for tenant', and
    where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is
    requested from '<tenant A id>' instead. Run Connect-OER again with -Force to rebuild the credential
    for '<tenant B id>'. Disconnect-OER does not clear it.`
  - `Outcome` `FAILED`, `ErrorId` `GraphTokenAcquisitionFailed,Initialize-OERAuth`, and `ErrorMessage`
    beginning `Failed to acquire a Microsoft Graph token:` and containing
    `not configured to acquire tokens for tenant`.
  - `SessionTenantId` and `TokenTenantId` still tenant A's (the refused attempt built no session), and
    `LastRequestTenantId` STILL tenant A's id: a refused reuse builds no credential, so the record does
    not move.

  **If the refusal never arrives** -- `SUCCEEDED` with `TokenTenantId` tenant B's id -- that is a
  FINDING against the pre-call warning's premise (that AzAuth refuses a reused credential after a
  successful sign-in), not a failure of this checklist. Write it as a finding, report it in S, and skip
  2.2b, whose premise is the same refusal.

  **Traces to:** predicate `Initialize-OERAuth.ps1:601-606`, text `:610-619`; record terms `:655-658`
  (all false: same type, same client id, no `Force`), so `:660` is not reached; the catch that wraps any
  `Get-AzToken` failure `:707-720`; the state rebuild `:964` is below that terminating catch. MEASURED
  (rationale `#switching-tenants-in-one-process`, ClientSecret row): the reused credential refuses a
  different tenant with that sentence, before sending anything. **One difference from the measurement,
  and it is why this check exists:** offline, the first sign-in had FAILED before the second was
  refused. Here it succeeded. The decompiled tenant resolver does not read whether an earlier token was
  issued, so the same refusal is expected -- but only this check measures it. Unit test P1.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R22 = Invoke-OerConnectCheck -Label '2.2' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
WARNING: This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not configured to acquire tokens for tenant',
and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild the credential for '00000000-0000-0000-0000-000000000003'
. Disconnect-OER does not clear it.
PS C:\Git\Omnicit.EntraRBAC> $R22 | Format-List

Label : 2.2
Outcome : FAILED
ErrorId : GraphTokenAcquisitionFailed,Initialize-OERAuth
ErrorMessage : Failed to acquire a Microsoft Graph token: The current credential is not configured to acquire tokens for tenant 00000000-0000-0000-0000-000000000003. To enable token acquisition for this tenant, see the guidance at https://aka.ms/azsdk/net/identit
y/multitenant/troubleshoot.
PreCallWarnings : 1
PostCallWarnings : 0
OtherWarnings : {}
Warnings : This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not config
ured to acquire tokens for tenant', and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild
the credential for '00000000-0000-0000-0000-000000000003'. Disconnect-OER does not clear it.
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **2.2b The same switch again, straight after 2.2's refusal: the warning fires again.**

  ```powershell
  $R22b = Invoke-OerConnectCheck -Label '2.2b' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
  $R22b | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `PreCallWarnings` `1`, again naming tenant B's id as the new tenant and tenant A's id as
  the tenant the credential was built for; `Outcome` `FAILED`, `ErrorId`
  `GraphTokenAcquisitionFailed,Initialize-OERAuth`, `ErrorMessage` containing
  `not configured to acquire tokens for tenant`; `LastRequestTenantId` still tenant A's id.
  **Traces to:** `Initialize-OERAuth.ps1:601-620`, reading the record 2.2 left unmoved (`:655-658`);
  `:707-720`. MEASURED (ClientSecret row): the same reused credential, the same refusal. Unit test P11.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R22b = Invoke-OerConnectCheck -Label '2.2b' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
WARNING: This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not configured to acquire tokens for tenant',
and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild the credential for '00000000-0000-0000-0000-000000000003'
. Disconnect-OER does not clear it.
PS C:\Git\Omnicit.EntraRBAC> $R22b | Format-List

Label : 2.2b
Outcome : FAILED
ErrorId : GraphTokenAcquisitionFailed,Initialize-OERAuth
ErrorMessage : Failed to acquire a Microsoft Graph token: The current credential is not configured to acquire tokens for tenant 00000000-0000-0000-0000-000000000003. To enable token acquisition for this tenant, see the guidance at https://aka.ms/azsdk/net/identit
y/multitenant/troubleshoot.
PreCallWarnings : 1
PostCallWarnings : 0
OtherWarnings : {}
Warnings : This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not config
ured to acquire tokens for tenant', and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild
the credential for '00000000-0000-0000-0000-000000000003'. Disconnect-OER does not clear it.
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **2.3 `Connect-OER -Force` to tenant B succeeds, emits no warning, and moves the record.**

  ```powershell
  $R23 = Invoke-OerConnectCheck -Label '2.3' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret; Force = $true }
  $R23 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `SUCCEEDED`, `PreCallWarnings` `0`, `SessionTenantId` and `TokenTenantId` both tenant B's
  id, and `LastRequestTenantId` tenant B's id afterwards.
  **Traces to:** `Connect-OER.ps1:288`; `Initialize-OERAuth.ps1:514-516` puts `Force` on the splat. The
  record still named tenant A when the predicate read it, so every other term of `:601-605` held and
  ONLY the last term, `:606` (`-not $TokenParams.ContainsKey('Force')`), kept this silent. The same
  `Force` moves the record (`:658`, `:660`). Post-call term `:892` excludes the GUID request;
  `TenantMismatch` `:756-770`. MEASURED (ClientSecret row): `-Force` builds a new credential for the new
  tenant and the request goes there. Unit tests P2 and `Connect-OER -Force`.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R23 = Invoke-OerConnectCheck -Label '2.3' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret; Force = $true }
PS C:\Git\Omnicit.EntraRBAC> $R23 | Format-List

Label : 2.3
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000003
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000003
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000003

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **2.4 `Disconnect-OER`, then tenant A without `-Force`: the same warning and the same refusal --
  the record survives the disconnect.**

  ```powershell
  Disconnect-OER
  Get-OerSwitchEvidence | Format-List
  $R24 = Invoke-OerConnectCheck -Label '2.4' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
  $R24 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** the first evidence block shows `SessionTenantId` empty but `LastRequestTenantId` still
  tenant B's id. Then `PreCallWarnings` `1` naming tenant A's id as the new tenant and tenant B's id as
  the tenant the credential was built for, `Outcome` `FAILED`, `ErrorId`
  `GraphTokenAcquisitionFailed,Initialize-OERAuth`, `ErrorMessage` containing
  `not configured to acquire tokens for tenant`. `LastRequestTenantId` is STILL tenant B's id afterwards.
  **Traces to:** `Disconnect-OER.ps1:21` clears `$script:_OERAuthState` and nothing else;
  `Initialize-OERAuth.ps1:601-620`; `:655-658` all false, so the refused reuse does not move the record;
  `:707-720`. MEASURED: nothing `Disconnect-OER` can reach clears AzAuth's credential, which 2.3 built
  for tenant B. Unit test P7.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId :
SessionAuthMethod :
TokenTenantId :
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000003
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000003

PS C:\Git\Omnicit.EntraRBAC> $R24 = Invoke-OerConnectCheck -Label '2.4' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
WARNING: This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000001', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000003'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000001': by default it fails with 'The current credential is not configured to acquire tokens for tenant',
and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000003' instead. Run Connect-OER again with -Force to rebuild the credential for '00000000-0000-0000-0000-000000000001'
. Disconnect-OER does not clear it.
PS C:\Git\Omnicit.EntraRBAC> $R24 | Format-List

Label : 2.4
Outcome : FAILED
ErrorId : GraphTokenAcquisitionFailed,Initialize-OERAuth
ErrorMessage : Failed to acquire a Microsoft Graph token: The current credential is not configured to acquire tokens for tenant 00000000-0000-0000-0000-000000000001. To enable token acquisition for this tenant, see the guidance at https://aka.ms/azsdk/net/identit
y/multitenant/troubleshoot.
PreCallWarnings : 1
PostCallWarnings : 0
OtherWarnings : {}
Warnings : This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000001', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000003'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000001': by default it fails with 'The current credential is not config
ured to acquire tokens for tenant', and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000003' instead. Run Connect-OER again with -Force to rebuild
the credential for '00000000-0000-0000-0000-000000000001'. Disconnect-OER does not clear it.
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId :
SessionAuthMethod :
TokenTenantId :
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000003
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000003

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **2.5 Tenant B again, still without `-Force`, straight after 2.4's refusal: no warning.**

  2.4's refused attempt did not move the record, which still names tenant B -- the tenant AzAuth's
  credential was built for by 2.3. A sign-in back to that tenant is the case the attempt-based record
  used to warn about falsely.

  ```powershell
  $R25 = Invoke-OerConnectCheck -Label '2.5' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
  $R25 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `PreCallWarnings` `0`, and `LastRequestTenantId` still tenant B's id.
  **Record:** `Outcome`, `ErrorId` and `TokenTenantId`. `SUCCEEDED` with `TokenTenantId` tenant B's id
  confirms the record rule against the real AzAuth. A REFUSAL here is a finding -- it would mean the
  refused attempt in 2.4 did change the credential after all -- and goes to S.
  **Traces to:** `Initialize-OERAuth.ps1:605` is false (record tenant B equals the requested tenant B);
  `:655-658` all false. The success is INFERRED from the decompiled AzAuth (the reuse test compares only
  the credential type and client id) and Azure.Identity (a request for the credential's own tenant is
  not refused) -- not measured. Unit test P10.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R25 = Invoke-OerConnectCheck -Label '2.5' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
PS C:\Git\Omnicit.EntraRBAC> $R25 | Format-List

Label : 2.5
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000003
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000003
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000003

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [x] **2.6 A client id that differs only in letter case gets no pre-call warning, and moves the
  record.**

  The only live exercise of the case-sensitive client id term, on both sides: the warning's `-ceq` and
  the record's `-cne`.

  ```powershell
  $AppIdOtherCase = if ($AppId -cne $AppId.ToUpperInvariant()) { $AppId.ToUpperInvariant() } else { $AppId.ToLowerInvariant() }
  $AppIdOtherCase -ceq $AppId
  $R26 = Invoke-OerConnectCheck -Label '2.6' -Parameters @{ TenantId = $TenantAId; ClientId = $AppIdOtherCase; ClientSecret = $Secret }
  $R26 | Format-List
  $E26 = Get-OerSwitchEvidence
  [pscustomobject]@{
      RecordClientIdIsOtherCase = ([string]$E26.LastRequestClientId -ceq $AppIdOtherCase)
      RecordClientIdIsOriginal  = ([string]$E26.LastRequestClientId -ceq $AppId)
      RecordTenantIsTenantA     = ([string]$E26.LastRequestTenantId -eq $TenantAId)
  } | Format-List
  $E26 | Select-Object SessionTenantId, TokenTenantId | Format-List
  ```

  **Expect:** the `-ceq` line prints `False` (if it prints `True`, the id has no letters and this check
  cannot run -- say so). Then `PreCallWarnings` `0`, `RecordClientIdIsOtherCase` `True`,
  `RecordClientIdIsOriginal` `False`, `RecordTenantIsTenantA` `True`.
  **Record:** `Outcome` and `TokenTenantId`. DECOMPILED, not measured: AzAuth's reuse test is an
  ordinal string comparison, so a case-only difference builds a NEW credential for tenant A and the
  sign-in succeeds. A failure here would say either that the reuse test is not ordinal or that Entra
  rejected the re-cased id -- record the error text so the two can be told apart.
  **Traces to:** `Initialize-OERAuth.ps1:604` (`-ceq` makes the warning's predicate false); `:657`
  (`-cne` moves the record) and `:660`. Unit tests P4, P12.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $AppIdOtherCase = if ($AppId -cne $AppId.ToUpperInvariant()) { $AppId.ToUpperInvariant() } else { $AppId.ToLowerInvariant() }
PS C:\Git\Omnicit.EntraRBAC> $AppIdOtherCase -ceq $AppId
False
PS C:\Git\Omnicit.EntraRBAC> $R26 = Invoke-OerConnectCheck -Label '2.6' -Parameters @{ TenantId = $TenantAId; ClientId = $AppIdOtherCase; ClientSecret = $Secret }
PS C:\Git\Omnicit.EntraRBAC> $R26 | Format-List

Label : 2.6
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> $E26 = Get-OerSwitchEvidence
PS C:\Git\Omnicit.EntraRBAC> [pscustomobject]@{
>> RecordClientIdIsOtherCase = ([string]$E26.LastRequestClientId -ceq $AppIdOtherCase)
>> RecordClientIdIsOriginal = ([string]$E26.LastRequestClientId -ceq $AppId)
>> RecordTenantIsTenantA = ([string]$E26.LastRequestTenantId -eq $TenantAId)
>> } | Format-List

RecordClientIdIsOtherCase : True
RecordClientIdIsOriginal : False
RecordTenantIsTenantA : True

PS C:\Git\Omnicit.EntraRBAC> $E26 | Select-Object SessionTenantId, TokenTenantId | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
TokenTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC>
  ```

  Then `Disconnect-OER` and `exit` back to the launcher.

- [x] **2.7 OPTIONAL -- `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH=true`: tenant B by DOMAIN, then by
  GUID.**

  **This check deliberately makes a session whose label names tenant B while its token was requested
  from tenant A.** Run no cmdlet in it; `Disconnect-OER` is the next line, and nothing here writes.
  Skipping it is legitimate -- write "not run, optional" and why.

  In the LAUNCHER, so the child inherits the variable before anything is imported:

  ```powershell
  $env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH = 'true'
  pwsh -NoProfile
  ```

  In the new child, paste the child block, then:

  ```powershell
  $env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
  $Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString

  # a) tenant A by GUID
  $R27a = Invoke-OerConnectCheck -Label '2.7a' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
  $R27a | Format-List

  # b) tenant B by DOMAIN, no -Force. Disconnect immediately afterwards.
  $R27b = Invoke-OerConnectCheck -Label '2.7b' -Parameters @{ TenantId = $TenantBDomain; ClientId = $AppId; ClientSecret = $Secret }
  $R27b | Format-List
  Get-OerSwitchEvidence | Format-List
  Disconnect-OER

  # c) tenant B by GUID, no -Force
  $R27c = Invoke-OerConnectCheck -Label '2.7c' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
  $R27c | Format-List
  Get-OerSwitchEvidence | Format-List
  Disconnect-OER
  exit
  ```

  And back in the LAUNCHER:

  ```powershell
  Remove-Item Env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
  Test-Path Env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
  ```

  **Expect:** the child echoes `true`; 2.7a `SUCCEEDED` with `PreCallWarnings` `0`. 2.7b carries
  `PreCallWarnings` `1` naming the tenant B domain as new and tenant A's id as the tenant the credential
  was built for, and its evidence block shows `LastRequestTenantId` still tenant A's id. 2.7c carries
  `PreCallWarnings` `1` naming tenant B's id as new and tenant A's id as the built-for tenant, and
  `LastRequestTenantId` is still tenant A's id. The launcher's `Test-Path` prints `False`.
  **Record:** 2.7b's `Outcome`, `TokenTenantId` and full warning list. **IF 2.7b SUCCEEDED with
  `TokenTenantId` tenant A's id, Expect** `PostCallWarnings` `1` as well: naming the tenant B domain,
  tenant A's id as issuer, and tenant A's id as the previous session's label.
  **Record:** 2.7c's `Outcome` and `ErrorId`. **IF section 4 found `TenantIdProperty` equal to
  `TidClaim`, Expect** `ErrorId` `TenantMismatch,Initialize-OERAuth` with a message naming tenant A's id
  as the issuing tenant and tenant B's id as the requested one.
  **Traces to:** pre-call `Initialize-OERAuth.ps1:601-620` (the requested tenant differs from the
  record's in both steps); record `:655-658` all false in both steps, so it stays on tenant A;
  post-call `:888-910`; `TenantMismatch` `:756-770`; `Disconnect-OER.ps1:21`. MEASURED (ClientSecret
  row): with this variable set, the reused credential sends its token request to the PREVIOUS tenant.
  That the issued token then names tenant A is INFERRED, hence the conditions.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
true
PS C:\Git\Omnicit.EntraRBAC> $Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString
Client secret of that app registration: ****************************************
PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> # a) tenant A by GUID
PS C:\Git\Omnicit.EntraRBAC> $R27a = Invoke-OerConnectCheck -Label '2.7a' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
PS C:\Git\Omnicit.EntraRBAC> $R27a | Format-List

Label : 2.7a
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> # b) tenant B by DOMAIN, no -Force. Disconnect immediately afterwards.
PS C:\Git\Omnicit.EntraRBAC> $R27b = Invoke-OerConnectCheck -Label '2.7b' -Parameters @{ TenantId = $TenantBDomain; ClientId = $AppId; ClientSecret = $Secret }
WARNING: This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant 'tenant-b.example.com', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. Az
Auth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach 'tenant-b.example.com': by default it fails with 'The current credential is not configured to acquire tokens for tenant', and where multi-tenant authentica
tion is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild the credential for 'tenant-b.example.com'. Disconnect-OER does not clear it.
WARNING: The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named '00000000-0000-0000-0000-000000000001'. If 'tenant-b.example.com'
is a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-b.example.com'. AzAuth does not send the nam
ed tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER -Force to move to another tenant.
Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
PS C:\Git\Omnicit.EntraRBAC> $R27b | Format-List

Label : 2.7b
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 1
PostCallWarnings : 1
OtherWarnings : {}
Warnings : {This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant 'tenant-b.example.com', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach 'tenant-b.example.com': by default it fails with 'The current credential is not configured to acquire tokens for tenant
', and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild the credential for 'tenant-b.example.com'. Disconnect-OER does not clear it., The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named '00000000-0000-0000-0000-000000000001'. If 'tenant-b.example.com' is a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-b.example.com'. AzAuth does not send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and
a client secret sign-in for the same application needs Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.}
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-b.example.com
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : tenant-b.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> # c) tenant B by GUID, no -Force
PS C:\Git\Omnicit.EntraRBAC> $R27c = Invoke-OerConnectCheck -Label '2.7c' -Parameters @{ TenantId = $TenantBId; ClientId = $AppId; ClientSecret = $Secret }
WARNING: This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not configured to acquire tokens for tenant',
and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild the credential for '00000000-0000-0000-0000-000000000003'
. Disconnect-OER does not clear it.
PS C:\Git\Omnicit.EntraRBAC> $R27c | Format-List

Label : 2.7c
Outcome : FAILED
ErrorId : TenantMismatch,Initialize-OERAuth
ErrorMessage : The Microsoft Graph token was issued for tenant '00000000-0000-0000-0000-000000000001', not for the requested tenant '00000000-0000-0000-0000-000000000003'. Omnicit.EntraRBAC refuses a session whose cached tenant does not describe the token beneath
it: every later call would act on '00000000-0000-0000-0000-000000000001' while reporting '00000000-0000-0000-0000-000000000003'. Sign in again with an account that belongs to '00000000-0000-0000-0000-000000000003'.
PreCallWarnings : 1
PostCallWarnings : 0
OtherWarnings : {}
Warnings : This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not config
ured to acquire tokens for tenant', and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild
the credential for '00000000-0000-0000-0000-000000000003'. Disconnect-OER does not clear it.
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId :
SessionAuthMethod :
TokenTenantId :
ArmTokenTenantId :
LastIssuedTenantId : tenant-b.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC> exit
  ```

---

## 3. Device code -- the tenant is never sent

**Start a NEW child process for 3.1-3.6** and paste the child block. Sign in as `person1@example.com`
every time a code is shown -- including when the check names tenant B, which that account is not in:
the device-code page is tenant-independent, and completing it with the wrong account is the situation
the post-call warning exists for.

**How to count device codes.** The module re-emits the sign-in instruction on the INFORMATION stream
(`Initialize-OERAuth.ps1:497-500`), so the helper's `InformationRecords` counts it, but it counts any
other information record too. Count the codes you actually typed in as well, and record both.

**Why several checks begin with an `-IncludeARM` sign-in to tenant A.** MEASURED in the module's own
device-code call shape: the Graph call passes a client id and the ARM call passes none, so AzAuth
builds a NEW credential at each of them. A Graph-only sign-in straight after an `-IncludeARM` one
therefore starts from a credential that has never signed in, and has to show a fresh device code.
Without that step, AzAuth reuses a credential that already holds this account's sign-in, and
Azure.Identity may first try to acquire the token silently for the named tenant (DECOMPILED, not
measured). 3.5 is the one check that deliberately takes that second path.

**The device-code hang, and the `-Force` the 2026-09-16 run had to add.** A device-code sign-in that
REUSES a credential which has ALREADY completed a sign-in, and names a different tenant, with no
`-Force`, **never returns**: no device code is printed, no error is raised, and the call does not come
back. MEASURED live on 2026-09-16, twice independently -- through this module (3.5) and against raw
`Get-AzToken` outside it (4.2). In 3.5 the helper function returned `$null`, so it never reached its
own return expression. That is why the command lines of 3.4a, 3.4, 3.5, 3.6a and 3.6 below carry
`Force = $true`: it is what the run had to add to get a device code shown at all, and it cured the
hang every time it was used.

**The condition is narrower than "any device-code tenant switch".** 3.2 and 3.3 switched tenants by
device code with no `-Force` and did NOT hang. Both ran straight after an `-IncludeARM` sign-in, whose
ARM call passes no client id and so makes AzAuth build a fresh credential -- the very step the
paragraph above already explains this section inserts. The hang needs a credential that has already
completed a sign-in.

`-TimeoutSeconds` does not bound it, and it is **not this module's parameter**: `Get-AzToken` owns it,
and `source/` passes it nowhere (MEASURED: zero occurrences in `source/`). The only escape is Ctrl+C,
which leaves AzAuth's credential in an unknown state -- so exit that child process and restart the
section in a new one rather than carrying on inside it.

- [x] **3.1 A first device-code sign-in with `-IncludeARM`, tenant A by GUID.**

  ```powershell
  $R31 = Invoke-OerConnectCheck -Label '3.1' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; IncludeARM = $true }
  $R31 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`, `TokenTenantId` tenant A's id.
  **Record:** the number of device codes you completed (INFERRED: two -- one for Graph, one for ARM),
  `InformationRecords`, and `ArmTokenTenantId`.
  **Traces to:** no previous session (`Initialize-OERAuth.ps1:889`, `:1013`); the pre-call warning is
  client secret only (`:601`); `TenantMismatch` `:756-770` and its ARM twin `:1052-1067`; the comment on
  the second device code `:476-488`. MEASURED (rationale `#switching-tenants-in-one-process`, further
  finding 2): the ARM call builds a new credential.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R31 = Invoke-OerConnectCheck -Label '3.1' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; IncludeARM = $true }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R31 | Format-List

Label : 3.1
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 2

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC>
  ```

- [~] **3.2 Straight on to tenant B by DOMAIN, no `Disconnect-OER` -- the post-call warning.**

  ```powershell
  $R32 = Invoke-OerConnectCheck -Label '3.2' -Parameters @{ TenantId = $TenantBDomain; DeviceCode = $true }
  $R32 | Format-List
  Get-OerSwitchEvidence | Format-List
  Disconnect-OER
  ```

  **Record:** device codes completed, `Outcome`, `TokenTenantId`.
  **Expect, IF `SUCCEEDED` with `TokenTenantId` tenant A's id:** `PostCallWarnings` `1`, the warning
  beginning `The Microsoft Graph token for tenant '<tenant B domain>' was issued by tenant
  '<tenant A id>', the same tenant that issued the token for the previous session, which named
  '<tenant A id>'.` and containing `did not switch tenants`; `SessionTenantId` the tenant B domain (a
  warning, not a refusal). If `TokenTenantId` is anything else, `PostCallWarnings` `0` and `- [~]`.
  **Traces to:** `Initialize-OERAuth.ps1:888-894`, `:897-909`. MEASURED (DeviceCode row): the
  device-code request goes to `organizations` whatever tenant is named. INFERRED, hence the condition:
  the token is then issued by the signing-in account's own tenant. Unit test Q1.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R32 = Invoke-OerConnectCheck -Label '3.2' -Parameters @{ TenantId = $TenantBDomain; DeviceCode = $true }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R32 | Format-List

Label : 3.2
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 1

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-b.example.com
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : tenant-b.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC>
  ```

  **Scoring: `- [~]`.** Its `Expect:` was conditional on `TokenTenantId` being tenant A's id; it came
  back tenant B's. The token really was issued by tenant B, so the switch DID take effect and there
  was no failed switch to warn about. The check executed cleanly and the warning was never given the
  input it tests.

- [~] **3.3 Tenant A, `Disconnect-OER`, then tenant B by DOMAIN -- the warning survives the
  disconnect.**

  ```powershell
  $R33a = Invoke-OerConnectCheck -Label '3.3a' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; IncludeARM = $true }
  $R33a | Format-List
  Disconnect-OER
  Get-OerSwitchEvidence | Format-List
  $R33 = Invoke-OerConnectCheck -Label '3.3' -Parameters @{ TenantId = $TenantBDomain; DeviceCode = $true }
  $R33 | Format-List
  Get-OerSwitchEvidence | Format-List
  Disconnect-OER
  ```

  **Expect:** 3.3a `SUCCEEDED` with `PostCallWarnings` `0` (a GUID request). The evidence block after
  the disconnect shows `SessionTenantId` empty and `LastIssuedTenantId` tenant A's id.
  **Record:** device codes completed for 3.3, its `Outcome` and `TokenTenantId`.
  **Expect, IF 3.3 `SUCCEEDED` with `TokenTenantId` tenant A's id:** `PostCallWarnings` `1`, as in 3.2,
  naming tenant A's id as the previous session's label. Otherwise `PostCallWarnings` `0` and `- [~]`.
  **Traces to:** `Disconnect-OER.ps1:21` (clears only the state, never `$script:_OERLastIssuedSession`);
  `Initialize-OERAuth.ps1:888` reads that record, not the state; `:892` keeps 3.3a silent. Unit test Q8.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R33a = Invoke-OerConnectCheck -Label '3.3a' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; IncludeARM = $true }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R33a | Format-List

Label : 3.3a
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 2

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId :
SessionAuthMethod :
TokenTenantId :
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC> $R33 = Invoke-OerConnectCheck -Label '3.3' -Parameters @{ TenantId = $TenantBDomain; DeviceCode = $true }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R33 | Format-List

Label : 3.3
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 1

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-b.example.com
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : tenant-b.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC>
  ```

  **Scoring: `- [~]`.** The same condition as 3.2, and the same outcome: the `Expect:` required
  `TokenTenantId` to be tenant A's id, and it came back tenant B's, so the switch took effect and the
  warning had nothing to fire on. 3.3a's own half did hold -- `PostCallWarnings` `0` on a GUID request,
  and the post-disconnect evidence block showing `SessionTenantId` empty with `LastIssuedTenantId`
  tenant A's id.

- [~] **3.4 Tenant A, `Disconnect-OER`, then NO tenant -- no warning.**

  ```powershell
  $R34a = Invoke-OerConnectCheck -Label '3.4a' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; Force = $true }
  $R34a | Format-List
  Disconnect-OER
  $R34 = Invoke-OerConnectCheck -Label '3.4' -Parameters @{ DeviceCode = $true; Force = $true }
  $R34 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** 3.4 `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`, `SessionTenantId`
  `organizations`.
  **Record:** device codes completed for 3.4a and for 3.4 (zero is a legitimate answer: this credential
  has already signed in), and 3.4's `TokenTenantId`. **Non-vacuous only if** it is tenant A's id: then
  every other post-call term held and only the no-tenant term kept this silent. If it differs, `- [~]`.
  **Traces to:** `Initialize-OERAuth.ps1:196-211` (no state, no `-TenantId`: `'organizations'`), `:891`.
  Unit test Q9.
  **Result:**
  ```powershell
It doesn't work. Its consistent with DeviceCode and all Devce Code test. We need to use force for the actual Device Code to appear. It doesn't show.
PS C:\Git\Omnicit.EntraRBAC> $R34a = Invoke-OerConnectCheck -Label '3.4a' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; Force = $True }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R34a | Format-List

Label : 3.4a
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 1

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC> $R34 = Invoke-OerConnectCheck -Label '3.4' -Parameters @{ DeviceCode = $true; Force = $True }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R34 | Format-List

Label : 3.4
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 1

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : organizations
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : organizations
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : organizations

PS C:\Git\Omnicit.EntraRBAC>
  ```

  **Scoring: `- [~]`.** By this check's own rule: "Non-vacuous only if `TokenTenantId` is tenant A's
  id." It was tenant B's, so the silence proves nothing about the no-tenant term. The Record still
  stands, and it is the row that identifies tenant B as the completing account's own tenant in this
  run. Note also that neither 3.4a nor 3.4 could be made to show a device code at all without
  `Force = $true` -- see the device-code hang recorded at the head of this section.

- [x] **3.5 RECORD -- tenant B by DOMAIN on a credential that has already signed in.**

  Run straight after 3.4, with no disconnect and no `-IncludeARM` step: AzAuth now holds a credential
  that has already signed this account in. DECOMPILED, not measured: Azure.Identity then first tries to
  acquire the token silently FOR THE NAMED TENANT, and shows a new device code only when that needs
  interaction. If that silent attempt reached tenant B, the switch would have taken effect and the
  warning would rightly stay silent (comment `Initialize-OERAuth.ps1:803-812`).
  **That citation was re-pinned BY HAND**, since the paragraph it names was rewritten on this branch
  after the run and the mechanical re-pin declined to guess: the comment at that anchor now records
  the fall-back half of this inference as CONTRADICTED BY MEASUREMENT. The silent acquisition attempt
  is still decompiled; the fall-back to a new device code is not what happens -- the call hangs. See
  the device-code hang at the head of this section.

  ```powershell
  $R35 = Invoke-OerConnectCheck -Label '3.5' -Parameters @{ TenantId = $TenantBDomain; DeviceCode = $true; Force = $true }
  $R35 | Format-List
  Get-OerSwitchEvidence | Format-List
  Disconnect-OER
  ```

  **Record:** device codes completed (zero means the silent path answered), `Outcome`, `ErrorId`, the
  first sentence of `ErrorMessage` if it failed, `TokenTenantId`, and the warning list. The Record is
  this check's deliverable and is written whatever happened.
  **Expect, IF `SUCCEEDED` with `TokenTenantId` equal to 3.4's `TokenTenantId`:** `PostCallWarnings` `1`,
  naming `'organizations'` as the previous session's label. Otherwise `PostCallWarnings` `0`, and the
  box is `- [~]`: the Record still stands, but the warning was never given the input it tests.
  **Traces to:** `Initialize-OERAuth.ps1:888-910`.
  **Result:**
  ```powershell
Same as above. No Device Code shows, just stuck. Must do force.
PS C:\Git\Omnicit.EntraRBAC> $R35 = Invoke-OerConnectCheck -Label '3.5' -Parameters @{ TenantId = $TenantBDomain; DeviceCode = $true }
PS C:\Git\Omnicit.EntraRBAC> $R35 | Format-List
PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : organizations
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : organizations
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : organizations

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC> $R35 = Invoke-OerConnectCheck -Label '3.5' -Parameters @{ TenantId = $TenantBDomain; DeviceCode = $true; Force = $true }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
WARNING: The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant '00000000-0000-0000-0000-000000000003', the same tenant that issued the token for the previous session, which named 'organizations'. If 'tenant-b.example.com' is a name of tenant '00000000-0000-0000-0000-000000000003', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000003' while reporting 'tenant-b.example.com'. AzAuth does not send the named tenant with a new de
vice code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER -Force to move to another tenant. Name the tenant by its
tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
PS C:\Git\Omnicit.EntraRBAC> $R35 | Format-List

Label : 3.5
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 1
OtherWarnings : {}
Warnings : The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant '00000000-0000-0000-0000-000000000003', the same tenant that issued the token for the previous session, which named 'organizations'. If 'tenant-b.example.com' is a name
of tenant '00000000-0000-0000-0000-000000000003', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000003' while reporting 'tenant-b.example.com'. AzAuth does not
send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER
-Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
InformationRecords : 1

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : tenant-b.example.com
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : tenant-b.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : tenant-b.example.com

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC>
  ```

- [~] **3.6 RECORD -- a GUEST account's device-code token, tenant C by DOMAIN.**

  Needs tenant C, where `person1@example.com` is a guest. Without it: "cannot be verified, and
  therefore we do not know -- no tenant where the signing-in account is a guest".

  ```powershell
  $R36a = Invoke-OerConnectCheck -Label '3.6a' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; IncludeARM = $true; Force = $true }
  $R36a | Format-List
  Disconnect-OER
  $R36 = Invoke-OerConnectCheck -Label '3.6' -Parameters @{ TenantId = $TenantCDomain; DeviceCode = $true; Force = $true }
  $R36 | Format-List
  Get-OerSwitchEvidence | Format-List
  Disconnect-OER
  ```

  **Record:** device codes completed, `Outcome`, and `TokenTenantId` -- tenant A's id (the guest's home
  tenant) or tenant C's (row 04). That is the question this check exists for.
  **Expect, IF `TokenTenantId` is tenant A's id:** `PostCallWarnings` `1`. **IF it is tenant C's:**
  `PostCallWarnings` `0`, since the switch did take effect.
  **Traces to:** `Initialize-OERAuth.ps1:888-910`.
  **Result:**
  ```powershell
Unable to test this due to Guest account limitations and access. It's fine. Nothing we need to itterae further on.
  ```

  **Scoring: `- [~]`.** The check was never given its input: tenant C, where the signing-in account is
  a guest, was not available to this run, so no guest device-code token was ever obtained. The question
  it exists for -- whether a GUEST's device-code token comes back issued by the guest's HOME tenant or
  by the host tenant -- is therefore still open. Row 04 of the placeholder table is NOT ALLOCATED: no
  tenant C id was ever printed.

  Then `exit` back to the launcher.

- [~] **3.7 Tenant B by GUID, first sign-in in a NEW process -- `TenantMismatch`.**

  **Start a NEW child process** and paste the child block. Sign in as `person1@example.com`, which is
  not in tenant B.

  ```powershell
  $R37 = Invoke-OerConnectCheck -Label '3.7' -Parameters @{ TenantId = $TenantBId; DeviceCode = $true }
  $R37 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `Outcome` `FAILED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`, and `SessionTenantId`,
  `TokenTenantId` and `LastIssuedTenantId` all empty: no session was established and nothing was
  recorded as one.
  **Expect, IF a device code was completed and section 4 found `TenantIdProperty` equal to `TidClaim`:**
  `ErrorId` `TenantMismatch,Initialize-OERAuth`, with a message beginning `The Microsoft Graph token was
  issued for tenant '<tenant A id>', not for the requested tenant '<tenant B id>'.`
  **Record:** device codes completed, `ErrorId`.
  **Traces to:** `Initialize-OERAuth.ps1:756-770`, which terminates above `Connect-MgGraph` (`:948`),
  the state rebuild (`:964`) and the session record write (`:1013`). MEASURED (DeviceCode row): the
  request goes to `organizations` whatever tenant is named. Found live before this branch
  (rationale `#requested-tenant-vs-granted-tenant`): device-code sign-ins naming a tenant the account was
  not in returned sessions for the signing-in account's own tenant.
  **Result:**
  ```powershell
It works, its due to that Device Code ALWAYS uses the Common/organization sign-in method and is tenant independted.

PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> $R37 = Invoke-OerConnectCheck -Label '3.7' -Parameters @{ TenantId = $TenantBId; DeviceCode = $true }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R37 | Format-List

Label : 3.7
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 1

PS C:\Git\Omnicit.EntraRBAC> Get-OerSwitchEvidence | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000003
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000003
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : 00000000-0000-0000-0000-000000000003

PS C:\Git\Omnicit.EntraRBAC>
  ```

  **Scoring: `- [~]`.** Its `Expect:` was `FAILED` with `TenantMismatch`; it SUCCEEDED, with a genuine
  tenant B token. The guard was therefore never handed a wrong-tenant token to refuse, so the check
  executed cleanly and measured nothing about the guard. **It is NOT a FAILED box:** nothing the code
  does went wrong here. The PREREQUISITE did -- the signing-in account turned out to have an identity
  in tenant B, which this file requires it not to have. See "What the run found".

  Then `exit` back to the launcher.

---

## 4. What `AzToken.TenantId` actually carries -- run this section FIRST

The post-call warning, the `TenantMismatch` guard and `TokenTenantId` all read `AzToken.TenantId`.
DECOMPILED only (rationale `#switching-tenants-in-one-process`, "Where the granted-tenant value itself
comes from"): AzAuth fills it from the token's `tid` claim, and ECHOES THE REQUESTED TENANT BACK when
the token has no `tid`. An echo would silently disable the post-call warning, since a domain echoed
back never equals a previous GUID. Every tenant below is therefore named by DOMAIN: an echo is then
visible as a domain where a GUID should be.

**This section calls `Get-AzToken` directly and holds a real access token in `$Token`.** The helper
decodes only the token's middle (payload) segment, in memory, and returns `tid` plus three booleans.
**Never type `$Token` on its own, never pipe it anywhere, never run this under `Start-Transcript`.**
The decode's `catch` prints a fixed string, not the exception, so even a failed decode cannot echo the
token. Every block ends by dropping the variable.

**Start a NEW child process for 4.1-4.2** and paste the child block, then:

```powershell
# The module's delegated Graph client, read from source rather than written into this file.
$GraphClientId = [regex]::Match(
    (Get-Content -Raw -LiteralPath 'C:\Git\Omnicit.EntraRBAC\source\Private\Initialize-OERAuth.ps1'),
    "DefaultGraphClientId = '([0-9a-fA-F-]+)'").Groups[1].Value
$GraphClientId.Length

function Measure-OerTokenTenant {
    param([Parameter(Mandatory)][object]$AzToken, [Parameter(Mandatory)][string]$Requested, [string]$Label = '')
    $Tid = try {
        $Segment = $AzToken.Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($Segment.Length % 4) {
            2 { $Segment += '==' }
            3 { $Segment += '=' }
        }
        ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Segment)) | ConvertFrom-Json).tid
    } catch {
        'DECODE FAILED'
    }
    [pscustomobject]@{
        Label                 = $Label
        TenantIdProperty      = $AzToken.TenantId
        TidClaim              = $Tid
        PropertyEqualsTid     = ([string]$AzToken.TenantId -eq [string]$Tid)
        PropertyEchoesRequest = ([string]$AzToken.TenantId -eq $Requested)
        TidIsRequest          = ([string]$Tid -eq $Requested)
    }
}
```

**Expect:** `$GraphClientId.Length` prints `36`.

- [x] **4.1 RECORD -- a first device-code token for tenant A, named by domain.**

  ```powershell
  $Token = $null
  $Fail41 = $( try { $Token = Get-AzToken -DeviceCode -ClientId $GraphClientId -Resource 'https://graph.microsoft.com/' -Scope 'User.Read' -Tenant $TenantADomain -ErrorAction Stop } catch { $_.Exception.Message } )
  $Fail41
  if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantADomain -Label '4.1' | Format-List }
  $Token = $null
  Remove-Variable -Name Token
  ```

  **Record:** the six fields, with both ids redacted. `PropertyEqualsTid` `True` and
  `PropertyEchoesRequest` `False` settle the decompile for an ordinary token; any other combination is a
  finding against every post-call `Expect:` in this file -- say so in S.
  **Traces to:** the input of `Initialize-OERAuth.ps1:755` (`$GrantedTenant = $GraphToken.TenantId`),
  which feeds `TokenTenantId` in the state (`:977`) and the session record (`:1013`). The call uses the
  same client, resource and tenant as the module's Graph device-code splat (`:695-703`); its scope is
  reduced to `User.Read`.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $GraphClientId.Length
36
PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> $Fail41 = $( try { $Token = Get-AzToken -DeviceCode -ClientId $GraphClientId -Resource 'https://graph.microsoft.com/' -Scope 'User.Read' -Tenant $TenantADomain -ErrorAction Stop
} catch { $_.Exception.Message } )
WARNING: To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $Fail41
PS C:\Git\Omnicit.EntraRBAC> if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantADomain -Label '4.1' | Format-List }

Label : 4.1
TenantIdProperty : 00000000-0000-0000-0000-000000000001
TidClaim : 00000000-0000-0000-0000-000000000001
PropertyEqualsTid : True
PropertyEchoesRequest : False
TidIsRequest : False

PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> Remove-Variable -Name Token
  ```

- [x] **4.2 RECORD -- the SWITCH: tenant B by domain, same process, no `-Force`.**

  Complete any device code with `person1@example.com`, which is not in tenant B.

  ```powershell
  $Token = $null
  $Fail42 = $( try { $Token = Get-AzToken -DeviceCode -ClientId $GraphClientId -Resource 'https://graph.microsoft.com/' -Scope 'User.Read' -Tenant $TenantBDomain -ErrorAction Stop } catch { $_.Exception.Message } )
  $Fail42
  if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantBDomain -Label '4.2' | Format-List }
  $Token = $null
  Remove-Variable -Name Token
  ```

  **If 4.2 printed an error and no fields**, run the same call once more with `-Force` added after
  `-ErrorAction Stop`, label it `4.2-Force`, and record both. MEASURED: `-Force` builds a new device-code
  credential, so that run shows a fresh code.

  **Record:** whether a device code was shown, the error's first sentence if any, and the six fields.
  The decisive answers: whether `TenantIdProperty` is the tenant B domain (an echo -- the post-call
  warning could then never fire for a device-code switch), tenant A's id (the `tid` of a token issued by
  the account's home tenant -- the shape the warning is built for), or tenant B's id.
  **Traces to:** as 4.1; the comment block at `Initialize-OERAuth.ps1:787-801` (which tenant a
  device-code token is issued for) and `:814-820` (whether `AzToken.TenantId` is the `tid` claim) held
  both of these facts as INFERRED and DECOMPILED when this check was written. **Both citations were
  re-pinned BY HAND**, since both paragraphs were rewritten on this branch after the run and the
  mechanical re-pin declined to guess: the first is now a RECORDED OBSERVATION weakened by this run,
  and the second is MEASURED -- by this very check.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> Remove-Variable -Name Token
PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> $Fail42 = $( try { $Token = Get-AzToken -DeviceCode -ClientId $GraphClientId -Resource 'https://graph.microsoft.com/' -Scope 'User.Read' -Tenant $TenantBDomain -ErrorAction Stop
} catch { $_.Exception.Message } )
PS C:\Git\Omnicit.EntraRBAC> $Fail42
PS C:\Git\Omnicit.EntraRBAC> if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantBDomain -Label '4.2' | Format-List }
PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> Remove-Variable -Name Token^C
PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> $Fail42 = $( try { $Token = Get-AzToken -DeviceCode -ClientId $GraphClientId -Resource 'https://graph.microsoft.com/' -Scope 'User.Read' -Tenant $TenantBDomain -ErrorAction Stop
-Force } catch { $_.Exception.Message } )
WARNING: To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $Fail42
PS C:\Git\Omnicit.EntraRBAC> if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantBDomain -Label '4.2' | Format-List }

Label : 4.2
TenantIdProperty : 00000000-0000-0000-0000-000000000003
TidClaim : 00000000-0000-0000-0000-000000000003
PropertyEqualsTid : True
PropertyEchoesRequest : False
TidIsRequest : False

PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> Remove-Variable -Name Token
PS C:\Git\Omnicit.EntraRBAC>
  ```

  Then `exit` back to the launcher.

- [~] **4.3 OPTIONAL RECORD -- client secret under `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH=true`,
  tenant A then tenant B, both by domain.**

  Needs section 2's app registration. This is the one shape MEASURED to send its request to the
  previous tenant, so it is where an echo of the requested tenant would be most misleading.

  **This child calls `Get-AzToken` directly, outside the module, so nothing scrubs a failure.** A failed
  call leaves an `ErrorRecord` in `$Error` whose `InvocationInfo.BoundParameters` holds the client
  secret IN PLAIN TEXT. **Never render `$Error`, `$Error[0]` or any error record in this child** -- no
  `Format-List *`, no `Get-Error`, no transcript -- and the block clears `$Error` before it exits.

  In the LAUNCHER: `$env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH = 'true'`, then `pwsh -NoProfile`. In the
  child, paste the child block and the section 4 helper block above, then:

  ```powershell
  $env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
  $Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString

  $Token = $null
  $Fail43a = $( try { $Token = Get-AzToken -ClientId $AppId -ClientSecret ([System.Net.NetworkCredential]::new('', $Secret).Password) -Resource 'https://graph.microsoft.com/' -Tenant $TenantADomain -ErrorAction Stop } catch { $_.Exception.Message } )
  $Fail43a
  if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantADomain -Label '4.3a' | Format-List }
  $Token = $null

  $Fail43b = $( try { $Token = Get-AzToken -ClientId $AppId -ClientSecret ([System.Net.NetworkCredential]::new('', $Secret).Password) -Resource 'https://graph.microsoft.com/' -Tenant $TenantBDomain -ErrorAction Stop } catch { $_.Exception.Message } )
  $Fail43b
  if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantBDomain -Label '4.3b' | Format-List }
  $Token = $null
  Remove-Variable -Name Token

  # A failed call above left its bound parameters -- the plaintext secret among them -- in $Error.
  $Error.Clear()
  $Error.Count
  exit
  ```

  Back in the LAUNCHER: `Remove-Item Env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH`, then
  `Test-Path Env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH` must print `False`.

  **Expect:** `$Error.Count` prints `0` before `exit`.
  **Record:** both field sets. 4.3b is the question: `TidClaim` tenant A's id with `TenantIdProperty`
  either tenant A's id (the property carries `tid`) or the tenant B domain (an echo).
  **Traces to:** as 4.1. MEASURED (ClientSecret row): with the variable set, the reused credential
  requests the previous tenant.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
PS C:\Git\Omnicit.EntraRBAC> $Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString
Client secret of that app registration: ****************************************
PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> $Fail43a = $( try { $Token = Get-AzToken -ClientId $AppId -ClientSecret ([System.Net.NetworkCredential]::new('', $Secret).Password) -Resource 'https://graph.microsoft.com/' -Tena
nt $TenantADomain -ErrorAction Stop } catch { $_.Exception.Message } )
PS C:\Git\Omnicit.EntraRBAC> $Fail43a
PS C:\Git\Omnicit.EntraRBAC> if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantADomain -Label '4.3a' | Format-List }

Label : 4.3a
TenantIdProperty : 00000000-0000-0000-0000-000000000001
TidClaim : 00000000-0000-0000-0000-000000000001
PropertyEqualsTid : True
PropertyEchoesRequest : False
TidIsRequest : False

PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> $Fail43b = $( try { $Token = Get-AzToken -ClientId $AppId -ClientSecret ([System.Net.NetworkCredential]::new('', $Secret).Password) -Resource 'https://graph.microsoft.com/' -Tena
nt $TenantBDomain -ErrorAction Stop } catch { $_.Exception.Message } )
PS C:\Git\Omnicit.EntraRBAC> $Fail43b
The current credential is not configured to acquire tokens for tenant tenant-b.example.com. To enable token acquisition for this tenant, see the guidance at https://aka.ms/azsdk/net/identity/multitenant/trouble
shoot.
PS C:\Git\Omnicit.EntraRBAC> if ($Token) { Measure-OerTokenTenant -AzToken $Token -Requested $TenantBDomain -Label '4.3b' | Format-List }
PS C:\Git\Omnicit.EntraRBAC> $Token = $null
PS C:\Git\Omnicit.EntraRBAC> Remove-Variable -Name Token
PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> # A failed call above left its bound parameters -- the plaintext secret among them -- in $Error.
PS C:\Git\Omnicit.EntraRBAC> $Error.Clear()
PS C:\Git\Omnicit.EntraRBAC> $Error.Count
0
PS C:\Git\Omnicit.EntraRBAC> exit
  C:\Git\Omnicit.EntraRBAC fix/tenant-switch-warning operator@workstation 12:57:49
  ```

  **What this run actually measured, and why the box is `- [~]`.** The block's own first line,
  `$env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH`, **printed nothing**: the variable was not set in this
  child. (2.7's child printed `true` in the same position, which is what the set state looks like.) So
  4.3b exercised the DEFAULT client secret path and got the default refusal -- the same outcome 2.2,
  2.2b and 2.4 already measured -- and never reached the question it exists for, which is what an
  echo would look like under the silent-redirect path. It EXECUTED cleanly and proves nothing about
  that question: `- [~]`, not a pass and not a failure.

  **4.3a still stands on its own:** `PropertyEqualsTid` `True`, `PropertyEchoesRequest` `False`, for a
  client secret token. That is one of the three measurements section 4 was run for.

  **4.3b's actual question was answered anyway, by 2.7b.** With the variable genuinely set, a client
  secret sign-in naming `tenant-b.example.com` SUCCEEDED and its `TokenTenantId` came back
  `00000000-0000-0000-0000-000000000001` -- the PREVIOUS tenant's id, not an echo of the requested
  domain. Both halves of the MEASURED ClientSecret row in
  `docs/development/rationale.md#switching-tenants-in-one-process` are therefore confirmed live: the
  default refusal (2.2, 2.2b, 2.4 and 4.3b), and the silent redirect under the environment variable
  (2.7b).

---

## 5. Managed identity -- the tenant is not an input at all

**Needs an Azure-hosted machine with a managed identity** (a VM, an Automation or Functions host, a
self-hosted agent). On any other machine every box here reads "cannot be verified, and therefore we do
not know -- no Azure-hosted machine with a managed identity".

**Setting up on that machine.** Copy `output/module` and `output/RequiredModules` from the launcher's
build there. Run the launcher block with three changes: **skip the two `git` lines and
`./build.ps1`** (there is no clone and nothing to build), point `Set-Location` and both `Resolve-Path`
paths at the folder you copied into, and **answer the tenant A and tenant B prompts both** -- 5.2 and
5.3 use one of them, depending on where the identity lives (below). Press Enter at the tenant C and
application prompts. Then start one child, and in the child block change only `Set-Location`; the
`ModuleBase` tell should now name your copied folder.

```powershell
$MiClientId = Read-Host 'Client id of a user-assigned managed identity (Enter for system-assigned)'
$MiParameters = @{ ManagedIdentity = $true }
if ($MiClientId) { $MiParameters.ClientId = $MiClientId }
```

**5.2 and 5.3 need a tenant that is NOT the identity's own.** They are written with tenant B. If 5.1
shows the identity lives in tenant B, replace `$TenantBDomain` and `$TenantBId` in both with
`$TenantADomain` and `$TenantAId` -- which is why both prompts were answered.

**Where and when section 5 actually ran.** On 2026-09-16, as **Azure Automation runbooks** on the
Automation account's **system-assigned** managed identity -- not on a VM and not from an interactive
console. The Result blocks below are the **job output itself**, pasted, which is why they carry no
`PS ...>` prompt lines: a runbook job has no prompt. The leading `Completed` line is Automation's own
job status, and the two tell lines under it are the child block's, so the `ModuleBase` names the
Automation sandbox's module folder rather than a local `output/module` -- which is the section 5 form
of the child block's `Expect:`.

**The versions differ from the rest of this file:** AzAuth **2.10.0** and PowerShell
**7.6.0-preview.5**, where sections 1-4 and 6 ran on AzAuth 2.9.0 and PowerShell 7.6.6. Section 5 is
therefore the only part of this run measured against a different AzAuth build, and the `AzAuth 2.10.0`
tell line in every block below is the evidence for it. The manifest pins AzAuth 2.9.0 as a MINIMUM, so
a newer one on `PSModulePath` is what a user actually gets; the IL comparison that carries the 2.9.0
measurements across to 2.10.0 is recorded in
`docs/development/rationale.md#switching-tenants-in-one-process`. Section S records both versions.

**Three jobs, and how their output is split here.** 5.1, 5.2 and 5.3 ran as ONE job; its output is
split below at the job's own `=====` markers, and the job header (`Completed` and the two tell lines)
is quoted once, under 5.1. 5.4 and 5.5 each ran as a separate job later, and each carries its own
complete output including its own header. The runbook's `Invoke-OerConnectCheck` adds a `Seconds`
elapsed time the child block's version does not have; everything else is the same shape.

**The `=====` markers and 5.5's summary object are the operator's own Swedish**, echoed by the runbook,
and are left exactly as the job printed them -- altering recorded output to translate it would be worse
than the four non-ASCII characters they cost (see the redaction notes above). This gloss therefore
names each marker by the check it heads rather than quoting the Swedish back, so that the four stay
four:

- 5.1's marker reads "no tenant named"; 5.2's "tenant B by DOMAIN"; 5.3's "the same tenant by GUID".
- The `EXTRA` marker at the end of 5.3's job reads "user-assigned MI, whether the module takes a
  client id".
- 5.4's marker reads "the ARM half, which section 5 never touched"; 5.5's reads "what does a READ do
  after a session that points at the wrong tenant?".
- In 5.5's summary object, whose field names the harness already spelled without accents:
  `SessionSager` is "the session says", `TokenFranTenant` "the token came from tenant",
  `LasningKastade` "the read threw", `Felmeddelande` "error message", `AntalFelposter` "number of
  error records", `AntalGrupper` "number of groups" and `ForstaTreNamn` "first three names".

- [x] **5.1 RECORD -- a first managed identity sign-in that names no tenant.**

  ```powershell
  $R51 = Invoke-OerConnectCheck -Label '5.1' -Parameters $MiParameters
  $R51 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** `SUCCEEDED`, `PreCallWarnings` `0`, `PostCallWarnings` `0`, `SessionTenantId`
  `organizations`.
  **Record:** `TokenTenantId` -- the identity's own tenant (row 05, or row 01/03 if it is A or B).
  **Traces to:** `Initialize-OERAuth.ps1:889` (no previous session), `:891`.
  **Result:** the job header, then the job's own `5.1` marker and what followed it. 5.2 and 5.3 come
  from this same job and this same output; their slices are quoted under their own boxes.
  ```powershell
Completed
Omnicit.EntraRBAC 1.0.0 from C:\usr\src\PSModules\Omnicit.EntraRBAC\1.0.0
AzAuth 2.10.0

===== 5.1 ingen tenant namngiven =====
Label              : 5.1
Seconds            : 1.8
Outcome            : SUCCEEDED
ErrorId            :
ErrorMessage       :
PreCallWarnings    : 0
PostCallWarnings   : 0
OtherWarnings      : {}
Warnings           :
InformationRecords : 0
SessionTenantId     : organizations
SessionAuthMethod   : ManagedIdentity
TokenTenantId       : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId    :
LastIssuedTenantId  : organizations
LastIssuedTokenId   : 00000000-0000-0000-0000-000000000001
LastRequestMethod   : ManagedIdentity
LastRequestClientId :
LastRequestTenantId : organizations
  ```

  **The identity lives in tenant A**, so placeholder row 05 is NOT ALLOCATED -- it takes row 01, under
  this file's own rule that the same identifier always gets the same placeholder. Tenant B is therefore
  not the identity's own tenant, and 5.2 and 5.3 ran exactly as written, with no substitution.

- [x] **5.2 RECORD -- another tenant, named by DOMAIN.**

  ```powershell
  $P52 = $MiParameters.Clone()
  $P52.TenantId = $TenantBDomain
  $R52 = Invoke-OerConnectCheck -Label '5.2' -Parameters $P52
  $R52 | Format-List
  Get-OerSwitchEvidence | Format-List
  ```

  **Record:** `Outcome`, `TokenTenantId`.
  **Expect, IF `SUCCEEDED` with `TokenTenantId` equal to 5.1's:** `PostCallWarnings` `1`, naming
  `'organizations'` as the previous session's label. Otherwise `PostCallWarnings` `0` and `- [~]`.
  **Traces to:** `Initialize-OERAuth.ps1:888-910`. MEASURED (ManagedIdentity row): the IMDS request is
  byte-identical whatever tenant is named. INFERRED, hence the condition: the token is issued by the
  identity's own tenant.
  **Result:** 5.1's job, continued at its `5.2` marker. The warning appears twice, as the job printed
  it: once on the warning stream as it fired, once inside the helper's `Warnings` field.
  ```powershell
===== 5.2 tenant B med DOMÄN =====
The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named 'organizations'. If 'tenant-b.example.com' is a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-b.example.com'. AzAuth does not send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
Label              : 5.2
Seconds            : 0.2
Outcome            : SUCCEEDED
ErrorId            :
ErrorMessage       :
PreCallWarnings    : 0
PostCallWarnings   : 1
OtherWarnings      : {}
Warnings           : The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant
                     '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous
                     session, which named 'organizations'. If 'tenant-b.example.com' is a name of tenant
                     '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch
                     tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while
                     reporting 'tenant-b.example.com'. AzAuth does not send the named tenant with a new device code
                     sign-in or with a managed identity request, so those tokens normally come from the signed-in
                     account's or the identity's own tenant, and a client secret sign-in for the same application needs
                     Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and
                     Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
InformationRecords : 0
SessionTenantId     : tenant-b.example.com
SessionAuthMethod   : ManagedIdentity
TokenTenantId       : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId    :
LastIssuedTenantId  : tenant-b.example.com
LastIssuedTokenId   : 00000000-0000-0000-0000-000000000001
LastRequestMethod   : ManagedIdentity
LastRequestClientId :
LastRequestTenantId : organizations
  ```

  Its condition HELD -- `TokenTenantId` equal to 5.1's -- so this is a genuine `- [x]`, not a
  `- [~]`: the warning was given the input it tests, and fired on it. The text the run printed here
  is word for word the one 1.5, 1.7, 2.7b and 3.5 printed, on a credential type none of those four
  used.

- [x] **5.3 RECORD -- the same tenant, named by GUID.**

  ```powershell
  $P53 = $MiParameters.Clone()
  $P53.TenantId = $TenantBId
  $R53 = Invoke-OerConnectCheck -Label '5.3' -Parameters $P53
  $R53 | Format-List
  Get-OerSwitchEvidence | Format-List
  Disconnect-OER
  exit
  ```

  **Record:** `Outcome`, `ErrorId`.
  **Expect, IF 5.2's `TokenTenantId` was the identity's own tenant and section 4 found
  `TenantIdProperty` equal to `TidClaim`:** `FAILED` with `ErrorId` `TenantMismatch,Initialize-OERAuth`,
  naming the identity's tenant as the issuer, and `PostCallWarnings` `0`.
  **Traces to:** `Initialize-OERAuth.ps1:756-770`; `:892` excludes a GUID request from the post-call
  warning.
  **Result:** the tail of 5.1's job, from its `5.3` marker to the end -- including the job's own
  `EXTRA` marker, which is read under the box.
  ```powershell
===== 5.3 samma tenant med GUID =====
Label              : 5.3
Seconds            : 0.1
Outcome            : FAILED
ErrorId            : TenantMismatch,Initialize-OERAuth
ErrorMessage       : The Microsoft Graph token was issued for tenant '00000000-0000-0000-0000-000000000001', not for
                     the requested tenant '00000000-0000-0000-0000-000000000003'. Omnicit.EntraRBAC refuses a session
                     whose cached tenant does not describe the token beneath it: every later call would act on
                     '00000000-0000-0000-0000-000000000001' while reporting '00000000-0000-0000-0000-000000000003'.
                     Sign in again with an account that belongs to '00000000-0000-0000-0000-000000000003'.
PreCallWarnings    : 0
PostCallWarnings   : 0
OtherWarnings      : {}
Warnings           :
InformationRecords : 0
SessionTenantId     : tenant-b.example.com
SessionAuthMethod   : ManagedIdentity
TokenTenantId       : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId    :
LastIssuedTenantId  : tenant-b.example.com
LastIssuedTokenId   : 00000000-0000-0000-0000-000000000001
LastRequestMethod   : ManagedIdentity
LastRequestClientId :
LastRequestTenantId : organizations

===== EXTRA: user-assigned MI, om modulen tar en client id =====
UamiClientId satt: True
  ```

  BOTH of its conditions held -- 5.2's `TokenTenantId` was the identity's own tenant, and section 4
  found `TenantIdProperty` equal to `TidClaim` -- so this is a genuine `- [x]` too.

  **Read the evidence block under it carefully: it is 5.2's session, not 5.3's.** `SessionTenantId`
  still reads `tenant-b.example.com` and `TokenTenantId` still reads row 01 -- 5.2's values, unchanged.
  That is the refusal working as designed, not a leftover: the `TenantMismatch` guard terminates ABOVE
  the state rebuild and above the session record, so a refused sign-in leaves the previous session
  exactly where it was and writes nothing of its own. 2.2 shows the same shape on the client secret
  path, where a refused switch left `SessionTenantId` and `TokenTenantId` on the previous tenant.
  (2.7c is the one refusal in this file whose evidence block comes back empty instead, and only
  because `Disconnect-OER` had run immediately before it.)

  **What 5.2 and 5.3 prove together, and it is the contrast this branch was designed to produce:**
  name the tenant by DOMAIN and you get a warning plus a session that points somewhere the token does
  not; name the SAME tenant by GUID and you get a refusal. Measured live, on a managed identity.

  **The job's `EXTRA` marker** asked whether this module accepts a client id for a USER-ASSIGNED
  managed identity, and answered `UamiClientId satt: True` -- "set: True". Nothing follows it in the
  job output, so no user-assigned sign-in was actually made: what is measured is that the parameter is
  there to set, not what a user-assigned identity then does. See 5.5's closing note.

- [x] **5.4 RECORD -- the ARM half: `-IncludeARM` across the same failed switch.**

  Written after the run and executed as its own runbook, in a FRESH job, so none of 5.1-5.3's state was
  in scope -- which is why this block carries its own `Completed` and tell lines. The post-call
  warning reads only the GRAPH token; this is the only check in this file that looks at the ARM one
  beside it.

  ```powershell
  Invoke-OerConnectCheck -Label 'B.1' -Parameters @{ ManagedIdentity = $true; IncludeARM = $true }
  Get-OerSwitchEvidence | Format-List
  Invoke-OerConnectCheck -Label 'B.2' -Parameters @{ ManagedIdentity = $true; IncludeARM = $true; TenantId = $TenantBDomain }
  Get-OerSwitchEvidence | Format-List
  ```

  **Expect:** B.1 `SUCCEEDED` with no warnings and `SessionTenantId` `organizations`; B.2 `SUCCEEDED`
  with `PostCallWarnings` `1`, as 5.2.
  **Record:** `ArmTokenTenantId` beside `TokenTenantId` in BOTH evidence blocks. That comparison is the
  whole point of the check.
  **Traces to:** the post-call warning (`Initialize-OERAuth.ps1:888-910`) sits ABOVE the ARM token call
  (`:1025-1026`) and above the write of `ArmTokenTenantId` (`:1078`), so it cannot read the ARM token's
  tenant at all; the ARM `TenantMismatch` twin (`:1052-1067`) is GUID-only, so a request naming a tenant
  by domain reaches neither guard.
  **Result:**
  ```powershell
Completed
Omnicit.EntraRBAC 1.0.0 from C:\usr\src\PSModules\Omnicit.EntraRBAC\1.0.0
AzAuth 2.10.0

===== B. ARM-halvan, som sektion 5 aldrig rörde =====
Label              : B.1
Seconds            : 1
Outcome            : SUCCEEDED
ErrorId            :
ErrorMessage       :
PreCallWarnings    : 0
PostCallWarnings   : 0
OtherWarnings      : {}
Warnings           :
InformationRecords : 0
SessionTenantId     : organizations
SessionAuthMethod   : ManagedIdentity
TokenTenantId       : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId    : 00000000-0000-0000-0000-000000000001
LastIssuedTenantId  : organizations
LastIssuedTokenId   : 00000000-0000-0000-0000-000000000001
LastRequestMethod   : ManagedIdentity
LastRequestClientId :
LastRequestTenantId : organizations
The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named 'organizations'. If 'tenant-b.example.com' is a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-b.example.com'. AzAuth does not send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
Label              : B.2
Seconds            : 0.1
Outcome            : SUCCEEDED
ErrorId            :
ErrorMessage       :
PreCallWarnings    : 0
PostCallWarnings   : 1
OtherWarnings      : {}
Warnings           : The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant
                     '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous
                     session, which named 'organizations'. If 'tenant-b.example.com' is a name of tenant
                     '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch
                     tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while
                     reporting 'tenant-b.example.com'. AzAuth does not send the named tenant with a new device code
                     sign-in or with a managed identity request, so those tokens normally come from the signed-in
                     account's or the identity's own tenant, and a client secret sign-in for the same application needs
                     Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and
                     Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
InformationRecords : 0
SessionTenantId     : tenant-b.example.com
SessionAuthMethod   : ManagedIdentity
TokenTenantId       : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId    : 00000000-0000-0000-0000-000000000001
LastIssuedTenantId  : tenant-b.example.com
LastIssuedTokenId   : 00000000-0000-0000-0000-000000000001
LastRequestMethod   : ManagedIdentity
LastRequestClientId :
LastRequestTenantId : organizations
  ```

  **What it establishes, plainly: the ARM token is in exactly the same wrong state as the Graph token,
  and the warning names only the Graph one.** On B.2 the session reports `tenant-b.example.com` while
  BOTH `TokenTenantId` and `ArmTokenTenantId` read `00000000-0000-0000-0000-000000000001` -- and for a
  module whose job is Azure RBAC, ARM is the half that WRITES role assignments.

  `PostCallWarnings` is `1` and not `2`, and that is correct arithmetic rather than a missed warning:
  there is exactly ONE `Write-Warning`, and it fires BEFORE the ARM token is acquired, so it cannot
  read that token's tenant to warn about it separately. The branch's answer to this finding is in the
  warning's own text, which names Azure Resource Manager alongside Microsoft Graph as AFFECTED while
  claiming no mechanism tying the two tokens together. Read the measurement at its own width: it is
  managed identity, where the Graph and ARM calls share AzAuth's credential. On the delegated types the
  ARM acquisition passes no client id and is a separate sign-in whose tenant this check never observes.
  Both halves of that are recorded under "The ARM half" in
  `docs/development/rationale.md#switching-tenants-in-one-process`.

- [x] **5.5 RECORD -- does a read after 5.2's state really act on the old tenant?**

  Written after the run and executed as its own runbook, in a FRESH job. This is the check that would
  prove the post-call warning's own consequence sentence, which opens "every call in this session acts
  on '<granted>' while reporting '<named>'" and goes on to name Azure Resource Manager calls, including
  the ones that write role assignments, alongside Microsoft Graph ones -- and which until this run had
  shipped unmeasured.

  ```powershell
  # Its own job, so it first re-creates 5.2's state: a sign-in of 5.1's shape (labelled A-setup-1),
  # then one of 5.2's (A-setup-2), which reproduced 5.2's warning word for word. Then, with the
  # session naming tenant B and the token issued by tenant A:
  $Groups = $null
  $FailA = $( try { $Groups = Get-OERGroup -All -ErrorAction Stop } catch { $_.Exception.Message } )
  ```

  **Record:** whether the read succeeded, the error if it did not, and how many objects came back.
  **Traces to:** the consequence sentence of the post-call warning's own message
  (`Initialize-OERAuth.ps1:897-909`).
  **Result:** the summary object at the end is the harness's own, with Swedish field names -- glossed at
  the head of this section.
  ```powershell
Completed
Omnicit.EntraRBAC 1.0.0 from C:\usr\src\PSModules\Omnicit.EntraRBAC\1.0.0
AzAuth 2.10.0

===== A. Vad gör en LÄSNING efter en session som pekar fel? =====
Label     Outcome   PostCallWarnings
-----     -------   ----------------
A-setup-1 SUCCEEDED                0
The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant '00000000-0000-0000-0000-000000000001', the same tenant that issued the token for the previous session, which named 'organizations'. If 'tenant-b.example.com' is a name of tenant '00000000-0000-0000-0000-000000000001', this is expected. Otherwise this sign-in did not switch tenants, and every call in this session acts on '00000000-0000-0000-0000-000000000001' while reporting 'tenant-b.example.com'. AzAuth does not send the named tenant with a new device code sign-in or with a managed identity request, so those tokens normally come from the signed-in account's or the identity's own tenant, and a client secret sign-in for the same application needs Connect-OER -Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.
A-setup-2 SUCCEEDED                1
SessionTenantId     : tenant-b.example.com
SessionAuthMethod   : ManagedIdentity
TokenTenantId       : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId    :
LastIssuedTenantId  : tenant-b.example.com
LastIssuedTokenId   : 00000000-0000-0000-0000-000000000001
LastRequestMethod   : ManagedIdentity
LastRequestClientId :
LastRequestTenantId : organizations
SessionSager    : tenant-b.example.com
TokenFranTenant : 00000000-0000-0000-0000-000000000001
LasningKastade  : True
Felmeddelande   : Authorization_RequestDenied: Insufficient privileges to complete the operation.
AntalFelposter  : 13
AntalGrupper    : 0
ForstaTreNamn   :
  ```

  **Why the FIRST attempt scored `- [~]`.** The read failed on PERMISSION, not on tenant
  (`AntalGrupper` `0`, `LasningKastade` `True`,
  `Authorization_RequestDenied: Insufficient privileges to complete the operation.`), so it never
  measured where the request went -- it EXECUTED cleanly and still proves nothing about the question
  the check exists for. There is a weak indication, and it is labelled as one:
  `Authorization_RequestDenied` is Graph saying it RECOGNISES the identity, which presupposes a tenant
  the identity exists in, and the identity exists only in tenant A. That is an INFERENCE, not a
  measurement, and this project does not book inferences as facts.

  What the block DOES establish beyond doubt is the state the read ran in: `SessionSager`
  `tenant-b.example.com` beside `TokenFranTenant` `00000000-0000-0000-0000-000000000001`. The
  session named one tenant while its token came from another, which is the warning's premise, measured.
  Only the consequence is unmeasured.

  **The re-run that would settle it.** Claude writes the check and the operator runs it, per SECURITY
  rule 1. Four prerequisites, each of which the first attempt lacked:

  - grant **`Directory.Read.All`** rather than `Group.Read.All` -- a superset of whatever
    `Get-OERGroup -All` touches, so a second permission refusal cannot be the answer again;
  - verify the grant has PROPAGATED before running;
  - confirm the app role sits on the **system-assigned** identity, not on a user-assigned one;
  - run it in a **NEW job**, so the managed identity token is minted fresh: a token already issued does
    not carry a role granted afterwards.

  ```powershell
  $Error.Clear()
  $Groups = $null
  $FailA = $( try { $Groups = Get-OERGroup -All -ErrorAction Stop } catch { $_.Exception.Message } )
  $ErrorRecordsFromThisCall = $Error.Count
  ```

  **RE-RUN RESULT, 2026-09-17. The read SUCCEEDED and returned 89 objects.** All four prerequisites
  above were met, the app role was granted, and the job was fresh.

  ```powershell
  $Groups = $null
  $FailA = $( try { $Groups = Get-OERGroup -All -ErrorAction Stop } catch { $_.Exception.Message } )
  $Groups.count
  89
  ```

  **This settles the consequence sentence, and it settles it as TRUE.** The managed identity exists in
  tenant A and nowhere else, so a read that returns 89 objects can only have been answered by tenant A.
  The session naming tenant B was measured in the first attempt and reproduced here by the same
  `A-setup-1` / `A-setup-2` pair. Therefore: a call in such a session really does act on the granted
  tenant while reporting the named one, exactly as the post-call warning's message says. **The sentence
  that ships to the public gallery is now measured rather than reasoned.**

  **One question the re-run did NOT close.** `$ErrorRecordsFromThisCall` was folded into the block to
  settle the `AntalFelposter` `13` question at no extra cost, but the operator's report captured only
  `$Groups.count`. The read succeeded, so that counter would have printed `0` and proved nothing about
  a FAILED read either way. The mocked reproduction below stands as the answer; the live confirmation
  is still outstanding, and is cheap to take the next time a failing read is in front of someone.

  **Why the `$Error.Clear()` is in that block.** The original harness never cleared `$Error`, so its
  `AntalFelposter` `13` counted every record the job had accumulated, not the ones this call
  produced. A mocked reproduction measured EXACTLY ONE record per failed `Get-OERGroup -All`, ten
  consecutive times, across five transport exception shapes, and confirmed the paging loop STOPS at the
  first failed page (five good pages then a 403 on page six made exactly six transport calls). If the
  cleared count prints `1`, there is nothing to fix. The re-run was expected to settle that at no
  extra cost and did not, for the reason recorded above: its read SUCCEEDED, so the counter never saw
  a failed one.

  **A caution for the next checklist author, from that same measurement.** `-ErrorVariable` sees **22**
  records for that one failed read -- two distinct exceptions republished per module frame -- and it
  scales per item: **220** for ten failing groups, against `10` in `$Error`. **Count `$Error`, not
  `-ErrorVariable`.** This file's own helper could have fallen into exactly that.

  **A gap in the run, not a limitation of the module.** `Connect-OER` DOES accept a client id for a
  USER-ASSIGNED managed identity (`-ManagedIdentity` together with `-ClientId`), which 5.3's job
  confirmed from the outside with its `UamiClientId satt: True` line and which is measurable from
  `(Get-Command Connect-OER).Parameters` and the parameter's own help. The user-assigned identity is
  therefore testable, and its absence from this run is a gap in the run.

---

## 6. `-WarningAction Stop` stops the sign-in at either warning

Both warnings are documented to stop the sign-in under `-WarningAction Stop`: the post-call warning
before `Connect-MgGraph` and before the session is rebuilt, the pre-call warning before any token is
requested. **A check here FAILS when the warning fires and the sign-in carries on** -- that is the
regression this section exists for, and it must never be written up as `- [~]`. The public observation
is the Graph SDK's own context, read before and after; the module-scope evidence is the supplement.

That a `-WarningAction Stop` given to `Connect-OER` reaches a `Write-Warning` inside the private
function, stops there with an `ActionPreferenceStopException`, still fills `-WarningVariable`, and
leaves a nested `-WarningAction Continue` call unaffected is PowerShell's own behaviour. It was checked
offline with stand-in functions of the same shape while this file was written -- not with this module.

- [~] **6.1 The post-call warning: tenant A, `Disconnect-OER`, tenant B by domain under
  `-WarningAction Stop`.**

  3.3's shape. **Start a NEW child process** and paste the child block. Sign in as
  `person1@example.com`.

  ```powershell
  $R61a = Invoke-OerConnectCheck -Label '6.1a' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; IncludeARM = $true }
  $R61a | Format-List
  Disconnect-OER

  $PostCallPhrase = 'the same tenant that issued the token for the previous session'
  $MgBefore       = Get-MgContext
  $EvidenceBefore = Get-OerSwitchEvidence
  $StopWarn = $null
  $StopInfo = $null
  $Stop = $(
      try {
          Connect-OER -TenantId $TenantBDomain -DeviceCode -WarningAction Stop -WarningVariable StopWarn -InformationVariable StopInfo
          'NO STOP'
      } catch {
          $_
      }
  )
  $MgAfter       = Get-MgContext
  $EvidenceAfter = Get-OerSwitchEvidence

  $StopRecord = @($Stop | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })[0]
  $StopTexts  = if ($null -eq $StopWarn) { @() } else { @($StopWarn | ForEach-Object { [string]$_.Message }) }
  [pscustomobject]@{
      Result                   = if (-not $StopRecord) { 'NO STOP' } elseif ($StopRecord.Exception -is [System.Management.Automation.ActionPreferenceStopException]) { 'STOPPED AT A WARNING' } else { 'OTHER ERROR' }
      ErrorId                  = if ($StopRecord) { $StopRecord.FullyQualifiedErrorId } else { '' }
      StoppedOnPostCallWarning = if ($StopRecord) { $StopRecord.Exception.Message.Contains($PostCallPhrase) } else { $false }
      Message                  = if ($StopRecord) { $StopRecord.Exception.Message } else { '' }
      PostCallWarnings         = @($StopTexts | Where-Object { $_.Contains($PostCallPhrase) }).Count
      OtherWarnings            = @($StopTexts | Where-Object { -not $_.Contains($PostCallPhrase) })
      InformationRecords       = if ($null -eq $StopInfo) { 0 } else { $StopInfo.Count }
      MgContextPresentBefore   = $null -ne $MgBefore
      MgContextPresentAfter    = $null -ne $MgAfter
      MgTenantUnchanged        = [string]$MgBefore.TenantId -eq [string]$MgAfter.TenantId
      SessionTokenIsPrevious   = [string]$EvidenceAfter.TokenTenantId -eq [string]$EvidenceBefore.LastIssuedTokenId
  } | Format-List
  $EvidenceBefore | Format-List
  $EvidenceAfter | Format-List
  ```

  **Expect:** 6.1a `SUCCEEDED` with `PostCallWarnings` `0`. The device-code instruction for the tenant B
  attempt IS printed and can be completed: `-WarningAction Stop` does not stop it.
  **Record:** device codes completed, `Result`, `ErrorId`, and anything in `OtherWarnings`.

  **Then read `Result`:**

  - **`STOPPED AT A WARNING` with `StoppedOnPostCallWarning` `True` -- Expect:**
    - `Message` beginning `The running command stopped because the preference variable
      "WarningPreference" or common parameter is set to Stop:` and naming the tenant B domain and tenant
      A's id; `PostCallWarnings` `1`.
    - `MgContextPresentAfter` equal to `MgContextPresentBefore`, and `MgTenantUnchanged` `True`: the
      module never called `Connect-MgGraph` for tenant B.
    - `$EvidenceAfter`: `SessionTenantId` and `TokenTenantId` empty; `LastIssuedTenantId` and
      `LastIssuedTokenId` IDENTICAL to `$EvidenceBefore` (tenant A's id twice); and
      `LastRequestTenantId` still tenant A's id, identical to `$EvidenceBefore`.
  - **`STOPPED AT A WARNING` with `StoppedOnPostCallWarning` `False`:** the stop came from some other
    warning. Record it from `Message`, then read `PostCallWarnings`:
    - `1` or more: this branch's warning fired, did not stop the sign-in, and a later warning did.
      **The box FAILS** -- leave it `- [ ]`, write `FAILED`, and carry it to S as a defect;
    - only `PostCallWarnings` `0` -- the stop came before this branch's warning was reached -- is
      `- [~]`.
  - **`NO STOP`: run `Disconnect-OER` at once** -- a session for the tenant B domain now exists. Then:
    - if `PostCallWarnings` is `1` or more, **or** `SessionTokenIsPrevious` is `True`, **the box FAILS**:
      either the warning fired and did not stop the sign-in, or the token came from tenant A and the
      warning did not fire at all. Leave it `- [ ]`, write `FAILED` and which of the two, and carry it to
      S as a defect;
    - only `PostCallWarnings` `0` with `SessionTokenIsPrevious` `False` -- the token came from some
      tenant other than A, so there was nothing to warn about -- is `- [~]`. Record `TokenTenantId`.
  - **`OTHER ERROR`:** record `ErrorId` and the first sentence of `Message`, then read `PostCallWarnings`:
    - `1` or more: this branch's warning fired, did not stop the sign-in, and the error came after it --
      from `Connect-MgGraph`, say, which sits below the warning. **The box FAILS** -- leave it `- [ ]`,
      write `FAILED`, and carry it to S as a defect;
    - only `PostCallWarnings` `0` -- no token reached the warning (a failed or cancelled sign-in) -- is
      `- [~]`.

  **Traces to:** the post-call `Write-Warning` (`Initialize-OERAuth.ps1:897`) sits in a `try`/`finally`
  (`:526`, `:1083`) with no `catch` between it and the caller, and `Connect-OER.ps1:290` calls
  `Initialize-OERAuth` with no `try`; `Connect-MgGraph` has one call site in the module (`:948`), below
  the warning, as are the state rebuild (`:964`) and the session record write (`:1013`); the request
  record does not move (`:655-658` all false: a device-code sign-in with no `-ClientId` records an empty
  client id both times, the same credential type, and no `Force`); the device-code token call passes
  `-WarningAction Continue` explicitly (`:497`); `Disconnect-OER.ps1:21-22`.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $R61a = Invoke-OerConnectCheck -Label '6.1a' -Parameters @{ TenantId = $TenantAId; DeviceCode = $true; IncludeARM = $true }
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $R61a | Format-List

Label : 6.1a
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 2

PS C:\Git\Omnicit.EntraRBAC> Disconnect-OER
PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> $PostCallPhrase = 'the same tenant that issued the token for the previous session'
PS C:\Git\Omnicit.EntraRBAC> $MgBefore = Get-MgContext
PS C:\Git\Omnicit.EntraRBAC> $EvidenceBefore = Get-OerSwitchEvidence
PS C:\Git\Omnicit.EntraRBAC> $StopWarn = $null
PS C:\Git\Omnicit.EntraRBAC> $StopInfo = $null
PS C:\Git\Omnicit.EntraRBAC> $Stop = $(
>> try {
>> Connect-OER -TenantId $TenantBDomain -DeviceCode -WarningAction Stop -WarningVariable StopWarn -InformationVariable StopInfo
>> 'NO STOP'
>> } catch {
>> $_
>> }
>> )
To sign in, use a web browser to open the page https://login.microsoft.com/device and enter the code ABCD12345 to authenticate.
PS C:\Git\Omnicit.EntraRBAC> $MgAfter = Get-MgContext
PS C:\Git\Omnicit.EntraRBAC> $EvidenceAfter = Get-OerSwitchEvidence
PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> $StopRecord = @($Stop | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })[0]
PS C:\Git\Omnicit.EntraRBAC> $StopTexts = if ($null -eq $StopWarn) { @() } else { @($StopWarn | ForEach-Object { [string]$_.Message }) }
PS C:\Git\Omnicit.EntraRBAC> [pscustomobject]@{
>> Result = if (-not $StopRecord) { 'NO STOP' } elseif ($StopRecord.Exception -is [System.Management.Automation.ActionPreferenceStopException]) { 'STOPPED AT A WARNING' } else { 'OTHER ERROR' }
>> ErrorId = if ($StopRecord) { $StopRecord.FullyQualifiedErrorId } else { '' }
>> StoppedOnPostCallWarning = if ($StopRecord) { $StopRecord.Exception.Message.Contains($PostCallPhrase) } else { $false }
>> Message = if ($StopRecord) { $StopRecord.Exception.Message } else { '' }
>> PostCallWarnings = @($StopTexts | Where-Object { $_.Contains($PostCallPhrase) }).Count
>> OtherWarnings = @($StopTexts | Where-Object { -not $_.Contains($PostCallPhrase) })
>> InformationRecords = if ($null -eq $StopInfo) { 0 } else { $StopInfo.Count }
>> MgContextPresentBefore = $null -ne $MgBefore
>> MgContextPresentAfter = $null -ne $MgAfter
>> MgTenantUnchanged = [string]$MgBefore.TenantId -eq [string]$MgAfter.TenantId
>> SessionTokenIsPrevious = [string]$EvidenceAfter.TokenTenantId -eq [string]$EvidenceBefore.LastIssuedTokenId
>> } | Format-List

Result : NO STOP
ErrorId :
StoppedOnPostCallWarning : False
Message :
PostCallWarnings : 0
OtherWarnings : {}
InformationRecords : 1
MgContextPresentBefore : False
MgContextPresentAfter : True
MgTenantUnchanged : False
SessionTokenIsPrevious : False

PS C:\Git\Omnicit.EntraRBAC> $EvidenceBefore | Format-List

SessionTenantId :
SessionAuthMethod :
TokenTenantId :
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC> $EvidenceAfter | Format-List

SessionTenantId : tenant-b.example.com
SessionAuthMethod : DeviceCode
TokenTenantId : 00000000-0000-0000-0000-000000000003
ArmTokenTenantId :
LastIssuedTenantId : tenant-b.example.com
LastIssuedTokenId : 00000000-0000-0000-0000-000000000003
LastRequestMethod : DeviceCode
LastRequestClientId :
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC>
  ```

  **Scoring: `- [~]`, by this check's own `NO STOP` branch.** `Result` was `NO STOP` with
  `PostCallWarnings` `0` and `SessionTokenIsPrevious` `False` -- the combination that branch scores
  exactly `- [~]`: the token came from a tenant other than A, so there was nothing to warn about and
  nothing for `-WarningAction Stop` to stop. `TokenTenantId` was
  `00000000-0000-0000-0000-000000000003`, and `Disconnect-OER` was run at once as that branch requires.
  **It is NOT a FAILED box.** Both FAILED conditions of the `NO STOP` branch require `PostCallWarnings`
  `1` or more, or `SessionTokenIsPrevious` `True`, and neither held. What stays unproven LIVE is the
  post-call warning's `-WarningAction Stop` PLACEMENT; unit test Q10 proves and mutation-proves that
  instead.

  Then `Disconnect-OER` and `exit` back to the launcher.

- [x] **6.2 The pre-call warning: client secret tenant A, then tenant B without `-Force` under
  `-WarningAction Stop`.**

  Needs section 2's app registration; without it, "cannot be verified, and therefore we do not know"
  and why. **Start a NEW child process** and paste the child block, then:

  ```powershell
  $Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString
  $R62a = Invoke-OerConnectCheck -Label '6.2a' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
  $R62a | Format-List

  $PreCallPhrase  = 'but the credential AzAuth holds for that application'
  $MgBefore       = Get-MgContext
  $EvidenceBefore = Get-OerSwitchEvidence
  $StopWarn = $null
  $Stop = $(
      try {
          Connect-OER -TenantId $TenantBId -ClientId $AppId -ClientSecret $Secret -WarningAction Stop -WarningVariable StopWarn
          'NO STOP'
      } catch {
          $_
      }
  )
  $MgAfter       = Get-MgContext
  $EvidenceAfter = Get-OerSwitchEvidence

  $StopRecord = @($Stop | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })[0]
  $StopTexts  = if ($null -eq $StopWarn) { @() } else { @($StopWarn | ForEach-Object { [string]$_.Message }) }
  [pscustomobject]@{
      Result                  = if (-not $StopRecord) { 'NO STOP' } elseif ($StopRecord.Exception -is [System.Management.Automation.ActionPreferenceStopException]) { 'STOPPED AT A WARNING' } else { 'OTHER ERROR' }
      ErrorId                 = if ($StopRecord) { $StopRecord.FullyQualifiedErrorId } else { '' }
      StoppedOnPreCallWarning = if ($StopRecord) { $StopRecord.Exception.Message.Contains($PreCallPhrase) } else { $false }
      ReachedTheTokenCall     = if ($StopRecord) { $StopRecord.Exception.Message.Contains('Failed to acquire a Microsoft Graph token') } else { $true }
      Message                 = if ($StopRecord) { $StopRecord.Exception.Message } else { '' }
      PreCallWarnings         = @($StopTexts | Where-Object { $_.Contains($PreCallPhrase) }).Count
      OtherWarnings           = @($StopTexts | Where-Object { -not $_.Contains($PreCallPhrase) })
      MgContextPresentBefore  = $null -ne $MgBefore
      MgContextPresentAfter   = $null -ne $MgAfter
      MgTenantUnchanged       = [string]$MgBefore.TenantId -eq [string]$MgAfter.TenantId
  } | Format-List
  $EvidenceBefore | Format-List
  $EvidenceAfter | Format-List
  ```

  **Expect:** 6.2a `SUCCEEDED` with `PreCallWarnings` `0`. Then `Result` `STOPPED AT A WARNING`,
  `StoppedOnPreCallWarning` `True`, `ReachedTheTokenCall` `False` -- no `GraphTokenAcquisitionFailed`, no
  refusal text, since no token was ever requested -- `PreCallWarnings` `1`, `MgTenantUnchanged` `True`,
  and `$EvidenceAfter` identical to `$EvidenceBefore` in every field: the session still tenant A's, and
  `LastRequestTenantId` still tenant A's id.
  **The record being unchanged does not by itself prove the stop**: the record rule would not move it for
  this call either (`:655-658` all false). `ReachedTheTokenCall` `False` is the discriminating
  observation.
  **Any other outcome FAILS**, with one exception, and that exception is itself conditional:
  `STOPPED AT A WARNING` with `StoppedOnPreCallWarning` `False` is a stop on some OTHER warning --
  record it from `Message`, then read `PreCallWarnings`:
  - `0` -- this branch's warning was never reached, and the stop came before it -- is `- [~]`;
  - `1` or more: this branch's warning FIRED, did not stop the sign-in, and something else did.
    **The box FAILS** -- leave it `- [ ]`, write `FAILED`, and carry it to S as a defect.

  **That `PreCallWarnings` rule belongs to THAT branch alone.** 6.2's own expected outcome above
  REQUIRES `PreCallWarnings` `1`, so a blanket "fail 6.2 whenever `PreCallWarnings` is 1 or more"
  would fail the check on a clean pass -- and a paraphrase saying exactly that was in circulation
  during this run.

  `OTHER ERROR` with `ReachedTheTokenCall` `True` means the warning did not stop the call before
  `Get-AzToken`; `NO STOP` means neither a stop nor the measured refusal happened (run
  `Disconnect-OER` at once, and record `TokenTenantId`, which also bears on 2.2's premise). Leave a
  failed box `- [ ]`, write `FAILED`, and carry it to S.
  **Traces to:** the pre-call `Write-Warning` (`Initialize-OERAuth.ps1:610`) sits inside the `try`
  (`:526`) whose only handler is the `finally` (`:1083`), ABOVE the record update (`:655-661`), the
  authority record (`:673`) and the Graph token call (`:705-706`), whose `catch` (`:707-720`) is where a
  refusal would surface as `GraphTokenAcquisitionFailed`; `Connect-OER.ps1:290` has no `try`.
  **Result:**
  ```powershell
PS C:\Git\Omnicit.EntraRBAC> $Secret = Read-Host -Prompt 'Client secret of that app registration' -AsSecureString
Client secret of that app registration: ****************************************
PS C:\Git\Omnicit.EntraRBAC> $R62a = Invoke-OerConnectCheck -Label '6.2a' -Parameters @{ TenantId = $TenantAId; ClientId = $AppId; ClientSecret = $Secret }
PS C:\Git\Omnicit.EntraRBAC> $R62a | Format-List

Label : 6.2a
Outcome : SUCCEEDED
ErrorId :
ErrorMessage :
PreCallWarnings : 0
PostCallWarnings : 0
OtherWarnings : {}
Warnings :
InformationRecords : 0

PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> $PreCallPhrase = 'but the credential AzAuth holds for that application'
PS C:\Git\Omnicit.EntraRBAC> $MgBefore = Get-MgContext
PS C:\Git\Omnicit.EntraRBAC> $EvidenceBefore = Get-OerSwitchEvidence
PS C:\Git\Omnicit.EntraRBAC> $StopWarn = $null
PS C:\Git\Omnicit.EntraRBAC> $Stop = $(
>> try {
>> Connect-OER -TenantId $TenantBId -ClientId $AppId -ClientSecret $Secret -WarningAction Stop -WarningVariable StopWarn
>> 'NO STOP'
>> } catch {
>> $_
>> }
>> )
WARNING: This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not configured to acquire tokens for tenant',
and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild the credential for '00000000-0000-0000-0000-000000000003'
. Disconnect-OER does not clear it.
PS C:\Git\Omnicit.EntraRBAC> $MgAfter = Get-MgContext
PS C:\Git\Omnicit.EntraRBAC> $EvidenceAfter = Get-OerSwitchEvidence
PS C:\Git\Omnicit.EntraRBAC>
PS C:\Git\Omnicit.EntraRBAC> $StopRecord = @($Stop | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })[0]
PS C:\Git\Omnicit.EntraRBAC> $StopTexts = if ($null -eq $StopWarn) { @() } else { @($StopWarn | ForEach-Object { [string]$_.Message }) }
PS C:\Git\Omnicit.EntraRBAC> [pscustomobject]@{
>> Result = if (-not $StopRecord) { 'NO STOP' } elseif ($StopRecord.Exception -is [System.Management.Automation.ActionPreferenceStopException]) { 'STOPPED AT A WARNING' } else { 'OTHER ERROR' }
>> ErrorId = if ($StopRecord) { $StopRecord.FullyQualifiedErrorId } else { '' }
>> StoppedOnPreCallWarning = if ($StopRecord) { $StopRecord.Exception.Message.Contains($PreCallPhrase) } else { $false }
>> ReachedTheTokenCall = if ($StopRecord) { $StopRecord.Exception.Message.Contains('Failed to acquire a Microsoft Graph token') } else { $true }
>> Message = if ($StopRecord) { $StopRecord.Exception.Message } else { '' }
>> PreCallWarnings = @($StopTexts | Where-Object { $_.Contains($PreCallPhrase) }).Count
>> OtherWarnings = @($StopTexts | Where-Object { -not $_.Contains($PreCallPhrase) })
>> MgContextPresentBefore = $null -ne $MgBefore
>> MgContextPresentAfter = $null -ne $MgAfter
>> MgTenantUnchanged = [string]$MgBefore.TenantId -eq [string]$MgAfter.TenantId
>> } | Format-List

Result : STOPPED AT A WARNING
ErrorId : ActionPreferenceStop,Microsoft.PowerShell.Commands.WriteWarningCommand
StoppedOnPreCallWarning : True
ReachedTheTokenCall : False
Message : The running command stopped because the preference variable "WarningPreference" or common parameter is set to Stop: This client secret sign-in for application '00000000-0000-0000-0000-000000000002' names tenant '00000000-0000-0000-0000-000000000003', but the credential AzAuth holds for that application in this PowerShell session was built for tenant '00000000-0000-0000-0000-000000000001'. AzAuth reuses that credential for the same application until it is told to rebuild it, so this
sign-in does not reach '00000000-0000-0000-0000-000000000003': by default it fails with 'The current credential is not configured to acquire tokens for tenant', and where multi-tenant authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITE
NANTAUTH) the token is requested from '00000000-0000-0000-0000-000000000001' instead. Run Connect-OER again with -Force to rebuild the credential for '00000000-0000-0000-0000-000000000003'. Disconnect-OER does not clear it.
PreCallWarnings : 1
OtherWarnings : {}
MgContextPresentBefore : True
MgContextPresentAfter : True
MgTenantUnchanged : True

PS C:\Git\Omnicit.EntraRBAC> $EvidenceBefore | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC> $EvidenceAfter | Format-List

SessionTenantId : 00000000-0000-0000-0000-000000000001
SessionAuthMethod : ClientSecret
TokenTenantId : 00000000-0000-0000-0000-000000000001
ArmTokenTenantId :
LastIssuedTenantId : 00000000-0000-0000-0000-000000000001
LastIssuedTokenId : 00000000-0000-0000-0000-000000000001
LastRequestMethod : ClientSecret
LastRequestClientId : 00000000-0000-0000-0000-000000000002
LastRequestTenantId : 00000000-0000-0000-0000-000000000001

PS C:\Git\Omnicit.EntraRBAC>
  ```

  Then `Disconnect-OER` and `exit` back to the launcher.

---

## T. Teardown

- [x] **T.1 Close every process and clear the launcher.**

  In any child still open: `Disconnect-OER`, then `exit`. Exiting is what drops AzAuth's credential --
  `Disconnect-OER` never touches it. Then in the LAUNCHER:

  ```powershell
  Remove-Item Env:OER_LIVE_TENANT_A_ID, Env:OER_LIVE_TENANT_A_DOMAIN, Env:OER_LIVE_TENANT_B_ID, Env:OER_LIVE_TENANT_B_DOMAIN, Env:OER_LIVE_TENANT_C_DOMAIN, Env:OER_LIVE_APP_ID -ErrorAction SilentlyContinue
  @(Get-ChildItem Env: | Where-Object Name -like 'OER_LIVE_*').Count
  Test-Path Env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH
  git -C 'C:\Git\Omnicit.EntraRBAC' status --short
  ```

  **Expect:** `0`, `False`, and `git status` listing this checklist and nothing else. Raw console output,
  if you kept any, lives under `docs/live-verification/raw/` or in a `*.log` here, both git-ignored.
  **Result:**
  ```powershell
Teardown verified 2026-09-17, on the machine the run used. The Remove-Item line was not needed:
nothing was left to remove.

OER_LIVE_* variables present     : 0
Test-Path Env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH : False
Test-Path Env:AZURE_AUTHORITY_HOST                   : False
git status --short               : only this checklist
  ```

  The identifiers were set with `$env:` in the launcher, which is PROCESS scope, so they did not
  outlive it and nothing from them was written to disk by any step in this file -- which is why the
  three checks above measure the cleared state rather than the clearing. What teardown does NOT close
  out is the app registration -- see T.2.

- [x] **T.2 What cannot be undone.**

  - **Nothing in a tenant was created or changed.** No step in this file writes.
  - **The sign-in logs keep every attempt**: tenants A, B and C, the app registration's service
    principal in A and B, and the managed identity's tenant. Checks 3.2-3.7 and 6.1 deliberately
    complete device-code sign-ins while naming tenant B, which the account is not in. 2.2, 2.2b and 2.4
    are refused client secret sign-ins, but the refusal happens on this machine before a request is
    sent (MEASURED), so they may leave no sign-in log entry at all. If Identity Protection or a sign-in
    alert fires for `person1@example.com` or for the app, this is why.
  - **The client secret** was typed at a `Read-Host -AsSecureString` prompt and never written to this
    file, so `README.md`'s rotate-on-leak rule is not triggered. If an error record from 4.3 was ever
    rendered, it held the secret in plain text: rotate it. Otherwise, whether to rotate it, or delete a
    registration made only for this run, is still a decision to record rather than leave implied.

  **Record:**

  ```powershell
  [pscustomobject]@{
      SignInAlertFired      = 'fired / did not fire -- which tenant and which account or app'
      AppSecretDisposal     = 'rotated / deleted with the registration / kept, deliberately / section 2 not run'
      ErrorRecordRendered43 = 'no / yes, and the secret was rotated'
      AzAuthVersionRecorded = 'the version the child block printed'
  } | Format-List
  ```
  **Result:**
  ```powershell
Teardown RUN 2026-09-17.

AppSecretDisposal     : deleted with the registration -- oer-live-tenantswitch removed, which
                        removes its secret and its service principals in both tenants
SignInAlertFired      : not recorded in the operator's report
ErrorRecordRendered43 : not recorded in the operator's report
AzAuthVersionRecorded : see section S
  ```

  **DECIDED AND DONE, 2026-09-17: the registration was deleted.** `oer-live-tenantswitch`, created for
  section 2, no longer exists, which removes its client secret and its service principals in both
  tenants in one operation. The Azure Automation resource group that carried section 5's managed
  identities was deleted with it.

  **The decision was forced rather than chosen.** A client secret value reached the operator's own
  working copy of this checklist in plain text -- not this file, which never held it, and not any
  commit. It was removed from that copy the same day, but a value that has been written to a file also
  lives in that file's edit history and in any sync or backup copy of it, so removal alone does not
  close it. `README.md`'s rotate-on-leak rule applied, and deleting the registration satisfies it more
  completely than rotating would.

  **The carried-forward half.** Sprint 4's `oer-live-apponly` was disposed of in the same round. No
  application object id, no service principal object id and no secret is written here, deliberately.

  `AzAuthVersionRecorded` is answered in section S instead, and separately for the two environments the
  run used.

---

## S. Sign-off

- [x] Every box above carries a written result. A box whose condition did not hold is `- [~]` and says
      which input it lacked (most often: which tenant the token came from). A FAILED box says `FAILED`.
      **Satisfied.** 32 verification checks, every one with a written result: **25 `- [x]`, 7 `- [~]`,
      0 FAILED**. Each `- [~]` box carries a "Scoring" note naming the input it lacked. 5.5 moved from
      `- [~]` to `- [x]` on 2026-09-17, when its re-run returned a successful read.
- [x] Any check that could not be run says so explicitly, with the reason.
      **Satisfied.** 3.6 is the only one: no tenant where the signing-in account is a guest was
      available to the run, so no guest device-code token was ever obtained and placeholder row 04
      stays NOT ALLOCATED.
- [x] Section 4's answer is recorded. If `AzToken.TenantId` turned out to ECHO the requested tenant rather
      than carry `tid`, that has been reported back before merge: every post-call warning `Expect:` in
      this file, and the warning itself, rest on the opposite.
      **Satisfied, and the answer is the one this file needed.** `AzToken.TenantId` carries the token's
      own `tid` claim and does NOT echo the requested tenant: `PropertyEqualsTid` `True` and
      `PropertyEchoesRequest` `False` in 4.1, 4.2 and 4.3a, corroborated a fourth time by 2.7b. There is
      nothing to report back on this one.
- [x] 2.2's refusal and 2.5's outcome are recorded. If 2.2 SUCCEEDED for tenant B, or 2.5 -- the sign-in
      back to the tenant the credential was built for -- was REFUSED, that has been reported back before
      merge as a finding against the pre-call warning's premise or its record rule.
      **Satisfied, and both matched their `Expect:`.** 2.2 was REFUSED
      (`GraphTokenAcquisitionFailed,Initialize-OERAuth`, "not configured to acquire tokens for tenant")
      after a SUCCESSFUL first sign-in -- the case the offline spike could only measure after a FAILED
      one. 2.5 SUCCEEDED, so the record rule holds against the real AzAuth. Neither is a finding.
- [x] Neither 6.1 nor 6.2 FAILED. A failure there means a documented stop does not happen, and has been
      reported back before merge.
      **Satisfied.** 6.2 is a full `- [x]`: `STOPPED AT A WARNING`, `StoppedOnPreCallWarning` `True`,
      `ReachedTheTokenCall` `False`, `PreCallWarnings` `1`. 6.1 is `- [~]` by its own `NO STOP` branch --
      `PostCallWarnings` `0` with `SessionTokenIsPrevious` `False` -- which is the combination that
      branch scores `- [~]`, and which matches neither of its two FAILED conditions.
- [x] The AzAuth version the child block printed is recorded, and if it is not `2.9.0`, that is said here.
      **Recorded, and it is two versions rather than one.** Sections 1-4 and 6 ran on **AzAuth 2.9.0**
      with **PowerShell 7.6.6**. Section 5 ran on **AzAuth 2.10.0** with **PowerShell
      7.6.0-preview.5**, in Azure Automation. The manifest pins AzAuth `2.9.0` as a **MINIMUM**, not an
      exact version, so 2.10.0 is what a user with a newer binary on `PSModulePath` actually gets. The
      IL comparison showing the two AzAuth builds are identical is in
      `docs/development/rationale.md#switching-tenants-in-one-process`.
- [x] Any other defect found has been reported back before merge.
      **Satisfied.** Two were found, and both were answered on this branch before merge: the
      **device-code hang** (written up at the head of section 3, and now a named known issue in the
      release note, the README, the about topic and `Connect-OER`'s help) and the **ARM
      under-reporting** (5.4, answered in the post-call warning's wording, which now names Azure
      Resource Manager as affected). What is left are DEBTS rather than unreported defects, each
      written up where it belongs. ~~5.5's re-run~~ was taken on 2026-09-17 and came back TRUE; ~~T.2's
      app registration decision~~ was taken the same day, by deletion. What remains is the tenant B
      prerequisite behind the five `- [~]` boxes in sections 3 and 6, and the live confirmation of the
      cleared error-record count, which needs a FAILING read in front of someone.

**Section T is cleanup, not a code gate.** Nothing in T bears on whether the code on this branch is
correct, so the boxes above are read against sections 1-6 alone; tick T and this sign-off at the end.

**Verified by:** Philip Haglund  **Date:** 2026-09-17
