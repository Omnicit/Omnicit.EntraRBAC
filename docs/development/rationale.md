# Omnicit.EntraRBAC -- rule rationale

Background for the rules in [CLAUDE.md](../../CLAUDE.md). CLAUDE.md states the rule; this file
carries the history that explains why the rule is worded the way it is.

**Read the relevant anchor before "simplifying" a rule.** Almost every entry below exists because
the obvious simplification was already tried in this repo and silently failed. CLAUDE.md links
here per rule as `Why: docs/development/rationale.md#<anchor>`.

---

## bearer-scrub

`Remove-OERErrorRecord -Record $PSItem` must be the first statement of every catch block that can
see transport. The raw `HttpRequestMessage` stored in `$Error` carries `Authorization: Bearer
<token>` in plain text; failing to remove it leaks the bearer token.

The older `$null = $Error.Remove($PSItem)` idiom looks equivalent but **never actually worked**,
anywhere in this module:

- Inside module code the automatic `$Error` variable resolves to the module's own private list.
  The swallowed record is never in that list, so the removal has nothing to match.
- Even matched against the caller's real `$global:Error` list, the `ErrorRecord` instance bound to
  `$PSItem` inside a `catch` is a *different object* than the one PowerShell appended there, so a
  reference-equality `.Remove($PSItem)` silently no-ops.

Only the record's `.Exception` object is reference-stable across that boundary. That is what
`Remove-OERErrorRecord` matches on, and it is the whole reason the helper exists.

Audit PR8 (#33) found this idiom was inert module-wide, across 23 tracked files -- not a single
site was actually scrubbing. See also SECURITY rule 6 in CLAUDE.md and
[#static-source-gates](#static-source-gates), which machine-checks the rule.

## bearer-scrub-tests

A bearer-scrub regression test needs a different proof depending on how the catch block re-throws.
Picking the wrong one produces a test that passes with the scrub deleted.

**Converted re-throw** -- `Invoke-OERGraphRequest` via `Convert-GraphHttpException`, or
`Invoke-OERArmRequest` via its own `ArmTransportError` conversion or `Convert-ArmHttpException`'s
status-derived, `ArmError`-fallback conversion. Assert against the caller's `$global:Error`,
filtered with `[object]::ReferenceEquals($PSItem.Exception, $OriginalException)`. A module-scoped
`$Error.Count` delta proves nothing -- the module's private `$Error` list never held the record.

**Bare `throw` re-throw** -- a catch block that rethrows the caught `ErrorRecord`/exception
unchanged, e.g. `Enable-OERGroupPermanentEligibility`. Here the `$global:Error` reference-identity
proof is **inert**: the same exception instance is re-appended to `$global:Error` at the next call
boundary regardless of whether the scrub ran. Use `Mock Remove-OERErrorRecord { }` plus
`Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly` instead -- guard the call directly.

**Asserting the cmdlet's own error too** -- match the *cmdlet-qualified* `FullyQualifiedErrorId`
(`'<Code>,<CmdletName>'`), never the bare code. PowerShell auto-records the mock's thrown
`ErrorRecord` into `-ErrorVariable` at roughly a dozen call boundaries before the cmdlet's own
`catch` runs, so a bare-code `-Match` assertion passes even with the cmdlet's
`$PSCmdlet.WriteError()` call deleted. The mechanism behind that deposit is written down once, with
its measured counts, in [#writeerror-deposit](#writeerror-deposit).

Related test shapes that look like guards but are not, found by audit PR9 (#34) and PR #63:
`-ErrorVariable` declared inside a `{ } | Should -Not -Throw` scriptblock never populates the outer
variable (child scope), and `Should -Invoke ... -Times N` is *at-least* semantics unless you add
`-Exactly`.

**That last one holds for `N >= 1` only, and the exception matters because this suite leans on it.**
`-Times 0` already means EXACTLY zero. Pester's own help for `Should -Invoke` states "If the value
passed to the Times parameter is zero, the Exactly switch is implied", and the implementation agrees
-- `Pester.psm1` gates the failure on `($Exactly -or ($Times -eq 0))`. Verified by execution against
both Pester 5.7.1 and 6.2.0 (the version this repository resolves at `latest`): a bare `-Times 0`
FAILS when the command was called, while a bare `-Times 1` passes when it was called twice. So the
roughly 400 bare `-Times 0` assertions under `tests/` are sound negative proofs, not inert guards.
Adding `-Exactly` at zero is harmless and clearer, but justifying it by calling the bare form
vacuously true is simply wrong -- that false justification was written into two test comments before
being caught on 2026-09-21, which is why it is recorded here rather than just deleted.

**A `-Because` string containing the word "because"** is the same family with a different mechanism:
the assertion works, the explanation it prints does not.
`output/RequiredModules/Pester/5.7.1/Pester.psm1` line 8285 formats the reason as
`" because $($bcs -replace 'because\s'),"`. `-replace` is a global, case-insensitive regex replace,
so EVERY occurrence of `because` followed by whitespace is deleted from the message, not merely a
leading one. Executed proof: the string `fails because the note was cut, because it was too long`
renders as ` because fails the note was cut, it was too long,`. Found while writing the release-note
gates -- see [#changelog-budget](#changelog-budget) -- where two messages rendered as broken prose
before it was caught, and `main`'s superseded 8,000-character ceiling message was affected too. Use
"since", or restructure the sentence.

**An unnarrowed `-ErrorVariable` assertion at an access-package cmdlet** (Sprint 4, issue #71) is a
sharper instance of the cmdlet-qualified rule two paragraphs up, and it is worth its own entry
because the assertion it defeats is the one a careful reviewer would ask for: not "did the cmdlet
write an error", but "did it write the RIGHT one". Measured, with the `Resolve-OERAccessPackageId`
call mocked to throw a `PermissionDenied` record with ErrorId `Authorization_RequestDenied` and
`Get-OERAccessPackageResourceRole -ErrorAction SilentlyContinue -ErrorVariable Err` collecting it:

```
COUNT=13
REC[0]  fqid='Authorization_RequestDenied'                                invocation='<none>'
...                                                (nine more of the same, three of them id-less)
REC[12] fqid='Authorization_RequestDenied,Get-OERAccessPackageResourceRole' invocation='Get-OERAccessPackageResourceRole'
```

Exactly ONE of the thirteen -- the last -- is the record the cmdlet itself published; every other one
is the engine's own capture of the INNER throw as it crossed a call boundary, and each of those
carries the BARE inner id and no `InvocationInfo.MyCommand`. Re-measured with the guard reverted (the
`$PSCmdlet.WriteError($PSItem)` replaced by the pre-fix fall-through into the not-found branch), the
list is identical except for the last entry, which becomes
`'AccessPackageNotFound,Get-OERAccessPackageResourceRole'` -- the exact defect the test exists to
catch -- while `$Err[0].FullyQualifiedErrorId` is still the bare `Authorization_RequestDenied`. So
`$Err.FullyQualifiedErrorId -notmatch 'AccessPackageNotFound'`, and every unnarrowed variant of it
(`$Err[0]`, a `-join`, a `Should -Not -Match` over the whole collection), passes with the fix
REVERTED. The narrowing that makes the assertion real is to filter to the record the cmdlet
published, by `InvocationInfo.MyCommand.Name`, then assert on that single record:

```powershell
$Published = @($Err) | Where-Object {
    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
    $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageResourceRole'
}
@($Published).Count | Should -Be 1
$Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
```

Do not treat 13 as a constant -- the count is an artefact of how many boundaries the throw crosses
and how many mocks are in play (Sprint 4's own working note recorded four at a different cmdlet, and
the same measurement at `New-OERAccessReviewDefinition` gives 13 as well). What IS stable is the
shape: more than one record, at most one of them the cmdlet's own, and the bare-id records present
whether the guard is there or not. Every resolver-failure test added in Sprint 4 under
`tests/Unit/Public/` uses the narrowing above; read one before writing another.

**A casing assertion written with a case-INSENSITIVE operator** (Sprint 4, issue #72) is inert for a
reason that has nothing to do with error records: PowerShell's default comparison operators ignore
case, so a test that claims to pin the exact spelling a cmdlet puts on the wire pins only its
letters. Executed proof, comparing the two spellings of the same value:

```
-like: True   -clike: False       -eq: True   -ceq: False
-match: True  -cmatch: False      -contains: True   -ccontains: False
'Delivered' | Should -Be 'delivered'        -> PASSED
'Delivered' | Should -BeExactly 'delivered' -> FAILED
```

All five of the forms a test would reach for first -- `-like`, `-eq`, `-match`, `-contains` and
`Should -Be` -- pass on a casing MISMATCH. The case-sensitive forms are `-clike`, `-ceq`, `-cmatch`,
`-ccontains` and `Should -BeExactly`. The worked example is
`tests/Unit/Public/Get-OERAccessPackageAssignment.Tests.ps1`, where the `-State` pins assert
`$Uri -clike "*state eq 'delivered'*"` and `... 'Delivered' ...` inside a `Should -Invoke`
`-ParameterFilter`; with plain `-like` both tests would pass no matter which spelling the cmdlet
emitted, which is the whole question issue #72 asks. One property of the URI builder is what makes a
`-clike` assertion on the finished URI a proof rather than an approximation: the value reaches the
filter through `ConvertTo-OERODataFilterValue`, i.e. `[uri]::EscapeDataString`, which does not alter
letter case (`'Delivered'` -> `'Delivered'`, `'delivered'` -> `'delivered'`, measured), so the casing
seen on the wire is exactly the casing the caller typed.

**A test whose outcome depends on the machine it runs on** is the same family from the other side:
every entry above passes with the defect present, these pass or fail with the machine, and the
local gate cannot tell which. The first GitHub Actions run (2026-09-13) found two mechanisms.

*A `Mock -ModuleName` the test body calls itself.* `Mock -ModuleName Omnicit.EntraRBAC
Get-OERConfiguration` installs the mock in the module's session state, so only calls made from
module code reach it. The same command written in the test body resolves in the test's own session
state, to the module's real exported function. Measured with three profiles written under
`$TestDrive` and only the module-scoped mock in place:

```
test-scope call    -> 3 object(s): p1,p2,p3   (Function from module [Omnicit.EntraRBAC] -- the real one)
module-scope call  -> 1 object(s): mocked
piped into Connect-OER:  -Times 1 passes   -Times 1 -Exactly fails   -Times 3 -Exactly passes
same pipe, empty profile directory:  -Times 1 fails
a test-scope Mock added beside the module one -> the test-scope call returns 1 object(s): mocked
```

`tests/Unit/Public/Connect-OER.Tests.ps1` piped a bare `Get-OERConfiguration` into `Connect-OER`
under exactly that mock, so every local gate run enumerated and imported the maintainer's real
`<home>/.config/Omnicit.EntraRBAC/Profiles`, and the at-least `-Times 1` read any number of real
profiles as a pass. It went red only on a runner with none. The fix is a second `Mock` without
`-ModuleName` for the call the test makes itself, plus `-Exactly` -- the half that would have caught
it on a machine that has profiles.

*A `-BasePath` default exercised on purpose.* A test proving that a profile cmdlet's `-BasePath`
DEFAULT binds (issue #40, [#profile-path](#profile-path)) resolves to the real home directory by
construction, and on Windows it cannot be moved: `[System.Environment]::GetFolderPath('UserProfile')`
returned the real profile folder with `USERPROFILE` and `HOME` both overridden (measured), so
removing `USERPROFILE` never takes such a test off the real disk. Keep the default under test,
intercept the first file-system call with a module-scoped `Test-Path` mock, and assert that the mock
received the default path: that proves the default reached the body, and nothing real is read.

*How the sweep was made -- repeat it before trusting a new profile-touching test.* Two halves. An AST
scan of `tests/` for a `-ModuleName` mock whose target the test also calls outside `InModuleScope`
within that mock's effective block (one hit, the Connect-OER test above), and for a mock without
`-ModuleName` outside `InModuleScope` (none). Then a run of the whole unit suite against a scratch
copy of the BUILT module in which every file-system primitive the profile code uses -- `Test-Path`,
`Get-ChildItem`, `Get-Item`, `Get-Content`, `Import-PowerShellDataFile`, `Set-Content`,
`Remove-Item`, `New-Item` -- is a module-scope proxy that logs, and refuses, any access under the
real `<home>/.config/Omnicit.EntraRBAC`. A Pester mock of the same command shadows the proxy, so only
an access that would really reach the disk is logged. That half found three tests the AST scan cannot
see, each exercising a default on purpose: `Get-OERConfiguration.Tests.ps1`,
`BasePathDefault.Cohort.Tests.ps1` and `Resolve-OERTenantAliasCompletion.Tests.ps1`. Measured: the
four tests as they stood produced four refused accesses, their fixed versions none, and the whole
unit suite after the fix passed 3756 tests with zero. Two traps in building such a probe: a Pester
mock of a proxy function cannot evaluate the proxy's `dynamicparam` block ("Cannot retrieve the
dynamic parameters"), so drop that block where the module uses no dynamic parameter of the cmdlet;
and a probe injected at a profile cmdlet's ENTRY cannot tell a bound default whose file-system call
is intercepted from a real read -- it has to sit at the primitive.

*An unset `-ErrorAction` while the test observes a non-terminating record.* Module code does not see
its caller's LOCAL `$ErrorActionPreference`, but it does read the GLOBAL one. Measured with a
throwaway module:

```
global Continue                      -> module sees Continue
global Stop                          -> module sees Stop
caller-local Stop, global Continue   -> module sees Continue
-ErrorAction Stop on the call        -> module sees Stop
global Stop, -ErrorAction Continue   -> module sees Continue
```

A global Stop is what an operator's profile sets, what GitHub Actions' `shell: pwsh` sets (the step
script is dot-sourced into the global scope with `$ErrorActionPreference = 'stop'` prepended), and
what Azure Pipelines' `PowerShell@2` sets by documented default (`errorActionPreference: stop`,
dot-sourced unless `runScriptInSeparateScope`). A default interactive shell runs Continue, which is
the only reason the local gate never saw the three tests that went red on Actions:
Export-OERInventory's summary-before-error ordering test, Get-OERRoleManagementPolicy's piped role
definition test and Set-OERGroupPimPolicy's partial-failure test. Each was checked for a PRODUCT
difference before it was touched, by recording every mock invocation, warning, output object, error
record and written bundle file under five modes. For all three, a global Stop was identical to an
explicit `-ErrorAction Stop` -- the mode Export-OERInventory's help tells operators to use -- and the
events before the cmdlet's own trailing error were identical to Continue. That error is the last
thing each cmdlet emits, so under Stop nothing is skipped: the statement throws instead of
returning. That is PowerShell's contract, so the defect was in the tests, and the fix pins
`-ErrorAction` on the call. Setting `$ErrorActionPreference = 'Continue'` inside the `It` does NOT
pin it: measured, the module still saw Stop and threw. A parameter-binding error
(`InputObjectNotBound`) obeys the per-call `-ErrorAction Continue` as well (measured).

The Actions workflow keeps GitHub's Stop default on purpose. It is the preference operator profiles
and Azure Pipelines run under, and the local gate already covers Continue.

*A `-like` pattern whose square brackets were meant literally.* In PowerShell wildcard syntax `[...]`
is a CHARACTER CLASS, so `-like '[FAIL]*'` matches one character out of `F`, `A`, `I`, `L` followed
by anything -- and never a literal `[`. Measured:

```
'[FAIL] something' -like '[FAIL]*'    -> False      # the intended match, silently missed
'F something'      -like '[FAIL]*'    -> True       # matched instead
'L'                -like '[FAIL]*'    -> True
'[FAIL] something' -like '`[FAIL`]*'  -> True       # backtick-escaped brackets
('[FAIL] something').StartsWith('[FAIL]')  -> True
```

This is the family's first member that lives in an OPERATOR's behaviour rather than in Pester, which
makes it the most general one recorded here: it needs no test framework, no mock and no error record,
only a wildcard match over text a human formatted. It reached this repository through a mutation
harness written to prove a redaction pass, which reported zero failing checks for two consecutive
runs while every check it thought it was reading had in fact failed. The harness looked right, ran,
and measured nothing -- the defining shape of this whole family.

Prefer `.StartsWith('[FAIL]')`, or `-match ('^' + [regex]::Escape('[FAIL]'))`, over escaping the
brackets. Both say what they mean; the backtick form works but is one deleted character away from
silently reverting, and `[System.Management.Automation.WildcardPattern]::Escape()` also escapes the
trailing `*`, so it cannot be used on a pattern that still needs a wildcard.

The same operator has a SECOND, louder failure for an UNBALANCED bracket: `'AR[Test' -like 'AR[Test'`
throws `WildcardPatternException` rather than returning `$false`, which is why
`Get-OERAccessReviewDefinition.Tests.ps1` leaves `[` out of its special-character set on purpose. The
loud form is harmless; it is the BALANCED one above that passes review, because it looks like a
string the author quoted from output.

Swept at the time this was written: zero `-like`/`-notlike`/`Should -BeLike` sites with a bracketed
literal pattern in any tracked `.ps1`, `.psm1` or `.psd1`, source and tests alike. The form never
reached a committed file -- it lived only in the throwaway harness -- so there is nothing to fix,
only something to recognise.

### The transport tripwire

Until Sprint 8 step 4 nothing stood between an unmocked module call and the real transport: there
was no global mock and no check, only the convention of mocking at the module boundary. Mocking
`Initialize-OERAuth` is not enough on its own. With no auth state, `Invoke-OERArmRequest` falls back
to `https://management.azure.com` and sends a real, unauthenticated `Invoke-WebRequest` -- measured
on 2026-10-05 by deleting one `Invoke-OERArmRequest` mock in a copy of
`Get-OERResourceGroup.Tests.ps1`: with `Initialize-OERAuth` still mocked, the call reached
`Invoke-WebRequest` from `Invoke-OERArmRequest.ps1`.

**What.** `tests/Unit/TestHelpers/OERTransportTripwire.ps1` defines a GLOBAL replacement for each of
the six commands through which module code reaches a tenant or the network: `Get-AzToken`,
`Connect-MgGraph`, `Disconnect-MgGraph`, `Invoke-MgGraphRequest`, `Invoke-WebRequest` and, since
Sprint 9 step 3, `Invoke-RestMethod`, which the tenant lookup sends with. Each one records the call
and throws. Every unit test file that imports the module dot-sources the helper and
calls `Install-OERTransportTripwire` in its root `BeforeAll`, directly after `Import-Module`, and
ends with a root `AfterAll` that runs `Assert-OERTransportTripwire` in a `try` and
`Uninstall-OERTransportTripwire` in its `finally`. The assert throws listing every recorded hit and
every name that no longer resolves to its replacement from the module's scope. A throw in a root
`AfterAll` fails the container -- `Result=Failed`, `FailedContainers=1`, measured on Pester 5.7.1
and 6.2.0 -- and Sampler's `Pester_Tests_Stop_On_Fail` gates on `Result -eq 'Passed'`, so
`./build.ps1 -Tasks test` fails with it. The install happens in the root `BeforeAll`, so Pester's
discovery phase (`BeforeDiscovery`, `Describe` bodies and `-ForEach` data) runs without the
tripwire; nothing calls module code at discovery time today (checked 2026-10-05).

The answering runspace in `OERConfirmHost.ps1` has a global scope of its own, so the parent's
replacements are invisible there. `Invoke-OERWithConfirmAnswer` installs the same replacements in
it from the parent's definitions, shares the parent's hit list, records a hit for any name that no
longer resolves there after the scenario, fails the run when that check itself raised an error
there (a scenario that left the runspace's definitions or hit list unreadable would otherwise let
the check record nothing and report success), and refuses to run at all without an installed
tripwire.

`tests/QA/testhygiene.tests.ps1` holds the wiring by presence, statically and importing nothing: a
root `BeforeAll` that calls `Install-OERTransportTripwire` after the first `Import-Module`, and a
root `AfterAll` whose `try` calls the assert and whose `finally` calls the uninstall, with no
`catch`, which would swallow the assert's throw. Its only exemptions are the two AST-only
alias-order cohort suites, which import nothing; the gate fails if either starts importing, calls a
`Verb-OER*` command or runs `Get-Command -Module`. The QA gate files themselves are outside the
tripwire -- they call help, the analyzer and pure maps only.

**Why it resolves.** `source/` never module-qualifies these six calls, and a function outranks a
cmdlet in command resolution, so module code resolves the global replacement. A Pester
`Mock -ModuleName` is an alias in the module's script scope and outranks both, so every existing
mock keeps working and records no hit. A test-scope `Mock` without `-ModuleName` is not seen by
module code, so that call hits the tripwire. All measured on Pester 5.7.1 and 6.2.0 alike, and the
known-answer suite `OERTransportTripwire.Tests.ps1` pins resolution, mock precedence and a re-import
of the module per name.

**Why record AND throw.** A throw alone is not enough: the module's own catch blocks turn it into a
`WriteError` or a Failed row that a test may never look at. Measured: a copy of
`Get-OERGroup.Tests.ps1` with one `Invoke-OERGraphRequest` mock deleted passed all 48 of its tests
while the transport was reached once, and only the `AfterAll` check failed the file. The record
holds parameter NAMES only, never a value, since a value may be a secret, a token or a URI; the
known-answer suite pins that a call whose `-Uri` carries a sentinel records `Parameters = 'Uri'` and
no sentinel.

**Why built from the cmdlet's metadata, with no `dynamicparam`.** Pester builds a mock's parameter
block from the command it resolves, which is now the replacement, so the replacement must carry
exactly the cmdlet's parameters. Each is generated with `ProxyCommand.GetCmdletBindingAttribute`
and `ProxyCommand.GetParamBlock` from the real cmdlet. Measured on 2026-10-05 (AzAuth 2.10.0,
Microsoft.Graph.Authentication 2.41.0, Microsoft.PowerShell.Utility 7.0.0.0): none of the five
implements `IDynamicParameters`, and the generated functions have the same parameter names (35, 30,
13, 30 and 54) and the same number of parameter sets (11, 6, 1, 1 and 4) as the cmdlets. The sixth,
`Invoke-RestMethod`, was added in Sprint 9 step 3 and the generator accepted it unchanged. Measured
on 2026-10-06 (PowerShell 7.6.6, Microsoft.PowerShell.Utility 7.0.0.0): the cmdlet does not implement
`IDynamicParameters` and has 58 parameters in 4 parameter sets, counted the same way, with
`Invoke-WebRequest` reading 54 and 4 again; the known-answer suite pins the replacement's parameter
parity per name. A Pester mock of a proxy with a `dynamicparam` block fails (see the probe traps
above), so the generator refuses a cmdlet that starts declaring dynamic parameters.

**Per file, not in `source/` and not in the build (A13).** A check in `source/` would publish a test
switch to the Gallery, and a build step would not cover a single `Invoke-Pester` run.

**Pester 5.7.1 and 6.2.0 differ on a filter that matches nothing.** A call that no
`-ParameterFilter` of a mock matches, with no default mock beside them: 5.7.1 calls the original --
now the tripwire, one hit; 6.2.0 throws "No mock for command 'Invoke-WebRequest' matched the call:
none of the parameter filters matched, and there is no default mock to fall back to." without
calling it, and records no hit. On 6.x that throw is raised inside module code, a module `catch` can
swallow it like any other failure, and the test can stay green with its happy path silently
replaced by its failure path. The tripwire cannot see that, since no transport is reached. Measured
in the final review of Sprint 8 step 4: a test that mocks `Invoke-OERGraphRequest` with a
`-ParameterFilter` only, then calls `Get-OERAdministrativeUnit` with `-Filter` and
`-ErrorAction SilentlyContinue`, passed on Pester 6.2.0 with no hit, while the module's catch
swallowed 13 "No mock for command" records; on 5.7.1 the same file failed its container on one hit,
`Invoke-MgGraphRequest` from `Invoke-OERGraphRequest.ps1`. The real transport was reached on
neither version. This is the inert shape that remains, recorded here and not gated: the remedy is a
default mock beside every filtered mock, so a call the filters stop matching falls back to it
instead of throwing.

**The traps, measured on PowerShell 7.6 with a throwaway module.**

- An unqualified `Remove-Item 'function:X'` inside `InModuleScope`, with no local `X` left, walks up
  and removes the GLOBAL replacement. The `AfterAll` then reports `X no longer resolves`.
- A scope qualifier in a `Remove-Item` path on the `function:` drive removes nothing and raises no
  error, with or without `-Force`: `function:script:X`, `function:local:X` and `function:global:X`
  alike. `Uninstall-OERTransportTripwire` therefore removes by an unqualified path, and only while
  the nearest definition is a replacement, then verifies from its own scope and from the module's.
- A function defined unqualified inside `InModuleScope` disappears when that block returns; one
  defined as `function script:X` persists in the module.
- Seven sites -- five in `Invoke-OERGraphRequest.Tests.ps1`, two in `Get-OERInventory.Tests.ps1` --
  ran a statement before the local stub's definition inside the `try` whose `finally` removes the
  stub, so a throw at that statement would have deleted the global replacement. The definition is
  now the first statement in each `try`.
- A ReadOnly replacement was measured and not adopted. It blocks the trap (`FunctionNotRemovable`)
  and Pester still mocks it, but it was set aside because
  `Remove-Item -Path function:global:X -Force` left it in place. That form leaves a plain function
  in place too (the qualifier above), and an unqualified `Remove-Item -Force` does remove a ReadOnly
  global function (measured). Plain functions plus the `AfterAll` resolution check stand: a removed
  replacement fails the file either way.

**What it found.** The first runs with the tripwire (Pester 6.2.0, 2026-10-05) found two tests that
reached the real `Invoke-MgGraphRequest` through the unmocked Graph wrapper and stayed green, since
module code swallowed the failure. `Get-OERInventory.Tests.ps1`, "does not emit url for a group
resource": the group resource's current-name lookup by `originId` was unmocked.
`Resolve-OERDirectoryRoleInput.Tests.ps1`, "never throws for a match, a miss, an ambiguity or a read
failure": its match case had no resolver mock, so it read Graph and exercised a read failure instead
of a match. Each now has the missing mock, and the whole unit suite then passed 5,482 tests with no
hit.

## writeerror-deposit

Sprint 8 step 4 (BL-27). Comments in several `source/` files each describe part of this mechanism,
at the site that pays for it. It is written down here once, with the numbers those comments
measured, so a reader does not have to assemble it from them.

**The mechanism.** `$PSCmdlet.WriteError()` deposits the record it writes into every
`-ErrorVariable` and `$Error` collector already listening on the call stack, the instant it runs --
before, and independently of, whatever `-ErrorAction` does next. Three facts:

- A `catch` further up can stop the resulting exception from becoming a hard stop. It can never
  retract a deposit from an `-ErrorVariable`, which the engine fills as the record is raised, before
  any `catch` runs. Only `$global:Error` has a way back, and only through `Remove-OERErrorRecord`,
  which removes the matching entry by exception reference (see [#bearer-scrub](#bearer-scrub)). A
  read that SUCCEEDED, or an apply step that ends `Updated`, can therefore still leave error
  records in the operator's own `-ErrorVariable` and `$Error`.
- An array subexpression `@( )` around the call runs it as its own nested pipeline, and the record
  is deposited again on the way out.
- Piping the call onward before the `@( )` closes leaks nothing to the caller, although a local
  `-ErrorVariable` still receives the record. This one is a measurement, not a consequence of the
  other two.

**What was measured, and where.** Each number comes from the comment at its site, which is found by
the quoted text and not by line number.

- One written record, in the access review read of `Get-OERInventory` ("The pipe into Where-Object
  is load-bearing"): `@(call -ErrorAction Stop)` inside a try/catch leaks 3 records to the caller;
  `$Var = call -ErrorAction SilentlyContinue -ErrorVariable Local` leaks 1;
  `@(call -ErrorAction SilentlyContinue -ErrorVariable Local)` leaks 1; only piping the call onward
  before the `@( )` closes leaks 0.
- The existence probe of `Sync-OERStructureAccessReview` ("-ErrorAction SilentlyContinue with a
  LOCAL -ErrorVariable"): the old shape, `-ErrorAction Stop` with an `@( )` around the call,
  reported a successful `Created` while leaving `AccessReviewDefinitionNotFound` records in the
  operator's own `$Error` and `-ErrorVariable` -- two per create on a live run, and eighteen on a
  genuine throttle failure. The `@( )` was the other half of that doubling, so dropping either one
  alone only halves the leak.
- The access package and policy name lookup of `Get-OERInventory` ("Measured offline against the
  real wrapper"): 20 records for an access review whose package and policy had been deleted, read
  through `Get-OERAccessPackage` and `Get-OERAccessPackageAssignmentPolicy`, against 0 through a
  transport read with the not-found codes declared. The same comment puts the two readers at about
  ten records per lookup, identical for a deleted package and for a 403.

**The remedies, and where each is used.**

1. *Capture, then inspect.* `-ErrorAction SilentlyContinue` with a LOCAL `-ErrorVariable`, and the
   call piped onward: the pipe is the only measured shape that leaks 0 to the caller, so the call is
   never a bare call inside `@( )` and never a bare assignment, which leak 1 each.
   `SilentlyContinue` means "captured", not "ignored": the records are inspected afterwards, so a
   failed read is still a failed read. Both sites pipe onward. The existence probe of
   `Sync-OERStructureAccessReview` reads `... -ErrorVariable ProbeErrors | Where-Object { ... }`
   and wraps only the filtered variable in `@( )`. The access review read of `Get-OERInventory`
   reads `@(call ... | Where-Object { ... })`, and its comment says the pipe is load-bearing and
   the filter is not to be simplified away. The group and administrative-unit reads of
   `Get-OERInventory` share the capture but not the pipe, as the probe's comment says: each is a
   bare call inside `@( )`, the shape measured above to leak 1. The local collection also holds
   records raised inside nested calls even when an inner catch swallowed them, so only a record the
   cmdlet itself published counts. The probe's comment measured a throttled attempt that was
   retried and then succeeded with zero matches: it left three `TooManyRequests` records and one
   bare, message-less exception beside the genuine not-found record. A published record carries the
   calling cmdlet's name as a comma-separated segment of its `FullyQualifiedErrorId`.
2. *Declare the expected codes at the request.* `Invoke-OERGraphRequest -ExpectedErrorCode` makes
   the wrapper answer with a marker instead of raising, so nothing is deposited anywhere. A throw
   caught afterwards cannot do that, since the engine fills `-ErrorVariable` as the record is
   raised, before any `catch` runs. Used by `Get-OERPimGroupPolicyId` (`ResourceTypeNotSupported`,
   and `ResourceNotFound` under `-NotFoundAsUnlisted`), by `Get-OERListedGroupPimPolicy`
   (`ResourceNotFound`), and by the name lookup of `Get-OERInventory`
   (`Get-AccessReviewReferenceName`). `Sync-OERStructureGroup` waits on a group created in the same
   run through the two PIM helpers, since a read through `Get-OERGroupPimPolicy` with
   `-ErrorAction Stop` deposited its `PimPolicyNotFound` records in the caller's `-ErrorVariable`
   on every attempt, and a run that ended `Updated` still handed the caller a list of errors. A
   403, an exhausted 429, a 5xx and a code that was not declared still raise, and still leave their
   own records; the name lookup's comment accepts that for a real failure, which the partial names.
3. *Publish the failure as itself, once.* Where the failure IS the outcome, the record is meant to
   reach the caller. In `Sync-OERStructureGroup` step 4 (pimPolicy), the `catch` around
   `Set-OERGroupPimPolicy -ErrorAction Stop` scrubs the caught record with `Remove-OERErrorRecord`,
   writes it again through the engine's own cmdlet with `$Caller.WriteError($PSItem)`, and adds a
   Failed result row carrying that same record. "Once" means once as a record the engine writes:
   the child's own `WriteError` has already deposited its record into the caller's
   `-ErrorVariable` before the `catch` runs; the `catch` does not retract that deposit, and the
   republish adds its own copy beside it (inferred from the mechanism above, not measured).
   `Remove-OERErrorRecord`, called first, scrubs the bearer token from the shared request object
   and drops the matching `$global:Error` entry. The handler's other `catch` blocks around child
   writes have the same shape. See [#approver-lookup](#approver-lookup) for the same rule stated
   for the approver lookups.

None of the three retracts a deposit that an inner call has already made into the caller's
`-ErrorVariable`: the first confines the deposit to a local collection, the second avoids making
it, and the third publishes one on purpose. A test that asserts on a `-ErrorVariable` therefore
narrows to the record the cmdlet published, as [#bearer-scrub-tests](#bearer-scrub-tests)
describes.

## static-source-gates

`tests/QA/sourcehygiene.tests.ps1` carries ten `Describe` blocks. Four machine-check a rule stated
in CLAUDE.md; the fifth checks a rule stated only in this file, the sixth checks an invariant no rule
states in prose, the seventh (Task 6, issue #81) and eighth (Sprint 2) each machine-check a
single-ownership rule CLAUDE.md ## Code Style states, the ninth machine-checks the
no-runtime-Az-cmdlet rule CLAUDE.md ## Dependencies states, and the tenth (Sprint 8 step 4b) the
transport gates CLAUDE.md ## Authentication Architecture, ## Graph Requests and ## ARM Requests
state. They all run off one shared `BeforeAll` that enumerates and parses the tree once for the
first six gates; the seventh, eighth and ninth each run their own additional parse pass, kept
deliberately separate from that shared walk so a mistake in new detection logic cannot perturb the
other gates' proven reachability closure or catch-clause scan. The tenth reads the command names
that shared walk already collected for its ownership checks and the `Initialize-OERAuth` call nodes
it keeps for its call-site check, and parses the two wrapper files again, from the text that walk
read, for its structural check.

**1. Encoding.** Every authored `.ps1`/`.psd1`/`.psm1`/`.ps1xml` under `source/` and `tests/` must
be ASCII-only and carry no UTF-8 BOM. It is a byte-level check because PSScriptAnalyzer cannot do
this job: `PSUseBOMForUnicodeEncodedFile` fires only on non-ASCII in a BOM-*less* file, so adding a
BOM inverts it to a pass; and `module.tests.ps1` hands only `source/<FunctionName>.ps1` to the
analyzer, so nothing under `tests/` and no `.psm1`, `.psd1` or `.ps1xml` is ever scanned by it. The
repo root is deliberately out of scope. There is no allow-list.

**2. Bearer scrub.** `Remove-OERErrorRecord -Record $PSItem` must be the FIRST statement of every
`catch` in a source file that reaches transport -- `Invoke-OERGraphRequest`, `Invoke-OERArmRequest`,
`Invoke-MgGraphRequest`, `Invoke-WebRequest`, `Invoke-RestMethod`, `Get-AzToken`, `Connect-MgGraph` or
`Connect-AzAccount` -- directly OR transitively through any module function it calls.
`Invoke-RestMethod` joined the set in Sprint 9 step 3 with the tenant lookup: it carries no
credential, but it is the module's one network call outside the two transports, and a record from a
failed request can carry the request message.

Transport is detected from `CommandAst.GetCommandName()`, **never a text grep**:
`source/Private/Remove-OERErrorRecord.ps1` carries a literal `Invoke-MgGraphRequest` in its
`.EXAMPLE` block, and a grep would false-positive it into a violation. A known limit of that
detection: it matches the command's literal name, so an alias -- `irm` for `Invoke-RestMethod`, as
`iwr`, `curl` or `wget` for `Invoke-WebRequest` -- does not mark a file as reaching transport here.
Gate 10's ownership scan does resolve those aliases, so such an alias anywhere but in its owner's file
is a violation there.

The gate carries a small, justified exemption list -- currently the four `Resolve-OERName` catches
in `New-OERGroup`, `New-OERCatalog`, `New-OERAccessPackage` and `New-OERAdministrativeUnit`, whose
`try` body is a single call to a pure local string-template helper that issues no HTTP request. An
exemption is keyed on the file AND verified structurally against that `try` shape, so it cannot
silently unguard the file's other catches, and it must carry a written reason. **When a new catch
trips the gate, add the scrub -- do not add an entry.**

**3. Duration encoder.** No file outside `ConvertTo-OERDuration` may build an ISO 8601 duration by
hand with the `-f` format operator (`"PT{0}H" -f $Hours`), which is how `New-OERPimRuleSet` used to
bypass the sole-int-to-ISO-encoder rule. Non-vacuity floor: more than 20 `-f` `BinaryExpressionAst`
nodes must still be found in `source/`, or the AST branch has stopped firing.

**4. Cmdlet references.** Every `Verb-OER...` token anywhere in `source/**/*.ps1` -- prose in
comment-based help included, which is why this one is a text scan and not an AST walk -- must
resolve to a real function under `source/Public` or `source/Private`. Non-vacuity floors: more than
195 scanned files and more than 3100 matched tokens.

**5. ARM api-versions.** Every distinct `api-version=...` literal in `source/` must appear in this
file under `## arm-transport`, which CLAUDE.md delegates to instead of keeping its own copy.
Non-vacuity: the `## arm-transport` section must be found and non-empty (an empty haystack would
report every version as undocumented for the wrong reason), and more than 35 api-version literals
must still be matched.

**6. suffix/psm1 mirror.** The region from the first `Update-TypeData` to end of file must be
byte-identical between `source/suffix.ps1` and the dev-mode `source/Omnicit.EntraRBAC.psm1` -- both
the `Update-TypeData` blocks and the `Register-ArgumentCompleter` calls, which is the whole of what
CLAUDE.md requires to be mirrored. The dev-mode loader's one extra comment-only paragraph
("Formats are loaded natively...") is stripped from both sides before comparison, because
ModuleBuilder appends `suffix.ps1` after the built loader's own boilerplate and that paragraph only
ever existed in the dev-mode copy. Non-vacuity: each region must be non-empty and must contain a
`Register-ArgumentCompleter` call, so a start anchor that stops matching -- or an end anchor that
silently truncates the completer half back off -- fails here instead of comparing `$null` to `$null`.

**7. Sovereign cloud endpoint hygiene** (Task 6, issue #81). `Get-OERCloudEndpoint` is the single
owner of the cloud-to-endpoint table (CLAUDE.md ## Code Style); no other `source/**/*.ps1` file may
hardcode one of the ten literal hostnames the table resolves (`graph.microsoft.com`,
`management.azure.com`, `graph.microsoft.us`, `dod-graph.microsoft.us`,
`microsoftgraph.chinacloudapi.cn`, `management.usgovcloudapi.net`, `management.chinacloudapi.cn`,
`login.microsoftonline.com`, `login.microsoftonline.us`, `login.chinacloudapi.cn`), and no call site
may pass `-TokenCache` to `Get-AzToken` (spike condition 6 below). Two independent AST-based checks,
each with its own exemption or non-vacuity mechanism:

- **Host literal.** Every `StringConstantExpressionAst`/`ExpandableStringExpressionAst` node's VALUE
  is matched against the ten hostnames. This is deliberately not the regex-plus-tokenizer
  comment-strip approach `tests/Unit/Private/Get-OERCloudEndpoint.Tests.ps1`'s
  `Remove-OERCommentRegion` uses: a comment is a TOKEN, never an AST node, so a value-level AST scan
  is comment-immune by construction -- verified empirically before the gate was written -- with no
  separate stripping step needed. Two exemptions, each carrying a written reason but NOT the same
  granularity: `Get-OERCloudEndpoint.ps1` (the owner) is exempted WHOLE-FILE, since it legitimately
  IS the table and every literal in it is correct by construction. `Invoke-OERArmRequest.ps1` (its
  documented public-cloud ARM fallback, a controller ruling -- see
  [#arm-transport](#arm-transport)) is narrowed to the exact AST shape of that one literal --
  `Test-OERArmBaseUrlElseLiteral` walks the parent chain to confirm it is the sole statement of an
  `IfStatementAst`'s `ElseClause`, and that the `IfStatementAst` is itself the right-hand side of the
  assignment to `$ArmBaseUrl` -- rather than being keyed on the file alone. A round-2 code review
  caught the original file-only version of this exemption by mutation: it exempted every literal
  anywhere in `Invoke-OERArmRequest.ps1`, not just the documented one, so a second, unrelated
  `management.chinacloudapi.cn` literal added elsewhere in that file passed silently. Mutation-proved
  both ways after the fix (the real fallback still passes; the same probe literal now fails, naming
  its own line and not the legitimate one) -- see `task-6-report.md`. Non-vacuity: more than 15
  quoted cloud-host literals must still be found across the tree (21 measured -- 20 inside the table,
  1 in the ARM fallback), so a predicate that stops matching fails loudly instead of reporting zero
  violations for the wrong reason.
- **`-TokenCache` never reaches `Get-AzToken`.** Detected via `CommandAst.GetCommandName() -eq
  'Get-AzToken'` plus a `CommandParameterAst` named `TokenCache` among that call's
  `CommandElements` -- never a text grep, for the same false-positive-on-comment-based-help reason
  gate 2 gives. Non-vacuity is an EXACT named-control count rather than a floor:
  `source/Private/Initialize-OERAuth.ps1` calls `Get-AzToken` exactly twice today (Graph token, ARM
  token), both by splat, matching gate 2's "counts every catch of the named control file" shape.

**8. Apply-document declared-value hygiene** (Sprint 2). `Test-OERDeclaredProperty` and
`Test-OERDeclaredNull` are the single owners of the apply engine's declared-value rule
(CLAUDE.md ## Code Style); no apply-document-walking file may read a document node's
`PSObject.Properties.Name` directly outside a named, reasoned allowlist. The violation is flagged on
the READ itself rather than on the `-contains`-family operator that might later consume it, so an
intermediate variable cannot hide the same defect. Its scope control asserts the eighteen scanned
files BY NAME rather than by count -- the nine `Sync-OERStructure*` handlers (AccessPackage,
AccessReview, AdministrativeUnit, Catalog, DirectoryRoleAssignment, DirectoryRoleManagementPolicy,
Group, RoleAssignment and RoleManagementPolicy) plus `Read-OERStructureDocument.ps1`,
`Get-OEROmittedPruneCollection.ps1`, `Resolve-OERDeclaredApprover.ps1`,
`Resolve-OERStructureRoleAssignmentScope.ps1` and the five `Resolve-OER*Change` helpers that take a
`-Declared` node -- because a bare count says only that eighteen became seventeen, never which file
left the scan. Two earlier rounds of that gate each claimed to cover every document consumer while
missing some, so the named list is the finding, not the tidy-up. Sprint 6 step 2 added
`Resolve-OERDeclaredApprover.ps1` (a document consumer, not a `Sync-OERStructure*` handler); Sprint 6
step 3 added `Sync-OERStructureDirectoryRoleManagementPolicy.ps1` (an eighth handler); Sprint 6 step
4 added `Resolve-OERDirectoryRoleAssignmentChange.ps1` (a fifth `Resolve-OER*Change` helper) and
`Sync-OERStructureDirectoryRoleAssignment.ps1` (a ninth handler); Sprint 8 step 1 added
`Resolve-OERStructureRoleAssignmentScope.ps1`, the `roleAssignments` scope pre-pass.

**9. Az context hygiene** (fix, stopping `Disconnect-OER` signing out the operator's own Az
session). CLAUDE.md ## Dependencies states that no Az module is a dependency of this module and no
Az cmdlet is invoked at run time at all; this gate proves it from the source with an AST walk,
independently of what is installed. Every `CommandAst` whose name matches `-Az` is checked against a
small allowlist covering AzAuth's own token surface and the module's internal `Invoke-AzTokenCall`
helper -- anything else fails the gate, naming the file and line. Non-vacuity: more than 195 parsed
files, more than 2700 `CommandAst` nodes, and at least one recognised `-Az`-shaped call still found,
so a matcher that stopped matching cannot pass by finding nothing to complain about.

**10. Transport gate hygiene** (Sprint 8 step 4b, A18, A19 and A20; two owner lists widened in
Sprint 9 step 2; the tenant lookup, the session-uncertain marker and the session reclaim added in
Sprint 9 step 3; the document tenant comparison added in Sprint 9 step 6b). The
gates that stand in front of every request -- the Graph SDK session gate in the Graph transport, and
the sign-in latch gate and the sign-in supersession gate in both transports, all described under
[#auth-state](#auth-state) -- are only as good as the claim that no request can go around them, and
this gate machine-checks that claim from the source. Ownership
rules, read from the command names the shared walk collected per file: `Get-MgContext` is called
only in `Get-OERGraphSessionFingerprint`; `Lock-OERSignIn`, `Unlock-OERSignIn` and
`Register-OERSignInIdentity` only in `Initialize-OERAuth`; `Get-OERSignInRefusal` only in the two
wrappers and in `Initialize-OERAuth`; `Get-OERSignInSupersession` only in the two wrappers;
`Get-OERSignInIdentity` only in `Register-OERSignInIdentity`, `Get-OERSignInSupersession` and
`Checkpoint-OERSignIn`; `Invoke-MgGraphRequest` only in the Graph wrapper and `Invoke-WebRequest`
only in the ARM wrapper; `Invoke-RestMethod` only in `Resolve-OERTenantDomain`, and
`Resolve-OERTenantDomain` only in `Initialize-OERAuth`; `Set-OERSessionUncertain` only in
`Initialize-OERAuth`, `Connect-OER` and `Disconnect-OER`; `Get-OERDocumentTenantMismatch` only in
`Invoke-OERStructure` -- and every listed owner must really call its command, so a rule cannot hold
over nothing and a stale owner is a failure. Two of those lists were widened by one owner each in
Sprint 9 step 2, each widening justified in the gate's own text. Each row of the owner table is
enforced only by its own `It`, which asserts that the command has no caller outside its owners and
that its owners really call it: no assertion reads the table as a whole, so a row without an `It`
asserts nothing. MEASURED in Sprint 9 step 6b: the `Get-OERDocumentTenantMismatch` row alone, with
its owner list emptied, left the gate green, so it got its own `It`, and the gate's comment now
says that a new row needs one.
`Initialize-OERAuth` reads the latch once, before `Lock-OERSignIn`, to refuse a SIGN-IN under a
latched outer command (BL-74); it refuses no request, and the transports' latch gates, which this
gate places, still do, so the reason a reader elsewhere is refused -- a gate no static check places
-- does not apply to it. The gate checks the file, not that the call stands before
`Lock-OERSignIn`; the unit test
`leaves the calling command unlatched when it refuses (the check stands before Lock-OERSignIn)`
holds that. `Checkpoint-OERSignIn` builds the snapshot of the session a command began with (BL-76,
BL-81) through the same function the memory uses, which keeps its terms identical to the
remembered ones -- a second identity builder there is the drift the rule exists to stop. Its own
callers get no row: the snapshot is a value a command keeps in its own variable, never a gate in
front of a request. The tenant lookup (Sprint 9 step 3, BL-12) is held tighter than an owner rule
alone: `Resolve-OERTenantDomain` holds exactly one `Invoke-RestMethod` call, with no splat, and that
call names only `-Uri`, `-Method`, `-TimeoutSec` and `-ErrorAction`. Two lists read the call's own
parameter names: a denied list of every credential-carrying parameter of the cmdlet (`-Headers`,
`-Authentication`, `-Token`, `-Credential` and the rest), and an allowed list of those four, since
PowerShell binds an abbreviated name (`-Head` for `-Headers`) and a parameter added to the cmdlet
later is on no list. A known-answer table of eleven miniatures runs that checker in every run. The
session-uncertain marker (Sprint 9 step 3, A10) is held the same way: `$script:_OERSessionUncertain`
is read and written only in `Set-OERSessionUncertain.ps1`, and in `Initialize-OERAuth` exactly three
`Set-OERSessionUncertain` calls stand where the rule puts them -- the statement directly after the
`Lock-OERSignIn` assignment, and the statement directly after each of the two
`Register-OERSignInIdentity` calls, in the same block. The session reclaim (Sprint 9 step 3, final
review I2, Ruling F2) is held as a NAME, since no command is called to pass it: `ReclaimGraphSession`
appears under `source/` only in `Connect-OER.ps1`, which passes it, and `Initialize-OERAuth.ps1`,
which declares and reads it, and both must really name it. A parameter of that name on any command, a
prefix of it on an `Initialize-OERAuth` call (PowerShell binds `-R` to the switch), a variable or a
parameter declaration in any scope, and a string constant or expandable string holding it -- a member
name, a hashtable key, an index -- each count, read from the AST, so comments do not; a known-answer
table of sixteen miniatures runs that scan in every run. A pairing rule, read from
`Initialize-OERAuth`: each `Register-OERSignInIdentity` call is the statement directly after an
`Unlock-OERSignIn` call in the same block, each call standing alone and both passing `-Invocation`
the same variable, and the two are called equally often -- two pairs, counted exactly, so a new success end is a deliberate edit of
that number. A dropped memory write leaves that success path unremembered with nothing but
`Initialize-OERAuth`'s own tests to show it, and a `Register-OERSignInIdentity` made conditional,
piped, assigned or handed its invocation positionally is refused rather than judged. And one
structural rule, read from the two wrappers' own ASTs: every send sits in the BODY of a try that
holds exactly one call path (in each of the three Graph statements, in `Invoke-GraphSingle`, one
`Invoke-MgGraphRequest` and one `Invoke-GraphAttempt`; in ARM one `Invoke-WebRequest`, in
`Invoke-ArmCall`), and that try is preceded, in the very block that holds it and in this order, by
its session gate (Graph only), its latch gate and its supersession gate, each a throw followed by a
return, with no `Initialize-OERAuth` or `Start-Sleep` between the earliest gate and any request, and
the ARM bearer token materialized only after the last gate -- every `$Plain =` assignment,
`.ArmToken` read and `['ArmToken']` or `["ArmToken"]` index read in `Invoke-ArmCall` starts after
it. A gate in an enclosing block does not count, and a gate out of order is a violation of its own.
The statement counts are exact, not floors: three Graph transport statements, one ARM statement,
exactly one direct `Invoke-MgGraphRequest` inside `Invoke-GraphAttempt`, and two bearer markers, so
a new send path is a deliberate edit of those numbers and never a statement the scan silently
cannot place. A known-answer table of forty-five miniature regressions -- a case per way of breaking
a rule, the order of the gates included -- and one of nine for the pairing rule run the checker
itself in every run, each with the verdict it must reach. ARM has no session gate by design (its
token is not a Graph SDK session), so none is required there.
And one call-site rule, read from the `Initialize-OERAuth` call nodes the shared walk keeps per file
(final review of round 1, F1): the latch is set on the frame that calls `Initialize-OERAuth`, so the
nearest enclosing function of every call under `source/` must be the file's own top-level function
-- in the Graph wrapper `Invoke-GraphSingle` and in the ARM wrapper `Invoke-ArmCallWithRefresh`, the
two transport refreshes -- with no script block expression between the call and it. A `foreach`,
`if` or `try` block is part of the function; a `{ ... }` handed to `&`, `.`, `ForEach-Object`,
`Invoke-Command` or anything else is not, which is stricter than the engine on purpose (a
`ForEach-Object` block inside a function was measured to carry the function's own invocation). Its
non-vacuity: at least as many public call sites as public files whose command names include
`Initialize-OERAuth` (86 files and 92 call sites in all when it was written, with a floor of 80
files), `Invoke-OERStructure` among them by name, and each transport's nested function found holding
a call. Its own known-answer table of eleven miniatures covers a direct call, statement blocks, `&`,
`.`, a nested function, `ForEach-Object`, a call in no function, both transport exceptions, a
refresh moved to another nested function and a call in a wrapper's top-level function.
Its stated limits: it proves the SHAPE of a gate, not that its condition can be true, which is the
unit suites' job, and so is the proof that `Get-OERSignInSupersession` walks every frame of the
call stack; the pairing rule proves where `Register-OERSignInIdentity` stands, not what it stores;
a command name built at run time is invisible to it, as to the Az context gate;
the ownership scan resolves a module-qualified name, the three `Invoke-WebRequest` aliases and the
`Invoke-RestMethod` alias `irm`, and nothing else (gate 2, which decides where a scrub is required,
matches only the literal names); a bearer read spelled any other way (`.Item('ArmToken')`, a key
held in a variable) is not a marker; and the reclaim rule cannot see a name built at run time, an
abbreviated key in a hashtable splatted into `Initialize-OERAuth` (`@{ Recl = $true }`, which binds),
or a call of `Connect-OER` itself from another source file, which passes the switch on its own.

Every gate asserts its own non-vacuity (per-root file counts, named control files, catch-clause and
token counts, region-content checks) so a detection bug fails loudly instead of passing over an
empty collection.

## pim-beta-pin

PIM-for-Groups is deliberately pinned to the Graph `beta` endpoint. All sixteen call sites, in eleven
source files, route through the private `Get-OERPimGroupsGraphPath`, which owns the version
constant. (The count read "eight" until Sprint 6 step 5; it had been counting FILES, and had
already fallen behind by one -- `Get-OERListedGroupPimPolicy` -- before `Test-OERGroupPimInUse`
added the tenth. Sprint 7 step 3 added the eleventh, `Send-OERNewGroupEligibilityRequest`, the
apply engine's own time-bound eligibility POST for a group created in the same run, which declares
a 404 ResourceNotFound to the transport where `Add-OERGroupEligibility` cannot. The test below now
lists every calling file and fails on one it does not name.)

The v1.0 API reference documents these operations as GA, but
`learn.microsoft.com/graph/how-to-pim-update-rules` still states that PIM for groups APIs are
available on beta only, and the Entra "Configure PIM for Groups settings" article still shows the
beta policy URL. Because these paths grant and revoke standing privilege in customer tenants, the
pin stays until a read-only v1.0 diff has been run against a real tenant.

The eligibility paths and the four policy paths migrate as **one unit**: `Get-OERPimGroupPolicyId`
returns the policy id that the policy readers and writers all consume, and Learn warns those ids
change when a group is onboarded.

`tests/Unit/Private/Get-OERPimGroupsGraphPath.Tests.ps1` guards the indirection both ways, and
`tests/QA/requiredscope.tests.ps1` anchors these URI literals on their resource roots rather than
on an API version because of it.

## graph-wrapper

`Invoke-OERGraphRequest` exists to provide four things no call site should re-implement:

1. **Bearer-token security** -- the scrub in every catch. See [#bearer-scrub](#bearer-scrub).
2. **ACRS claims-challenge retry** -- decodes `claims=` from a 401 `WWW-Authenticate` header or a
   PIM 400 body, calls `Initialize-OERAuth -ClaimsChallenge`, retries once.
3. **Token-rejected retry** -- a 401 with no claims challenge forces `Initialize-OERAuth
   -ForceRefresh` and retries once.
4. **Structured error conversion** -- non-recoverable failures go through
   `Convert-GraphHttpException`, producing typed `ErrorRecord` objects.
5. **Retry-After throttle backoff** (added by PR #77) -- a 429, or a 503 carrying a `Retry-After`,
   is retried until a wait budget is spent: 300 s per request, 900 s per call however many pages it
   fetches.

**The header read behind item 5 is shape-tolerant, and that is load-bearing.** Two collection types
reach it and the obvious code for one is silently wrong on the other. Kiota's
`ApiException.ResponseHeaders` is an `IDictionary[string, IEnumerable[string]]`: it has `.Keys` and
an indexer, and PowerShell's `foreach` does NOT walk it element-by-element (a dictionary is a single
item to `foreach`), so `.Keys` plus the indexer is the only read that works -- and that is what the
Kiota path has always done. An exception's `.Response.Headers` is a
`System.Net.Http.Headers.HttpResponseHeaders`, which has no `.Keys` member at all: `$Headers.Keys`
neither throws nor yields header names, so a `.Keys` walk pointed at THAT shape would silently find
nothing and miss a `Retry-After` that was genuinely present. No such walk was ever pointed at it --
the `.Response.Headers` path asked for the header BY NAME instead -- so before
`Get-RetryAfterHeaderValue` the two shapes were served by two different reads, each correct only for
its own collection and silently wrong on the other. That is precisely why one shape-tolerant owner
was needed: an `HttpResponseHeaders` collection must be enumerated DIRECTLY, element by element, and
a Kiota dictionary must not be. The by-name read is no answer either: its `GetValues(name)`
accessor THROWS `InvalidOperationException 'The given header was not found.'` when the header is
absent, which is the normal case on every non-throttled failure -- a live `Get-OERInventory` read
of 100 groups shipped 96 such records into the caller's `-ErrorVariable`, since `-ErrorVariable` is
populated by the ENGINE from the error stream and captures records raised inside nested calls even
when an inner catch swallowed them (see [#bearer-scrub](#bearer-scrub)).
`Get-RetryAfterHeaderValue` is therefore the single owner of that read, discriminating on
`PSObject.Properties['Keys']` rather than on a type so no Graph SDK type has to be loaded to
decide, and it never throws -- an exception escaping there would REPLACE the real Graph error the
caller needs to see.

**Partial-read facts on a failed `-All` enumeration (issue #73).** Before Sprint 4 Task 3, a
failure on page N of a paged read propagated straight out of the paging loop and `$AllValues` --
everything pages 1..N-1 had already fetched -- was discarded with it: a re-run started over from
page 1 with nothing carried forward. The call still fails, deliberately and unchanged: the apply
engine diffs against what it reads, and a short list reads as drift and provokes a write, so a
partial page set is never returned on the success channel and no resume mechanism was built.
What changed is that the paging loop's own `catch` (and the `GraphExpectedCodeOnLaterPage` throw,
the other way a paged read fails partway through) now attaches three note properties an opted-in
caller can read back: `PartialValue` (every item aggregated before the failure, `@()` when page 1
itself failed), `NextLink` (the URI of the failing request -- the original `-Uri` for page 1, the
followed `@odata.nextLink` for a later page), and `PageNumber` (the 1-based page that failed).

**The one measurement that decided where those properties are attached: to the Exception, never
to the ErrorRecord.** Measured on this codebase's PowerShell 7 / .NET runtime:

```powershell
function Inner {
    $Ex = [System.Exception]::new('boom')
    $Rec = [System.Management.Automation.ErrorRecord]::new($Ex, 'MyId', 'InvalidOperation', $null)
    $Rec | Add-Member -NotePropertyName PartialValue -NotePropertyValue @('a', 'b') -Force
    throw $Rec
}
try { Inner } catch { "PartialValue: [$($_.PartialValue -join ',')]" }   # -> "PartialValue: []"
```

A note property attached to an `ErrorRecord` does NOT survive a `throw` -- PowerShell rebuilds the
`ErrorRecord` on the way out, and the catching frame sees nothing, even a bare re-throw (`throw`
with no argument) inside the same function that attached it. A note property attached to the
**Exception** DOES survive a `throw`, including out across a module boundary, because the exception
instance is carried by reference rather than rebuilt; `$Ex.Data['key']` also survives, for the same
reason. This is the same idiom `ConvertTo-SoftFailureRecord` already used for
`ResponseStatusCode`/`ResponseHeaders` before issue #73 existed -- the paging catch and the
`GraphExpectedCodeOnLaterPage` throw both follow it with `Add-Member -NotePropertyName ... -Force`
on `$PSItem.Exception` (or, for the latter, the freshly-built `[System.Exception]` before it is
wrapped in an `ErrorRecord`), never on the `ErrorRecord` itself. The obvious form -- attach to
`$PSItem`, since that is the object the catch block hands you -- is the one this measurement rules
out. Worth carrying forward past this one change: it is the shape any future "attach diagnostics to
the error" work in this module would get wrong without re-deriving the same measurement.

## arm-transport

The module does NOT use `Connect-AzAccount`/`Invoke-AzRestMethod` for ARM calls. Az.Accounts (5.x)
cannot reliably reuse an externally acquired (AzAuth) access token: its `AccessTokenAuthenticator`
fails to retrieve the token for the `management.azure.com` resource, and `Connect-AzAccount` also
chokes on a stale `DefaultSubscriptionForLogin`.

Instead, `Initialize-OERAuth -IncludeARM` caches the ARM bearer token (SecureString) in
`$script:_OERAuthState.ArmToken`, and `Invoke-OERArmRequest` sends it directly via
`Invoke-WebRequest -SkipHttpErrorCheck` against the host of the session -- the state's
`ArmResourceUrl`, else the ARM host of the state's cloud, else, with no state at all,
`https://management.azure.com` (the `ArmResourceUrl` bullet below) -- with an
`Authorization: Bearer` header. The token plaintext is materialized only at the request boundary and cleared in a `finally`; the transport `catch` scrubs
first, because the failed request carries the bearer header.

Behaviour that follows from this design:

- `Invoke-WebRequest -SkipHttpErrorCheck` does not throw on 4xx/5xx. The wrapper inspects
  `StatusCode`/`Content`; non-2xx responses convert through `Convert-ArmHttpException`.
- 401s force `Initialize-OERAuth -IncludeARM -ForceRefresh` and retry once. App-only sessions get a
  clear error instead.
- **Throttling (issue #57).** A 429, and a 503 that carries `Retry-After`, are retried with a
  bounded backoff. This was absent entirely until Sprint 3, for a mechanical reason rather than an
  oversight: the wrapper normalized every response to `{ StatusCode; Content }` and destroyed the
  headers on that line, so whatever `Retry-After` ARM sent was gone before the status was judged.
  The shape now carries `Headers`, and the collection stays inside the wrapper -- only its
  `Retry-After` entry is ever read, and nothing from it reaches any stream.
  The contract mirrors `Invoke-OERGraphRequest`'s, constant for constant:
  `ThrottleWaitBudgetSeconds = 300` per REQUEST (per PAGE under `-All`), `CallDeadlineSeconds = 900`
  per CALL as a DEADLINE that counts request time and not only sleeping, `ThrottleRetryHardCap = 10`
  as a runaway guard, and a 1..120-second clamp on any single wait. `Retry-After` is honoured in
  both RFC 9110 forms -- delta-seconds and an HTTP-date -- with exponential fallback when it is
  absent or unparseable; reading a date as zero would retry immediately against an endpoint that
  just asked for a pause. Each retry emits one `Write-Verbose` line naming the delay, the attempt
  and whether the value was server-directed or a fallback; the absence of exactly that diagnostic is
  what exposed the Graph-side bug in PR #77.
  **The bounds are enforced at the decision to wait, never by stopping a paging loop between
  pages.** Truncating an enumeration returns a partial collection as though it were complete, and
  the apply engine reads a short list as drift and writes on it. That placement is also the LIMIT of
  what `CallDeadlineSeconds` bounds, and the source comment used to overstate it: since the deadline
  is only ever consulted at a decision to wait, it caps a THROTTLED call and nothing else -- a
  never-throttled `-All` walk follows `nextLink` for as long as ARM keeps handing out pages and
  never reads the number at all. Bounding that is a separate, still-open gap. What the deadline does
  cover on a throttled call is real time, not only sleeping: `Get-ArmCallElapsed` returns the LARGER
  of wall-clock and seconds slept, so it binds on the single-request path too -- one slow request can
  cross 900 s with nothing slept. The comment claiming it "never binds" there was false and is gone
  from both wrappers.
  **The backoff wraps the 401 refresh rather than nesting inside it.** A 429 is never a 401, so a
  throttled response cannot reach the refresh branch and cannot spend the single per-call refresh
  budget; and because that budget is one shared `[ref]`, the two retry paths cannot multiply into an
  unbounded loop.
  **The Graph code is mirrored, not shared, and that is a decision rather than duplication.** The
  two transports differ in ERROR SHAPE: Graph's 429 is consumed by Kiota's `RetryHandler` and
  re-raised as an `AggregateException` wrapping an `ApiException` with no `.Response`, so its helper
  must walk an exception chain and fall back to the converted error code; ARM's 429 arrives as an
  ordinary response object with a real status and real headers, so its helper is a plain status
  test. A helper abstract enough to cover both would fit neither. Both files carry a comment saying
  so; keep the two contracts in step deliberately when either changes. Mirroring has a standing cost
  the false "never binds" comment demonstrated: a wrong line copied into the second file is now
  wrong in two places, so a correction to one is a correction to both.
- `-All` follows `nextLink`/`@nextLink` paging, converting absolute next-page URLs back to paths via
  `Uri.PathAndQuery`.
- Pinned api-versions: managementGroups `2020-05-01` (its list paging property is `@nextLink`, not
  `nextLink`), subscriptions `2022-12-01`, roleDefinitions and roleAssignments `2022-04-01`, the
  whole Azure PIM surface `2020-10-01`, and resources/resourceGroups `2025-04-01`.
- `roleDefinitionId` in a role assignment body is always the FULL ARM resource id, never a bare GUID.
- `ArmResourceUrl` IS configurable, as of Task 6's sprint (issue #81): `Initialize-OERAuth -Environment`
  sets it from `Get-OERCloudEndpoint`'s `ArmResource` field instead of the module hardcoding
  `https://management.azure.com` as the only reachable value. `Invoke-OERArmRequest` keeps that
  literal as a documented fallback for the one case configuration cannot reach -- a call made before
  any auth state exists -- so it fails on the missing token instead of on a null host; that fallback
  is a controller ruling, not an oversight, and is exempted by name (not deleted) from the gate-7
  hardcoded-host-literal check in [#static-source-gates](#static-source-gates). See
  [#sovereign-clouds](#sovereign-clouds) for the sovereign-cloud design and its evidence.
  **Since Sprint 10 step 3 (BL-65) the host is chosen in three steps:** the state's `ArmResourceUrl`
  when it has one; otherwise, for a state that has none, the `ArmResource` host of the state's
  `Environment` (`Global` when the key is missing, empty or null), read from `Get-OERCloudEndpoint`;
  and the literal only when there is no state at all. Before that, a state without `ArmResourceUrl`
  sent to the public cloud whatever cloud the session was in. The cloud-host branch is defence in
  depth: no state the module builds holds a token without a url -- `Initialize-OERAuth` sets and
  clears `ArmToken` and `ArmResourceUrl` together, in the drop under
  [The Graph SDK session](#the-graph-sdk-session) as in the state rebuild -- and a state without a
  token is refused before the host matters, so only a hand-built state reaches the branch with a
  request to send, as the unit suite's states do. The literal now names only the host of a
  request that is refused for its missing token (next bullet), so no request goes to it. An
  `Environment` the cloud table does not know throws from `Get-OERCloudEndpoint`, which never falls
  back to the public row; `Initialize-OERAuth` validates the name, so a real state cannot hold one,
  and the unit suite pins that no request is sent for it.
- **A request is never sent without an ARM token (BL-65, BL-96; decision A8).** A session with no
  ARM token -- no state at all, no `ArmToken` key, a null token, an empty `SecureString` or a blank
  one -- used to send `Authorization: Bearer ` with nothing after it: to the public cloud when there
  was no state, and for the state `Initialize-OERAuth` leaves after it drops the token. ARM would have
  answered it 401 (never measured). `Invoke-ArmCall` now refuses it directly after the `$Plain = ...` materialization and
  before the request is built: `[string]::IsNullOrWhiteSpace($Plain)` throws the **existing**
  `ArmTokenAcquisitionFailed` (category `AuthenticationError`, target the request path), whose
  message says no request was sent and names `Connect-OER -IncludeARM`, with the app-only route
  spelled out. The id is reused on purpose (A8: no new ErrorId, no new public value) -- it already
  means "the session holds no ARM token it can use".
  **The check reads `$Plain`, not the state, and that is what keeps gate 10 green.** The gate counts
  exactly two bearer markers in `Invoke-ArmCall` -- the `$Plain = ...` assignment and the one
  `.ArmToken` read -- and requires both after the supersession gate. An empty plaintext is exactly
  "no token" for all the shapes (measured: `[System.Net.NetworkCredential]::new('', $null).Password`
  and an empty `SecureString` both give an empty string without an error, and a blank one gives the
  blanks back), so the test needs no second `.ArmToken` read, and `$Plain = $null` is not a marker
  since the gate excludes a `$null` right-hand side. The refusal therefore stands after both gates: a
  latched command still reads `SignInRefused` and a superseded one `SignInSuperseded`, never the
  token refusal. The `return` after the `throw` is load-bearing like the one after each gate: under
  `-ErrorAction SilentlyContinue`, with no `try` up the call stack, a function carries on past its
  own `throw`, to the request. The `$Plain = $null` inside the block clears the plaintext of a blank
  token before the throw; no test can observe it, since the variable is local, and it is kept by
  review.
  **Proofs** (`tests/Unit/Private/Invoke-OERArmRequest.Tests.ps1`): the Describe "sends nothing
  without an ARM token (BL-65, BL-96)" drives the five shapes, the two order tests, the 401 retry
  after a refresh that leaves no token (one request, never the retry) and a control that sends with a
  token; "takes its host from the session's cloud (BL-65)" drives the host; and "... outside any try
  (BL-65, BL-96)" runs the wrapper under `-ErrorAction SilentlyContinue` in a runspace with no `try`
  (`Invoke-OERWithConfirmAnswer`) for a state without the key, a blank token and no state, with
  `ARM CALLS: 0` and `ArmTokenAcquisitionFailed` the only record. **Mutations**, each run on a copy
  of `source/`: deleting the whole block turned the five shapes, the 401 test and the three
  no-`try` tests red (9); deleting only the `return` turned the three no-`try` tests red and nothing
  else, which is the proof that Pester's own `try` hides it; `IsNullOrEmpty` for `IsNullOrWhiteSpace`
  turned the blank shape and its no-`try` twin red; deleting the `elseif` host branch turned the
  USGov, China, USGovDoD, dropped-url and unknown-cloud tests red; passing `Environment` on without
  the `Global` default turned the three missing-or-empty-`Environment` tests red; making the session's
  own `ArmResourceUrl` lose to the cloud table turned the precedence test red; and moving the block
  with the materialization above the supersession gate turned the supersession order test and B6 red,
  and above both gates also the latch order test and A6 -- and, against a scratch project root (the
  gate reads `source/` from its own checkout), gate 10's "materializes the bearer token after both"
  test in both cases. One mutation is equivalent and stays: dropping the `$script:_OERAuthState`
  condition of the `elseif` changes nothing, since no state reads `Global`, whose ARM host is the same
  string as the `else` literal; the literal stays all the same, as the documented fallback and
  gate 7's exemption by shape.

Verified 2026-08-25 by grepping the whole tree (`grep -rno 'api-version=[0-9-]*' source/`, 43 hits):
managementGroups 5 real call sites, the Azure PIM surface 13, roleDefinitions/roleAssignments 10,
subscriptions 3, resources/resourceGroups 9 -- 40 real request-path sites in total, plus 3 more that
appear only inside `Invoke-OERArmRequest`'s own comment-based help (`.PARAMETER Path`/`.EXAMPLE`
strings, not live call sites). Regenerate this table with the same grep whenever a new ARM endpoint
is pinned or an existing api-version is bumped -- do not hand-edit the counts without re-running it.

## sovereign-clouds

Sovereign-cloud support (GCC High / DoD / China; issue #81) added `Get-OERCloudEndpoint`, an
`-Environment` parameter on `Connect-OER` and `Initialize-OERAuth`, a `Get-OERGraphServiceRoot`
helper for the two member-add cmdlets that build an absolute `@odata.id` bind reference by hand, and
an optional `Environment` key on the Tenant Profile schema. See
[#auth-state](#auth-state) for the cache-key change and [#arm-transport](#arm-transport) for the ARM
side.

**The load-bearing fact underneath all of it is that AzAuth's `Get-AzToken` has no authority
parameter at all.** A spike settled the question by reflection and IL disassembly against the exact
shipped AzAuth 2.9.0 binaries. What follows is recorded as EVIDENCE, not as a conclusion someone
merely asserted -- a later reader auditing this design should be able to tell a measured fact from an
assumption.

1. `Get-AzToken`'s real parameter list, reflected off `AzAuth.PS.dll`: `-Resource -Scope -Tenant
   -Claim -ClientId -TokenCache -UseUnprotectedTokenCache -Username -TimeoutSeconds
   -CredentialPrecedence -Interactive -Broker -DeviceCode -ManagedIdentity -WorkloadIdentity
   -ExternalToken -AzurePipelines -ServiceConnectionId -SystemAccessToken -ClientSecret
   -ClientCertificate -ClientCertificatePath -Force`. No `-Environment`, `-Authority` or `-Instance`
   in any of its eleven parameter sets.
2. Azure.Identity 1.19.0 (shipped inside AzAuth 2.9.0) reads `AZURE_AUTHORITY_HOST`.
   `Azure.Identity.EnvironmentVariables.AuthorityHost` is a property, not a static field, so its
   getter runs on every read. Measured against a fresh `TokenCredentialOptions()`: the variable
   unset gives `https://login.microsoftonline.com/`; set to `https://login.microsoftonline.us/`
   gives that; set to `https://login.chinacloudapi.cn/` gives that.
3. AzAuth never overrides it -- proven twice, by two independent methods. (a) `set_AuthorityHost`
   appears in the `MemberRef` table of neither `AzAuth.Core.dll` (262 member refs) nor
   `AzAuth.PS.dll` (108); an assembly cannot call a member it does not reference. (b) A full IL walk
   of all 224 methods in `AzAuth.Core.dll` -- 2171 resolved member references, 0 methods aborted on
   an unknown opcode, live control returning 16 Azure.Identity credential constructor call sites --
   found zero. Worth recording: an earlier revision of that walker mis-keyed two-byte opcodes,
   aborted early, and reported "none" from a walk that had covered almost nothing -- the control
   figure is what caught it.
4. The authority is baked into a credential instance at construction, with no process-wide
   singleton. Measured on `ClientSecretCredential.Client.AuthorityHost`: four credentials
   constructed under four different environment-variable values each kept their own authority, and
   re-reading the earlier instances after resetting the variable did not change them. This is why
   the variable must be set around the `Get-AzToken` call itself, not once at module load.
5. It crosses AzAuth's private `AssemblyLoadContext`. `AzAuth.PS.dll` ships
   `PipeHow.AzAuth.LoadContext.DependencyAssemblyLoadContext`. Modelled by loading `Azure.Identity.dll`
   into an isolated `AssemblyLoadContext` and setting the environment variable from PowerShell: the
   ALC-loaded `TokenCredentialOptions.AuthorityHost` followed the variable in all three cases tried.
6. **Condition -- `-TokenCache` must never be passed to `Get-AzToken`.** `AzAuth.Core` contains
   exactly one hardcoded authority, in `CacheManager.InitializeCacheManagerAsync`, disassembled as
   `PublicClientApplicationBuilder.Create(...)` then `ldc.i4.1` (`AzureCloudInstance.AzurePublic`,
   the first argument of the `WithAuthority(AzureCloudInstance, String, Boolean)` overload; the
   second `ldc.i4.1` is `validateAuthority`). That path is reached only when `-TokenCache` is
   supplied, guarded by `String.IsNullOrWhiteSpace(tokenCache)` and a `brtrue` past the branch. Gate
   7 in [#static-source-gates](#static-source-gates) machine-checks that no call site ever passes it.
7. **Condition -- `-Force` is mandatory on a cloud switch.** `TokenManager.credential` is a static
   field. The `ClientSecret`, `DeviceCode` and `ManagedIdentity` paths reuse it whenever
   `credential is <SameType> && previousClientId == clientId` -- neither the tenant nor the
   authority is part of that reuse condition. `Interactive` and `ClientCertificate` construct
   unconditionally. `GetAzToken.BeginProcessing` disassembles to `get_Force` / `get_IsPresent` /
   `brfalse.s` / `call TokenManager::ClearCredential`, so `-Force` is the only supported way to drop
   the cached credential; `TokenManager` and `ClearCredential` are both internal and live in that
   private ALC, so nothing outside AzAuth can reach them directly. `Initialize-OERAuth` tracks the
   last authority it attempted in `$script:_OERLastAuthorityHost` and passes `-Force` whenever the
   effective authority differs from it. The same static-credential reuse this item measures for a
   cloud switch is also why a same-session TENANT switch needs its own handling; see
   [Switching tenants in one process](#switching-tenants-in-one-process) below.
8. The Graph half, from `Get-MgEnvironment` on the pinned Microsoft.Graph.Authentication 2.36.0:
   `Global` -> `login.microsoftonline.com` / `graph.microsoft.com`; `USGov` ->
   `login.microsoftonline.us` / `graph.microsoft.us`; `USGovDoD` -> `login.microsoftonline.us` /
   `dod-graph.microsoft.us`; `China` -> `login.chinacloudapi.cn` / `microsoftgraph.chinacloudapi.cn`.
   It also lists `DelosCloud`, `BleuCloud` and `GovSGCloud`, deliberately left out of
   `Get-OERCloudEndpoint`: none of the three has an Azure Resource Manager counterpart in this
   design, and none has a customer behind it.
9. **What the spike does NOT prove:** that a request actually travels to the authority the variable
   names. That needs a network hop and was deliberately not done as part of the spike; it is a check
   in the live-verification checklist instead, not a claim this document makes.

**From AzAuth 2.10.0 onward, items 2 and 5 must be re-measured in `Azure.Core.dll`, not in
`Azure.Identity.dll`.** Both items stay true exactly as written, since both are scoped to the
Azure.Identity 1.19.0 binary shipped inside AzAuth 2.9.0 -- but the METHOD they describe now points
at an empty file. MEASURED: the `Azure.Identity.dll` 1.21.0 that AzAuth 2.10.0 pulls in is a
57-entry type-forwarding facade with one TypeDef and zero method bodies; the implementation moved
into `Azure.Core.dll` 1.57.0, and `AzAuth.Core.dll` 2.10.0 no longer references `Azure.Identity` at
all. Anyone re-running the spike against a 2.10.0 install will open `Azure.Identity.dll`, find it
empty, and could conclude the behaviour is gone. It is not: DECOMPILED, every load-bearing method
was re-read in `Azure.Core` 1.57.0 -- the `AuthorityHost` property getter, `AzureAuthorityHosts` and
its four host literals, `IdentityCompatSwitches`, and the whole `TenantIdResolver` family with its
ordinal-case-insensitive tenant compare and its refusal string -- and all of them are byte-identical
to 1.19.0's. AzAuth's own two assemblies are IL-identical across that bump; see
[Switching tenants in one process](#switching-tenants-in-one-process) below for that comparison and
for which AzAuth version each measurement in this file describes.

Two standing risks, recorded rather than resolved:

- **PIM-for-Groups stays pinned to the Graph `beta` endpoint** ([#pim-beta-pin](#pim-beta-pin)), and
  beta endpoint availability in US Government and China clouds is not established. A sovereign
  tenant that needs PIM-for-Groups may find the pinned beta path behaves differently, or not at all,
  from the commercial cloud this module was built and tested against.
- **Nothing in this feature has been verified against a live sovereign tenant.** The spike proves
  what the AzAuth and Azure.Identity binaries DO, entirely offline; it does not prove that a real
  sign-in against a real GCC High, DoD or China tenant succeeds end to end. That is deliberate --
  SECURITY rule 1 forbids Claude and CI from making live calls against a real tenant -- and it means
  this whole feature carries an unpaid live-verification debt until an operator with access to a
  sovereign tenant runs it by hand.

## odata-escaping

`ConvertTo-OERODataFilterValue` is the single owner of OData filter-value escaping: double the
embedded single quote, then percent-encode per RFC 3986. Any Graph display-name lookup that
interpolates a caller-supplied value into a `$filter=... eq '...'` URL must go through it.

Deliberate exceptions that must NOT use it:

| Site | Why it is exempt |
|---|---|
| `New-OERAccessReviewScopeQuery` | The filter goes in a JSON request body, not a URL. |
| `Get-OERCatalogResourceRole` | Its structural slashes and parentheses must survive unencoded. |
| `Get-OERPimGroupPolicyId` | The value is a GUID and cannot carry reserved characters. |
| `-Filter` passthrough branches | The caller supplies a whole filter expression, not one value. |

The `-Filter` passthrough branches -- `Get-OERGroup`, `Get-OERAdministrativeUnit`,
`Get-OERAccessReviewDefinition`, `Get-OERCatalog`, `Get-OERAccessPackage`, and the ARM sites --
percent-encode the *entire* caller-supplied filter string with `[System.Uri]::EscapeDataString`
rather than a single interpolated value. The last two were the outlier until commit `51ae59d` fixed
them. Every passthrough branch is encoded now, so **a new one that is not is a bug, not the house
style**.

## reviewer-scope-query

`Resolve-OERReviewerScopeQuery` is the single owner of the access review reviewer scope query
grammar. Every read-side site that turns a live `accessReviewReviewerScope` back into a reviewer
calls it -- `Get-OERInventory`'s projection and `Resolve-OERAccessReviewChange`'s live-state diff.

Never re-implement the `'^/users/([^/]+)$'` / `'^/groups/([^/]+)'` pair inline. Ten inline copies is
exactly what let a single Graph behaviour break the export and the apply engine at once: **Graph
normalizes a reviewer scope on read**, so a query written as `/users/{id}` reads back as
`/v1.0/users/{id}`, which no anchored copy matched.

The helper also owns the distinction the diff depends on: an `Unparsed` scope is a real reviewer
this module cannot express, and is NOT the same as an EMPTY reviewers collection, which is the
documented self-review shape. Collapsing the two writes `SelfReview` over live named reviewers.

`./manager` is matched FIRST, always.

## duration-vocabulary

`-Duration` is a raw ISO 8601 string; `-DurationDays`/`-DurationHours` are whole-unit ints.

- `ConvertTo-OERDuration` is the sole int-to-ISO encoder.
- `ConvertFrom-OERDuration` is the sole ISO-to-int decoder on the read side. It parses ANY ISO 8601
  duration via `[System.Xml.XmlConvert]::ToTimeSpan()`, not just the day/hour forms this module
  itself emits, and returns `$null` -- never a truncated value -- for anything that is not a whole
  number of the requested unit.
- `Resolve-OERDurationInput` is the sole normalizer for a parameter that must accept both forms.

`-DurationInDays`, `-EligibleDuration`, ... are the canonical (pre-existing) parameter names.
`-DurationDays`, `-EligibleDurationDays`, ... are the module-standard aliases added by audit PR6
(#31). **Never rename a parameter without leaving the old name as an `[Alias()]`.**

Note also that PIM-for-groups rejects an eligible duration of `P1Y`; use `P365D`.

## declared-property

`Test-OERDeclaredProperty`/`Test-OERDeclaredNull` are the single owners of the apply engine's
declared-value rule.

A structure-document property is "declared" only when it is present and not `null`
(`Test-OERDeclaredProperty`). An empty string or an empty array still counts as declared, since
`""` clears a description and `[]` asserts an empty list -- but an explicit `null` means exactly
what an omitted key means.

`Test-OERDeclaredNull` isolates the narrower "explicitly null, not merely absent" case that a
handful of `-Prune` child-collection handlers need to treat differently from an omitted key.

Never re-implement `.PSObject.Properties.Name -contains ...` plus a null check inline in a
`Sync-OERStructure*` handler -- call one of these two.

Three shapes this rule gets violated in, all three found under issue #56, and all three producing
permanent non-convergence rather than a visible error:

- **A read-modify-write splat gated on CONTENT rather than declaration.**
  `Sync-OERStructureAccessPackage` bound `-ApprovalStage` only when `@($Parts.Stages).Count -gt 0`,
  so a declared `"approvalStages": []` reached `Set-OERAccessPackageAssignmentPolicy` as an OMITTED
  parameter -- and that cmdlet GETs the live policy and hands it to `ConvertTo-OERPolicyBody` as
  `-Existing`, where an omitted `-ApprovalStage` carries the live stages FORWARD. The write never
  cleared them, so the next pass saw the same drift again. `-Existing` is the load-bearing part:
  the two sibling call sites build a body with no live baseline, where bound-empty and omitted
  produce an identical body and the same wrong predicate is invisible. Correct those anyway -- a
  count gate is the wrong predicate everywhere, and a harmless one is a trap for whoever next adds
  `-Existing` to that path.
- **A create-path default gated on TRUTHINESS.** `Sync-OERStructureAccessReview` tested
  `$Item.reviewers` for truth before counting it, and `[bool]@()` is `$false` in PowerShell, so a
  declared `"reviewers": []` short-circuited at that middle clause -- the count test never ran --
  and fell into the omitted-key branch, whose default is `-Manager`. A document asking for a self
  review got a manager review, and with no `fallbackReviewers` the handler reported `Failed` and
  created nothing, on every run, forever. Truthiness on the VALUE cannot separate declared-empty
  from absent; only the predicate can.
- **An offline gate asking "declared?" where the requirement is "NON-EMPTY".**
  `Test-OERStructureSchema` passed a document whose `"fallbackReviewers": []` sat beside a manager
  reviewer, because the declared predicate says a declared-empty array IS declared -- while
  `Sync-OERStructureAccessReview` collects its fallback reviewers under a truthiness test, finds none
  in `[]`, and reports `Failed` with nothing created. The document validated clean with zero findings
  and could never apply, on every run, forever. The declared predicate answers "did the document
  speak about this key", not "does it supply a usable value": where the requirement downstream is a
  NON-EMPTY list, declaration has to be paired with a count -- and with the declaration test in
  FRONT of it, because `@($Node.absentKey)` is `@($null)`, whose `Count` is 1 and not 0.

The offline validator has to move with the handler, and it went wrong in both directions here.
`Test-OERStructureSchema` classified a declared-empty `reviewers` as "uses the manager default" and
demanded `fallbackReviewers` for it; that finding went false the moment the handler read the same
document as a self review. On the fallback side it did the opposite, demanding nothing where the
handler demands a non-empty list. A rule that lives in two places is only half-written until both
places agree.

## property-naming

An identifier is `<Noun>Id`; a display name is `<Noun>DisplayName`. A bare noun must never hold a
display name.

Where a shape historically used another spelling, keep it as an `AliasProperty` registered with
`Update-TypeData -Force` in `suffix.ps1` (mirrored in the dev-mode psm1) rather than storing the
value twice. **Two stored copies drift; an alias cannot.** Alias properties bind through
`ValueFromPipelineByPropertyName` and serialize with `ConvertTo-Json`, so they are not a
presentation-only trick.

One caveat found in PR #43: an `AliasProperty` does *not* solve JSON casing. The inventory schema
fix needed the stored property itself renamed -- the prescribed alias approach was a proven no-op
there.

An ARM-scoped object exposes the full ARM resource path as `ResourceId`, never a bare `Id`. This is
not a stylistic choice: `Id` is already claimed, module-wide, by unrelated pipeline-bound
parameters carrying `[Alias('Id')]` -- `-PolicyId` on `Get`/`Set-OERRoleManagementPolicy` and
`-RoleEligibilityScheduleId` on `Enable-OEREligibleRoleAssignment`. `Get-OERResource`,
`Get-OERResourceGroup`, `Get-OERSubscription` and `Get-OERManagementGroup` store `ResourceId`
directly. `Get-OERRoleDefinition` follows the same no-bare-`Id` rule but stores the path the other
way round: `RoleDefinitionId` is the one STORED value (so a piped role definition still binds
`-Role` on `New-OERRoleAssignment`, and its PIM siblings, through that alias), and `ResourceId` is
registered as an `AliasProperty` of it in `suffix.ps1` rather than a second stored copy -- the
one-stored-value-plus-alias rule two paragraphs up, applied to this same shape. Never add an `Id`
alias to any of these five converters.

## alias-declaration-order

The rule above governs the PROPERTY names a converter emits. This one governs the `[Alias()]` list
on the PARAMETER those properties bind to, and it is the reason the two are not interchangeable.

`ValueFromPipelineByPropertyName` resolves the parameter NAME first, then the aliases in
DECLARATION ORDER, first match wins. So the order inside `[Alias('GroupId', 'Id', 'DisplayName')]`
is load-bearing, not cosmetic: a `ConvertTo-OERGroupMember` object carries BOTH a stored `GroupId`
(the parent group) and an `Id` (an `AliasProperty` of `PrincipalId` -- the MEMBER's own object id).
An `Id`-before-`GroupId` list on any `-Group` parameter therefore binds the piped principal in place
of the piped group, and on `Remove-OERGroup` (`ConfirmImpact = 'High'`) that means
`Get-OERGroupMember ... | Remove-OERGroup` deletes the PRINCIPAL's tenant object rather than the
group. The same collision exists on `-AdministrativeUnit` with a piped administrative-unit member.

Two AST-driven cohort suites machine-check it -- `Unit/Public/GroupAliasOrder.Cohort.Tests.ps1` and
`Unit/Public/AdministrativeUnitAliasOrder.Cohort.Tests.ps1`. Both discover their carriers from the
source AST rather than from the built module, so a new carrier is covered without editing them and
an exact-count assertion fails loudly if one is added with the wrong order or silently dropped.

Note the asymmetry with `#property-naming`: the converter is told to store the SPECIFIC name and
alias the generic one, and the parameter is told to declare the SPECIFIC alias first. Both rules
point the same way -- the generic `Id` is always the fallback, never the thing that wins.

## scope-pipeline-binding

`-Scope` deliberately does not bind from the pipeline on every Azure cmdlet, and the split is by
design, not an oversight (`A-scope-pipeline-binding-inconsistent`).

Two different object shapes exist in this module, and only one of them is meant to feed `-Scope`:

- **Assignment-shaped objects** (`RoleAssignment` and its PIM siblings -- `ActiveRoleAssignment` /
  `RoleAssignmentSchedule`, `EligibleRoleAssignment` / `RoleEligibilitySchedule`) represent an
  existing assignment INSTANCE. They carry a `Scope` property (the scope the assignment already
  applies at), which feeds the four cmdlets that actually bind `-Scope` from the pipeline --
  `Enable-OEREligibleRoleAssignment`, `Disable-OEREligibleRoleAssignment`,
  `Remove-OERActiveRoleAssignment` and `Remove-OEREligibleRoleAssignment` -- which locate the live
  assignment by principal, role and scope rather than by a single id. `Set-OERRoleAssignment` and
  `Remove-OERRoleAssignment` are a narrower case still: they have NO `-Scope` parameter at all and
  act on `-Id` alone (the full `RoleAssignmentId`, which already embeds the scope), so they need no
  `Scope` property to bind from the pipeline in the first place.
- **Scope-DEFINING objects** (`Resource`, `ResourceGroup`, `Subscription`, `ManagementGroup`,
  `RoleDefinition` -- see `#property-naming` above) represent the ARM resource itself, before any
  assignment exists at it. They carry only friendly properties (`SubscriptionId`, `ResourceGroup`,
  `ManagementGroupName`, `ResourceType`, `ResourceName`) and never `Scope` or a bare `Id`, and feed
  the create/read cmdlets (`New-`/`Get-OERRoleAssignment` and friends) by those friendly properties,
  which `Resolve-OERScope` recomposes into a scope string.

Binding `-Scope` itself from the pipeline on a scope-DEFINING object would be wrong twice over: none
of `Resource`/`ResourceGroup`/`Subscription`/`ManagementGroup` even carries a raw `Scope` property to
bind from, and if one did, that value would be the object's OWN ARM path -- not a scope a caller
composed from friendly parts, which is the job the friendly properties already do correctly.

## guid-predicate

`Test-OERGuid` is the single GUID predicate. Never re-implement the canonical
`^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z` regex inline.

Since Sprint 10 step 5 (BL-101) the predicate ends in `\z`. With `$`, a value followed by one line
feed passed (a carriage return and line feed already failed), while an ECMA-262 validator of the
schema's pattern refused it, so the offline validator and such a validator disagreed on a `tenantId`
read from a file or a here-string with a stray line break. PowerShell's own `Test-Json`, whose
regular expressions are .NET's, accepts that value like the old predicate did; only a strictly
ECMA-262 validator refuses it.

What changes module-wide: every caller asks `Test-OERGuid` whether a value is an object id, so a
value followed by a line feed now takes each caller's name path instead -- a lookup by name, or a
refusal such as `InvalidPrincipalId` for `-PrincipalId`; a `-TenantId` goes to the tenant lookup.

The deliberate exception is the wider `-as [guid]` cast in `Get-OERInventory` and `New-OERGroup`,
which intentionally also accepts braced, parenthesised and dash-less forms that `Test-OERGuid`
rejects. Do not migrate those two call sites to `Test-OERGuid`. Since Sprint 9 step 6 (ruling R14)
two more read a group's `administrativeUnit` with the same cast, on purpose, so that they decide
between an object id and a display name exactly as `New-OERGroup` does: the created-membership match
in `Sync-OERStructureAdministrativeUnit` and the unit placement check (Rule 12) in
`Test-OERStructureSchema`. Do not migrate them either.

## mfa-authcontext-exclusion

Entra PIM treats an enabled Conditional Access authentication context and
`MultiFactorAuthentication` on activation as mutually exclusive: a role or group activation policy
cannot require both at once. The Entra portal enforces the same rule in its own UI by only ever
offering the tenant's *published* authentication contexts in the picker, so an admin clicking
through the portal cannot even construct the invalid combination -- an API caller can.

**The gap this rule closes is issue #54.** The Azure PIM (ARM) write path already reconciled this
combination; the Graph PIM-for-groups write path did not. That asymmetry was not a design choice,
it was a capability gap: `New-OERPimRuleSet` is a from-scratch, surgical per-rule patch builder for
`Set-OERGroupPimPolicy` -- it emits a rule object only for the parameter the caller actually bound,
with no read of the policy's current state and therefore no visibility into whether MFA or a
context was already live. It could not reconcile a collision it could never see.
`Resolve-OERPimActivationConflict` is now the single, transport-free decision function both write
paths (and the apply diff) call into: given what the caller asked for and what the resulting
policy state would be, it returns one of `Conflict`, `ClearMfa`, `DisableAuthContext` or `None`,
and the caller applies that decision in its own idiom.

**The apply diff (`Resolve-OERGroupPimPolicyChange`) had to change for the same reason the write
path did.** The diff builds its `Set-OERGroupPimPolicy` call by comparing each field independently
against the current policy and splatting only the fields that differ. A document that declares
both `authenticationContextId` and `MultiFactorAuthentication` in `activationEnablement` would,
before this change, see both fields as "different from current" on run 1 and send both -- the
write path would then clear MFA per the rule above. Run 2 would see the document still declares
MFA but the live policy no longer has it, so it re-sends MFA and the write path clears the context
instead. Every subsequent run repeats the previous run's correction: the plan never reaches
`Unchanged` and a live security control toggles on every apply. The diff now runs the same
conflict resolution the write path runs, so it converges to whichever side the resolution settles
on.

**The `DisableAuthContext` arm, and the `ClearMfa` arm, both deliberately break the apply engine's
presence semantics** -- each can queue a `SetParams` field the input document never declared. That
is correct, not a bug: PIM cannot hold the conflicting combination regardless of what the document
says, so the write path will change that field no matter what. A plan that printed `Unchanged` for
a field the apply is about to overwrite would be lying to the operator; naming the field it is
about to change is the honest plan.

**The diff also says why, and the group handler warns with it (Sprint 9 step 6, BL-17).**
`Resolve-OERGroupPimPolicyChange` returns `ConflictReason`: the resolution's `Reason` when its
`ClearMfa` arm actually changes the enablement list or its `DisableAuthContext` arm runs, and `$null`
otherwise, including when the reconciled list is already the live one. Because the diff hands
`Set-OERGroupPimPolicy` parameters that are already reconciled, the cmdlet finds no conflict and
writes no warning about the pair, so before this step a real `Invoke-OERStructure` run said what it
cleared or disabled only in the result row's Detail. `Sync-OERStructureGroup` now writes
`ConflictReason` as a warning before its `$Caller.ShouldProcess`, in a real run as under `-WhatIf`:
`Policy 'ID': reason`, with the id of the policy it read, or
`pimPolicy (ACCESSTYPE) of group 'NAME': reason` when no policy was read. The directory-role handler
takes the same decision, through `Resolve-OERPimActivationConflict`, under `-WhatIf` only: its diff
(`Resolve-OERRoleManagementPolicyChange`) does not reconcile the pair, so
`Set-OERDirectoryRoleManagementPolicy` reconciles it itself and warns in a real run. Why the two
differ: [#warning-before-confirmation](#warning-before-confirmation), Sprint 9 step 6, ruling R5.

**The schema gate (`Test-OERStructureSchema`) treats the two sections differently on purpose.**
The `roleManagementPolicies` (Azure PIM) section raises a hard `Error` for the same collision,
because ARM has never reconciled it for that section and an apply would fail outright against a
live tenant. The `groups` (PIM-for-groups) section raises only a `Warning`: those documents
already validated successfully before this change (the offline schema never checked the
combination), and the apply engine now reconciles them instead of failing, so promoting this to an
`Error` would break documents that work today. A schema-only fix -- reject the combination offline
and leave the write and diff paths alone -- was considered and rejected for the same reason: it
would not close the write-path gap that is issue #54's actual defect, only hide it from
`Test-OERStructure` while `Invoke-OERStructure` kept flapping.

**`-ResolveUnrequestedConflict` exists only for the ARM caller, and only ARM needs it.** ARM's
`roleManagementPolicies` PATCH is a read-modify-write over the *entire* rule set
(`Resolve-OERPolicyRulePatch`): every apply run submits all rules, including ones the caller did
not touch this time, so ARM re-validates a pre-existing invalid combination even when the change
in this call is unrelated to either side of it. Graph's PIM-for-groups PATCH is per-rule:
`Set-OERGroupPimPolicy` only ever sends the rule(s) the caller's parameters touched, so a
combination the caller did not raise this call is left alone rather than resolved unasked. This is
the one deliberate behavioural difference between the two transports built on the same shared
decision helper.

**Graph does not validate `claimValue` against the tenant's actual authentication contexts at
all.** An unknown or unpublished context id is accepted silently on write; the failure only
surfaces later, for an end user, at activation time -- the least convenient place to discover a
typo, and exactly what the portal's published-only picker exists to prevent. This is why
`Set-OERGroupPimPolicy` calls the new `Get-OERAuthenticationContext` to validate the claim value
before writing. That read degrades to a `Write-Warning` rather than a hard permission requirement
on purpose: `RoleManagementPolicy.ReadWrite.AzureADGroup` (the write permission this cmdlet
already needs) does not imply `AuthenticationContext.Read.All` (a separate, independently
consented permission), so an automation identity can be fully authorized to make the write and
still fail the validation read. A failed READ is not a refusal -- the caller may already know the
context id is valid and must still be able to set it.

**Graph enforces the exclusion ASYMMETRICALLY, so the PATCH ORDER of the two rules is
load-bearing.** The design above reasoned from "Graph accepts both rule PATCHes individually and
the last writer wins". That premise is true in only ONE direction, and the first live run of the
reconcile against a real tenant proved it:

- ENABLING an authentication context while `MultiFactorAuthentication` is already on the activation
  enablement rule is **accepted**. That silent acceptance is the entire defect issue #54 exists to
  reconcile -- Graph will happily store the combination PIM cannot honour.
- ENABLING `MultiFactorAuthentication` while an authentication context is already enabled is
  **rejected**, with `MfaAndAcrsConflict: The Mfa and Acrs policy settings cannot be enabled
  simultaneously.`

`Set-OERGroupPimPolicy` patches one rule per request, so the rule that goes SECOND is validated
against the state the first one left. `New-OERPimRuleSet` emits `Enablement_EndUser_Assignment`
before `AuthenticationContext_EndUser_Assignment`, and the patch loop followed that emitted order.
For the `ClearMfa` direction that order is correct by luck: MFA is removed first, so the context is
enabled against a policy that no longer carries the MFA flag. For the `DisableAuthContext`
direction it was exactly wrong. The observed live run, against a policy holding context `c1` and
`{Justification}`:

    Set-OERGroupPimPolicy -Group $Id -AccessType member -ActivationEnabledRules MultiFactorAuthentication,Justification

warned that `c1` was disabled by the reconcile, then warned
`Rule 'Enablement_EndUser_Assignment' was not applied: MfaAndAcrsConflict: ...`, and reported a
partial apply. The MFA PATCH had been sent FIRST, while `c1` was still enabled, and Graph refused
it; only afterwards was `c1` disabled. The caller asked for `MultiFactorAuthentication, Justification`
and the policy ended with `{Justification}` and no context -- NEITHER the old protection nor the
requested one in force. A reconcile that leaves the tenant less protected than either the before or
the after state is worse than no reconcile.

The fix is a rule ordering applied immediately before the patch loop -- the loop is where transport
sequencing belongs. When the rule set carries both rules, they are ordered by what the
authentication-context rule DOES: `isEnabled = $false` goes FIRST, `isEnabled = $true` goes LAST.
Every other rule keeps its emitted position. The ordering is deliberately NOT in `New-OERPimRuleSet`:
that helper is a pure, shared builder owning rule SHAPE, and a rule set built for a different
transport must not inherit this transport's sequencing. It now has one owner, the private
`Get-OERPimRulePatchOrder`, called immediately before the patch loop by both Microsoft Graph PIM
write paths that PATCH one rule at a time: `Set-OERGroupPimPolicy` (where the ordering was first
found and fixed) and `Set-OERDirectoryRoleManagementPolicy` (Sprint 6 step 3), which needs the exact
same ordering for the same reason -- it too sends one PATCH per changed rule.

Three consequences worth keeping in mind:

- **This is not a reconcile-only concern.** A caller binding both parameters explicitly
  (`-AuthenticationContextId '' -ActivationEnabledRules MultiFactorAuthentication`) against a policy
  with a live context produces no `Resolution` at all, builds both rules straight from its own
  binding, and hit the identical rejection. The apply engine inherits it through any document
  declaring MFA together with `authenticationContextId: ""`. The ordering rule is therefore stated
  over the RULE SET, not over the reconcile.
- **The conflict-removing half is now always patched first**, in both directions, but that only
  makes the mutually exclusive state unreachable-by-declining-in-order for `ClearMfa` -- there,
  declining the first prompt and accepting the second is what the declined-partner guard still
  warns about. For `DisableAuthContext` the same guard is now wrong in both halves: decline the
  context-disable and accept the MFA prompt, and the accepted `Enablement_EndUser_Assignment` PATCH
  is sent while the context is still enabled, so Graph rejects it with `MfaAndAcrsConflict` -- the
  policy keeps its context, never gains MFA, and the guard still warns that the policy "still
  requires both multi-factor authentication and an authentication context," a state Graph no longer
  allows to exist. Accept the context-disable and decline the MFA prompt instead, and the policy
  ends with neither control while the guard stays silent, because it tests for the opposite
  asymmetry (`$Sent` containing the partner rule but not the reconciled one). The guard was derived
  against a fixed rule order and was never re-derived once the order became direction-dependent;
  reworking it to warn on either split of the pair, with direction-appropriate wording, is an open
  follow-up and not done in this branch. Both shapes require explicit interactive `-Confirm` consent
  per rule and are unreachable from `Invoke-OERStructure`, which applies with `-Confirm:$false`.
- **Do not "tidy" the ordering back into a fixed sequence.** A fixed order cannot be right for both
  directions, and the direction that is wrong fails only against a live tenant -- every mocked test
  that does not assert on PATCH ORDER passes either way.

## pim-rule-pair-put-back

Sprint 9 step 4 (BL-09, BL-10). `Send-OERPimRulePatch` is the single owner of sending a Microsoft
Graph PIM rule set one PATCH per rule, for `Set-OERGroupPimPolicy` and
`Set-OERDirectoryRoleManagementPolicy`. It owns two rules the section above leaves open: the first
rule of the MFA / authentication-context pair is put back when Graph rejects the second, and no
warning is written between the first PATCH and the last put-back.

**Why the pair is put back.** `AuthenticationContext_EndUser_Assignment` and
`Enablement_EndUser_Assignment` together decide whether activation requires multi-factor
authentication or an authentication context. The patch order above sends the conflict-removing half
first, so when the second half is then rejected the first has already been applied: a context
disabled, or MFA removed, and the control the caller asked for never arrived. The policy is left
with NEITHER control, which is worse than the state before the call and worse than the state the
caller wanted. `Set-OERDirectoryRoleManagementPolicy` already put the accepted half back, with logic
written inline in the cmdlet; `Set-OERGroupPimPolicy` did not, and reported the accepted rule as
applied. One helper replaces the inline copy and gives the group cmdlet the same behaviour, so the
two cannot drift again: `tests/Unit/Private/Send-OERPimRulePatch.Tests.ps1` holds by AST that
neither cmdlet sends a rule PATCH of its own and that each calls the helper once. A rejected FIRST
half needs nothing, since the second was validated against an unchanged policy. The pair counts
only when both rules are in the confirmed set, so a DECLINED half is never put back (the
declined-partner guard of the section above covers that case). A put-back that is itself rejected
leaves the first half applied: the helper reports why, and the cmdlets say what activation now
requires. The group cmdlet says it may now require neither control; the directory cmdlet reads the
object it just returned and names what that role now requires.

**A rule that was put back is not reported as changed.** The group cmdlet builds the property list
of its result from the rules it sent minus the one put back, so that rule adds no property to the
result. `Applied` is `$false` in any case, since a rule was rejected, and the `PolicyRulesRejected`
error names the put-back, or its failure.

**Why the group cmdlet confirms every rule before it sends any.** The helper takes the confirmed
set and asks nothing itself, so the cmdlet answers every `ShouldProcess` prompt first, in patch
order, and sends afterwards. It used to prompt and send rule by rule. The put-back also needs the
first half's live version, which has to be read BEFORE the first PATCH changes it, and not under
`-WhatIf` or when a prompt was declined, where nothing, or not the whole pair, is sent. With the
confirmed set known first, the cmdlet reads the first half only when both pair rules were accepted,
so `-WhatIf`, a declined prompt and a declined partner make no first-half read of their own. (A
reconcile read, below, runs before the prompts and is made under `-WhatIf` as well.) The
declined-partner guard of the section above reads the same set and is unchanged.

**Where the first half's live version comes from.** The two reconcile reads the group cmdlet may
already make are exactly the first half in each direction: `ClearMfa` reads the enablement rule and
sends it first, `DisableAuthContext` reads the authentication-context rule and sends it first. Each
read is kept by rule id and reused, so a reconcile adds no read. A call that supplies both
parameters explicitly makes no reconcile read, and costs one: a single GET of the first rule, after
the prompts and before the first PATCH. A failed read costs the put-back and nothing else, so it is
a warning, written at once -- before any PATCH, so a `-WarningAction Stop` caller stops with nothing
sent -- and the call goes on. Should the second half then be rejected, the helper sends no request
and reports that the value before the call was not read. The directory cmdlet already holds every
live rule from its policy read.

**Why the put-back body is the live rule minus `@odata.context`.** A single-rule read carries an
`@odata.context` annotation that describes the response and is not part of the rule. The helper
sends the live rule as a new hashtable made by a JSON round trip, always, so the caller's copy is
never changed, and removes that key. This is a design decision, not a measured one: the put-back
cannot be provoked live, as below.

**Why the helper returns its messages instead of writing them.** A caller running with
`-WarningAction Stop`, or with `$WarningPreference` set to `Stop`, is stopped by the first
`Write-Warning`. Measured: outside any `try` that ends the whole script (a hosted runspace's
`Invoke()` then throws to its parent), and inside one the caller catches an
`ActionPreferenceStopException`. The directory cmdlet wrote a rejected rule's warning inside its
loop, directly BEFORE the put-back, so a Stop caller was stopped between the rejected rule and the
put-back and left with exactly the half-applied pair the put-back exists to prevent; the group
cmdlet's loop likewise left every later rule unsent. The helper therefore writes nothing -- its body
holds no warning, error, information or host call, which the AST test checks -- and returns
`Warning` in the order the messages arose. Both callers write them directly after it returns,
before the result object, so the first message still stops a Stop caller, but only after every
PATCH and the put-back were sent. The messages that precede the sends, a reconcile reason or a
failed first-half read, are written before the first PATCH on purpose: stopping there sends
nothing. The rejection text now names the policy, and the label differs per cmdlet: the group
cmdlet writes `Rule 'ID' of PIM policy 'ID' was not applied`, the directory cmdlet
`Rule 'ID' of directory role management policy 'ID' was not applied`. The group cmdlet's earlier
wording, `Rule 'ID' was not applied`, survives in the older live-verification checklists and in the
live run quoted above.

**Why `requiredscope.tests.ps1` counts a call to the helper as a write by the caller.** That gate
decides whether a cmdlet writes from the method of the `Invoke-OERGraphRequest` calls in its own
body. The helper receives its path from the cmdlet and carries no path literal, and the two cmdlets
no longer PATCH on their own, so their policy endpoints would have read as read-only and the gate
would have accepted a read scope for a cmdlet that writes the policy. A call to
`Send-OERPimRulePatch` now marks the CALLING function as a Graph writer. Measured by mutation:
without the clause a read-only scope row for either cmdlet passes the gate, with it the gate is red.

**The put-back cannot be provoked live.** The patch order is chosen so that Graph accepts both
halves: the one rejection the exclusion has (enabling MFA while a context is enabled) is exactly
what sending the conflict-removing half first avoids, and no request can be made to fail the second
half on demand. It is check class B: mocked, mutation-proven unit tests with a rejecting transport,
in `tests/Unit/Private/Send-OERPimRulePatch.Tests.ps1` (the helper, both directions), in
`tests/Unit/Public/Set-OERGroupPimPolicy.Tests.ps1` and in
`tests/Unit/Public/Set-OERDirectoryRoleManagementPolicy.Tests.ps1` (the two cmdlets, each under
`-WarningAction Stop` inside a `try` and in a script with no `try`). The decision rests on the
asymmetry recorded in the section above, which was measured live; the put-back itself was not.

## completers

Tab-completion is scriptblock-based, not `IArgumentCompleter` classes -- which is why there is no
`source/Classes` directory even though the loader iterates one.

Each completer is a `Register-ArgumentCompleter` call in `source/suffix.ps1` (appended to the built
psm1 by ModuleBuilder) and **mirrored verbatim** in the dev-mode `source/Omnicit.EntraRBAC.psm1`
loader. A scriptblock authored inside the module keeps module session-state affinity, so it can call
a private helper from both the built and the from-source load path. An `IArgumentCompleter` class
could not.

Rule 2 in CLAUDE.md (fast and offline) is why `Get-OERCommonDirectoryRoleName` is a static curated
list and the live `Get-OERDirectoryRoleNameMap` is not used for completion.

Rule 6 (end-to-end `TabExpansion2` test) exists because a helper that works but is registered on the
wrong command name is the failure mode that actually happens -- a unit test of the helper alone
cannot see it. Audit PR3 (#27) learned that completers cannot be verified by mocked tests at all.

## auth-state

`Initialize-OERAuth` is the single auth entry point and uses AzAuth's `Get-AzToken` for all
credential types. There is no MSAL reflection or hand-rolled token acquisition -- this module does
NOT use the approach from Omnicit.PIM.

1. **Idempotency** -- if `$script:_OERAuthState` already holds a Graph token for the same tenant
   *and* auth identity (AuthMethod + ClientId) with at least 5 minutes remaining, and, when
   `-IncludeARM` is set, a valid cached ARM token, and the process still holds the Graph SDK
   session it connected (see [The Graph SDK session](#the-graph-sdk-session) below), it returns
   immediately with no network call and no prompt.
2. **Graph token** -- `Get-AzToken -Resource 'https://graph.microsoft.com/'`, wired into
   `Connect-MgGraph -AccessToken` as a SecureString.
3. **ARM token (optional)** -- with `-IncludeARM`, a second `Get-AzToken` acquires
   `https://management.azure.com/`. See [#arm-transport](#arm-transport) for why the result is used
   directly rather than through Az.Accounts.
4. **Cache** -- `$script:_OERAuthState` holds `TenantId`, `AuthMethod`, `ClientId`, `Account`,
   `GraphTokenExpiry`, `ArmTokenExpiry`, `ClaimsSatisfied`, plus `TokenTenantId` and
   `ArmTokenTenantId` (below), and `GraphSessionFingerprint`, the fingerprint of the Graph SDK
   session the module connected -- never a token ([The Graph SDK session](#the-graph-sdk-session)
   below).
5. **ACRS step-up** -- see [#graph-wrapper](#graph-wrapper) item 2.
6. **Sign-in latch** -- every entry latches the command that called it, and only a success releases
   it; both transports send nothing for a latched command, refusing each of its requests with
   `SignInRefused`, except that the Graph wrapper's session gate, which comes first, still reports a
   changed session as `GraphSessionChanged`. An entry made while a command OUTSIDE its caller is
   latched is refused before any of that, with no token call and no latch of its own (BL-74). See
   [A command whose sign-in is refused sends nothing](#a-command-whose-sign-in-is-refused-sends-nothing)
   and [A command acts under the session it began with](#a-command-acts-under-the-session-it-began-with)
   below.
7. **Tenant lookup** -- a tenant named by anything other than a GUID or `organizations` is resolved
   to its tenant ID before any token is requested, and every token is checked against that ID, so a
   domain is checked exactly as a GUID is (BL-12). See
   [Switching tenants in one process](#switching-tenants-in-one-process) below.
8. **Session-uncertain marker** -- a sign-in that does not succeed leaves the session uncertain, and
   while it is, a command that names no tenant is refused before it requests a token (A10, BL-89).
   See [A refused sign-in leaves the session uncertain](#a-refused-sign-in-leaves-the-session-uncertain)
   below.
9. **Document tenant** -- an exported structure document names the tenant its Graph token was
   issued for (`tenantId`), and `Invoke-OERStructure` applies a document that names its tenant only
   there: it compares the document with a `-TenantId` that is a tenant ID before the sign-in, and
   with the tenants the session's tokens were issued for after it, and refuses it with
   `DocumentTenantMismatch` (BL-88, A14). It never signs in to the document's tenant. See
   [A document names the tenant it was exported from](#a-document-names-the-tenant-it-was-exported-from)
   below.

The tenant *and identity* part of step 1 is load-bearing: PR #36 closed the audit's only Critical
finding, which was an ARM token surviving a tenant switch. PR #37 then removed the
`-AuthMethod 'Interactive'` default that pushed app-only and managed-identity sessions into a
browser prompt on all 22 ARM cmdlets -- auth now inherits the session identity.

### Requested tenant vs granted tenant

`TenantId` records what the caller **asked for**. `TokenTenantId` and `ArmTokenTenantId` record what
each token was **issued for**, read from `AzToken.TenantId` -- a property AzAuth has always exposed
and this module used to discard while consuming `Identity` and `ExpiresOn` from the same object.

Keep them separate. `TenantId` is the value all three cache-key predicates (`$GraphCached`,
`$ArmCached`, `$ArmIdentityUnchanged`) compare, so repointing it at the granted value would silently
change session-reuse semantics module-wide. The granted values are **evidence**, not cache keys. One
reader does key on the Graph value, for another purpose: since Sprint 9 step 3 the sign-in
identity's tenant term is `TokenTenantId` when it is a GUID (BL-77, under
[A command sends nothing under a sign-in a later command replaced](#a-command-sends-nothing-under-a-sign-in-a-later-command-replaced)).

`Initialize-OERAuth` raises a terminating `TenantMismatch` when the two disagree, before
`Connect-MgGraph` runs and before `$script:_OERAuthState` is rebuilt (and, for ARM, before the token
is cached), so a refused token never becomes a usable session -- the same two-sided placement rule
the `AppOnlySessionCredentialUnavailable` check follows. A refused Graph token leaves nothing
half-built behind. A refused ARM token is the exception the BL-89 paragraph under
[A refused sign-in leaves the session uncertain](#a-refused-sign-in-leaves-the-session-uncertain)
describes: the ARM step comes after the Microsoft Graph half has connected and rebuilt the state (or
answered from the cache), so the session then holds that Graph token -- for the tenant the sign-in
named or, when it named none (Ruling F3, below), for the tenant the Graph token came from -- and no
ARM token from this sign-in. The state is not cleared of an older one: on an ARM-only top-up, or a
rebuild that carried the state forward for the same identity and the Graph token's own tenant (A13,
below), the previous ARM token of that identity and tenant can stay in it.

**Both values compared are GUIDs, whether the tenant was named by GUID or by domain** (BL-12, since
Sprint 9 step 3). The requested side is the tenant ID the request named or, for a tenant named by
domain, the tenant ID the cloud authority's OpenID discovery document resolved it to before any
token was requested -- see **The tenant lookup** under
[Switching tenants in one process](#switching-tenants-in-one-process) below. The token request
itself still names the tenant as given; only the comparison uses the tenant ID. `Test-OERGuid`
gates the GRANTED side, so a granted value that is not a GUID is recorded as it is and not compared.
`'organizations'` names no tenant: nothing is looked up for it, the expected tenant ID is `$null`,
and that term -- one an input falsifies, so it stays mutation-provable -- is what leaves it
uncompared with a requested tenant. Graph and ARM compare against the same tenant ID, so a domain is
refused exactly as a GUID is, by both `TenantMismatch` checks.

**With no tenant named, an ARM token the sign-in acquires is compared with the Graph token** (Sprint
9 step 3, final review M1, Ruling F3). Since BL-77 the sign-in identity's tenant term is the Graph token's tenant, and
that opened one narrow path. In `X -TenantId <GUID> | Y -TenantId organizations` on an interactive
session, Y names another tenant than the state, inherits nothing and signs in afresh: its Graph token
comes from X's tenant and -- at a second prompt answered with another account -- its ARM token from
another. `organizations` has no expected tenant, so the ARM token was never compared, Y's identity
equalled X's, X was not superseded, and X's Azure calls would go out with the other tenant's ARM
token -- the final review's finding; no end-to-end test here runs that pipeline. The same split
existed, older, within one command that names no tenant. So when `$ExpectedTenantId` is `$null` the
ARM token's tenant is compared with `$script:_OERAuthState.TokenTenantId` -- the Graph token the same
call acquired, or the cached one an ARM-only acquisition runs beside -- when both are GUIDs, and a
difference is the existing terminating `TenantMismatch`, raised before the ARM token is cached; its
message names both tenants and says that the two tokens of one session were compared. A named
tenant's ARM token is compared only with the tenant ID it names, as before. The limit: a token whose
tenant AzAuth does not report as a GUID, on either side, leaves nothing to compare. No new error id;
every term of the condition stands on its own line and is mutation-proved
(see the proof under
[A refused sign-in leaves the session uncertain](#a-refused-sign-in-leaves-the-session-uncertain)).

**A renewal carries the ARM token only for the renewed Graph token's tenant** (Sprint 9 step 3
round 1, decision A13, BL-95). The comparison above runs only where an ARM token is ACQUIRED. When
only the Graph token of a session that names no tenant was renewed -- near its expiry, or by a
transport's refresh -- `$ArmIdentityUnchanged` carried the old ARM token into the rebuilt state and
`$ArmCached`, decided on the state at entry, skipped the ARM branch, so the carried token was never
compared with the new Graph token. MEASURED by the scoped re-review of step 3's final fixes, with
mocked tokens: Graph and ARM tokens from one tenant, then the Graph token renewed from another, left
the state's Graph and ARM tenants different with no `TenantMismatch`. On an interactive
`organizations` session that is one human error away -- the renewal's prompt answered with another
tenant's account -- and the session then held tenant B's Graph token beside tenant A's ARM token
under one sign-in identity (BL-77 takes the identity's tenant from the Graph token), so a later
`Invoke-OERStructure -Prune` without `-TenantId` planned against tenant B and removed Azure role
assignments in tenant A. `$ArmIdentityUnchanged` compares the tenant LABEL, and `organizations` is the
label before and after. The rebuild therefore carries the ARM token only when, besides those terms,
the state's `ArmTokenTenantId` equals the new Graph token's tenant and both are GUIDs
(`$ArmTokenKept`, each term on its own line). Otherwise all four ARM fields are dropped, and the ARM
step reads `$ArmTokenKept` beside `$ArmCached`, so the same call acquires a new ARM token under
`-IncludeARM`, compared with the new Graph token (F3, above); without `-IncludeARM` the next call
that needs one acquires it. The direction is the safe one: the cost is an ARM token acquired again --
a second prompt on an interactive session -- where the carry was refused, including for a token whose
tenant AzAuth did not report as a GUID. A named tenant changes nothing in practice, since both tokens
of such a session were compared with the tenant ID it names. The proof is the Describe
`Initialize-OERAuth carries an ARM token over a renewal only for the renewed Graph token's tenant (A13, BL-95)`
in `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, whose header names the mutation each It
catches, and H12 in `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`: with no `try` anywhere,
a Graph-only renewal answered from tenant B drops tenant A's ARM token, and the Azure cmdlet after it
acquires a new one, which is refused against the renewed Graph token, and sends no ARM request.

HISTORY: until Sprint 9 step 3 the comparison was gated on BOTH values being canonical GUIDs. The
requested tenant is very often a verified domain (`contoso.onmicrosoft.com`) while a token always
carries a GUID, so an unconditional comparison would have rejected almost every real sign-in, and
when the request named a domain the mismatch was not detectable from the token alone: the granted
value was recorded and left to speak for itself, and the post-call warning under
[Switching tenants in one process](#switching-tenants-in-one-process) was the only signal.

**A token without a `tid` claim is not checked.** DECOMPILED, and NOT measured: AzAuth's
`AzToken.TenantId` falls back to echoing the REQUESTED tenant when the token carries no `tid` claim.
For a request naming a domain that echo is the domain, which is not a GUID and is not compared; for
a request naming a GUID it is that GUID, which compares equal. Such a token is therefore checked
neither for a GUID nor for a domain. Every token the live runs decoded carried `tid` (see
"Where the granted-tenant value itself comes from" below).

Found live, not by review: three device-code sign-ins against a deliberately nonexistent tenant all
returned working sessions, since the device-code verification page is tenant-independent and the
operator completed it with a real account. The module then held a session whose `TenantId` named a
tenant the token was not issued for -- the same "the cached label stopped describing the token
beneath it" family as the audit's only Critical.

### Switching tenants in one process

Finding F12 asked whether a same-session tenant switch with ClientSecret, DeviceCode or
ManagedIdentity reuses a credential baked against the previous tenant. A spike (2026-09-14) settled
it by reflection, IL disassembly of the exact shipped AzAuth 2.9.0 / Azure.Identity 1.19.0
binaries, and measurement with every call proxied through a local listener that answers every
request with a blocked response, so no live tenant was ever reached. What follows is recorded as
EVIDENCE in the same MEASURED / INFERRED style as [#sovereign-clouds](#sovereign-clouds) above --
never read a label here as stronger than the spike stated it. A live-verification run on
2026-09-15/16 then settled several of the questions the spike could only decompile or infer; those
findings are labelled MEASURED below and name the checklist check that measured them. Two further
labels appear where the run did something other than confirm: RECORDED OBSERVATION, for what the
run showed but cannot establish as a rule, and CONTRADICTED BY MEASUREMENT, for a claim it refuted
outright.

**What changed in Sprint 9 step 3 (BL-12).** This subsection used to record a decision NOT to look
a domain up, since that is a network call of its own. Philip replaced that decision on 2026-10-06
(P-2). A tenant named by domain is now resolved to its tenant ID before any token is requested, and
every token, Graph and ARM, is checked against that ID, so a switch that did not take effect is
refused with `TenantMismatch` whether the tenant was named by GUID or by domain -- see
**The tenant lookup** below. The post-call warning that compared granted tenants, and its tracker,
are retired. The spike's evidence and the live-run tables below are unchanged; the paragraphs that
described the retired warning are kept as history and labelled HISTORY.

**Which AzAuth version each measurement describes, and the re-check against 2.10.0.** The spike ran
against AzAuth 2.9.0 / Azure.Identity 1.19.0. Of the live run, sections 1-4 and 6 of the checklist
ran on AzAuth 2.9.0 and section 5 on AzAuth 2.10.0. The manifest pins 2.9.0 as a MINIMUM, so a user
gets whatever newer binary is on `PSModulePath`, and three load-bearing AzAuth claims -- the
`-Force` condition and the credential-reuse predicate recorded here, and the `-TokenCache`
hardcoded authority recorded as [#sovereign-clouds](#sovereign-clouds) item 6 -- were therefore
re-checked against 2.10.0 by disassembling every method in both shipped AzAuth assemblies and
diffing the result against 2.9.0's. All three hold. DECOMPILED: `AzAuth.Core.dll` and
`AzAuth.PS.dll` are IL-identical between 2.9.0 and 2.10.0 -- the full disassembly of every method,
the complete user-string heap and the complete MemberRef table all diff clean -- so 2.10.0 is a
dependency bump and every claim measured against 2.9.0's binaries carries over unchanged. That is a
metadata and IL comparison, not a runtime measurement; the corroborating MEASURED half is checklist
section 5, which ran the module against 2.10.0 and behaved as this section records. One trap comes
with the newer package and is recorded under [#sovereign-clouds](#sovereign-clouds): from
Azure.Identity 1.21.0 the implementation lives in `Azure.Core.dll`, and `Azure.Identity.dll` itself
is an empty forwarding facade.

**Per credential type, calling `Get-AzToken` a second time for a different tenant with no
`-Force`:**

| Type | Reuses the process-wide credential? | What the reused call does | Does `-Force` fix it? |
|---|---|---|---|
| ClientSecret | MEASURED: yes, for the client id used in the spike. DECOMPILED: the reuse test is an ordinal (case-sensitive) client-id comparison, so this holds whenever the id matches, not only for the one id measured | MEASURED: fails loudly before sending anything -- "The current credential is not configured to acquire tokens for tenant" (naming the new one; Azure.Identity refuses the requested tenant). MEASURED: with the environment variable `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH=true` set, the same call instead silently sends its token request to the PREVIOUS tenant | MEASURED: yes -- a new credential instance is constructed and baked to the new tenant |
| DeviceCode | MEASURED: yes, for the client id used in the spike. DECOMPILED: the reuse test is an ordinal (case-sensitive) client-id comparison, so this holds whenever the id matches, not only for the one id measured | MEASURED: the credential never holds a tenant at all; every device-code request goes to the `organizations` authority path whatever tenant was named. INFERRED (not executable offline, since no sign-in can complete without a network): the issued token's tenant is the signing-in account's own | MEASURED: no -- the request still goes to `organizations` |
| ManagedIdentity (system- and user-assigned) | MEASURED: yes, for the client id used in the spike. DECOMPILED: the reuse test is an ordinal (case-sensitive) client-id comparison, so this holds whenever the id matches, not only for the one id measured | MEASURED: the tenant is not an input to the request at all -- the IMDS request is byte-identical whatever tenant was named, and the error is identical too | MEASURED: no -- the request stays byte-identical |

ClientCertificate and Interactive were outside the spike's scope: decompiling `TokenManager.cs`
shows both construct a brand-new credential on every call, so no earlier tenant ever survives into
them.

A FAILED call still leaves its credential behind: MEASURED, every first attempt in the spike failed
against the network-isolation proxy, and every following call in the same sequence still reused
that instance. The reuse is process-wide, not runspace-local: MEASURED, a call made in a second
runspace of the same process reused the first runspace's credential.

**The live run corroborated the ClientSecret row above, both halves.** MEASURED live, 2026-09-15/16:
the default refusal ("The current credential is not configured to acquire tokens for tenant")
reproduced through the module in checklist 2.2, 2.2b and 2.4, and against raw `Get-AzToken` in 4.3b;
the silent redirect to the PREVIOUS tenant under `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH=true`
reproduced in checklist 2.7b, which SUCCEEDED and whose token came from the previous tenant while
the session reported the newly named one. Worth recording beyond the row itself: on 2.7b
Azure.Identity was silent and this module was not -- BOTH of this branch's warnings fired on that
call, the pre-call one and the post-call one. That is the branch's own value, measured on the single
shape the spike had flagged as silently dangerous. An earlier reading of the run treated 4.3b's
refusal as a failure to reproduce the silent redirect; it was not, since 4.3's child process printed
an EMPTY `$env:AZURE_IDENTITY_DISABLE_MULTITENANTAUTH` and therefore ran the default path, while
2.7's child printed `true`. That is why the row keeps its label on both halves. (HISTORY: the
post-call warning was retired in Sprint 9 step 3. 2.7b named its tenant by domain and its token
came from the previous tenant; since the lookup, `TenantMismatch` refuses that shape before the
session is created -- read in the code and pinned by `Initialize-OERAuth`'s unit tests, not run
live again.)

**A RECORDED OBSERVATION that weakens the DeviceCode row's INFERRED half.** That row infers that the
issued token's tenant is the signing-in account's own. The live run is not consistent with that as a
general rule. Every device-code sign-in in the run, with the tenant each named and the tenant its
token came back for:

| Check | Tenant named | Token's tenant |
|---|---|---|
| 3.1 | tenant A, by GUID | tenant A |
| 3.2 | tenant B, by domain | tenant B |
| 3.3a | tenant A, by GUID | tenant A |
| 3.3 | tenant B, by domain | tenant B |
| 3.4 | none | tenant B |
| 3.5 | tenant B, by domain | tenant B |
| 3.7 | tenant B, by GUID | tenant B |
| 6.1a | tenant A, by GUID | tenant A |
| 6.1 | tenant B, by domain | tenant B |

(3.4a and 3.6a are left out on purpose: their own evidence blocks were never printed, so their
tokens' tenants are not in the record and nothing about them is inferred here.) Two things follow.
Naming no tenant at all returned a tenant B token, which identifies tenant B as the completing
account's own tenant in this run. Yet every sign-in that NAMED tenant A came back issued by tenant
A -- so for this account, on this run, the named tenant reached the issued token, which the offline
spike could not observe at all: it measured the device-code REQUEST going to `organizations`, and
never got as far as a token. This is a RECORDED OBSERVATION, not a MEASURED fact. The run cannot
exclude the alternative explanation, and it is a plain one: which account completed each device-code
page was not recorded, and a different account at one of those pages would produce the same table.

It does not contradict what this repository already knows.
[Requested tenant vs granted tenant](#requested-tenant-vs-granted-tenant) above records an earlier
live finding, that device-code sign-ins naming a deliberately NONEXISTENT tenant returned working
sessions for the signing-in account's own tenant. The reading that fits both: the named tenant
reaches the token when the account can actually obtain one there, and falls back to the account's
own tenant when it cannot -- which is precisely the shape the retired post-call warning existed to
catch, and which `TenantMismatch` now refuses for a tenant named by domain as well as by GUID. The
2026-09-15/16 run therefore did NOT exercise that failure mode, because the account turned out to
have an identity in tenant B as well, contrary to the checklist's own stated prerequisite. The check
that would settle it is a device-code sign-in naming a tenant the completing account genuinely has
no identity in, with the completing account recorded. It is not run here: SECURITY rule 1 keeps
every live check in the operator's own hands.

**Why the pre-call warning is ClientSecret-only, and why it needs its own tracker.** Only
ClientSecret can be PREDICTED before the call: DECOMPILED, AzAuth's reuse predicate (same
credential type and a matching client id) is knowable from the module's own inputs before
`Get-AzToken` is ever invoked, so the module can warn ahead of the call instead of only
interpreting its result afterward (as the retired post-call warning did) -- prediction works
because the predicate is known, not because the refusal is fast. Separately, MEASURED: the refusal
itself then happens in about 0.01 seconds with zero network requests sent, which confirms the reused
credential is never given a chance to reach the wire; it is corroborating evidence, not the reason
prediction is possible. DeviceCode and
ManagedIdentity credentials never carry a tenant at all (MEASURED), so telling either caller to
pass `-Force` would be false advice -- MEASURED, `-Force` changes neither type's request. The pre-call
warning is therefore ClientSecret-only at the predicate level, not merely untested for the other
two: it never applies to DeviceCode or ManagedIdentity at all.

**What the record tracks, and when it moves.** The predicate compares the module's own record of
the token request that last made AzAuth BUILD its credential (`$script:_OERLastTokenRequest`) --
and so, for a client secret, of the tenant the credential AzAuth currently holds was built for. It
is deliberately NOT the last request ATTEMPTED, and not `$script:_OERAuthState` either. It moves
only when the call is about to make AzAuth build a NEW credential: no record exists yet, the
credential type differs from the record's, the client id differs from the record's (case-sensitively,
`-cne` -- see below), or the call carries `-Force` (from `Connect-OER -Force`, or one this module
adds automatically on a sovereign-cloud switch). MEASURED: a same-application client secret call
with no `-Force` receives the SAME credential instance AzAuth already holds, still built for the
earlier tenant, whether that call is then silently answered (from the earlier tenant, under
`AZURE_IDENTITY_DISABLE_MULTITENANTAUTH`) or refused outright (the default) -- so such a call must
NOT move the record either way: AzAuth's credential stays built for the earlier tenant regardless of
what tenant the refused call asked for. A FAILED call that DOES build a new credential (a different
application or credential type, or a `-Force` call that itself then fails) still moves the record,
since AzAuth constructs the credential object before it ever sends a request -- MEASURED: every
first attempt in the spike failed against the network-isolation proxy and still left the credential
it had built for the next call to reuse. `$script:_OERAuthState` cannot substitute for this record:
it is written only after a successful Graph token, while the credential-build the record tracks
happens, success or failure alike, before any request is sent.

**The design this replaced, and the two defects it had.** An earlier version of this record moved
on every ATTEMPT, not only on a credential build. That produced a FALSE POSITIVE: after a refused
switch to tenant B, going back to sign in to tenant A again -- which works immediately, since
AzAuth's credential was never actually rebuilt -- still warned, because the attempt-based record had
already been moved to B by the refused attempt and so disagreed with the (entirely correct) request
for A. It also produced a FALSE NEGATIVE: retrying the SAME refused switch to tenant B a second time
warned only on the first try, because that first refused attempt had already moved the attempt-based
record to B, so the retry's comparison (record B vs. requested B) found no difference and stayed
silent -- even though AzAuth's credential was still built for A and the retry would fail exactly as
the first attempt had. Moving the record only when AzAuth actually builds a new credential closes
both defects: a refused or reused call never moves it, so the warning keeps firing on every retry
until `-Force` is genuinely used, and it never fires falsely about a return to the tenant the
credential is still, in fact, built for.

**Why `-ceq` on the client id and `-ne` on the tenant.** Decompiling `TokenManager.cs` shows
AzAuth's own reuse test is a plain ordinal (case-sensitive) client-id comparison, so `-ceq` mirrors
it exactly: a client id differing only in case gets a brand-new credential built for the new
tenant, and warning about it would be false. Decompiling Azure.Identity's tenant resolver shows it
compares the requested tenant against the credential's tenant case-insensitively, both where it
refuses and where it silently redirects under the multitenant-disable switch, so `-ne`
(PowerShell's default case-insensitive string comparison) matches that: a case-only tenant
difference is the same tenant to Azure.Identity and must not warn. The record-move predicate tests
the SAME client id comparison as its own negation, `-cne`, for the identical reason: a client id
differing only in case gets a brand-new credential built, so the record must move to describe it.

**Why a token can come back from another tenant than the one named.** MEASURED: every device-code
request goes to `organizations` whatever tenant was named, a managed-identity request is
byte-identical for any tenant, and a client-secret credential reused under the multitenant-disable
switch silently sends to the PREVIOUS tenant. INFERRED, since no token can be issued offline: a
device-code token is therefore issued for the signing-in account's own tenant and a managed-identity
token for the identity's own tenant, so a switch made with either -- or with that reused
client-secret credential -- comes back issued by the SAME tenant as before, under the new label.
(The device-code half of that inference is weakened, though not withdrawn, by the RECORDED
OBSERVATION above.) A second inference used to sit here, and the live run has since split it in
two. DECOMPILED, and still standing: a device-code credential reused after a SUCCESSFUL earlier
sign-in first attempts silent reacquisition for the REQUESTED tenant. CONTRADICTED BY MEASUREMENT:
the fall-back to a new device code, "only when that needs interaction", does not happen -- live,
that call never returns at all (further finding 1 below). The reassurance that used to be drawn from
it -- that such a switch may in fact reach the new tenant, and the check then stays silent by design
-- is therefore withdrawn. Each of these shapes that returns a token from another tenant than the
one named is now refused by `TenantMismatch`, by GUID or by domain. The same inference is repeated
in `Initialize-OERAuth.ps1`'s comment above the `TenantMismatch` check; this paragraph is the record
that governs.

HISTORY: until Sprint 9 step 3 this was the reasoning behind the post-call warning, which compared
GRANTED tenants -- this sign-in's with the previous session's -- because for a tenant named by domain
the granted tenant was the only signal there was: the GUID-only `TenantMismatch` could not compare a
domain with the GUID a token carries.

**Where the granted-tenant value itself comes from (evidence Q4(c)).** MEASURED live, 2026-09-15/16,
against real tokens: `AzToken.TenantId` carries the acquired token's own `tid` claim. Three checks
decoded the token's payload segment in memory and compared it with the property -- 4.1 (a first
device-code token, tenant named by domain), 4.2 (a device-code token after a switch, with `-Force`)
and 4.3a (a client secret token, tenant named by domain) -- and all three found the property equal
to `tid` and NOT an echo of the requested value. Checklist 2.7b corroborates it a fourth time, on
the one shape where an echo would have been most misleading: a client secret sign-in naming a tenant
by DOMAIN under `AZURE_IDENTITY_DISABLE_MULTITENANTAUTH=true` returned a token whose `TenantId` was
the PREVIOUS tenant's id, not an echo of the requested domain. DECOMPILED, and NOT measured, since
no live token exercised it: the property falls back to echoing the REQUESTED tenant when the token
carries no `tid` claim at all, so such a token reads back the tenant it was asked for rather than
one the token claims to be issued for -- the known limit recorded under
[Requested tenant vs granted tenant](#requested-tenant-vs-granted-tenant). What the measurement
settles: `TenantMismatch`, and the sign-in identity that reads `TokenTenantId` (BL-77), rest on a
measured property rather than a decompiled one, as the retired post-call warning did, and every
conditional `Expect:` in the live-verification checklist that hung on this question is grounded.

**The ARM half.** MEASURED live, 2026-09-16, checklist 5.4 -- a managed identity sign-in with
`-IncludeARM` whose switch did not take effect: `ArmTokenTenantId` equalled `TokenTenantId`, so the
ARM token was in the same state as the Graph token, issued by the same tenant. Read that measurement
at its own width: it is managed identity. On the three delegated types the ARM acquisition passes no
client id and so builds its own credential (further finding 2 below), which makes it a separate
sign-in whose token may reach the requested tenant, repeat the Graph token's tenant, or land on a
third. The ARM token's own `TenantMismatch` check covers all three: it compares the ARM token's
granted tenant with the same tenant ID the Graph check uses -- the GUID as named, or the one a domain
resolved to -- and when the Graph token was cached and only the ARM token is acquired, that sign-in
makes its own lookup (a cache hit inside the resolver for a domain already resolved in the process).
HISTORY: the retired post-call warning read only the GRAPH token, since it ran before the ARM token
was acquired, and carried the ARM half by wording; the ARM half's own check was then the GUID-only
`TenantMismatch`, blind to a request that named its tenant by domain.

**The pre-call warning stops the sign-in under `-WarningAction Stop`.** Like the module's existing
ambient `AZURE_AUTHORITY_HOST` warning, a caller running with `-WarningAction Stop` or
`$WarningPreference = 'Stop'` turns the `Write-Warning` call into a terminating error at that point,
before any token is requested. It is the module's one tenant-switch warning now. HISTORY: there were
two until Sprint 9 step 3, and the post-call one stopped such a caller before `$script:_OERAuthState`
was rebuilt, that is before the session was created.

**HISTORY: the retired post-call warning, and why the lookup replaced it.** From the F12 spike
until Sprint 9 step 3 the module warned AFTER a sign-in that named its tenant by domain, when that
tenant differed from the one the last established session named and the token came from the same
tenant as that session's token. It compared against a dedicated tracker,
`$script:_OERLastIssuedSession` (`TenantId` and `TokenTenantId` only), written right after
`$script:_OERAuthState` was rebuilt, so only a session that was actually established was recorded.
`Disconnect-OER` deliberately left that tracker alone, for the reason it still leaves
`$script:_OERLastAuthorityHost` and `$script:_OERLastTokenRequest` alone: disconnecting before
connecting to the next customer is the most natural way to switch tenants, and AzAuth's credential
is process-wide (MEASURED) whatever `Disconnect-OER` clears. Its known shapes were recorded here:

- Two benign ones that satisfied its terms without being failures -- two names for one tenant (a
  verified domain and the tenant's initial `onmicrosoft.com` name), and a previous session that
  named no tenant (recorded as `organizations`) followed by a sign-in naming that tenant's own domain.
  Its sentence named the requested and the granted tenant so the operator could recognise them.
- `organizations` was NOT excluded as a previous label, since the failure it existed to catch has
  that shape: a device-code sign-in naming no tenant, then `-TenantId` naming a customer's domain,
  still issued by the operator's own home tenant. A CURRENT request naming no tenant was excluded:
  no switch can fail to take effect when no particular tenant was asked for.
- It could not check the first sign-in in a process, nor the first after the module was re-imported,
  since it needed a previous entry to compare with.

The lookup makes it obsolete (Sprint 9 step 3, Ruling R6). After it, a sign-in that names its tenant
by domain is either checked against that tenant's ID or refused before any token is requested, so a
token from another tenant is refused with `TenantMismatch` -- including on the first sign-in in a
process, which the warning could never check. What the warning could still see is only a domain
naming the very tenant its token came from: a correct sign-in. The warning and
`$script:_OERLastIssuedSession` are removed; the pre-call warning and its record,
`$script:_OERLastTokenRequest`, stay.

**Why `Connect-OER -Force` exists.** A public lever was required, not optional: in this module,
`Connect-OER -Force` is the only PUBLIC lever that clears AzAuth's static credential, and in AzAuth
itself only `Get-AzToken -Force` does (see below) -- `Initialize-OERAuth -ForceRefresh` already puts
`Force` on the `Get-AzToken` splat it builds. `Connect-OER -Force` forwards `-ForceRefresh` and
nothing else. Two internal paths put `Force` on the call as well. One is the automatic cloud switch:
`Initialize-OERAuth` adds `Force` whenever the authority it is about to use differs from the last
one it attempted. The other is the refresh retry after a rejected token: `Invoke-OERGraphRequest`
and `Invoke-OERArmRequest` call `Initialize-OERAuth -ForceRefresh`, for a session that is not
app-only -- a client secret or certificate session raises `AppOnlyTokenRefreshUnsatisfiable` there
instead of refreshing.

**What does NOT clear AzAuth's credential.** MEASURED: `Clear-AzTokenCache`, with or without
`-Force`, leaves the credential instance unchanged in every case tried. DECOMPILED: it has zero
references to `TokenManager` at all -- it only ever touches the on-disk MSAL token cache, never the
static credential field. MEASURED: removing and re-importing the AzAuth module leaves the same
credential instance in place. `Disconnect-OER` clears only `$script:_OERAuthState` (this module's
own session state) and calls `Disconnect-MgGraph` for the session the module connected (A4; it
called `Disconnect-AzAccount` too until 2026-09-21); reading its source shows it never touches
AzAuth's credential at all, so it was never capable of clearing it. Decompiling AzAuth shows the
only call site that clears the static credential is `Get-AzToken`'s own `-Force` handling.

**The tenant lookup (BL-12, decided by Philip 2026-10-06, P-2).** HISTORY first: this paragraph
used to record the lookup as a proposal, not built, since it is a new network call, and the gap it
would close -- a device code or managed identity sign-in naming its tenant by domain went unchecked
on the first sign-in in a process and the first after a module re-import, the cases the post-call
warning could not compare. The decision of 2026-10-06 builds it.

`Initialize-OERAuth` resolves every requested tenant that is neither a GUID nor `organizations`
through `Resolve-OERTenantDomain`, the single owner of the module's one network call outside the
Microsoft Graph and Azure Resource Manager transports, and its one deliberately unauthenticated
call. It sends one GET of `{AuthorityHost}{domain}/v2.0/.well-known/openid-configuration` to the
cloud's Microsoft Entra ID authority, the host read from `Get-OERCloudEndpoint`, through
`Invoke-RestMethod` with `-Uri`, `-Method Get`, `-TimeoutSec 30` and `-ErrorAction Stop` and nothing
else: no `Authorization` header and no credential of any kind. (The ARM wrapper's documented
no-auth-state fallback also sends a request without a token, by accident of state rather than by
design, which is why this is the one DELIBERATELY unauthenticated call.) It reads the tenant ID
from the first path segment of the document's `issuer`. The lookup runs after the cached return -- a session that
needs no new token was checked when it was established (Sprint 9 step 3, Ruling R3) -- and after the
credential checks (`AppOnlySessionCredentialUnavailable`, `MissingClientSecret`,
`MissingClientCertificate`), and before the AzAuth trackers move and before any token call, so a
refused lookup builds no AzAuth credential and requests nothing. The token request still names the
tenant as given (Sprint 9 step 3, Ruling R4); only the two `TenantMismatch` checks use the tenant ID.

**Measured first (Sprint 9 step 3, the step's first measurement, 2026-10-06).** By hand, outside the
module: unauthenticated, no sign-in, the commercial cloud's authority host as
`Get-OERCloudEndpoint -Environment Global` returns it, GET of the path above, no `Authorization`
header sent (checked on the request message). The `consumers` row was measured the same way later
the same day, during the step's review. The test tenant's domain and GUID, and the consumer tenant's
tenant ID, are deliberately not written here.

| Tenant asked for | Status | Issuer | Issuer holds the test tenant's GUID |
|---|---|---|---|
| the test tenant's primary domain | 200 | the authority, then a GUID | yes |
| the same domain in upper case | 200 | the authority, then a GUID | yes |
| the test tenant's GUID | 200 | the authority, then a GUID | yes |
| a made-up domain: label `oer-s93-doesnotexist` under `onmicrosoft.com` | 400, `invalid_tenant` (AADSTS90002) | none | no |
| `organizations` | 200 | the template `{tenantid}` | no |
| `common` | 200 | the template `{tenantid}` | no |
| `consumers` | 200 | the authority, then the fixed tenant ID of the Microsoft account (consumer) tenant | no |

**The cache.** A tenant ID found is kept for the rest of the process, per cloud and per domain in
lower case, so a domain costs one request per cloud however often, and in whatever letter case, it is
named. A failure is not cached: the next sign-in asks again (Sprint 9 step 3, Ruling R7).
Re-importing the module empties the cache (INFERRED from module scoping, not tested);
`Disconnect-OER` does not. The accepted cost: a domain moved to another tenant during one process is
not seen until the module is re-imported.

**The cost.** One unauthenticated request per domain and cloud per process, before the first token
request for that domain, and up to the 30-second bound when the authority does not answer. A tenant
named by GUID, and `organizations`, cost nothing, and so does a cached return, which makes no lookup.

**`TenantResolutionFailed`, the one new error id.** A lookup that fails -- a refused request, whose
`error` and `AADSTS` codes the message carries, a network failure, or a document whose `issuer` names
no tenant ID -- refuses the sign-in with a terminating `TenantResolutionFailed`: `AuthenticationError`,
the tenant as named as its target, the lookup failure as its inner exception, and a message that names
the authority and tells the operator to check the domain and the cloud (`-Environment`) or to name the
tenant by its tenant ID. It is raised after the lookup's try statement, not inside its catch (fact 3
under [The Graph SDK session](#the-graph-sdk-session)), and its record is scrubbed first like every
other transport failure. No token is requested and no credential is built. It is a refusal after the
sign-in latch like every other, so the command sends nothing, and the session is left uncertain
([A refused sign-in leaves the session uncertain](#a-refused-sign-in-leaves-the-session-uncertain)).

**`common` and `consumers` (Sprint 9 step 3, Ruling R5).** Every requested tenant that is neither a
GUID nor `organizations` is looked up, `common` and `consumers` included, and the issuer decides.
`common`'s discovery issuer is the template `{tenantid}` (MEASURED above), which names no tenant:
`-TenantId common` is refused with `TenantResolutionFailed`, where it used to reach `Get-AzToken` and
build a session that named no tenant `TenantMismatch` could check. `consumers` does not share that
fate: its issuer carries the fixed tenant ID of the Microsoft account (consumer) tenant (MEASURED
above), so `-TenantId consumers` RESOLVES to that tenant ID and every token is compared with it like
any tenant ID; the lookup does not refuse it. The ruling expected both to be refused; the
measurement shows the lookup refuses only `common`. Whether a sign-in naming `consumers` then gets a
token whose tenant compares equal is NOT measured. `organizations` stays exempt, unlooked-up and
compared with no requested tenant: it is the module's own value for a sign-in that names no tenant.
An ARM token a sign-in acquires under it is compared with the session's Graph token instead (Ruling
F3), and a renewal of the Graph token carries the cached one only for the renewed Graph token's
tenant (A13), both under [Requested tenant vs granted tenant](#requested-tenant-vs-granted-tenant).

**Known limits of the lookup.**

- PowerShell 7.4 and later bind `-TimeoutSec` to `ConnectionTimeoutSeconds` (MEASURED on 7.6.6 for
  the lookup helper's commit: the cmdlet resolves the name to that parameter), so there the 30-second
  bound covers establishing the connection. Whether a response that stalls after the connection is
  bounded is NOT measured.
- A token without a `tid` claim is compared neither for a GUID nor for a domain (DECOMPILED, under
  [Requested tenant vs granted tenant](#requested-tenant-vs-granted-tenant)).
- A domain named under the wrong cloud is looked up at that cloud's authority. Whether the commercial
  authority resolves a sovereign tenant's domain, or the reverse, is NOT measured; either way the
  token request then goes to the wrong authority, as it did before the lookup.
- Not yet run live through the module: the measurement above was made by hand, every lookup in the
  tests is stubbed, and the transport tripwire refuses a real one.

**The proof.** `tests/Unit/Private/Resolve-OERTenantDomain.Tests.ps1`: the request and its exact
parameters, no credential, the issuer read, one cache entry per cloud and lower-cased domain, no
failure cached, the authority's codes in the message, and the scrub of each failure record.
`tests/Unit/Private/Initialize-OERAuth.Tests.ps1`: the Describe
`Initialize-OERAuth tenant named by domain (BL-12)` -- `TenantResolutionFailed` before any token
request and with no AzAuth credential built, the sovereign cloud's authority asked, `common` looked
up, no lookup for a GUID, `organizations` or a cached return, none for a sign-in the credential
checks refuse first, and a lookup of its own for an ARM-only acquisition -- and the domain cases of
the Describe `Initialize-OERAuth granted-tenant guard`: the Graph and the ARM token refused for
another tenant than the one a domain resolves to, accepted for that tenant, `organizations`
uncompared on both, and one lookup for a domain named by two sign-ins. End to end, with no `try`: H6 and H7 in
`tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` run `Invoke-OERStructure` naming a domain --
H6 one that does not resolve, H7 one whose token comes back from another tenant -- and show no token
request in H6, nothing connected in H7, and no Graph or ARM request in either. Mutation-proved on
copies of `source/`: replacing the lookup with no expected tenant turns thirteen tests red, H6 among
them; raising the refusal inside the catch without `-Terminating` turns H6 red; moving the
lookup after the tracker writes, above the cached return, or above the credential checks each turns
its placement test red; comparing only GUIDs again, on either token, turns that token's domain
refusal red, and H7 with it on the Graph side; dropping the `organizations` term turns the
`organizations` tests red on each side; and in the helper, dropping the cache write, caching a
failure, adding a header, a second sender, a dropped scrub, a hardcoded cloud and an unlowered key
each turn their own unit test or gate red. Gate 10 of [#static-source-gates](#static-source-gates) holds the owner
rules and the call's parameters.

**Two further findings, outside the spike's direct questions.**

1. MEASURED: a DeviceCode `Get-AzToken` call can block forever, printing no device code and raising
   no error, `-TimeoutSeconds` included. A failing network is one INSTANCE of that condition, not
   the condition itself. The spike measured that instance -- in every run, a device-code request
   that fails at the network level never returned. The live run of 2026-09-16 measured a second
   instance on a HEALTHY connection, twice independently: through the module (checklist 3.5) and
   against raw `Get-AzToken` outside it (checklist 4.2). MEASURED, that second instance: a
   device-code call that REUSES a credential which has already completed a sign-in, and names a
   DIFFERENT tenant, with no `-Force`, never returns; no device code is printed and no error is
   raised, and in 3.5 the harness function returned `$null`, so it never reached its own return
   expression. MEASURED: `-Force` cured it every time it was used. The mechanism underneath both
   instances, from decompiling AzAuth: it waits on a blocking queue that only the device-code
   callback completes, and `-TimeoutSeconds` bounds only the inner token acquisition, not that
   wait -- so anything that stops the callback from running hangs the call.

   Two boundaries, both MEASURED, both making the claim NARROWER. (a) It is not every device-code
   tenant switch: checklist 3.2 and 3.3 switched by device code with no `-Force` and returned
   normally. Both ran straight after an `-IncludeARM` sign-in, whose ARM call passes no client id
   and so makes AzAuth build a fresh credential; the hang needs a credential that has already
   signed in. (b) It refutes the second half of the INFERRED device-code claim recorded above (and
   repeated in `Initialize-OERAuth.ps1`'s comment): the silent acquisition attempt for the
   REQUESTED tenant is still DECOMPILED, but the fall-back to a new device code "only when that
   needs interaction" is CONTRADICTED BY MEASUREMENT. Live, there is no fall-back -- it hangs.

   The module's own path hangs too, not only a bare `Get-AzToken` call: MEASURED, checklist 3.5
   hung inside `Initialize-OERAuth`'s DeviceCode path. INFERRED, still, for the other instance:
   that path would hang the same way on a proxy or network failure before a code is issued, which
   has only ever been measured against `Get-AzToken` directly.

   `-TimeoutSeconds` is AzAuth's own parameter, not this module's: MEASURED, `source/` passes it
   nowhere -- zero occurrences under `source/`. (It does appear in tracked files under `docs/`,
   including this paragraph; those are prose about the parameter, not a call passing it.) So there is
   no module-level knob a caller could reach for, and nothing in the module's help promises one. The
   module does not carry a guard-shaped-but-inert timeout parameter here; it has no such parameter at
   all.
2. MEASURED, in the module's own DeviceCode call shape (a Graph acquisition using the Microsoft
   Graph Command Line Tools client, followed by an ARM acquisition with no client id, followed by
   another Graph acquisition for a different tenant with no `-Force`): every one of the three calls
   BUILT A NEW credential instance, because AzAuth's reuse test also requires a matching client id,
   and the Graph and ARM calls in this module's own shape never share one -- the ARM call falls
   back to Azure.Identity's built-in default public client. `Initialize-OERAuth`'s comment above
   `Invoke-AzTokenCall` already documents this measured shape and states plainly that whether the
   operator is shown a second device code on the ARM call "has not yet been observed live" --
   consistent with what this spike measured, not a contradiction of it.

### A client secret reaches AzAuth as a string

`-ClientSecret` is a `[securestring]` on `Connect-OER` and on `Initialize-OERAuth`, and it stays one:
the module never accepts a plain string and never keeps one in `$script:_OERAuthState`; the splats
hold it until the `finally` (CLAUDE.md, Authentication Architecture and SECURITY rule 5). There is
one place the plain text exists, and it is the hand-over to AzAuth.

AzAuth 2.10.0 declares `Get-AzToken -ClientSecret` as `String` (its help). For a client secret
sign-in `Initialize-OERAuth` therefore converts the secret with
`[System.Net.NetworkCredential]::new('', $ClientSecret).Password` -- a .NET call, not a parameter
binding -- and puts the result in the `Get-AzToken` splat. The Graph splat and, with `-IncludeARM`,
the ARM splat are each a shallow clone of that one splat, and both acquisitions go through
`Invoke-AzTokenCall`'s non-device-code branch (`return Get-AzToken @TokenParameter`). So the secret
is bound to a `String` parameter once for each token requested: once for the Graph token, and a
second time for the ARM token when `-IncludeARM` makes the call acquire both. The device-code
branch of that helper never carries a secret.

PowerShell module logging (Event 4103, `LogPipelineExecutionDetails` or the "Turn on Module
Logging" policy) records bound parameter values. That is the mechanism
[#directory-role-assignments](#directory-role-assignments) records for a token, and the reason
`Get-OERTokenObjectId` takes a `[securestring]`. On a machine where module logging covers AzAuth,
the string bound to `-ClientSecret` is therefore written to the log in plain text. INFERRED from
that mechanism: no capture of an event for this parameter is recorded here.

**While the module acquires tokens through AzAuth's `Get-AzToken`, it cannot change it.** The
parameter that receives the plain text belongs to AzAuth and is a string, so the value it is handed
has to be one, and there is no equivalent of the `Get-OERTokenObjectId` shape to move to. Nothing
the module does afterwards withdraws a log entry either. `Remove-OERErrorRecord` clears the
`Authorization` header of a request message and removes the record from `$global:Error`; it reaches
neither a request body, nor a parameter binding, nor a log. The `finally` block in
`Initialize-OERAuth` that sets the splats' `ClientSecret` to `$null` only drops the module's own
references to the string, once the token calls are done.

**What to do.** Prefer a certificate (`-Certificate` or `-CertificatePath`) or a managed identity
(`-ManagedIdentity`): neither hands AzAuth a secret string. Where a secret is unavoidable, keep
module logging from covering AzAuth on that machine, and treat the log of a machine where it does
as holding the secret. The same warning is in `Connect-OER`'s `-ClientSecret` help and beside the
client secret line in the README's Quick Start.

### The Graph SDK session

`Initialize-OERAuth` hands the Graph token it acquired to the Microsoft Graph PowerShell SDK:
`Connect-MgGraph -AccessToken` with `-NoWelcome` and `-ErrorAction Stop`, plus `-Environment` outside
`Global`, and **no `-ContextScope`**, which is not a parameter of the `-AccessToken` parameter set
at all (below). Every sign-in the module makes goes through that one call -- `Connect-OER` and the
first-use sign-in of any other cmdlet alike -- so an OER session always comes with an SDK session in
the same process. `Connect-MgGraph` runs only on a call where `$GraphCached` is false -- the first
sign-in, a different tenant, identity or cloud, `-ForceRefresh`, a claims challenge, a Graph token
within five minutes of expiry, a process that holds no SDK session at all, or, under `Connect-OER`
only, a session another `Connect-MgGraph` started -- so the SDK session is started per sign-in or
token refresh and not once per cmdlet; a call whose Graph session is still valid never reaches it.
`Disconnect-OER` is the matching end: inside its `ShouldProcess` it clears `$script:_OERAuthState`,
and it calls `Disconnect-MgGraph` there only when the session is the module's own (A4, below).

**Why the module checks which session the process holds.** The SDK keeps one session per process,
and `Invoke-OERGraphRequest` passes no token of its own: it calls `Invoke-MgGraphRequest`, so every
Graph call goes out under whichever session the SDK holds at that moment -- INFERRED, the second
half of the premise below. Before the check existed, an operator's own `Connect-MgGraph`, or
another tool's, made while the module's cache was still valid was followed by OER cmdlets that
returned from the cache without reconnecting. Their Graph reads and writes would then go to that
session's tenant while `$script:_OERAuthState` still named the module's, and Azure Resource Manager,
which keeps its own token, could point at another tenant than Graph. A forced refresh, a claims
challenge or the five-minute window reconnected and put the module's session back, so the window
was bounded, but nothing announced it.

The premise has two halves, with different evidence. That another `Connect-MgGraph` REPLACES the
module's session is READ IN THE SOURCE (the SDK facts below). That `Invoke-MgGraphRequest` then
CARRIES the module's next Graph calls under the replacing session is INFERRED: which session it
authenticates with was not read. Check 1.3, in section 1 of the live checklist of the change that
added the check, `docs/live-verification/fix-refuse-a-changed-graph-sdk-session-checklist.md`,
measures that half live.

**The SDK facts the check stands on.** READ IN THE SOURCE of `microsoftgraph/msgraph-sdk-powershell`
at tag `v2.41.1`, not executed:

- The session is a process-wide static singleton (`GraphSession.cs`). `Get-MgContext` writes
  `GraphSession.Instance.AuthContext` itself, and nothing when it is null (`GetMGContext.cs`).
- Every `Connect-MgGraph` builds a new `AuthContext` and assigns it after sign-in
  (`ConnectMgGraph.cs:171`, `:256`); a failed one resets the session (`LogoutAsync`).
  `Disconnect-MgGraph` sets it to null (`AuthenticationHelpers.cs:582`).
- The module's own connect, `-AccessToken`, sets `AuthType` and `TokenCredentialType` to
  `UserProvidedAccessToken` and `ContextScope` to `Process` (`ConnectMgGraph.cs:244-251`). Then
  `JwtHelpers.DecodeJWT` sets `ClientId` from the token's `appid` claim, `Scopes` from `scp` (split)
  or `roles`, `TenantId` from `tid`, `AppName` from `app_displayname` and `Account` from `upn`
  (`JwtHelpers.cs:40-44`). `Environment` is the environment name, `Global` by default.
  `-ContextScope` is not a parameter of the `-AccessToken` parameter set.
- A certificate connect sets `AuthType` to `AppOnly`, `TokenCredentialType` to `ClientCertificate`
  and `CertificateThumbprint`, with `ContextScope` `Process` by default
  (`ConnectMgGraph.cs:206-218`), then the same decode.

MEASURED 2026-10-05, by reflection over Microsoft.Graph.Authentication 2.41.1 offline, with no
session in the process: `Get-MgContext` declares `[OutputType(IAuthContext)]`, and `IAuthContext`
has `AuthType`, `TokenCredentialType`, `ClientId`, `TenantId`, `Scopes` (`String[]`), `Environment`,
`AppName`, `Account`, `LoginHint`, `HomeAccountId`, `CertificateThumbprint`,
`CertificateSubjectName`, `SendCertificateChain`, `Certificate` (`X509Certificate2`),
`ContextScope`, `PSHostVersion`, `ManagedIdentityId`, `ClientSecret` (`SecureString`) and
`WamEnabled` -- none of them a token. The contract `Describe` in
`tests/Unit/Private/Get-OERGraphSessionFingerprint.Tests.ps1` pins the names and types of the eight
properties the fingerprint reads, and of the two it never reads, against whichever SDK release CI
resolves, so a renamed or retyped property turns it red instead of leaving the fingerprint to
compare two empty values as equal.

NOT YET MEASURED: the values `Get-MgContext` really holds after the module's own connect, and after
a certificate connect for another application in the same tenant -- that is, whether the fingerprint
tells those two apart live. Check 1.1, in section 1 of the same live checklist, measures them.

**The fingerprint.** `Get-OERGraphSessionFingerprint` is its single owner. It reads eight
properties of the context by name -- `AuthType`, `TokenCredentialType`, `ClientId`, `TenantId`,
`Account`, `AppName`, `Environment` and `Scopes` -- sorts the scopes ordinally and keeps them as an
array, and writes the eight as compact JSON. The same grant in another order is therefore the same
session, and no value holding a separator -- one scope with a space in it -- can make two sessions
compare equal. `Initialize-OERAuth` records it as `GraphSessionFingerprint` in the state it
rebuilds, read straight after its own `Connect-MgGraph`; the key is written even when the value is
`$null`, so a session whose context could not be read is still compared. From the facts above, a
certificate connect differs from the module's in `AuthType` and `TokenCredentialType`, and an
`-AccessToken` connect with a token for another application, tenant or user differs in `ClientId`,
`TenantId` or `Account`. That a client secret, managed identity or interactive connect differs the
same way is INFERRED, not read here. The properties outside the eight (`ContextScope`,
`CertificateThumbprint`, `LoginHint`, `HomeAccountId`, `PSHostVersion`) do not change it; the same
test file pins both directions.

**Values, not object identity.** Two sessions with equal values give an equal fingerprint whatever
object carries them. Two runspaces in one process -- `ForEach-Object -Parallel`, for example --
connected as the same identity to the same tenant each sees the other's `Connect-MgGraph` as its
own session, and neither is refused; the SDK's object identity is an implementation detail this
module does not depend on. The cost is the mirror image: a session someone else started with
exactly the same eight values is accepted, and such a session sends nothing to another tenant. The
same test file pins that two distinct context objects with equal values give equal fingerprints.

**What it never holds.** No token: it reads only the eight properties above, and the context
carries no token property in the reflection above. Not the context object. And it never reads the
context's `ClientSecret` or `Certificate`: every value is read by name, never by enumerating the
context. The test for that records every read of the two properties and has a positive control,
since a getter that throws would prove nothing -- MEASURED 2026-10-05, PowerShell 7 swallows an
exception a ScriptProperty getter raises on member access and returns `$null`. The fingerprint does
hold the session's tenant id and user principal name, so it is never written to any stream:
`Get-OERGraphSessionState` returns only a state word, and the `GraphSessionChanged` message names
no token and no tenant but the module's own.

**Four states.** `Get-OERGraphSessionState` is the single owner of the comparison, which is
ordinal:

- `Untracked` -- no state, or a state without the key. Nothing is compared and `Get-MgContext` is
  not called. Every state `Initialize-OERAuth` builds carries the key, so outside the tests, whose
  hand-built states stay valid this way, this is the no-state case: a first sign-in, or the first
  after `Disconnect-OER`, whose `Connect-MgGraph` replaces whatever session the process held, as any
  `Connect-MgGraph` does.
- `Own` -- the process holds the session the module connected. Everything carries on as before, the
  cached return included.
- `Absent` -- the process holds no session, after `Disconnect-MgGraph` for example. A cache miss: the
  module connects again with a token of its own, as after a renewal. It does not keep its Graph
  token to reconnect with, so an inherited app-only identity (client secret or certificate) cannot,
  and gets `AppOnlySessionCredentialUnavailable`, whose message then names the closed Graph SDK
  session (`Disconnect-MgGraph`), until `Connect-OER` is run with the secret or certificate. A
  delegated or managed identity session signs in again by itself.
- `Changed` -- another `Connect-MgGraph` replaced the module's session. `Initialize-OERAuth` raises
  a terminating `GraphSessionChanged` (`AuthenticationError`, target the module's own tenant) at
  every entry, before any token call: on a cache hit, under `-ForceRefresh`, for a claims-challenge
  step-up, for a renewal inside the five-minute window, for a call naming another tenant with
  `-TenantId` and for an `-IncludeARM` call alike. The module never switches the session back by
  itself, since that would move the other session's calls to this module's tenant.

**Taking the session back.** `-ReclaimGraphSession`, a private switch on `Initialize-OERAuth`,
makes `Changed` a cache miss, so the module connects again and its `Connect-MgGraph` replaces the
other session. Only `Connect-OER` passes it, on every parameter set: an explicit `Connect-OER` is
the operator's instruction to take the session back. Any other caller passing it would move the
other session's calls to this module's tenant without anyone asking, which is exactly what the
refusal exists to prevent. `Connect-OER` is therefore idempotent only while the session is `Own`;
over `Changed` or `Absent` it signs in again. The module's own renewal -- a `Connect-MgGraph` after
the five-minute window, or `-ForceRefresh` under its own session -- writes a new fingerprint, and the
next call is `Own`. Since A10 the switch is also the way past the session-uncertain refusal and the
one key that clears that marker without a tenant, so a second caller would reopen BL-89 as well.
Review alone held the one-caller rule until Sprint 9 step 3 (final review I2, Ruling F2); gate 10 of
[#static-source-gates](#static-source-gates) now holds the NAME `ReclaimGraphSession` to
`Connect-OER.ps1` and `Initialize-OERAuth.ps1`.

**`Disconnect-OER` (A4, BL-67, Sprint 10 step 3).** Decision A4 (Philip): `Disconnect-OER` ends
only the Graph SDK session the module connected, the same stance it takes for an Az session, which
it leaves alone since the module never establishes an Az context. Until this change it called
`Disconnect-MgGraph` whatever session the process held, so after another `Connect-MgGraph` it ended
that session too, exactly as it did before the check existed. The alternative this paragraph used to
name -- skipping `Disconnect-MgGraph` when the state is `Changed`, one condition and a help change --
is the one taken, and widened to the other states below. `Disconnect-OER` reads
`Get-OERGraphSessionState` ONCE, into `$GraphSessionState`, before its `ShouldProcess` gate and so
before `$script:_OERAuthState` is cleared: the fingerprint lives in that state, and once it is
cleared every state reads `Untracked`. Inside the gate it clears the state, the fingerprint with it,
and the A10 marker in every case, so the next cmdlet is `Untracked` and signs in from the start; only
`Own` then calls `Disconnect-MgGraph`.

- `Own` -- the process holds the session the module connected. `Disconnect-MgGraph`, no warning.
- `Changed` -- another `Connect-MgGraph` replaced it. Left connected, with the warning.
- `Untracked` -- the module holds no record of a session of its own. With a session in the process
  (`Get-OERGraphSessionFingerprint` returns a value) it is left connected, with the warning; with
  none there is nothing to leave, so no warning.
- `Absent` -- the session the module connected is already gone. Nothing to disconnect, no warning.

The warning is one string, written once by `Write-Warning` when a session exists and is left -- for
`Changed`, and for `Untracked` with a session in the process: `Disconnect-OER leaves the Microsoft
Graph PowerShell SDK session in this process connected, since Omnicit.EntraRBAC has no record of
connecting it. Run Disconnect-MgGraph to end that session.` It says "has no record of connecting
it" and not "did not connect it": for an `Untracked` session the module cannot know it did not
connect it, since an earlier import of the module may have; it knows only that it holds no record.
The `ShouldProcess` target and action strings are unchanged.

Ruling: a warning before the gate, not after it, and not Verbose or Information. It is shown by
default, it shows under `-WhatIf` and before a `-Confirm` prompt is answered, it is about what the
command will leave and not an outcome of the answer, and the rule of
[#warning-before-confirmation](#warning-before-confirmation) -- no `Write-Warning` after a public
cmdlet's first `$PSCmdlet.ShouldProcess` -- allows it with no allowlist entry, so the allowlist stays
at nine. The state is read before the gate for the same reason: the warning has to know it. Cost if
wrong: a declined `-Confirm` has shown a warning about a command that then did nothing, and the
warning stays true, since the session stays connected either way.

Ruling: the warning before the gate stands under `-WarningAction Stop` and
a global `$WarningPreference` of `Stop` too, and its cost is named and pinned. A `Disconnect-OER` that would
leave another session (`Changed`, or `Untracked` with a session in the process) stops AT the warning
-- measured in plain PowerShell 7.6.6 as a script-terminating `ActionPreferenceStop`, error id
`ActionPreferenceStop,Microsoft.PowerShell.Commands.WriteWarningCommand` -- so its gate never runs and
it clears nothing: the state, its fingerprint, the ARM token and the A10 marker all stay. That is
the safe side. A `Changed` state is refused by the session gate at the next entry, and the marker
stays set, so a command that names no tenant is refused with `SignInRefused`; the only cost is that
the operator meets a stop where a disconnect was asked for. The alternative, the warning inside the
gate, would let the command clear first, but it would then print only after the answer and never
under `-WhatIf`, which is the case the rule of
[#warning-before-confirmation](#warning-before-confirmation) exists for. So the help says to run it
with the default warning preference, or to end the other session first with `Disconnect-MgGraph`,
after which the state reads `Absent` and there is nothing to warn about. Two tests in the same
Describe pin it, one per way to stop: `-WarningAction Stop` on a `Changed` state and a global
`$WarningPreference` of `Stop` on an `Untracked` one each throw that error id, and the state, the
marker and the `Disconnect-MgGraph` count are as they were (the fingerprint too, for `Changed`). The
preference variable has to be set globally: module code does not see a caller's local one, measured
by a first version of the test that set it locally and saw no exception.

Ruling: an `Untracked` session that the process holds is treated as not the module's. The module
cannot prove it is its own, and leaving it is the safe direction. A session from an earlier import
of the module reads `Untracked` -- re-importing clears `$script:_OERAuthState` and the fingerprint
with it, while the SDK session stays in the process -- so it is left, and the warning names
`Disconnect-MgGraph`. Cost if wrong: after a re-import the operator ends that session by hand.

Leaving a session does not protect it from the module's next sign-in. After `Disconnect-OER` the
state is `Untracked`, and the next `Initialize-OERAuth` sign-in runs `Connect-MgGraph`, which
replaces whatever session the process held, as any `Connect-MgGraph` does (above). What A4 changes is
only that `Disconnect-OER` no longer ends a session it did not start; the help, the README and the
about topic say both halves. The one gap is the gap every gate read has: another runspace's
`Connect-MgGraph` between the read and the disconnect is not seen (see "What is still not covered"
below).

The tests are in `tests/Unit/Public/Disconnect-OER.Tests.ps1`, Describe `Disconnect-OER ends only
the Graph SDK session the module connected (A4, BL-67)`: one test per state -- `Own`, `Changed`,
`Untracked` with no state and with a state that has no fingerprint, `Untracked` with no session,
and `Absent` -- each pinning the exact warning text and its count (one, or none), whether
`Disconnect-MgGraph` ran, and that the state is cleared; `Changed` also the A10 marker. Two
`-WhatIf` tests. On `Changed` the warning is written and the state and marker are untouched, which
a warning inside the gate could not do. On `Own` `Disconnect-MgGraph` is not called, the state and
marker stay and no warning is written: on every other state the call is not made whatever the gate
does, so this is the one test that holds the disconnect itself inside the gate. An AST test, read
from the loaded function, requires the one `Write-Warning` to start before the first `ShouldProcess`
call. The A18 test now expects the one read the decision makes (`Get-MgContext` once after the
disconnect, and still once after the module is asked what it tracks). MUTATIONS (G5), each one edit
to a copy of `source/` run through the covering tests: (a) `Disconnect-MgGraph` called
unconditionally (`if ($true)`) turns the `Changed`, both `Untracked`-with-a-session,
`Untracked`-with-none and `Absent` tests red; (b) the `Untracked` arm of the warning condition
dropped turns the two `Untracked`-with-a-session tests red; (c)
`$null -ne (Get-OERGraphSessionFingerprint)` dropped, so every `Untracked` warns, turns the
`Untracked`-with-none test red; (d) the `Write-Warning` block moved inside the gate turns the
`-WhatIf`-on-`Changed` test, the AST order test and the cohort's after-the-gate rule red (the last
with `OER_COHORT_SOURCE_ROOT` pointed at the mutated copy); (e) `'Own'` swapped for `'Changed'` in
the disconnect condition turns the `Own` test, the first Describe's `calls Disconnect-MgGraph for
the session the module connected` and the `Changed` test red; (f) the `if ($GraphSessionState -eq
'Own')` block moved out of the gate, after it, turns the `-WhatIf`-on-`Own` test red.

**Why `Invoke-OERGraphRequest` checks again before every call.** MEASURED 2026-10-05 in
PowerShell 7, with plain functions and no module code:

1. A terminating error that a nested advanced function raises with `$PSCmdlet.ThrowTerminatingError`
   -- the shape of `Write-CmdletError -Terminating` -- ends that function, but the CALLING function
   carries on with its next statement, with the default error preference as well as under
   `-ErrorAction SilentlyContinue` or `Ignore`, unless a `try` or `trap` is active somewhere up the
   call stack. Inside any `try`, Pester's included, it propagates.
2. Under `SilentlyContinue` or `Ignore`, a function carries on past its OWN `throw` to its next
   statement; inside any `try` it propagates.
3. Under the same preference with no `try` up the stack, a `throw` inside a `catch` block resumes
   after the whole `try` statement, not at the `catch` block's next statement.

No public cmdlet wraps its `Initialize-OERAuth` call, so at a prompt or in a script a cmdlet carries
on past the refusal at its entry (fact 1) and reaches its Graph calls. `Invoke-OERGraphRequest`
therefore asks `Get-OERGraphSessionState` before every request it sends: at the head of each attempt
-- the first, each throttled retry, each page under `-All` -- outside the attempt's `try`, whose
`catch` would turn the refusal into a Graph failure, and again after the `Initialize-OERAuth` call of
the claims-challenge step-up and of the token-rejected retry, since each of those sends a request
too. Each gate is a `throw` followed by a `return`, and the `return` is load-bearing: under
`SilentlyContinue` or `Ignore` it is what keeps the request from going out (fact 2). At a prompt
the operator therefore sees more than one error for one cmdlet: `GraphSessionChanged` at its entry,
and then an error for each Graph call it attempts -- `GraphSessionChanged` from the transport,
carried in the message where the cmdlet re-publishes a failed lookup under its own id
(`PrincipalNotFound`, for example) or the apply engine reports it as a `Failed` row. That is why the
user-facing texts say the Graph CALLS are refused, never that the cmdlet stops.

A paged read that a refusal interrupts ends. The paging `catch` re-throws, and under fact 3 that
resumes after the whole `try` statement, so the `catch` sets `$PageFailed` and the loop checks it
straight after the `try` statement: `if ($PageFailed) { return }`. Under
`-ErrorAction SilentlyContinue` or `Ignore` outside any `try`, a page whose request fails (the
refusal included) therefore ends the read with nothing on the success channel instead of looping.
It is `return`, not `break`, so on that path the caller gets no partial collection that reads as
complete. Inside a `try` the refusal propagates, with `PartialValue`, `NextLink` and `PageNumber` on
its exception, as for any page whose request fails.

The proofs run in a runspace with no `try`. Pester runs every test inside one, where all three facts
turn into propagation, so a test there cannot see a cmdlet carry on. G6, G6b, G7 and G9 in
`tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` (Describe
`Invoke-OERGraphRequest Graph SDK session gate (A18)`) run the module in a second runspace with no
`try` (`Invoke-OERWithConfirmAnswer` in `tests/Unit/TestHelpers/OERConfirmHost.ps1`), with the
transport tripwire installed, and assert that no request goes out once the session has changed.

**Azure Resource Manager after the refusal.** The check is at every `Initialize-OERAuth` entry, so
an Azure-only cmdlet's `-IncludeARM` entry raises `GraphSessionChanged` too, and inside a `try` that
ends the cmdlet. Outside any `try` the cmdlet carries on (fact 1). Until the sign-in latch existed
its Azure Resource Manager calls then went out, with whatever ARM token the state held; since then
the refusal leaves the cmdlet latched, so `Invoke-OERArmRequest` refuses each of its ARM requests
with `SignInRefused` before it materializes a bearer
([A command whose sign-in is refused sends nothing](#a-command-whose-sign-in-is-refused-sends-nothing),
below). There is still no session gate in the ARM wrapper: ARM sends the module's own token, which
another `Connect-MgGraph` does not touch, so an ARM call of a cmdlet whose entry was NOT refused --
the session replaced in the middle of a cmdlet, after its entry -- still goes out to the module's
own tenant with that token, while the session gate refuses that cmdlet's Graph calls.

The ARM token drop predates the latch and stays as a second guard that does not depend on it. A
refused request that names another tenant, identity or cloud -- the `$ArmIdentityUnchanged` rule the
state rebuild already applies -- drops that token first (`ArmToken`, `ArmTokenExpiry`,
`ArmResourceUrl` and `ArmTokenTenantId`), since `Invoke-OERArmRequest` compares nothing and sends
whatever token the state holds. A request that reached the send after the drop used to carry an
empty bearer, to the public cloud's host whatever cloud the session was in, and ARM would have
answered it with 401 (never measured); since Sprint 10 step 3 (BL-65, BL-96) the wrapper refuses it
with `ArmTokenAcquisitionFailed` before it is sent, instead of sending it
([#arm-transport](#arm-transport) holds the refusal and its proofs). The same change makes a state
without `ArmResourceUrl` take its cloud's ARM host from its `Environment`, not the public cloud's --
which no state the module builds needs, since the drop clears the token and the url together.
Before the drop existed, the final review of A18 MEASURED `Get-OERSubscription -TenantId` naming a
second tenant, in a runspace with no `try`, being refused and then listing the first tenant's
subscriptions with the first tenant's token. G10 in
`tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` (Describe
`Initialize-OERAuth refusal leaves no ARM token for another tenant (A18, R20)`) runs that call in a
runspace with no `try` and pins that no request carries that token. A12 and A13 in
`tests/Unit/Private/Initialize-OERAuth.Tests.ps1` pin the drop and its limit: a refused request for
the module's own tenant, identity and cloud keeps its token, since that token is for the tenant the
request meant. The cost falls on an app-only session: once
`Connect-OER` has taken the session back after a drop, it needs `Connect-OER -IncludeARM` again
before an Azure cmdlet, since the module never keeps the certificate or the client secret; a
delegated or managed identity session re-acquires its ARM token by itself. An ARM-only cmdlet that
has to acquire an ARM token is refused at its `Initialize-OERAuth` entry like any other, before any
token call. Any Graph call such a cmdlet makes goes through the gate like every other. The
user-facing texts therefore say that, after the refusal, the cmdlet's Microsoft Graph calls are
refused with `GraphSessionChanged` and its Azure Resource Manager calls with `SignInRefused`.

**What is still not covered.**

- A session swapped by another runspace between the gate and the request. The gate reads the
  session, and the SDK reads it again when it sends; a `Connect-MgGraph` in another runspace of the
  same process in between is not caught.
- A session swapped by another runspace between the module's own `Connect-MgGraph` and the
  fingerprint read straight after it. `Initialize-OERAuth` records whatever session the process holds
  at that read, so another runspace's `Connect-MgGraph` landing in between is recorded as the
  module's own session, and the module's Graph calls then go out under it without a refusal.
- The live values of the eight properties (check 1.1) and the carrying half of the premise (check
  1.3), both in section 1 of the live checklist named above.

**The message, in four places.** `Connect-OER`'s and `Disconnect-OER`'s `.DESCRIPTION`, the
README's `### Disconnect` and the about topic's `GRAPH SDK SESSION` section, which sits outside
`SWITCHING TENANTS` so that the README binding of that section stays untouched, say the same thing,
each in its own medium's voice: `Connect-OER`, and the automatic sign-in of any other cmdlet, sets up
a Graph SDK session with the module's token; another `Connect-MgGraph` that replaces it makes the
next OER cmdlet send nothing, refusing its Microsoft Graph calls with `GraphSessionChanged` and
(since the sign-in latch) its Azure Resource Manager calls with `SignInRefused`; the module never
switches the session back by itself, and `Connect-OER` run with the same sign-in the session used
(for an app-only session, its certificate or client secret, since a bare `Connect-OER` signs in
interactively) or a new PowerShell process are the ways out; after a `Disconnect-MgGraph` run
instead of `Disconnect-OER` the next cmdlet signs in again by itself, except on an app-only session;
and `Disconnect-OER` ends only the session the module connected, leaving any other with a warning
(A4). The README and the about topic add one sentence the two help texts do not carry: runspaces in
one process (`ForEach-Object -Parallel`, `Start-ThreadJob`) share one Graph SDK session, so a
parallel fan-out across tenants in one process gets `GraphSessionChanged`, and each tenant belongs
in its own process (`Start-Job`, or a separate PowerShell process). `Connect-OER`'s `.DESCRIPTION`
alone carries the general case as well: a cmdlet whose own sign-in fails or is refused sends no
Microsoft Graph or Azure Resource Manager request (`SignInRefused`).

**The old guidance, and what was known about it.** Until the check existed, the same four texts
told the operator to run `Disconnect-OER` before their own `Connect-MgGraph` in the same process, or
to use a new process. They no longer do: the module refuses its Graph calls under another session
instead of relying on that order. What the record held about that order stays true as history:

- MEASURED, for a certificate sign-in: check T.8 in
  `docs/live-verification/feat-pim-group-approval-checklist.md` ran `Disconnect-OER`, then
  `Connect-MgGraph` with a certificate thumbprint and `-ContextScope Process`, and passed on
  2026-09-28 as the dedicated certificate identity: both identity lines `True`, then the two
  read-back counts, `0` and `0`.
- REPORTED, not saved, for a delegated interactive sign-in: check T.4 in
  `docs/live-verification/fix-withhold-prune-on-unresolved-entries-checklist.md` ran `Disconnect-OER`
  and then `Connect-MgGraph` with delegated scopes and `-ContextScope Process`. Its result reads
  "Output was not preserved; the operator reports every step completed as expected", dated
  2026-09-24. There is no captured output to point at.

Both checks disconnected first, so neither one ran the opposite order. The caution the live
checklists give for that order -- that `Connect-OER` leaves its raw access token in the Graph SDK's
process cache, which a later `Connect-MgGraph` would otherwise try to read as an MSAL cache -- was
the explanation `c2a5c70` wrote. In the history `main` carries, the text first appears in `c2a5c70`
(#10), in `feat-pim-group-approval-checklist.md`, and the same wording later appears in
`feat-directory-role-management-policies-checklist.md` (`55acea9`),
`feat-directory-role-assignments-checklist.md` (`6b952e6`) and
`feat-inventory-directory-roles-and-rename-checklist.md` (`d9783e9`).

MEASURED on 2026-10-05, in checks 1.1, 1.3, 2.2 and 2.5 of
`docs/live-verification/fix-refuse-a-changed-graph-sdk-session-checklist.md`, as the dedicated
certificate identity: a `Connect-MgGraph` with a certificate thumbprint and `-ContextScope Process`,
made straight after `Connect-OER` in the same process, fails with `AuthenticationFailedException`
(MSAL cannot deserialize the SDK's process token cache, which holds the module's raw access token)
and leaves no Graph SDK session at all. The module's next call then finds the session Absent, not
Changed: a delegated or managed identity session connects again by itself, and an app-only one
reports `AppOnlySessionCredentialUnavailable`. The same `Connect-MgGraph` made after
`Disconnect-MgGraph` succeeds and replaces the session, and the module refuses that one with
`GraphSessionChanged` (checks 2.2 and 2.5). INFERRED from the SDK source and not measured: a
`Connect-MgGraph -AccessToken`, or a delegated sign-in with the default `-ContextScope CurrentUser`,
does not read that process cache, and replaces the session as the `Disconnect-MgGraph`-first order
does.

### A command whose sign-in is refused sends nothing

**The finding.** Fact 1 under [The Graph SDK session](#the-graph-sdk-session) is not particular to
`GraphSessionChanged`. Every terminating error `Initialize-OERAuth` raises -- `GraphTokenAcquisitionFailed`,
`GraphConnectFailed`, `TenantMismatch`, `AppOnlySessionCredentialUnavailable`, `MissingClientSecret`,
`MissingClientCertificate` and `GraphSessionChanged`, and since Sprint 9 step 3 `TenantResolutionFailed`
-- ends `Initialize-OERAuth` and not the cmdlet
that called it, and no public cmdlet wraps its call. Finding F1 of the step 4b review (PR #24) was
therefore that a cmdlet run with `-TenantId B`, whose sign-in for B failed or was refused, carried on
and sent its Graph calls under the Graph SDK session tenant A left, and its ARM calls with whatever
ARM token the state held. For `Invoke-OERStructure -TenantId B -Prune` that is B's document applied
to A.

**The latch.** `Initialize-OERAuth` calls `Lock-OERSignIn` directly after its BL-74 check (see
[A command acts under the session it began with](#a-command-acts-under-the-session-it-began-with)),
which comes first so that a refusal there latches nothing of its own; until Sprint 9 step 2
`Lock-OERSignIn` was the first statement. It records the invocation of the command that called
`Initialize-OERAuth` in `$script:_OERSignInLatch` and returns it.
`Unlock-OERSignIn` removes that one entry, and `Initialize-OERAuth` calls it only where a sign-in
succeeded: at the cached return, and as the last statement of a new connection that went the whole
way -- after the ARM step, inside the big `try` and never in its `finally`, which also runs on every
terminating error. Every refusal, terminating error and early return leaves the entry in place. The
table is a `ConditionalWeakTable`, created on first use, and it stores only the boolean `$true`. Its
keys are the commands' own invocation objects, held weakly, so the table keeps no command alive, and
used only for their identity: the decision is a lookup by reference and never reads a key. The keys
are not empty -- the table can be enumerated, and each invocation carries its command's bound
parameters, `-TenantId` among them and, on `Connect-OER`, the `SecureString` secret and the
certificate as well -- but nothing reads them through the latch. Gate 10 of
[#static-source-gates](#static-source-gates) keeps both calls in `Initialize-OERAuth`.

**The latched frame is the immediate caller's.** `Lock-OERSignIn` latches the frame of the command
that called `Initialize-OERAuth` directly, which is the command's own frame only while the call
stands in the command's own function. MEASURED: a `& { }` script block carries an invocation of its
own, so a call moved into one, or into a nested function, latches a frame that ends at once, and the
command sends again after a refused sign-in -- with every unit test still green, since they mock
`Initialize-OERAuth`. So `Initialize-OERAuth` is called directly in the command's own function, and
gate 10 holds every call site under `source/` to that; the transports' own refreshes, in
`Invoke-GraphSingle` and `Invoke-ArmCallWithRefresh`, are the stated exception (Ruling R5).

**The gates.** `Get-OERSignInRefusal` walks `Get-PSCallStack`, innermost frame first, and returns the
name of the first frame whose invocation the table holds -- nothing when none is, and nothing at
once, without reading the stack, when the table was never created, which is the case in every unit
test that mocks `Initialize-OERAuth`. (With `-OutsideCaller`, which only `Initialize-OERAuth` passes,
for BL-74, the walk starts after the frame `Lock-OERSignIn` would latch; the transports never pass
it.) Both transports ask it before every request, and
`New-OERSignInRefusedError` is the single owner of the refusal: `SignInRefused`,
`AuthenticationError`, the latched command's name as its target, and a message that names no tenant,
account or token. In `Invoke-OERGraphRequest` the latch gate stands straight after each session gate
-- at the head of each attempt (the first, each throttled retry, each page under `-All`), and after
the `Initialize-OERAuth` call of the claims-challenge step-up and of the token-rejected retry --
outside the attempt's `try`, so a changed session is still reported as `GraphSessionChanged`. In
`Invoke-OERArmRequest` it stands once, in `Invoke-ArmCall`, which every request passes through (the
first, each throttled retry, the 401 retry and every page), before the bearer token is materialized
and before `Invoke-WebRequest`. Each gate is a `throw` followed by a `return`, for fact 2. The ARM
wrapper has no session gate (step 4b round 1, Ruling R2): an ARM call of a command whose entry was
not refused still goes out with the module's own token, as described under
[The Graph SDK session](#the-graph-sdk-session).

**Why the key is the command, not a module boolean** (step 4b round 1, Ruling R1). MEASURED by the
controller on 2026-10-05 in plain PowerShell 7, with no module code: a latch that any later
successful sign-in releases does not close F1. Almost every public cmdlet calls `Initialize-OERAuth`
in its `begin` block, and the apply handlers call public cmdlets (`New-OERGroup`, `Set-OERGroup`,
`Get-OERRoleAssignment`, ...) that call it again without `-TenantId`, inherit session A and hit the
cache: inside a refused `Invoke-OERStructure -TenantId B`, the first nested cmdlet would release a
boolean and every later write would go to A. A pipeline does the same: in
`Get-OERGroup -TenantId B | Remove-OERGroup` both `begin` blocks run first, so `Remove-OERGroup`'s
cache hit would release a boolean before `Get-OERGroup`'s `process` block reads. Keyed on the
invocation, and refused while ANY frame on the stack is held, a nested cmdlet's success releases
only its own entry and the refused outer command stays latched, and a pipeline neighbour's success
releases only its own. Measured the same way: `(Get-PSCallStack)[0].InvocationInfo` is
reference-equal to `$MyInvocation` in an advanced function's `begin`, `process` and `end` blocks, a
nested function sees its caller's frame at index 1, and `Get-PSCallStack` costs about 0.1 ms at a
depth of 60 frames -- the price each request pays once the table exists. Since Sprint 9 step 2 the
nested case no longer reaches the cache at all: a nested cmdlet's sign-in under a latched outer
command is refused at its entry (BL-74), so it releases nothing. The key still carries the pipeline
case, which BL-74 does not reach -- both `begin` blocks run before either `process` block, so no
latched frame is on `Remove-OERGroup`'s call stack when it signs in -- and the same-frame retry,
where a command whose own sign-in was refused signs in again and a success releases it.

**Opening again.** A command that finishes is on no call stack, so the latch does not refuse the
command after it. `Disconnect-OER` does not touch the table and has no need to. Until Sprint 9 step 3
that was the whole story: `Connect-OER`, or any new command whose own sign-in succeeded, sent again,
and there was nothing to clear -- which is also how the next command in a script, naming no tenant,
went on under the session the refused sign-in had left in place (BL-89). Since A10 the refusal leaves
something behind that does need clearing: the session-uncertain marker, under which a later command
that names no tenant is refused before it signs in, until a sign-in that names its tenant, a
successful `Connect-OER` or a `Disconnect-OER` clears it -- see
[A refused sign-in leaves the session uncertain](#a-refused-sign-in-leaves-the-session-uncertain). A
command that names its tenant is not affected by the marker, and signs in and sends as before.

Until a refused command finishes, it also refuses a command downstream of it in the same pipeline
while that command handles its output, since the refused frame is on the call stack then (measured): in
`Invoke-OERStructure -TenantId B ... | ForEach-Object { Get-OERGroup ... }`, the `Get-OERGroup`
requests are refused too -- conservative, and intended. Since BL-74 a sign-in made there is refused
at its entry as well, before any token call: `Get-OERGroup`'s here, which runs inside the refused
command's output, and so would be the sign-in of an `Invoke-OERStructure` piped after a refused
command, since its sign-in in `process` runs inside that command's output too. Read in the code,
not measured end to end: from `Initialize-OERAuth`'s side both are a latched frame outside the
caller, the shape the BL-74 unit Context pins. A downstream cmdlet piped directly, as in
`Get-OERGroup -TenantId B | Remove-OERGroup`, signs in in its `begin` block, before any output
exists, so BL-74 does not refuse that sign-in; the latch refuses its requests.

**What the operator sees.** Outside any `try`, a cmdlet whose sign-in was refused carries on, sends
nothing, and reports an error for each request it then attempts: `SignInRefused` from the transport
(`GraphSessionChanged` instead for a Graph request while the session stays changed), carried in the
message where the cmdlet re-publishes a failed lookup under its own id -- `PrincipalNotFound` from
`Get-OERActiveRoleAssignment`, `Get-OEREligibleRoleAssignment` or `Get-OERRoleAssignment` when
their principal lookup is the refused request, for example -- or where the apply engine reports it
as a `Failed` row. Inside a `try` the refusal at its entry propagates and ends it. The user-facing
texts therefore say that such a command sends nothing, never that it stops.

**`ArmTokenAcquisitionFailed`** (step 4b round 1, Ruling R4) is the one refusal that is not
terminating: it writes its error and returns early, after the Graph half has connected or come from
the cache. It leaves the latch set like every other early return, so that command's Microsoft Graph
calls are refused too, although its Graph session is in order. It reaches every command that signs
in with `-IncludeARM` and also calls Graph -- for example `Get-OERInventory -IncludeARM`,
`Export-OERInventory` and `Invoke-OERStructure` with ARM sections, and the `-IncludeARM` role
assignment cmdlets that resolve a principal through Graph. The rule is that every early abort leaves
the latch set, and this path is no exception; the cost is a whole command refused where only its
Azure half failed. This paragraph is about `Initialize-OERAuth`'s refusal. Since Sprint 10 step 3
(BL-65, BL-96) the ARM wrapper raises the same id too, as a terminating throw before it sends a
request that has no token to send; that refusal neither latches nor marks, since only
`Initialize-OERAuth` does either (see the bullet on a request never sent without an ARM token under
[#arm-transport](#arm-transport)).

**Where the key is not the public cmdlet.** The latch keys on the IMMEDIATE caller of
`Initialize-OERAuth`, which for the `begin`-block call of a public cmdlet is that cmdlet. Elsewhere:

- A refresh inside a transport (step 4b round 1, Ruling R5). The claims-challenge step-up and the
  token-rejected retry of `Invoke-OERGraphRequest` call `Initialize-OERAuth` from its nested
  `Invoke-GraphSingle`, and the 401 retry of `Invoke-OERArmRequest` from its nested
  `Invoke-ArmCallWithRefresh`. A sign-in refused there latches that nested function, so
  `SignInRefused`'s target names an internal function, only that one retry is refused, and the
  command's next request is a new transport call, which the latch does not refuse. The session is
  the same tenant's, and the session gate covers a changed one. The message's "this command" then
  means that internal function, which only the target shows.
- Three private helpers call `Initialize-OERAuth` themselves: `Resolve-OERInventoryScopeTree`,
  `Resolve-OERReviewerScope` and `Resolve-OERTargetList`, each forwarding the `-TenantId` its caller
  passed it. A refusal there latches the helper, and refuses only the requests made inside it. A
  refusal at the calling cmdlet's own entry latches the cmdlet, and with it every request the helper
  makes, since the cmdlet's frame is on the helper's call stack. Since BL-74 it refuses the helper's
  own sign-in too, before its token call: the latched cmdlet is a frame outside the helper, so an
  `Export-OERInventory -TenantId B` whose own sign-in to B was refused no longer has
  `Resolve-OERInventoryScopeTree` try B's sign-in again. The helper is not latched by that refusal;
  the cmdlet's latch covers its requests. Read in the code, not measured.
- A transport's refresh is not reached by BL-74 in practice (read in the code): it follows a
  request that went out, and the latch gate in front of that request found no latched frame on the
  call stack the refresh shares.

**The proof.** Pester runs every test inside a `try`, where the refusal propagates, so the carrying
on is proved in a runspace with no `try`, as for the session gate. H1 in
`tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` (Describe
`A command whose sign-in was refused sends nothing through either transport (A19, F1)`) runs
`Invoke-OERStructure -TenantId` naming another tenant, with `-WhatIf`, over a state for tenant A whose
Graph SDK session is still the module's own, with that sign-in failing at its token call
(`GraphTokenAcquisitionFailed`). No Graph and no ARM request leaves -- neither the group read the
handler makes itself nor the role assignment read of a nested `Get-OERRoleAssignment`, whose own
sign-in, which A's cache would have answered before Sprint 9 step 2, is now refused at its entry
(BL-74) -- both sections answer with rows, and none is planned or written. H2 pinned, until Sprint 9
step 3, that a plain command after it, on the same state, sent its request; since A10 it pins the
opposite -- that such a command, naming no tenant, sends nothing until a command names the tenant
(see [A refused sign-in leaves the session uncertain](#a-refused-sign-in-leaves-the-session-uncertain)).
H3, H4 and H5 pin BL-74 in the same
Describe: H3 is H1 with A's Microsoft Graph token two minutes from expiry, where the nested sign-in,
had it got past the check, would renew it, and it shows one token call (the refused one) and no
`Connect-MgGraph`; H4 pipes two documents to `Invoke-OERStructure -TenantId`, the first document's
sign-in failing, and shows the second document's own sign-in attempted and its group read sent --
the command's own latched frame is not a reason to refuse. In H3 the nested refusal is caught by
the apply handler's own `try`; H5 has no `try` anywhere. In H3's state it pipes a groups-only
`Invoke-OERStructure -TenantId` into `ForEach-Object { Get-OERGroup -Filter ...; $_ }`, so
`Get-OERGroup` signs in in its `begin` block, outside any `try`, inside the refused command's
output, which `Invoke-OERStructure` also emits outside any `try`. It shows the same single token
call, no connection, no Graph request, and the `SignInRefused` that `Initialize-OERAuth` raised
naming `Invoke-OERStructure`. The latch's own states are pinned in
`tests/Unit/Private/Initialize-OERAuth.Tests.ps1` (Describe `Initialize-OERAuth sign-in latch (A19)`,
which holds the BL-74 Context `refused under a latched outer command (BL-74)`), and each wrapper's
gate in its own test file (Describes `Invoke-OERGraphRequest sign-in latch gate (A19)` and
`Invoke-OERArmRequest sign-in latch gate (A19)`).

### A command sends nothing under a sign-in a later command replaced

**The finding (F-E).** Round 1 of step 4b stopped on it, and it is older than the round: it was
present in the first version. In a pipeline every `begin` block runs before any `process` block,
and almost every public cmdlet signs in in its `begin` block and acts in its `process` block:
counted from the source on 2026-10-06, and again with the AST after Sprint 9 step 2, 84 of the 86
DIRECT public `Initialize-OERAuth` call sites -- one in each of 86 files -- stand in a `begin`
block, and the other two, in `Invoke-OERStructure` and `Connect-OER`, in `process`. Six more public
cmdlets sign in in `process` INDIRECTLY, through a private helper that calls `Initialize-OERAuth`
itself. Three also sign in in `begin`, so their own frame remembers the identity and this
subsection's gate compares it: `Export-OERInventory` (`Resolve-OERInventoryScopeTree`),
`New-OERAccessReviewDefinition` and `Set-OERAccessReviewDefinition` (`Resolve-OERReviewerScope`).
The other three sign in nowhere else, and only when a value is a name:
`New-OERAccessPackageApprovalStage` and `New-OERAccessPackageRequestorScope`
(`Resolve-OERTargetList`) and `New-OERAccessReviewStage` (`Resolve-OERReviewerScope`) -- see
[A command acts under the session it began with](#a-command-acts-under-the-session-it-began-with).
So the first command's `process` block acts under the session a LATER command's sign-in switched to:
`New-OERGroup -TenantId A ... | Add-OERGroupMember -TenantId B` created the group in B, with no
error. MEASURED in plain PowerShell 7, with no module code: two functions that each sign in in their
`begin` block, piped one into the other, report "creates grp under session B (named A)". The rest
was read in the code.

**Why neither round 1 gate sees it.** Both sign-ins succeed. The latch holds a command only while
its sign-in is refused, and each of the two commands released its own entry at its own success. The
session gate compares the Graph SDK session with the one the module's own `Connect-MgGraph` left,
and the downstream command's `Connect-MgGraph` is the module's own session -- for B. Everything the
two gates read is true; what is wrong is which command the session was signed in for.

**The memory.** Where `Initialize-OERAuth` succeeds -- exactly where `Unlock-OERSignIn` releases
the latch: at the cached return, and as the last statement of a new connection that went the whole
way -- `Register-OERSignInIdentity` remembers which identity the calling command signed in as, keyed
on the same invocation the latch uses (`$SignInCaller`, which `Lock-OERSignIn` returned at entry).
The table, `$script:_OERSignInIdentity`, is a `ConditionalWeakTable` like the latch's: created on
first use, keyed weakly on the commands' own invocation objects, and used only for their identity.
Its value is one string from `Get-OERSignInIdentity`: a tenant, then the state's AuthMethod, ClientId
and Environment, in that fixed order, each read as a string (a missing one as empty) and joined by a
line feed -- never a token. The tenant term is the tenant the Graph token was issued for
(`TokenTenantId`) when that is a GUID, and the tenant as named (`TenantId`) otherwise, never the ARM
token's (BL-77, Sprint 9 step 3; until then it was always `TenantId`, so the four terms were exactly
the ones `$ArmIdentityUnchanged` compares -- see "One tenant named two ways" below). A later success of
the same command replaces its value, and a success that leaves no state removes its entry, so that
command is no longer compared. One function builds both the remembered and the compared value, so
the list of terms cannot drift between the two.

**The gate.** Both transports ask `Get-OERSignInSupersession` before every request. It returns at
once, without reading the call stack, when the table was never created -- the case in every unit
test that mocks `Initialize-OERAuth`. Otherwise it reads the current identity once, walks
`Microsoft.PowerShell.Utility\Get-PSCallStack` from the innermost frame outwards, and returns the
name of the first frame whose invocation the table holds with a value that is not `-eq` the current
identity -- `'a script block'` when that frame has no command name. The comparison is PowerShell's
`-eq`, which ignores case, as `$ArmIdentityUnchanged` compares its terms. A frame the table
does not hold is not compared, so a command with no memory is never refused by this gate. When it
returns a name, the transport throws the record `New-OERSignInSupersededError` builds --
`SignInSuperseded`, `AuthenticationError`, that command's name as its target, and text that names no
tenant, account or token and fits the cause (see "Why no state counts as a difference" below) --
followed by a `return`, for fact 2 under [The Graph SDK session](#the-graph-sdk-session).

**Why any frame, and not the nearest.** The nested case. The apply handlers and several public
cmdlets call public cmdlets that sign in again without `-TenantId` (see "Why the key is the command"
under the previous subsection). In `Outer -TenantId A | Down -TenantId B`, a cmdlet nested in
`Outer`'s `process` block signs in after `Down`'s `begin` block switched the state to B, hits B's
cache and remembers B. Its own frame matches the state, so a walk that stopped at the nearest
remembering frame would let it write to B on `Outer`'s behalf. The walk goes on past a frame whose
memory equals the state and finds `Outer`, which remembers A.

**Why the innermost frame that differs is the target.** In the nested case the inner frames
inherited the current state and match it. The command whose sign-in another command replaced is the
outer one, and it is the command the message speaks to ("Run the commands as separate statements").
The first frame that differs, walking outwards, is the closest such command to the request.

**Why no state counts as a difference.** When the module holds no state at all -- after a
`Disconnect-OER` run inside the pipeline, for example -- there is no current identity, and a
remembered string is never `-eq` to `$null`, so every remembering frame differs and the request is
refused with `SignInSuperseded`. Refusing is the safe direction: the request would otherwise go out
under no session of the module's, or with no token. The cost is that such a pipeline reports
`SignInSuperseded` instead of an authentication failure.

**The text fits the cause (BL-92, Sprint 10 step 3).** The record used to carry one text for both
causes, saying that another OER command in the same pipeline signed in to a different tenant or
identity -- which is untrue after a `Disconnect-OER`, where no command signed in at all.
`New-OERSignInSupersededError` now builds four texts, with the same id, category and target, by cause
and by effect:

- By cause, from the module's state. When it holds a session, another command's sign-in replaced it,
  and the text says so and advises separate statements. When it holds none, `Disconnect-OER` ended the
  module's session after the command began, and the text says that and advises running `Disconnect-OER`
  as a statement of its own, after the commands that use the session. The function reads the state
  itself (`$null -eq $script:_OERAuthState`, the test `Get-OERSignInIdentity` makes for "not signed
  in") and takes no argument for it. Ruling: the callers do not pass the cause, so the transports'
  gated statements stay as they are, `throw (New-OERSignInSupersededError -Command $X)`, and
  `Disconnect-OER` is the only place under `source/` that sets the state to `$null` (a module that
  never signed in also holds `$null`, but then no command remembers an identity and no snapshot
  differs, so nothing is refused). Gate 10 of `tests/QA/sourcehygiene.tests.ps1` does not hold the
  arguments of that call: `Test-OERGateBody` matches the factory by call name only, so a transport
  that passed `-Document` would stay green there. What holds it is the last Context of
  `tests/Unit/Private/New-OERSignInSupersededError.Tests.ps1`, "only Invoke-OERStructure passes
  -Document (BL-92)", which reads the loaded `Invoke-OERGraphRequest`, `Invoke-OERArmRequest` and
  `Invoke-OERStructure` and requires every transport call to bind no `-Document` (an abbreviation or
  a splat counts as binding it) and `Invoke-OERStructure`'s one call to bind it.
- By effect, from the new `-Document` switch. A request says that the module sends nothing while the
  command runs and that "this request was not sent". With `-Document` the text says the command "did
  not apply this document" and that Omnicit.EntraRBAC "sent nothing for it". Only `Invoke-OERStructure`
  passes it, since what it refuses is a whole document, before it signs in. The two transports refuse
  one request, and the three builders keep the request wording too (Ruling: what a builder refuses is
  its lookup request, which is a request, and not an object it was asked to apply).
- The command's name is the only value in any of the four. It is the argument of the last `-f`, and
  the format string is composed from fixed fragments alone, so a name that holds `{0}` is written as
  passed.

The tests build every variant under the state it names and put the state back; the cause tests also
hold the state `@{}`, which is a held session and not the ended one, and a mutation that keys the cause
on a field of the state instead of on `$null` turns it red.

**The order of the three gates.** In `Invoke-OERGraphRequest` the supersession gate stands straight
after each latch gate, which stands straight after each session gate: at the head of each attempt
(the first, each throttled retry, each page under `-All`), and after the `Initialize-OERAuth` call
of the claims-challenge step-up and of the token-rejected retry. In `Invoke-OERArmRequest` it stands
once, in `Invoke-ArmCall`, straight after the latch gate and before the bearer token is
materialized. The session gate comes first, so a changed session is still reported as
`GraphSessionChanged`; the latch gate next, so a command whose own sign-in was refused is still
reported as `SignInRefused`. All three stand outside the attempt's `try`, whose `catch` would turn a
refusal into a Graph failure. At the two Graph retry sites, and on the ARM 401 retry, the
supersession gate also refuses a step-up or a refresh whose sign-in changed the state's identity: a
command on the call stack still remembers the identity from before it.

**What it costs.** A pipeline that deliberately spans tenants or identities is refused, and more of
it than the command whose sign-in was replaced. MEASURED on 2026-10-05, in plain PowerShell and in
the round's end-to-end tests: a downstream command processes each object inside the upstream
command's output call, with the upstream command's frame still on the call stack, in `Up | Down`
and in `Up | ForEach-Object { Inner }` alike. So in
`Get-OERGroup -TenantId A | ForEach-Object { New-OERGroup -TenantId B ... }` the downstream
`New-OERGroup` sends nothing to B -- its requests are refused, the refusal naming `Get-OERGroup` --
and any later request `Get-OERGroup` makes is refused too: the next group's member read under
`-IncludeMembers`, for example. Its listing itself goes out under A, since `Get-OERGroup` reads
every page of a `-Filter` or `-All` listing before it emits the first group (read in the code).
That is the any-frame rule working as decided, and it is the rule the user-facing texts state: one
pipeline works in one tenant with one identity. A cross-tenant copy is two statements, each of which
signs in and finishes before the next one starts: `$Groups = @(Get-OERGroup -TenantId A ...)`, then
`foreach ($Group in $Groups) { New-OERGroup -TenantId B ... }`. (`$Groups | New-OERGroup ...` is not
the shape, since `New-OERGroup` binds nothing from the pipeline.) The same pipeline naming the same
tenant and identity twice sends every request, and so do two separate statements naming different
tenants.

Two shapes that worked before this round are refused now, both on the safe side. The first is a
copy of a whole structure: `Get-OERInventory -TenantId A ... | Invoke-OERStructure -TenantId B`
(`-InputObject` binds the inventory from the pipeline, under its alias `Inventory`).
`Invoke-OERStructure` signs in to B in its `process` block, inside `Get-OERInventory`'s output,
while `Get-OERInventory`'s frame still remembers A, so every request of the apply is refused, the
refusal naming `Get-OERInventory` (read in the code, by the same rule as the measured
`Up | Down`). The working form is two statements:
`$Inventory = Get-OERInventory -TenantId A ...`, then
`Invoke-OERStructure -InputObject $Inventory -TenantId B ...` -- and since Sprint 9 step 6b
(BL-88, A14) a line between them that removes the inventory's `tenantId`,
`$Inventory.PSObject.Properties.Remove('tenantId')`: the export names tenant A, and the apply
refuses it in B with `DocumentTenantMismatch` otherwise, before its sign-in when B is a tenant ID.
The pipeline form is now refused the same way, and when B is a tenant ID that refusal comes first,
before `Invoke-OERStructure` signs in to B at all (read in the code). See
[A document names the tenant it was exported from](#a-document-names-the-tenant-it-was-exported-from).
The second was one tenant named two ways, and Sprint 9 step 3 ended it (BL-77, below).

**One tenant named two ways (BL-77).** HISTORY: until Sprint 9 step 3 the identity's tenant term was
the tenant as the caller NAMED it, the value `TenantId` holds in the state -- the same key the cache
predicates compare -- so a GUID on one command and a domain on another were two identities, and so
was no tenant named at all before the module held a state, which records it as `organizations`.
MEASURED by the final review of this round, with stand-ins of the cmdlets' shape and the module's own
sign-in: `'x' | Up -TenantId <guid> | Down -TenantId <its domain>`, one tenant, sent nothing and
reported `SignInSuperseded` for both commands; so did a pipeline after `Connect-OER` by GUID where
only the downstream command named the domain. That was a false refusal, not a wrong-tenant write, and
comparing the granted tenant was recommended to the architect.

Since the tenant lookup checks every named tenant against the Graph token (BL-12), the granted tenant
is the one the session acts on, and `Get-OERSignInIdentity` now uses it (Sprint 9 step 3, Ruling
R15): the tenant term is `TokenTenantId` when it is a GUID, `TenantId` otherwise, never
`ArmTokenTenantId`, since the ARM token is not always acquired and the identity must not change when
it is. That left the ARM token of a sign-in naming no tenant compared with nothing, and so able to
come from another tenant than the identity's; since the final review of Sprint 9 step 3 (Ruling F3)
an ARM token such a sign-in acquires is compared with the Graph token instead, and since round 1 of
that step (A13) a renewal of the Graph token carries the cached ARM token only for the renewed Graph
token's tenant -- both under
[Requested tenant vs granted tenant](#requested-tenant-vs-granted-tenant). One tenant named by GUID
on one command and by domain on another, or not named at all, is then ONE identity to the
supersession gate and to the snapshot, and P18 below pins the measured pipeline sending. What did not
change is the session cache, still keyed on the tenant as named: a command that names its tenant
differently from the session inherits nothing from it and signs in again, with the default
interactive method when it names no credential -- on an app-only session, a browser prompt, and then
an identity that differs in its method, which the gate does refuse. So the rule to name the tenant
explicitly and consistently (the README's Sovereign Clouds section, the about topic's SOVEREIGN
CLOUDS) stands, now for the cache rather than for the gate. When `TokenTenantId` is not a GUID --
AzAuth reported no tenant for the token, or a state carries none -- the term falls back to the
tenant as named, and one tenant named two ways is again two identities there.

**What the operator sees.** A public cmdlet catches the transport's refusal the way it catches any
failed request: it writes it as an error record -- or the apply engine as a `Failed` row -- and
carries on; the refused request is simply not sent. The record's target is the command whose
sign-in was replaced, which is not always the command that wrote it: a downstream command's record
names the upstream command, and its `FullyQualifiedErrorId` names the command that wrote it
(`SignInSuperseded,<writer>` in the tests' terms). Where a cmdlet re-publishes a failed lookup
under its own id, the refusal travels in that record's message instead: `New-OERGroup` reports its
refused name lookup as `GroupResolveFailed`, so for `New-OERGroup` the operator sees that id and
not `SignInSuperseded`. MEASURED in the round's end-to-end tests: a transport throw caught nowhere
at all ends the whole script it runs in, which is why the stand-ins there catch each request the
way the public cmdlets do. The texts therefore say that such a command sends nothing, never that it
stops or that a refused request ends the statement.

**A consequence, stated.** By the same rule, an outer command whose NESTED cmdlet deliberately signs
in to another tenant or identity is refused for the outer command: the outer frame's memory differs
from the state the nested sign-in left. No cmdlet under `source/` does that today -- read in the
code, every nested sign-in passes the outer command's own `-TenantId`, or none. This is the rule
working, not a limit to work around: work in another tenant belongs in a statement of its own.

**Known limits.**

- Runspaces in one process (step 4b's F5). Each runspace imports its own copy of the module, with
  its own state and its own memory, so a sign-in in another runspace is never compared (INFERRED
  from how PowerShell scopes a module's state, not measured in this round). What the runspaces
  share is the process's Graph SDK session, which only the session gate covers, with the gaps listed
  under [The Graph SDK session](#the-graph-sdk-session). Each tenant still belongs in its own
  process.
- `Invoke-OERStructure` and `Connect-OER` sign in in their `process` block, not in `begin`. In
  `Invoke-OERStructure -TenantId A ... | X -TenantId B`, X's `begin` block signs in to B first, then
  `Invoke-OERStructure`'s own sign-in switches the state to A. `Invoke-OERStructure` sends every
  request to A, as it should, its `-Prune` deletions included, and it is X whose requests -- made
  inside `Invoke-OERStructure`'s output, with X remembering B -- are refused. `Connect-OER` outputs
  nothing, so no command downstream of it runs per object. The any-frame rule covers both
  directions, and the user-facing texts therefore speak of the command whose sign-in another one
  replaced, which is usually, not always, the first. Read in the code, not measured.
- CLOSED in Sprint 9 step 2 (BL-76), and older than this round: `Invoke-OERStructure` WITHOUT
  `-TenantId` upstream of a command that names another tenant. Its sign-in in `process` names no
  tenant, so it inherited the state the downstream command's `begin` block had already switched to
  B, remembered B, and nothing differed: its document, `-Prune` deletions included, was applied to B
  with no error. MEASURED by the final review of this round with a stand-in of
  `Invoke-OERStructure`'s shape (a sign-in with no tenant in `process`, then a DELETE): after a
  sign-in to A, `'doc' | <stand-in> | Down -TenantId B` sent the stand-in's DELETE under B, with no
  error. The same review measured that a downstream command's `begin` block runs before the
  upstream `process` block even when the downstream command takes no pipeline input, so
  `Invoke-OERStructure -Path x.json -Prune | <any OER cmdlet> -TenantId B` applied the document in B
  as well (inferred from those two measurements). This round did not close it, and its texts told
  the operator to name `-TenantId` on `Invoke-OERStructure` or to run it as a statement of its own.
  The fix is not the one this bullet first sketched -- capturing the tenant in `begin` and naming it
  in the `process` block's sign-in, which A6 rules out -- but a snapshot of the whole identity in
  `begin`, compared before that sign-in: `Invoke-OERStructure` now refuses the document with
  `SignInSuperseded` and sends nothing for it. The three name-looking builders had the same gap
  (BL-81) and are closed the same way. See
  [A command acts under the session it began with](#a-command-acts-under-the-session-it-began-with).
- CLOSED for a document that names its tenant (BL-88, Sprint 9 step 6b); OPEN, and older than
  Sprint 9 step 2, for a document without `tenantId` and for the three name-looking builders:
  `Invoke-OERStructure` or one of the builders WITHOUT `-TenantId`, called inside a script block or
  a function in a pipeline. The snapshot that closed the bullet above is taken when the command's
  own `begin` block runs, and inside a script block that is when the block runs, after every `begin`
  block of the outer pipeline. In
  `Get-ChildItem *.json | ForEach-Object { Invoke-OERStructure -Path $_ -Prune } | ForEach-Object -Begin { Connect-OER -TenantId B } -Process { $_ }`,
  after a sign-in to A, `Invoke-OERStructure` begins under B, compares B with B, signs in under B and
  remembers it, so neither its own check nor the supersession gate sees a difference, and `-Prune`
  runs in B with no error. The three builders, called the same way, look their names up in B.
  MEASURED by the final review of Sprint 9 step 2 with plain-PowerShell stand-ins of the shape: the
  direct pipeline was refused, and the same command wrapped in `ForEach-Object` applied under B. That
  step left the gap open (its Ruling R11), and A11 parked it for Philip (P-4). Since Sprint 9 step 6b
  an exported document names the tenant it was read from (`tenantId`), and `Invoke-OERStructure`
  compares it, after the sign-in, with the tenant the session's tokens were issued for: a document
  in that pipeline exported from A is refused in B with `DocumentTenantMismatch` and nothing is read
  or written for it, whichever session the command began with -- see
  [A document names the tenant it was exported from](#a-document-names-the-tenant-it-was-exported-from).
  A document without `tenantId` is still applied in B, and the builders still look their names up
  there, so the texts still tell the operator to name `-TenantId` on such a command, or to run it as
  a statement of its own: README's `### Disconnect` section and the about topic's
  `GRAPH SDK SESSION` in one sentence each, CLAUDE.md as a rule.
- A command that signs in again inside its own `process` block, to another tenant, replaces its own
  memory, and nothing compares that second sign-in with its first: it is the same command's own
  choice.

**The user-facing texts.** The README's `### Disconnect` section and the about topic's
`GRAPH SDK SESSION` section close with the same paragraph, outside `SWITCHING TENANTS` so that the
README binding of that section stays untouched: one OER pipeline works in one tenant with one
identity; if commands in it sign in to different tenants or identities, a command whose sign-in
another one replaced sends nothing more, every request made while it runs refused with
`SignInSuperseded`, the requests of a command handling its output included; most cmdlets sign in
before any command in the pipeline processes input, so that is usually the first command; a cmdlet
that reports a failed lookup under an error of its own, `New-OERGroup`'s `GroupResolveFailed` for
one, carries the refusal's message in that error instead; a tenant counts by the tenant its token
was issued for, so one tenant named by its GUID, by its domain or not at all is one tenant to this
check, but a command that names it differently from the session signs in again, with a pointer to
"Name the tenant explicitly and consistently" (until Sprint 9 step 3, BL-77, this clause said that a
tenant counted by the name given, so those were three sign-ins and a pipeline naming one tenant two
ways was refused); `Invoke-OERStructure` signs in when it processes its document, but
without `-TenantId` it acts only under the session it began with, and refuses a document with
`SignInSuperseded`, sending nothing for it, when another command in the pipeline has signed in to a
different tenant or identity by then -- any sign-in counting when the module held no session --
and the three builders that look up a name do the same before they resolve what they are given
(until Sprint 9 step 2 this clause said that nothing refused it, and told the operator to name
`-TenantId` on it or run it as a statement of its own); called inside a script block or a function
in a pipeline, each of those four commands begins only when that block runs, after every other
command in the pipeline has begun and so after most of their sign-ins, and takes the session they
left for its own; a document exported by `Get-OERInventory` or `Export-OERInventory` names its
tenant, and `Invoke-OERStructure` refuses it in any other tenant with `DocumentTenantMismatch`,
reading and writing nothing for it, whichever session it began with, while a document without
`tenantId`, and the three builders, still take that session for their own, so the operator is told
to name `-TenantId` there (the known limit above, open for those; until Sprint 9 step 6b the clause
ended at that advice, for all four); the commands run as separate statements, with objects
collected in a variable first to move them between tenants. Both give the two-statement examples --
groups read and created, and an inventory read and applied, its `tenantId` removed between the two
since Sprint 9 step 6b -- the two pipelines they replace commented out, and a pointer to the limits
per sign-in type that `SWITCHING TENANTS` states for the statement that switches tenant. A short
paragraph after that pointer states the document tenant rule for the operator: a document that
names its tenant is applied only there, a `-TenantId` that is another tenant ID refuses it before
the sign-in with no token request, any other one is compared after the sign-in with the tenant the
session's tokens were issued for, and an export used as a template for another tenant gets its
`tenantId` changed or removed first. The README's inventory walkthrough says in one sentence that
the exported `inventory.json` names its tenant and is applied only there.
`Connect-OER`'s help carries the same rule in two sentences, beside the general case of a refused
sign-in; its sentence that a cmdlet a refused command calls does not change that by signing in
stays true, since such a cmdlet is now refused at its sign-in (BL-74), and a sentence beside it
says that `Connect-OER` run inside a refused command's output is refused the same way and signs in
as before as a statement of its own. The `Invoke-OERStructure` help states its pipeline session
rule in full, and each builder's `-TenantId` help states its own, the fail-safe refusals included.
BL-74 has no paragraph of its own in the README or the about topic: what an operator sees is the
existing rule that a refused command sends nothing, except that a cmdlet it calls no longer reaches
a sign-in prompt; the release note states that.

**The proof.** The two places the memory is written are pinned in
`tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, Describe
`Initialize-OERAuth sign-in memory (A20)`. Each wrapper's gate is pinned in its own test file,
Describes `Invoke-OERGraphRequest sign-in supersession gate (A20)` and
`Invoke-OERArmRequest sign-in supersession gate (A20)`, including its place after the session and
latch gates and, in a runspace with no `try`, the `return` after each `throw`. End to end, the
Describe `A command whose sign-in a later command in the pipeline replaced sends nothing (A20, F-E)`
in `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` runs the real `Initialize-OERAuth` and
both transports over stubbed token, connect and send calls, in a runspace with no `try` around the
pipeline: P1 two commands naming different tenants, P1b the F-E pipeline itself with the real
`New-OERGroup` and `Add-OERGroupMember` (nothing is created), P2 the nested case, P5 the
`ForEach-Object` shape and P6 a sign-in that was a cached return, with P3 and P4 as the positive
controls. P7 to P9 are the positive controls for a NEW sign-in that keeps the identity while a
remembering command runs, in a one-tenant pipeline on a user-assigned managed identity: P7 the Graph
wrapper's forced refresh after a rejected token, P8 the ARM wrapper's after a 401, P9 a downstream
command's sign-in while the first command's tokens are within five minutes of expiry. Each request
goes out, the retry included. Mutation-proved: a refresh that stops forwarding the client id turns
P7 or P8 red, and an identity that also carried the Graph token's exact expiry turns all three red,
and none of P1 to P6. Gate 10 of [#static-source-gates](#static-source-gates) keeps the three gates,
their order, the pairing of each memory write with its latch release, and the helpers' owners in
place. P10 to P17, in the same Describe, belong to the next subsection. P18 and P18b belong to BL-77:
P18 pipes a command naming one tenant by its tenant ID into one naming it by its domain, the stubbed
lookup resolving the domain to that tenant, and both commands send every request, with no
`SignInSuperseded`; P18b, the control, has the domain's token come back from another tenant, and the
second sign-in is refused with `TenantMismatch` while nothing is replaced silently. The unit Context
`the tenant term (BL-77)` in `tests/Unit/Private/Get-OERSignInIdentity.Tests.ps1` pins the term
itself: the granted tenant for a domain and for no tenant named, one identity for one tenant named
two ways, the fall-back to the name for a granted value that is not a GUID, never the ARM token's
tenant, and two granted tenants still told apart. Mutation-proved: the tenant term always the name
turns four of those tests and P18 red; the ARM tenant first turns the ARM tests red; dropping the GUID
check turns the fall-back cases red.

### A command acts under the session it began with

**The findings.** Sprint 9 step 2 closed three gaps in what the two subsections above describe,
each a sign-in that should not have run as it did.

- BL-76, the known limit above, open until this step: `Invoke-OERStructure` WITHOUT `-TenantId`
  signs in in its `process` block and names no tenant, so it inherited whatever state a downstream
  command's `begin` block had left by then, remembered that, and passed every gate.
- BL-81, the same gap in three builders the count of direct call sites did not show:
  `New-OERAccessPackageApprovalStage` and `New-OERAccessPackageRequestorScope` sign in only through
  `Resolve-OERTargetList`, and `New-OERAccessReviewStage` only through `Resolve-OERReviewerScope`,
  in `process` and only when a value is a name. Without `-TenantId`, a downstream command's `begin`
  block decided which tenant a name was looked up in. The supersession gate saw neither BL-76 nor
  BL-81: the inherited sign-in remembers the switched identity, so the command's frame matches the
  state.
- BL-74: a command whose sign-in was refused carries on (fact 1 under
  [The Graph SDK session](#the-graph-sdk-session)) and calls cmdlets that sign in again without
  `-TenantId`. The transports refused every request they made, but the sign-ins themselves still
  ran, and near the cached token's expiry one of them reached `Get-AzToken` -- a browser or device
  code prompt on an interactive or device code session -- and `Connect-MgGraph`, for a command that
  sends nothing. Read in the code (`Lock-OERSignIn` was the first statement, and nothing looked at
  an outer frame), and MEASURED by H3 before the fix: two token calls and one connection where the
  refused sign-in's one token call is all there should be.

**The snapshot (BL-76, BL-81).** `Checkpoint-OERSignIn` is the single owner of the session a command
began with. Without parameters it returns an `Omnicit.EntraRBAC.SignInSnapshot` whose only
property, `Identity`, is what `Get-OERSignInIdentity` returns now -- the four terms the memory
holds, never a token -- or `$null` when the module holds no state. With `-ChangedSince` it tells
whether the identity now differs, by the same case-insensitive `-eq` the supersession gate uses, so
no state matches only a snapshot of no state. The snapshot is a value the command keeps in its own
variable: nothing else reads it, and it ends with the command. `Invoke-OERStructure` and the three
builders take it in their `begin` block, and every `begin` block of a pipeline runs before any
`process` block, so for a command that stands in the pipeline itself it holds the session after
every UPSTREAM command's `begin`-block sign-in and before any DOWNSTREAM one. A command called inside
a script block or a function in a pipeline begins only when that block runs, after every `begin`
block of the outer pipeline, so its snapshot may already hold a downstream command's sign-in: that
is the known limit above, which this step did not close, and which Sprint 9 step 6b closed only for
a document that names its tenant (BL-88, under
[A document names the tenant it was exported from](#a-document-names-the-tenant-it-was-exported-from)).
Without `-TenantId` each of them compares in `process`:

- `Invoke-OERStructure` for each document after the document is read and validated, directly
  before `Initialize-OERAuth`, so a document that cannot be read or does not validate still reports
  `InvalidStructureDocument` or `StructureValidationFailed`. It takes the snapshot again after every
  sign-in, refused or not: without `-TenantId` a refused sign-in leaves the identity as it was, or
  sets the one this command asked for, so the result is the same and nothing has to read the latch.
  A first sign-in from no session therefore does not refuse the next piped document, while a
  document refused with `SignInSuperseded` moves nothing, and the document after it is compared
  with the same session.
- The builders directly before their first lookup call, after their own argument checks -- a
  missing approver or reviewer still reports `NoApprover` or `NoReviewer` -- and whether or not a
  value is a name; `New-OERAccessPackageRequestorScope` only in the branch that resolves `-User` or
  `-Group` for `SpecificDirectoryUsers`, so a scope with no targets is never refused. They take no
  pipeline input, so their `process` block runs once and the snapshot is never taken again.

When the identity changed -- another tenant, application, method or cloud, or none at all after a
`Disconnect-OER` -- the command writes `SignInSuperseded` (`New-OERSignInSupersededError`, with its
own name as the target) as a non-terminating error and returns before anything is signed in to or
looked up: `Invoke-OERStructure` applies nothing of that document and goes on to the next, and a
builder builds nothing. With `-TenantId` nothing changes: the sign-in names its tenant, and the
supersession gate covers the rest. A builder called nested, as `Sync-OERStructureAccessPackage` calls
the two access package builders, runs its `begin` and `process` blocks back to back under one
identity and is never refused. The `SignInSuperseded` message says the change came "after X began"
instead of "after X signed in": a command refused here has not signed in at all, and "began" is true
of every A20 refusal too. `Invoke-OERStructure` refuses a whole document, so since Sprint 10 step 3
(BL-92) it passes `-Document` and the text says the command did not apply this document and sent
nothing for it; the three builders pass nothing and keep the wording for a request, since what they
refuse is their lookup. See "Why no state counts as a difference" under
[A command sends nothing under a sign-in a later command replaced](#a-command-sends-nothing-under-a-sign-in-a-later-command-replaced).

**Why a snapshot, and never `-TenantId` from `begin` (A6, decided 2026-10-06).** The fix that the
known limit above sketched, while it was open until this step, was to capture the tenant in `begin`
and name it in the `process` block's sign-in. A `-TenantId` other than the tenant the state holds
inherits nothing (`$SessionUsable` in `Initialize-OERAuth`), so that sign-in would fall back to the
default method, `Interactive`: an app-only or managed-identity session -- the unattended case --
would get a browser prompt instead of a refusal. A tenant alone would also miss a change of
application, method or cloud, all of which the snapshot's four terms catch. The snapshot only
compares, and the command refuses, which is the safe direction; it never signs in on the command's
behalf.

**BL-74: a sign-in under a refused command is refused before it is made.** `Initialize-OERAuth`
now asks `Get-OERSignInRefusal -OutsideCaller` before anything else. The walk starts after the
frame `Lock-OERSignIn` would latch -- frame 0 is `Get-OERSignInRefusal` itself, frame 1
`Initialize-OERAuth`, and the caller is the first frame from index 2 that carries an invocation --
and returns the first latched frame beyond it. When it finds one, `Initialize-OERAuth` raises a
terminating `SignInRefused` (`New-OERSignInRefusedError`, with that outer command as the target),
with a `return` after it, and makes no token call and no `Connect-MgGraph`. That reaches a cmdlet a
refused command calls, which is what the apply handlers and several cmdlets do, and a sign-in made
inside a refused command's output; see "Opening again" and "Where the key is not the public
cmdlet" under [A command whose sign-in is refused sends nothing](#a-command-whose-sign-in-is-refused-sends-nothing).

**Why only outside the caller.** A command whose own sign-in was refused may sign in again from
the same frame, and a success releases it: `Invoke-OERStructure` does that for each piped document,
and several of `Initialize-OERAuth`'s own tests retry a refused sign-in the same way. A walk over
the whole stack would find that command's own latched frame and refuse the retry, so the second of
two documents would be refused because the first one's sign-in failed. The check stands before
`Lock-OERSignIn` so that its refusal latches nothing of its own: the outer command's latch already
refuses every request the caller makes while it runs.

**What it costs.**

- An upstream command that signs in in its PROCESS block and then emits a document now has that
  document refused when `Invoke-OERStructure` names no tenant:
  `... | ForEach-Object { Connect-OER -TenantId $_.T; $_ } | Invoke-OERStructure`. That sign-in
  comes after `Invoke-OERStructure`'s `begin` block took the snapshot, so it is a change like any
  other (read in the code). An upstream command that signs in in its `begin` block is not affected:
  `Get-OERInventory -TenantId A | Invoke-OERStructure -WhatIf` applies as before, since that `begin`
  block runs before `Invoke-OERStructure`'s.
- A builder whose values are all object ids, or that has only switches (`-Manager`, `-SelfReview`),
  is refused too under a changed session, although it would look nothing up: the check stands
  before the lookup call, not inside the resolver's branch for names. The builders take no pipeline
  input, and their output is assigned to a variable or passed as a value, not piped: the
  parameters it is built for -- `-ApprovalStage` and `-RequestorScope` of
  `New-OERAccessPackageAssignmentPolicy` and `Set-OERAccessPackageAssignmentPolicy`, `-Stage` of
  `New-OERAccessReviewDefinition` and `Set-OERAccessReviewDefinition` -- bind nothing from the
  pipeline (read in the code). `New-OERAccessReviewStage`'s `StageId` does bind one elsewhere,
  `Get-OERAccessReviewInstanceDecision -Stage`, through that parameter's alias, but that is not how a
  built stage is used. So the false refusal needs a pipeline the builders are not used in, and it is
  on the safe side: the builder builds nothing and sends nothing.
- From a process with no session the snapshot is "no session", so any sign-in by another command
  before the document is processed is a change -- even a downstream command that names no tenant
  and signs in to `organizations`, the identity `Invoke-OERStructure` itself would have used.
  Refusing is the safe direction, and the shape, a `StructureResult` piped into an OER cmdlet, is
  unusual.
- HISTORY, ended by BL-77 in Sprint 9 step 3: one tenant named two ways counted as two identities
  here exactly as under A20, so after `Connect-OER -TenantId <guid>`,
  `Invoke-OERStructure -Path x.json | X -TenantId <its domain>` refused the document although both
  named one tenant. The snapshot's tenant term is now the granted tenant, as the memory's is, so that
  pipeline applies when X's token comes back from the same tenant and X signs in with the same
  method, client and cloud. X still signs in again, since the cache is keyed on the name, and a
  sign-in that differs in method -- the default interactive one, on an app-only session -- is still a
  change. The answer to that is the same rule to name the tenant explicitly and consistently.
- A `Disconnect-OER` in the pipeline refuses the same way, and since Sprint 10 step 3 (BL-92) the
  record says so: the module holds no state then, and the text says that `Disconnect-OER` ended the
  module's session after the command began, with advice to run it as a statement of its own. Until
  then the text, shared with A20, spoke of another command's sign-in, which no command had made.
- Under BL-74 a cmdlet a refused command calls gets `SignInRefused` at its own entry, where it used
  to sign in, or hit the cache, and be refused at its first request. `SignInRefused`'s fixed message
  says "this request was not sent", which then means the sign-in. In the apply engine the handler's
  `catch` reports it as a `Failed` row with that text, so H3's rows and error ids match H1's, and
  only the token and connection counts tell the two apart.

**The proof.** Unit: `tests/Unit/Private/Checkpoint-OERSignIn.Tests.ps1` (Describe
`Checkpoint-OERSignIn`) pins the snapshot's shape, a change of each of the four terms, letter case,
no state on either side, the type guard and the read through `Get-OERSignInIdentity`.
`tests/Unit/Public/Invoke-OERStructure.Tests.ps1`, Describe
`Invoke-OERStructure acts only under the session it began with (BL-76)`, pins the refusal on a
tenant switch, another application, a cleared state and a first sign-in from no session; the
controls for an unchanged identity, `-TenantId`, two documents from no session and an upstream
command that signed in in its `begin` block; the two validation-order tests; and the snapshot taken
again only after a sign-in -- every piped document refused under a switch, and the documents after
one whose rows a downstream command answered by switching; since BL-92 the refusals of a switch, of
another application and of a first sign-in from no session also pin the message of a refused
document with another command's sign-in as its cause, and the cleared-state refusal the one that
says `Disconnect-OER` ended the session. The three builders' test files each hold
a Describe `... looks a name up only under the session it began with (BL-81)` (`a target` for the
requestor scope): the refusal, the fail-safe refusal, an argument error as itself (the no-target
scope for the requestor scope, which also has a non-specific scope given `-User`, built with its
warning and never refused), an unchanged identity, `-TenantId` and the nested call.
`tests/Unit/Private/Get-OERSignInRefusal.Tests.ps1` has the Describe
`Get-OERSignInRefusal -OutsideCaller (BL-74)`, and `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`
the Context `refused under a latched outer command (BL-74)`, with `Get-AzToken` and
`Connect-MgGraph` asserted not called beside a positive control, and two tests beside it: the
rewritten `keeps the refused command latched, and refuses the sign-in of a command it calls (BL-74)`,
and a new one that carries the property the rewritten test used to,
`releases only its own entry when a sign-in succeeds: a refused command that is not on the call stack stays latched`.

End to end, in `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1` with the real
`Initialize-OERAuth`, every transport stubbed and no `try` around the pipeline: P10 to P13 in the
A20 Describe for BL-76 -- P10 a downstream `Connect-OER` to another tenant, after which the only
token calls are the two `Connect-OER` sign-ins (the statement before the pipeline and the
downstream one), no Graph or ARM request leaves and one `SignInSuperseded` names
`Invoke-OERStructure`; P11 the same identity again, applied; P12 with `-TenantId`, signed in to the
named tenant again and applied there; P13 two documents from no session, both applied. In P14 to
P16 each builder is refused after a downstream switch and no lookup is sent; in P17 the lookup is
sent when the downstream command signs in again as the same identity. H3, H4 and H5 in the A19
Describe pin BL-74, as described under
[A command whose sign-in is refused sends nothing](#a-command-whose-sign-in-is-refused-sends-nothing).

Mutation-proved, each on a copy of `source/`: deleting `Invoke-OERStructure`'s check turns its four
unit refusals and P10 red; dropping its `-not $TenantId` turns the `-TenantId` control and P12 red;
deleting the second snapshot turns the two-documents test and P13 red; moving the check above the
read turns both validation-order tests red; and taking the snapshot again inside the refusal branch,
or after the output loop, turns the re-take tests red. For each builder, deleting the check turns
its unit refusals and its P test red, dropping `-not $TenantId` its `-TenantId` control, and moving
the requestor scope's check out of its branch the no-target test; hoisting it only out of the
`SpecificDirectoryUsers` branch, still under `-User` or `-Group`, turns the non-specific scope's
test red, and no other test in that file. Deleting BL-74's check turns the BL-74 Context, the
rewritten nested test, H3 and H5 red, H5 with two token calls and one connection; dropping
`-OutsideCaller` turns H4, the unit test
`is released when a sign-in from the same frame succeeds after a refusal` and five other
same-frame retries red; starting the walk at frame 0 turns two `-OutsideCaller` tests and those six
`Initialize-OERAuth` tests red; moving the check after `Lock-OERSignIn` turns
`leaves the calling command unlatched when it refuses (the check stands before Lock-OERSignIn)` red.
One guard survives every test by construction: the `return` after the terminating BL-74 refusal.
`Write-CmdletError -Terminating` ends `Initialize-OERAuth` itself even with no `try` anywhere up the
stack -- measured with a Pester probe that was not committed -- so the `return` is unreachable
today, and it stays against a future change that stops that helper throwing. Gate 10 of
[#static-source-gates](#static-source-gates) holds the two widened owner lists.

### A document names the tenant it was exported from

**The finding (BL-88).** The known limit Sprint 9 step 2 left open (its Ruling R11), under
[A command sends nothing under a sign-in a later command replaced](#a-command-sends-nothing-under-a-sign-in-a-later-command-replaced):
`Invoke-OERStructure` without `-TenantId`, called inside a script block or a function in a
pipeline, begins only when that block runs, after every `begin` block of the outer pipeline. Its
snapshot (BL-76) then already holds a downstream command's sign-in, its own sign-in names no tenant
and inherits that session, and its frame remembers it, so neither the snapshot nor the supersession
gate sees a difference: the document, `-Prune` included, was applied in the tenant the downstream
command switched to, with no error. MEASURED by the final review of Sprint 9 step 2 with
plain-PowerShell stand-ins, and reproduced end to end before this step's fix by P19 and P19d below,
which recorded the document's group read going out under the switched tenant. Nothing the command
can see of its own session tells the two tenants apart, so the only general fix the architect saw
had to come from the document -- and that changes the export's format and how a document can be
used as a template, which is not the architect's decision: A11 parked it for Philip (P-4).

**The decision (A14, Philip's decision 2026-10-07, P-4).** An exported document carries its tenant,
and the apply refuses another one. The export writes a new top-level `tenantId`, the tenant the
Microsoft Graph token was issued for; `tenantAlias` is still used only for the naming templates and
does not change. The apply compares the document's tenant with the session's after its sign-in and
refuses the whole document with the new `DocumentTenantMismatch` before any section is read or
written; a `-TenantId` that is another tenant ID than the document's refuses it before the sign-in.
Nothing ever signs in WITH the document's tenant, so A6 stands: the tenant is only compared. A
document without `tenantId` behaves exactly as before, and an export used as a template for another
tenant gets the key removed or changed first -- the cost Philip accepted. It closes BL-88 for an
exported document, since the command inside the script block still signs in under the switched
session but the document names the right tenant, and leaves the form open, with the advice
`-TenantId`, for a document without the key and for the three name-looking builders, which take no
document.

**The export.** `Get-OERInventoryTenantId` is the single owner of which tenant an export names: the
state's `TokenTenantId` when it is a canonical GUID (`Test-OERGuid`), and nothing otherwise.
`Get-OERInventory` and `Export-OERInventory` call it in their `begin` block, directly after their
own `Initialize-OERAuth`, and pass the value to `ConvertTo-OERInventory -TenantId`, which writes
`tenantId` directly after `version`, and only when it is a GUID (Ruling R7: a second small helper,
so that the converter, the single owner of the inventory shape, stays pure). The capture stands in
`begin` so that the document names the session this command signed in under, never one a nested
cmdlet or a pipeline neighbour switched to by the time the document is assembled.
`Export-OERInventory` takes its own capture rather than reading the `tenantId` of the inventory
`Get-OERInventory` returns, and passes it to both of its converter calls. The bundle folder's name
and the summary's `TenantId` keep the tenant as named, as before; only `inventory.json` carries the
granted tenant. The validator (`Test-OERStructureSchema`, Rule 1b) and the schema
(`Get-OERStructureSchemaJson`) know the key: a present `tenantId` must be a string holding a
canonical GUID, and an explicit `null`, an empty string, a value that is not a string or any other
value is an Error (Ruling R3), which `Invoke-OERStructure` reports as `StructureValidationFailed`
before either comparison. A `null` is refused rather than read as no key, since an LLM that wrote one
would otherwise drop the check silently; a document meant to carry no check omits the key. If wrong:
treat an explicit `null` as absent, one condition. Until Sprint 10 step 5 (BL-101) the validator
accepted two shapes the schema is written to refuse: a GUID followed by a line feed, through the
predicate's `$` (only a strictly ECMA-262 validator refuses it; PowerShell's own `Test-Json`, whose
regular expressions are .NET's, accepts it like the old predicate did), and a one-GUID array, through
Rule 1b's string cast, which reads a one-element array as its element (`Test-Json` refuses that one
too). Both are now refused, the first by the predicate's `\z` and the second by Rule 1b's own check
that the value is a string, as the schema's `type: string` does. A document without the key is valid
as before. The prompt template tells an LLM to keep `tenantId` exactly as exported and never to
invent, change or remove one.

**The two comparisons, and their order.** `Get-OERDocumentTenantMismatch` is the single owner of
the comparison and of the `DocumentTenantMismatch` id and message. It returns nothing for a document
without the key; otherwise an error record, or nothing when the comparison passes. It never signs
in, sends nothing and reads nothing but the module's state, and it compares with PowerShell's
case-insensitive `-eq`. `Invoke-OERStructure` calls it twice per document, in `process`, after the
document is read and validated:

1. Before the sign-in, only when `-TenantId` is bound, and before the BL-76 check. When `-TenantId`
   is a canonical GUID that is not the document's `tenantId`, the document is refused with no token
   request, no tenant lookup and no `Connect-MgGraph`, and the snapshot is not taken again, since
   nothing signed in. A domain, `organizations`, a braced or dash-less GUID or any other name is
   not compared here (Ruling R8): it is not a tenant ID, and the tenant it names is known only from
   the token it yields. If wrong: nothing is lost, since the second comparison still refuses such a
   document, after a token request.
2. After the sign-in, whatever `-TenantId` names and without one: directly after the snapshot is
   taken again, and before the omitted-collection warning under `-Prune`, the administrative unit
   pre-pass, the role-assignment scope pre-pass and every section. The document's `tenantId` must
   equal the state's `TokenTenantId`, and, when Azure Resource Manager is used, `ArmTokenTenantId`
   as well. A GUID `-TenantId` that passed the first comparison is compared again here: a refused
   sign-in leaves another session, or none, in place, and outside any `try` the command carries on
   to this point.

A difference writes `DocumentTenantMismatch` as a non-terminating error and returns: nothing is read
or written for that document, and the next piped document is tried on its own. Its category is
`InvalidOperation` and its target the document's path, or the parameter set's name, as
`InvalidStructureDocument`'s is (Ruling R5; if wrong, change both before this step merges, since
every merge publishes and a change after it is a published change). The message names the
document's tenant and, when there is one, the tenant it was compared with; with no state, or a
token tenant that is not a GUID, it says instead that the session holds no Microsoft Graph (or
Azure Resource Manager) token whose tenant can be compared with it. It says that nothing was read or
written for the document -- signed in to, read or written, before the sign-in -- and tells the
operator to name that tenant with `-TenantId` or, to use the document as a template for another
tenant, to change or remove its `tenantId`. It holds no token, account or credential.

**One comparison after the sign-in, not one per section (Ruling R1).** The spec's "before every
section, the administrative unit pre-pass included" is read as ONE comparison directly after the
sign-in, before the first thing that reads or writes for the document: the same sentence says the
whole document is refused and nothing read or written for it, which a check between sections could
not honour once the first section had run. A session that changes between sections is refused by
the supersession gate (A20) instead: `Invoke-OERStructure`'s frame remembers the identity its own
sign-in gave it, whose tenant term is `TokenTenantId` (BL-77) -- the tenant just compared with the
document -- so a later switch differs from it and every request after it is refused. If wrong: add
a comparison before each section in the dispatch loop.

**Why never the tenant as named.** The tenant the caller named (`TenantId` in the state) can be a
domain, `organizations` or nothing at all, so an export that wrote it would often name no tenant ID
a later session could be compared with. The granted tenant is the one every request goes out under:
since BL-12 a named tenant is checked against the token (`TenantMismatch`), and since BL-77 the
identity's tenant term, which the supersession gate and the snapshot compare, is `TokenTenantId`.
So the export writes `TokenTenantId` and the apply compares with it. A document exported under
`-TenantId contoso.onmicrosoft.com` then applies whether the apply names that tenant by its GUID, by
its domain or not at all, as long as the token comes from that tenant. A comparison with the name
would refuse the domain, and no tenant named whenever the session itself was named by a domain or
`organizations`, and would pass a session named for the document's tenant whose token came from
another.

**Why no session, or a token tenant that is not a GUID, refuses (Ruling R4).** After the sign-in the
comparison needs a tenant ID. With no state -- a sign-in refused from no session -- or a
`TokenTenantId` that is not a GUID -- AzAuth reported no tenant for the token, the documented limit
of `TenantMismatch` -- the document's tenant cannot be shown to be the session's, so the document is
refused: the safe direction, as for the supersession gate's "no state counts as a difference". If
wrong: such a document cannot be applied from a session whose token reports no tenant ID until its
`tenantId` is removed. A missing ARM token tenant, or one that is not a GUID, refuses a document that
uses Azure Resource Manager the same way.

**The ARM term.** The Azure sections are applied with the ARM token, which the ARM wrapper sends
with no session gate, and the ARM token can come from another tenant than the Graph token in ways
the sign-in does not always catch: a granted tenant that is not a GUID is not compared by
`TenantMismatch`, and the ARM token of a sign-in that names no tenant is compared with the Graph
token only when both are GUIDs (A13 and F3, under
[Requested tenant vs granted tenant](#requested-tenant-vs-granted-tenant)). So when Azure Resource
Manager is used -- `$NeedArm`: an Azure section both selected by `-Include` and declared in the
document, or `-IncludeARM` -- the ARM token's tenant must be the document's too. Otherwise it is not
compared: a Graph-only document sends no ARM request, and a session that holds no ARM token, or one
from an earlier sign-in, must not refuse it. A document with no Azure section under an explicit
`-IncludeARM` is compared on both tokens, since the command asked for Azure Resource Manager.

**The gate (Ruling R6).** The single owner is held by one row in gate 10's owner table --
`Get-OERDocumentTenantMismatch` called only in `Invoke-OERStructure`, which must really call it --
with an `It` of its own, since a row alone asserts nothing (measured, below). There is no rule on
the `DocumentTenantMismatch` literal or on a read of a document's `tenantId`. If wrong: a second
comparison written inline, without calling the owner, is caught only by review and the CLAUDE.md
rule.

**What it costs.**

- An export used as a template for another tenant gets its `tenantId` changed to that tenant's ID,
  or removed, first (A14, the accepted cost). The cross-tenant copy under
  [A command sends nothing under a sign-in a later command replaced](#a-command-sends-nothing-under-a-sign-in-a-later-command-replaced)
  -- `$Inventory = Get-OERInventory -TenantId A ...`, then
  `Invoke-OERStructure -InputObject $Inventory -TenantId B ...` -- is refused now unless the key is
  removed between the two statements, and the README and the about topic show that line (Ruling R9):
  `$Inventory.PSObject.Properties.Remove('tenantId')`. A document written by hand, or by an LLM from
  a template without the key, is not affected.
- A session whose token reports no tenant ID cannot apply an exported document that carries
  `tenantId`, and cannot write one: the export then leaves the key out, with no warning (Ruling R2),
  so that document carries no tenant check -- the same documented limit as `TenantMismatch`'s. A
  warning was not added, since about 140 existing tests that count warnings run with no state. If
  wrong: add one warning in the two callers of `Get-OERInventoryTenantId`.
- A document refused because a refused sign-in left another session in place reports two errors,
  outside any `try`: the sign-in's own (`SignInRefused`, `TenantMismatch` and the rest), then
  `DocumentTenantMismatch`, whose message speaks of the session's token -- the session the refusal
  left in place, which is the one every request would have gone out under. When that session is the
  document's tenant, the document passes the comparison and the sign-in latch refuses every request
  instead, as before.

**Known limits.**

- A document without `tenantId` -- written by hand, from a template, or exported from a session
  whose token reported no tenant ID -- keeps the open form of BL-88: called without `-TenantId`
  inside a script block or a function in a pipeline, it is applied in the tenant another command's
  sign-in left. So do the three name-looking builders, which take no document. The texts keep the
  advice to name `-TenantId` for those.
- After a REFUSED sign-in, the export's capture in `begin` reads the session the refusal left in
  place -- usually the previous tenant's -- so the export names that tenant although the operator
  named another (Ruling R10). Every read the export then makes is refused by the sign-in latch, so
  the document holds no section content: applied in the tenant it names it declares only empty or
  unread sections, which create nothing and give `-Prune`, which acts only on the child collections a
  document declares, nothing to remove; applied anywhere else it is refused. Read in the code, not
  tested. The capture stays in `begin` (R7, and the reason under "The export"). If wrong: the
  exported `tenantId` can name the previous session's tenant for an empty bundle.
- Nothing machine-checks who calls `Get-OERInventoryTenantId`; gate 10 holds only the comparison.
  `tests/Unit/Public/DirectoryRoleInventory.RoundTrip.Tests.ps1` runs with no state, so its
  export-to-apply round trip carries no `tenantId` and never reaches the comparison.

**The user-facing texts.** `Invoke-OERStructure`'s help states the document tenant rule in a
paragraph of its own beside its pipeline session rule, and its `-TenantId` and `-InputObject` point
at it; `Get-OERInventory`'s and `Export-OERInventory`'s help say what `tenantId` names, that it is
not the tenant as named, and when it is left out; `Test-OERStructure`'s help that the key is
checked offline as a string holding a canonical GUID and compared only by the apply. The README and
the about topic carry it in the clause and the short paragraph described under "The user-facing texts" of
[A command sends nothing under a sign-in a later command replaced](#a-command-sends-nothing-under-a-sign-in-a-later-command-replaced),
and the copy example removes the key. CLAUDE.md carries the closed and open halves in its
Authentication Architecture rule and the two owners in a Code Style rule.

**The proof.** Unit: `tests/Unit/Private/Get-OERDocumentTenantMismatch.Tests.ps1`, Describe
`Get-OERDocumentTenantMismatch (BL-88, A14)`, pins the owner: a document without `tenantId` returns
nothing in both modes; before the sign-in the document's tenant in another letter case passes,
another tenant ID gives exactly one record (id, category, target and message), a domain,
`organizations` or a braced tenant ID is left to the second comparison, and the state is not read;
after the sign-in no state, a Graph token tenant that is missing or not a GUID, and another tenant
each refuse, the granted tenant is compared and never the name
(`compares the GRANTED tenant, never the tenant as named: a named tenant equal to the document's does not pass when the token differs`),
and with `-IncludeARM` the ARM token's tenant is compared -- another tenant, or none, refuses --
while without it the ARM token is not; no token ever reaches the message.
`tests/Unit/Public/Invoke-OERStructure.Tests.ps1`, Describe
`Invoke-OERStructure refuses a document from another tenant (BL-88, A14)`, pins the command: test 1
refuses before the sign-in with `Initialize-OERAuth` never called; 2 is the letter-case control; 3,
a domain whose token comes from another tenant, and 3b, `organizations`, are refused after the
sign-in only; 4 and 5, without `-TenantId`, are refused under another tenant and applied under the
document's; 6 refuses with no session; 7 applies a document without `tenantId` as before; Context 8
holds that a refused document gets no `-Prune` warning and no administrative unit pre-pass, beside a
control; Context 9 the ARM term -- refused under another ARM tenant before the scope pre-pass,
dispatched when both tokens match, refused when the ARM tenant is not a tenant ID, a groups-only
document refused under an explicit `-IncludeARM` and applied without it, and no ARM comparison
without an Azure section or `-IncludeARM`; 10 refuses only the piped document that names another
tenant and applies the next one; 11 reports a `tenantId` that is not a tenant ID as
`StructureValidationFailed` before either comparison; and 12 terminates the statement as
`DocumentTenantMismatch` under `-ErrorAction Stop`, before and after the sign-in. The export:
`tests/Unit/Private/Get-OERInventoryTenantId.Tests.ps1` (Describe
`Get-OERInventoryTenantId (BL-88, A14)`), the Context `tenantId (BL-88, A14)` in
`tests/Unit/Private/ConvertTo-OERInventory.Tests.ps1`, and the Describes
`Get-OERInventory tenantId (BL-88, A14)` and `Export-OERInventory tenantId (BL-88, A14)` in the two
cmdlets' files, which include
`captures the tenant in begin, directly after the sign-in, not when the document is assembled` and
`writes its own capture, not the tenantId of the inventory Get-OERInventory returned`. The validator
and the schema: the Describes `Test-OERStructureSchema tenantId (BL-88, A14)` and
`Get-OERStructureSchemaJson tenantId (BL-88, A14)`. The help: the Describes
`Get-OERInventory help documents the tenantId (BL-88, A14)` and
`Test-OERStructure help documents the tenantId (BL-88, A14)`, and one `It` each in
`tests/Unit/Public/Export-OERInventory.Tests.ps1` and `tests/Unit/Public/Invoke-OERStructure.Tests.ps1`;
the prompt template: the Describe `Get-OERInventoryPromptTemplate tenantId (BL-88, A14)`.

End to end, in `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`, in the A20 Describe with the
real `Initialize-OERAuth`, every transport stubbed and no `try` around the pipeline: P19 is BL-88's
shape -- after `Connect-OER` to one tenant, `Invoke-OERStructure` without `-TenantId` inside a
`ForEach-Object` script block, followed by a `ForEach-Object` whose `-Begin` signs in to another --
and the only token calls are the two `Connect-OER` sign-ins, no Graph or ARM request leaves, no
`SignInSuperseded` is written, and exactly one `DocumentTenantMismatch` names the document's path.
P19b, the control for the open form, applies a document without `tenantId` under the switched
tenant; P19c applies a document that names the switched tenant; P19d adds `-IncludeARM` and sends
nothing through either transport; P19e runs `Invoke-OERStructure -TenantId` naming another tenant ID
than its document as a plain statement, and no token for that tenant is requested and nothing is
sent. Gate 10 of [#static-source-gates](#static-source-gates) holds the comparison to
`Invoke-OERStructure`, in its own `It`,
`compares a structure document's tenantId with Get-OERDocumentTenantMismatch only in Invoke-OERStructure.ps1`.

Mutation-proved, one exact edit at a time. Deleting the comparison after the sign-in turns unit
tests 3, 4, 6, 8, 9 (the ARM refusal), 10 and 12 (after the sign-in), P19 and P19d red; dropping
only its `return` turns 3, 4, 6, 8, 9, 10, P19 and P19d red, while 12 stays green, since under
`-ErrorAction Stop` the write itself throws. Deleting the comparison before the sign-in turns test 1,
12 (before the sign-in) and P19e red -- P19e records a token request for the other tenant -- and
dropping only its `return` turns test 1 and P19e red, so in a script with no `try` that `return` is
what keeps the token request from being made. Moving the comparison after the `-Prune` warning
turns Context 8's test red. In the owner: comparing `TenantId` instead of `TokenTenantId` turns the
GRANTED-tenant test and seven more of the owner's tests red; dropping the ARM branch turns the
owner's two `-IncludeARM` refusals and Context 9's three refusals red; returning early when there is no state turns
`refuses when the session holds no state` and test 6 red; and dropping the GUID test before the
sign-in turns
`returns nothing when -TenantId is a domain, organizations or a braced tenant ID: those are compared after the sign-in`,
test 3 and test 3b red. In the export: reading `TenantId` turns
`returns the tenant the Graph token was issued for, never the tenant as named` and the cmdlets'
tests red; moving the capture out of `begin` turns the capture test red; dropping `-TenantId` from
`Export-OERInventory`'s canonical converter call turns five of its tests red, and from its Azure-only
call `passes the capture to both ConvertTo-OERInventory calls, the Azure-only branch and the canonical one`;
and dropping the converter's GUID test turns its four `leaves tenantId out` cases red. Dropping the
helper's GUID test turns only the helper's own four non-GUID cases red: the converter's test keeps a
non-GUID out of the document, so that mutant is caught by one layer of the two, by design. In the
validator: removing `tenantId` from the known keys, deleting Rule 1b, or replacing `Test-OERGuid`
with a `[guid]` cast each turns its tests red, the last only the braced and dash-less GUID cases.
And gate 10: the row with its owner list emptied left the gate green until the row got its own
`It`, which then turns red, as it does for a call added to another file.

### A refused sign-in leaves the session uncertain

**The finding (BL-89).** A sign-in that fails or is refused usually leaves the module's session as it
was: the previous tenant's, or none. The exception is a refusal at the Azure Resource Manager step --
`ArmTokenAcquisitionFailed`, or `TenantMismatch` on the ARM token -- which comes after the Microsoft
Graph half has already connected and rebuilt the state for the tenant the sign-in named (or, when it
named none, the tenant the Graph token came from), so the session is then that tenant's, without an
ARM token from this sign-in. The latch covers the command whose sign-in it
was, for as long as that command runs, and a command that finishes is on no call stack, so the next
statement in a script is a new command the latch knows nothing about. Outside any `try` the script
carries on to it, and when that command names no tenant it inherits the session the refused sign-in
left in place. The shape is a loop over tenant profiles:

```powershell
foreach ($Alias in $Aliases) {
    Connect-OER -TenantAlias $Alias -ClientId $AppId -CertificatePath $Pfx
    Invoke-OERStructure -Path "$Alias.json" -Prune
}
```

When one `Connect-OER` failed or was refused -- a certificate the tenant does not accept, or, since
BL-12, a domain the lookup cannot resolve -- the `Invoke-OERStructure` after it named no tenant,
inherited the previous tenant's session and applied that alias's document there, `-Prune` deletions
included, with no error of its own. Read in the code; H8 below runs the shape end to end. Neither
the latch nor the supersession gate sees it: the refused command has finished, and the next one
signs in successfully, under the session it inherits.

**The marker.** `Set-OERSessionUncertain` is the single owner of `$script:_OERSessionUncertain`: it
sets or clears the marker and returns what it was, and `$null` reads as clear. It holds one boolean
and nothing about the sign-in that set it -- no tenant, account or token. Only three files call it:
`Initialize-OERAuth`, `Connect-OER` and `Disconnect-OER`.

**The rule, in `Initialize-OERAuth`** (Sprint 9 step 3, Rulings R9, R10 and R13).

- Directly after `Lock-OERSignIn` it sets the marker, keeping the value it found. So every refusal,
  terminating error and early return after that point leaves the session uncertain,
  `ArmTokenAcquisitionFailed`'s early return, `GraphSessionChanged` and `TenantResolutionFailed`
  included. The BL-74 refusal stands before `Lock-OERSignIn` and does not touch the marker: the
  latched outer command it found set it when its own sign-in was refused. The marker need not still
  be set by then -- a pipeline neighbour whose sign-in names its tenant and succeeds clears it while
  the refused command stays latched -- and that is harmless: the latched command, and every cmdlet it
  calls, sends nothing either way, and the marker decides only whether a later command that names no
  tenant may sign in, after a sign-in that did succeed.
- After the `GraphSessionChanged` refusal, and before the cached return, the tenant lookup and every
  token call, it refuses a call that names no tenant -- no `-TenantId`, or `-TenantId organizations`,
  which names none -- when the marker it found was set and the call is not `Connect-OER`'s
  (`-ReclaimGraphSession`). The refusal is a terminating `SignInRefused` from
  `New-OERSignInRefusedError -SessionUncertain`: the calling command's name as its target and fixed
  text that names no tenant, saying that an earlier sign-in failed or was refused and that the
  module's session may not be the one that sign-in asked for, that nothing was sent, and that
  `-TenantId`, `Connect-OER` or `Disconnect-OER` sends again (see the next paragraph for why that is
  one text for every refusal that sets the marker). No token is requested
  and nothing is looked up or connected. The caller stays latched, so the transports refuse each of
  its requests with `SignInRefused`, and BL-74 refuses the sign-ins of the cmdlets it calls. It
  stands after the `GraphSessionChanged` refusal so that a changed session still reads
  `GraphSessionChanged`.
- At each of the two success ends, directly after `Register-OERSignInIdentity`, it clears the marker
  when the call named its tenant and is not a transport's own refresh, or is `Connect-OER`'s; any
  other success puts back the value it found.

**One text for every refusal that sets the marker (BL-93, Sprint 10 step 3).** The marker holds one
boolean and nothing about the sign-in that set it, by design, so the refusal cannot say whose session
the module still holds. The text used to say the session "may still belong to the tenant before it".
That was literally true after a failed renewal of the session's own token within the same tenant,
where the tenant before is the same tenant, but misleading: it read as a switch to another tenant
that did not happen. The text now names no cause and no tenant, and says only that the session may
not be the one the earlier sign-in asked for. That holds for every refusal that sets the marker: a
sign-in for another tenant that failed or was refused, a failed renewal of the session's own token,
an Azure Resource Manager step that failed after the Graph half connected -- where the session is the
requested tenant's Graph session without its Azure half, which is why the text says "may not be" and
not "is not" -- and a changed Graph SDK session. The id, category and target are unchanged. (Ruling:
one text and no second variant, since telling the cases apart would need the marker to hold a cause,
and it holds none.) The unit test of `New-OERSignInRefusedError` pins the exact text and that it
matches neither `tenant before` nor `belong`; putting the old wording back turns both red. README and
the about topic keep their description that such a sign-in usually leaves the session as it was.

**What clears it.** A successful sign-in of a command that names its tenant: `-TenantId`, or
`Connect-OER -TenantAlias`, whose profile names it. A successful `Connect-OER`, with or without a
tenant. And `Disconnect-OER`, inside its `ShouldProcess` beside clearing the state, so `-WhatIf`
leaves the marker as it leaves the state. A re-import of the module empties it with the rest of the
module's state (INFERRED from module scoping, not tested). Nothing else does: a command that names no
tenant cannot, since it is refused before it signs in.

**Why `Connect-OER` is exempt, and marks first.** An explicit `Connect-OER` is the operator's
instruction to sign in, as it is for taking back a changed Graph SDK session, so the marker never
refuses it, and its success clears the marker even without a tenant: the operator has just said
which session to use. It sets the marker as the first statement of its `process` block (Sprint 9
step 3, Ruling R11), so its own refusals before any sign-in -- `AmbiguousTenant`,
`InvalidTenantAlias`, `TenantAliasNotFound` -- leave the session uncertain too. In the loop above a
misspelt alias would otherwise leave the previous tenant's session certain, and the document would
be applied there. A BOUND `-TenantAlias` always reaches the alias check (final review I1, Ruling
F1), so an empty, whitespace or `$null` alias, typed or piped, is refused with `InvalidTenantAlias`
and leaves the marker set. Until then the block ran only for a truthy alias: an empty one skipped
it, so `Connect-OER` named no tenant, signed in to the current session's tenant and, as
`Connect-OER`'s sign-in, cleared the marker -- in the loop above, a blank alias in a profile list or a
CSV row applied its document, `-Prune` included, in the previous row's tenant (measured by the final
reviewer with a scratch probe; H10 below runs it end to end). `[ValidateNotNullOrEmpty()]` was
rejected for this: a binding error never runs `process`, so it would mark nothing.

**An empty `-TenantId` is refused, not read as no tenant** (Sprint 9 step 3 round 1, decision A12,
BL-94). Every public cmdlet read an empty `-TenantId` the way it reads an omitted one: each passes the
value on only when it is truthy (`if ($TenantId) { $AuthParams.TenantId = $TenantId }`), and
`Initialize-OERAuth` reads emptiness, not presence. So a loop such as
`Invoke-OERStructure -TenantId $Row.TenantId -Path $Row.Path -Prune`, over rows with an empty cell,
applied that row's document in the tenant of the current session, refused sign-in or not, and
`Connect-OER -TenantId ''` signed in to the current session's tenant and, as `Connect-OER`'s sign-in,
cleared the marker. The two halves of the rule split on where the refusal must stand:

- `Connect-OER` refuses a BOUND `-TenantId` that is empty, whitespace or `$null` with the new
  `InvalidTenantId` (category `InvalidArgument`, pre-decided in A7), in `process` directly after it
  sets the marker and before `AmbiguousTenant`, so the refusal leaves the session uncertain like its
  other refusals; a blank `-TenantId` beside an alias is therefore `InvalidTenantId`, not
  `AmbiguousTenant`. It decides on `$PSBoundParameters.ContainsKey('TenantId')`, never on
  truthiness, and its `-TenantId` carries no validation attribute, since a binding error would skip
  `process` and leave the marker as the previous sign-in left it. `Connect-OER` with neither
  `-TenantId` nor `-TenantAlias` bound still names no tenant, as before.
- Every other public cmdlet that declares `-TenantId` -- ninety, `New-OERConfiguration` and
  `Set-OERConfiguration` among them, whose `-TenantId` is stored rather than signed in to -- carries
  `[ValidateNotNullOrEmpty()]`. Its binding error stops that one command before its `begin` block,
  so it signs in nowhere and sends nothing, and the next statement of a script runs as usual; there is
  no marker to set, since nothing was attempted. `Set-OERConfiguration` is the one that binds
  `-TenantId` from the pipeline: there an empty value is refused per input object, after `begin`,
  and the next object is still processed (measured by the round's final review); it signs in to
  nothing either way. `Set-OERConfiguration -TenantId ''` used to reach the
  cmdlet's own checks, which refuse, as `TenantProfileMalformed`, a write that would leave an existing
  profile without a tenant; it is now refused at binding instead, before anything is read, and
  nothing is written either way.
- No internal call passes an empty value on to a public cmdlet: every one forwards `-TenantId` only
  when it is set (the ninety cmdlets, `Invoke-OERStructure`, the three builders and the two access
  review cmdlets through `Resolve-OERReviewerScope`, and the three private resolvers that sign in),
  and the configuration cmdlets hand a validated or profile-checked value to
  `ConvertTo-OERTenantConfiguration`. The one deliberate exception is `Connect-OER`, which always
  passes `TenantId` to `Initialize-OERAuth`, as `''` when neither `-TenantId` nor `-TenantAlias` is
  bound: `Initialize-OERAuth` reads emptiness, not presence, as "no tenant named", and that is the
  case A12 leaves as it was. Nothing machine-checks the forwarding; the cohort below holds the
  attribute, which fails closed at binding whatever a caller forwards.

`tests/Unit/Public/TenantIdNotEmpty.Cohort.Tests.ps1` holds the rule from the source: it reads every
`source/Public/*.ps1` with the AST, pins the count of `-TenantId` carriers at 91, requires the
attribute on every one but `Connect-OER`, requires `Connect-OER`'s to carry no `Validate*` or
`Allow*` attribute and not to be mandatory, and drives the binding refusal for `Get-OERGroup`,
`Invoke-OERStructure`, `Get-OERSubscription` and the two configuration cmdlets with every sign-in and
transport mocked and counted at zero. `OER_COHORT_SOURCE_ROOT` points the scan at a scratch copy for
a mutation proof.

**Why a transport's refresh does not clear it.** The claims-challenge step-up and the token-rejected
retry of `Invoke-OERGraphRequest`, and the 401 retry of `Invoke-OERArmRequest`, call
`Initialize-OERAuth` with the session's own `TenantId` and `-ClaimsChallenge` or `-ForceRefresh`, on
behalf of a command that has already signed in. That is not the operator naming a tenant, so the
refresh puts back the value it found: a sign-in that failed in the meantime -- a pipeline neighbour's,
for example -- is not forgotten because a token was renewed. Read in the code: a refresh for a session
that itself named no tenant (`organizations`) names none either, and while the marker is set it is
refused like any other such call.

**Every refusal marks.** `Initialize-OERAuth`'s `ArmTokenAcquisitionFailed` marks although the Graph
half of that sign-in connected, and `GraphSessionChanged` marks although no sign-in was attempted:
the rule is that a sign-in that did not go the whole way leaves the session uncertain, as it leaves
the latch set. The ARM wrapper's refusal of a request with no token, which raises the same id, is
not a sign-in and marks nothing. The cost is a later no-tenant command refused where only an Azure
token failed, or where another `Connect-MgGraph` replaced the session; naming the tenant, or
`Connect-OER`, sends again.

**`Invoke-OERStructure`, piped several documents** (Sprint 9 step 3, Ruling R14). With `-TenantId`,
every document's sign-in names the tenant, so A19's same-frame retry is unchanged: after one
document's sign-in failed, the next one signs in again, and a success clears the marker. Without
`-TenantId`, every document after one whose sign-in was refused is refused too, and the batch sends
nothing more.

**Known limits.**

- A `Connect-OER` whose parameters cannot be bound -- a mandatory parameter bound to an empty string,
  for example -- is refused by PowerShell before its `process` block runs, so it marks nothing, and a
  no-tenant command after it inherits the previous session as before.
- A `-TenantId` of spaces on any cmdlet that signs in, other than `Connect-OER`, passes
  `[ValidateNotNullOrEmpty()]` and nothing more (A12, above). It names a tenant that is not the
  session's and is looked up like any value that is not a tenant ID, and refused with
  `TenantResolutionFailed` when the authority resolves it to no tenant. That path ends in a refusal,
  so decision A12's attribute stands as decided for those cmdlets: PowerShell 7.4's
  `[ValidateNotNullOrWhiteSpace()]` does not exist on 7.2, which the module supports, and a
  `[ValidatePattern()]` or `[ValidateScript()]` that refused spaces at binding on 7.2 would replace
  the attribute A12 names on every one of them for a value that is already refused.
- **`New-OERConfiguration` and `Set-OERConfiguration` refuse a `-TenantId` of white space only at
  binding** (Sprint 10 step 3, BL-96). They store the tenant and look nothing up, so such a value was
  written to the profile and refused only later, when a `Connect-OER -TenantAlias` read it back at its
  lookup: a profile nobody could use, found at sign-in time. Both now carry
  `[ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = '...')]` declared ABOVE
  `[ValidateNotNullOrEmpty()]`, with the message `The TenantId consists only of white space. Supply
  the tenant ID or a verified domain of the tenant.` A script, since 7.2 has no
  `[ValidateNotNullOrWhiteSpace()]`; `IsNullOrWhiteSpace` is exactly what 7.4's attribute tests, so a
  tab, a line break and a no-break space count as white space as a space does; and `ErrorMessage` on
  `[ValidateScript()]` exists since PowerShell 6, so it is available on 7.2. The order is measured,
  in plain PowerShell 7.6: validation attributes run in REVERSE declaration order, so with the script
  declared first an empty value still reaches `[ValidateNotNullOrEmpty()]` first and reads its own
  message (`The argument is null or empty`), a blank one reads the script's, and both carry
  `ParameterArgumentValidationError,<cmdlet>`. Declared the other way round, an empty value would
  read the white-space message, which is wrong for it. The attribute stays, since
  `TenantIdNotEmpty.Cohort.Tests.ps1` requires it on every carrier but `Connect-OER`.
  `Set-OERConfiguration` binds `-TenantId` from the pipeline, so a piped profile object whose
  `TenantId` is blank is refused per input object, at binding, and the next object is still
  processed. That is the safe direction, since the write would otherwise keep a blank tenant; the
  repair is `Set-OERConfiguration -TenantAlias <alias> -TenantId <tenant>`. That refusal reaches
  `$Error` and not `-ErrorVariable`, as the round-trip tests of `Set-OERConfiguration.Tests.ps1`
  already record for a binding failure on pipeline input. The refusal covers what is typed or piped
  in, not what is already stored. Existing profiles are read as before: `Get-OERConfiguration` and
  `Connect-OER -TenantAlias` are unchanged, and a stored blank `TenantId` is read and emitted as it
  is. `Set-OERConfiguration` takes the tenant from the file when `-TenantId` is not bound, and its
  guard on the resolved value tests truthiness, which `'   '` passes, so an update that names no
  `-TenantId` writes a stored blank back unchanged; only a real `-TenantId` replaces it.
- A no-tenant command after a refusal is refused even when the operator meant the previous tenant, and
  even when the module holds no session at all and the command would have signed in to
  `organizations`. Both are on the safe side; `-TenantId`, `Connect-OER` or `Disconnect-OER` sends
  again.
- The marker refuses only a command that names NO tenant. A command that names another tenant signs
  in to that tenant as it always did, and its own sign-in is checked like any other; one that names
  the previous tenant explicitly signs in there, as named.
- It does not close the known limit under
  [A command sends nothing under a sign-in a later command replaced](#a-command-sends-nothing-under-a-sign-in-a-later-command-replaced):
  `Invoke-OERStructure` or a name-looking builder without `-TenantId`, called inside a script block
  or a function in a pipeline, still takes another command's SUCCESSFUL sign-in for the session it
  began with. The marker records only sign-ins that did not succeed. Sprint 9 step 6b closed that
  limit for a document that names its tenant, by comparing the document's `tenantId` with the
  session after the sign-in, not through the marker (BL-88, under
  [A document names the tenant it was exported from](#a-document-names-the-tenant-it-was-exported-from));
  it stays open for a document without `tenantId` and for the builders.
- Each runspace imports its own copy of the module and so has its own marker (INFERRED, as for the
  state).

**The user-facing texts.** The README's `### Disconnect` section and the about topic's
`GRAPH SDK SESSION` each carry two paragraphs and the loop example, outside `SWITCHING TENANTS`. The
first: a sign-in that fails or is refused usually leaves the session as it was, and a script carries
on past the error; from then on a command that names no tenant -- no `-TenantId`, or
`-TenantId organizations` -- is refused with `SignInRefused` before it requests a token, and so are
its requests and the sign-ins of the cmdlets it calls; a command that names its tenant signs in as
usual; a successful sign-in naming the tenant, a successful `Connect-OER` with or without a tenant,
or `Disconnect-OER` sends again; and what the loop above did before this version, with the loop as
the example. The second: `Invoke-OERStructure` without `-TenantId` refuses every document piped to
it after one whose sign-in was refused; a `Connect-OER` whose parameters cannot be bound never runs,
so it leaves nothing behind; an empty `-TenantAlias`, typed or piped, is refused with
`InvalidTenantAlias`, and an empty, whitespace or `$null` `-TenantId` with `InvalidTenantId`, both
counting as a refused sign-in; every other cmdlet refuses an empty or `$null` `-TenantId` at
parameter binding, so that command never runs and sends nothing; `New-OERConfiguration` and
`Set-OERConfiguration` also refuse a `-TenantId` of white space only at binding (BL-96), so a blank
tenant can no longer be entered into a profile through them, while a profile already on disk with
one is still read as it is and keeps it through an update that does not name `-TenantId`; and on any
other cmdlet a `-TenantId` of spaces is looked up like any value that is not a tenant ID.
`Connect-OER`'s and `Disconnect-OER`'s help carry
the rule for their own side, `Connect-OER`'s `.PARAMETER TenantId` and `.PARAMETER TenantAlias` the
two empty values.

**The proof.** `tests/Unit/Private/Set-OERSessionUncertain.Tests.ps1` pins the owner: setting and
clearing return the previous value, and `$null` reads as clear. In
`tests/Unit/Private/Initialize-OERAuth.Tests.ps1`, the Describe
`Initialize-OERAuth session uncertain after a refused sign-in (A10)` pins the rule: a no-tenant call
refused after each kind of refusal, with no token call; `organizations` counted as no tenant; a
sign-in naming the tenant clearing the marker; `Connect-OER`'s `-ReclaimGraphSession` exempt and
clearing; a transport's refresh leaving it set; the BL-74 refusal leaving it as it was; and A19's
same-frame retry. `tests/Unit/Public/Connect-OER.Tests.ps1` (Context
`the session-uncertain marker (A10, BL-89)`) pins the mark before any sign-in, and
`tests/Unit/Public/Disconnect-OER.Tests.ps1` the clear and its `-WhatIf`. End to end, with no `try`,
in `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`: H2, rewritten -- after the refused
`Invoke-OERStructure -TenantId`, a plain command without `-TenantId` sends nothing until a command
names the tenant; H4, extended -- the A19 retry under `-TenantId` unchanged under A10; and H8 -- the
loop above, a refused `Connect-OER` and then an `Invoke-OERStructure` without `-TenantId` that
requests no token and sends nothing, and that sends after `Disconnect-OER` and a successful
`Connect-OER`. Gate 10 of [#static-source-gates](#static-source-gates) holds the owner, the variable
and the marker's three places in `Initialize-OERAuth`. For A12, the Context
`the session-uncertain marker (A10, BL-89)` in `tests/Unit/Public/Connect-OER.Tests.ps1` pins
`InvalidTenantId` for an empty, whitespace and `$null` `-TenantId`, beside an alias too, on every
credential set, with no profile read, no sign-in and the marker set, and `Connect-OER` with no tenant
at all still signing in; H11 runs the loop with a blank cell end to end, with no `try`: a refused
`Connect-OER -TenantId` and the `Invoke-OERStructure` after it, and an
`Invoke-OERStructure -TenantId` refused at binding, request no token and send nothing, and a row
naming the tenant then sends; and `TenantIdNotEmpty.Cohort.Tests.ps1` (above) holds the attribute.

Mutation-proved on copies of `source/` (the gate from a scratch project root), one exact edit per
mutant. Deleting the A10 refusal turns sixteen tests red: the A10 Describe's test after
`MissingClientSecret`, its seven tests after the other kinds of refusal, its ordering,
`organizations` and refused-itself tests and its two transport-refresh tests, and H2, H8 and H10
(fifteen before H10 was added).
Dropping `-not $ReclaimGraphSession` from the refusal turns the `-ReclaimGraphSession` test red.
Dropping the refresh terms from `$ClearsUncertainty`, or putting the marker back as clear at both
success ends, turns the two transport-refresh tests red. Dropping the `organizations` term turns the
`organizations` test red. Moving the check above the `GraphSessionChanged` refusal turns the ordering
test red (`GraphSessionChanged` expected, `SignInRefused` found). Deleting `Connect-OER`'s set turns
its nine marker tests, H10 and the gate's owner rule (stale) red (four marker tests and the owner
rule before the F1 tests below were added). Deleting `Disconnect-OER`'s clear turns
its clear test, H8 and the owner rule red -- H8 only through its after-`Disconnect-OER` step, added
for this: the `Connect-OER -TenantId` after it names the tenant and clears the marker on its own, so
without that step H8 stayed green. Moving the marker's set above `Lock-OERSignIn` but below the BL-74
check is caught by the gate's position rule alone, since no statement runs between the two; moving
it above the BL-74 check also turns the BL-74 marker test and the A19 BL-74 test red. A fourth
caller turns the owner rule red, and a direct write of the variable in `Disconnect-OER` the variable
rule and the owner rule (stale). `New-OERSignInRefusedError` ignoring `-SessionUncertain` turns its
two message tests and thirteen A10 tests red. One mutant is equivalent: putting the marker back as
clear at the CACHED return only changes nothing a test can see, since a cached return reached while
the marker was set always clears it -- the call named its tenant without a refresh, or passed
`-ReclaimGraphSession` -- and the position rule still holds that statement in place.

The final review's fixes are proved the same way (Rulings F1 to F3). F1: in the same Context of
`tests/Unit/Public/Connect-OER.Tests.ps1`, a bound empty, whitespace or `$null` `-TenantAlias`, an
empty one beside a `-TenantId` and an empty one read from a piped object are each refused with
exactly one `InvalidTenantAlias`, with no profile read, no sign-in and the marker set. H10, in the
same no-`try` Describe as H8, runs the loop with a blank alias after tenant A's app-only session:
`InvalidTenantAlias`, then an `Invoke-OERStructure` without `-TenantId` refused with exactly one A10
`SignInRefused`, with no token, no Graph and no ARM request and nothing planned; its control, the
next row naming tenant A, plans the document there. Reverting the condition to `if ($TenantAlias)`
turns the empty, `$null`, beside-`-TenantId` and piped tests and H10 red; run before the fix, H10
recorded one Graph and one ARM request and `would create group` in tenant A. The whitespace test
stays green under that mutant, since a whitespace alias is truthy and was always refused; it pins
the message. F2: the gate's known-answer table runs in every run, and three mutants each turn the
rule red -- `@{ ReclaimGraphSession = $true }` added to `Disconnect-OER.ps1`, `-R` added to another
file's `Initialize-OERAuth` call, and `Connect-OER`'s line deleted (stale owner). F3: the tests F3
(a) to (e) in the Describe `Initialize-OERAuth granted-tenant guard`. Deleting the comparison turns
(a) and (c) red; dropping its inequality turns (b) and the `organizations` ARM test red; dropping
either GUID term turns its (d) case red; and dropping the no-expected-tenant term turns (e) red.
No end-to-end pipeline test was added for F3: the A20 Describe's stubs answer one tenant per request
for both resources and record no header, so showing which token an ARM request carried would need
new stub machinery; the unit tests show that the refused ARM token is never cached.

**The proof of the white-space refusal** (Sprint 10 step 3, BL-96). The Context
`refuses a white-space -TenantId at binding (BL-96)` in `tests/Unit/Public/New-OERConfiguration.Tests.ps1`
and in `tests/Unit/Public/Set-OERConfiguration.Tests.ps1` binds a space, three spaces, a tab, a
carriage return and line feed, and a no-break space (U+00A0) with every mandatory parameter given,
in a `try` under `-ErrorAction Stop`. Each expects exactly `ParameterArgumentValidationError,<cmdlet>`,
a `ParameterBindingException`, the message carrying the text above, and `Export-OERConfiguration`
mocked in module scope and counted at zero. The mock writes a file when it is called, so the check
that no profile file exists (New) or that the existing one is byte-unchanged (Set) does not restate
the mock. One more test per file binds `''` and expects `The argument is null or empty` and not the
white-space message, which fixes the declaration order. Set adds the pipeline test: two piped
objects, the first with `TenantId = '  '`, give exactly one `ParameterArgumentValidationError,Set-OERConfiguration`
in `$Error`, the second object written once and the first one's file unchanged. Each file also has a
control with a real tenant, and `tests/Unit/Public/Get-OERConfiguration.Tests.ps1` a profile whose
stored `TenantId` is three spaces, read and emitted as it is; those passed before the change, and
are there to hold the unchanged half.

Mutation-proved on copies of `source/`, one exact edit per mutant. Deleting the `[ValidateScript()]`
turns the five blank-value tests red in New, and those five and the pipeline test in Set. Swapping
the two attributes turns the `''` test red in each. `IsNullOrEmpty` for `IsNullOrWhiteSpace` turns
the five blank-value tests red in each, and the pipeline test in Set. A script that trims only ASCII
spaces, run in `New-OERConfiguration` only, turns the tab, the line break and the no-break-space
tests red; an ASCII-whitespace regex turns only the no-break-space test red, in each. Dropping
`ErrorMessage` turns the five message assertions red in each (and, in Set, the pipeline test's
message assertion), since PowerShell then names the script in the message. Deleting
`[ValidateNotNullOrEmpty()]` from `New-OERConfiguration` turns the `''` test and the cohort's
attribute test for it red; the cohort's run-time row for it stays green, since the script refuses
`''` with the same id too, so the attribute test is the one that holds the attribute. In
`Set-OERConfiguration` only, inverting the script's test turns its control red. One mutant is
equivalent, run in `New-OERConfiguration` only: `Trim()` for `IsNullOrWhiteSpace`, which trims every
Unicode white space as the .NET method does.

## profile-path

Tenant profiles live at `<home>/.config/Omnicit.EntraRBAC/Profiles/<alias>.psd1`.

`<home>` is `[System.Environment]::GetFolderPath('UserProfile')`, falling back to `$HOME`, resolved
in `Resolve-OERProfilePath`'s `-BasePath` default. That is the same directory as `$env:USERPROFILE`
on Windows and the user's home directory on Linux and macOS.

**Do NOT write `$env:USERPROFILE` here:** it is a Windows-only variable, and this module declares
`CompatiblePSEditions = 'Core'`. Issue #40 was exactly this bug; seven cmdlets carry a
`-BasePath`/`-ProfileBasePath` default and `tests/Unit/Private/BasePathDefault.Cohort.Tests.ps1`
now guards all seven at once.

Profile schema -- `TenantId` is required, everything else optional:

```powershell
@{
    TenantId = '00000000-0000-0000-0000-000000000000'
    Naming   = @{
        Group   = 'role_sec_{area}_{tier}'
        AU      = '{prefix}_au_{name}'
        Catalog = 'CAT-{org}-{scope}'
    }
    Defaults = @{
        PrimaryApprovers        = @('<guid>', '<guid>')
        EscalationApprovers     = @('<guid>')
        Catalog                 = 'CAT-IT-PRG-Core'
        AuthenticationContextId = 'c1'
        ActivationMaxHours      = 8
    }
}
```

## type-data

`TypesToProcess` in the manifest is intentionally empty. Type data (ScriptProperty and AliasProperty
members) is registered inline with `Update-TypeData -Force` in `suffix.ps1`, mirrored in the dev-mode
psm1 loader.

`-Force` overwrites an existing member, so `Import-Module -Force` re-imports cleanly and cross-path
collisions -- the built module and a from-source import registering the same member from different
file paths -- do not fail with "member already present".

There is no `Types.ps1xml`, because `-AppendPath` cannot use `-Force` and is not idempotent across
paths.

`FormatsToProcess`, by contrast, IS active: format data is loaded natively via the manifest from
`source/Formats/Omnicit.EntraRBAC.Format.ps1xml`.

## dependencies

Two files name this module's dependencies, they say deliberately different KINDS of thing, and
neither is a copy of the other.

**`source/Omnicit.EntraRBAC.psd1` declares FLOORS.** Its `RequiredModules` entries are
`ModuleVersion` values, and a manifest `ModuleVersion` is always a minimum, never an exact pin and
never `latest` -- there is no manifest syntax for "newest". A floor already gives a consumer the
newest version they happen to have or install; what it fixes is the oldest version the module claims
to work against. This is what ships, and the Version column in CLAUDE.md's Dependencies table
reproduces it.

**`RequiredModules.psd1` resolves the BUILD AND TEST environment, and every entry in it is
`latest`.** Decision on record (Philip, 2026-09-21): the build and test environment runs the newest
release of every module, with nothing pinned anywhere in that file. The risk that a newly released
version breaks the build is accepted deliberately and is repaired when it happens, in its own commit
naming the module and the version that moved -- not pre-empted by a pin. Before this decision the
file pinned `Az.Resources` and `Microsoft.Graph.Authentication` to the manifest's floor values and
left `AzAuth` at `latest`; that mixture is gone.

So the two files still differ, and still should, but **they now differ in kind rather than in
value**, which is a different rule from the one this section used to state. Do not reconcile them by
writing a version number into `RequiredModules.psd1`, and do not reconcile them by trying to write
`latest` into the manifest.

**The cost, stated plainly, because it is real and nothing in the repository compensates for it.**
CI now tests the combination a NEW consumer gets -- newest AzAuth, newest
Microsoft.Graph.Authentication, newest everything -- which is the combination most consumers will
actually run, and which nothing tested before. In exchange, **the declared floors are no longer
exercised by anything.** A consumer sitting at exactly `AzAuth 2.9.0` or
`Microsoft.Graph.Authentication 2.36.0` is running a combination no test in this repository has ever
executed. The floors are now a claim, not a tested claim. Raising a floor to whatever CI last proved
green would make the claim true again at the cost of forcing an upgrade on those consumers; that
trade has not been made, and making it is a decision, not a cleanup.

**Drift has to stay visible for "repair it when it breaks" to be cheap.** With `latest` everywhere,
a red build is only quick to diagnose if the run says which module moved, so
`.github/workflows/build-and-test.yml` prints the name and version of everything under
`output/RequiredModules` immediately after the build resolves dependencies. That step is the reason
the decision is affordable; do not remove it as noise.

It **accounts for every directory** under that root: each one is either a version row or a
`skipped, not a version folder:` line, and nothing is filtered away in silence. The skipped lines
are real -- the bootstrapper unpacks a `.nupkg` into the module folder itself, leaving the package's
own `_manifest`, `_rels`, `dependencies` and `package` directories beside the version subfolder
(seen next to `Microsoft.PowerShell.PSResourceGet`'s `1.0.1`; a tree resolved with `-UseModuleFast`
appears not to have them). The first version of this step dropped them quietly, which made
PSResourceGet look like it had four versions and then, once filtered, made the filter itself a place
where a real module could vanish. A diagnostic that hides rows is the same shape as the defect it
exists to expose, which is why the accounting is stated here as a property to keep.

**`PowerShellForGitHub` is declared explicitly** even though `Sampler.GitHubTasks` already brings it
in transitively. Sampler's `Publish_Release_To_GitHub` task is declared
`-if ($GitHubToken -and (Get-Module -Name PowerShellForGitHub -ListAvailable))` and therefore SKIPS
SILENTLY when the module is absent -- see the reasoning kept in `build.yaml` next to the removed
`publish` workflow. A transitive dependency that silently decides whether a release step runs at all
is worth being able to see in the file that resolves it.

**`Az.Resources` was removed from the manifest on 2026-09-21, as vestigial.** It had been declared
`>= 9.0.3` since the ARM work landed, and the module never called a single cmdlet from it. Measured
in the source before removal: every `*-Az*` token under `source/` is either AzAuth's `Get-AzToken` /
`Clear-AzTokenCache`, the module's own local `Invoke-AzTokenCall` helper, or prose inside a comment
or a help block. There is no dynamic call either -- no `Invoke-Expression`, no string-built command
name, no `Get-Command 'Get-Az*'`, and every `& $x` in the module invokes a local scriptblock. The
`-IncludeARM` path never establishes an Az context: it caches an ARM bearer token as a SecureString
and `Invoke-OERArmRequest` sends it directly, which is the whole design recorded in
[#arm-transport](#arm-transport). The one real Az call in the module is the `Get-Command`-guarded
`Disconnect-AzAccount` in `Disconnect-OER`, and that is **`Az.Accounts`, not `Az.Resources`** --
a module the manifest never named, which arrived transitively behind the `Az.Resources` pin.

So a consumer was being made to install `Az.Resources` and its dependency tree for nothing. Removing
it makes the install smaller and the Gallery's dependency list honest.

**`Az.Accounts` took its place in `RequiredModules.psd1` for TEST reasons, not a runtime one.**
Pester's `Mock` resolves the command it is given and throws when it cannot, so a test that mocks an
Az cmdlet cannot run at all unless `Az.Accounts` is on `PSModulePath`. There are **two** such
reasons, and the second is the weightier one.

1. `tests/Unit/Public/Disconnect-OER.Tests.ps1` mocks `Disconnect-AzAccount` in `BeforeEach`, so
   with `Az.Resources` gone and nothing else pulling `Az.Accounts` in, every `It` in that file would
   fail before reaching its body. That mock does second duty locally: without it the test tears down
   the operator's real Az context and on-disk token cache -- the context used for the manual live
   verification this module's security rules require. `tests/Unit/Private/Initialize-OERAuth.Tests.ps1`
   mocks `Disconnect-AzAccount` in three further places for the same protection.

2. **`tests/Unit/Private/Initialize-OERAuth.Tests.ps1` holds the test-level PROOF of the premise
   this whole removal rests on.** The `It` named *"acquires and caches an ARM bearer token (no
   Connect-AzAccount) when -IncludeARM is set"* (lines 126-140 as of 2026-09-21) mocks
   `Connect-AzAccount` and then asserts `Should -Invoke ... Connect-AzAccount -Times 0`. That
   negative assertion is what demonstrates, in the suite rather than by reading the source, that
   `-IncludeARM` never establishes an Az context -- the fact `Az.Resources` was removed on. A second
   site in the same file mocks `Connect-AzAccount` defensively inside an ARM-failure test, and needs
   the command to resolve just as much.

**So do not remove `Az.Accounts` now that `Disconnect-OER` has changed.** Reason 1 was the one that
was easy to notice and easy to make obsolete, and on 2026-09-21 it partly WAS: `Disconnect-OER` no
longer calls `Disconnect-AzAccount`, so anyone skimming would conclude the mock, and then the entry,
is dead. It is not -- the assertion inverted to `-Times 0 -Exactly`, and a negative assertion still
needs the command to resolve. Reason 2 is untouched by that change and would
be silently destroyed. Worse, the destruction has a green-looking repair: removing `Az.Accounts`
makes the `Mock Connect-AzAccount` line throw, and "fixing" that by deleting the mock and its
`-Times 0` assertion leaves a passing suite with the proof gone -- the guard-shaped-but-inert shape
this repository already tracks in [#bearer-scrub-tests](#bearer-scrub-tests). If that mock ever
fails to resolve, the answer is to restore `Az.Accounts`, never to delete the assertion.

It is deliberately NOT added to the manifest: a test-environment need is not a consumer's need.

**DECIDED (Philip, 2026-09-21): `Disconnect-OER` no longer calls `Disconnect-AzAccount`.** This was
recorded here as raised-but-not-decided when `Az.Resources` was removed; it is now settled, and the
call is gone.

The reasoning is the same fact the removal rested on. The module never establishes an Az context --
`-IncludeARM` only acquires an ARM token, which `Invoke-OERArmRequest` sends itself -- so there is no
session of the module's own for `Disconnect-AzAccount` to end. The only thing the call could reach
was the OPERATOR's own Az session and their on-disk Az token cache, cleared as a side effect of
ending an unrelated one. That is the context used for this module's manual live verification, which
its security rules require, so the side effect landed on exactly the session an operator could least
afford to lose silently.

It is a user-visible behaviour change and is carried in `CHANGELOG.md` as one. The version is a
PATCH deliberately (Philip): nothing a caller invokes changes shape, and the removed behaviour was
never this module's to perform.

`Az.Accounts` stays in `RequiredModules.psd1`. Both reasons above survive the change -- the negative
`Connect-AzAccount` assertion is untouched, and `Disconnect-OER.Tests.ps1`'s assertion merely
inverts to `-Times 0 -Exactly`, which still needs the command to resolve before it can be written.

Nothing in `RequiredModules.psd1` is bundled into a build artefact. The built module under
`output/module/` contains only this module's own files, and `package_module_nupkg` packs that tree;
dependencies reach a consumer through the manifest's floors, which is what the file's own comment
now says.

Do not add other `Microsoft.Graph.*` SDK modules. The module intentionally uses raw
`Invoke-MgGraphRequest` (via `Invoke-OERGraphRequest`) to avoid typed SDK coupling and version drift.

## changelog-budget

`CHANGELOG.md`'s `[Unreleased]` section is not a working log. It is the literal text that ships as
the module's release notes. Sampler's `Create_changelog_release_output` task does three things, all
within that one task body.

**This section deliberately cites no line numbers.** `RequiredModules.psd1` resolves Sampler at
`latest` ([#dependencies](#dependencies)), so both the line numbers and the FILE drift underneath
any citation: the task used to live in `tasks/release.module.build.ps1` and now lives in
`tasks/Changelog.changelogmanagement.build.ps1`. Cite the task and the call instead, and re-verify
by reading the task body. **Verified against Sampler 0.120.1, 2026-09-21: the task had moved file,
and every behaviour below was unchanged.**

- **The `Update-Changelog` call** -- `Update-Changelog -Path $ChangeLogPath -OutputPath
  $ChangeLogOutputPath -ErrorAction Stop -ReleaseVersion $ModuleVersion -LinkMode none` rewrites the
  `## [Unreleased]` heading to `## [<version>] - <date>` in the OUTPUT copy. **The source
  `CHANGELOG.md` is never modified by a build**, which is why converting the heading by hand is a
  defect rather than a shortcut: it leaves the source section empty and the next build then
  publishes nothing.
- **The `$moduleManifestReleaseNotes` length branch** -- if the latest release section's `RawData`
  exceeds 10,000 characters it is cut with `.Substring(0, 10000)`, and otherwise passes through
  whole. No warning, no error; the note simply stops mid-sentence. Since the cut is a fixed-length
  `Substring`, a truncated value is always EXACTLY 10,000 characters, which is what makes
  `Length -lt 10000` a sound "was not truncated" proof.
- **The `Update-Manifest` splat** -- `PropertyName = 'PrivateData.PSData.ReleaseNotes'` with
  `Value = $moduleManifestReleaseNotes` is where the value lands in the built manifest.

`output/ReleaseNotes.md` is a red herring. The task sets `$ReleaseNotes` from THAT file (written
just above by `ConvertFrom-Changelog ... -Format Release -NoHeader`), falling back to the whole
`output/CHANGELOG.md` if it is empty or absent, and `$ReleaseNotes` is then used only as a
truthiness guard on the `if` that gates the manifest update. The value actually written is
`$moduleManifestReleaseNotes`, computed above from the latest release section alone, so nothing in
`output/ReleaseNotes.md` ever reaches the manifest.

**The history.** Issue #39 found `[Unreleased]` at 16,322 characters with the built `ReleaseNotes`
cut mid-sentence -- the 10,000 truncation, firing silently. PR #46 rewrote the section from a running
delta list into a product summary (21,017 -> 6,626 characters) and added an 8,000-character ceiling
as a margin under Sampler's cap. Six PRs later it was back at 7,969: **31 characters of headroom**,
which is issue #61. The rewrite worked; the process around it did not, since every PR appended to the
same section and nothing ever left it. The durable answer is therefore a rule about where finished
detail goes -- under a new dated heading -- not another trim. This branch archived the accumulated
body as `## [0.7.0] - 2026-08-28` and left `[Unreleased]` at 1,705 characters.

**Why the completeness proof reads the BUILT manifest and not the source file.** The two
measurements are not the same string. `(Get-ChangelogData -Path CHANGELOG.md).Unreleased.RawData`
includes the 15-character `## [Unreleased]` heading, while the published section carries the longer
`## [<version>] - <date>` form instead. Measured on this branch on 2026-08-28: published 1,719
characters against source 1,705, a gap of exactly 14, since `## [0.8.0-chore] - 2026-08-28` is 29
characters against 15 and both sides trim the same 2 trailing characters. **The gap is the
heading-length difference, and it grows with a longer version label.** So the source-side budget
always reads short of the article that actually ships, and only the manifest gate measures what a
consumer sees.

**Why the floor exists: a mechanical failure, not a length.** The floor catches one thing: an emptied
or hand-converted `[Unreleased]` section, which publishes `ReleaseNotes` of length 0 while the build
reports success (measured 2026-09-17). Reproduced on 2026-09-23 with a heading-only `[Unreleased]`:
Sampler logged `No changes detected in current release, exiting.` and `No Release notes found to
insert.`, and the build still ended `Build succeeded. 7 tasks, 0 errors, 0 warnings` with the built
`ReleaseNotes` empty. The floor does NOT measure whether a note is any good -- review does that -- and
it never did: 500 characters of filler passed the old 500-character floor exactly as well as 500
characters of release note.

It is not redundant with the non-empty assertion. For a completely empty `[Unreleased]` section
`Get-ChangelogData` does NOT return `$null`: it returns the 17-character string `## [Unreleased]\n\n`.
Verified by execution against a synthetic changelog, with these consequences, all confirmed by
running them:

- the pre-existing `RawData | Should -Not -BeNullOrEmpty` **passes** on that section, so it does not
  see the empty shape at all;
- the old ceiling-only `-BeLessOrEqual 8000` **passes** on it too -- it is blind to the empty shape,
  which is the OPPOSITE failure from the oversize section it was added for and which it catches
  correctly. It is not an inert guard, and it does not belong in this repo's ledger of those;
- the body floor **fails** on it: after the heading line, the body trims to 0 characters.

`$null` comes back only when the `## [Unreleased]` heading is missing altogether, which the non-empty
assertion does catch. The two assertions genuinely split the space; neither is redundant. The more
familiar framing -- `$null.Length` is the integer `0`, so a bare length check passes silently -- is
true in general and is what the in-code comment says, but it is not the mechanism here, and the
17-character measurement is the sharper fact.

**Why the floor is 50 characters of BODY, not 500 of `RawData`** (Philip, 2026-09-23). The reasons
for dropping the 500 are recorded under
[#publish-on-merge](#the-release-note-floor-after-a-stable-release): it failed pull requests that
were not wrong, and the only way past it was padding that every merge would then publish. What
stays is the part with a real job, and one sentence -- 50 characters -- is enough to tell an empty
section from a written one. The floor now measures the body, the section after its heading line,
trimmed, so the heading no longer counts towards it and an empty section measures 0 rather than 17.
The first line must be exactly `## [Unreleased]` before the split is trusted; if it is not, the
check fails there and says so instead of measuring from the wrong line.

**What `tests/QA/module.tests.ps1` asserts, as of P14.** Source side: the first line of
`[Unreleased]` is exactly `## [Unreleased]`, the body after it is at least 50 characters, and the
whole `RawData` is at most 4,000. Artefact side: the built manifest carries a
`PrivateData.PSData.ReleaseNotes` key, non-empty; its body after the heading line is at least 50
characters; the whole value is strictly less than 10,000; its heading line starts with `## [`, the
built version and `]`; and its body is `-BeExactly` the source body. The built version is
`ModuleVersion` plus `-` and `Prerelease` when there is one -- the string Sampler's task reads back
from the built manifest (`Get-BuiltModuleVersion`, through `Split-ModuleVersion`) and passes to
`Update-Changelog -ReleaseVersion` -- and the closing bracket is part of the prefix, so `1.0.1`
cannot pass for `1.0.1-preview0001`. Close-out: while the body of `[Unreleased]` contains `No changes
to the module since`, it must be exactly the close-out sentence for the latest dated section, with
whitespace collapsed since the sentence wraps; and a diff touching `source/` fails while that clause
stands. Finally, the "changelog has been updated" diff rule fires only when a changed path matches
`^source/`: a customer-facing document is not served by an entry forced out of a docs-only PR. The
close-out check reads the same diff through the same function, and skips on the same condition.

**Why the whole body is compared, not a 400-character tail.** Until P14 the artefact side compared
the last 400 characters of the published notes with the last 400 of the source section, after
`TrimEnd()`. Truncation always removes the END, so a tail compare cannot be fooled by a cut -- it
was falsified against a value cut at 900 characters, comfortably inside every length bound, and
caught it -- but it sees nothing earlier than its 400 characters. Measured on 2026-09-23: one
character removed from the middle of the built body (index 642 of 1,285, so 643 characters from the
end) passed the old test file unchanged and failed the exact comparison, which named the index. A
comparison of the whole body is the stronger proof against a cut, and against any other change on
the way to the manifest. It needs no normalization: measured the same day against a fresh build, the
source and published bodies after the heading line were byte-identical -- 1,285 bytes each, LF only,
the same two trailing newlines -- since `Update-Changelog -LinkMode none` rewrites the heading line
and nothing else. The tail sample also needed a floor above 400 to have a tail to take; the exact
comparison does not, which is part of what let the floor drop to 50. The heading check is new with
it: every earlier check ignored the heading line, so a note published under another version's
heading passed them all.

That measurement, and the falsification of every changed check, ran on a local build whose version
was supplied the way CI supplies it, through `$env:ModuleVersion` (`1.0.1-test-changelog-floor0001`,
stamped as `1.0.1` with prerelease `test`). Without GitVersion on the machine, a local build falls
back to `0.0.1`, and the version cap below then fails by design.

Both artefact-side checks read the BUILT module, and `build.yaml`'s `test` workflow does not include
`build`. The notes gate additionally compares that artefact against the CURRENT `CHANGELOG.md`, so a
build older than the last changelog edit turns it red -- the correct direction of failure, since a
stale build is exactly the state in which the source-side gates are green while the published note is
wrong. The version cap reads only the artefact's own version and never `CHANGELOG.md`, so staleness
reddens it only when no built module resolves at all, or when the stale artefact was itself outside
the `1.x` line.

**Why option B was measured and NOT taken.** Option B was to feed `PrivateData.PSData.ReleaseNotes`
from a purpose-written file instead of from the changelog. Sampler hardcodes
`Value = $moduleManifestReleaseNotes` in the task body with no configuration hook, so B requires a
repo-owned task in a `.build/` folder (`build.ps1:323-324` loads `.build/**/*.ps1` and lets it
override Sampler's own tasks) wired into `build.yaml`'s `build:` workflow. That is new machinery with
no precedent in this repo, running on every build, whose failure mode is an empty or wrong
`ReleaseNotes` -- which is the #39 defect. The benefit at the time was zero, since nothing published
then. It is no longer zero, since every merge to `main` now publishes and `ReleaseNotes` is read by
consumers on the Gallery -- but the cost has gone UP with it, because an empty `ReleaseNotes` is now
published rather than merely built. And B's desired OUTPUT -- a short blurb plus a link rather than the
whole log -- is obtained by making `[Unreleased]` be that blurb, which is what this branch did. Do
not re-litigate this from scratch; if the coupling ever does bite, the `.build/` route is where to
start.

**A Pester trap found while writing these gates.** A `-Because` string must never contain the word
"because" -- Pester deletes every occurrence of it from the rendered message, so the explanation
prints as scrambled prose while the assertion itself works. Two of this branch's messages hit it
before it was caught. The mechanism, the executed proof and the repo-wide rule live with the other
test shapes that look like guards but are not, in
[#bearer-scrub-tests](#bearer-scrub-tests).

## version-cap

> **Lifted on 2026-09-13 (issue #62).** The cap below `1.0.0` described here is history; the
> version is now held in the `1.x` line. The measured GitVersion rule in this section still holds.
> What changed, and why the original major pattern was not restored in full, is in the last
> subsection, "Lifted to 1.0.0".

Philip's decision, 2026-08-24: **nothing builds at or above `1.0.0` until he calls the first real
release.** Until then the version is purely incremental and the effective ceiling is `0.999.999`.
When the module is actually published, versioning is revisited and made semantically correct with
respect to the breaking changes that have accumulated since `0.1.0`. This is a release decision, not
a downgrade.

Two independent causes had to be fixed together, since fixing either one alone leaves the other in
place:

1. **A local annotated tag `v1.0.0` on commit `778601a`**, never pushed. **GitVersion takes the
   HIGHEST reachable version tag, or `next-version`, whichever is greater, as its base version** (a
   `release/x.y.z` branch name is a third candidate -- see below),
   and returns a tag's version verbatim when the tag sits on HEAD. So any tag at or above
   `next-version` overrides it -- and `v1.0.0` was above every value `next-version` could have been
   lowered to while the cap holds, so editing `next-version` with that tag standing would have
   changed nothing. This is why the tag had to be DELETED, not merely left in place beside a lowered
   `next-version`.
2. **Commit `5816e87`** ("fix(errors)!: unify the nothing-to-update ErrorId") matched the
   `^[a-z]+(\(.+\))?!:` alternation of `major-version-bump-message`.

Together they made `main` build `2.0.0-preview0001`. `main`'s own `next-version` was `1.0.0` at the
time, matching the tag exactly, so the major bump landed on a `1.0.0` base and produced `2.0.0` --
which is why both levers had to move, and why neither one alone is the whole story. In fact TWO
commits reachable from `main` match that alternation -- `715fb6d` as well as `5816e87` -- and the
result was still `2.0.0` rather than `3.0.0`: this repository's own history confirming the
at-most-one-increment rule measured below.

**Everything in this section was MEASURED, not reasoned.** `gitversion.exe` 5.12.0 -- on this
machine at `C:\Program Files\Git\cmd\gitversion.exe`, a GitTools binary dropped into Git's `cmd`
folder and NOT part of Git for Windows (its version resource reads `GitTools and Contributors`,
`Copyright GitTools 2023`, and it is dated 2025-11-08 while every genuine Git binary beside it is
2026-07-10 from the Git 2.55.0 install; do not expect to find it on a clean install) -- run against
throwaway repositories carrying this repo's `GitVersion.yml` verbatim -- `mode: ContinuousDelivery`,
`next-version: 0.8.0`, the four bump-message patterns and the whole `branches:` block, unedited --
each repository built from scratch per row and `.git/gitversion_cache` deleted before every run.

**The rule, in full.** GitVersion picks a BASE, then applies AT MOST ONE increment to it:

- **Base** -- the greatest of three candidates: the highest reachable version tag, `next-version`,
  and the `x.y.z` parsed out of a `release/x.y.z` branch name. The last of those needs no tag and no
  config in this repo's `GitVersion.yml`: the `release:` block is inherited from GitVersion's own
  defaults, and it applies both to the branch being built and to a branch named by a STANDARD merge
  commit message (`Merge branch 'release/2.0.0' into main`, `Merge pull request #99 from
  release/2.0.0`). One exception to the comparison: a tag sitting on HEAD supplies its
  `MajorMinorPatch` verbatim and takes no increment, and it outranks every other tag and
  `next-version` however high they are, but a higher `release/x.y.z` still beats it. Only the
  `MajorMinorPatch` comes from the tag. The prerelease LABEL never does: a release tag on HEAD
  yields no label on any branch, and a prerelease tag on HEAD takes the BRANCH's label, not its own
  -- measured, `v0.9.0-alpha.1` on HEAD builds `0.9.0-preview.1` on `main` (`main`'s own
  `tag: preview`, with the counter reset) and `0.9.0-chore-x.1` on `chore/x`.
- **The window the increment is read from** -- the commits since the NEAREST reachable tag, which is
  not necessarily the tag that supplied the base, and every reachable commit when no tag exists at
  all.
- **Whether an increment applies at all** -- a TAG base NOT on HEAD takes one on any branch whose
  config sets a default increment, and every branch this repo's convention produces does, by two
  different routes: `Patch` on `main` and, by inheritance from it, on `chore/`, `feat/`, `refactor/`
  and `test/`, which match no `branches:` block at all; and `Patch` explicitly on `fix/`, which
  matches the `hotfix:` block. The prerelease label is the tell -- `fix/x` builds `3.0.1-fix.1+1`,
  carrying `hotfix:`'s `tag: fix`, where `chore/x` builds `3.0.1-chore-x.1+1` from its own branch
  name. A `release/*`
  branch is the exception -- the inherited `release:` block carries `increment: None`, so a tag base
  there takes no default increment either. Measured: `v3.0.0` on HEAD~1 computes `3.0.1` on `main`
  and `3.0.0` on `release/2.0.0`. A `next-version` or `release/x.y.z` base likewise takes none by
  default. In every one of those no-default cases the base is used exactly as written when no
  `+semver:` commit is in the window -- but one there still moves it, including on a tag base that
  took no default (`v3.0.0` on HEAD~1 plus `+semver: minor`, on `release/2.0.0`, measures `3.1.0`).
- **How large the increment is** -- for a tag base, the GREATER of the branch's default increment
  and the highest `+semver:` level in the window; for a `next-version` or `release/x.y.z` base, the
  highest `+semver:` level alone, the branch default contributing nothing. Never more than one
  increment, whatever the commit count.

**One limit, stated because the document otherwise reads as universal over tags.** Everything above
about tags was measured with RELEASE tags (`v0.9.0`). A PRERELEASE-labelled tag behaves differently
and is out of scope of the "a tag base always takes one" rule: `v0.9.0-preview.1` on an ancestor
computes `0.9.0`, not `0.9.1`, and `+semver: minor` in the window does not move it either -- what
advances is the prerelease counter (`FullSemVer 0.9.0-preview.2+1`). The repo has never used one;
the rows are in the table below so that nobody has to guess.

The branch default is `Patch` on `main` and on every branch prefix this repo's convention uses
(`chore/`, `feat/`, `fix/`, `refactor/`, `test/`). It is `Minor` on any branch matching the
`feature:` block's `^f(eature(s)?)?[\/-]` regex -- measured, that is a name STARTING with
`feature/`, `feature-`, `features/`, `features-`, `f/` or `f-`. **Both branch regexes are anchored
at the start of the name since 2026-10-08 (BL-57)** -- `feature:` as above and `hotfix:` as
`^(hot)?fix(es)?[\/-]` -- so, like the inherited `release:` regex, they test the PREFIX. `feat/`
alone does not match `feature:`, since `feat` is neither `f` nor `feature` followed by a separator,
so no branch this repo's convention produces gets the `Minor` default, whatever follows its prefix.

Before the anchor both regexes were unanchored and tested the WHOLE branch name, and `feature:` beat
`hotfix:` when both matched: measured against a `v0.9.0` ancestor, `chore/feature-flags`, `feat/f-x`
and `fix/feature-parity` all took the `Minor` default, although all three are conventional names
under the prefix table in `CLAUDE.md`, while `chore/feature`, `chore/features`, `chore/featurex` and
`chore/xfeature` computed `0.9.1` -- the separator was part of the match, not decoration. Classified
on 2026-10-08 with `[regex]::IsMatch` and `IgnoreCase`, the .NET match GitVersion makes, the anchor
changes five such names: `chore/feature-flags`, `feat/f-x` and `test/off-the-shelf-x` no longer
match `feature:`, `fix/feature-parity` matches `hotfix:` alone, and `chore/prefix-cleanup` no longer
matches `hotfix:`, so its prerelease label comes from its own name instead of `fix`. The versions
those names now compute were not re-measured with `gitversion.exe`; by the `chore/x` and `fix/x`
rows below they take the `Patch` default. Only `main` publishes, and `^main$` did not change.

**Which base GitVersion picks.** Branch `main` unless a row names one; no `+semver:` commit is
reachable in any of these:

| Reachable tags, branch name, merge commits | Computed `MajorMinorPatch` |
|---|---|
| none | `0.8.0` -- `next-version` supplies the base, and it takes no DEFAULT increment |
| `v0.5.0` on an ancestor | `0.8.0` -- `next-version` still wins; the tag is NOT the base |
| `v0.7.9` on an ancestor | `0.8.0` -- `next-version` still wins |
| `v0.8.0` on an ancestor (EQUAL to `next-version`) | `0.8.1` -- the tag wins, so "at or above"; and a TAG base does take a default increment |
| `v0.9.0` on an ancestor | `0.9.1` -- the tag wins and takes the branch default, `Patch` on `main` |
| `v1.0.0` on an ancestor | `1.0.1` -- the tag wins |
| `v0.9.0` on HEAD~3 (FARTHER) and `v0.5.0` on HEAD~2 (NEARER) | `0.9.1`, `FullSemVer 0.9.1-preview.1+3` -- the HIGHEST tag wins, not the nearest, and the `+3` names `v0.9.0`'s commit as the base |
| `v1.2.0` on an ancestor and `v0.9.0` on HEAD | `0.9.0` -- a tag ON HEAD is returned verbatim and outranks a HIGHER ancestor tag |
| `v0.5.0` on HEAD | `0.5.0` -- verbatim and with no prerelease label, even though `next-version` is HIGHER |
| `v1.0.0` on HEAD | `1.0.0`, verbatim -- the HEAD short-circuit is not special to `0.x` |
| `v9.9.9` on an UNREACHABLE side branch | `0.8.0` -- "reachable" is a real qualifier, not a hedge |
| `v0.9.0-preview.1` on an ancestor | `0.9.0` -- a PRERELEASE tag base takes NO `MajorMinorPatch` increment; the prerelease counter advances instead (`FullSemVer 0.9.0-preview.2+1`) |
| `v0.9.0-preview.1` on HEAD | `0.9.0` -- the HEAD short-circuit is not special to release tags. The `FullSemVer 0.9.0-preview.1` is `main`'s OWN `preview` label, not the tag's: `v0.9.0-alpha.1` on HEAD of `main` also builds `0.9.0-preview.1`, and on `chore/x` builds `0.9.0-chore-x.1` |
| `v1.0.0-preview.1` on an ancestor | `1.0.0` -- so a prerelease tag breaches the cap exactly as a release tag would |
| no tag, branch NAMED `release/2.0.0` | `2.0.0` -- a branch NAME is a third base candidate; no tag is involved anywhere |
| no tag, branch NAMED `release/0.5.0` | `0.8.0` -- it joins the same greatest-wins comparison, and `next-version` outranks it |
| no tag, branch `releases/2.0.0` or `release-2.0.0` | `2.0.0` on both -- the inherited `release:` regex takes those spellings; `rel/2.0.0` measures `0.8.0` and does not |
| no tag, branch `xrelease/2.0.0`, `my-release/2.0.0`, `chore/release/2.0.0` or `pre-release-2.0.0` | `0.8.0` on all four -- the `release:` regex is ANCHORED at the START of the branch name, as `feature:` and `hotfix:` are too since BL-57 |
| no tag, branch `chore/release-blockers` (a real branch from this repo's history) | `0.8.0`, with its ordinary branch-name label -- names that merely CONTAIN `release` are unaffected |
| no tag, branch `release/blockers` (matches, but no parsable version) | `0.8.0` -- the `release:` block applies (the label becomes `beta`) but nothing parses out, so `next-version` stands |
| `v3.0.0` on an ancestor, branch `release/2.0.0` | `3.0.0` -- the higher candidate wins, here the tag, and it takes no increment, since the `release:` block sets `increment: None` (on `main` the same tag computes `3.0.1`) |
| `v1.0.0` on an ancestor, branch `release/2.0.0` | `2.0.0` -- and here the branch name |
| `v0.5.0` on HEAD, branch `release/2.0.0` | `2.0.0` -- the HEAD short-circuit does NOT outrank a higher `release/x.y.z` base |
| `v0.5.0` on HEAD, branch `release/0.3.0` | `0.5.0` -- but it does win when it is the higher of the two |
| no tag, merge commit `Merge branch 'release/2.0.0' into main` | `2.0.0` -- a merge MESSAGE naming a release branch supplies the same candidate |
| no tag, merge commit `Merge pull request #99 from release/2.0.0` | `2.0.0` -- the GitHub PR merge form works too |
| no tag, merge commit `Merge pull request #99 from PhilipHaglund/release/2.0.0` | `0.8.0` -- the owner-prefixed form GitHub actually writes does NOT match |
| no tag, merge commit with an arbitrary message naming `release/2.0.0` | `0.8.0` -- it must be a STANDARD merge message, not just any merge |
| no tag, a PLAIN (one-parent) commit whose message is `Merge branch 'release/2.0.0' into main` | `0.8.0` -- it must be a real merge commit, not just merge-shaped text |
| no tag, branch `fix/2.0.0`, `hotfix/2.0.0`, `feat/2.0.0`, `chore/2.0.0`, `support/2.0.0` or `feature/2.0.0` | `0.8.0` on all six -- only `release/`-family names parse a base out of the branch name |

**How much it increments that base.** Branch `main` unless a row says otherwise; where a row lists a
sequence, it is history order, earliest first:

| Reachable tags and `+semver:` commits | Computed `MajorMinorPatch` |
|---|---|
| no tag, one `+semver: fix` | `0.8.1` -- a `next-version` base IS moved by a bump message; it is not used verbatim unconditionally |
| no tag, one `+semver: minor` | `0.9.0` -- the same at minor level |
| no tag, TWO `+semver: minor` | `0.9.0` -- increments are NOT cumulative: one step, whatever the commit count |
| no tag, two `+semver: minor` and one `+semver: fix` | `0.9.0` -- the HIGHEST level in the window wins, not the first or the last |
| no tag, one `+semver: major` | `0.8.0` -- the major lever really is dead; `'(?!)'` matches nothing |
| no tag, one `feat!: ...` commit | `0.8.0` -- dead through the alternation's other half too |
| `v0.9.0` ancestor, no `+semver:` commit | `0.9.1` -- a TAG base always takes an increment: the branch default |
| `v0.9.0` ancestor, one `+semver: fix` | `0.9.1` -- indistinguishable from the default here; patch is the DEFAULT, not the rule |
| `v0.9.0` ancestor, one `+semver: minor` | `0.10.0` -- so a tag base is NOT always patch-incremented |
| `v0.9.0` ancestor, TWO `+semver: minor` | `0.10.0` -- one step from a tag base as well |
| `v0.9.0` ancestor, only `+semver: none` | `0.9.1` -- `no-bump-message` does NOT cancel a tag base's default increment |
| `v0.99.0` ancestor, one `+semver: minor` | `0.100.0` -- a minor increment never carries into major |
| one `+semver: minor`, THEN `v0.9.0`, then a plain commit | `0.9.1` -- the window opens after the tag; an earlier bump message is ignored |
| `v0.9.0`, then `+semver: minor`, then `v0.5.0`, then a plain commit | `0.9.1` -- the window opens at the NEAREST tag (`v0.5.0`), not at the tag that supplied the base (`v0.9.0`) |
| `v0.9.0`, then a plain commit, then `v0.5.0`, then `+semver: minor` | `0.10.0` -- the same shape with the message INSIDE the window; contrast the row above |
| one `+semver: minor`, THEN `v0.5.0` (below `next-version`, so not the base), then a plain commit | `0.8.0` -- a tag that LOST the base comparison still closes the message window |
| `v0.9.0` on HEAD, whose own message is `+semver: minor` | `0.9.0` -- the HEAD short-circuit outranks a bump message as well as a higher tag |
| branch `feature/x`, `v0.9.0` ancestor, no `+semver:` commit | `0.10.0` -- the branch default is `Minor` there; `Patch` is a property of the branch config, not of tag bases |
| branch `feature/x`, `v0.9.0` ancestor, one `+semver: fix` | `0.10.0` -- the GREATER of branch default and message level wins; a message cannot lower it |
| branch `feature/x`, no tag, one `+semver: fix` | `0.8.1` -- on a `next-version` base the branch default contributes nothing at all |
| `v0.9.0` ancestor on `chore/x`, `feat/x`, `fix/x`, `refactor/x`, `test/x` | `0.9.1` on all five -- every prefix this repo's convention uses defaults to `Patch` |
| `v0.9.0` ancestor on `f/x`, `features/x`, `feature-x` | `0.10.0` on all three -- the `feature:` regex takes several spellings, and all three still START the name under BL-57's anchor; `feat/` is not one of them |
| `v0.9.0` ancestor on `chore/feature-flags`, `feat/f-x`, `fix/feature-parity` | `0.10.0` on all three BEFORE BL-57's anchor (2026-10-08), when the regex tested the WHOLE name and `feature:` beat `hotfix:`; with the anchor none of the three matches `feature:` (classified, not re-measured), so all three take the `Patch` default, as the `chore/x` and `fix/x` row above |
| branch `release/2.0.0`, no tag, no `+semver:` commit | `2.0.0` -- like `next-version`, a `release/x.y.z` base takes NO default increment |
| branch `release/2.0.0`, no tag, one `+semver: minor` | `2.1.0` -- but a bump message moves it, exactly as it moves a `next-version` base |
| branch `release/2.0.0`, no tag, one `+semver: fix` | `2.0.1` -- same at patch level |
| `v0.9.0-preview.1` ancestor, one `+semver: minor` | `0.9.0` -- a PRERELEASE tag base is moved by neither the branch default nor a bump message |

Apart from the rows that name a branch, everything above was measured on `main` and then re-run on a
`chore/x` branch: all 37 numbers reproduce exactly, and only the prerelease label differs. **Three
earlier revisions of this anchor got this rule wrong, each by generalising a correct measurement one
boundary too far.** The first claimed a reachable tag always wins whatever its value -- refuted by
the `v0.5.0`-on-an-ancestor row. The second said the NEAREST reachable tag -- refuted by the two-tag
row, where the farther `v0.9.0` beats the nearer `v0.5.0`. The third said "a TAG base is
patch-incremented, `next-version` is used verbatim" -- false on both halves, since `v0.9.0` plus a
`+semver: minor` builds `0.10.0` and a bare `next-version: 0.8.0` plus a `+semver: fix` builds
`0.8.1`; it also contradicted the HEAD short-circuit stated two sentences above it, a tag on HEAD
taking no increment at all. Do not restate any of the three; re-measure with the tables above if you
doubt the rule.

**The tag was DELETED rather than moved.** It was never pushed and nothing was ever published from
it, so it costs nothing to recreate at real release time from the commit that actually ships -- and
moving it would have left a `1.0.0` tag reachable as the increment base, which is cause 1 all over
again, just on a different commit. The exact recreation command, with the original tagger data, is
recorded in `docs/live-verification/chore-version-cap-and-changelog-budget-checklist.md` so nothing
is lost. Running it before the release is called would re-breach the cap.

**A `release/x.y.z` BRANCH re-breaches the cap just as a tag does, and leaves no tag behind to
find.** Per the base table above, a branch named `release/1.0.0` computes `1.0.0` with no tag
anywhere in the repository, and so does a merge commit on any branch whose standard merge message
names one. `release/` is not among the prefixes in `CLAUDE.md`'s branch-naming table, and cutting
one is the natural first move when the release is finally called -- which is precisely when the cap
is still supposed to be holding. Do not create one, or a `releases/...` or `release-...` name, until
the cap is lifted.

**The blast radius is narrow, and measured.** `release:` is ANCHORED at the start of the branch
name, as `feature:` and `hotfix:` are too since BL-57: `xrelease/2.0.0`, `my-release/2.0.0`,
`chore/release/2.0.0` and `pre-release-2.0.0` all compute `0.8.0`, and so does this repo's own
historical `chore/release-blockers`. A matching name with no parsable version (`release/blockers`)
is harmless too -- it changes the prerelease label to `beta` and leaves `next-version` standing.
None of this repo's own prefixes carry the hazard either: `fix/2.0.0`, `hotfix/2.0.0`, `feat/2.0.0`,
`chore/2.0.0`, `support/2.0.0` and even `feature/2.0.0` all measure `0.8.0`. And every one of the 53
merges reachable from this branch is the GitHub owner-prefixed form
(`Merge pull request #77 from PhilipHaglund/fix/graph-retry-after`), which does NOT feed the release
route -- so only a deliberately cut `release/x.y.z` branch, or a hand-written `Merge branch
'release/x.y.z'`, can trigger it here.

**`minor-version-bump-message` and `patch-version-bump-message` are deliberately left working**, so
intent (feature versus fix) is still recorded in history for when semantics are switched back on.
They cannot threaten the cap, and the real reason is stronger than the "minor bumps roll `0.8` ->
`0.9` -> `0.10`" argument earlier revisions of this anchor gave. Nothing rolls inside a single
computation: this repository has no reachable tag, so the base is `next-version` and at most one
increment is applied, at the highest reachable `+semver:` level -- which makes `0.8.0`, `0.8.1` and
`0.9.0` the entire set of versions a `+semver:` BUMP MESSAGE can produce here. (A commit message can
still reach `1.0.0` and beyond by a different route -- a standard merge message naming a
`release/x.y.z` branch, per the base table above. That is a branch-naming hazard rather than a
bump-lever one, and it is covered by the paragraph above and by `CLAUDE.md`.) Rolling is what
happens across RELEASES, once each release leaves a tag behind to serve as the next base, and even
there a minor increment never carries into major: `v0.9.0` plus `+semver: minor` measures `0.10.0`,
and `v0.99.0` plus `+semver: minor` measures `0.100.0`. Only the major lever is neutralised, with
the pattern `'(?!)'` -- an empty negative lookahead, which always fails in .NET regex, so no commit
message can match it. Measured on 2026-08-28, no commit reachable from this branch carries a
`+semver:` token at all, which is why the computed base is `0.8.0` with no increment applied. The
original pattern to restore at publish time,
`'(\+semver:\s?(breaking|major))|(^[a-z]+(\(.+\))?!:)'`, is quoted in `GitVersion.yml` itself beside
the disabled one.

**The trap: `.git/gitversion_cache` is stale after any tag change**, and makes the very build you use
to verify the fix report the OLD version. Delete it before measuring. This has already cost one
session.

A regex in a config file is a convention, so the cap is additionally enforced where it cannot be
argued with: a QA gate in `tests/QA/module.tests.ps1` fails when the module under test reports a
version at or above `1.0.0`. It reads the version from the built artefact rather than by re-running
GitVersion -- what matters is what was stamped into the module, whatever produced it -- and it
compares `[System.Version]` values rather than strings, since as strings `"10.0.0"` sorts before
`"2.0.0"`. It is preceded by an explicit `Should -Not -BeNullOrEmpty` and
`Should -BeOfType [System.Version]`: `$null | Should -BeLessThan ([version]'1.0.0')` **passes** in
Pester 5.7.1, so without those two lines the cap would have been one more guard-shaped-but-inert
test.

**`next-version` is `0.8.0`, not the `0.7.0` that issue #55's text names.** This branch creates a
`## [0.7.0] - 2026-08-28` heading for the archived detail, and #55's own invariant -- the next number
above the newest dated heading -- then yields `0.8.0`. Keeping `0.7.0` would also risk a duplicate
heading if a release were ever cut at exactly `0.7.0`, since Sampler's `Update-Changelog` would
synthesise a second one.

At release time, lift all of it together: restore `major-version-bump-message`, set `next-version` to
the real release number, recreate the tag on the commit that ships, raise the QA assertion, and
restore the `publish:` workflow in `build.yaml` -- the step that actually ships anything, and the
only brake that lives in the repository. Never raise the assertion on its own to make a build pass.
The authoritative, ordered version of that list, with the cache-clear and rebuild steps spelled out,
is check 4.2 in
`docs/live-verification/chore-version-cap-and-changelog-budget-checklist.md`; keep the two in step.

### Lifted to 1.0.0

Philip's decision, 2026-09-13 (issue #62): the first public release is `1.0.0`. Both levers moved
in one commit. `GitVersion.yml` now has `next-version: 1.0.0` and a live
`major-version-bump-message` of `'\+semver:\s?(breaking|major)'`; `tests/QA/module.tests.ps1` now
requires the built version to be at or above `1.0.0` and below `2.0.0`.

**The original major pattern was not restored in full, and that is measured, not reasoned.**
GitVersion 5.12.0 against this repository with `next-version: 1.0.0`:

| `major-version-bump-message`, `ignore` | Computed |
|---|---|
| `'(?!)'` (the cap's pattern) | `1.0.0` |
| original `'(\+semver:\s?(breaking\|major))\|(^[a-z]+(\(.+\))?!:)'` | `2.0.0` |
| original, with `5816e87` and `715fb6d` under `ignore: sha` | `2.0.0` |
| original, with `ignore: commits-before: 2026-08-26T00:00:00` | `2.0.0` |
| `'\+semver:\s?(breaking\|major)'` alone | `1.0.0` |

Cause 2 above never left the history: with no version tag every reachable commit is in the
increment window, and both `!:` commits are reachable. Throwaway repositories on `main` then pinned
what the new lever does, and what the original pattern does in a repository seeded without this
history (one commit, `v1.0.0` on HEAD):

| Case | Computed |
|---|---|
| new lever, no message | `1.0.0` |
| new lever, `+semver: fix` | `1.0.1` |
| new lever, `+semver: minor` | `1.1.0` |
| new lever, `+semver: major` | `2.0.0` |
| new lever, a `fix(x)!:` subject | `1.0.0` |
| original pattern, seeded, `v1.0.0` on HEAD | `1.0.0` |
| original pattern, seeded, then a `feat!:` commit | `2.0.0` |
| original pattern, seeded, then a `fix:` commit | `1.0.1` |

So the original pattern is safe to restore in a repository seeded without this history, and only
there.

**Why the 0.x detail was archived as `[0.10.0]`, not `[1.0.0]`.** `Update-Changelog` never checks
for an existing heading, and Sampler's `Create_changelog_release_output` selects every released
section whose version equals the build's (its `Where-Object { $_.Version -eq $ModuleVersion }`
filter; no line number, for the reason given in [#changelog-budget](#changelog-budget)). Measured with
ChangelogManagement 3.1.0: with an archived `## [1.0.0]` and an exact `1.0.0` build, the output
changelog carries two `## [1.0.0]` headings, two sections match, and `ReleaseNotes` becomes an
`Object[]` holding the summary and the archived detail together. A prerelease build does not
collide, so only the real release build would have been wrong. `[0.10.0]` is the unspent version
the detail was accumulated under, and it keeps the invariant stated above: `next-version` is above
the newest dated heading.

**What check 4.2 of the version-cap checklist still lists.** Step 1 is done in part (the `+semver`
half only), and steps 2 and 4 are done. Step 3, the tag, belongs on the commit that actually ships.
Step 5 was recorded here as "not done and not planned", on the grounds that `1.0.0` was published by
hand and `build.yaml` defined no `publish` workflow. That is now history on both counts: publishing
is automated, and it lives in the workflow rather than in `build.yaml`. See
[#publish-on-merge](#publish-on-merge).

---

## publish-on-merge

Decision 4 (Philip, 2026-09-18): from `1.1.0` onward, every merge to `main` publishes a preview to
the PowerShell Gallery, and a full release is cut by pushing a `v` tag. The hand publication of
`1.0.0` was a one-off, not the model. This anchor records how that is built and what was measured
while building it.

**The publish is a job in `.github/workflows/build-and-test.yml`, not a Sampler task.** The
alternative -- restoring `Publish_Release_To_GitHub` and `publish_module_to_gallery` in
`build.yaml`, which that file's own comment used to prescribe -- was rejected on four measured
grounds. Every one of them is a failure that reports success:

1. **Both tasks skip silently.** They are declared `-if ($GitHubToken -and ...)`
   (`New-Release.GitHub.build.ps1:61`) and `-if ($GalleryApiToken -and ...)`. A missing token
   publishes the package with no tag, or publishes nothing at all, and the build is green either
   way. The workflow's publish job instead FAILS on an empty `GALLERYAPITOKEN`, and says why.
2. **`publish_module_to_gallery` writes "Package Published to PSGallery." even when `$SkipPublish`
   is set.** Its log is therefore not evidence. The workflow asks the Gallery instead, with
   `Find-PSResource` on the exact version, and goes red if it cannot see it.
3. **`publish_module_to_gallery` rewrites the built manifest as it publishes**, so the published
   bytes are not provably the tested bytes.
4. **A publish job running `./build.ps1 -ResolveDependency` resolves `latest` again.** Every entry
   in `RequiredModules.psd1` is `latest` by decision ([#dependencies](#dependencies)), so
   re-resolving at publish time can ship a build made against dependencies no test run ever saw.

Guarding those tasks with `build.yaml` keys would not have helped either: Sampler's publish task
reads its settings through InvokeBuild's `property` function, which never consults `build.yaml`, so
`SkipPublish:` and its neighbours are inert there. That reasoning predates this decision and is
kept in `build.yaml`'s comment, where anyone reaching for those keys will actually read it.

`./build.ps1 -Tasks publish` stays undefined, so there is no local publishing path at all. A
publish happens on a runner, from a verified artefact, or it does not happen.

### The tag after each publish is the mechanism, not bookkeeping

`GitVersion.yml` runs `mode: ContinuousDelivery`, and in that mode the preview counter does NOT
advance per commit -- it advances when a tag gives the next build a new base. Two merges in a row
with no tag between them therefore compute the SAME version, and the second publish is refused by
the Gallery.

Measured on 2026-09-22 with GitVersion 5.12.0 -- the release CI pins -- in a throwaway clone of
this repository, starting from `main` at `838c55f` with `v1.0.0` reachable:

| Step | `NuGetVersionV2` |
|---|---|
| `main` tip as it stands | `1.0.1-preview0001` |
| after tagging `v1.0.1-preview0001` ON that tip | `1.0.1-preview0001` (the tag is returned verbatim) |
| one further commit | `1.0.1-preview0002` |
| a SECOND further commit, no new tag | `1.0.1-preview0002` **again** |
| tag `v1.0.1-preview0002`, then one commit | `1.0.1-preview0003` |
| tag `v1.1.0` sitting on the tip | `1.1.0` |
| one commit after `v1.1.0` | `1.1.1-preview0001` |

Row four is the whole reason the publish job creates a tag. Sampler and DSC Community do the same
thing for the same reason.

**If the publish succeeds and no tag follows it**, the next merge to `main` computes the same
version and the publish job's idempotence check finds it already on the Gallery and skips. Until
2026-10-09 this section said the line then stalled until someone pushed the missing tag by hand.
It did not: the tag step went on to create the tag and the release on that merge's OWN commit,
over the package built from the previous one. What the tag step does about that now is the next
section.

### The tag step tags only the build that was published

Decision A16 (Philip, 2026-10-09, BL-114): the tag step never creates a tag or a release on a
commit whose build is not the published package, and when it cannot show that it is, it refuses
with a red run and the repair in its message.

**The defect, as it stood in the code at `34c69a4`.** The publish step skipped the upload when
`Find-PSResource` already found the exact version, and the tag step then ran
`gh release create v<version> --target $env:GITHUB_SHA`. A publish that no tag followed -- the tag
step failed, or the publish step failed although its upload had arrived -- left GitVersion's base
where it was, so the next merge computed the same version, skipped the publish and tagged its own
commit. The tag and the GitHub release then named a commit whose build was never published under
that version, the Gallery's release notes and the GitHub release could disagree, and that merge's
changes reached no package until a later merge published one.

**It was one merge away on 2026-10-08.** The publish of `2226538` (run 37818385476) was answered
with a 500 by the Gallery although the package arrived, and the tag step was skipped. The
architect re-ran the failed job in the same run, which found the version, skipped the publish and
tagged the right commit. Had the next merge come first, `0fc48ac` would have been tagged
`v1.1.4-preview0003` over the package built from `2226538`.

**The mechanism: the package is read back and compared with the tested artefact.** On every run
but a `v` tag run, the tag step first runs `PublishArtefact.ps1 -Compare`. It verifies the
downloaded artefact exactly as `-Verify` does, saves the package the Gallery serves under the
recorded version with `Save-PSResource` (exact version, `-Prerelease`, `-TrustRepository`,
`-SkipDependencyCheck`) into an empty directory, and compares the two version folders file by file
and SHA-256 by SHA-256, in both directions, through the same `Compare-FileHashSet` that `-Verify`
uses. Same build: the step goes on as before. A package that differs: it throws, naming what
differs and the repair. (An artefact that fails the `-Verify` half throws `-Verify`'s own
message.) A read that fails, or saves nothing: it throws as well, and says a re-run of the job
reads again. The script stays the single owner of the proof, as `-Record` and `-Verify` are.

Measured on 2026-10-09: publishing a build into a local repository with `Publish-PSResource` and
saving it back with `Save-PSResource` gave exactly the four files `-Record` records, every SHA-256
equal, with PSResourceGet 1.0.1 and 1.2.0 -- no nuspec, no `_rels`, no `[Content_Types].xml`. A
module installed from the Gallery on the maintainer's machine holds only its own files plus the
`PSGetModuleInfo.xml` the installer writes, which `Save-PSResource` does not write without
`-IncludeXml`. So the whole version folder is compared with no exemption list, and since the
manifest is one of the files, a package of another version cannot match either.

**What was not chosen, and why.**

- **`GITHUB_RUN_ATTEMPT`.** A re-run of the failed job raises it, and so does the re-run of
  only the failed jobs after a refusal, which must not tag. It cannot tell the two apart.
- **Trusting this job's own upload.** "This job published it" is true only in the attempt
  that uploaded; the 2026-10-08 shape is a re-run that did not upload and must still tag. It
  would also leave the comparison running only during an incident, so a flaw in it would show
  up exactly when it is needed. Comparing on every run means every merge exercises it.
- **Tagging before publishing.** It would put a tag on a commit before anything is published
  under it, which is the opposite of the decision.

**The comparison runs before the release lookup.** A release that already exists for the tag
would otherwise make a refused run go green with nothing published -- for example after the tag
and a release were made by hand on the publishing commit and the refused run's failed jobs were
re-run.

**The tag must not already name another commit.** `gh release create` ignores `--target` when the
tag already exists, and attaches the release to the tag where it stands. The repair below asks for
preview tags pushed by hand, so a tag on the wrong commit is a realistic input: without a check the
release would have landed on that commit while the log named `GITHUB_SHA`, and the release-exists
branch would even have turned the run green. So after `-Compare` the step asks
`git/matching-refs/tags/<tag>` -- a PREFIX match, so the answer is filtered to the exact ref; an
annotated tag names a tag object, which is peeled once to the commit it names -- and refuses when
the tag names another commit, or when the lookup itself fails or answers nothing (an empty answer
refuses like a failed one, since an answer that says nothing is not evidence the tag is absent).
The message names `git push origin :refs/tags/<tag>` and a re-run. A tag that names `GITHUB_SHA`
goes on as before. A tag set by that commit's own run, whose build is the same package, needs no
repair: the message says so, and that run may stay red. When the run's build is not the package,
the comparison refuses first, and its repair text names a tag in the way as well.

**The shapes, offline.** `tests/Workflow/PublishJob.Tests.ps1` runs the publish job's own step
text in `pwsh`, wrapped the way `shell: pwsh` wraps it, against a fake Gallery and a fake GitHub:

| Shape | Before (at `34c69a4`) | Now |
|---|---|---|
| An ordinary merge | publishes and tags its commit | publishes, compares, tags its commit |
| Re-run of the failed job in the same run, after a 500 whose upload arrived | skips the publish, tags its commit | skips the publish, matches, tags its commit |
| The next merge, after a tag step that failed or a 500 nobody re-ran | skips the publish and tags ITS OWN commit over the previous commit's package | refused when its build differs, nothing tagged, the repair in the message |
| The next merge, byte-identical build | skips the publish, tags that commit too | tags its commit (its build IS the package) |
| Re-run of only the failed jobs after that | (the tag was already wrong) | refused again, also after the repair tag, also with a release made by hand |
| Repair tag on the publishing commit, then all jobs re-run | -- | counts up, publishes and tags the refused commit |
| Re-run after a preview tag was pushed by hand onto another commit | attached the release to that commit | refused, nothing created, the repair in the message |
| A rebuild of the published commit on a later day | tagged the right commit with another build's package | refused; the tag by hand on that commit is the whole repair |
| A read of the Gallery that fails | (no read) | refused, then tags on a re-run that can read |
| A `v` tag run | attaches the release to the existing tag | unchanged: no comparison |

The guard is mutation-proven: with the `-Compare` call removed from the tag step, the refusal
shapes tag the wrong commit and the suite goes red. `OER_WORKFLOW_ROOT` points the suite at a
directory that holds a mutated copy of `.github/` for such a run; it is never set in CI.

**Repair.** For a refused run: push the missing tag by hand onto the commit that published the
version (`git tag v<version> <commit>` and `git push origin v<version>`), then re-run ALL jobs of
the newest refused run (it carries the older ones' changes; an older one re-run after it is
refused against the newer package). Its rebuild counts up from that tag and publishes it as the
next preview. A preview tag carries a hyphen, so the `Stable Version` ruleset does not cover it.
The run that published can instead be repaired by re-running its own failed job, which matches and
tags.

**Known limits.**

- **A rebuild of the published commit is another build.** The built manifest's release notes
  carry the build date, so re-running ALL jobs of the run that published, on a later day,
  produces different bytes and is refused. Re-run only its failed jobs, which reuse the tested
  artefact; or, if all were re-run already, the tag by hand on that commit is the whole repair.
- **A later merge whose build is byte-identical is tagged.** A merge that changes nothing under
  `source/` or in `CHANGELOG.md`, built the same day, normally produces the published bytes exactly
  (the build resolves its tools and dependencies afresh, so a change there makes it another build,
  which is refused), so its commit is tagged. That is what A16 asks: its build IS the package.
- **The read is a single attempt.** The Confirm step polls until the version is indexed, but a
  transient failure of the read itself refuses, and a re-run of the job reads again. Left without
  a retry on purpose, so a refusal is never delayed into a timeout.
- **The count-up after the repair tag is GitVersion's measured behaviour** (the measured table
  under "The tag after each publish is the mechanism, not bookkeeping"), not something the offline
  suite runs: the suite plays the rebuilt artefact.

### The published version comes from the MANIFEST, not from GitVersion

`Publish-PSResource` publishes the version the manifest carries, and that string is not always
`NuGetVersionV2`. A PowerShell prerelease label must be alphanumeric, so Sampler keeps only the
first hyphen-delimited segment of it. Measured on 2026-09-22: on a branch named
`ci/publish-on-merge`, GitVersion computed `1.0.1-ci-publish-on-me0001` while the manifest was
stamped `1.0.1` with prerelease `ci`. On `main` and on a `v` tag the two agree exactly --
`1.0.1-preview0001` stamps `1.0.1` plus `preview0001`, and `1.1.0` stamps `1.1.0` with no label.

So the publish, the Gallery confirmation and the tag all take their version from the built
manifest, and the only cross-check asserted against GitVersion is the one that holds on every
branch: the manifest's `ModuleVersion` is the numeric part of `NuGetVersionV2`. Note also that the
version FOLDER is `MajorMinorPatch` alone (`output/module/Omnicit.EntraRBAC/1.0.1`), never the
prerelease-bearing string.

### Provenance: the published bytes are the tested bytes

`.github/scripts/PublishArtefact.ps1` owns both halves of that proof in one file, and the tag
step's comparison with the Gallery (`-Compare`) as well, so a recorder and a verifier cannot drift
apart -- two that enumerated or hashed differently would fail on honest artefacts and agree on
tampered ones.

`-Record` runs on the `ubuntu-latest` leg after its Test step, and only on success. It writes
`publish-meta.json`: the commit, the GitVersion value, the manifest's version and prerelease, and a
SHA-256 for every file in the version folder. `-Verify` runs in the `package` job and AGAIN in the
`publish` job, each downloading the artefact separately, and refuses to continue on a wrong commit,
on a changed, added or removed file, or on a manifest that is not the recorded one. Both directions
are compared: checking only the recorded files would pass an artefact that gained one, and checking
only the files on disk would pass one that lost a recorded file.

One leg records, not three, because three artefacts would make the publish choose between them, and
choosing is not proving.

### Two measured facts about Publish-PSResource

Both would have cost a red run to find, and both are pinned by comments at their call sites.

**`-Path` must be the VERSION FOLDER.** Pointing it at the module folder's root fails with "No file
with a .psd1 extension was found" -- first measured in P6, reproduced on 2026-09-22.

**The declared `RequiredModules` must be resolvable on `PSModulePath` before publishing**, because
`Publish-PSResource` validates the manifest with `Test-ModuleManifest`. On a clean runner neither
`AzAuth` nor `Microsoft.Graph.Authentication` is present, and the publish fails with "The specified
RequiredModules entry 'AzAuth' ... is invalid" -- a manifest error, giving no hint that the repair
is an install. `-SkipDependenciesCheck` does NOT cover this: it waives only the separate check that
the dependencies exist in the DESTINATION repository. Both jobs therefore install the two modules
before publishing. The `package` job additionally needs `-SkipDependenciesCheck`, since its
destination is an empty folder under `RUNNER_TEMP`; the real publish does not skip it, since both
dependencies genuinely are on the Gallery and the check is worth running there.

### Why `package` exists at all

It runs on every pull request and every push, it has no environment and no secrets, and it can
publish nothing: its repository is a folder under `RUNNER_TEMP`. It rehearses the real publish --
the same `Publish-PSResource` call against the same version folder -- and then proves the package
it produced can be found, installed and imported by a consumer in a clean `pwsh` process, asserting
that the exported command count matches the manifest's `FunctionsToExport`. The point is that the
evidence arrives on the pull request, BEFORE anything permanent happens: a version cannot be
withdrawn from the Gallery, only unlisted.

### Triggers

`tags: ['v*', '!v*-*']` was added to the push trigger so a full release can be cut by pushing
`v<X.Y.Z>`. The exclusion keeps the preview tags the workflow creates from starting runs of their
own; a tag pushed with `GITHUB_TOKEN` does not trigger a workflow in the first place, so the
exclusion is the second lock on that door rather than the only one.

`paths-ignore` must never be added to the `pull_request` trigger. `ubuntu-latest`,
`windows-latest`, `macos-latest` and `package` are required checks on `main` (measured 2026-10-08),
and a run that never happens never reports them -- a required check that never reports stays
Pending forever. That is the same failure mode the matrix protects against, described in CLAUDE.md
under Module Layout.

### No deployment approval: the gate is in the settings

Decision (Philip, 2026-09-23): publishing asks for no approval. The model is unchanged -- a merge to
`main` publishes a preview, a `v<X.Y.Z>` tag publishes the full release -- but the gate moved from a
click on the deployment to repository settings that were already in place when the click was
removed:

- **The `Entra RBAC` environment has no required reviewers.** Its deployment rules admit branch
  `main` and four tag patterns, matched with Ruby's `File.fnmatch`: `v[0-9].[0-9].[0-9]`,
  `v[0-9].[0-9].[0-9][0-9]`, `v[0-9].[0-9][0-9].[0-9]` and `v[0-9].[0-9][0-9].[0-9][0-9]`. The
  earlier `v*` pattern was removed, so no tag carrying a hyphen reaches the Gallery key. A version
  outside the patterns -- a major of 10 or more, or a minor or patch of 100 or more -- is refused at
  deployment, visibly, and the repair is to add a pattern.
- **The tag ruleset `Stable Version`** includes `v*`, excludes `v*-*`, restricts creation, update
  and deletion, and blocks force pushes. Its bypass list, as measured on 2026-10-08, is the
  Repository admin role (the owner account, Omnicit) and the user PhilipHaglund. Only they can
  create, move or delete a stable tag; everyone else is refused, the workflow's own `GITHUB_TOKEN`
  included.

The two are built to fit: every tag the environment admits is a tag the ruleset protects, since
each pattern starts with `v` and none admits a hyphen. A pattern added later must keep that
property. One that admits a tag the ruleset does not cover reopens exactly the hole described next.

**The threat these settings close.** With no approval, and without them, anyone with push access
could point a `v*` tag at an unreviewed commit whose workflow had been changed, and reach the
secret -- past the pull request and past CI alike.

**Why the closure cannot live in the workflow.** A tag push runs the workflow file AT the tagged
commit. A check written into that file -- a condition on the `publish` job, a step comparing the
tag against `main`, anything -- is therefore authored by whoever authors the commit, and the commit
that abuses the secret simply writes the check away. The environment's deployment rules and the
tag ruleset are evaluated by GitHub against the ref, outside anything a commit can change. The
`publish` job's `if:` and the trigger's `!v*-*` exclusion stay, but they keep honest runs honest;
they are not the control. The same holds for the version guard described
[below](#the-publish-job-refuses-a-version-its-ref-does-not-call-for).

**What that asks of the workflow.** Since the ruleset refuses `GITHUB_TOKEN` a stable tag, the
release step must never create, move or delete one: a stable run that tried would fail in its last
step, after the Gallery publish. Verified on 2026-09-23 before this decision was written down:

- No step runs `git tag` or `git push`. The only tag the workflow writes is the one
  `gh release create` makes when the named tag does not exist yet, and on a `main` run that tag is
  a hyphenated preview tag, outside the ruleset. The first publish logged exactly that:
  `Created the release v1.0.1-preview0001 on 2c7c7d78e3d6...`.
- On a `v` tag run the tag already exists, since it is what started the run. `gh release create`
  creates a matching tag only "if a matching git tag does not yet exist" (its own help text), and
  the REST API it calls documents `target_commitish` as "Unused if the Git tag already exists".
  `--target` is `GITHUB_SHA`, the tagged commit, in any case. The stable path therefore attaches a
  release to the existing tag and writes no ref.

**Measured on 2026-09-23: what GitVersion computes on a stable tag.** The case that matters is a
`v` tag on a commit that ALSO carries a preview tag, which is the normal case, since every merge
tags its own commit. The release step names its tag from the computed version, so a computed version
that differed from the pushed tag would make it try to create a different tag -- refused by the
ruleset, after the Gallery publish. Measured with GitVersion 5.12.0 in a fresh CI-like clone
(`git init`, a fetch of `refs/heads/*` into `refs/remotes/origin/*` and of every tag, a detached
checkout, `GITHUB_ACTIONS` and `GITHUB_REF` set) against a bare copy of the public repository:

| State | `NuGetVersionV2` |
|---|---|
| `main` after the merge of #5, untagged | `1.0.1-preview0002` (confirmed live after that merge) |
| `v1.0.1` on a commit that also carries `v1.0.1-preview0002` | `1.0.1` |
| `v1.1.0` on that same commit | `1.1.0` |
| the next `main` commit after `v1.0.1` | `1.0.2-preview0001` |
| the next `main` commit after `v1.1.0` | `1.1.1-preview0001` |

The stable tag wins over the preview tag on the same commit, the computed version IS the tag, and
the release step therefore names the tag that already exists. After it, the preview line carries on
one patch above the stable version.

**Measure that in a fresh clone, never in a working copy.** With `GITHUB_ACTIONS` set, GitVersion's
normalization creates a local branch named `tags/<tag>` and moves local branches to their remote
counterparts. On a runner that is harmless, since the clone is thrown away, but in an ordinary
working copy it changes the very branches being measured, so the answer it gives there is wrong.

**Accepted residual.** Whoever can merge a pull request can publish a preview, since the merge is
the publish and nobody else is asked. That holds until `Require approvals` is switched on for
`main` with a second reviewer to give it.

### The publish job refuses a version its ref does not call for

The step `Refuse a version the triggering ref does not call for` runs in the `publish` job straight
after the artefact is verified, before anything else, and it never sees `GALLERYAPITOKEN`. It reads
`PublishVersion` and `PublishPrerelease` -- the version the built manifest carries, as the
verification step exports it -- and requires:

- **On `refs/tags/v*`:** that `v` plus `PublishVersion` equals the tag name exactly, case included,
  and then that the tagged commit is in `main`'s history. The checkout is `fetch-depth: 1`, so git
  cannot answer the second question; the step asks the compare API for `main...<commit>`, where
  `identical` or `behind` means `main` contains the commit and `ahead` or `diverged` means it does
  not. Any other answer, or a failed call, is a refusal as well.
- **On `refs/heads/main`:** that `PublishPrerelease` is not empty.
- **On any other ref:** a refusal. The job's `if:` already admits no other ref, so this is a second
  lock -- one that keeps holding if that condition is ever edited.

Every refusal says what was expected, what was found, and that NOTHING has been published. On a tag
it also says that the tag is still there, and that someone on the `Stable Version` bypass list
removes it with `git push origin :refs/tags/<tag>`. The workflow itself never deletes a stable tag,
and the ruleset would refuse it if it tried.

It catches three mistakes, each of which would otherwise put a permanent, unintended version on the
Gallery before anything stopped it:

1. **A tag run on which GitVersion computes something other than the tag.** The publish would go
   through under the computed version, and only the release step would then fail, against the
   ruleset, with the version already on the Gallery. The measurement above says an honest tag
   computes itself, so this is the net under that measurement, not a correction of it.
2. **A stable tag on a commit that is not on `main`** -- created in a checkout that sits on a
   feature branch, say. The ruleset decides WHO may push a stable tag, not WHERE it may point, so
   this would publish unreviewed code as a full release.
3. **A `main` run that computes a stable version**, after a change to `GitVersion.yml` for example.
   The decision is that a full release comes from a tag and from nothing else.

Run locally on 2026-09-23 against the step's own text, extracted from the workflow and wrapped the
way `shell: pwsh` wraps it: the two honest cases pass, and a wrong version, a prerelease build on a
stable tag, a commit off `main`, a stable version on `main` and a foreign ref are all refused.
Against the public repository the compare API answered `behind` for `2c7c7d7` (on `main`),
`identical` for the `main` tip, and `diverged` for the head commit of a pull request branch that had
been squash-merged.

**This does not contradict the section above, which says a check in the workflow cannot be the
control.** It still is not. The gate against an ADVERSARY stays in the environment's deployment rules
and the tag ruleset, because a tag push runs the workflow file at the tagged commit, and a commit
written to do harm simply deletes this step. A MISTAKE deletes nothing: whoever tags the wrong
commit, or merges a `GitVersion.yml` that computes the wrong thing, is running the workflow as it
stands, guard included. The settings decide who may publish; this step stops an honest publish that
asked for the wrong thing.

### The release-note floor after a stable release

This was recorded here as an open question until P14. Decision (Philip, 2026-09-23, option 1 of
four): `tests/QA/module.tests.ps1` holds `[Unreleased]` to "not empty" -- a body of at least 50
characters, about one sentence -- instead of a 500-character floor. The 4,000-character ceiling is
unchanged.

The 500-character floor failed two kinds of pull request that were not wrong:

1. **The close-out after a stable tag.** It moves `[Unreleased]` under `## [X.Y.Z] - <date>` and
   has to leave a new `[Unreleased]` behind, which has nothing true to say yet.
2. **Any release whose honest note is shorter than 500 characters** -- a patch carrying one small
   fix, say. The pull request that made the fix failed.

The only way past was padding, and publishing on merge is what made padding unacceptable rather
than merely untidy: every merge publishes a preview with `[Unreleased]` as its `ReleaseNotes`, so
the padding would have reached the Gallery, which can unlist a version but never delete one. The
floor's legitimate job was always a MECHANICAL one -- an emptied or hand-converted section publishes
`ReleaseNotes` of length 0 while the build reports success (measured 2026-09-17) -- and the quality
of a note is decided in review. 500 characters of filler passed the floor anyway.

The close-out got a fixed sentence rather than free text, so that a gate can hold it (CLAUDE.md,
"CHANGELOG and Version"):

```text
No changes to the module since X.Y.Z. A preview published from this point differs from X.Y.Z only in documentation, tests or the build.
```

The close-out is the FIRST merge after the tag: a merge landing between the tag and the close-out
publishes a preview whose notes describe the previous release's changes as new. The first change
under `source/` after the close-out then REPLACES the sentence, since its opening claim stops being
true the moment the module changes; a note added after the sentence would publish both. The gate
side of all this -- the body floor, the two close-out checks, and why the built notes are now
compared whole instead of by a 400-character tail -- is under [#changelog-budget](#changelog-budget).

## directory-role-assignments

Sprint 6 step 4 added six cmdlets -- `New-`, `Get-` and `Remove-OEREligibleDirectoryRoleAssignment`,
and the same three for active assignments -- and the apply section `directoryRoleAssignments[]`.
This anchor records why the harder decisions sit where they do.

**Role name matching is case-insensitive, but the exact-case path stays a single request.**
`Resolve-OERDirectoryRoleDefinitionId` issues an exact-case `displayName eq '...'` OData filter
first. Step 3's live check 1.2b measured Microsoft Graph's `roleDefinitions` filter as
case-SENSITIVE: a role named `Reports Reader` in the tenant returned nothing for a filter typed
`reports reader`. Only when the exact-case request finds nothing does the whole role definition list
get paged (`-All`) and matched `OrdinalIgnoreCase`; a unique case-insensitive match returns its id,
more than one throws `AmbiguousName` listing every candidate id, and no match returns `$null`. A
name typed in its exact case still costs one request and never reaches the paged list at all, so the
common case (a name typed as the portal shows it) pays nothing extra for this; only a name typed in
another letter case pays for the second, paged request. Cost if a tenant carried two role
definitions differing only in case: a name typed in the exact case of one of them would silently pick
that one, without ever reaching the case-insensitive step that would otherwise refuse the ambiguity.

**Both kinds of assignment are read from their SCHEDULE, never an activation instance.**
`Get-OEREligibleDirectoryRoleAssignment` reads `roleEligibilitySchedules` and
`Get-OERActiveDirectoryRoleAssignment` reads `roleAssignmentSchedules` -- the objects that carry the
window of the request that created them, which is what idempotence
(`Resolve-OERDirectoryRoleAssignmentChange`) compares the declared window against. Three fields
decide whether a schedule can stand for a declared entry, and the private
`Select-OERManagedDirectoryRoleAssignment` is the single place all three are read: `directoryScopeId`
must be `/` (tenant scope -- an administrative-unit-scoped one belongs to
`administrativeUnits[].scopedRoles`, not here); `memberType` must be `Direct` (one a principal holds
through a group is managed through that group, never here); and for an Active read,
`assignmentType` must be `Assigned` -- an `Activated` schedule is the activation of an eligible
assignment, created by the principal and ended by PIM, and is never a declared Active assignment,
never counted as one, and never pruned. The Get cmdlets themselves still return every row at `/`,
activations included, so an operator asking to see them still can; only the apply engine's filter
narrows. Reading schedules rather than instances also picks the safer failure direction: an
assignment whose schedule a read somehow missed would be silently re-created every run (visible as
`Created` every run, never a silent delete), not silently removed.

**A group must be role-assignable before either New cmdlet ever writes.** `isAssignableToRole` can
only be set when a group is created, and Microsoft Graph only reports the mismatch after the
eligibility or active-assignment request is submitted. The role-assignable check therefore runs
first, as its own private read-only helper (so the required-scope gate attributes it as a read, not
a write), whenever the resolved principal is a group or of unknown type -- a raw `-PrincipalId`
might name a group, so the check has to run for it too. `isAssignableToRole` false is
`GroupNotRoleAssignable` before any write; a read that fails for any other reason is written to
Verbose and the request proceeds, letting Microsoft Graph enforce it as before this check existed.

**A permanent request is pre-checked against the role's own PIM policy, and a refusal changes
nothing.** Unlike the ARM eligible-role-assignment cmdlet, which auto-opens the equivalent Azure
policy when a permanent request would otherwise be refused, the Graph directory-role path never
changes a policy implicitly. `Test-OERDirectoryRolePermanentAllowed` reads
`AllowPermanentEligibility`/`AllowPermanentActiveAssignment` from the role's policy
(`Get-OERDirectoryRolePolicyAssignment` plus the shared `ConvertTo-OERRoleManagementPolicy`) before
`ShouldProcess`, the same place the ARM pre-check runs. `$false` is `PermanentAssignmentNotAllowed`
and no request is submitted at all; the message points at `-AllowPermanentEligibility` /
`-AllowPermanentActiveAssignment` on `Set-OERDirectoryRoleManagementPolicy`, and at declaring
`allowPermanentEligibility` / `allowPermanentActiveAssignment` under `directoryRoleManagementPolicies`
in the same document (that section runs first in the apply order). An unreadable answer -- no policy
assignment found, or the policy carries no expiration rule for that kind -- is not a refusal: it is
written to Verbose and the request proceeds, letting Microsoft Graph enforce the policy as it always
did.

**The prune pass is keyed on RESOLVED role ids, runs once per section, and withholds before it
removes anything.** Like `roleAssignments`, the pass runs in the handler invocation for the FIRST
item of its group -- here the section's first item, there the first item of each resolved scope --
but here it runs BEFORE that item's own reconcile, where the `roleAssignments` pass follows it. And
unlike `roleAssignments`, it runs whatever that first item's own outcome, since a role or principal
that fails to resolve for item one says nothing about whether item two's pair should be pruned. It is
keyed on resolved role definition ids, not on the text the document wrote, so one role written by
display name in one entry and by id in another is one pair, and neither entry's live assignment is
ever reported `Extra`. `roleAssignments` is keyed on resolved ids too: the scope the engine resolved
and the role definition's GUID (see [#role-assignment-key](#role-assignment-key)). Only
the `(role, assignmentType)` pairs the document actually declares are read -- a role the document
does not name is never touched, and a role declared only for `Eligible` never has its `Active`
assignments read, nor the reverse. `ConvertTo-OERPruneWithheldResult` is called FIRST for every
undeclared candidate: an entry whose PRINCIPAL cannot be resolved withholds only its own pair, since
only that one candidate might be its live counterpart; an entry whose ROLE cannot be resolved
withholds every pair of its declared `assignmentType`, since without a role id there is no way to
know which pair it belongs to. A pair whose live READ fails is its own `Failed` row, and nothing in
that pair is removed or reported `Extra` -- a failed read is not proof the pair is empty, and
treating it as one would let a transient Graph failure silently strip privilege the document still
declares.

**The signed-in identity's object id comes from the token, never `/me`.** `Initialize-OERAuth`
stores `SignedInObjectId` in `$script:_OERAuthState` whenever it builds a new state from a fresh
Graph token, read by the private `Get-OERTokenObjectId` from the token's `oid` claim -- present on a
delegated user's token and an app-only service principal's token alike, so the same read serves both
without a conditional `/me` call an app-only sign-in does not have. `Get-OERSignedInObjectId` is the
only reader, and treats a missing key (a state built before this key existed) or a non-GUID value the
same as unresolved. When it cannot be determined, EVERY prune candidate in the section is withheld,
not only the ones that might turn out to be the caller's own: the alternative -- pruning everything
except a candidate that happens to match no known id -- would prune the operator's own assignment on
exactly the session that carries no `oid` claim at all. `Get-OERTokenObjectId` takes the token as a
`[securestring]`, the same one `Initialize-OERAuth` hands to `Connect-MgGraph`, and never as a
`[string]`: PowerShell module logging (Event 4103, `LogPipelineExecutionDetails` or the "Turn on
Module Logging" policy) records every bound parameter value, so a string parameter would log the live
Graph token on every sign-in on such a machine. The plaintext exists only inside the helper, through
a .NET call that is not a parameter binding.

**A group the signed-in identity is a member of is never pruned, and an unreadable membership
withholds.** The own-assignment guard protects only the signed-in identity's DIRECT assignments --
the ones `Select-OERManagedDirectoryRoleAssignment` would otherwise let the prune pass consider. A
role-assignable group's own direct assignment is a candidate too, and removing it ends the role for
every member who holds it through the group, the operator included when the operator is one of
them. The first version of this anchor accepted that and recorded it as a known gap, on the grounds
that closing it needed group-membership expansion the guard did not do; the review of PR #12
reversed that, since the gap is exactly the self-lockout the own-assignment guard exists to prevent.
A second guard now runs right after the own-assignment one. For a candidate whose `PrincipalType` is
neither `User` nor `ServicePrincipal` -- a `Group`, or a type the converter did not recognize, which
might be one -- the pass reads the signed-in identity's transitive group memberships through the
private `Get-OERMemberGroupId`, one `POST v1.0/directoryObjects/{oid}/getMemberGroups` with
`securityEnabledOnly` false (a role-assignable group is always security-enabled, so `true` would
return it as well; `false` is kept because it can only return more groups, never miss one),
and a candidate whose id is in that set is reported `Skipped`, with or without `-Prune`. That call
names the object by the token's `oid`, so the same request serves a delegated user and an app-only
service principal: `/me` does not exist app-only, and `/users/{id}` or `/servicePrincipals/{id}`
would need the object's type first. Microsoft Learn (directoryObject: getMemberGroups, "Group
memberships for a directory object") asks for `Directory.Read.All`, which `Invoke-OERStructure`
already requires outright, so the consent list does not grow. The read is lazy and happens at most
once per pass: a run whose candidates are all users or service principals never makes it, and the
answer -- or the failure -- stands for every later candidate in every pair, so a large section does
not pay one request per group. A read that fails is written once, and every `Group` or
unknown-type candidate in the pass is withheld (`Skipped`, "prune withheld: the signed-in identity's
group memberships could not be read"): a failed read is not an empty membership, and treating it as
one would remove exactly the assignment this guard exists to keep. User and service principal
candidates carry on to the prune, since neither can be such a group. Cost if the permission assumed
here is wrong for some tenant: withheld `Skipped` rows on every group candidate, never a wrong
removal. The group guard reads ACTIVE group memberships only (`getMemberGroups`). An identity that
is only eligible for membership through PIM for Groups is not a member until it activates, so a
group it could activate into is an ordinary prune candidate -- decide knowingly before running
`-Prune` in a tenant that uses PIM for Groups on role-assignable groups.

**Testing note: a mocked throw is not gone once the code under test catches it.** Several of the new
suites assert against `-ErrorVariable` around a call whose OWN internal try/catch is expected to
swallow a mocked failure and report it a different way (a `Failed` structure result, or a re-thrown
`ErrorRecord` carrying the cmdlet's own error id). Pester still leaves the mock's thrown record in
the caller's `-ErrorVariable` -- measured, several copies, one per mock call boundary the pipeline
crosses -- even when the code under test caught it and never let it reach the caller as an unhandled
error. An assertion that only checks `-ErrorVariable` is non-empty, or matches the bare mocked
message, therefore passes whether or not the code under test's own catch block ran at all. The new
suites instead count only the records whose `FullyQualifiedErrorId` ends `,<CmdletName>` -- the
qualifier PowerShell attaches to an error the NAMED cmdlet itself writes, which the mock's own inner
record never carries -- for example
`@($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OEREligibleDirectoryRoleAssignment' }).Count | Should -Be 1`.
This is the same family of trap `#bearer-scrub-tests` already documents for a re-thrown record; it
recurs here because every one of the six new cmdlets, and the new
`Sync-OERStructureDirectoryRoleAssignment` handler, catches Graph and lookup failures internally
before reporting its own outcome.

**A principal's assignments of a role cannot change for five minutes after its active assignment of
that role starts -- a Graph limit, measured live, and reported rather than worked around.** The step
4 live run (check 3.3) found Microsoft Graph refusing the engine's `adminUpdate` of an eligible window
with HTTP 400 `ActiveDurationTooShort: The Active duration is too short. Miniumum Required is 5
minutes.` The follow-up measured it on test objects. Every refusal came while the principal's ACTIVE
assignment of the role was younger than five minutes, and every success while it was older, or while
there was none:

- an eligible `adminUpdate` 2, 3 and 4.5 minutes after the active assignment started: refused, with
  `targetScheduleId` set to the eligibility schedule's id, without it, and without `startDateTime`;
- the same update 14 and 16 minutes after it started: accepted, with and without `targetScheduleId`,
  beside a time-bound active assignment and beside a permanent one -- so neither `targetScheduleId`
  nor a permanent active assignment is the lever;
- `adminRemove` of either kind, 3.7 minutes after the active assignment started: refused the same
  way; 8 minutes after: accepted;
- a principal with no active assignment of the role: every update accepted;
- `adminAssign` is never refused this way.

The write path is therefore unchanged: `targetScheduleId` is not sent, and the engine never answers a
refusal by removing an assignment and creating it again, since a failure between those two requests
would leave the principal with no eligibility at all -- the same class of harm as a prune that
deletes on a failed lookup. The handler recognizes the refusal by its error id or message, on an
update of either kind and on a prune removal, and reports the row Failed with the cause and the way
out: apply the document again in five minutes. It matters in one situation above all: a document
that creates a principal's active assignment and, within five minutes, changes or prunes another of
that principal's assignments of the same role -- as check 3.3 did two minutes after 3.1.

Two more Graph behaviours were measured on the way, both outside the module's control. When one
principal holds an eligible and a permanent active assignment of the same role, an `adminUpdate` of
either kind removed the other kind, with no request for it (an active update to permanent removed the
eligible assignment; an eligible update removed the permanent active one); the next run finds the
declared assignment absent and creates it, and `adminAssign` beside the other kind is accepted. And a
directory-role schedule `adminUpdate` replaces the schedule rather than updating it in place: the
schedule id changes (check 2.7), which is why the engine matches on role, principal and kind only.
A document that declares both kinds for one principal and role can therefore need two runs to
converge, and the help of the New cmdlets, the engine and the schema says so.

**A removal answered `RoleAssignmentDoesNotExist` is read back, and counts as done only when the read
proves the assignment gone.** The step 4 teardown removed four active assignments with
`Remove-OERActiveDirectoryRoleAssignment`, and all four answered `RoleAssignmentDoesNotExist: The Role
assignment does not exist.`, while Graph lists each `adminRemove` request as Revoked and the
assignments were gone. The prerequisite script's own raw removal of the certificate identity's active
assignment answered the same, as a 404. What the evidence shows:

- the wrapper logged ONE POST per call, and the prerequisite script, which calls the SDK directly
  without the wrapper, got the same answer -- so the wrapper's own retries are not the cause;
- Graph holds ONE `adminRemove` request per principal, and a refused request leaves none (the
  `ActiveDurationTooShort` refusals left no request either), so a rejected second send would leave no
  trace;
- the removals ran back to back, and the Revoked requests' creation times put each active removal at
  about 33 to 44 seconds against about one second for an eligible one -- each active request was
  created some half a minute after its call began, not at its start;
- the Microsoft Graph SDK below the wrapper (2.41.0, request context `MaxRetry` 3, `RetryDelay` 3)
  resends a request, a POST included, when it is answered 503 or 504, three seconds later, and hands
  back only the last answer; measured offline with its own retry handler over a stubbed transport,
  and not for 500 or 502.

A slow first answer that the SDK resends, whose second answer finds the assignment already removed,
fits all of that; so does Graph answering the one slow request with `RoleAssignmentDoesNotExist`
itself. Nothing in the module's streams can tell the two apart, since the SDK's intermediate answers
never reach them, so the transport is left as it is: changing the retry of every POST on an
unproven cause would trade a known behaviour for a guess. `Set-MgRequestContext -MaxRetry 0` in the
live session, before one active removal, would settle it: a 503 or 504 then surfaces instead of
`RoleAssignmentDoesNotExist`.

The fix holds whichever it is. On `RoleAssignmentDoesNotExist` the Remove cmdlet reads the
principal's schedules of the role again, at every scope (`Test-OERDirectoryRoleAssignmentGone`), and
only a read that succeeds and keeps no direct, tenant-scope schedule -- for Active an Assigned one,
through `Select-OERManagedDirectoryRoleAssignment` -- makes the removal a success, with a verbose line
and no request object. A read that fails, or finds the assignment still in place, leaves the original
error exactly as before: a failed read is never an absent assignment. The prune pass removes through
the same cmdlets, so its row is Removed or Failed by the same rule. One consequence is deliberate: a
removal of an assignment that never existed now also ends without an error, since the state the
caller asked for holds; the verbose line says what was found.

**A removal counted as done still warns when the principal keeps the role another way.** The
direct assignment the caller named is gone, so the removal succeeds -- but a principal that still
holds the role as an activation, through a group, or at a narrower directory scope has not lost it,
and a verbose line alone would hide that. The re-read's filter names only the role and the principal,
no directory scope, so the same single request also returns those rows: widening it costs no
request, only the few extra rows in the answer. `Select-OERManagedDirectoryRoleAssignment -Excluded`
names why each such row is not the one the removal stood for (Scope, Group, Activation) from the same
three guard lines that decide the kept side, so the two sides cannot drift, and the Remove cmdlet
writes a warning naming how the principal still holds the role, with no id beyond those its own
"Removing ..." warning already shows. The prune pass captures that warning with `-WarningVariable`
and adds the same words to its Removed Detail, so it makes no second read either. Not verified live:
Learn documents `$filter` on `roleDefinitionId` and `principalId` without `directoryScopeId`, and a
refusal would fail the read and keep the original error; and step 4 measured that Graph lists no
inherited row in the per-role read (check 4.4), so the group case may not occur for these schedules
at all.

## inventory-azure-eligibility

Task 3 of Sprint 6 step 5 added `azurePimEligibility.json` to the `Export-OERInventory` bundle: the
Azure PIM eligible role assignments at the scopes `Resolve-OERInventoryScopeTree` already walks for
`roleAssignments.json` and `roleManagementPolicies.json`, projected read-only and never fed back
through `Invoke-OERStructure`. This anchor records ruling R4 and the one claim in it that is
measured rather than documented.

**R4 (decided): one paged `roleEligibilitySchedules` list per scope of the walk, not per
role-assignment-and-eligibility pair.** `Get-OERInventoryAzureEligibility` calls
`Get-OEREligibleRoleAssignment` exactly once for each scope `Export-OERInventory`'s Azure walk
visits: a management group scope is read with `-AtScope` (eligibilities at or above it, matching how
Learn documents the `atScope()` filter); every other scope -- every subscription
`Resolve-OERInventoryScopeTree` enumerates -- is read with no filter at all. The read runs as its own
pass AFTER the existing role-assignment / policy walk over the same scope list, not interleaved with
it, so a throttled request against one file is never blamed on the other and a scope that fails one
read can still succeed the other. Results are deduplicated on `RoleEligibilityScheduleId` (falling
back to a scope/role/principal composite key on the rare row that carries none), so an eligibility
visible from several scopes in the walk -- a management group's own eligibility, read once directly
at the management group and again, inherited, from every subscription below it -- is written once.
A scope whose read fails is named in `SkippedScopes` (`Export-OERInventory`'s
`SkippedEligibilityScopes`) and folds into the bundle's existing `InventoryPartial` error with its
own clause naming `azurePimEligibility.json`, exactly as a failed role-assignment scope already
named `roleAssignments.json` and `roleManagementPolicies.json` -- never presented as a scope with no
eligibility, since that would read as a fact nothing measured.

**Why per-scope, not per management group only, and not filtered by `-AsTarget` or a principal:**
the bundle's job is to tell an LLM (and an operator) who can already activate what at the scopes the
rest of the bundle proposes against, not to answer "what can the signed-in identity activate" -- so
`-AsTarget` is wrong on its face, and a principal filter would require already knowing which
principal to ask about, which is exactly what this file exists to surface. Reading every scope
unfiltered, rather than only management groups with `-AtScope`, is what makes a subscription's own
directly-scoped eligibilities visible at all: `-AtScope` on a subscription would show only
eligibilities inherited from a management group above it, silently dropping every eligibility
declared AT that subscription or below it.

**The below-scope coverage of an unfiltered read is an EXPECTED claim awaiting live verification, not
a measured or documented one.** Microsoft Learn's `roleEligibilitySchedules` `listForScope`
reference documents FOUR supported filters -- `atScope()`, `principalId eq '{id}'` ("at, above, or
below the scope for the specified principal"), `assignedTo('{userId}')` (used here as the module's
`-User`/`-Group`/`-ServicePrincipal` filters) and `asTarget()` -- and none of the four documents what
an unfiltered, `$filter`-less list returns relative to the scope in the URL. No live check of this
module's own unfiltered read has been run yet, so this is neither an observed nor a measured fact:
`Get-OEREligibleRoleAssignment`'s own help attributes the phrase "every eligibility that applies at
the scope (direct and inherited)" to the UNFILTERED read itself -- "Without a filter, every
eligibility that applies at the scope (direct and inherited) is returned" -- with the filtered forms
(a principal filter, `-AtScope`, `-AsTarget`) each getting their own sentence after it. "Applies at
the scope (direct and inherited)" names eligibilities AT the scope and INHERITED from a scope ABOVE
it; it says nothing about a scope BELOW it, and establishes no below-scope coverage either way. That
is exactly the gap Microsoft documents for no unfiltered read at all, and this helper's own
`.DESCRIPTION` and `Export-OERInventory`'s help are worded as EXPECTED behaviour pending the step 5
live-verification checklist, section 4 -- not as anything measured -- do not read either as stronger
than that.

**This is not a low-stakes hedge: `Resolve-OERInventoryScopeTree` enumerates management group and
subscription scopes only, never a resource group or a resource, so a resource-group- or
resource-scoped eligibility can reach `azurePimEligibility.json` in exactly ONE way -- through an
unfiltered subscription read's below-scope coverage.** There is no second path and no independent
walk that would catch it if the unfiltered read turns out not to reach that far: unlike a
management-group-level gap (caught anyway, later, when the walk visits the subscription directly, as
the deduplication case above shows), a resource-group-scoped eligibility has no scope of its own in
the walk to be caught FROM. The step 5 live-verification checklist, section 4
(`docs/live-verification/feat-inventory-directory-roles-and-rename-checklist.md`, written by a later
task), is where this gets measured for the first time. If that check finds an unfiltered
subscription-scoped read does NOT surface a resource-group-scoped eligibility beneath it, this
design does not capture resource-group-scoped eligibility at all, and R4 needs revisiting -- not a
silent gap to leave documented away.

**Measured, step 5 live run (2026-09-30), check 4.1: the unfiltered subscription read DOES return a
resource-group-level eligibility.** One `roleEligibilitySchedules` read of the test subscription,
with no `$filter`, returned an eligible Reader assignment at a resource group below it, identical to
a direct read of that resource group (4.3); the walk cost one eligibility request per scope (4.2). R4
stands. The two paragraphs above record why this had to be measured; they no longer describe an open
question.

**A listing that fails is never an empty level (step 5 live run, 2026-09-30 and 2026-10-01).** Two
gaps showed in the scope walk itself, before any eligibility read:
- App-only, the management-group LISTING answers `AuthorizationFailed`, and
  `Resolve-OERInventoryScopeTree` read that as "no management groups": the bundle reported nothing
  skipped. The full tree's management-group and subscription listings are now each caught: the level
  that could not be listed is named in the tree's `SkippedScopes` (`<management groups: the listing
  failed>`, `<subscriptions: the listing failed>`), and `Export-OERInventory` folds it into both
  `SkippedScopes` and `SkippedEligibilityScopes`, which makes the bundle `InventoryPartial`. A
  `-ManagementGroup` branch that cannot be read throws instead, since nothing of it could be walked,
  and the export then records the whole Azure walk as skipped.
- An operator's full-tree export minutes after creating a management group walked five management
  groups while six existed: the new one was absent from `scopeHierarchy.json` (the tenant root group
  was there), so its eligibility never reached `azurePimEligibility.json` although the per-scope read
  had nothing to do with it. The Management Groups API documents `Cache-Control: no-cache` as the
  way to bypass its caches, so `Get-OERManagementGroup` was made to send it -- and the operator's
  re-run, check 6.1R, measured it to change nothing: a few seconds and again about a minute after a
  new management group was created, the list lacked it with the header and without it alike, while a
  read by `-Name` found it at once. The header was removed again, with the private `-Header`
  parameter of `Invoke-OERArmRequest` that only it used. **This is a documented limitation, not a
  fixed gap:** a management group created in the last few minutes can be missing from the list, and
  an export in that window neither walks it nor names it as skipped, since nothing tells it the
  group exists; the help of `Get-OERManagementGroup` and `Export-OERInventory` says so. Not done, and
  why: enumerating the tree from the root with `$expand=children&$recurse=true`, or the root's
  `descendants`, might see a new group sooner -- unmeasured -- but needs read at the tenant root
  group, which an operator who sees only part of the tree does not hold. Parked until measured,
  together with how long the list lags.
- The management-group level of the eligibility read itself is NOT in doubt: the same 6.1 export
  holds an eligible assignment read at an existing management group's scope.

## pim-in-use-criterion

Task 6 of Sprint 6 step 5 made `Test-OERGroupPimInUse` the single owner of one question: does this
group use PIM for Groups? It records rulings R1-R3 and the one claim in them that is documented
rather than measured.

**The problem.** Microsoft Graph lists PIM-for-Groups policies for EVERY group, including one never
used with PIM for Groups (measured live 2026-09-28,
`docs/live-verification/feat-pim-group-approval-checklist.md`, run 2, check X.1). `Get-OERInventory`
read and exported them, so every exported group carried a default `pimPolicy` -- and a proposal that
changes one of those blocks onboards the group to PIM for Groups on apply, which cannot be undone,
and changes its policy ids (Microsoft Graph documentation, "Onboarding groups to PIM for Groups").
The export was inviting an irreversible change to groups nobody had chosen to put under PIM.

**R1 (the criterion).** A group uses PIM for Groups when EITHER its PIM eligibility is non-empty
(the caller passes the count it already read, as `-EligibilityCount`, so no second eligibility read
is made), OR any of its policies, listed in ONE request through `Get-OERPimGroupsGraphPath` as
`policies/roleManagementPolicies?$filter=scopeId eq '<id>' and scopeType eq 'Group'&$select=id,lastModifiedDateTime,lastModifiedBy`,
carries a non-empty `lastModifiedDateTime`, `lastModifiedBy.id` or `lastModifiedBy.displayName`. A
404 `ResourceNotFound` on that listing means PIM does not know the group: not in use. A 400
`ResourceTypeNotSupported` means PIM for Groups cannot manage the group at all: not in use either,
reported with the reason "PIM for Groups cannot manage the group (ResourceTypeNotSupported)". Any
other failure -- `ResourceNotFound` with another status included -- throws, and each caller accounts
for it.

**Why `ResourceTypeNotSupported` is an answer (final review of step 5).** Microsoft Learn ("Bring
groups into Privileged Identity Management", and the PIM for Groups API overview) says dynamic groups
and groups synchronized from on-premises cannot be managed in PIM for Groups, and this module's
sibling reads of the same beta family already take 400 `ResourceTypeNotSupported` as an answer:
`Get-OERGroup`'s eligibility read (no eligibility) and `Get-OERPimGroupPolicyId` (no policy). The
first version declared only `ResourceNotFound`, so for such a group the criterion threw, every
`Get-OERInventory` run recorded `groups/<name>/pimPolicy` unread, and a tenant with dynamic or
synchronized groups could never export anything but `InventoryPartial`. The code is declared at the
REQUEST, like the others, so it leaves no record in a caller's `-ErrorVariable`, and it is accepted
whatever the status, exactly as the two sibling reads accept it. What this listing answers for a
dynamic group is not yet measured: the step 5 checklist creates one (`oer-s65-pim-dynamic`) and
records the answer.

**The basis, and exactly how far it reaches.** Microsoft Learn, "List roleManagementPolicies" (v1.0):
Example 3 lists the two policies of a GROUP (`scopeType` `Group`), both untouched, each reading
`"lastModifiedDateTime": null, "lastModifiedBy": { "displayName": null, "id": null }`. The MODIFIED
shape comes from a different example: Example 2's policy has `scopeType` `Directory` and reads
`"lastModifiedDateTime": "2022-04-20T16:12:29.553Z", "lastModifiedBy": { "displayName": "MOD Administrator", "id": null }`.
Two things follow. The `id` can be null on a modified policy, which is why any ONE of the three fields
counts. And Learn shows no modified GROUP policy at all, so "a modified group policy carries a date
or a name" is an inference from a directory-role example -- documented for one scope type and
assumed for the other. Nor does Learn say whether an eligibility request that onboards a group
stamps its policies (the eligibility half of R1 covers that case whatever the answer), or what this
listing answers for a group PIM does not know: the 404 is MEASURED only on the policy-ASSIGNMENT
listing of the same family (`Get-OERPimGroupPolicyId`, 2026-09-28), and expected here.

**What an earlier live run already observed, which is not the same as having measured this
criterion.** The 2026-09-28 run of `docs/live-verification/feat-pim-group-approval-checklist.md`
printed `lastModifiedDateTime` for group policies in two follow-up reads: both policies of a group
nothing had ever onboarded read it empty (check 6.1), and on a group that run created and patched,
the patched owner policy read `2026-09-28 09:46:01` while the unpatched member policy read it empty
(check 5.2). That is the date half of R1 seen on a GROUP policy. It did not print `lastModifiedBy`,
did not look at a group onboarded only through an eligibility, and did not run this helper.

**The criterion is NOT counted as proven until it is measured live in the step 5 checklist**
(`docs/live-verification/feat-inventory-directory-roles-and-rename-checklist.md`, written by a later
task): an untouched group, a group whose policy was changed, a group onboarded only through an
eligibility, and a dynamic group PIM for Groups cannot manage. Cost if it is wrong, in each direction: a used group whose policy never shows a
modification loses its exported `pimPolicy` (safe -- an omitted block leaves the live policy
untouched on apply), or an untouched group's policy is still exported (the original risk, which the
apply-side warning below still catches). The live check detects both.

**R2 (`Get-OERInventory`).** The criterion runs BEFORE the four policy calls (two
`Get-OERPimGroupPolicyId` pre-checks, two `Get-OERGroupPimPolicy` reads) and a group not in use makes
none of them and carries no `pimPolicy` key -- one listing instead of four calls, and the reason is
written to the verbose stream. A criterion that could not be read is never guessed in either
direction: `pimPolicy` is omitted (an export would claim a use nobody measured) AND
`groups/<name>/pimPolicy` is recorded as unread, with its cause, so the run ends in `InventoryPartial`
(an omission alone would claim the group does not use PIM for Groups). That cause is a tenth
read-failure message shape, so the distinct-cause cap rose from nine to ten with it. When the
group's eligibility read itself failed, the count passed is 0 by default, not by measurement. A
modified policy still decides "in use" on its own, and that path is unchanged; but a "not in use"
decided on the policies alone is half an answer, so `pimPolicy` is omitted AND
`groups/<name>/pimPolicy` is reported unread beside `groups/<name>/eligibility` (fix round 1 of
Task 6; the first version reported only the eligibility, which left the help's "reported through
InventoryPartial" promise false for this case). No second cause is recorded for it: the eligibility
read's own cause is already on the list. `Export-OERInventory`'s RBAC-relevance filter is unchanged:
a `pimPolicy` key now implies the group was found to use PIM for Groups.

**A known blind spot of R1, named once.** A group used only through PIM ACTIVE assignments (no
eligibility) whose policies were never modified is not found to use PIM for Groups: R1 does not
look at assignment schedules. Its `pimPolicy` is then omitted from the export (the safe direction:
an omitted block leaves the live policy untouched on apply), and an apply that declares one for it
writes the R3 warning although the group is already onboarded. The documents therefore say "not
found to use PIM for Groups (no PIM eligibility and no modified policy)", never "does not use".

**R3 (`Sync-OERStructureGroup`).** Before the FIRST changed policy write of an item for a group that
already existed -- once per item, and before its `ShouldProcess` gate so `-WhatIf` shows it -- the
handler asks the criterion and warns when the group was not found to use PIM for Groups, or when that
could not be determined -- worded as the criterion's finding, never as "does not use", for the blind
spot above. It WARNS and never blocks, and it never changes a row: the document asked
for this policy, and onboarding a group on purpose through its first policy is the normal way a group
comes under PIM. It does not ask for a group created in the same run (no PIM history to protect), nor
once step 3 of the same item has SUCCESSFULLY written an eligibility (that request onboarded the group
already; a refused or `-WhatIf`-skipped one did not). The count it passes is what the item read, and
the item reads PIM eligibility only when it declares `eligibility` -- deliberately, since requesting
that read for a `pimPolicy`-only entry lets a 403 on the beta eligibility endpoint fail an item that
has no use for the answer. A group renamed through `previousDisplayName` takes the existing-group
path and is asked like any other existing group.

## typed-group-member-read

Sprint 9 step 1 (BL-13) made `Get-OERGroupRelation` the single reader of a group's `members` and
`owners` collections, and made that reader ask twice where it used to ask once. This anchor records
the defect, what was measured, why the second request is a typed one, and why the group prune never
removes a service principal (A9).

**The defect (BL-13).** Microsoft Learn documents it twice: "Known issues in Microsoft Graph" lists
"GET /groups/{id}/members doesn't return service principals in v1.0" (workaround: the `beta`
endpoint, or `$expand=members`), and a note on "List group owners" says the same of owners.
`Get-OERGroup -IncludeMembers -IncludeOwners` and `Get-OERGroupMember` read exactly those two
collections, so the module never saw a service principal that was a member or an owner. Nothing
failed: the read succeeded and the guard for unread collections never fired, so the export wrote a
group's members and owners without them as if that were the whole list.

**The measurement (2026-10-06).** Checks 1.1 to 1.5 of
`docs/live-verification/fix-read-service-principal-group-members-checklist.md`, app-only as the
dedicated live-verification identity through the module's own transport, on the unchanged build. The
group held one group member, one service principal member and one service principal owner, and no
user, device or organizational contact. Counts only:

| Read | Answer | Listed by the untyped read |
|---|---|---|
| `v1.0` `members`, untyped | 1 object, the group | -- |
| `members/microsoft.graph.servicePrincipal` | 1 object, the service principal | no |
| `members/microsoft.graph.group` | 1 object, the group | yes |
| `members` cast to `user`, `device` or `orgContact` | 0 each, cast accepted (200) | -- |
| `beta` `members`, for the record | 2 objects, service principal and group | -- |
| `v1.0` `owners`, untyped | 0 objects | -- |
| `owners/microsoft.graph.servicePrincipal` | 1 object, the service principal | no |
| `owners/microsoft.graph.user` | 0 objects | -- |

The typed answers carry no `@odata.type` annotation at all. As the same certificate's identity with
no permission, the group read succeeds, the untyped members read and both owners reads answer 403
`Authorization_RequestDenied`, and the typed service principal members read still succeeds: the two
requests can disagree about permission, which matters for the whole-or-nothing rule below.

**Why a typed read, and not `beta` or `$expand=members`.** `beta` answers both (the table's `beta`
row), but the module pins group reads to `v1.0`; the PIM-for-Groups `beta` pin is a separate,
owned exception (`#pim-beta-pin`), and moving the module's most-used group reads onto `beta` would
carry that endpoint's unestablished availability in the US Government and China clouds
(`#sovereign-clouds`) onto every group read. `$expand=members` is the other workaround Learn names,
but "Customize Microsoft Graph responses with query parameters" says an expand on a directory
object typically returns at most 20 items and has no `@odata.nextLink`: a group with more members
would come back short with no signal, which is the failure this fix removes. The typed collection
is an ordinary list, so `-All` follows its pages.

**R1: only `servicePrincipal` is read typed, for both relations.** It is the only type the untyped
read was seen to leave out, and the only one Learn names. The `user`, `device` and `orgContact`
casts were accepted but the group held none of them, so their zeros show that the cast works, not
that nothing is missing. If wrong: a device or organizational contact the untyped read leaves out
would still be missing from `Members`. The repair is one more entry in the type list at the top of
`Get-OERGroupRelation`, made after a measurement with such a member.

**How the two reads are merged.** On object id, ignoring case, the untyped read's order first and
then what only the typed read added, so a service principal that Graph one day starts listing in
both appears once. Every object goes through `ConvertTo-OERGroupMember`. Since a typed answer has no
`@odata.type`, the helper passes the type it asked for as `-DefaultObjectType`, so ObjectType reads
`servicePrincipal`; an untyped object with no annotation whose id the typed read also lists gets it
too, the typed read being the proof of its type.

**A5: read whole or not at all.** Two requests make a new way to be half right: the untyped read
succeeds and the typed one fails (a 403, an exhausted 429, a 5xx), or the reverse. Handing back
what was read would state half a collection as a fact, which `Get-OERInventory` would write into an
apply document and `-Prune` would then act on (the chain behind issue #76). So
`Get-OERGroupRelation` emits nothing until both reads have succeeded and lets either failure
propagate; the caller's own catch reports it under the id it always had. `Get-OERGroup` omits the
property and writes `GroupMemberReadFailed` or `GroupOwnerReadFailed`, and `Get-OERGroupMember`
writes the transport's own record and returns nothing. `Get-OERGroupMember` collects the objects
into a list before it emits any, since a cmdlet emits as it goes: output from a successful first
read would already be in the pipeline when the second read failed. No ErrorId, parameter or output
type is new.

**Nothing else in the reads changed.** The export and the apply engine read a group through
`Get-OERGroup`, so they follow with no code of their own. A group's service principal members and
owners now count in the engine's comparison like any other principal: a declared one that is live
is `Unchanged`, a declared one that is not live is added, and the engine reconciles owners only when
the document declares an `owners` key, as before. The one change to the engine is A9, below.

**A9: the group prune never removes a service principal (Sprint 9 step 1, round 1).** Microsoft
Learn documents both omissions for every caller of `v1.0`, not as an effect of app-only: the List
group members operation "currently doesn't return any service principals" ("Known issues in
Microsoft Graph"), and "service principals are not listed as group owners" (the note on List group
owners); the test tenant measured both (the table above). So before this fix no version of the
module saw a service principal in a group, no version pruned one, and no document exported by an
earlier version lists one. Making the reads whole would on its own have turned every such document
into a removal: applied with `-Prune`, it would take every group's service principal members and
owners away, which is more than any earlier version ever removed -- a decision that is not this
fix's to make. So the reads and the export are whole, and the engine withholds the prune instead:
an undeclared live member or owner whose ObjectType is `servicePrincipal` is reported `Extra`
without `-Prune`, with a hint that `-Prune` leaves it in place, and `Skipped` with `-Prune`, with a
Detail starting `prune withheld:`, under `-WhatIf` too. No warning is written, no ShouldProcess
prompt is issued and `Remove-OERGroupMember` is not called for it. A declared service principal is
added and reported like any other principal, and a member or owner of any other type, or of none, is
pruned exactly as before. `ConvertTo-OERPruneWithheldResult` owns the rule and both texts, as the
single owner of "prune withheld" (its `-ObjectType` form); the handler calls it straight after the
unresolved-entry rule and, for owners, before the last-owner guard, so a lone service principal
owner is withheld for its type and still counts as an owner standing. Whether the engine should
ever prune service principals was decided on 2026-10-08 (BL-82): never. Every document exported
before 1.1.3 lacks service principals, so the first `-Prune` with such a document would remove them
all; a service principal in a group is often put there by something other than the document; and
the signed-in app could remove itself. Removing one stays possible on purpose, one at a time, with
`Remove-OERGroupMember -ServicePrincipal`.

**What A9 takes away: self-removal.** The group prune has no guard for the signed-in identity, unlike
the directory role prune, which never removes the signed-in identity's own assignment nor one held
through a group the identity belongs to (`#directory-role-assignments`). Without A9 the typed read
would have made an app-only identity (ClientCertificate, ClientSecret or ManagedIdentity) a group
prune candidate for the first time: a document that omits the running automation's own service
principal, applied with `-Prune -Confirm:$false` by that app, would remove it from the group and
could cut its own privileges part-way through the run. Under A9 that service principal is never
removed, so the case does not arise. A delegated user removing themselves through a group prune was
possible before this fix and still is; this change does not touch it.

**The five kinds of withheld prune `ConvertTo-OERPruneWithheldResult` builds.** One parameter set per
kind, each a `Skipped` row whose Detail starts `prune withheld:` and carries no warning and no
ShouldProcess prompt: a declared entry that could not be resolved, which withholds every candidate of
its collection (`-Unresolved`); an entry whose scope could not be resolved, which withholds every
candidate of the section (`-UnresolvedScope`, A12 under [#role-assignment-key](#role-assignment-key));
a live administrative unit scoped role whose name the directory role list did not give, beside a
role the document declares by a name no live role of that principal matches, which is neither added
nor removed (`-Declared` with `-UnnamedRoleId`); a group member or owner that is a service principal
(`-ObjectType`, A9 above); and, since Sprint 9 step 6, a live administrative unit member that is a
group this run created into the unit (`-CreatedGroup`, BL-07, below). The directory role prune's two
guards for the signed-in identity, under [#directory-role-assignments](#directory-role-assignments),
write their own `prune withheld:` rows.

**BL-07: the run that creates a unit membership does not prune it.** A group's `administrativeUnit`
is applied only when `New-OERGroup -AdministrativeUnit` creates the group, and never round-trips, so
the unit's own `administrativeUnits[]` entry need not list the group; and `Invoke-OERStructure` runs
the `administrativeUnits` section after `groups`. Under `-Prune` the unit's prune pass therefore saw
the new group as an undeclared member and removed, in the same run, the membership the create had
just made. Now `Sync-OERStructureGroup` records each successful create into a unit -- the unit as
the document names it, the new group's id and its name -- in a list `Invoke-OERStructure` keeps per
document and passes to the groups and administrative units handlers as a private parameter (ruling
R8: a run-scoped list through the handlers' extra parameters, as `roleAssignments` already does). A
group `New-OERGroup` found already existing is recorded too, which can only withhold. Its withheld
row therefore says the run either created the group into the unit or found it already existing
(Sprint 10 step 5, BL-100): the handler cannot tell the two apart, and the earlier text claimed a
create in both. The unit's
prune pass, straight after the unresolved-entry call, withholds a candidate whose id is a recorded
group id and whose record names this unit, by its display name or its object id (a reference that
parses as a GUID, braced and dash-less forms included, is read as the unit's object id and compared
as a GUID, as `New-OERGroup` reads it -- Sprint 9 step 6, ruling R14): with `-Prune` the
row is `Skipped` and nothing is removed, without `-Prune` it is `Extra` as before, with the usual
"use -Prune to remove" hint. Only the creating run withholds it. A later run cannot tell that the
membership came from the create, since nothing records it in the tenant or the document, and
withholding every group member of a unit would end the unit prune for groups altogether -- a
decision this fix does not make. Every later apply with `-Prune` removes the membership unless the
unit's `members` name the group.

**The validator reports the later removal.** Rule 12 of `Test-OERStructureSchema` (issue #59)
reports a Warning finding for a group whose `administrativeUnit` names a unit the same document
reconciles without naming the group in its `members`. Since BL-07 it checks a template-based group
under the name `Resolve-OERName` computes, as the duplicate check does; matches the unit the way
`New-OERGroup` reads `administrativeUnit` -- a value that parses as a GUID by the `id` an entry
declares, any other by `displayName`; and reports a unit named by an object id that no entry
declares when an entry that may be that unit (one declaring no `id` of its own) reconciles its
members without naming the group, since offline it cannot tell which unit that is. When the group
declares no `id` of its own, a member that is an object id may be the group and counts as naming it,
since an exported inventory lists a group member by its id (Sprint 9 step 6, ruling R9: no false
finding, at the price of a missed one when that id is another object) -- unless that id is the `id`
another `groups[]` entry declares, which names that other group (ruling R13). Its
text says what the engine now does: the creating run withholds the prune, every later apply with
`-Prune` removes the membership. `Invoke-OERStructure` surfaces no Warning finding -- it joins only
the Error findings into `StructureValidationFailed`, when it refuses the document -- so this finding
reaches an operator through `Test-OERStructure`.

## group-rename

Sprint 6 step 5 made a group renameable through the apply document: `previousDisplayName` names the
group's current display name or object id beside the new `displayName`. Both names are resolved on
every run, before anything is read or written, and the outcome is decided by which of them match.

**Why "neither name matches" fails instead of creating (decision before the step 5 live run,
2026-09-30).** The first version created the group under `displayName` when neither name resolved,
exactly as an entry without `previousDisplayName` does. Its own documentation then had to tell the
operator not to re-apply too soon: Microsoft Graph's display-name lookup can follow a rename with a
delay, and inside the window in which neither name resolves yet, a re-run created a SECOND group
beside the renamed one -- a duplicate that nothing reports, which other sections' references could
then bind to. A document that declares a rename names a group that already exists, so no reading of
that document asks for a create. The entry now fails with `GroupRenameNotFound` (category
`ObjectNotFound`, target the new name) and one Failed row, nothing is created, read or written, and
the same holds under `-WhatIf`, since the decision is made before any `ShouldProcess` gate. An object
id in `previousDisplayName` that no longer names a group (checked with one read,
`v1.0/groups/<id>?$select=id`) counts as not matching, so with `displayName` not matching either, it
fails the same way.

**Cost, accepted.** A document written to create a group AND carrying a `previousDisplayName` -- one
copied from a rename, say -- no longer creates it; the error says to remove `previousDisplayName`.
And a re-run inside the lookup window is a Failed row to re-run later, instead of a silent duplicate.
An entry without `previousDisplayName` is unchanged: a `displayName` nobody carries is created.

**Both names on different groups** stays `GroupRenameConflict` (category `ResourceExists`): the
document never merges two groups. A name matching several groups throws `AmbiguousName`, as an
ambiguous `displayName` does, and the object id is the way around an ambiguous old name.

**Catalog resources follow a rename (step 5 live run, check 5.5, 2026-09-30).** A catalog keeps the
display name a resource had when it was added: after the group `oer-s65-catres-old` was renamed,
the catalog still recorded the resource under its old name. The catalogs handler matched Group and
Application resources on that recorded name, so a document naming the group by its NEW name -- what
every other section is told to do after a rename -- planned `would remove undeclared resource` for
the renamed group's own resource under `-Prune`, the P0 family (an access package then loses its
resource). A Group or Application resource is now identified by the object id its declared name
resolves to (`Resolve-OERGroupId`, or `Resolve-OERApplicationId` for an application's service
principal; an object id is taken as it is), compared with the live originId; a SharePoint site keeps
its name/url keys. A name that resolves to nothing, or to several, fails its entry and withholds that
catalog's prune (the step 1 rule); a lookup that FAILS throws, so a failed read is never read as an
absent resource. `Get-OERInventory` writes the CURRENT name, looked up by originId with the id as
the fallback, in both the catalogs and the access packages sections, and the access package handler
resolves a name to the group first when that group is a resource of the catalog -- otherwise a name
the catalog still records for ANOTHER resource could bind the role to the wrong group and read the
right binding as undeclared. The earlier documentation that told a proposal to keep the old recorded
name in those two sections is withdrawn.

## role-assignment-key

Sprint 8 step 1 changed what identifies a `roleAssignments` entry in the apply engine, from the text
the document wrote to what that text resolves to, and made a repeated entry an error instead of two
passes that undo each other. This anchor records why each part sits where it does. Everything below
was derived from the code and covered by mocked tests, except the one fact marked as measured live.

**The scope is resolved once, before dispatch, and entries are grouped on the canonical resolved
scope (BL-01).** The engine used to group sibling entries on the scope TEXT, compared without regard
to letter case, and to run one prune pass per distinct text. `sub:` and `subscription:` with an id,
`/subscriptions/` with that id, a subscription's name, `mg:` with a management group's name or
display name, and the management group's path are all spellings of ONE scope, so a document that used
two of them formed two groups over one live scope. Under `-Prune` each group's pass removed what the
other group declared: in practice only the LAST group's assignments were left after a run, and the
others were created and removed again on every run. Without `-Prune` each group reported the other's
assignments as `Extra`. A trailing `/` was never trimmed either. No live scope carries one, so that
group's comparison never matched: it pruned nothing itself, drew a false "inherited" `Skipped` row for
its own assignment, and, when the same scope was also written without the slash, had its assignments
pruned by that other group. Such a scope is now refused before the run instead (A15, below).

`Resolve-OERStructureRoleAssignmentScope` now runs once before the first entry is dispatched. It
parses each entry's scope with `ConvertTo-OERScopeSplat`, resolves it with `Resolve-OERScope` and puts
the result in the canonical form `ConvertTo-OERCanonicalScope` owns. The engine groups on that string
without regard to letter case, and hands EVERY entry of a group the same string as `-ResolvedScope`.
The handler never resolves the scope again, and uses exactly that string for every Azure Resource
Manager call and for the comparison of a live assignment's scope with the declared one, which is what
decides what the prune may touch. Were the handler to resolve it for itself, the comparison could
stand on a different spelling than the group was formed on, and a trailing `/` would come back at the
comparison of a live assignment's scope with the declared one, which silently matched nothing for a
scope ending in `/`. As a side effect each distinct scope text is looked up once per run and not three
times per entry, which for a `sub:` name was two to three listings each time. Only a success is
cached, by the exact scope text: a transient failure on one entry must not fail the next entry with
the same text. Labels, which each declared entry's rows carry as their Item, keep the document's own
text, since an operator searches the output for what the document says; a Detail that names the scope
names the resolved scope the handler was given (the engine's own Detail for a scope it could not
resolve quotes the text, since there is no resolved scope).

**The role is compared on its GUID, the last segment of its id (BL-35).** `Resolve-OERRoleDefinitionId`
anchors a role given as a GUID at the scope it was handed. A live assignment at a resource group
carries the role definition id anchored at the SUBSCRIPTION -- measured live, see the withheld
candidate row in `docs/live-verification/fix-withhold-prune-on-unresolved-entries-checklist.md` -- and
a management group is expected to behave the same way. Comparing whole ids therefore never matched a
role given as a GUID below the subscription: with `-Prune` the live assignment was removed and
created again on every run. A role given by name did match, since the listing returns Azure's own id,
and the export writes a name or a full id, so a round trip never met the defect. But the
`AmbiguousName` message asks the operator to give the GUID, which led straight into it. The match and
the declared key set both compare the last segment without regard to letter case; a GUID names one
role definition everywhere, so nothing is lost, and the id sent to Azure when an assignment is
created is unchanged.

**An unresolved scope withholds the prune of the whole section (A12).** An entry whose scope cannot
be resolved belongs to no group, and it may be a spelling of ANY scope in the section: its own live
assignment would look undeclared at whichever scope it names. So every undeclared candidate at every
scope is reported `Skipped` with a Detail starting "prune withheld:", with or without `-Prune`, and
none is removed, while the entry itself is `Failed` with its error published as itself. It is the
rule `#directory-role-assignments` already applies to a role it cannot resolve, and it errs towards
removing less. The earlier end-to-end test, which expected an assignment to be removed beside an
unresolved scope, was turned round on purpose.

**A repeat after resolution is `Failed` and still counts as declared.** Two entries of one resolved
scope that name the same principal and role are one assignment declared twice, and only resolution can
tell, for a subscription's name and its id look nothing alike. The later entry is reported `Failed`,
naming the earlier one by index and label, and nothing is read or written for it: no create and no
in-place update, so two spellings cannot each rewrite the condition of one assignment. Its key stays
in the declared set, so the prune never removes the assignment it describes; withholding the key would
let a malformed document delete a live assignment, which is the one direction this change never goes.
An earlier entry that carries no key, because its principal or role did not resolve, never makes a
later one a duplicate.

**The validator owns uniqueness, and the canonical scope is a pure helper.** `schema.json` is draft-07,
which cannot say that the items of an array have unique keys, so `Test-OERStructureSchema` owns the
rule: a repeated entry is an `Error` at the later entry's path, naming the earlier index, in every
section, and an `Error` refuses the whole document before authentication and before any write. The
validator compares scopes, and must do it without a transport: `Test-OERStructure` is
`Transport = 'None'` in `Get-OERRequiredScopeMap`, and the requiredscope gate follows the call graph,
so a validator that reached `Resolve-OERScope` would give a cmdlet that needs no permission an edge to
Azure. `ConvertTo-OERCanonicalScope` is therefore pure: a prefix in any letter case, `sub:` and
`subscription:` with a GUID to `/subscriptions/` and the GUID, `mg:` to the management group path, and
a trailing `/` trimmed except for `/` itself. The engine uses the same helper, so the offline and the
online comparison cannot drift. What the helper cannot know is a subscription's name or a management
group's display name, and those pairs are the ones the engine catches after resolution, which is why
the rule lives in both places. `ConvertTo-OERScopeSplat` is likewise the one owner of the `sub:`,
`subscription:` and `mg:` syntax, which `Sync-OERStructureRoleManagementPolicy` and the role assignment
handler used to parse with two private copies.

**The export leaves colliding names out, and writes colliding principals by id.** A document that
`Get-OERInventory` writes is the one an operator edits and applies, so it must not be one the
validator now refuses. Live groups, administrative units, catalogs, access reviews, or access packages
of one catalog that share a name, without regard to letter case, are left out of the document, all of
them, and each name is reported through `InventoryPartial` with the cause "share the name", also on
the verbose stream. The apply engine has refused an ambiguous name since Sprint 7, so neither entry
could have been applied. Leaving a top-level entry out removes nothing, since `-Prune` acts on child
collections only and the engine never deletes a top-level object. Role assignments are different:
every row is real and wanted, so a colliding principal is written by object id, with `principalType`
so a re-apply creates the right kind of principal, and a role is written as its full definition id
only when the principal already was an id. A role policy read twice is written once, since it is one
policy.

**A scope written with a trailing or doubled `/` is refused (A15).** The canonical form trims every
trailing `/`. With the trim alone, a document whose ONLY spelling of a scope ended in `/` would start
to prune undeclared assignments at that scope under `-Prune`, which that group never did, and a scope
written as `//` would canonicalise to the root `/` and, under `-Prune`, prune undeclared assignments at
the tenant root scope, which earlier versions never did. Both remove more than before, and this change
never does that. `Test-OERStructureSchema` therefore reports a `roleAssignments` or
`roleManagementPolicies` scope that ends with `/` (other than the root `/` itself) or contains `//`
anywhere as an `Error` at the entry's scope path, and `Invoke-OERStructure` refuses the whole document
before it signs in. A refusal removes nothing, and Azure Resource Manager never returns a scope with
either spelling, so a document `Get-OERInventory` writes is not hit. The helper keeps its trim: for a
document the validator accepts it changes nothing -- a unit test walks the candidate spellings and
shows that every accepted path is its own canonical form and only `/` itself becomes `/` -- and the
engine still applies it to the scope it resolved. The first round of this change accepted the merge
as a cost; it was withdrawn on review. Every effect of the change is now to remove fewer assignments,
or the same.

**A failed read of the assignments at a scope is `Failed`, never an empty list (A14).**
`Get-OERRoleAssignment` reports a failed read, for instance a 403 at a management group, as a
non-terminating error and returns nothing. The handler read it without `-ErrorAction Stop`, so its
catch was never reached: the failed read became an empty list, every declared entry at that scope was
planned as a create (measured live: six assignments that exist, as an identity without read access at
the management group), and a read that failed part way would have handed the prune pass an incomplete
list. The read now carries `-ErrorAction Stop`, so the entry is `Failed` with the read error published
as itself, nothing is created or planned, and the prune pass for that scope does not run.

## approver-lookup

Sprint 8 step 3 (BL-14, decision A5) made the PIM approver lookups follow the rule every other lookup
on the cohort's list follows: an ambiguous name is reported as `Ambiguous*`, a failed lookup is
published as itself, and `*NotFound` means only that nothing matched.

**Why the exception went.** The approver lookups shared the decided exception with the principal and
Azure role definition lookups: every throw out of an approver lookup became `ApproverNotFound`. That
took in a 403, an exhausted 429 and a group display name that several groups share, so an identity
without the right to read groups was told that an approver who exists did not, and an ambiguous name
was reported missing instead of naming its candidates. Unlike the other two, the approver exception
had no written reason anywhere -- not here, not in CLAUDE.md, not in a commit message -- and the
approved scope of the step took BL-14 in. The principal and Azure role definition lookups keep their
exception; nothing in this step changes them.

**What is published.** Six call sites: `Set-OERGroupPimPolicy`, `Set-OERDirectoryRoleManagementPolicy`
and `Set-OERRoleManagementPolicy`, and the approver step of the three apply handlers
(`Sync-OERStructureGroup` step 4, `Sync-OERStructureRoleManagementPolicy` and
`Sync-OERStructureDirectoryRoleManagementPolicy`). At each of them:

- an approver that matches nothing is `ApproverNotFound`, with the message, category
  (`ObjectNotFound`) and target it always had;
- an ambiguous name is the new `AmbiguousApproverName`, category `InvalidArgument`, the approver
  value as target, and a message that carries the resolver's text, which names the candidate ids;
- anything else is published as itself, once: `$PSCmdlet.WriteError($PSItem)` in a cmdlet, and
  `$Caller.WriteError($PSItem)` plus a Failed row carrying that record in a handler.

Every path still returns before anything is written for that policy (two handlers read the live
policy first). No published id is removed or renamed: `ApproverNotFound` stays, for exactly what it
always meant. What changes is how a failure that was never a missing approver is reported: its id and
category, a prefix on the ambiguous message, the approver value as the target of an ambiguous record
(in a handler too), and, for a failed lookup, the failed record's own target.

**How the three are told apart.** `Resolve-OERPrincipal` used to signal "not found" by throwing a bare
string, which a catch cannot tell apart from a failure. It now throws an ErrorRecord with the internal
id `PrincipalUnresolved` (category `ObjectNotFound`, the value as target, the same message text). Both
approver resolvers -- `Resolve-OERApproverInput` for the two Microsoft Graph cmdlets and
`Resolve-OERDeclaredApprover` for the handlers -- wrap only that record, as `ApproverUnresolved`; an
`AmbiguousName` record and every other failure leave them exactly as thrown, scrubbed first.
`Set-OERRoleManagementPolicy` calls `Resolve-OERPrincipal` itself, since its approver body and its
blank-value rule differ from `Resolve-OERApproverInput`'s, so the not-found record it sees is
`PrincipalUnresolved` rather than `ApproverUnresolved`; it maps that one to `ApproverNotFound`.

**Why the internal ids differ from the published ones.** A record thrown inside a nested command is
collected into the calling cmdlet's `-ErrorVariable` even when the cmdlet catches it (measured, see
[#bearer-scrub-tests](#bearer-scrub-tests)). An `ApproverNotFound` thrown by a resolver would sit next
to the one the cmdlet writes, and a caller counting `ApproverNotFound` records would see it twice. So
`PrincipalUnresolved` and `ApproverUnresolved` are named so that no published id is a prefix of them,
and a `-like 'ApproverNotFound*'` filter never matches them. They do appear in
a caller's `-ErrorVariable` beside the published record, where a record whose id was the bare message
text sat before, so a test that counts what a cmdlet published filters on the published id, or on
the cmdlet's own record.

**The principal lookups are unchanged.** The other callers of `Resolve-OERPrincipal` --
`Get-OERRoleAssignment`, `Get-OEREligibleRoleAssignment`, `Get-OERActiveRoleAssignment`, and
`Resolve-OERPrincipalOrId` with every cmdlet that uses it -- read only the message and
`Test-OERAmbiguousNameError`, so they publish the same ids and messages as before. Their existing
tests pass without a change, which is the proof.

**BL-97 (F1): approvers that name nobody fail in the plan too.** For an Azure role management policy
the diff sends both approver sides whenever either differs, since Azure Resource Manager replaces the
whole approver list, the side the document does not declare seeded from the live policy. A declared
empty side beside an other side that is empty too -- declared, or seeded empty from the live policy
-- is therefore exactly the call `Set-OERRoleManagementPolicy` refuses with `ApproverRequired`
before anything is sent. Before Sprint 10 step 5 the `-WhatIf` plan reported that entry as "would
update" while every run reported it `Failed`. Now `Resolve-OERRoleManagementPolicyChange` flags it,
in its `ApproverRequired` property (the Azure shape only, never with `-SendDeclaredApproverSideOnly`,
where the directory-role cmdlet carries the undeclared side from the live rule), and
`Sync-OERStructureRoleManagementPolicy` reports the entry `Failed` with that same ErrorId before its
`ShouldProcess` gate: the plan and the run report the same row, and nothing is sent, the other
declared fields of the entry included. The condition is exactly the cmdlet's own (Sprint 10 step 5,
ruling R1): an approver parameter is bound and the non-blank values of both name nobody. A document that turns
approval on over an empty live approver list sends no approver parameter, so it is not flagged:
nothing refuses it before Azure Resource Manager, and the plan and the run already agree. The
cmdlet's own refusal stays in place as the backstop.

## failed-schedule-request

Sprint 9 step 5 (BL-33) made a PIM schedule request that Microsoft Graph or Azure Resource Manager
ACCEPTED, and then answered with a status in the Failed family, an error in the twelve cmdlets that
send one. The private `Test-OERScheduleRequestFailed` owns the rule. This section records why the rule
is the Failed family and nothing wider, why a cmdlet emits the request object before the error, why
there is one owner, and what the two ARM `New-` cmdlets do with a role policy they opened.

**What was wrong.** A schedule request is answered in two layers: the call is accepted, and the
object it returns carries a `status`. Both services answer a request they took and then could not
act on with the status `Failed`, which grants, changes, removes, activates or deactivates nothing.
Only `Add-OERGroupEligibility` wrote an error for it (`EligibilityRequestFailed`). The other eleven
cmdlets that send a schedule request emitted the object and wrote nothing, so a caller reading "no
error" read a request that did nothing as done, and so did the apply engine, which calls them with
`-ErrorAction Stop` and acts on an error alone.

**Why the Failed family and nothing else.** The statuses are taken from the documentation. Microsoft
Graph documents them on the `request` resource, which `unifiedRoleEligibilityScheduleRequest`,
`unifiedRoleAssignmentScheduleRequest` and `privilegedAccessGroupEligibilityScheduleRequest` inherit
(learn.microsoft.com/graph/api/resources/request?view=graph-rest-1.0): Canceled, Denied, Failed,
Granted, PendingAdminDecision, PendingApproval, PendingProvisioning, PendingScheduleCreation,
Provisioned, Revoked, ScheduleCreated. Azure Resource Manager documents them in the `Status` enum of
role assignment and role eligibility schedule requests, Microsoft.Authorization api-version
2020-10-01 (learn.microsoft.com, the azure-mgmt-authorization v2020_10_01 `Status` enum, and the
Az.Resources completer for `IRoleAssignmentScheduleRequest.Status`): Accepted, PendingEvaluation,
Granted, Denied, PendingProvisioning, Provisioned, PendingRevocation, Revoked, Canceled, Failed,
PendingApprovalProvisioning, PendingApproval, FailedAsResourceIsLocked, PendingAdminDecision,
AdminApproved, AdminDenied, TimedOut, ProvisioningStarted, Invalid, PendingScheduleCreation,
ScheduleCreated, PendingExternalProvisioning. They are the same two lists the owner's own help
carries.

The rule is a prefix, not a list: a status that starts with `Failed`, compared without regard to
letter case, so `Failed`, `FailedAsResourceIsLocked` and any later member of the family are errors
without a change here. Everything else is left alone, one reason per group:

- `Denied`, `AdminDenied`, `Canceled` and `TimedOut` are outcomes of an approval, or of a requester's
  cancellation, that come after the request was answered. They are never the synchronous answer to
  the admin and self requests these cmdlets send.
- `Invalid` has no documented meaning.
- `Accepted`, `ProvisioningStarted`, `AdminApproved`, `Granted`, `Provisioned`, `ScheduleCreated`
  and every `Pending*` value are applied or on their way.
- `Revoked` is a removal's success. A removal answered `Revoked` is never an error, and the engine
  keeps reporting it `Removed`.

If wrong: an admin request answered synchronously with `Denied`, `AdminDenied`, `Canceled`,
`TimedOut` or `Invalid` would still read as success. None of them has been measured as the answer to
a request that did nothing; should one be, `Test-OERScheduleRequestFailed` is the one place to add
it.

**Why the object is emitted first.** Under `-ErrorAction Stop` the first error a cmdlet writes stops
it, so nothing after the error runs. The request object is the only record of what the service took
(its name or id and its status), and a caller that wants to retry, report or look the request up
needs it. Written first, it reaches the caller, through `-OutVariable` for example, before the error
stops the cmdlet. `Add-OERGroupEligibility` already did this and the other eleven follow it. The
error is non-terminating, written with `Write-CmdletError` in category `InvalidResult`, like every
other failure a public cmdlet reports. Its target is the object the request acts on: the group id,
the role definition id of a directory role, or the target scope of an Azure role.

**Two ids.** `EligibilityRequestFailed` already existed, from `Add-OERGroupEligibility`, and names an
eligibility request. It goes to the group, directory role and Azure eligibility cmdlets (Add- and
Remove-OERGroupEligibility, New- and Remove-OEREligibleDirectoryRoleAssignment, New- and
Remove-OEREligibleRoleAssignment). The active assignment, activation and deactivation requests are
not eligibility requests, so reusing the id would have published the wrong noun: they get the one
new id, `AssignmentRequestFailed` (New- and Remove-OERActiveDirectoryRoleAssignment, New- and
Remove-OERActiveRoleAssignment, Enable- and Disable-OEREligibleRoleAssignment). No published id is
renamed or removed.

**Why one owner.** Before the step the module held the literal `Failed` three times: once in
`Add-OERGroupEligibility`, and twice in `Sync-OERStructureGroup`, where the two new-group replication
waits read an eligibility request's answer. Eleven more copies would have made fourteen places to
decide what a failed request is, and fourteen places to drift apart on case, on the prefix and on
`Revoked`. The owner is a pure private function, so it makes no request and writes nothing, and the
twelve cmdlets and the two waits all ask it.

What holds that is the cohort check in `tests/Unit/Private/Test-OERScheduleRequestFailed.Tests.ps1`,
and only that much of it: the twelve cmdlet files call the owner, and no other file under `source/`
compares a status to a `Failed` literal in the shapes the check scans, which are a status-named
operand against a literal that starts with `Failed`, in either order, with `-eq`, `-ne`, `-like`,
`-notlike`, `-match` or `-notmatch` (and their case-sensitive and explicitly case-insensitive forms).
A comparison written in another shape, such as `-in`, `-contains`, a `switch`, `StartsWith` or a
pattern anchored with a caret, is not seen by it and stays a matter for review. The check does NOT
hold that the two engine waits call the owner. The behaviour tests in
`tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1` do, by driving each wait with `FAILED` and
`FailedAsResourceIsLocked` answers.

**The engine's two waits.** They are the replication waits of `Sync-OERStructureGroup` for a group
created in the same run, where Graph can take an eligibility request and fail it at once because the
group is not yet known to PIM for Groups, and the same request minutes later is Provisioned
(measured live on 2026-10-03). The engine waits and asks again from one shared budget. They are not
new error handling, which is why the decision that the engine needs no code of its own for this step
holds. They already compared the answer to the literal with `-eq` and `-ne`, which are
case-insensitive, so `FAILED` was taken as Failed before the move as well. Routing them through the
owner changes behaviour only for the OTHER values that start with `Failed`, `FailedAsResourceIsLocked`
for example: such an answer used to end the wait as applied, and is now waited through like `Failed`.
Without the move the rule would have had three owners, which is the cost it removes. The time-bound
wait sends its request itself, through `Send-OERNewGroupEligibilityRequest`. The permanent wait calls
`Add-OERGroupEligibility` with a module flag set around exactly that call, so that the cmdlet does not
write its own error for an answer the wait handles.

Everywhere else the engine needed no code. Each call it makes to these cmdlets passes
`-ErrorAction Stop`, so the new error lands in the handler's `catch` and the row is Failed, carrying
the cmdlet's id. The tests run the real cmdlets against a transport mock for the directory role
assignment create, update and prune paths and for the group eligibility prune, and hold that a
Failed answer is a Failed row and never Created, Updated or Removed, while a `Revoked` removal stays
Removed.

**A Failed answer after an opened role policy.** `New-OEREligibleRoleAssignment` and
`New-OERActiveRoleAssignment` can open the role management policy first, so that a permanent grant is
allowed, and send the grant afterwards. A request answered Failed grants nothing, and a grant that is
refused already rolls the policy back (`New-OERActiveRoleAssignment` gained that rollback in the same
step, see below). Leaving the policy open on a Failed answer would be the very weakening that
rollback exists to undo, so a Failed answer rolls it back too. The one record,
`EligibilityRequestFailed` or `AssignmentRequestFailed`, carries the rollback text: how the rollback
went and, when it failed, the `Set-OERRoleManagementPolicy` command that closes the policy by hand.
It is one record and not a `PolicyOpenedButGrantFailed` as well, since the request was accepted, not
refused. The rollback text has three outcomes. A rollback answered `NoChange` --
`Set-OERRoleManagementPolicy` writes it when no rule differs, so the rollback READ the policy as
already disallowing permanent assignments -- used to read as "The rollback ALSO failed, so the
policy is still open", which sent the operator to close a policy that may be closed. Sprint 10
step 2 (BL-99) first made it say that the policy was already closed and the rollback changed
nothing, and round 1 of that step (Sprint 10 step 2 round 1, finding 3) took that back. The read
shows only what the policy looked like to the rollback, and read-after-write consistency of
`roleManagementPolicies` is NOT measured: a read made seconds after the open may come from a
replica that has not seen it yet. "Already closed" and "not open" claimed more than that read
shows, and either could be false with the policy still open. The text now says that the rollback
read the policy as already disallowing permanent assignments and changed nothing, and that the
read may not reflect the open yet. It asks for a confirming `Get-OERRoleManagementPolicy
-PolicyId` read, and gives the `Set-OERRoleManagementPolicy` command that closes the policy if
that read still shows the permanent property True (`AllowPermanentEligibility` for the eligible
cmdlet, `AllowPermanentActiveAssignment` for the active one). That errs the way the group wait's
out-of-date read does, toward advice that may prove unneeded and never toward a weakened policy
left unreported. It stands in the refused grant's `PolicyOpenedButGrantFailed` and in the Failed
answer's record alike, since both come from the one rollback block. The block decides on the
error id, never on the message: the first comma-separated segment of the caught record's
`FullyQualifiedErrorId`, compared ordinally, must be `NoChange` (the real cmdlet's record reads
`NoChange,Set-OERRoleManagementPolicy` under `-ErrorAction Stop`, measured against a mocked
transport). The error id is the contract the cmdlet owns, while its message, "No applicable policy
rule changed.", is prose that can be reworded, or reused by another failure, and deciding on it
could turn a failed rollback into a closed policy. The rollback runs BEFORE the object is emitted,
not only before the error: a consumer that stops the pipeline at the object,
`Select-Object -First 1` for example, would otherwise skip it exactly as `-ErrorAction Stop` skips
what follows the error, and the policy would stay open. The object is still emitted before the
error. `Add-OERGroupEligibility` has no rollback to run, since the single-rule open it makes has no
public inverse, so its Failed record only names the policy that is left open.

**The order on a refused grant.** In `New-OEREligibleRoleAssignment`, a grant that threw after the
policy was opened wrote the grant's own error first, then rolled back, then wrote
`PolicyOpenedButGrantFailed`. Under `-ErrorAction Stop` the first error stops the cmdlet, so neither
the rollback nor the `PolicyOpenedButGrantFailed` record ever ran, and the policy stayed open
(measured while writing this step). That is an older defect, fixed here because BL-80 brings
`New-OERActiveRoleAssignment` to the shape of `New-OEREligibleRoleAssignment` and would otherwise have
copied it: `New-OERActiveRoleAssignment` opened the policy before it asked for confirmation and had no
rollback at all. Each of the two cmdlets now has one rollback block, shared by the refused-grant path
and the Failed path. On a refused grant it runs first, then the cmdlet writes
`PolicyOpenedButGrantFailed`, which names the policy, how the rollback went (rolled back, read as
already disallowing permanent assignments and left unchanged, or failed) and how the request failed,
and only then the grant's own error. Under `-ErrorAction Stop` the cmdlet is stopped by
`PolicyOpenedButGrantFailed`, after the rollback, and the grant's own message travels inside it,
since under Stop its own record is never reached.
`New-OERActiveRoleAssignment` also opens the policy only once the assignment is confirmed, as
`New-OEREligibleRoleAssignment` already did, so a declined prompt weakens nothing while `-WhatIf`
still plans the policy change.
`Add-OERGroupEligibility` kept its older order through this step, its grant error written before
`PolicyOpenedButGrantFailed`, so under `-ErrorAction Stop` the advice naming the policy it left open
was never written. Sprint 10 step 2 (BL-98) gave it the same order: on a grant refused after it
opened the policy, it writes `PolicyOpenedButGrantFailed` first -- the policy left open, the
`Set-OERGroupPimPolicy` command that closes it, and the grant's own message inside it -- and only
then the grant's own error. Under `-ErrorAction Stop`, the way the apply engine calls it, the advice
is the error that stops it, so the engine's Failed row for the item carries it. There is still no
rollback, since the single-rule open it makes has no public inverse.

**What a new group's `GroupNotOnboarded` says about its policy (Sprint 10 step 2, BL-51).** For a
group created in the same run, the engine's permanent wait calls `Add-OERGroupEligibility`, which
opens the group's policy to allow permanent eligibility before it sends the request. When the wait
ran out, `GroupNotOnboarded` said nothing about that, so a policy the run had opened stayed open
unreported. The engine now decides it itself, not through a flag threaded out of the cmdlet: the
readiness poll has just read the policy before each call, and its read before the FIRST call is the
before-state -- kept from that call only, since a later poll reads a policy the first call may
already have opened, and unknown when the poll was refused or its read carried no
permanent-eligibility setting. After the attempts the engine reads the policy once more, with the
poll's own two calls and no wait of its own, and the message gives one of seven outcomes, decided in
this order: nothing sent and nothing opened, not readable after the attempts, not left open, a
closed read that may be out of date, open and possibly opened, already allowed before the first
request, or opened and still open. A read after the attempts that fails, is unlisted, answers 404 or
reads no setting is unknown, and an unknown is never written as "not opened": the message says the
policy may have been opened and gives the command that closes it, since a reader who acts on "not
opened" leaves a weakened policy in place. A closed read is "not left open" only when the poll did
not read the policy closed just before the first request (Sprint 10 step 2, Ruling R4). When it did,
that request would have opened it, and a read made seconds after the open can come from a replica
that has not seen it yet: the message then says the read may be out of date and gives the close
command for the case that the policy allows permanent eligibility. That errs toward advice that may
prove unneeded, never toward a weakened policy left unreported. A closed read after a before-state
that is unknown can still be such a stale read; that is the cost of not threading a flag out of the
cmdlet. The command comes from `Get-OERGroupPimPolicyCloseAdvice`, which `Add-OERGroupEligibility`
uses too, and is `Set-OERGroupPimPolicy -Group G -AccessType A -AllowPermanentEligibility:$false`
(Sprint 10 step 2, Ruling R1). The advice before this step named `-ActivationMaxHours` without the
switch, and `Set-OERGroupPimPolicy` patches `Expiration_Admin_Eligibility` only when
`-EligibleDuration` or `-AllowPermanentEligibility` is bound, so that command left the policy open.
Binding the switch to false sends the rule with `isExpirationRequired` true and the live
`maximumDuration`; the helper's own tests run the advice's text against the cmdlet to hold that.

Round 1 of the step (Sprint 10 step 2 round 1, finding 2) applied the same reading to the opposite
instruction. `Add-OERGroupEligibility` tells the operator how to OPEN a policy by hand when its own
open fails (`PolicyOpenFailed`), and that command now comes from the private
`Get-OERGroupPimPolicyOpenAdvice`, the opening counterpart of the close advice. It names only
`-AllowPermanentEligibility`, where it used to carry `-ActivationMaxHours <n>` as well. That text
did not run as typed: PowerShell reserves the less-than operator, so the command failed to parse
until the placeholder was replaced (measured in plain PowerShell), and a value put in its place
rewrote the activation maximum, since `-ActivationMaxHours` patches the activation rule and the
open does not touch it. With the switch alone `Set-OERGroupPimPolicy` reads the live eligibility
`maximumDuration` and sends it back unchanged with `isExpirationRequired` false; if that read
fails it warns and falls back to the `-EligibleDuration` default, which is the cmdlet's own
behaviour and not the advice's. The helper's tests parse the text, run it against the cmdlet, and
keep the old text as a record of why it changed. The id, category and target of `PolicyOpenFailed`
are as they were.

**A later attempt that throws after an earlier one failed (Sprint 10 step 2 round 1, finding 1).**
The permanent wait calls `Add-OERGroupEligibility` again after a request answered `Failed`, since a
new group may still be replicating. That first request may already have opened the policy, which the
cmdlet does before it sends and cannot undo, and the handler suppresses the cmdlet's own
`EligibilityRequestFailed` for the wait, so nothing else says so. A LATER call can then throw having
opened nothing, with an error that says nothing of the policy the earlier request opened. Only
`GroupNotOnboarded` reported it. Such an error now gets the same statement: the after-attempts read
and its outcome, the six outcomes after a call was made, come from ONE scriptblock in the handler,
`$PermanentPolicyAfterAttempts`, that `GroupNotOnboarded` calls too, so the two texts cannot drift
(the idiom of `$RollBackOpenedPolicy` in the Azure cmdlets, not a new private function, since it
reads the handler's own locals and the poll's functions; Sprint 10 step 2 round 1, ruling P3). The
statement is appended to the caught message, and the Failed row carries the same text. It travels in
a NEW record, not in `ErrorDetails` on a copy, since the codebase reads a record by its
`Exception.Message`. That record keeps the caught record's error id, category and target, and does
not chain the caught exception as its `InnerException`: only the message is reused (Sprint 10 step 2
round 1, ruling P2). The id is republished, so it is derived exactly: the
`FullyQualifiedErrorId` without the suffix PowerShell appends for the command that wrote it,
stripped only when the id ends with it, and never the first comma segment, since an id can contain
a comma. The read is made before the record is written, so a caller stopped by it under
`-ErrorAction Stop` gets the statement too. A first call's error is published as it was, since
nothing was sent before it, and so is a `PolicyOpenedButGrantFailed`, which already names the
policy that call opened and how to close it. A later call's `PolicyOpenFailed` gets the statement
like any other error, so one message can name the command that opens a policy and, when the read
finds it open, the one that closes it. Known limit: an id from an anonymous script block that
itself ends with a comma loses that comma, since PowerShell's format cannot tell it from the
suffix. An EMPTY caught error id would derive as the writing command's name, since PowerShell then
reads the `FullyQualifiedErrorId` as the bare command name (measured in plain PowerShell: an empty
id written by a function reads `Write-T`, which the strip cannot tell from a suffix), so such a
record would be published as `<command>,<caller>`. That is unreachable today, since every
`Write-CmdletError` call passes an id and Graph records always carry a code.

## warning-before-confirmation

Sprint 9 step 6 (BL-18, BL-17) moved the warnings about a deletion or about widened access to where
an operator can still act on them: ahead of the confirmation gate. This section records rule A4 for
the public cmdlets and for the apply engine, the rulings taken on it (numbered as in that step's
ledger, so "ruling R5" below is Sprint 9 step 6's R5, not another section's), and what it does not
cover. The
same step's withheld prune of a unit membership the run created (BL-07) is described with the other
kinds of withheld prune, under [#typed-group-member-read](#typed-group-member-read).

**What was wrong (BL-18).** Sixteen public cmdlets wrote that warning inside
`if ($PSCmdlet.ShouldProcess(...))`. A `-Confirm` prompt was then answered with no warning on screen,
the warning printed only once the operator had said yes, and `-WhatIf` never showed it at all. A
warning seen only after committing is not a guard. Four cmdlets -- `Remove-OERGroup`,
`Remove-OERAdministrativeUnit`, `Remove-OERAccessReviewDefinition` and
`Remove-OERAccessPackageAssignmentPolicy` -- already warned before their gate.

**Rule A4 for cmdlets.** The warning stands directly before the cmdlet's own
`$PSCmdlet.ShouldProcess`, its text unchanged. A warning that needs a value computed only inside the
gate moves out with that computation, or is named as an exception with its reason; none of the
sixteen needed either, since every value their texts use was already computed before the gate. The
warning still comes after the cmdlet's own checks and lookups, so a call the cmdlet refuses before it
reaches its gate writes its error and never the warning.

**What it changes for a `-WarningAction Stop` caller.** With `-WarningAction Stop`, or
`$WarningPreference = 'Stop'`, the first warning stops the cmdlet. None of the moved warnings stands
in a `try`, so under `-WhatIf` such a caller is now stopped at the warning instead of seeing the
`What if:` line, and under `-Confirm` before the prompt instead of after answering it. Nothing is
changed either way; it is the direction the rule exists for. The release note says so.

**Ruling R3: the cohort rule is "no warning after the first gate", not "no warning inside the if
body".** `tests/Unit/Public/WarningBeforeConfirmation.Cohort.Tests.ps1` reads every
`source/Public/*.ps1` with the AST and fails a `Write-Warning` that starts after the file's first
`$PSCmdlet.ShouldProcess` call. That is stricter than the defect's own shape: it also catches
`$Proceed = $PSCmdlet.ShouldProcess(...)` followed by `if ($Proceed) { Write-Warning ... }`, and an
early `if (-not $PSCmdlet.ShouldProcess(...)) { return }`. A warning that can only follow the gate is
named in the file's allowlist with its reason, in one of three kinds: an outcome warning, which
reports what the action did (a read-back that failed after an add, the put-back messages, a removal
after which the principal still holds the role another way); a warning that depends on what the
operator confirmed (a declined partner rule, a live rule read only for a pair that will be sent); and
a warning not about a deletion or widened access at all that stands after the gate only by position
(`Export-OERInventory`'s apply-schema self-check, which runs on every path). An entry that matches no
warning, or more than one, fails as well, so the list cannot go stale. If wrong: a future cmdlet with
a legitimate warning after its gate is named in the list with its reason. Beside the rule the file
pins the twenty cmdlets that warn before their gate, by name and warning, so a DELETED warning is
caught and not only a moved one, and it proves each moved warning at run time: on `OERConfirmHost`,
whose host now records the order of warnings, `What if:` lines and prompts, the warning comes before
the `What if:` line under `-WhatIf` and before the prompt under `-Confirm` answered No, and no write
request is sent. The number of gated public cmdlets and the roster are pinned, so a new gated cmdlet
or a new warning before a gate is added to them on purpose. `OER_COHORT_SOURCE_ROOT` points the AST
parts at a copy of `source/`, for a mutation proof; it is never set in CI.

**Rule A4 for the apply engine (BL-17).** `Invoke-OERStructure` calls the module's cmdlets from its
`Sync-OERStructure*` handlers behind its own `$Caller.ShouldProcess`, with `-Confirm:$false`.
Under `-WhatIf` that gate declines and the cmdlet is never called, so its warning was never written:
the plan showed the change but not the warning a real run gives. A handler therefore writes the same
warning before `$Caller.ShouldProcess` only when the cmdlet it calls will not write it, so the plan
shows it and a real run never warns twice. In four cases the handler does this under `-WhatIf` only,
deciding from the inputs the cmdlet's own warning uses and writing the cmdlet's text: an
administrative unit whose membership type changes (`Set-OERAdministrativeUnit`), an ABAC condition
removed from an Azure role assignment (`Set-OERRoleAssignment`), a permanent group eligibility that
needs the PIM for Groups policy opened (`Add-OERGroupEligibility`, step 5 of the group handler,
through the same `Get-OERGroupPermanentEligibilityState` read) and a directory role policy whose MFA /
authentication context pair the write reconciles (`Set-OERDirectoryRoleManagementPolicy`, through
`Resolve-OERPimActivationConflict`). The group PIM pair is the fifth case, ruling R5 below.

**Ruling R7: "the same warning" is held by tests, not by a shared message helper.** Each handler's
tests run the case as a plan and as a real run with the REAL cmdlet, from one live state, and hold
that the plan's text equals the run's case-sensitively and that the run writes it exactly once. The
directory role case runs a matrix of live and declared MFA and context states through both. If
wrong: a message helper can be split out later with no change in behaviour.

**Ruling R4: those four warn only under `-WhatIf`.** The other form -- warn before
`$Caller.ShouldProcess` always and silence the cmdlet with `-WarningAction SilentlyContinue`, as the
group handler's eligibility prune already does for `Remove-OERGroupEligibility` -- was weighed and
rejected: `Set-OERDirectoryRoleManagementPolicy`, `Set-OERGroupPimPolicy` and `Add-OERGroupEligibility`
write other warnings as well (put-back outcomes, read failures) that silencing would hide, and a
mixed form would make the rule harder to hold. The cost: under an engine `-Confirm` the prompt for
one of those four comes before the warning, which the cmdlet writes only once the prompt is accepted,
and a declined prompt shows the change only in its own text. If wrong: the administrative unit and
role assignment handlers, whose cmdlets write no other warning, can switch to the silenced form
locally.

**Ruling R5: group PIM's reconciled pair warns in both modes.** `Resolve-OERGroupPimPolicyChange`
reconciles the MFA / authentication context pair itself, and `Set-OERGroupPimPolicy`, given the
reconciled parameters, finds nothing to reconcile and writes no warning about it
([#mfa-authcontext-exclusion](#mfa-authcontext-exclusion)). Without a handler warning a real run
would say nothing at all, so the handler writes the diff's `ConflictReason` before
`$Caller.ShouldProcess` in every mode, after the PIM-onboarding question of
[#pim-in-use-criterion](#pim-in-use-criterion). A4's purpose holds: the plan shows it and a real run
writes it once; of the five cases, it is the only one a declined engine prompt also shows.
Extension: the warning states the diff's decision, not the outcome. `Set-OERGroupPimPolicy` can still
refuse the call after it -- an authentication context the tenant does not define or has not
published, a failed policy lookup, an unreadable approval rule -- and the `Failed` row then shows that
nothing was changed. If wrong: the warning becomes `-WhatIf`-only, and a real run shows the reason
only in the row's Detail.

**Ruling R6: a time-bound group eligibility has no warning to show.** Step 3 of the group handler
writes the time-bound entries, and `Add-OERGroupEligibility` warns only for a PERMANENT eligibility
that needs the policy opened; a time-bound one never opens it. A warning that a first eligibility
onboards a group to PIM for Groups would be a new warning, not this rule.

**Rulings R10 and R11: the plan decides on the state the run would reach.** A real run reaches step 5
after step 4 of the same item has applied its changed `pimPolicy`, so the plan cannot simply trust
the live read. When step 4's gate declined a change that sets `allowPermanentEligibility` for an
access type, that value stands in for the read's: true plans no warning, false plans it when the
policy is listed (R10). Whether the policy is listed always comes from the read. Once the warning is
planned for an access type, that access type counts as open, so a later permanent entry of it plans
none: in a real run the first entry's `Add-OERGroupEligibility` opens the policy and the later ones
find it open (R11). Each access type is decided on its own. The plan assumes the open succeeds; if it
fails (`PolicyOpenFailed`), a real run warns again for the next entry of that access type, which the
plan cannot know.

**What the engine rule does not cover.** A handler decides from the inputs the cmdlet's warning uses,
not from every refusal the cmdlet can make before it. Where the real cmdlet refuses first --
`Set-OERDirectoryRoleManagementPolicy` given an authentication context id not of the `c` plus number
shape, or a live policy without the pair rule; `Set-OERRoleAssignment` not finding the assignment on
its own re-read -- the plan shows the warning and the real run the error. When a group's PIM policy
cannot be read and the document declares only an authentication context while the live rule still
requires MFA, the diff has no live MFA to see, so `ConflictReason` stays `$null` and the plan shows
nothing, while the real `Set-OERGroupPimPolicy`, which reads the rule itself, reconciles and warns
once. Under `-WhatIf` step 5 makes one policy read per changed permanent eligibility that a real
run makes inside `Add-OERGroupEligibility` anyway, so the permissions it needs are unchanged.
