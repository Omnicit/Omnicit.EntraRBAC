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
`$PSCmdlet.WriteError()` call deleted.

Related test shapes that look like guards but are not, found by audit PR9 (#34) and PR #63:
`-ErrorVariable` declared inside a `{ } | Should -Not -Throw` scriptblock never populates the outer
variable (child scope), and `Should -Invoke ... -Times N` is *at-least* semantics unless you add
`-Exactly`.

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

## static-source-gates

`tests/QA/sourcehygiene.tests.ps1` carries eight `Describe` blocks. Four machine-check a rule stated
in CLAUDE.md; the fifth checks a rule stated only in this file, the sixth checks an invariant no rule
states in prose, and the seventh (Task 6, issue #81) and eighth (Sprint 2) each machine-check a
single-ownership rule CLAUDE.md ## Code Style states. They all run off one shared `BeforeAll` that
enumerates and parses the tree once for the first six gates; the seventh and eighth each run their
own additional parse pass, kept deliberately separate from that shared walk so a mistake in new
detection logic cannot perturb the other gates' proven reachability closure or catch-clause scan.

**1. Encoding.** Every authored `.ps1`/`.psd1`/`.psm1`/`.ps1xml` under `source/` and `tests/` must
be ASCII-only and carry no UTF-8 BOM. It is a byte-level check because PSScriptAnalyzer cannot do
this job: `PSUseBOMForUnicodeEncodedFile` fires only on non-ASCII in a BOM-*less* file, so adding a
BOM inverts it to a pass; and `module.tests.ps1` hands only `source/<FunctionName>.ps1` to the
analyzer, so nothing under `tests/` and no `.psm1`, `.psd1` or `.ps1xml` is ever scanned by it. The
repo root is deliberately out of scope. There is no allow-list.

**2. Bearer scrub.** `Remove-OERErrorRecord -Record $PSItem` must be the FIRST statement of every
`catch` in a source file that reaches transport -- `Invoke-OERGraphRequest`, `Invoke-OERArmRequest`,
`Invoke-MgGraphRequest`, `Invoke-WebRequest`, `Get-AzToken`, `Connect-MgGraph` or
`Connect-AzAccount` -- directly OR transitively through any module function it calls.

Transport is detected from `CommandAst.GetCommandName()`, **never a text grep**:
`source/Private/Remove-OERErrorRecord.ps1` carries a literal `Invoke-MgGraphRequest` in its
`.EXAMPLE` block, and a grep would false-positive it into a violation.

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
intermediate variable cannot hide the same defect. Its scope control asserts the twelve scanned files
BY NAME rather than by count -- the seven `Sync-OERStructure*` handlers plus
`Read-OERStructureDocument.ps1` and the four `Resolve-OER*Change` helpers that take a `-Declared`
node -- because a bare count says only that twelve became eleven, never which file left the scan.
Two earlier rounds of that gate each claimed to cover every document consumer while missing some, so
the named list is the finding, not the tidy-up.

Every gate asserts its own non-vacuity (per-root file counts, named control files, catch-clause and
token counts, region-content checks) so a detection bug fails loudly instead of passing over an
empty collection.

## pim-beta-pin

PIM-for-Groups is deliberately pinned to the Graph `beta` endpoint. All eight call sites route
through the private `Get-OERPimGroupsGraphPath`, which owns the version constant.

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
`Invoke-WebRequest -SkipHttpErrorCheck` against `$script:_OERAuthState.ArmResourceUrl` (default
`https://management.azure.com`) with an `Authorization: Bearer` header. The token plaintext is
materialized only at the request boundary and cleared in a `finally`; the transport `catch` scrubs
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
`^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$` regex inline.

The deliberate exception is the wider `-as [guid]` cast in `Get-OERInventory` and `New-OERGroup`,
which intentionally also accepts braced, parenthesised and dash-less forms that `Test-OERGuid`
rejects. Do not migrate those two call sites to `Test-OERGuid`.

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

The fix is a rule ordering applied in `Set-OERGroupPimPolicy` immediately before the patch loop --
the loop is where transport sequencing belongs. When the rule set carries both rules, they are
ordered by what the authentication-context rule DOES: `isEnabled = $false` goes FIRST, `isEnabled =
$true` goes LAST. Every other rule keeps its emitted position. The ordering is deliberately NOT in
`New-OERPimRuleSet`: that helper is a pure, shared builder owning rule SHAPE, and a rule set built
for a different transport must not inherit this transport's sequencing.

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
   `-IncludeARM` is set, a valid cached ARM token, it returns immediately with no network call and
   no prompt.
2. **Graph token** -- `Get-AzToken -Resource 'https://graph.microsoft.com/'`, wired into
   `Connect-MgGraph -AccessToken` as a SecureString.
3. **ARM token (optional)** -- with `-IncludeARM`, a second `Get-AzToken` acquires
   `https://management.azure.com/`. See [#arm-transport](#arm-transport) for why the result is used
   directly rather than through Az.Accounts.
4. **Cache** -- `$script:_OERAuthState` holds `TenantId`, `AuthMethod`, `ClientId`, `Account`,
   `GraphTokenExpiry`, `ArmTokenExpiry`, `ClaimsSatisfied`, plus `TokenTenantId` and
   `ArmTokenTenantId` (below).
5. **ACRS step-up** -- see [#graph-wrapper](#graph-wrapper) item 2.

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
change session-reuse semantics module-wide. The granted values are **evidence**, not keys.

`Initialize-OERAuth` raises a terminating `TenantMismatch` when the two disagree, before
`Connect-MgGraph` runs and before `$script:_OERAuthState` is rebuilt (and, for ARM, before the token
is cached), so a refused token never becomes a usable session and never leaves a half-built one
behind -- the same two-sided placement rule the `AppOnlySessionCredentialUnavailable` check follows.

**The comparison is gated on both values being canonical GUIDs**, via `Test-OERGuid`. That gate is
the whole difficulty: the requested tenant is very often a verified domain
(`contoso.onmicrosoft.com`) while a token always carries a GUID, so an unconditional comparison
would reject almost every real sign-in. It also excludes `'organizations'` and the empty string
structurally -- neither is a GUID -- so no separate term for either exists; a term no input can
falsify cannot be mutation-proved. When the request named a domain the mismatch is simply not
detectable from the token alone, and nothing is inferred: the granted value is recorded and left to
speak for itself.

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
2.7's child printed `true`. That is why the row keeps its label on both halves.

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
own tenant when it cannot -- which is precisely the shape the post-call warning exists to catch. The
2026-09-15/16 run therefore did NOT exercise that failure mode, because the account turned out to
have an identity in tenant B as well, contrary to the checklist's own stated prerequisite. The check
that would settle it is a device-code sign-in naming a tenant the completing account genuinely has
no identity in, with the completing account recorded. It is not run here: SECURITY rule 1 keeps
every live check in the operator's own hands.

**Why the pre-call warning is ClientSecret-only, and why it needs its own tracker.** Only
ClientSecret can be PREDICTED before the call: DECOMPILED, AzAuth's reuse predicate (same
credential type and a matching client id) is knowable from the module's own inputs before
`Get-AzToken` is ever invoked, so the module can warn ahead of the call instead of only
interpreting its result afterward -- prediction works because the predicate is known, not because
the refusal is fast. Separately, MEASURED: the refusal itself then happens in about 0.01 seconds
with zero network requests sent, which confirms the reused credential is never given a chance to
reach the wire; it is corroborating evidence, not the reason prediction is possible. DeviceCode and
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

**Why the post-call warning compares GRANTED tenants.** For a tenant named by domain, the granted
tenant is the only signal there is: the existing GUID-only `TenantMismatch` guard cannot compare a
domain against the GUID a token carries. MEASURED: every device-code request goes to
`organizations` whatever tenant was named, a managed-identity request is byte-identical for any
tenant, and a client-secret credential reused under the multitenant-disable switch silently sends
to the PREVIOUS tenant. INFERRED, since no token can be issued offline: a device-code token is
therefore issued for the signing-in account's own tenant and a managed-identity token for the
identity's own tenant, so a switch made with either -- or with that reused client-secret credential
-- comes back issued by the SAME tenant as before, under the new label, which is exactly the shape
the check looks for. (The device-code half of that inference is weakened, though not withdrawn, by
the RECORDED OBSERVATION above.) A second inference used to sit here, and the live run has since
split it in two. DECOMPILED, and still standing: a device-code credential reused after a SUCCESSFUL
earlier sign-in first attempts silent reacquisition for the REQUESTED tenant. CONTRADICTED BY
MEASUREMENT: the fall-back to a new device code, "only when that needs interaction", does not
happen -- live, that call never returns at all (further finding 1 below). The reassurance that used
to be drawn from it -- that such a switch may in fact reach the new tenant, and the check then stays
silent by design -- is therefore withdrawn. The same inference is repeated in
`Initialize-OERAuth.ps1`'s comment above this check; this paragraph is the record that governs.

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
carries no `tid` claim at all, and such a token would make the post-call comparison read back the
tenant it was asked for rather than one the token claims to be issued for. What the measurement
settles: the post-call warning rests on a measured property rather than a decompiled one, and every
conditional `Expect:` in the live-verification checklist that hung on this question is grounded.

**The ARM half.** MEASURED live, 2026-09-16, checklist 5.4 -- a managed identity sign-in with
`-IncludeARM` whose switch did not take effect: `ArmTokenTenantId` equalled `TokenTenantId`, so the
ARM token was in the same state as the Graph token, issued by the same tenant. The post-call warning
itself reads only the GRAPH token, since it runs before the ARM token is acquired; that is why its
text names both transports, carrying the ARM half by WORDING rather than by a second warning or a
second measurement. Read that measurement at its own width: it is managed identity. On the three
delegated types the ARM acquisition passes no client id and so builds its own credential (further
finding 2 below), which makes it a separate sign-in whose tenant this check never observes -- it may
reach the requested tenant, repeat the granted one, or land on a third. The ARM half's only tenant
check of its own remains the GUID-only `TenantMismatch`, equally blind to a request that named its
tenant by domain.

**Both warnings stop the sign-in under `-WarningAction Stop`.** Like the module's existing ambient
`AZURE_AUTHORITY_HOST` warning, a caller running with `-WarningAction Stop` or
`$WarningPreference = 'Stop'` turns either `Write-Warning` call into a terminating error at that
point: the pre-call warning stops before any token is requested, and the post-call warning stops
before `$script:_OERAuthState` is rebuilt, i.e. before the session is created.

**The post-call warning's two benign shapes, and why `'organizations'` is not excluded as a
previous label.** The check's own terms are satisfied by two situations that are not failures:

- two names for the same tenant, such as a verified domain and that tenant's own
  `...onmicrosoft.com` name;
- a previous session that named no tenant at all (recorded as `'organizations'`), followed by a
  sign-in naming that same tenant's own domain -- for example `Connect-OER -Interactive` (or
  `-ManagedIdentity`) with no `-TenantId`, then the same again with `-TenantId <that tenant's
  domain>`.

Both are answered by the warning's own sentence, which names the requested tenant and the granted
tenant in place of "new" and "granted" and says the switch is expected if the former is a name of
the latter. `'organizations'` is deliberately NOT excluded as a previous label, because the
failure this check exists to catch has exactly that shape: a device-code sign-in naming no tenant
at all, followed by `-TenantId <a customer's domain>`, still issued by the operator's own home
tenant (the INFERRED device-code behaviour in the table above). Excluding `'organizations'` would
silence precisely the case the check was built for.

**The tracker, and why it survives `Disconnect-OER`.** The post-call check compares against a
dedicated `$script:_OERLastIssuedSession` tracker (`TenantId`, `TokenTenantId` only), written right
after `$script:_OERAuthState` is rebuilt -- so only a session that was ACTUALLY established is ever
recorded, never a token `TenantMismatch` refused, nor a failed `Get-AzToken` or `Connect-MgGraph`
call, each of which terminates before that point is reached. `Disconnect-OER` deliberately does NOT
clear it, for the same reason `$script:_OERLastAuthorityHost` and `$script:_OERLastTokenRequest`
survive it: disconnecting before connecting to the next customer is the most natural way to switch
tenants, and it is what `Connect-OER`'s own help recommended before this check existed ("To sign in
as a different account or tenant, run `Disconnect-OER` first"). MEASURED: AzAuth's credential is
process-wide and nothing `Disconnect-OER` can reach clears it. A check that instead read
`$script:_OERAuthState` -- which `Disconnect-OER` DOES clear -- would therefore have gone silent on
exactly the switch pattern the module's own former help text recommended.

A request that names NO tenant is now excluded as well, a DIFFERENT case from the previous-label
`'organizations'` shape above: this exclusion is on the CURRENT request naming no tenant
(`$EffectiveTenant -eq 'organizations'`), not on a previous one. There is no switch that could have
failed to take effect when the caller asked for no particular tenant at all. Before this tracker
existed the case could not even arise: a request with no tenant against a live
`$script:_OERAuthState` session inherited that session's own tenant, so `$EffectiveTenant` was never
`'organizations'` while a real session was live. Through the tracker it now can arise, right after
`Disconnect-OER`, so the exclusion is a NEW term, not a restatement of the old one. The
previous-label `'organizations'` case -- where the PREVIOUS session named no tenant and THIS one
names a domain -- is untouched by this exclusion and still warns, on purpose.

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
own session state) and calls `Disconnect-MgGraph`/`Disconnect-AzAccount`; reading its source shows
it never touches AzAuth's credential at all, so it was never capable of clearing it. Decompiling
AzAuth shows the only call site that clears the static credential is `Get-AzToken`'s own `-Force`
handling.

**The unverified case, and the proposed fix.** The pre-call warning never applies to DeviceCode or
ManagedIdentity at all -- it is ClientSecret-only at the predicate level, as above. So the only
warning that could ever catch a DeviceCode or ManagedIdentity sign-in naming a tenant by DOMAIN is
the post-call one, and it needs a PREVIOUS entry in `$script:_OERLastIssuedSession` to compare
against. That tracker survives `Disconnect-OER` (previous section), so what remains unverified is
narrower than "no previous session": only the very FIRST sign-in in a PowerShell process, and the
first sign-in after Omnicit.EntraRBAC itself is re-imported -- which resets the tracker along with
the rest of the module's scope, even though AzAuth's own credential is MEASURED to survive a
re-import of AzAuth -- go unchecked. (The module-reimport half of that limit is INFERRED from
PowerShell module scoping, not executed; the AzAuth-credential-survives-reimport half is MEASURED.)
Resolving the named domain to its tenant ID via the cloud authority's OpenID discovery document
before the call would close even that gap, by turning a domain request into the GUID request the
existing `TenantMismatch` guard already covers. That is a NEW network call on every sign-in, which
is why it is proposed here and not built in this branch.

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

**`Az.Accounts` took its place in `RequiredModules.psd1` for a TEST reason, not a runtime one.**
`tests/Unit/Public/Disconnect-OER.Tests.ps1` mocks `Disconnect-AzAccount`, and Pester's `Mock`
requires the command to exist: with `Az.Resources` gone and nothing else pulling `Az.Accounts` in,
every `It` in that file would fail in `BeforeEach`. The mock does second duty locally, since without
it the test would tear down the operator's real Az context and on-disk token cache -- the context
used for the manual live verification this module's security rules require. It is deliberately NOT
added to the manifest: a test-environment need is not a consumer's need.

**Left alone deliberately:** `Disconnect-OER` still calls `Disconnect-AzAccount` when the command
resolves, even though the module never created that session. Signing out a session you did not
establish is arguably wrong, and it is a separate question from this one -- raised, not decided,
and not changed here.

Nothing in `RequiredModules.psd1` is bundled into a build artefact.
 The built module under
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

**Why the floor exists, and why it is not redundant with the non-empty assertion.** For a completely
empty `[Unreleased]` section `Get-ChangelogData` does NOT return `$null`: it returns the 17-character
string `## [Unreleased]\n\n`. Verified by execution against a synthetic changelog, with these
consequences, all confirmed by running them:

- the pre-existing `RawData | Should -Not -BeNullOrEmpty` **passes** on that section, so it does not
  see the empty shape at all;
- the old ceiling-only `-BeLessOrEqual 8000` **passes** on it too -- it is blind to the empty shape,
  which is the OPPOSITE failure from the oversize section it was added for and which it catches
  correctly. It is not an inert guard, and it does not belong in this repo's ledger of those;
- the `-BeGreaterOrEqual 500` floor **fails** on it.

`$null` comes back only when the `## [Unreleased]` heading is missing altogether, which the non-empty
assertion does catch. The two assertions genuinely split the space; neither is redundant. The more
familiar framing -- `$null.Length` is the integer `0`, so a bare length check passes silently -- is
true in general and is what the in-code comment says, but it is not the mechanism here, and the
17-character measurement is the sharper fact.

**What `tests/QA/module.tests.ps1` asserts, as of this branch.** Source side: `[Unreleased]` is at
least 500 and at most 4,000 characters. Artefact side: the built manifest carries a
`PrivateData.PSData.ReleaseNotes` key, non-empty, at least 500, and strictly less than 10,000; plus a
tail compare -- the last 400 characters of the published notes must equal the last 400 characters of
the source `[Unreleased]` body, `-BeExactly`, after `TrimEnd()`. Truncation always removes the END,
so a tail compare cannot be fooled by it; this was falsified against a value cut at 900 characters,
comfortably inside every length bound and therefore invisible to all of them, and the tail compare
caught it. Finally, the "changelog has been updated" diff rule fires only when a changed path matches
`^source/`: a customer-facing document is not served by an entry forced out of a docs-only PR.

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
`ReleaseNotes` -- which is the #39 defect. The benefit today is zero, since `build.yaml` deliberately
defines no `publish` workflow. And B's desired OUTPUT -- a short blurb plus a link rather than the
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
`feature:` block's `f(eature(s)?)?[\/-]` regex -- measured, that is `feature/`, `feature-`,
`features/`, `features-`, `f/` and `f-`. **The regex is unanchored, so it tests the WHOLE branch
name, not the prefix**, and it beats the `hotfix:` block when both match: `chore/feature-flags`,
`feat/f-x` and `fix/feature-parity` all take the `Minor` default, and all three are conventional
names under the prefix table in `CLAUDE.md`. `feat/` alone does not match, since `feat` is neither
`f` nor `feature` followed by a separator. So no branch PREFIX this repo's convention produces gets
the `Minor` default, but a name carrying `feature/`, `feature-`, `features/`, `features-`, `f/` or
`f-` anywhere in it does. The separator is part of the match, not decoration: measured against a
`v0.9.0` ancestor, `chore/feature`, `chore/features`, `chore/featurex` and `chore/xfeature` all
compute `0.9.1`, while `chore/feature-flags` computes `0.10.0`.

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
| no tag, branch `xrelease/2.0.0`, `my-release/2.0.0`, `chore/release/2.0.0` or `pre-release-2.0.0` | `0.8.0` on all four -- unlike `feature:`, the `release:` regex is ANCHORED at the START of the branch name |
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
| `v0.9.0` ancestor on `f/x`, `features/x`, `feature-x` | `0.10.0` on all three -- the `feature:` regex is unanchored, so several spellings reach the `Minor` default; `feat/` is not one of them |
| `v0.9.0` ancestor on `chore/feature-flags`, `feat/f-x`, `fix/feature-parity` | `0.10.0` on all three -- the regex tests the WHOLE name, so conventional names under this repo's own prefixes reach the `Minor` default, and `feature:` beats `hotfix:` when both match |
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

**The blast radius is narrow, and measured.** Unlike the `feature:` regex, `release:` is ANCHORED at
the start of the branch name: `xrelease/2.0.0`, `my-release/2.0.0`, `chore/release/2.0.0` and
`pre-release-2.0.0` all compute `0.8.0`, and so does this repo's own historical
`chore/release-blockers`. A matching name with no parsable version (`release/blockers`) is harmless
too -- it changes the prerelease label to `beta` and leaves `next-version` standing. None of this
repo's own prefixes carry the hazard either: `fix/2.0.0`, `hotfix/2.0.0`, `feat/2.0.0`,
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
Step 5 is not done and is not planned: `1.0.0` is published by hand, so `build.yaml` still defines no
`publish` workflow.
