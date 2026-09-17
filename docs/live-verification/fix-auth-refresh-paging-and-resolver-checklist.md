# Live verification checklist -- auth refresh, paged reads and the access package resolver (issues #71, #72, #73, #75)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened. A recorded observation is the deliverable there -- do
not substitute a guess.

**Three box states, and the middle one is the point of this file.** `- [x]` is a check that ran and
whose evidence supports it. `- [ ]` is a check that has not been run. `- [~]` is a check that
EXECUTED cleanly and still proves nothing, because the tenant held no data for it to measure -- a
count of `0` compared against another count of `0` is a vacuous pass, and ticking one would record
a verification that did not happen. A `- [~]` box is a debt, not a failure of the code. Sprint 3's
run produced three of them and the operator initially reported them as passes; that is exactly the
mistake this state exists to prevent.

**Every `Expect:` in this file was traced to a real property in a real converter, or to a real line
of a real code path, before it was written.** Three of Sprint 3's checks could not fail: two asked
`Format-List`/`Select-Object` for properties that do not exist (`Format-List` ignores an unknown
property name silently) and one read a path the cmdlet never writes. A checklist is code and has
the same defect class as a guard-shaped-but-inert test, so where a carried-forward check's
expectation turned out to be wrong against current source it is marked **CORRECTED** and the reason
is written under it.

---

## What this file is, and what it replaces

This is the consolidated checklist for branch `fix/auth-refresh-paging-and-resolver` (Sprint 4,
issues #71, #72, #73, #75). It also **absorbs the 29 unticked checks of
`docs/live-verification/feat-pipeline-binding-and-converter-ownership-checklist.md`** (PR #64),
which has stood at 59 of 88 ticked since 2026-08-26.

The reason for consolidating is arithmetic, not tidiness. Most of PR #64's 29 unticked checks are
the S1-S9 block that builds a MULTI-STAGE access review over an access package with a delivered
assignment, plus the sections 6 and 7 that hang on it. This sprint's own checks need the SAME
tenant set-up: an access package, an assignment policy, a delivered assignment, and a paged read.
Two checklists would mean building that twice, which is precisely why PR #64's has never been run.
Section 2 below builds it once and everything else uses it.

PR #64's file keeps its ticked history -- it is the verification record for what WAS run in that
sprint -- and carries a superseded banner pointing here. Its 59 ticked boxes are not re-run.

## Order

Run top to bottom in one connection.

1. **Section 1 first, before the tenant set-up.** It is the one check whose ANSWER becomes a
   one-line source change that has to land in this PR before merge.
2. **Section 2** builds the shared tenant objects. Several of its steps wait on Microsoft Graph and
   cannot be hurried.
3. **Sections 3 and 4** are read-only. Nothing in them writes to the tenant.
4. **Section 5** is the write set. Every destructive step is run with `-WhatIf` first and the plan
   is read before the switch comes off. Two steps in it create real objects; both are torn down in
   section T.
5. **Chapter U comes BEFORE section T, even though it is printed after it.** It is the re-run set
   added after the 2026-09-11 pass, it needs a build at or after commit `72b3477`, and every one of
   its four checks reads objects section 2 built -- `oer-live-pim`, `OER-CAT-A`, `oer-live-res`,
   `oer-live-ap`. Teardown removes those, so running T first makes U unrunnable. U.3 also removes
   and then re-creates `oer-live-ap2` and its policy, which T then clears. Do not run U against an
   older build: U.1 and U.3 would both reproduce the pre-fix failure and prove nothing.
6. **Section T** is teardown, run after chapter U. **Section S** is the sign-off.

## Redact before you commit

Read `docs/live-verification/README.md` first. The rules that bite here:

- Every tenant identifier pasted into a `Result:` block becomes
  `00000000-0000-0000-0000-0000000000NN`, counting up from `01` per DISTINCT identifier in
  first-appearance order, restarting in this file. Access package ids, assignment policy ids,
  assignment ids, principal ids, access review definition/instance/stage ids, subscription ids,
  role management policy ids, group object ids, tenant ids and application (client) ids -- all of
  them. An abbreviated id is redacted too, and is written out as the FULL placeholder.
- Email addresses outside `example.com`/`contoso.com` become `person1@example.com`,
  `person2@example.com`, ... on the same per-file, first-appearance rule.
- **No credential ever goes in.** Section 3 connects an app-only session; its client secret or
  certificate password never appears in this file, not even shaped like a placeholder. Checks 3.7
  and 3.8 print error records, and a rendered `ErrorRecord` whose `TargetObject` is an
  `HttpRequestMessage` prints the bearer token in full. If one is ever seen, that is a finding:
  record the FACT, the file and the line, never the value, and rotate the secret that minted it.
- **Display names of test objects may stay.** `oer-live-ap`, `oer-live-pim`, `oer-live-ar-multistage`
  and the rest are names this checklist created and are what make it readable.

`tests/QA/dochygiene.tests.ps1` fails the gate on a violation and reports file and line without
printing the value. It is a backstop, not a substitute for redacting as you write.

### The placeholder table -- fill it in as you go

Keep this filled in as you run, so a later reader can follow which id is which. Write only
placeholders here, never a real value, and never the mapping between them.

**The rows are in FIRST-APPEARANCE order**, which is what `README.md` requires and what makes the
numbering reproducible while you fill results in. Run the file top to bottom and the ids arrive in
this order.

| Placeholder | What it is | First appears in |
|---|---|---|
| `00000000-0000-0000-0000-000000000001` | access package `oer-live-ap` id | 2.2 |
| `00000000-0000-0000-0000-000000000002` | assignment policy id (`$PolicyId`) | 2.2 |
| `00000000-0000-0000-0000-000000000003` | a delivered assignment's own id | 2.3 |
| `00000000-0000-0000-0000-000000000004` | the assignee's object id (`TargetId`) | 2.3 |
| `00000000-0000-0000-0000-000000000005` | multi-stage review definition id (`$DefId`) | 2.5, captured 2.6 |
| `00000000-0000-0000-0000-000000000006` | recurring review definition id (`$RecDef.Id`) | 2.5 |
| `00000000-0000-0000-0000-000000000007` | review instance id (`$InstId`) -- **NOT ALLOCATED on the 2026-09-11 run**; see the rows-05-and-07 note below | 2.7 |
| `00000000-0000-0000-0000-000000000008` | review stage id (`$StageId`) | 2.8 |
| `00000000-0000-0000-0000-000000000009` | PIM-onboarded group `oer-live-pim` id -- **and the same value is 3.1's `$NotAPackage`** | 3.1, reused 4.7 |
| `00000000-0000-0000-0000-000000000010` | subscription id (`$Sub`) | 5.1 |
| `00000000-0000-0000-0000-000000000011` | role management policy id | 5.1 |

**Row 09 is deliberately ONE row for what reads like two things.** Check 3.1 needs a GUID that is
syntactically valid and is not an access package, and suggests `oer-live-pim`'s object id because it
is already to hand; check 4.7 reads that same group's PIM policy. It is one identifier, so it gets
one placeholder -- `README.md` is explicit that the same identifier always gets the same placeholder
within a file, and several checks turn on two ids being equal or different. If you use a different
GUID at 3.1, split this into two rows and renumber the rest.

**One id in this file is a literal VALUE, not a redaction, and is deliberately absent from the table
above:** `00000000-0000-0000-0000-000000000099` in check 3.7. It is a deliberately non-existent
instance id sent to Graph on purpose, so it replaces nothing and needs no `NN` slot. Keep it out of
the sequence.

**Thirteen more identifiers arrived with the 2026-09-11 run, and they are APPENDED rather than
interleaved.** The eleven rows above keep their numbers: renumbering them would break the prose
under the table -- row 09's two-uses-one-row rule above all -- and the whole point of the numbering
is that a later reader can follow it. Rows 12-15 were reserved while the run was being prepared;
rows 16-24 were allocated during the redaction pass, in the order the values first appear in this
file. **Strict first-appearance order therefore holds for 01-11 and again for 16-24, but NOT across
the 12-15 block** -- row 12 in fact first appears in 2.2, earlier than rows 10 and 11. That was the
right trade against renumbering eleven rows and the prose that names them; the "First appears in"
column is what a reader follows, not the number.

| Placeholder | What it is | First appears in |
|---|---|---|
| `00000000-0000-0000-0000-000000000012` | catalog `OER-CAT-A` id (`CatalogId` column) | 2.2 |
| `00000000-0000-0000-0000-000000000013` | group `oer-live-res` object id -- the `originId` half of every binding key `'<role>\|<originId>'` in 5.11 and 5.12 | 5.11 |
| `00000000-0000-0000-0000-000000000014` | access package `oer-live-ap2` id, created by 5.10's first apply | 5.10 |
| `00000000-0000-0000-0000-000000000015` | application (client) id of the tenant's STANDING app registration for this module -- what 3.11 fell back to on 2026-09-11; **NOT `oer-live-apponly`, which is row 26** | 3.11 |
| `00000000-0000-0000-0000-000000000016` | tenant id | 3.11 |
| `00000000-0000-0000-0000-000000000017` | service principal object id of the same app registration -- the object 3.11 disables and re-enables | 3.11 |
| `00000000-0000-0000-0000-000000000018` | Graph `request-id` on 3.11's FIRST 401 | 3.11 |
| `00000000-0000-0000-0000-000000000019` | Graph `client-request-id` on 3.11's FIRST 401 | 3.11 |
| `00000000-0000-0000-0000-000000000020` | Graph `request-id` on 3.11's SECOND 401 | 3.11 |
| `00000000-0000-0000-0000-000000000021` | Graph `client-request-id` on 3.11's SECOND 401 | 3.11 |
| `00000000-0000-0000-0000-000000000022` | access review decision id | 4.1 |
| `00000000-0000-0000-0000-000000000023` | the RECURRING review's instance id -- **a different value from row 06, its definition id** | 4.5 |
| `00000000-0000-0000-0000-000000000024` | the role-definition segment of `oer-live-pim`'s member PIM policy id (`Group_<row 09>_<row 24>`) | 4.7 |
| `00000000-0000-0000-0000-000000000025` | access package `oer-live-ap2` id, created by U.3 -- **a DIFFERENT object from row 14** | U.3 |
| `00000000-0000-0000-0000-000000000026` | application (client) id of `oer-live-apponly`, the app U.4 signed in as -- **a DIFFERENT registration from row 15** | U.4 |

**Row 25 is appended by chapter U's run, and it is NOT row 14 repointed.** Rows 14 and 25 carry the
same display NAME, `oer-live-ap2`, and nothing else: row 14's object was created by 5.10's first
apply and was DELETED at the top of U.3 (`still present: 0`), and U.3 then created a new access
package that Graph gave a new id. Two objects, two identifiers, two placeholders -- `README.md` is
explicit that the numbering exists so a reader can tell ids apart, and collapsing these onto one row
would assert an identity that is false. Row 14's real value no longer appears anywhere in this file;
the row stays in the table because 5.10's write-up above still refers to it. The thirteen-rows
sentence above describes the 2026-09-11 pass and is left as it was -- **rows 25 and 26 arrived with
chapter U**, on 2026-09-12 and 2026-09-13, which is what their "First appears in" column says.

**Rows 15 and 26 are TWO DIFFERENT APP REGISTRATIONS, and row 26 is not row 15 repointed.** Row 15 is
the tenant's standing registration for this module. Check 3.11 used it on 2026-09-11 because
`Initialize-OerS4Prereq.ps1` had never been run with `-IncludeAppOnly` and `oer-live-apponly` did not
exist yet, so there was nothing else to sign in as. Row 26 is `oer-live-apponly`, created afterwards
by the prereq script and used by check U.4 on 2026-09-13. Two registrations, two client ids, two
placeholders -- the same rule that keeps rows 14 and 25 apart, and it is here for the same reason: a
reader comparing 3.11's run with U.4's must be able to see that they signed in as different
applications, which is most of why one probe met a propagation delay the other did not.

**3.11's prompt text is misleading for that run, and it is left as the operator typed it.** The
`Read-Host` label reads `oer-live-apponly application (client) id`, but the `displayName` printed two
lines below it is the pre-existing registration -- rendered in the result block as
`<the module's own pre-existing app registration -- REDACTED>` -- and 3.11's own verification note
says the same thing in full, including that `-IncludeAppOnly` was never passed. Read the printed
`displayName`, never the prompt label. U.4's prompt label says only `app-only application (client)
id` and carries no such trap.

**Row 17 belongs to row 15's app and stays unambiguous.** It is the service principal object id of
the standing registration -- the object 3.11 disables and re-enables. U.4 disables and re-enables
`oer-live-apponly`'s service principal too, but it never PRINTED that id: its transcript interpolates
`$($Sp.id)` into the URI and the value never reaches the output. There is therefore no second service
principal id in this file and no row to allocate for one. T.2 says what both registrations leave
behind.

**Rows 18-21 are Graph correlation ids, not tenant objects.** They identify a request, not a
directory object, and they are redacted anyway: the gate matches a GUID shape, and a correlation id
pasted beside a real 401 is still a value this repository has no reason to carry.

**ROWS 05 AND 07 ARE THE SAME IDENTIFIER HERE, and that is a `OneTime`-SPECIFIC behaviour -- not a
property of access reviews in general.** Measured on the 2026-09-10 setup run and confirmed by check
2.7 (`SameValue = True`): `oer-live-ar-multistage` is a `OneTime` review, and Graph gave its single
instance **the same id as the definition**. That is not a bug and not a copy/paste slip.
`README.md` is explicit that the same identifier always gets the same placeholder within a file, so
where they are equal, **row 07 is not allocated at all** -- `00000000-0000-0000-0000-000000000005`
is written everywhere the one-time review's instance id appears. Allocating two placeholders for one
id would make 2.9, 3.7, 4.1, 4.2 and 4.4 read as though they were addressing two different objects.

**The recurring review is the counter-example, and it is why row 23 exists.** Check 4.5 read
`oer-live-ar-recurring`'s single instance and its id **differs** from that definition's id (row 06),
so it is a distinct identifier and carries its own placeholder. Read rows 05/07 as "a `OneTime`
review's instance reuses its definition's id on this tenant", never as "an instance id equals its
definition id".

**And three UPN slots, on the same first-appearance rule as the ids.** All three first appear
together in the session block, in this order: `person1@example.com` is `<assignee-upn>` (`$Assignee`,
the holder of the delivered assignment 1.1, 4.6 and 5.2 read), `person2@example.com` is `<upn>`
(`$Assignee2`, 5.2's intended second target -- see finding F-E for why it never bound), and
`person3@example.com` is `<reviewer-upn>` (`$Reviewer`, 2.4, 5.4, 5.6, 5.7 and 5.8).
**The tenant's own `onmicrosoft.com` domain is not `example.com`** -- an address in it is a real
address and is redacted like any other. **The domain itself is not written out here either**, and
that is the point of the rule rather than an excess of it: this file names the test accounts by
display name a few lines up, so domain plus display name reconstructs all three of the addresses the
placeholders above were allocated to hide. Only the display NAMES (`oer-live-assignee` and the rest)
may stay.

## What changed on this branch, and why a mocked suite cannot settle it

Four issues, all of them in places a mocked test can only prove intent.

- **#75 -- the 401 detection read a member the real exception does not have.** The token-rejected
  branch of `Invoke-OERGraphRequest` now takes its status from `Get-ResponseFactFromException`
  first (the same helper the throttle path uses) and falls back to `.Response.StatusCode` only when
  that returns nothing. A mocked test can build either exception shape; only a real Graph 401
  proves which shape actually arrives, that the silent refresh happens exactly ONCE, and that an
  app-only session gets a clear error instead of a browser prompt.
- **#73 -- a failure on page N no longer discards pages 1..N-1.** A failed `-All` walk now carries
  `PartialValue`, `NextLink` and `PageNumber` on the thrown **Exception** (never on the ErrorRecord
  -- a note property on an ErrorRecord does not survive a `throw`). The call still fails; this only
  lets an opted-in caller recover what was already read.
- **#71 -- a GUID handed to `-AccessPackage` is no longer trusted blind.** `Resolve-OERAccessPackageId`
  now issues one existence read (`GET accessPackages/{id}?$select=id`) and throws
  `AccessPackageNotFound` for an id no package has, instead of handing the bad id on and letting
  every caller return an empty collection. Ten call sites were changed in the same sprint so a 403
  or an exhausted 429 from that read surfaces AS ITSELF rather than as "not found". The cost is one
  extra request per id-shaped value, and section 3 measures it.
- **#72 -- the `-State` filter's casing is UNVERIFIED.** `[ValidateSet]` is case-insensitive, so
  whichever spelling the caller types is what goes on the wire. Microsoft Learn's example writes
  `state eq 'Delivered'`; whether entitlement management compares it case-sensitively is not
  documented anywhere. Section 1 settles it.

**Every test on this branch mocks the transport.** They prove the module BUILDS the intended
request and REACTS correctly to a supplied response. They prove nothing about what real Graph sends
back.

---

## Open the session (paste once, before section 1)

This block is mechanics, not a check. It rebuilds the branch, imports whatever version folder the
build landed in, connects, and defines the one helper the request-counting checks use.

> **Do not hardcode a module version in the import line.** PR #64's checklist carried
> `output/module/Omnicit.EntraRBAC/2.0.0/...`, which was already wrong when it was written and is
> wronger now: Task 1 of this sprint moved the computed version to **0.10.0**, and it will move
> again. `Import-OerBuild` below finds the newest manifest under `output/module` whatever it is
> called, and prints the version it actually loaded as the tell.

```powershell
$Repo   = 'C:\Git\Omnicit.EntraRBAC'
$Alias  = 'Omnicit'
$Vault  = 'C:\Obsidian\Philip Obsidian\Notes\Omnicit Entra RBAC'
$S4     = Join-Path $Vault 'Initialize-OerS4Prereq.ps1'
$LogDir = Join-Path ([System.IO.Path]::GetTempPath()) 'oer-sprint4-live'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType Directory -Path './live' -Force | Out-Null

# The names the prereq script created. Every one of them is an object THIS sprint made; nothing
# below names a pre-existing object in the tenant.
$Catalog    = 'OER-CAT-A'
$ResGroup   = 'oer-live-res'
$Package    = 'oer-live-ap'
$PolicyName = 'oer-live-ap-policy'
$PimGroup   = 'oer-live-pim'
$Assignee   = 'person1@example.com'
$Assignee2  = 'person2@example.com'
$Reviewer   = 'person3@example.com'

function Import-OerBuild {
    $Psd1 = Get-ChildItem (Join-Path $Repo 'output\module\Omnicit.EntraRBAC') -Recurse -Filter 'Omnicit.EntraRBAC.psd1' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Remove-Module Omnicit.EntraRBAC -Force -ErrorAction SilentlyContinue
    Import-Module $Psd1.FullName -Force
    $M = Get-Module Omnicit.EntraRBAC
    '{0} {1}  built {2:yyyy-MM-dd HH:mm}  branch={3}' -f $M.Name, $M.Version, $Psd1.LastWriteTime,
        (git -C $Repo branch --show-current)
}

# Counts the requests a command actually issued, by reading the wrapper's own per-request verbose
# line ("[Invoke-OERGraphRequest] GET <uri>") off stream 4. Pass -Verbose INSIDE the scriptblock.
# Used by 3.3, 3.4, 3.6, 4.6 and 5.10; nothing here depends on a preference variable.
function Measure-OerRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Script, [string]$Label = '')
    $Lines  = [System.Collections.Generic.List[string]]::new()
    $Output = [System.Collections.Generic.List[object]]::new()
    & $Script 4>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.VerboseRecord]) { $Lines.Add([string]$_.Message) }
        else { $Output.Add($_) }
    }
    $Requests = @($Lines | Where-Object { $_ -match '^\[Invoke-OERGraphRequest\] (GET|POST|PATCH|PUT|DELETE) ' })
    [PSCustomObject]@{
        Label        = $Label
        RequestCount = $Requests.Count
        ExistsReads  = @($Requests | Where-Object { $_ -match '/accessPackages/[^/?]+\?\$select=id$' }).Count
        Pages        = @($Lines | Where-Object { $_ -match 'Fetching page ' }).Count
        Refreshes    = @($Lines | Where-Object { $_ -match 'Token rejected .* Forcing re-authentication' }).Count
        OutputCount  = $Output.Count
        Output       = $Output.ToArray()
        Requests     = $Requests
        Verbose      = $Lines.ToArray()
    }
}

cd $Repo
./build.ps1 -Tasks build
Import-OerBuild
Connect-OER -TenantAlias $Alias -IncludeARM

# The ids. Resolved from the objects the prereq script created, so nothing below has to be typed
# by hand -- and so a re-connect in a fresh session restores the whole set in one paste.
$ApId        = (Get-OERAccessPackage -DisplayName $Package).Id
$PolicyId    = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId |
                    Where-Object DisplayName -eq $PolicyName)[0].Id
$NotAPackage = (Get-OERGroup -Group $PimGroup).Id
$DefId       = (Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage').Id
$RecDefId    = (Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-recurring').Id
$Inst        = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages
$InstId      = @($Inst)[0].Id
$StageId     = @($Inst.Stages | Where-Object { $null -ne $_ })[0].AccessReviewStageId
$Sub         = @(Get-OERSubscription)[0].SubscriptionId
[pscustomobject]@{ ApId = $ApId; PolicyId = $PolicyId; NotAPackage = $NotAPackage; DefId = $DefId
                   RecDefId = $RecDefId; InstId = $InstId; StageId = $StageId; Sub = $Sub } | Format-List
```

`-IncludeARM` is needed only by check 5.1. Everything else is Graph-only.

**Run `Initialize-OerS4Prereq.ps1` before any of this** -- `& $S4 -WhatIf` to read the plan, then
`& $S4`, and do not start section 1 until its verify phase reports **0 FAIL**. Every object section 2
asks for already exists once it has run, so **section 2's steps below are CONFIRMATIONS, not
creations**. Run them anyway: they are what put the ids on the record, and 2.7's wait is a real
measurement even when the instance is already there.

**Record the module version the tell printed here, so every result below is attributable to a
build:** ______________________

---

## 1. The merge blocker (issue #72)

**Nothing else in this file changes source. This one does.** Check 1.1 has three possible outcomes
and each names a specific edit to
`source/Public/Get-OERAccessPackageAssignment.ps1`. **Merging this PR without running check 1.1
would have closed issue #72 without answering it**, which is what made it the merge blocker: the
source comment on the `-State` parameter deferred the question to this checklist by name, so
shipping with the box unticked would have left a comment in the tree pointing at a verification that
never happened. **It was run on 2026-09-11 and commit `72b3477` put the answer where the deferral
was** -- the comment now states the measurement and its one-pair limit, and nothing in `source/`
points at this file any more. Keep the check as the record and as a re-run recipe, not as a promise
the tree is still making.

- [x] (verified 2026-09-11) **1.1 Does entitlement management compare the `state` filter case-sensitively?**

  `[ValidateSet]` on `-State` is case-insensitive (`IgnoreCase = True`, not overridden), so both
  `delivered` and `Delivered` bind, and PowerShell passes the bound value through VERBATIM: the
  spelling the caller typed is interpolated into `state eq '...'` unchanged
  (`source/Public/Get-OERAccessPackageAssignment.ps1`, the `$Filters += "state eq '..."` line).
  `ConvertTo-OERODataFilterValue` only doubles quotes and percent-encodes, and neither `delivered`
  nor `Delivered` contains a character it touches, so the casing reaches Graph exactly as typed.

  **You need an access package with at least one assignment in the `delivered` state.** Any package
  in the tenant will do; it does not have to be `oer-live-ap`. If the tenant has none, run section 2
  first and come back here BEFORE running anything else -- section 1 stays first in the running
  order even when its data has to be created by section 2.

  ```powershell
  # Find a package that has a delivered assignment. Note: no -State filter here on purpose -- this
  # read must not depend on the very behaviour under test.
  $Ap = $Package     # 'oer-live-ap' -- a display NAME here on purpose, so no #71 existence read
  $All = @(Get-OERAccessPackageAssignment -AccessPackage $Ap)
  $All | Group-Object State | Format-Table Name, Count

  # The two spellings, counted.
  $Lower = @(Get-OERAccessPackageAssignment -AccessPackage $Ap -State delivered)
  $Upper = @(Get-OERAccessPackageAssignment -AccessPackage $Ap -State Delivered)
  [pscustomobject]@{
      Unfiltered        = $All.Count
      DeliveredInStates = @($All | Where-Object { [string]$_.State -ieq 'delivered' }).Count
      LowerCaseFilter   = $Lower.Count
      UpperCaseFilter   = $Upper.Count
  } | Format-List

  # And the proof that the two requests really differed only in that one letter.
  (Measure-OerRequest { Get-OERAccessPackageAssignment -AccessPackage $Ap -State delivered -Verbose }).Requests
  (Measure-OerRequest { Get-OERAccessPackageAssignment -AccessPackage $Ap -State Delivered -Verbose }).Requests
  ```

  **The two `Requests` lines are load-bearing.** They must show
  `...&$filter=accessPackage/id eq '...' and state eq 'delivered'` and
  `... and state eq 'Delivered'` respectively. If both print the same casing, the module normalised
  somewhere and the count comparison below measures nothing -- stop and say so.

  **Record:** the four counts, and the two request URIs (with the package id redacted).

  **Then apply exactly one of these three outcomes:**

  | What you saw | What to change |
  |---|---|
  | `LowerCaseFilter` and `UpperCaseFilter` are EQUAL and NON-ZERO | The backend is case-insensitive for this pair. **Change no code.** In `source/Public/Get-OERAccessPackageAssignment.ps1`, replace the comment's "is UNVERIFIED" sentence with a statement that check 1.1 verified case-insensitive comparison on `<date>`, and delete the "If it turns out case matters" paragraph -- the question is closed. Do NOT touch the emitted string and do NOT widen the `ValidateSet`. |
  | The counts DIFFER, one of them zero | The backend is case-sensitive and only one spelling works. Insert one line immediately before the `if ($State) { $Filters += "state eq '..." }` line, normalising `$State` to the spelling that worked. **Do not assume "capitalise the first letter" is the whole rule** -- `partiallyDelivered` and `deliveryFailed` are camelCase, so if you can produce assignments in those states, test them too, and if you cannot, name the untested values explicitly in the comment. Then update the two `-clike` pinning tests in `tests/Unit/Public/Get-OERAccessPackageAssignment.Tests.ps1`: they currently assert that BOTH spellings survive to the wire unchanged, which becomes false the moment normalisation is added. |
  | BOTH counts zero, or the package has no delivered assignment | Inconclusive. Mark this box `- [~]`, write the reason, leave the code and the comment as they stand (still UNVERIFIED), and **do not guess**. Say so in the PR: issue #72 stays open. |

  **A vacuous pass to watch for:** `LowerCaseFilter` and `UpperCaseFilter` both `0` against a
  package with no delivered assignment is `0 -eq 0`, which reads as "equal counts" and is worth
  nothing. That is what the `DeliveredInStates` column is there to expose -- if it is `0`, this
  check did not run.
  **Result:**
  ```powershell
> $Ap = $Package # 'oer-live-ap' -- a display NAME here on purpose, so no #71 existence read  
> $All = @(Get-OERAccessPackageAssignment -AccessPackage $Ap)  
> $All | Group-Object State | Format-Table Name, Count  
  
Name Count  
---- -----  
delivered 1  
  
>  
> # The two spellings, counted.  
> $Lower = @(Get-OERAccessPackageAssignment -AccessPackage $Ap -State delivered)  
> $Upper = @(Get-OERAccessPackageAssignment -AccessPackage $Ap -State Delivered)  
> [pscustomobject]@{  
> Unfiltered = $All.Count  
> DeliveredInStates = @($All | Where-Object { [string]$_.State -ieq 'delivered' }).Count  
> LowerCaseFilter = $Lower.Count  
> UpperCaseFilter = $Upper.Count  
> } | Format-List  
  
Unfiltered : 1  
DeliveredInStates : 1  
LowerCaseFilter : 1  
UpperCaseFilter : 1  
  
>  
> # And the proof that the two requests really differed only in that one letter.  
> (Measure-OerRequest { Get-OERAccessPackageAssignment -AccessPackage $Ap -State delivered -Verbose }).Requests  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/accessPackages?$filter=displayName eq 'oer-live-ap'&$select=id,displayName  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/assignments?$expand=target,accessPackage&$filter=accessPackage/id eq '00000000-0000-0000-0000-000000000001' and state eq 'delivered'  
> (Measure-OerRequest { Get-OERAccessPackageAssignment -AccessPackage $Ap -State Delivered -Verbose }).Requests  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/accessPackages?$filter=displayName eq 'oer-live-ap'&$select=id,displayName  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/assignments?$expand=target,accessPackage&$filter=accessPackage/id eq '00000000-0000-0000-0000-000000000001' and state eq 'Delivered'

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): outcome row 1 of the three-outcome table applies.
# LowerCaseFilter and UpperCaseFilter are EQUAL (1) and NON-ZERO; DeliveredInStates is 1, so the
# comparison is not the vacuous 0-against-0; and the two verbose URIs differ in exactly one letter,
# which proves the module did not normalise anywhere. Entitlement management compares this value
# CASE-INSENSITIVELY. Issue #72 is answered.
# Action: CHANGE NO CODE. Update the comment in source/Public/Get-OERAccessPackageAssignment.ps1 as
# outcome row 1 describes, and name partiallyDelivered and deliveryFailed explicitly as UNTESTED --
# no assignment on this tenant could be put into either state, and both are camelCase.
  ```

---

## 2. Setup, once -- the shared tenant objects

> **This environment (Omnicit AB, built and verified by `Initialize-OerS4Prereq.ps1` in this folder).**
> `& $S4 -WhatIf` prints the plan, `& $S4` builds it, `& $S4 -SkipUsers -SkipObjects` re-verifies,
> and `& $S4 -SkipUsers -RestoreWrites` is the section T aid -- it deletes, BY NAME and never by
> pattern, exactly what the script and this checklist created. **The tenant is LIVE PRODUCTION.**
> Every object in the table below is one this sprint created, prefixed `oer-live-` or `OER-`, with
> **two deliberate exceptions that are pre-existing**: the subscription at
> `<your-subscription-id-or-name>` is DISCOVERED and read, never created, and check 3.11's app
> registration is a standing one whose service principal it disables and re-enables in place. Both
> are called out where they appear -- the `<app-id>` row below, check 3.11 itself, and section T.2.
> **Nothing else pre-existing is read-modified.**
>
> | Checklist token | What it resolves to on this tenant (redacted) |
> |---|---|
> | `<your-tenant-alias>` | `Omnicit` |
> | catalog | `OER-CAT-A` |
> | its one resource | group `oer-live-res`, bound to `oer-live-ap` TWICE: role `Member` (declared by 5.11/5.12's document) and role `Owner` (**deliberately UNDECLARED -- it is 5.12's `Extra` row; do not tidy it away**) |
> | access package / policy | `oer-live-ap` (`$ApId`) / `oer-live-ap-policy` (`$PolicyId`), admin-assignment only |
> | `<assignee-upn>` | `person1@example.com` -- holder of the DELIVERED assignment 1.1, 4.6 and 5.2 need |
> | `<upn>` (5.2's `-WhatIf` target) | `person2@example.com` |
> | `<reviewer-upn>` | `person3@example.com` |
> | PIM group | `oer-live-pim` -- member policy eligible 200 d / active 90 d / activation 8 h. **Its object id is 3.1's `$NotAPackage` AND 5.9's stale GUID** (placeholder row 09). |
> | multi-stage review | `oer-live-ar-multistage` (`$DefId`), two stages, 3 d then 2 d, `-AutoApplyDecisions` deliberately NOT set |
> | recurring review | `oer-live-ar-recurring` (`$RecDefId`), Weekly, 3 occurrences |
> | `<your-subscription-id-or-name>` | `$Sub` -- **discovered, never created.** The prereq script prints the first readable subscription and saves the Contributor policy as found. |
> | 5.10's second package | `oer-live-ap2` / `oer-live-ap2-policy` -- must NOT exist before the run; `-RestoreWrites` removes it |
> | `<app-id>` (3.11) | `oer-live-apponly` when the prereq script ran with `-IncludeAppOnly` -- **it did not**, so the run used an app registration that already existed (placeholder rows 15 and 17). **Its client secret never enters this file, not even shaped like a placeholder.** |
> | Baseline files | `%TEMP%\oer-s4\oer-s4-created.json`, `%TEMP%\oer-s4\oer-s4-arm-baseline.json` |
>
> **What the prereq script could NOT build in a live production tenant.** These are known before the
> run starts, so the checks that depend on them are `- [~]` / "cannot be verified, and therefore we
> do not know", not discoveries made halfway through:
>
> | Missing prerequisite | Why | Checks it costs |
> |---|---|---|
> | an access review instance with MORE THAN 100 decisions | one decision per delivered assignment, so it needs 100+ real principals joined to a live group | 4.4, and the multi-page half of 3.6 |
> | an access package with MORE resource role bindings than one server page | one binding is one catalog resource x one role, so a second page needs ~50 new groups as catalog resources | 5.11, and the paging half of 5.12 |
> | a SECOND instance of the recurring review | `Weekly` is the shortest recurrence `New-OERAccessReviewDefinition` accepts; the second instance is seven days out | 4.5 |
> | an identity with exactly the wrong slice of permission | not arrangeable on a tenant that has to keep working | 3.5 |
> | a mid-walk (page 2 or later) paging failure | the checklist's own text already says so | 3.8 |
>
> **The first run may need a second pass, and that is a property of the tenant, not of the script.**
> Entitlement management's origin-system view lags behind directory writes by minutes. Measured
> 2026-09-10: a group created seconds earlier was refused by `Add-OERCatalogResource` with
> `ResourceNotFoundInOriginSystem`, and `Add-OERGroupEligibility` on a second seconds-old group
> answered `ResourceNotFound`. The script now retries both until the object READS BACK (up to four
> minutes), and skips the two resource role bindings outright when the catalog resource is still not
> readable -- a binding cannot exist without it, so attempting one only produces identical failures.
> If verify still reports the catalog resource or either binding as FAIL, **re-run `& $S4
> -SkipUsers`**: everything in the script is idempotent and it picks up exactly where it stopped.
>
> **This block has been redacted.** The three UPNs above are placeholders (see the placeholder
> table); every OBJECT display name that survives is one this sprint created and resolves to nothing
> outside a tenant that no longer holds the object. The one pre-existing object this file touches --
> check 3.11's app registration -- is therefore referred to by ROLE and never by its display name, in
> this block and everywhere else: a standing registration does not stop resolving when the run is
> torn down, so its name is not a test name. `Initialize-OerS4Prereq.ps1` itself is NOT in
> this repository -- it lives beside the operator's own copy of this checklist, and a re-run needs
> it from there.

Use a throwaway tenant or a disposable slice of a test tenant. Sections 3, 4 and 5 all draw on what
this section builds.

You need, in total:

- One catalog `OER-CAT-A` with at least one resource, and an access package `oer-live-ap` in it with
  **at least one assignment policy, at least one resource role binding, and at least one delivered
  ASSIGNMENT**. The assignment is the one that is easy to miss and it is not optional: checks 1.1,
  4.6 and 5.2 all need it.
- One PIM-onboarded group `oer-live-pim` with a member policy (check 4.7).
- A subscription you can read, for check 5.1.
- Optionally, for section 4's paging checks, a collection with **more than one page**. Graph's
  default page size varies by endpoint; an access review instance with more than 100 decisions is
  the easiest to produce, by scoping the review at an access package that has more than 100
  assignments. It cannot be produced by scoping a review at a large GROUP:
  `New-OERAccessReviewDefinition` has no `-Group` parameter, and this module creates
  access-package-scoped reviews only.
- Optionally, for check 5.11/5.12, an access package carrying **more resource role bindings than one
  server page**.

- [x] (verified 2026-09-11) **2.1 Connect, with the scopes access reviews need.** *(PR #64 S1; the import line is
  CORRECTED -- see below.)*

  ```powershell
  Import-OerBuild
  Connect-OER -TenantAlias $Alias
  (Get-OERRequiredScope -Cmdlet New-OERAccessReviewDefinition, New-OERAccessReviewStage,
      Get-OERAccessReviewInstance, New-OERAccessPackageAssignment,
      Remove-OERAccessReviewDefinition -Unique).GraphScope
  ```

  **Expect:** the connect succeeds and the scope list is exactly these seven --
  `AccessReview.Read.All`, `AccessReview.ReadWrite.All`, `Application.Read.All`,
  `EntitlementManagement.Read.All`, `EntitlementManagement.ReadWrite.All`, `Group.Read.All`,
  `User.ReadBasic.All`. Access reviews additionally need a Microsoft Entra ID Governance or Entra
  Suite license in the tenant
  (https://learn.microsoft.com/entra/id-governance/entitlement-management-access-reviews-create).
  **Failure looks like:** a consent error on the first Graph call in 2.2 rather than here --
  `Connect-OER` succeeding is not proof the scopes were granted.

  > **CORRECTED from PR #64 S1: the import line.** S1 read
  > `Import-Module ./output/module/Omnicit.EntraRBAC/2.0.0/Omnicit.EntraRBAC.psd1 -Force`. There has
  > never been a `2.0.0` folder on this branch, and the computed version is now `0.10.0` and capped
  > below `1.0.0` by design. Use `Import-OerBuild` from the session block, which resolves the newest
  > manifest whatever it is named and prints the version it loaded.
  >
  > **Re-verified against current source:** the seven scopes are still exactly right. The union of
  > the five cmdlets' `GraphScope` entries in `source/Private/Get-OERRequiredScopeMap.ps1` is
  > unchanged by this sprint -- issue #71 added a GET on an endpoint the resolver's display-name
  > query already covered (`identityGovernance/entitlementManagement`), and added no write.
  **Result:**
  
  ```powershell
> (Get-OERRequiredScope -Cmdlet New-OERAccessReviewDefinition, New-OERAccessReviewStage,  
> Get-OERAccessReviewInstance, New-OERAccessPackageAssignment,  
> Remove-OERAccessReviewDefinition -Unique).GraphScope  
AccessReview.Read.All  
AccessReview.ReadWrite.All  
Application.Read.All  
EntitlementManagement.Read.All  
EntitlementManagement.ReadWrite.All  
Group.Read.All  
User.ReadBasic.All
  ```

- [x] (verified 2026-09-11) **2.2 Re-confirm the package and the policy GUID.** *(PR #64 S2, unchanged.)*

  ```powershell
  Get-OERAccessPackage -DisplayName $Package | Format-Table Id, DisplayName, CatalogId
  Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId |
      Format-Table Id, DisplayName, DurationInDays
  # Already set by the session block; re-assert it here so this step stands on its own in a fresh
  # session, and print it so the result block records WHICH policy the rest of the file pins.
  $PolicyId = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId |
                    Where-Object DisplayName -eq $PolicyName)[0].Id
  [pscustomobject]@{ ApId = $ApId; PolicyId = $PolicyId; PolicyName = $PolicyName } | Format-List
  ```

  **Expect:** exactly one package, and at least one policy. Copy the `Id` of the policy you intend
  to review into `$PolicyId`. If there is more than one, pick one and stay with it for the whole of
  sections 2, 4 and 5 -- the review scope pins ONE package plus ONE policy, and assignments made
  under a different policy are invisible to the review. Confirm `CatalogId` is the catalog you
  expect: a leftover duplicate `oer-live-ap` in another catalog resolves cleanly and reviews
  nothing.
  **Failure looks like:** an empty policy list -- the set-up above is not done. Create one with
  `New-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap' -DisplayName '<name>'
  -RequestorScope (New-OERAccessPackageRequestorScope -AdminAssignmentOnly)` and start again.

  > **Traced:** `Id`, `DisplayName`, `CatalogId` are all real properties of
  > `ConvertTo-OERAccessPackage`'s output object; `Id`, `DisplayName`, `DurationInDays` are all real
  > properties of `ConvertTo-OERAssignmentPolicy`'s. Neither converter changed this sprint.
  **Result:**
  
  ```powershell
> Get-OERAccessPackage -DisplayName $Package | Format-Table Id, DisplayName, CatalogId  
  
Id DisplayName CatalogId  
-- ----------- ---------  
00000000-0000-0000-0000-000000000001 oer-live-ap 00000000-0000-0000-0000-000000000012  
  
> Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId |  
> Format-Table Id, DisplayName, DurationInDays  
  
Id DisplayName DurationInDays  
-- ----------- --------------  
00000000-0000-0000-0000-000000000002 oer-live-ap-policy 365  
  
> # Already set by the session block; re-assert it here so this step stands on its own in a fresh  
> # session, and print it so the result block records WHICH policy the rest of the file pins.  
> $PolicyId = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId |  
> Where-Object DisplayName -eq $PolicyName)[0].Id  
> [pscustomobject]@{ ApId = $ApId; PolicyId = $PolicyId; PolicyName = $PolicyName } | Format-List  
  
ApId : 00000000-0000-0000-0000-000000000001  
PolicyId : 00000000-0000-0000-0000-000000000002  
PolicyName : oer-live-ap-policy
  ```

- [x] (verified 2026-09-11) **2.3 Confirm at least one principal is in scope.** *(PR #64 S3, unchanged.)* A review over an
  access package reviews its ASSIGNMENTS. With no delivered assignment under `$PolicyId` there is
  nothing to decide -- and check 1.1 has nothing to count either.

  ```powershell
  Get-OERAccessPackageAssignment -AccessPackage $ApId | Format-Table Id, TargetId, State
  # only if that is empty -- the prereq script already made one, so expect NOT to need this:
  # New-OERAccessPackageAssignment -AccessPackage $ApId -Policy $PolicyId -User $Assignee
  ```

  **Expect:** at least one assignment reaching `delivered`. Delivery is not instant; re-run the
  `Get-` line until `State` settles.
  **Failure looks like:** the assignment stuck in `delivering` or landing on `deliveryFailed`. Fix
  that before creating the review.

  > **Traced:** `Id`, `TargetId` and `State` are all real properties of `ConvertTo-OERAssignment`'s
  > output object. `-User` takes a UPN or an object id and resolves through
  > `Resolve-OERPrincipalOrId`.
  **Result:**
  
  ```powershell
> Get-OERAccessPackageAssignment -AccessPackage $ApId | Format-Table Id, TargetId, State  
  
Id TargetId State  
-- -------- -----  
00000000-0000-0000-0000-000000000003 00000000-0000-0000-0000-000000000004 delivered
  ```

- [x] (verified 2026-09-11) **2.4 Build the two stage objects.** *(PR #64 S4, unchanged.)* These are LOCAL objects.
  `New-OERAccessReviewStage` calls Graph only to resolve the reviewer name, and creates nothing in
  the tenant.

  ```powershell
  $StageOne = New-OERAccessReviewStage -StageId '1' -DurationInDays 3 -Reviewer $Reviewer
  $StageTwo = New-OERAccessReviewStage -StageId '2' -DependsOn '1' -DurationInDays 2 `
      -Reviewer $Reviewer -DecisionsThatMoveToNextStage NotReviewed
  $StageOne, $StageTwo | Format-Table StageId, DurationInDays, ReviewerCount
  ```

  **Expect:** two objects, `ReviewerCount` 1 on each. `-DecisionsThatMoveToNextStage` accepts only
  `Approve`, `Deny`, `Recommendation`, `NotReviewed`.
  **Failure looks like:** a `UserNotFound` naming `<reviewer-upn>`, or `ReviewerCount` 0.
  **Do NOT use `-Manager` here.** `New-OERAccessReviewDefinition` refuses a manager reviewer with no
  fallback (`ManagerFallbackRequired`), and it is an unnecessary variable in a setup step.

  > **Traced:** `New-OERAccessReviewStage` emits `StageId`, `DurationInDays`, `ReviewerCount` and
  > `GraphStage`. `-DurationInDays` carries `[ValidateRange(1, [int]::MaxValue)]`.
  **Result:**
  
  ```powershell
> $StageOne = New-OERAccessReviewStage -StageId '1' -DurationInDays 3 -Reviewer $Reviewer  
> $StageTwo = New-OERAccessReviewStage -StageId '2' -DependsOn '1' -DurationInDays 2 `  
> -Reviewer $Reviewer -DecisionsThatMoveToNextStage NotReviewed  
> $StageOne, $StageTwo | Format-Table StageId, DurationInDays, ReviewerCount  
  
StageId DurationInDays ReviewerCount  
------- -------------- -------------  
1 3 1  
2 2 1
  ```

- [x] (verified 2026-09-11) **2.5 Create the multi-stage definition.** *(PR #64 S5, unchanged.)*

  ```powershell
  # THE PREREQ SCRIPT ALREADY CREATED THIS. Read it back rather than making a second one -- 2.6
  # fails outright on two definitions of the same name.
  $Def = Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage'
  $Def | Format-List Id, DisplayName, Status, StageCount

  # Only if the read above comes back empty:
  # $Def = New-OERAccessReviewDefinition `
  #     -DisplayName             'oer-live-ar-multistage' `
  #     -DescriptionForAdmins    'Live verification of sections 4 and 5. Safe to delete.' `
  #     -DescriptionForReviewers 'Live verification. No action needed.' `
  #     -AccessPackage           $Package `
  #     -AssignmentPolicy        $PolicyId `
  #     -Stage                   $StageOne, $StageTwo `
  #     -Recurrence              OneTime `
  #     -StartDate               (Get-Date) `
  #     -DurationInDays          5
  ```

  **Expect:** one object with a GUID `Id`, `StageCount` 2, and a `Status` of `NotStarted` or
  `Initializing`.
  **Failure looks like:** a parameter binding error. `-Stage` lives in the `MultiStage` parameter
  set, which does NOT contain `-Reviewer`, `-ReviewerGroup`, `-Manager`, `-SelfReview`,
  `-FallbackReviewer` or `-FallbackReviewerGroup`. Adding any of those to this call makes the
  command unresolvable. For a multi-stage review, reviewers live on the stage objects only.

  **Why these values.**

  - `-Recurrence OneTime` is the fastest cadence to an instance. The module emits NO `recurrence`
    object at all for `OneTime` -- the private builder returns nothing and the caller omits the key
    -- so there is no future schedule for the service to wait on. Learn: "In the case of a one-time
    review, only one instance is created per resource."
  - `-StartDate (Get-Date)` is REQUIRED by the binder but is **discarded** when `-Recurrence` is
    `OneTime`, because it is used only to build the recurrence range. Pass it to satisfy the binder;
    do not expect it to influence anything.
  - `-DurationInDays 5` is the sum of the two stage durations (3 + 2). Learn documents the stage
    `endDateTime` as "the cumulative total of the durationInDays for all stages", and documents that
    where `stageSettings` is defined its settings are used instead of the definition's, so the
    per-stage values are the ones that govern.
  - Deliberately NOT passed: `-AutoApplyDecisions`. If decisions auto-apply, the review can REMOVE
    the assignment 2.3 created. See section T.
  - **If you also need the recurring definition check 4.5 asks for** (more than one instance),
    create a SECOND definition -- do not turn this one into a recurring review. Sections 4 and 5 are
    far easier to reason about on a one-time review with exactly one instance. The second definition
    is single-stage and lives in the `SingleStage` set:

    ```powershell
    # Also already created by the prereq script -- read it back.
    $RecDef = Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-recurring'
    $RecDef | Format-List Id, DisplayName, Status, StageCount

    # Only if that is empty:
    # $RecDef = New-OERAccessReviewDefinition `
    #     -DisplayName             'oer-live-ar-recurring' `
    #     -DescriptionForAdmins    'Live verification of check 4.5. Safe to delete.' `
    #     -DescriptionForReviewers 'Live verification. No action needed.' `
    #     -AccessPackage           $Package `
    #     -AssignmentPolicy        $PolicyId `
    #     -Reviewer                $Reviewer `
    #     -Recurrence              Weekly `
    #     -StartDate               (Get-Date) `
    #     -Occurrences             3 `
    #     -DurationInDays          3
    ```

  > **Traced:** `Id` (an `AliasProperty` of `AccessReviewDefinitionId`, registered in
  > `source/suffix.ps1`), `DisplayName`, `Status` and `StageCount` are all real properties of
  > `ConvertTo-OERAccessReviewDefinition`'s output.
  **Result:**
  
  ```powershell
> $Def = Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage'  
> $Def | Format-List Id, DisplayName, Status, StageCount  
  
Id : 00000000-0000-0000-0000-000000000005  
DisplayName : oer-live-ar-multistage  
Status : InProgress  
StageCount : 2

> $RecDef = Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-recurring'  
> $RecDef | Format-List Id, DisplayName, Status, StageCount  
  
Id : 00000000-0000-0000-0000-000000000006  
DisplayName : oer-live-ar-recurring  
Status : InProgress  
StageCount : 0

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): Status reads InProgress where the Expect says NotStarted or
# Initializing. Not a discrepancy: Initialize-OerS4Prereq.ps1 created both definitions earlier, so the
# review had already started by the time this step read it back. StageCount 2 is the assertion that
# matters and it holds. oer-live-ar-recurring's StageCount 0 is correct for a single-stage review --
# Graph builds stageSettings only for multi-stage definitions.
  ```

- [x] (verified 2026-09-11) **2.6 Capture the definition id.** *(PR #64 S6, unchanged.)*

  ```powershell
  $DefId = $Def.Id
  # or, in a fresh session:
  $DefId = (Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage').Id
  $DefId
  ```

  **Expect:** one GUID. This is `$DefId` in 4.1, 4.3, 4.4, 5.3 and 5.5, and the display name
  `oer-live-ar-multistage` is check 5.3's name input. (`Id` is an `AliasProperty` of
  `AccessReviewDefinitionId`; both spellings return the same value.)
  **Failure looks like:** more than one result, meaning a review of that name already exists. Rename
  the new one or delete the old one -- an ambiguous display name makes 5.3 unreadable.
  **Result:**
  ```powershell
> $DefId = $Def.Id  
> # or, in a fresh session:  
> $DefId = (Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage').Id  
> $DefId  
00000000-0000-0000-0000-000000000005
  ```

- [x] (verified 2026-09-11) **2.7 Wait for the SERVICE to create the instance, then capture its id.** *(PR #64 S7,
  unchanged.)* This is the step most likely to look broken when it is not. Instances are created by
  Microsoft Graph, and an empty result immediately after 2.5 is normal.

  ```powershell
  Get-OERAccessReviewInstance -Definition $DefId |
      Format-Table Id, Status, StartDateTime, EndDateTime
  $InstId = @(Get-OERAccessReviewInstance -Definition $DefId)[0].Id
  [pscustomobject]@{ DefId = $DefId; InstId = $InstId; SameValue = ($DefId -eq $InstId) } | Format-List
  ```

  > **`SameValue` of `True` is the EXPECTED answer here, and printing it is the point.** Measured on
  > the 2026-09-10 setup run: a `OneTime` review's single instance carries the same id as its
  > definition. Learn documents `accessReviewInstance.id` only as a unique identifier and promises
  > nothing about its relationship to the definition's, so this is an observation, not a rule -- but
  > an operator who sees two identical GUIDs and assumes a typo will "fix" `$InstId` to something
  > wrong and take 3.7, 4.1, 4.2 and 4.4 down with it. **Redaction consequence:** when they are
  > equal they are ONE identifier and get ONE placeholder -- see the note under the placeholder
  > table.

  **Expect:** eventually exactly one instance -- a one-time review has exactly one -- with a GUID
  `Id` and a `Status` moving `Initializing` -> `NotStarted` -> `InProgress`. An instance sitting in
  `NotStarted` is already usable for 4.1 and 4.2: Learn describes
  `accessReviewInstance.startDateTime` as "DateTime when review instance is scheduled to start.
  **May be in the future**", so the object can exist before it starts.

  **How long this takes is not documented as a number, and this block will not invent one.** What
  Learn does say: "When creating an access review, you're able to specify the start date, but the
  start time could vary a few hours based on system processing ... could be delayed due to system
  processing"
  (https://learn.microsoft.com/entra/id-governance/create-access-review#create-a-single-stage-access-review).
  A processing delay is documented; **its magnitude is not**. **Poll -- re-run the command every few
  minutes -- rather than concluding failure.** Write the wait you actually observed on the result
  line; it is the only measurement anyone will have.

  **Failure looks like:** still nothing after a long wait AND a definition `Status` stuck at
  `Initializing`, which usually means the scope query matched no assignments. Go back to 2.3.
  **If you cannot get an instance at all,** write "cannot be verified, and therefore we do not know"
  on 4.1, 4.2 and 4.4, say the instance never materialized, and do not tick them.

  > **Traced:** `Id` (an `AliasProperty` of `AccessReviewInstanceId`), `Status`, `StartDateTime` and
  > `EndDateTime` are all real properties of `ConvertTo-OERAccessReviewInstance`. Sprint 3 added a
  > `$select` to this read (`id,status,startDateTime,endDateTime,scope`), and all four columns above
  > are inside it -- so #74 does not blank any of them. That was checked, not assumed.
  **Result:**
  
  ```powershell
> Get-OERAccessReviewInstance -Definition $DefId |  
> Format-Table Id, Status, StartDateTime, EndDateTime  
  
Id Status StartDateTime EndDateTime  
-- ------ ------------- -----------  
00000000-0000-0000-0000-000000000005 InProgress 2026-09-11 09:05:32 2026-10-11 09:05:32  
  
> $InstId = @(Get-OERAccessReviewInstance -Definition $DefId)[0].Id  
> [pscustomobject]@{ DefId = $DefId; InstId = $InstId; SameValue = ($DefId -eq $InstId) } | Format-List  
  
DefId : 00000000-0000-0000-0000-000000000005  
InstId : 00000000-0000-0000-0000-000000000005  
SameValue : True

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): the Record asks for the wait actually observed and it is
# not on the line. The instance already existed because Initialize-OerS4Prereq.ps1 had created the
# definition earlier and polled for it; that script's own poll is the only measurement this run has.
# SameValue True is the EXPECTED answer for a OneTime review -- see the note under this check.
  ```

- [x] (verified 2026-09-11) **2.8 Capture the stage id.** *(PR #64 S8, unchanged.)*

  ```powershell
  $Inst = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages
  $Inst | Format-Table Id, Status
  $Inst.Stages | Format-Table AccessReviewStageId, Status, StartDateTime, EndDateTime
  $StageId = ($Inst.Stages | Select-Object -First 1).AccessReviewStageId
  ```

  **Expect:** `$Inst.Stages` is non-empty. Because "a new stage will only be created when the
  previous stage ends", expect ONE stage here -- stage 1 -- not two.
  **On the id format:** Learn documents `accessReviewStage.id` only as "Unique identifier of the
  stage. Read-only." and states no format. It is NOT promised to be the `'1'` / `'2'` passed to
  `New-OERAccessReviewStage -StageId` -- that value goes into the definition's `stageSettings`,
  which is a different object. Write down what you actually see.
  **Failure looks like:** `$Inst.Stages` empty while the definition has two stages configured.
  Confirm the review really is multi-stage first:
  `(Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage').StageSettings`. An empty
  `StageSettings` means the create fell into the single-stage path and 4.1/4.2 cannot run against
  it.
  **Careful:** where a definition has several instances, `$Inst` is an ARRAY and `$Inst.Stages`
  unrolls across all of them. The one-time review from 2.5 has exactly one instance, which is why
  4.1's `$Inst.Stages` is safe as written -- do not point `$Inst` at `oer-live-ar-recurring`.

  > **Traced:** `AccessReviewStageId`, `Status`, `StartDateTime` and `EndDateTime` are all real
  > properties of `ConvertTo-OERAccessReviewStage`. `StageSettings` is a real property of
  > `ConvertTo-OERAccessReviewDefinition`. The stages read deliberately sends NO `$select`
  > (documented in `Get-OERAccessReviewInstance.ps1`), so #74 cannot have blanked a stage field.
  **Result:**
  
  ```powershell
> $Inst = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages  
> $Inst | Format-Table Id, Status  
  
Id Status  
-- ------  
00000000-0000-0000-0000-000000000005 InProgress  
  
> $Inst.Stages | Format-Table AccessReviewStageId, Status, StartDateTime, EndDateTime  
  
AccessReviewStageId Status StartDateTime EndDateTime  
------------------- ------ ------------- -----------  
00000000-0000-0000-0000-000000000008 InProgress 2026-09-11 09:05:36 2026-09-14 09:05:36
  ```

- [x] (verified 2026-09-11) **2.9 Confirm the three ids satisfy sections 4 and 5 before you start them.** *(PR #64 S9,
  unchanged.)*

  ```powershell
  [pscustomobject]@{ DefinitionId = $DefId; InstanceId = $Inst.Id; StageId = $StageId } | Format-List
  $Inst.Stages | Select-Object -First 1 |
      Format-List AccessReviewStageId, AccessReviewInstanceId, AccessReviewDefinitionId
  ```

  **Expect:** three non-empty values in the first block, and all three properties populated in the
  second. The second block is a dry run of check 4.2 -- if it passes here, 4.1 and 4.2 are runnable.
  **Failure looks like:** `AccessReviewInstanceId` or `AccessReviewDefinitionId` `$null`. That is
  check 4.2's own failure mode, so do not "fix" it in setup -- record it as 4.2's result.
  **Result:**
  ```powershell
> [pscustomobject]@{ DefinitionId = $DefId; InstanceId = $Inst.Id; StageId = $StageId } | Format-List  
  
DefinitionId : 00000000-0000-0000-0000-000000000005  
InstanceId : 00000000-0000-0000-0000-000000000005  
StageId : 00000000-0000-0000-0000-000000000008  
  
> $Inst.Stages | Select-Object -First 1 |  
> Format-List AccessReviewStageId, AccessReviewInstanceId, AccessReviewDefinitionId  
  
AccessReviewStageId : 00000000-0000-0000-0000-000000000008  
AccessReviewInstanceId : 00000000-0000-0000-0000-000000000005  
AccessReviewDefinitionId : 00000000-0000-0000-0000-000000000005
  ```

---

## 3. Read-only -- this sprint's own checks

Nothing in this section writes to the tenant.

### 3.1 - 3.5: issue #71, the access package resolver

- [ ] **SUPERSEDED BY U.1 -- 3.1 A stale or mistyped GUID is no longer silence.**

  Use a GUID that is syntactically valid but is not an access package. A group's object id works
  well and is trivially available.

  ```powershell
  $NotAPackage = (Get-OERGroup -Group $PimGroup).Id      # set by the session block; re-asserted here
  $NotAPackage
  Get-OERAccessPackageAssignment -AccessPackage $NotAPackage `
      -ErrorAction SilentlyContinue -ErrorVariable Err
  @($Err) | ForEach-Object {
      [pscustomobject]@{
          Id       = $_.FullyQualifiedErrorId
          Category = $_.CategoryInfo.Category
          Command  = $_.InvocationInfo.MyCommand.Name
          Message  = $_.Exception.Message
      }
  } | Format-List
  ```

  **Expect:** NO output objects at all, and among the collected records exactly one whose `Command`
  is `Get-OERAccessPackageAssignment` -- the record the cmdlet itself published. Its `Id` starts
  `AccessPackageNotFound`, its `Category` is `ObjectNotFound`, and its `Message` is the resolver's
  own tailored text, beginning "The access package id '...' does not resolve to an access package
  in this tenant."
  **Before this branch:** the same command produced no output and NO error at all -- that is
  issue #71.

  > **Narrow to the published record, not to `$Err[0]`.** `-ErrorVariable` collects FOUR records for
  > one logical failure here: the engine's own captures of the inner `throw` (which carry the bare
  > id with no `Command`) plus the one the cmdlet published. Asserting on the join of all of them
  > passes even with the fix reverted. `InvocationInfo.MyCommand.Name` is populated only on the
  > published record; that is the one to read.
  >
  > **Traced:** `source/Private/Resolve-OERAccessPackageId.ps1` throws
  > `'AccessPackageNotFound'` / `ObjectNotFound` with that message; the catch in
  > `source/Public/Get-OERAccessPackageAssignment.ps1` re-publishes it verbatim through
  > `$PSCmdlet.WriteError($PSItem)` rather than folding it into the generic
  > "Access package 'X' not found." branch.
  **Result:**
  
  ```powershell
> Get-OERAccessPackageAssignment -AccessPackage $NotAPackage `  
> -ErrorAction SilentlyContinue -ErrorVariable Err  
> @($Err) | ForEach-Object {  
> [pscustomobject]@{  
> Id = $_.FullyQualifiedErrorId  
> Category = $_.CategoryInfo.Category  
> Command = $_.InvocationInfo.MyCommand.Name  
> Message = $_.Exception.Message  
> }  
> } | Format-List  
  
Id : AccessPackageNotFound  
Category : OperationStopped  
Command :  
Message : AccessPackageNotFound: The access package was not found.  
  
Id : AccessPackageNotFound  
Category : OperationStopped  
Command :  
Message : AccessPackageNotFound: The access package was not found.  
  
Id : AccessPackageNotFound  
Category : OperationStopped  
Command :  
Message : AccessPackageNotFound: The access package was not found.  
  
Id :  
Category :  
Command :  
Message :  
  
Id : AccessPackageNotFound  
Category : OperationStopped  
Command :  
Message : AccessPackageNotFound: The access package was not found.  
  
Id : AccessPackageNotFound  
Category : OperationStopped  
Command :  
Message : AccessPackageNotFound: The access package was not found.  
  
Id :  
Category :  
Command :  
Message :  
  
Id : AccessPackageNotFound  
Category : OperationStopped  
Command :  
Message : AccessPackageNotFound: The access package was not found.  
  
Id : AccessPackageNotFound,Get-OERAccessPackageAssignment  
Category : OperationStopped  
Command : Get-OERAccessPackageAssignment  
Message : AccessPackageNotFound: The access package was not found.

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): NOT A PASS -- box un-ticked.
# The Expect requires Category = ObjectNotFound and the resolver's own message ("The access package id
# '...' does not resolve to an access package in this tenant."). The run returned
# Category = OperationStopped and Graph's own terse text, so the tailored throw in
# Resolve-OERAccessPackageId NEVER FIRED: the real Graph code is AccessPackageNotFound, which is
# OUTSIDE the declared superset ('ResourceNotFound','NotFound','ObjectNotFound',
# 'Request_ResourceNotFound'), and Get-ExpectedGraphErrorMatch compares whole tokens.
# This is still loud and still not the silence of issue #71 -- the safe direction to be wrong in, as
# the resolver's own comment predicted -- but #71's tailored error is not being delivered. Re-run this
# check once the code set is fixed. See finding F-A.

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-13): SUPERSEDED BY CHECK U.1, which passed on
# 2026-09-12 after the F-A fix. This box stays un-ticked because the run recorded above is the
# pre-fix behaviour and must not read as a pass; U.1 is where this check's verdict lives.
  ```

- [x] (verified 2026-09-11) **3.2 THE HEADLINE CAPTURE: what error code does Graph actually answer with?**

  The resolver DECLARED a deliberate SUPERSET of not-found codes --
  `'ResourceNotFound', 'NotFound', 'ObjectNotFound', 'Request_ResourceNotFound'` -- because the code
  entitlement management returns for a GET of a non-existent access package id **was not documented
  on Microsoft Learn**. This check is what let that set be narrowed to the one true code, and it
  has been: commit `72b3477` replaced the superset with the measured pair
  `'AccessPackageNotFound', 'NotFound'`. **Everything below is the record of that measurement, not a
  description of what the resolver declares today** -- the "follow-up, and it is DONE" paragraph
  under the Record list has the detail.

  ```powershell
  # Same id as 3.1. Call the transport directly so the raw Graph failure is not softened.
  $Uri = "v1.0/identityGovernance/entitlementManagement/accessPackages/$NotAPackage`?`$select=id"
  $RawErr = $null
  try {
      & (Get-Module Omnicit.EntraRBAC) ([scriptblock]::Create("Invoke-OERGraphRequest -Uri '$Uri' -Verbose"))
  } catch {
      $RawErr = $_
  }
  'captured: ' + ($null -ne $RawErr)      # must print True before you read anything below

  # PROJECT, then format. "Format-List FullyQualifiedErrorId, CategoryInfo" on an ErrorRecord
  # prints the ERROR VIEW -- the "<Category>: <message>" rendering -- and not the two named
  # properties, so the values it shows come from the rendering and not from the properties it
  # names. That is the same defect class as a Format-List asking for a property that does not
  # exist: the output looks like evidence and is not. Build a pscustomobject first. See F-H.
  $E = @($RawErr)[0]
  [pscustomobject]@{
      FullyQualifiedErrorId = $E.FullyQualifiedErrorId
      GraphErrorCode        = ([string]$E.FullyQualifiedErrorId -split ',')[0].Trim()
      Category              = [string]$E.CategoryInfo.Category
      Message               = $E.Exception.Message
  } | Format-List

  # RECORD ITEM 2 -- the HTTP status, read where it still exists. Invoke-OERGraphRequest hands
  # back a record built by Convert-GraphHttpException, which deliberately does NOT chain the raw
  # SDK exception (it references the HttpRequestMessage and therefore the bearer token), so the
  # status is gone by the time the record above reaches you: the record carries a status-DERIVED
  # LABEL only when the body had no parseable code, and here the body had one. Ask Graph directly.
  # This is the one place in this file that calls Invoke-MgGraphRequest outside the module wrapper,
  # and it is a checklist, not module source -- the "all Graph calls go through the wrapper" rule
  # is about source/.
  $AbsUri = "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages/$NotAPackage`?`$select=id"
  $Status = $null
  $StatusFrom = 'not captured'
  try {
      $null = Invoke-MgGraphRequest -Method GET -Uri $AbsUri -ErrorAction Stop
  } catch {
      $Ex = $PSItem.Exception
      if ($null -ne $Ex.Response -and $null -ne $Ex.Response.StatusCode) {
          $Status = [int]$Ex.Response.StatusCode; $StatusFrom = 'Exception.Response.StatusCode'
      }
      elseif ($null -ne $Ex.ResponseStatusCode) {
          $Status = [int]$Ex.ResponseStatusCode; $StatusFrom = 'Exception.ResponseStatusCode (Kiota ApiException)'
      }
  }
  [pscustomobject]@{ HttpStatus = $Status; StatusReadFrom = $StatusFrom } | Format-List
  ```

  > **That last block leaves a bearer-carrying record in `$Error`, and it is the only thing in this
  > file that does.** A raw `Invoke-MgGraphRequest` failure produces an `ErrorRecord` whose
  > `TargetObject` is the `HttpRequestMessage`; rendering it prints `Authorization: Bearer <jwt>` in
  > full. The block reads ONE integer off it and prints nothing else. Do not widen it, do not
  > `Format-List *` the catch variable, and do not paste console scrollback from around it without
  > reading it first. `$Error.Clear()` afterwards if you are about to transcribe anything.

  > **`try`/`catch`, NOT `-ErrorAction`/`-ErrorVariable` -- and this is a measured correction, not a
  > style preference.** The call operator applied to a module-scoped scriptblock takes no common
  > parameters: `-ErrorAction SilentlyContinue -ErrorVariable RawErr` are passed INTO the
  > scriptblock as `$args` and bind to nothing. Measured in a clean `pwsh` against a synthetic
  > module: with a terminating `throw` -- which is exactly what `Invoke-OERGraphRequest` does
  > (`throw Convert-GraphHttpException $AttemptError`) -- the statement aborts and `$RawErr` keeps
  > whatever it held before, so both evidence lines print nothing whatever Graph answered; with a
  > non-terminating `Write-Error` the record still printed despite `SilentlyContinue`, proving the
  > parameter never bound. The `'captured: ' + ...` line is there so an empty capture announces
  > itself instead of reading as "Graph returned nothing".

  **Record, all four:**

  1. The exact `FullyQualifiedErrorId` (its first comma-separated segment is the Graph `error.code`,
     or the literal label `NotFound` when a bare 404 carried no body code).
  2. The HTTP status the failure came back on -- **404, or something else**. Entitlement management
     has been observed answering unusual shapes on this resource family (see the `$select` warning
     in `source/Public/Get-OERAccessPackageResourceRole.ps1`). If it answers 403 for an id the
     caller cannot see, the declared set will NOT match and the operator gets the raw Graph error --
     correct and loud, but worth recording so the message can be improved.
  3. Whether that code is INSIDE the set `source/Private/Resolve-OERAccessPackageId.ps1` declares.
     Check 3.1's result already answers this indirectly: a tailored `AccessPackageNotFound` with
     `Category = ObjectNotFound` means the set matched; a raw Graph code with
     `Category = OperationStopped` surfacing at the cmdlet means the real code is outside it.
     **This is what the 2026-09-11 run found, and the set has since been narrowed to the measured
     pair `'AccessPackageNotFound', 'NotFound'` in commit `72b3477`.**
  4. The `-Verbose` request line, so the URI that produced the answer is on the record.

  **Do not paste the raw error record wholesale.** A rendered `ErrorRecord` whose `TargetObject` is
  the `HttpRequestMessage` prints the bearer token in full. `Format-List` on the two named
  properties, plus `.Exception.Message` alone, is deliberate -- do not widen it to `Format-List *`.
  **The `catch` above serves this rule too:** an uncaught terminating error renders ITSELF to the
  console, which is precisely the full-record dump this paragraph forbids. Catching it is what keeps
  the record out of the scrollback and lets you choose which two properties to look at.

  **The follow-up, and it is DONE.** Commit `72b3477` narrowed
  `-ExpectedErrorCode 'ResourceNotFound', 'NotFound', 'ObjectNotFound', 'Request_ResourceNotFound'`
  in `source/Private/Resolve-OERAccessPackageId.ps1` to `'AccessPackageNotFound', 'NotFound'` -- the
  code this check measured, plus `Convert-GraphHttpException`'s status-derived label for a 404 whose
  body carried no parseable code -- and rewrote the comment above it to say the set was narrowed on
  this check's evidence rather than guessed. Chapter U.1 re-runs check 3.1 against it.
  **Result:**
  ```powershell
> $Uri = "v1.0/identityGovernance/entitlementManagement/accessPackages/$NotAPackage`?`$select=id"  
> $RawErr = $null  
> try {  
> & (Get-Module Omnicit.EntraRBAC) ([scriptblock]::Create("Invoke-OERGraphRequest -Uri '$Uri' -Verbose"))  
> } catch {  
> $RawErr = $_  
> }  
VERBOSE: [Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/accessPackages/00000000-0000-0000-0000-000000000009?$select=id  
> 'captured: ' + ($null -ne $RawErr) # must print True before you read anything below  
captured: True  
> @($RawErr)[0] | Format-List FullyQualifiedErrorId, CategoryInfo  
OperationStopped: AccessPackageNotFound: The access package was not found.  
  
> @($RawErr)[0].Exception.Message  
AccessPackageNotFound: The access package was not found.

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): the headline IS captured: the code entitlement management
# answers with for a GET of a non-existent access package id is AccessPackageNotFound. It is OUTSIDE
# the resolver's declared four-code set, and check 3.1 shows the consequence.
# Record item 2 of 4 is MISSING: the HTTP status was never read. And "Format-List
# FullyQualifiedErrorId, CategoryInfo" rendered the ErrorRecord instead of printing the two named
# properties, so the id and category above come from the rendering rather than from the properties.
# The code is on the record; the status is not. See finding F-H.
# APPLIED 2026-09-11: the block above now projects into a pscustomobject before formatting, and
# carries a status read that goes straight to Graph -- Convert-GraphHttpException builds a fresh
# record and drops the status, so the converted record could never have supplied it.
# STILL OPEN: record item 2 has no value on this page. Run the two added lines in the same session as
# chapter U.1's 3.1 re-run -- same connection, same $NotAPackage -- and paste the HttpStatus /
# StatusReadFrom pair here. The box stays ticked: the HEADLINE this check exists for (the code) is
# measured, and the missing item is an addition to the record, not the check's subject.
  ```

- [x] (verified 2026-09-11) **3.3 A GUID that IS a live access package still works, and costs exactly ONE extra read.**

  ```powershell
  $ApId = (Get-OERAccessPackage -DisplayName $Package).Id     # a GUID from here on -- that is the point
  $M = Measure-OerRequest -Label 'by id' {
      Get-OERAccessPackageAssignment -AccessPackage $ApId -Verbose
  }
  $M | Format-List Label, RequestCount, ExistsReads, Pages, OutputCount
  $M.Requests
  ```

  **Expect:** `ExistsReads` is exactly **1** -- one `GET .../accessPackages/<id>?$select=id`, first
  -- followed by the assignments read. `RequestCount` is `1 + Pages`. `OutputCount` matches what
  check 1.1's `Unfiltered` count returned. The existence read is a single id-addressed GET, **not**
  a paged walk and **not** a `$filter=displayName eq ...` query.
  **Failure looks like:** `ExistsReads` of 0 (the guarantee is not in the build you loaded), or more
  than 1 (the probe is running per page, which it must not).

  > **Traced:** `Resolve-OERAccessPackageId` builds the URI as
  > `v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?$select=id`, which is what the
  > helper's `ExistsReads` regex matches. The cost of "ONE existence read per GUID" is stated in the
  > helper's own `.DESCRIPTION`.
  **Result:**
  
  ```powershell
> $ApId = (Get-OERAccessPackage -DisplayName $Package).Id # a GUID from here on -- that is the point  
> $M = Measure-OerRequest -Label 'by id' {  
> Get-OERAccessPackageAssignment -AccessPackage $ApId -Verbose  
> }  
> $M | Format-List Label, RequestCount, ExistsReads, Pages, OutputCount  
  
Label : by id  
RequestCount : 2  
ExistsReads : 1  
Pages : 1  
OutputCount : 1  
  
> $M.Requests  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/accessPackages/00000000-0000-0000-0000-000000000001?$select=id  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/assignments?$expand=target,accessPackage&$filter=accessPackage/id eq '00000000-0000-0000-0000-000000000001'
  ```

- [x] (verified 2026-09-11) **3.4 The documented pipeline goes from 2N requests to 3N.**
  *(Heading, `Expect` and the `Expected3N` column CORRECTED by finding F-D -- see below.)*

  `Get-OERAccessPackage | Get-OERAccessPackageResourceRole` is a documented pipeline. Every piped
  package binds its own `Id` to `-AccessPackage` (which carries `[Alias('Id')]` with
  `ValueFromPipelineByPropertyName`), so every one of them is now probed before its own read.

  ```powershell
  $A = Measure-OerRequest -Label 'packages' { Get-OERAccessPackage -Verbose }
  $Pkgs = @($A.Output)
  $B = Measure-OerRequest -Label 'roles by pipe' { $Pkgs | Get-OERAccessPackageResourceRole -Verbose }
  [pscustomobject]@{
      Packages          = $Pkgs.Count
      RoleReadRequests  = $B.RequestCount
      ExistenceReads    = $B.ExistsReads
      Expected3N        = 3 * $Pkgs.Count
  } | Format-List
  ```

  **Expect:** `ExistenceReads` equals `Packages` -- exactly one probe per id-addressed call, never
  more, which is what issue #71's cost model claims -- and `RoleReadRequests` equals `Expected3N`.
  The THREE requests per package, named: (1) the existence probe
  `GET accessPackages/{id}?$select=id`, (2) the resource-role read itself
  `GET accessPackages/{id}?$expand=resourceRoleScopes($expand=role,scope),catalog`, and (3) the
  best-effort `Get-OERCatalogResource -Catalog <catalog-id>` join that fills `ResourceDisplayName`.
  That third one is an `-All` walk, so on a large catalog it is itself more than one request and
  the per-package cost rises ABOVE three -- add any extra pages before calling a surplus a defect.
  Time it too, on a tenant with a realistic package count -- the cost of the guarantee is what an
  operator will feel.
  **Record:** the three counts and the elapsed time.
  **Failure looks like:** `ExistenceReads` of 0, meaning the guarantee is absent; `ExistenceReads`
  above `Packages`, meaning something is probing per item rather than per package; or a
  `RoleReadRequests` far above `3N` that the catalog walk's paging does not account for.

  > **Traced:** `source/Private/Resolve-OERAccessPackageId.ps1`'s `.DESCRIPTION` states the 2N-to-3N
  > figure and names all three requests, and `source/Public/Get-OERAccessPackageResourceRole.ps1`
  > declares `[Parameter(Mandatory, ValueFromPipelineByPropertyName)] [Alias('Id')]` on
  > `-AccessPackage`. The catalog join is the `$ResourceNameMap` block in that same file.
  >
  > **CORRECTED 2026-09-11 by finding F-D, and this is the measurement that corrected it.** This
  > check shipped asking for `2N` and carrying an `Expected2N` column, with a note predicting that
  > `3N` would come back and calling the difference a doc finding rather than a failure. It did:
  > `Packages = 6`, `ExistenceReads = 6`, `RoleReadRequests = 18`. `ExistenceReads` equalling
  > `Packages` is #71's claim and it held, so #71 is behaving; the surplus is the catalog-resource
  > read, once per package. The `.DESCRIPTION`'s "N requests to 2N" sentence was the imprecise part
  > and was corrected in commit `72b3477` -- the wording above is that sentence's, not a second
  > phrasing of it. A future run that sees `2N` is now the mismatch to investigate.
  **Result:**
  
  ```powershell
> $A = Measure-OerRequest -Label 'packages' { Get-OERAccessPackage -Verbose }  
> $Pkgs = @($A.Output)  
> $B = Measure-OerRequest -Label 'roles by pipe' { $Pkgs | Get-OERAccessPackageResourceRole -Verbose }  
> [pscustomobject]@{  
> Packages = $Pkgs.Count  
> RoleReadRequests = $B.RequestCount  
> ExistenceReads = $B.ExistsReads  
> Expected2N = 2 * $Pkgs.Count       # the pre-F-D column; Expected3N is what the block asks for now  
> } | Format-List  
  
Packages : 6  
RoleReadRequests : 18  
ExistenceReads : 6  
Expected2N : 12

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): ticked, and the surplus is the documented one.
# ExistenceReads 6 equals Packages 6, which is exactly what #71's cost model claims. RoleReadRequests
# 18 is 3N, not the .DESCRIPTION's 2N: the third request per package is Get-OERCatalogResource, the
# ResourceDisplayName join, precisely as the note above predicted. That is a DOCUMENTATION finding
# (F-D), not a failed check. The Record's elapsed time was not captured.
# APPLIED: commit 72b3477 corrected the .DESCRIPTION to 2N-to-3N and named all three requests; this
# check's heading, Expect and column were corrected to match. No re-run is needed -- the numbers above
# ARE the measurement, and they now agree with both the source and the Expect.
  ```

- [~] **3.5 A 403 from the resolver's existence read surfaces AS ITSELF, not as `AccessPackageNotFound`.**

  This was fixed across ten call sites in this sprint. Every unit guard for it MOCKS the resolver,
  so only a live run proves the whole chain.

  **The natural probe:** an identity that can reach entitlement management but cannot read the
  catalog the package lives in, or an identity lacking `EntitlementManagement.Read.All` outright.
  Sign in as that identity and re-run 3.1's command against a package id that DOES exist.

  **On the Omnicit tenant there is no such identity and one cannot be minted safely** -- every
  account that can reach entitlement management here is a real administrator, and a purpose-built
  one would need a directory role assignment in live production to prove a mocked guard. So the
  expected outcome of this check is `- [~]`. Run the block anyway ONLY if you already have an alias
  for a suitable identity; otherwise run the second block, which records the fact rather than
  leaving the box empty.

  ```powershell
  # (a) Only if you have one. $UnderPrivAlias is a Get-OERConfiguration alias you already own.
  $UnderPrivAlias = ''      # leave empty to skip
  if ($UnderPrivAlias) {
      Disconnect-OER
      Connect-OER -TenantAlias $UnderPrivAlias
      Get-OERAccessPackageAssignment -AccessPackage $ApId -ErrorAction SilentlyContinue -ErrorVariable Err
      @($Err) | Where-Object { $_.InvocationInfo.MyCommand.Name } | ForEach-Object {
          [pscustomobject]@{ Id = $_.FullyQualifiedErrorId; Category = $_.CategoryInfo.Category }
      } | Format-List
      Disconnect-OER
      Connect-OER -TenantAlias $Alias -IncludeARM
  }
  ```

  ```powershell
  # (b) The write-up when (a) is skipped. This is evidence about the tenant, not about the code.
  [pscustomobject]@{
      Check          = '3.5'
      Outcome        = 'cannot be verified, and therefore we do not know'
      Reason         = 'no identity on the Omnicit tenant can reach entitlement management without also being able to read the catalog; minting one means a directory role assignment in live production'
      OnlyEvidence   = 'the mocked guards: the "surfaces a 403 out of Resolve-OERAccessPackageId as itself" It in each tests/Unit/Public/*AccessPackage*.Tests.ps1'
      BoxState       = '- [~]'
  } | Format-List
  ```

  **Expect:** the published record's `Id` starts `Authorization_RequestDenied` (or whatever Graph
  really names it -- record it) and its `Category` is `PermissionDenied`. It must **not** be
  `AccessPackageNotFound` and must **not** be `ObjectNotFound`: a permission failure is not evidence
  that the package does not exist, and reporting it as such is the failed-read-as-an-empty-fact
  defect of issue #76.

  **Honest limits.** Arranging an identity with exactly the wrong slice of permission is not always
  possible on a tenant you also have to keep working. If you cannot arrange one, mark this box
  `- [~]`, say so, and note that the mocked guards
  (`tests/Unit/Public/*AccessPackage*.Tests.ps1`, the "surfaces a 403 out of
  Resolve-OERAccessPackageId as itself" `It` in each) are the only evidence there is. Do not
  substitute a `Disconnect-OER`-then-fail probe: that produces an auth error from
  `Initialize-OERAuth`, which never reaches the resolver and proves nothing about this path.
  **Remember to reconnect as the privileged identity before section 4.**
  **Result:**
  ```powershell
> # (a) Only if you have one. $UnderPrivAlias is a Get-OERConfiguration alias you already own.  
> $UnderPrivAlias = '' # leave empty to skip  
> if ($UnderPrivAlias) {  
> Disconnect-OER  
> Connect-OER -TenantAlias $UnderPrivAlias  
> Get-OERAccessPackageAssignment -AccessPackage $ApId -ErrorAction SilentlyContinue -ErrorVariable Err  
> @($Err) | Where-Object { $_.InvocationInfo.MyCommand.Name } | ForEach-Object {  
> [pscustomobject]@{ Id = $_.FullyQualifiedErrorId; Category = $_.CategoryInfo.Category }  
> } | Format-List  
> Disconnect-OER  
> Connect-OER -TenantAlias $Alias -IncludeARM  
> }  
> # (b) The write-up when (a) is skipped. This is evidence about the tenant, not about the code.  
> [pscustomobject]@{  
> Check = '3.5'  
> Outcome = 'cannot be verified, and therefore we do not know'  
> Reason = 'no identity on the Omnicit tenant can reach entitlement management without also being able to read the catalog; minting one means a directory role assignment in live production'  
> OnlyEvidence = 'the mocked guards: the "surfaces a 403 out of Resolve-OERAccessPackageId as itself" It in each tests/Unit/Public/*AccessPackage*.Tests.ps1'  
> BoxState = '- [~]'  
> } | Format-List  
  
Check : 3.5  
Outcome : cannot be verified, and therefore we do not know  
Reason : no identity on the Omnicit tenant can reach entitlement management without also being able to read the catalog; minting one means a directory role assignment in live production  
OnlyEvidence : the mocked guards: the "surfaces a 403 out of Resolve-OERAccessPackageId as itself" It in each tests/Unit/Public/*AccessPackage*.Tests.ps1  
BoxState : - [~]

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): box state corrected from '- [~~]' to '- [~]'. The house
# rules define exactly three states and '~~' is not one of them. The written outcome is unchanged.
  ```

### 3.6 - 3.8: issue #73, partial-read facts on a failed paged walk

- [~] **3.6 A healthy `-All` walk names every page, and the aggregate matches.**

  This is the instrumentation check. It proves the page counter that a failed walk reports is a real
  running count, not a constant.

  ```powershell
  $M = Measure-OerRequest -Label 'assignments walk' {
      Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose    # a display NAME: ExistsReads must be 0
  }
  $M | Format-List Pages, RequestCount, OutputCount
  $M.Verbose | Where-Object { $_ -match 'Fetching page ' }
  ```

  **Expect:** one `[Invoke-OERGraphRequest] Fetching page N...` line per page, numbered from 1 with
  no gaps, and `OutputCount` equal to the total the portal shows for that package. On a small
  package `Pages` will be `1`, which is a legitimate result -- but a single-page walk cannot
  discriminate a working page counter from a broken one, so if `Pages` is `1`, mark this box `- [~]`
  and say the collection did not span a page boundary.
  **Failure looks like:** `Pages` of 1 while `OutputCount` is a suspiciously round number (100, 200)
  and the portal shows more.

  > **Traced:** `source/Private/Invoke-OERGraphRequest.ps1` emits
  > `"[Invoke-OERGraphRequest] Fetching page $PageNumber..."` at the top of the `-All` loop, and
  > `$PageNumber` is the same variable attached to a failed walk's exception as `PageNumber`.
  **Result:**
  
  ```powershell
> $M = Measure-OerRequest -Label 'assignments walk' {  
> Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose # a display NAME: ExistsReads must be 0  
> }  
> $M | Format-List Pages, RequestCount, OutputCount  
  
Pages : 1  
RequestCount : 2  
OutputCount : 1  
  
> $M.Verbose | Where-Object { $_ -match 'Fetching page ' }  
[Invoke-OERGraphRequest] Fetching page 1...

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): Pages = 1, so this box is '- [~]' by the check's own
# instruction. The walk executed cleanly and emitted "Fetching page 1..." exactly once, but a
# single-page walk cannot discriminate a working page counter from a broken one.
# What the tenant lacked: any access package assignment collection spanning a page boundary --
# oer-live-ap carries one assignment.
  ```

- [x] (verified 2026-09-11) **3.7 A page-1 failure carries `PartialValue` (EMPTY, never `$null`), `NextLink` and
  `PageNumber` on the ERROR.**

  This half IS provokable on a healthy tenant: a paged read whose very first request 404s.

  ```powershell
  # A GUID-shaped instance id that does not exist on a real definition. The -All decisions read
  # fails on page 1.
  $Ghost = '00000000-0000-0000-0000-000000000099'
  Get-OERAccessReviewInstanceDecision -Definition $DefId -Instance $Ghost `
      -ErrorAction SilentlyContinue -ErrorVariable Err
  # NARROW FIRST, then build. -ErrorVariable collects every record raised anywhere down the call
  # stack, including the raw Invoke-MgGraphRequest ones whose Exception has no PartialValue at all;
  # building the pscustomobject over those throws "Cannot index into a null array" into the middle
  # of the evidence. The published record is the one whose InvocationInfo.MyCommand.Name is the
  # cmdlet -- the same narrowing 3.5's block (a) already applies, and the one 3.1's own "Narrow to
  # the published record" note asks for in prose. See finding F-G.
  @($Err) | Where-Object { $_.InvocationInfo.MyCommand.Name } | ForEach-Object {
      [pscustomobject]@{
          Id           = $_.FullyQualifiedErrorId
          Command      = $_.InvocationInfo.MyCommand.Name
          HasPartial   = $null -ne $_.Exception.PSObject.Properties['PartialValue']
          PartialCount = @($_.Exception.PartialValue).Count
          PartialIsNull= $null -eq $_.Exception.PartialValue
          PageNumber   = $_.Exception.PageNumber
          HasNextLink  = -not [string]::IsNullOrEmpty([string]$_.Exception.NextLink)
      }
  } | Format-Table -AutoSize
  # And the count, so an empty table is distinguishable from a table nobody built.
  'records from the cmdlet: ' + @($Err | Where-Object { $_.InvocationInfo.MyCommand.Name }).Count
  ```

  **Expect:** at least one record with `HasPartial` `True`, `PageNumber` `1`, `HasNextLink` `True`
  and `PartialIsNull` `False`. `PartialCount` is `0` -- page 1 failed, so nothing had been
  aggregated -- and that is the point: an EMPTY ARRAY, not `$null`, so a caller can iterate it
  without a null guard. `NextLink` on a page-1 failure is the ORIGINAL request URI.
  **Do not print `NextLink` itself** -- it can carry a continuation token. `HasNextLink` is the
  assertion; a `True` is the evidence.
  **Failure looks like:** `HasPartial` `False` on every record, meaning the facts were attached to
  the ErrorRecord instead of to the Exception and did not survive the throw; or `PartialIsNull`
  `True`, meaning a `$null` was attached where an empty array was intended.

  > **Note the double-check on the same value.** `PartialCount` alone is worthless here:
  > `@($null).Count` is `1` and `$null.Count` is `0` in PowerShell, so a count of `0` could mean
  > either "empty array" or "no property at all". `HasPartial` and `PartialIsNull` are what
  > disambiguate it. Both traps are recorded in this repository's memory.
  >
  > **Traced:** the paging catch in `source/Private/Invoke-OERGraphRequest.ps1` does
  > `$PSItem.Exception | Add-Member -NotePropertyName PartialValue -NotePropertyValue $PartialSnapshot -Force`
  > (plus `NextLink` and `PageNumber`) and then a bare `throw`;
  > `source/Public/Get-OERAccessReviewInstanceDecision.ps1` re-publishes it with
  > `$PSCmdlet.WriteError($PSItem)`. `$PartialSnapshot` is `$AllValues.ToArray()`, which is an empty
  > `object[]` when nothing was aggregated.
  **Result:**
  
  ```powershell
> $Ghost = '00000000-0000-0000-0000-000000000099'  
> Get-OERAccessReviewInstanceDecision -Definition $DefId -Instance $Ghost `  
> -ErrorAction SilentlyContinue -ErrorVariable Err  
> @($Err) | ForEach-Object {  
> [pscustomobject]@{  
> Id = $_.FullyQualifiedErrorId  
> Command = $_.InvocationInfo.MyCommand.Name  
> HasPartial = $null -ne $_.Exception.PSObject.Properties['PartialValue']  
> PartialCount = @($_.Exception.PartialValue).Count  
> PartialIsNull= $null -eq $_.Exception.PartialValue  
> PageNumber = $_.Exception.PageNumber  
> HasNextLink = -not [string]::IsNullOrEmpty([string]$_.Exception.NextLink)  
> }  
> } | Format-Table -AutoSize  
InvalidOperation:  
Line |  
2 | [pscustomobject]@{  
| ~~~~~~~~~~~~~~~~~~  
| Cannot index into a null array.  
  
Id Command HasPartial PartialCount PartialIsNull PageNumber HasNextLink  
-- ------- ---------- ------------ ------------- ---------- -----------  
InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest Invoke-MgGraphRequest False 1 True False  
InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest Invoke-MgGraphRequest False 1 True False  
NotFound True 0 False 1 True  
NotFound True 0 False 1 True  
NotFound True 0 False 1 True  
NotFound True 0 False 1 True  
NotFound True 0 False 1 True  
InvalidOperation:  
Line |  
2 | [pscustomobject]@{  
| ~~~~~~~~~~~~~~~~~~  
| Cannot index into a null array.  
NotFound True 0 False 1 True  
NotFound,Get-OERAccessReviewInstanceDecision Get-OERAccessReviewInstanceDecision True 0 False 1 True

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): ticked -- the published record (Command =
# Get-OERAccessReviewInstanceDecision) carries HasPartial True, PartialCount 0, PartialIsNull False,
# PageNumber 1 and HasNextLink True, which is the Expect exactly.
# Worth recording: the Graph code on THIS path is NotFound, which IS inside the resolver's declared
# set. The contrast with 3.1/3.2's AccessPackageNotFound is why the decisions path behaves and the
# access-package path does not.
# The two "Cannot index into a null array" errors are block noise, not a defect: the pscustomobject is
# built for every collected record, including ones whose Exception has no such properties. Filter on
# $_.InvocationInfo.MyCommand.Name first. See finding F-G.
# APPLIED 2026-09-11: the block above now narrows before it builds, and prints the surviving record
# count so an empty table cannot pass for a clean one. The findings this run recorded stand -- the
# published record's six values are unchanged by the filter; only the noise goes. No re-run needed.
  ```

- [~] **3.8 A MID-WALK failure (page 2 or later) carries the same three facts.**

  **This is honestly not provokable on a healthy tenant, and this checklist will not pretend
  otherwise.** What #73 fixes is a failure on page N of an enumeration that already succeeded on
  pages 1..N-1. Producing one on demand needs a read whose permission, throttle state or backend
  health changes BETWEEN two pages of the same walk. None of that is arrangeable from a
  workstation:

  - Revoking a permission mid-walk is not schedulable -- the walk is seconds long and consent
    propagation is not.
  - A throttle cannot be provoked from one machine: a serial command loop issues roughly two
    requests a second against a bucket sized in the hundreds per second, about two orders of
    magnitude below the limit. PR #77's own live run confirmed it (11 requests in 5 s, then 10
    rounds over 8 definitions in 473 s, never throttled once).
  - Killing the network mid-walk produces a transport exception, which does take this catch -- but
    it is a different failure class from the one the issue is about, and the timing is not
    controllable.

  **The closest honest probe, if you want one:** run 3.6's walk against the largest paged collection
  the tenant has, with the network interface toggled off after the second `Fetching page` line
  appears. If you get it, record `PageNumber`, `HasPartial` and `PartialCount` exactly as 3.7 does;
  `PartialCount` should be non-zero and equal to the items from the completed pages.

  **If you do not run it:** mark this box `- [~]`, write "the mid-walk half is evidence-limited: a
  page-2-or-later failure cannot be arranged on a healthy tenant", and record that the mechanism is
  covered by the mocked guards `3a` (page 3 throws, `PartialValue` holds pages 1 and 2 in order) and
  `3e` (the `GraphExpectedCodeOnLaterPage` route) in
  `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`, plus check 3.7 above which proves the
  attach-to-Exception mechanism survives a real module boundary. **Do not tick it.**

  **The runnable part, and it is not a substitute for the check.** Before writing "cannot be
  arranged", establish the one fact that makes that claim checkable: whether ANY read in this tenant
  even spans a page boundary. A tenant where nothing pages cannot produce a mid-walk failure by
  construction, and that is a stronger write-up than an assertion.

  ```powershell
  $Candidates = @(
      @{ Label = 'access packages';          Script = { Get-OERAccessPackage -Verbose } }
      @{ Label = 'groups (all)';             Script = { Get-OERGroup -All -Verbose } }
      @{ Label = 'assignments on the package'; Script = { Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose } }
      @{ Label = 'decisions';                Script = { Get-OERAccessReviewInstanceDecision -Definition $DefId -Instance $InstId -Verbose } }
  )
  @($Candidates | ForEach-Object {
      $R = Measure-OerRequest -Label $_.Label -Script $_.Script
      [pscustomobject]@{ Label = $_.Label; Pages = $R.Pages; Items = $R.OutputCount; Requests = $R.RequestCount }
  }) | Format-Table -AutoSize
  ```

  **Record:** the table. Every `Pages` of `1` is the evidence for "no collection in this tenant
  spans a page boundary, so a page-2-or-later failure cannot be provoked here at all". A `Pages`
  above 1 identifies the one read the network-toggle probe above could be aimed at, if you want it.
  **Result:**
  ```powershell
> $Candidates = @(  
> @{ Label = 'access packages'; Script = { Get-OERAccessPackage -Verbose } }  
> @{ Label = 'groups (all)'; Script = { Get-OERGroup -All -Verbose } }  
> @{ Label = 'assignments on the package'; Script = { Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose } }  
> @{ Label = 'decisions'; Script = { Get-OERAccessReviewInstanceDecision -Definition $DefId -Instance $InstId -Verbose } }  
> )  
> @($Candidates | ForEach-Object {  
> $R = Measure-OerRequest -Label $_.Label -Script $_.Script  
> [pscustomobject]@{ Label = $_.Label; Pages = $R.Pages; Items = $R.OutputCount; Requests = $R.RequestCount }  
> }) | Format-Table -AutoSize  
  
Label Pages Items Requests  
----- ----- ----- --------  
access packages 1 6 1  
groups (all) 1 91 1  
assignments on the package 1 1 2  
decisions 1 1 1

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): box corrected to '- [~]' -- the check says in bold "Do not
# tick it." The mid-walk half is evidence-limited: a page-2-or-later failure cannot be arranged on a
# healthy tenant.
# The table above is stronger evidence than an assertion: NO collection in this tenant spans a page
# boundary. Every Pages is 1, the largest being 91 groups in a single page, so a mid-walk failure
# cannot be provoked here at all. Mechanism covered by the mocked guards 3a and 3e in
# tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1, plus check 3.7 above.
  ```

### 3.9 - 3.11: issue #75, the silent token refresh

- [x] (verified 2026-09-11) **3.9 Read the session's token state -- the precondition for 3.10, and the reason it is hard.**

  ```powershell
  & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState } | ForEach-Object {
      [pscustomobject]@{
          AuthMethod       = $_.AuthMethod
          Environment      = $_.Environment
          GraphTokenExpiry = $_.GraphTokenExpiry
          MinutesLeft      = [math]::Round(($_.GraphTokenExpiry - [datetime]::UtcNow).TotalMinutes, 1)
      }
  } | Format-List
  ```

  **Expect:** `AuthMethod` `Interactive` (for the main session), an `Environment` of `Global`, and a
  `MinutesLeft` in the tens. **Deliberately no ids are selected** -- `TenantId`, `ClientId` and
  `Account` are all identifiers and would have to be redacted; nothing below needs them.

  **Record `MinutesLeft`. It is the clock 3.10 runs against.**

  > **Why the 401 branch is hard to reach, and this is a measured fact rather than an excuse.**
  > `Initialize-OERAuth` runs in the `begin` block of every public cmdlet and re-acquires the token
  > whenever `GraphTokenExpiry` is not more than five minutes away
  > (`$script:_OERAuthState.GraphTokenExpiry -gt $FiveMinutesFromNow` in the `$GraphCached`
  > predicate). So the ordinary "leave it idle overnight and run a command" scenario NEVER reaches
  > the wrapper's 401 handler -- the pre-emptive refresh gets there first. The branch fires only
  > when a token is rejected while still clock-valid, or when a SINGLE cmdlet's own run crosses the
  > expiry after `Initialize-OERAuth` has already been called once. That second case is the one
  > 3.10 exploits.
  **Result:**
  
  ```powershell
> & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState } | ForEach-Object {  
> [pscustomobject]@{  
> AuthMethod = $_.AuthMethod  
> Environment = $_.Environment  
> GraphTokenExpiry = $_.GraphTokenExpiry  
> MinutesLeft = [math]::Round(($_.GraphTokenExpiry - [datetime]::UtcNow).TotalMinutes, 1)  
> }  
> } | Format-List  
  
AuthMethod : Interactive  
Environment : Global  
GraphTokenExpiry : 2026-09-11 12:51:37  
MinutesLeft : 29,8
  ```

- [~] **3.10 A genuinely expired token triggers exactly ONE silent refresh and ONE retry.**

  This is issue #75's fifth acceptance criterion and it is live-only.

  **Read the entry condition before picking a probe.** The 401 branch is reachable in exactly two
  states, and neither is "the token has expired":

  - **(i) The token is REJECTED while still clock-valid.** `$GraphCached` is true, so
    `Initialize-OERAuth` hands the session straight back and the stale token goes on the wire.
    Revocation and continuous access evaluation produce this. **Probe B.**
  - **(ii) A SINGLE cmdlet's own Graph work outlasts the token's remaining lifetime.**
    `Initialize-OERAuth` ran once, in `begin`, and is not consulted again for the rest of that
    invocation. **Probe A** -- and it has a hard arithmetic precondition, below.

  **PROBE A IS ARITHMETICALLY IMPOSSIBLE ON THIS TENANT. Measured 2026-09-11; do not try to wait it
  out.** Step 0 below timed the longest single-cmdlet read available here at **1.7 seconds**. Probe
  A needs one cmdlet's own Graph work to OUTLAST the token lifetime remaining when it starts, so it
  needs `MinutesLeftBefore` to be below `1.7 / 60` of a minute -- about 0.03 -- while
  `Initialize-OERAuth` refuses to hand back any token with five minutes or less left. The two
  conditions have no overlap, and waiting moves you between them rather than into a gap:

  - `MinutesLeft` **above 5**: `$GraphCached` is true, the 1.7-second read finishes with minutes to
    spare, nothing expires and nothing refreshes -- the outcome table's **row 4**. That is exactly
    what this run got: `MinutesLeftBefore 28.8`, `MinutesLeftAfter 28.7`, `Refreshes 0`.
  - `MinutesLeft` **5 or below**: `$GraphCached` is false, `Initialize-OERAuth` refreshes
    PRE-EMPTIVELY in `begin` before the read starts -- the outcome table's **row 2**.

  There is no third state. Probe A on this tenant can only ever produce row 4 or row 2, so the only
  remaining route to the 401 branch is **probe B with a THROWAWAY DELEGATED ACCOUNT** -- revocation
  leaves the token clock-valid, so `$GraphCached` stays true and the wrapper is actually reached.
  Run against the operator's own identity it would sign a production administrator out everywhere,
  which is why this run did not have it.

  **This is the measurement behind the branch's own standing claim that issue #75's FIFTH acceptance
  criterion may never be tickable on this tenant.** The criterion is not weakened and the box is not
  ticked on the strength of the mocked guards; what is recorded is that the only route left needs a
  prerequisite (a disposable delegated account) that has to be arranged before a run, not during
  one. A tenant with a genuinely slow read -- tens of seconds of Graph work in a single cmdlet with
  no nested public call -- would make probe A reachable again; this one has none.

  **Probe A -- non-intrusive, but only if your tenant has a read slow enough.** Run step 0 anyway on
  any tenant: `$ReadSeconds` is the number that decides whether the rest of probe A is worth the
  wait, and it is evidence either way.

  ```powershell
  # STEP 0 -- MEASURE FIRST. Probe A cannot fire unless one cmdlet's own Graph work runs longer
  # than the token lifetime you leave it. Time your longest single-cmdlet read:
  $Sw = [System.Diagnostics.Stopwatch]::StartNew()
  $null = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages -IncludeDecisions
  $ReadSeconds = [math]::Round($Sw.Elapsed.TotalSeconds, 1); $ReadSeconds

  # STEP 1 -- wait until MinutesLeft is just ABOVE five, and BELOW $ReadSeconds/60. Re-read 3.9's
  # block to check; do not run anything else in the meantime, since every cmdlet's begin block
  # would refresh the token and reset the clock.
  # STEP 2 -- capture the clock, run the read, capture the clock again.
  function Get-OerMinutesLeft {
      & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState } |
          ForEach-Object { [math]::Round(($_.GraphTokenExpiry - [datetime]::UtcNow).TotalMinutes, 1) }
  }
  $Before = Get-OerMinutesLeft
  $Log = Join-Path $LogDir 'refresh-probe.log'
  Start-Transcript -Path $Log | Out-Null
  $M = Measure-OerRequest -Label 'long walk across expiry' {
      Get-OERAccessReviewInstance -Definition $DefId -IncludeStages -IncludeDecisions -Verbose
  }
  Stop-Transcript | Out-Null
  $After = Get-OerMinutesLeft
  [pscustomobject]@{ MinutesLeftBefore = $Before; MinutesLeftAfter = $After
                     Refreshes = $M.Refreshes; Requests = $M.RequestCount } | Format-List
  $M.Verbose | Where-Object { $_ -match 'Token rejected' }
  ```

  **The two clock readings are the tell, and without them this check invites a false tick.** Read
  the outcome off this table, in this order:

  | `MinutesLeftBefore` | `MinutesLeftAfter` | `Refreshes` | What actually happened |
  |---|---|---|---|
  | above 5 | LOWER than before | `1` | **The check ran and PASSED.** The token expired mid-read, the wrapper caught the 401, refreshed once and retried once. |
  | **5 or below** | ~55-60 (jumped) | `0` | **The check did NOT run.** `Initialize-OERAuth` refreshed pre-emptively in `begin` before the read even started. Mark `- [~]`; the window was on the wrong side of the five-minute boundary. |
  | above 5 | ~55-60 (jumped) | `0` | **The check did NOT run.** The read finished before the token expired -- `$ReadSeconds` was shorter than the lifetime left. Mark `- [~]`. |
  | above 5 | LOWER than before | `0` | **The check did NOT run.** Nothing expired and nothing refreshed. Mark `- [~]`. |
  | any | any | `2` or more **for the same request** | **FAILURE** -- a retry loop. Two refresh lines back to back for one request is the defect. |

  **A `Refreshes` of `0` is never a pass**, however clean the run looked. "No browser, command
  completed, full result" satisfies three of the sentences below and proves nothing at all if the
  401 branch was never entered.

  **Expect, when the table's first row is what you got:** exactly ONE
  `[Invoke-OERGraphRequest] Token rejected (status=401). Forcing re-authentication and retrying
  once...` line **per rejected request**, the same request immediately succeeding afterwards, the
  command completing normally with the full result, and **no browser window**.

  > **`Export-OERInventory` is NOT a usable probe-A read, and this was checked rather than assumed.**
  > `Get-OERInventory` calls fifteen other PUBLIC cmdlets (`Get-OERGroup`, `Get-OERAccessPackage`,
  > `Get-OERAccessReviewDefinition`, ...), and every one of them calls `Initialize-OERAuth` in its
  > own `begin`. So the first nested cmdlet that starts within five minutes of expiry refreshes
  > pre-emptively and the 401 branch is never reached, however long the whole walk takes. Probe A
  > needs a cmdlet that does its own Graph work with no nested public call --
  > `Get-OERAccessReviewInstance`, `Get-OERAccessPackageAssignment` and
  > `Get-OERAccessReviewInstanceDecision` all qualify.
  >
  > **If step 0 shows your longest such read runs in seconds, probe A cannot fire on this tenant.**
  > That is the likely outcome on a small tenant, and it is a legitimate finding: say so, give
  > `$ReadSeconds`, and go to probe B or to the unprovable write-up below. Do not stretch the wait
  > to make the numbers look right -- waiting longer moves `MinutesLeftBefore` DOWN through five,
  > which lands you in the table's second row.

  **Probe B -- intrusive, only on a throwaway account. This is the one that reliably reaches the
  branch**, since it produces state (i): the token is rejected while `$GraphCached` is still true,
  so no pre-emptive refresh can get in the way. Revoke the signed-in user's sessions from the Entra
  portal (or `POST /users/{id}/revokeSignInSessions`), then issue any read.

  > **Read the result of probe B carefully.** Revocation kills the refresh token as well as the
  > access token, so MSAL may have nothing left to refresh with and `Get-AzToken -Interactive` will
  > open a browser. **A browser prompt in probe B is NOT a defect of #75** -- it is MSAL correctly
  > reporting that silent refresh is impossible. What probe B still proves is that the 401 was
  > DETECTED and routed to `Initialize-OERAuth -ForceRefresh` exactly once, which is what
  > `Refreshes = 1` records. Record which of the two happened.

  **If neither probe can be arranged:** mark this box `- [~]`, write "cannot be verified, and
  therefore we do not know -- a genuinely expired token could not be provoked", and record that the
  detection logic is covered by tests `2a`, `2d` and `2f` in
  `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`, which build a real
  `Microsoft.Kiota.Abstractions.ApiException` rather than a synthetic stand-in. **Do not tick it.**
  An unprovokable check is written up as unprovable.

  > **Traced:** the verbose string is verbatim from `source/Private/Invoke-OERGraphRequest.ps1`
  > (`Write-Verbose "[Invoke-OERGraphRequest] Token rejected (status=$StatusCode). Forcing
  > re-authentication and retrying once..."`), which is the line the helper's `Refreshes` counter
  > matches. The single retry, and the fact that a second failure is surfaced rather than retried
  > again, are both visible in the same block: `if ($RefreshAttempt.Kind -ne 'Failure') { return
  > $RefreshAttempt.Value }` followed by `throw Convert-GraphHttpException $RefreshAttempt.Value`.
  **Result:**
  
  ```powershell
> # STEP 0 -- MEASURE FIRST. Probe A cannot fire unless one cmdlet's own Graph work runs longer  
> # than the token lifetime you leave it. Time your longest single-cmdlet read:  
> $Sw = [System.Diagnostics.Stopwatch]::StartNew()  
> $null = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages -IncludeDecisions  
> $ReadSeconds = [math]::Round($Sw.Elapsed.TotalSeconds, 1); $ReadSeconds  
1,7  
>  
> # STEP 1 -- wait until MinutesLeft is just ABOVE five, and BELOW $ReadSeconds/60. Re-read 3.9's  
> # block to check; do not run anything else in the meantime, since every cmdlet's begin block  
> # would refresh the token and reset the clock.  
> # STEP 2 -- capture the clock, run the read, capture the clock again.  
> function Get-OerMinutesLeft {  
> & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState } |  
> ForEach-Object { [math]::Round(($_.GraphTokenExpiry - [datetime]::UtcNow).TotalMinutes, 1) }  
> }  
> $Before = Get-OerMinutesLeft  
> $Log = Join-Path $LogDir 'refresh-probe.log'  
> Start-Transcript -Path $Log | Out-Null  
> $M = Measure-OerRequest -Label 'long walk across expiry' {  
> Get-OERAccessReviewInstance -Definition $DefId -IncludeStages -IncludeDecisions -Verbose  
> }  
> Stop-Transcript | Out-Null  
> $After = Get-OerMinutesLeft  
> [pscustomobject]@{ MinutesLeftBefore = $Before; MinutesLeftAfter = $After  
> Refreshes = $M.Refreshes; Requests = $M.RequestCount } | Format-List  
  
MinutesLeftBefore : 28,8  
MinutesLeftAfter : 28,7  
Refreshes : 0  
Requests : 3  
  
> $M.Verbose | Where-Object { $_ -match 'Token rejected' }

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): cannot be verified, and therefore we do not know.
# MinutesLeftBefore 28,8 / MinutesLeftAfter 28,7 / Refreshes 0 is the outcome table's FOURTH row:
# nothing expired and nothing refreshed, so the 401 branch was never entered. A Refreshes of 0 is
# never a pass, however clean the run looked.
# PROBE A IS ARITHMETICALLY IMPOSSIBLE ON THIS TENANT, and that is the finding rather than a failure
# to try harder. $ReadSeconds = 1,7: a 1,7-second read cannot cross a token expiry. Waiting does not
# help -- with more than five minutes left you land on this same row 4, and with five minutes or less
# you land on row 2, because Initialize-OERAuth refreshes pre-emptively in begin before the read even
# starts. There is no window between the two.
# Probe B (revocation, which leaves the token clock-valid so $GraphCached stays true) is the only
# remaining route, and on this tenant it would revoke the operator's own PRODUCTION sessions. It needs
# a throwaway delegated account -- a prerequisite this run did not have.
# Detection logic is covered by tests 2a, 2d and 2f in
# tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1, which build a real
# Microsoft.Kiota.Abstractions.ApiException rather than a synthetic stand-in. See finding F-J.
# APPLIED 2026-09-11: the arithmetic is now written into the check itself, above probe A, so the next
# reader does not spend an afternoon waiting for a window that does not exist. No re-run is scheduled
# in chapter U: the prerequisite probe B needs -- a throwaway delegated account -- is a setup task,
# not a checklist step, and inventing a re-run box for it would be a box nobody can tick either.

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-13): SECOND DATA POINT, and it closes the write-up.
# The 2026-09-11 21:17 run crossed the boundary from the other side: MinutesLeft was 4,5 when the
# read was issued, a re-authentication prompt opened, and MinutesLeftBefore read 84,3 by the time the
# probe measured it -- the token had ALREADY been replaced. That is the outcome table's row 2.
#
#   | run                  | MinutesLeftBefore | what happened                          | table row |
#   |----------------------|-------------------|----------------------------------------|-----------|
#   | 2026-09-11 (earlier) | 28,8              | nothing expired, nothing refreshed      | row 4     |
#   | 2026-09-11 21:17     | 4,5 -> 84,3       | pre-emptive refresh in begin, browser   | row 2     |
#
# BOTH SIDES OF THE FIVE-MINUTE BOUNDARY HAVE NOW BEEN RUN, and neither reaches the wrapper. That
# turns the claim from an arithmetic argument into a measurement: above five minutes a 1,7-second
# read cannot span an expiry; at or below five minutes Initialize-OERAuth re-acquires in begin before
# the read starts. There is no window in between. The branch IS reachable -- check U.4 reached it on
# an app-only session by having the service no longer accept a clock-valid token -- but not through
# ordinary token expiry on a delegated session.
# Do not use $ReadSeconds = 21 from the 21:17 run as a read time: that is how long the browser prompt
# stood open. The read itself is 1,7 s.
# One loose end, resolved and recorded rather than chased: immediately after that re-authentication
# every entitlement-management read answered "Forbidden: Attempted to perform an unauthorized
# operation" until the session was reconnected. Most likely the broker prompt landed on a different
# cached account or a narrower scope set. It did not recur, and 3.1 read normally the next morning.
  ```

- [~] **3.11 An app-only session gets `AppOnlyTokenRefreshUnsatisfiable`, and no browser prompt.**

  An app-only session cannot silently force-refresh: the credential material is deliberately not
  cached, so calling `Initialize-OERAuth` would throw on the missing secret or certificate. The
  wrapper detects this and emits a clear error instead.

  **The app-only session needs an app registration holding `EntitlementManagement.Read.All`, and on
  the 2026-09-11 run that was NOT `oer-live-apponly`.** `Initialize-OerS4Prereq.ps1 -IncludeAppOnly`
  creates one by that name and consents the permission to it, but `-IncludeAppOnly` was never
  passed, so the check signed in as the tenant's pre-existing app registration for this module --
  rows 15 and 17 of the placeholder table are that app's client id and its service principal object
  id. **Re-run against the SAME registration that run used**, so step 1's disable and step 3's
  re-enable land on the object T.2 already tracks rather than on a second one. Whichever you use,
  confirm the target at step 1 before disabling it: the prompts take an application (client) id, and
  step 1 turns the principal behind that id off.

  **Neither route mints the client secret for you** -- `addPassword` returns the value in cleartext
  and it would then live in this console's scrollback and in any transcript. Add one in the portal,
  keep it in your secret store, and read it from there.

  ```powershell
  # STEP 0 -- the connect. NOTHING here is transcribed into the result block, and the two Read-Host
  # lines exist so no secret ever appears in a command you can scroll back to.
  # Captured BEFORE Disconnect-OER, and deliberately never printed -- a tenant id is an identifier
  # and would have to be redacted out of the result block again.
  $TenantIdValue = & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.TenantId }
  $AppId  = Read-Host 'app-only application (client) id'
  $Secret = Read-Host 'client secret' -AsSecureString
  Disconnect-OER
  Connect-OER -TenantId $TenantIdValue -ClientId $AppId -ClientSecret $Secret
  Remove-Variable Secret -ErrorAction SilentlyContinue
  & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.AuthMethod }
  ```

  **STEP 1 -- the probe, and it is NOT 3.10's probe B.** Revoking sign-in sessions does nothing to a
  client-credentials token: there is no user session behind it. What DOES reject a still-clock-valid
  app-only token is **disabling the service principal**, which is a one-field change reversed by the
  same field -- and on the registration this check actually uses, a standing one, that reversal at
  step 3 is not optional. Because the token stays clock-valid,
  `$GraphCached` stays true, `Initialize-OERAuth` hands the session straight back, and the wrapper's
  401 branch is actually reached -- which is the whole point.

  Run this in a SECOND `pwsh` window, signed in as yourself, so the app-only session in the first
  window is not disturbed. `$AppId` is the same value you typed at step 0's prompt.

  ```powershell
  Connect-MgGraph -TenantId (Read-Host 'tenant id') -NoWelcome -Scopes 'Application.ReadWrite.All'
  $AppId = Read-Host 'app-only application (client) id'
  $Sp = @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `
      -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,displayName,accountEnabled").value)[0]
  $Sp | Format-List displayName, accountEnabled      # confirm the TARGET before the next line

  # Disable it. One field, and step 3 puts it back -- check the displayName printed above is the app
  # you meant FIRST. On the 2026-09-11 run this was the tenant's standing registration, not a
  # throwaway, so leaving it off is a real outage for anything else using it.
  Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)" `
      -Body '{"accountEnabled":false}' -ContentType 'application/json'
  ```

  **STEP 2 -- THE PROBE. It runs BEFORE the re-enable, and the block order below is load-bearing.**
  The 2026-09-11 run printed the re-enable block above the probe block, ran them in the order they
  were printed, and therefore measured an already-re-enabled principal: `Refreshes = 0`, `Requests
  = 2`, an empty `ErrorIds` and no "Token rejected" line. Nothing about the module was learned. The
  blocks are now in execution order and step 3 is the LAST thing you run. See finding F-I.

  ```powershell
  # Back in the APP-ONLY window, once the second window reports accountEnabled False.
  #
  # '2>&1', NOT '-ErrorVariable', AND NO '-ErrorAction SilentlyContinue'. Both halves are measured,
  # not stylistic (2026-09-11, in a clean pwsh against a synthetic Measure-OerRequest):
  #   * '-ErrorVariable Err' written INSIDE this scriptblock sets $Err in the scriptblock's own
  #     CHILD scope. '&' on a scriptblock creates one, so the outer $Err keeps whatever it held --
  #     a preset sentinel survived the call untouched. The old form of this block did exactly that,
  #     so its ErrorIds line would have read EMPTY whether the branch fired or not. That is the
  #     guard-shaped-but-inert form PR #34 recorded, arriving here as an evidence command.
  #   * '-ErrorAction SilentlyContinue' SUPPRESSES the redirect: with it, '2>&1' captured ZERO
  #     records; without it, one ErrorRecord. The cmdlet's error is non-terminating either way.
  $M = Measure-OerRequest -Label 'app-only after SP disable' {
      Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose 2>&1
  }
  $ErrRecords = @($M.Output |
      Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo.MyCommand.Name })
  [pscustomobject]@{
      Refreshes  = $M.Refreshes
      Requests   = $M.RequestCount
      ErrorCount = $ErrRecords.Count
      ErrorIds   = ($ErrRecords | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join '; '
      Categories = ($ErrRecords | ForEach-Object { [string]$_.CategoryInfo.Category }) -join '; '
  } | Format-List
  # Two evidence lines, each of which prints something whatever happened. EXPECT 0 HERE, and read
  # the Expect below before treating that as a failure: on an app-only session the wrapper throws
  # ABOVE the "Token rejected" verbose line, so Refreshes and this count are both 0 on a PASS.
  # ErrorIds is the discriminator, not Refreshes.
  'token-rejected lines: ' + @($M.Verbose | Where-Object { $_ -match 'Token rejected' }).Count
  $M.Verbose | Where-Object { $_ -match 'Token rejected' }
  ```

  **Propagation is not instant and this block will not invent a number for it.** A disabled service
  principal's existing token keeps being accepted until the change reaches the token-validating
  endpoint. If the read simply succeeds, wait and re-run -- do not conclude anything from the first
  attempt. If it never fails, that is `- [~]` with "the service principal disable did not produce a
  401 within the time waited", and it is a fact about propagation, not about the module.

  **How you know the disable really took, and the 2026-09-11 run proved it by accident.** While the
  principal was off, a Graph call issued from the APP-ONLY window -- any call, on that window's own
  still-clock-valid app-only token -- came back **HTTP 401 `Authorization_IdentityDisabled`, "The
  authenticating application principal is disabled."** (The run hit it because the re-enable block
  was pasted into the wrong window; the fact it recorded is the useful part.) That is precisely the
  condition the wrapper's 401 branch exists for: a token inside its lifetime that the service no
  longer accepts. Seeing that 401 from the app-only window is the green light to run the probe
  block above; not seeing it means propagation has not landed yet, so wait rather than concluding.
  **Do not render that record.** Read its status line only -- a raw `Invoke-MgGraphRequest` failure
  carries the `HttpRequestMessage`, and with it the bearer token, on its `TargetObject`.

  **STEP 3 -- RE-ENABLE, and it is the LAST step. Do not leave the principal off.**

  ```powershell
  # In the second window, once the probe above has answered -- not before.
  Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)" `
      -Body '{"accountEnabled":true}' -ContentType 'application/json'
  @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `
      -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)?`$select=accountEnabled")).accountEnabled
  ```

  **Expect:** `AuthMethod` reads `ClientSecret` (or `ClientCertificate`), and when the token is
  rejected the call fails with FullyQualifiedErrorId **`AppOnlyTokenRefreshUnsatisfiable`**, category
  `AuthenticationError`, and a message naming the auth method and directing the operator to
  re-run `Connect-OER`. **No browser window opens at any point**, and the wrapper does not call
  `Initialize-OERAuth` **for the refresh** -- that is the whole point of the branch. (The cmdlet's
  own `begin` block still calls it once on the way in, as it does for every cmdlet; what the branch
  skips is the `-ForceRefresh` call.)

  **`Refreshes` of `0` and `token-rejected lines: 0` are the PASS here.** The app-only guard throws
  ABOVE the "Token rejected" verbose line and above `Initialize-OERAuth -ForceRefresh`, so the
  counter this file uses everywhere else as the proof of life stays at `0` by construction on this
  one check. It is therefore NOT the discriminator -- `0` is also what the 2026-09-11 wrong-order
  run produced. **`ErrorIds` is:** `AppOnlyTokenRefreshUnsatisfiable,Get-OERAccessPackageAssignment`
  means the branch fired; an EMPTY `ErrorIds` means the read succeeded and the probe met an enabled
  principal.

  > **THE NEAR-MISS TO CHECK FOR FIRST, and it is the likely outcome of probe A.** An app-only
  > session whose token is within five minutes of expiry trips a guard BEFORE the request is sent:
  > the cmdlet's `begin` calls `Initialize-OERAuth`, `$GraphCached` is false, and
  > `source/Private/Initialize-OERAuth.ps1` fails at its `$InheritIdentity` app-only guard with
  > FullyQualifiedErrorId **`AppOnlySessionCredentialUnavailable`** -- also category
  > `AuthenticationError`, also naming the auth method and telling you to re-run `Connect-OER`. The
  > two ids differ by four words and the two messages read almost identically.
  >
  > **`AppOnlySessionCredentialUnavailable` is not by itself a pass for this check, and it is not by
  > itself a miss either.** *(Corrected 2026-09-13 by check U.4, which measured both ids from one
  > invocation.)* It proves the pre-emptive refresh path refuses app-only correctly, which is a
  > different guarantee -- but the refusal is NOT fatal, so the cmdlet continues into `process` and
  > the wrapper's 401 branch can still be entered in the very same call. Do not read this id as
  > proof that the wrapper was skipped. Read `ErrorIds` as a list: if
  > `AppOnlyTokenRefreshUnsatisfiable` appears anywhere in it, the branch fired. Only when it does
  > not appear is this box `- [~]` -- record the ids you actually got, and note that probe B
  > (revocation, which leaves the token clock-valid and so keeps `$GraphCached` true) is another
  > route to `AppOnlyTokenRefreshUnsatisfiable`.

  **Failure looks like:** a browser prompt (the app-only session was pushed into an interactive
  re-auth), or a generic 401 surfacing instead of the tailored error. **Not a failure, but not a
  pass either:** an `ErrorIds` carrying `AppOnlySessionCredentialUnavailable` and NOTHING else, per
  the note above -- the id beside `AppOnlyTokenRefreshUnsatisfiable` is expected, and is a pass.

  **If 3.10 could not be provoked, this cannot be either.** Mark it `- [~]` with the same reason and
  the same pointer to tests `2b` (both variants) in
  `tests/Unit/Private/Invoke-OERGraphRequest.Tests.ps1`, which assert
  `Initialize-OERAuth` is invoked `-Times 0 -Exactly` on this shape.

  **Reconnect as the delegated identity before section 4.**

  > **Traced:** `source/Private/Invoke-OERGraphRequest.ps1` throws
  > `'AppOnlyTokenRefreshUnsatisfiable'` with category `AuthenticationError` when
  > `$script:_OERAuthState.AuthMethod -in 'ClientSecret', 'ClientCertificate'`, BEFORE the
  > `Initialize-OERAuth` call and before the verbose refresh line.
  **Result:**
  
  ```powershell
#1st Window (App Only)
> $TenantIdValue = & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.TenantId }  
> $TenantIdValue  
00000000-0000-0000-0000-000000000016  
> $AppId = Read-Host 'oer-live-apponly application (client) id'  
oer-live-apponly application (client) id: 00000000-0000-0000-0000-000000000015  
> $Secret = Read-Host 'client secret' -AsSecureString  
client secret: ****************************************  
> Disconnect-OER  
> Connect-OER -TenantId $TenantIdValue -ClientId $AppId -ClientSecret $Secret  
> Remove-Variable Secret -ErrorAction SilentlyContinue  
> & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.AuthMethod }  
ClientSecret

#2nd Window (Interactive)
> Connect-MgGraph -TenantId (Read-Host 'tenant id') -NoWelcome -Scopes 'Application.ReadWrite.All'  
tenant id: 00000000-0000-0000-0000-000000000016  
WARNING: Note: Sign in by Web Account Manager (WAM) is enabled by default on Windows. If using an embedded terminal, the interactive browser window may be hidden behind other windows.  
> $AppId = Read-Host 'oer-live-apponly application (client) id'  
oer-live-apponly application (client) id: 00000000-0000-0000-0000-000000000015  
> $Sp = @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `  
> -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,displayName,accountEnabled").value)[0]  
> $Sp | Format-List displayName, accountEnabled # confirm the TARGET before the next line  
  
displayName : <the module's own pre-existing app registration -- REDACTED>  
accountEnabled : True  
  
>  
> # Disable it. This is one field on an app THIS SPRINT created, and the last line here puts it back.  
> Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)" `  
> -Body '{"accountEnabled":false}' -ContentType 'application/json'  
>
#App Only Window 
> # RE-ENABLE, in the second window, as soon as the probe below has answered. Do not leave it off.  
> Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)" `  
> -Body '{"accountEnabled":true}' -ContentType 'application/json'  
Invoke-MgGraphRequest: PATCH https://graph.microsoft.com/v1.0/servicePrincipals/00000000-0000-0000-0000-000000000017  
HTTP/1.1 401 Unauthorized  
Cache-Control: no-cache  
Transfer-Encoding: chunked  
Vary: Accept-Encoding  
Strict-Transport-Security: max-age=31536000  
request-id: 00000000-0000-0000-0000-000000000018  
client-request-id: 00000000-0000-0000-0000-000000000019  
x-ms-ags-diagnostic: {"ServerInfo":{"DataCenter":"Sweden Central","Slice":"E","Ring":"3","ScaleUnit":"001","RoleInstance":"GV2PEPF00000EC8"}}  
Date: Fri, 11 Sep 2026 17:56:18 GMT  
Content-Type: application/json  
  
{"error":{"code":"Authorization_IdentityDisabled","message":"The authenticating application principal is disabled.","innerError":{"date":"2026-09-11T17:56:19","request-id":"00000000-0000-0000-0000-000000000018","client-request-id":"00000000-0000-0000-0000-000000000019"}  
}}  
> @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `  
> -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)?`$select=accountEnabled")).accountEnabled  
Invoke-MgGraphRequest: GET https://graph.microsoft.com/v1.0/servicePrincipals/00000000-0000-0000-0000-000000000017?$select=accountEnabled  
HTTP/1.1 401 Unauthorized  
Cache-Control: no-cache  
Transfer-Encoding: chunked  
Vary: Accept-Encoding  
Strict-Transport-Security: max-age=31536000  
request-id: 00000000-0000-0000-0000-000000000020  
client-request-id: 00000000-0000-0000-0000-000000000021  
x-ms-ags-diagnostic: {"ServerInfo":{"DataCenter":"Sweden Central","Slice":"E","Ring":"3","ScaleUnit":"001","RoleInstance":"GV2PEPF00000EC8"}}  
Date: Fri, 11 Sep 2026 17:56:25 GMT  
Content-Type: application/json  
  
{"error":{"code":"Authorization_IdentityDisabled","message":"The authenticating application principal is disabled.","innerError":{"date":"2026-09-11T17:56:25","request-id":"00000000-0000-0000-0000-000000000020","client-request-id":"00000000-0000-0000-0000-000000000021"}  
}}

# Interactive
> # RE-ENABLE, in the second window, as soon as the probe below has answered. Do not leave it off.  
> Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)" `  
> -Body '{"accountEnabled":true}' -ContentType 'application/json'  
> @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `  
> -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)?`$select=accountEnabled")).accountEnabled  
True  
>

#App Only
> # Back in the app-only window, once the second window reports accountEnabled False.  
> $M = Measure-OerRequest -Label 'app-only after SP disable' {  
> Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose -ErrorAction SilentlyContinue -ErrorVariable Err  
> }  
> [pscustomobject]@{  
> Refreshes = $M.Refreshes  
> Requests = $M.RequestCount  
> ErrorIds = (@($Err) | Where-Object { $_.InvocationInfo.MyCommand.Name } |  
> ForEach-Object { $_.FullyQualifiedErrorId }) -join '; '  
> } | Format-List  
  
Refreshes : 0  
Requests : 2  
ErrorIds :  
  
> $M.Verbose | Where-Object { $_ -match 'Token rejected' }  
>

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): cannot be verified, and therefore we do not know --
# the probe ran in the WRONG ORDER. Read the transcript above: the service principal was disabled, the
# app-only window's own calls correctly answered 401 Authorization_IdentityDisabled ("The
# authenticating application principal is disabled."), and THEN the second window re-enabled it
# (accountEnabled True) BEFORE the Measure-OerRequest probe was run. The probe therefore met an
# already-enabled principal: Refreshes 0, Requests 2, ErrorIds empty, and no "Token rejected" line.
# AppOnlyTokenRefreshUnsatisfiable was never reached.
# What DID hold: AuthMethod reads ClientSecret, and the 401 above proves the disable produces exactly
# the state the wrapper's branch needs -- a token rejected while still clock-valid. It is the BLOCK
# ORDERING in this checklist that is wrong, not the probe: the re-enable block is printed before the
# probe block. Re-run with the probe first and the re-enable last. See finding F-I.
# APPLIED 2026-09-11: the blocks above are now in execution order -- step 1 disable, step 2 probe,
# step 3 re-enable -- and the 401 Authorization_IdentityDisabled is written up as the go/no-go signal
# rather than left buried in this note. Chapter U.4 is the re-run; this box stays '- [~]' until it
# carries a result.
# FOR SECTION T.2: this check used the tenant's PRE-EXISTING app registration for this module
# (appId 00000000-0000-0000-0000-000000000015, service principal object id 00000000-0000-0000-0000-000000000017), NOT a throwaway created by
# the prereq script -- -IncludeAppOnly was never passed. It is referred to by role and never by its
# display name, since it is a standing registration and not a test object that stops resolving once
# the run is torn down. That service principal was disabled and re-enabled during this check and now
# reads accountEnabled True. Its client secret was entered through Read-Host and never written to
# this file; T.2 carries the rotation decision, and there is nothing here to delete.
  ```

---

## 4. Read-only -- carried from PR #64

- [x] (verified 2026-09-11) **4.1 A stage pipes into the decision reader.** *(PR #64 6.1, unchanged.)* **Requires the
  MULTI-STAGE review from section 2.** Graph builds an instance's `stages` collection only from the
  definition's `stageSettings`, so on a single-stage review `$Inst.Stages` is legitimately EMPTY,
  nothing reaches the pipe, and the cmdlet prints nothing. That is not a failure of this check --
  it means the review under test is single-stage. Go back to 2.5.

  ```powershell
  $Inst = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages
  $Inst.Stages | Select-Object -First 1 | Get-OERAccessReviewInstanceDecision -Verbose
  ```

  **Expect:** the stage-scoped decisions, and the verbose URI ends
  `.../definitions/<def>/instances/<inst>/stages/<stage>/decisions`. **The URI is the proof, not the
  row count** -- a stage that has not started yet can legitimately carry zero decisions, and this
  check is about where the request went.
  **Failure looks like:** prompts for `-Definition` and `-Instance` -- the parent ids did not land
  on the stage shape.

  > **Re-verified against Sprint 3's `$select` change, since a reader would expect it to have
  > moved.** It has not. `Get-OERAccessReviewInstance -IncludeDecisions` gained a `$select` in
  > Sprint 3, but `Get-OERAccessReviewInstanceDecision` -- the cmdlet this check drives -- still
  > builds a bare `"$InstBase/stages/$Stage/decisions"` with no query string at all. The "URI ends
  > `/decisions`" expectation is therefore still literally correct.
  >
  > **Traced:** `-Definition`, `-Instance` and `-Stage` all carry `ValueFromPipelineByPropertyName`
  > with aliases `AccessReviewDefinitionId`, `AccessReviewInstanceId` and `AccessReviewStageId`
  > respectively, and `ConvertTo-OERAccessReviewStage` emits exactly those three property names.
  **Result:**
  
  ```powershell
> $Inst = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages  
> $Inst.Stages | Select-Object -First 1 | Get-OERAccessReviewInstanceDecision -Verbose  
VERBOSE: [Initialize-OERAuth] Returning cached auth state for tenant '00000000-0000-0000-0000-000000000016'.  
VERBOSE: [Invoke-OERGraphRequest] Fetching page 1...  
VERBOSE: [Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000005/instances/00000000-0000-0000-0000-000000000005/stages/00000000-0000-0000-0000-000000000008/decisions  
  
Principal Decision ReviewedBy ApplyResult Id  
--------- -------- ---------- ----------- --  
oer-live-assignee NotReviewed New 00000000-0000-0000-0000-000000000022
  ```

- [x] (verified 2026-09-11) **4.2 The stage shape carries its parents.** *(PR #64 6.2; one clarification.)* **Requires the
  MULTI-STAGE review**, for the same reason as 4.1: with no `stageSettings` on the definition there
  is no `stages` collection and `Format-List` prints nothing. Empty output here means single-stage,
  not a missing property.

  ```powershell
  $Inst.Stages | Select-Object -First 1 | Format-List *
  ```

  **Expect:** `AccessReviewStageId`, `AccessReviewInstanceId` and `AccessReviewDefinitionId` all
  populated, alongside `Status`, `StartDateTime`, `EndDateTime`, `Reviewers` and
  `FallbackReviewers` -- **eight properties in total**, plus the `Id` alias.
  **Failure looks like:** any of the three ids missing or `$null`.

  > **CLARIFIED from PR #64 6.2.** The original wrote "alongside the original six properties", which
  > is arithmetically right (six before the fix, two added) but reads as a total. The object has
  > eight properties; naming them all is what makes `Format-List *` falsifiable rather than
  > impressionistic.
  >
  > **Traced:** the eight are the literal keys of the `[PSCustomObject]@{...}` in
  > `source/Private/ConvertTo-OERAccessReviewStage.ps1`. `Id` is an `AliasProperty` of
  > `AccessReviewStageId`, registered in `source/suffix.ps1`.
  **Result:**
  
  ```powershell
> $Inst.Stages | Select-Object -First 1 | Format-List *  
  
Status : InProgress  
StartDateTime : 2026-09-11 09:05:36  
EndDateTime : 2026-09-14 09:05:36  
Reviewers : {System.Collections.Hashtable}  
FallbackReviewers : {}  
AccessReviewStageId : 00000000-0000-0000-0000-000000000008  
AccessReviewInstanceId : 00000000-0000-0000-0000-000000000005  
AccessReviewDefinitionId : 00000000-0000-0000-0000-000000000005  
Id : 00000000-0000-0000-0000-000000000008

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): ticked -- the Expect is met exactly. AccessReviewStageId,
# AccessReviewInstanceId and AccessReviewDefinitionId are all populated, alongside Status,
# StartDateTime, EndDateTime, Reviewers and FallbackReviewers: eight properties in total, plus the Id
# alias. AccessReviewInstanceId equals AccessReviewDefinitionId because this is a OneTime review (see
# 2.7's note), not because a parent id is missing -- which is the failure mode this check exists to
# catch, so the distinction matters.
  ```

- [x] (verified 2026-09-11) **4.3 A GUID still short-circuits with no lookup -- on the access review DEFINITION resolver.**
  *(PR #64 6.4, expectation UNCHANGED.)*

  ```powershell
  Set-OERAccessReviewDefinition -Id $DefId -DisplayName 'oer-live-ar-multistage-renamed' -WhatIf -Verbose
  ```

  **Expect:** no display-name query in the verbose output. The first Graph request is the
  read-modify-write `GET .../accessReviews/definitions/<def-id>`, and nothing is written
  (`-WhatIf`).
  **Failure looks like:** a `displayName eq '<guid>'` filter going out.

  > **THIS CHECK DOES NOT GOVERN THE PATH ISSUE #71 CHANGED, and the sprint verified that rather
  > than assuming it.** 6.4 exercises `Resolve-OERAccessReviewDefinitionId` -- access review
  > DEFINITIONS. Issue #71 changed `Resolve-OERAccessPackageId` -- access PACKAGES. They are sibling
  > helpers with the same shape and different subjects, and the sprint's own plan initially assumed
  > they were one helper and pre-decided to "update 6.4's expectation". That premise was false.
  > `source/Private/Resolve-OERAccessReviewDefinitionId.ps1` still reads, verbatim:
  > `if (Test-OERGuid -Value $DisplayName) { return $DisplayName }` -- no Graph call. So 6.4 carries
  > across exactly as it stood.
  >
  > **The access package equivalent is check 3.3, and it has the OPPOSITE expectation:** a GUID now
  > costs exactly one existence read. Both facts are written here so a later reader does not
  > re-derive them, and so nobody "fixes" 4.3 to match 3.3.
  **Result:**
  
  ```powershell
> Set-OERAccessReviewDefinition -Id $DefId -DisplayName 'oer-live-ar-multistage-renamed' -WhatIf -Verbose  
VERBOSE: [Initialize-OERAuth] Returning cached auth state for tenant '00000000-0000-0000-0000-000000000016'.  
VERBOSE: [Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000005  
What if: Performing the operation "Update access review definition" on target "00000000-0000-0000-0000-000000000005".
  ```

- [~] **4.4 Access review decisions return every page.** *(PR #64 7.1, unchanged.)*

  ```powershell
  $D = @(Get-OERAccessReviewInstanceDecision -Definition $DefId -Instance $InstId)
  $D.Count
  ```

  **Expect:** the full decision count, matching what the portal shows.
  **Failure looks like:** a round number that smells like a page size (100, 200) and is less than
  the portal's count.
  **Vacuity warning:** a review whose instance has NO decisions returns `0`, which matches a portal
  showing `0`, and proves nothing about paging. Sprint 3 found that no access review in the
  `Omnicit` tenant had a single decision on any instance of any definition. If that is still true,
  mark this box `- [~]` and say the count was zero on both sides.
  **Result:**
  ```powershell
> $D = @(Get-OERAccessReviewInstanceDecision -Definition $DefId -Instance $InstId)  
> $D.Count  
1

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): '- [~]'. The count is 1, not 0, so the literal vacuity
# trap ("0 compared against 0") does not apply -- but this check is about PAGING, and one decision on
# one page cannot discriminate a working pager from a broken one.
# What the tenant lacked: an access review instance with more than 100 decisions, which needs more
# than 100 delivered assignments. That was declared unbuildable in the Setup block before the run
# started. The portal count was not recorded either, so the "matching what the portal shows" half of
# the Expect was never actually compared.
  ```

- [~] **4.5 Access review instances return every page.** *(PR #64 7.2, unchanged.)*

  ```powershell
  @(Get-OERAccessReviewInstance -Definition $RecDefId).Count
  @(Get-OERAccessReviewInstance -Definition $RecDefId) | Format-Table Id, Status, StartDateTime, EndDateTime
  ```

  **Expect:** every instance of the recurring review created in 2.5. Needs MORE THAN ONE instance to
  mean anything; a weekly review with `-Occurrences 3` will not have three instances on day one.
  **Failure looks like:** truncation at a page boundary.
  **Vacuity warning:** one instance is `1`, which is also what a broken pager would return. If the
  recurring definition has not produced a second instance yet, mark this `- [~]`.
  **Result:**
  ```powershell
> @(Get-OERAccessReviewInstance -Definition $RecDefId).Count  
1  
> @(Get-OERAccessReviewInstance -Definition $RecDefId) | Format-Table Id, Status, StartDateTime, EndDateTime  
  
Id Status StartDateTime EndDateTime  
-- ------ ------------- -----------  
00000000-0000-0000-0000-000000000023 InProgress 2026-09-11 09:05:34 2026-09-14 09:05:34

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): '- [~]' by the check's own vacuity warning -- one instance
# is 1, which is also exactly what a broken pager would return.
# What the tenant lacked: a second instance of the recurring review. Weekly is the shortest recurrence
# New-OERAccessReviewDefinition accepts, so the second instance is seven days out.
# Worth recording for the redaction pass: the recurring review's instance id
# (00000000-0000-0000-0000-000000000023) DIFFERS from its definition id
# (00000000-0000-0000-0000-000000000006), while the one-time review's instance id EQUALS its
# definition id (2.7). The same-id behaviour is OneTime-specific, and this recurring instance needs
# its own placeholder row. See finding F-K.
# APPLIED 2026-09-11: row 23 allocated, and the prose under the placeholder table now says the
# same-id behaviour is OneTime-specific rather than a property of reviews in general.
  ```

- [x] (verified 2026-09-11) **4.6 Access package assignments return every page.** *(PR #64 7.3; one addition.)*

  ```powershell
  $M = Measure-OerRequest -Label 'assignments' {
      Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose    # a display NAME: ExistsReads must be 0
  }
  $M | Format-List OutputCount, Pages, RequestCount, ExistsReads
  ```

  **Expect:** `OutputCount` is the full count the portal shows. This read uses
  `$expand=target,accessPackage`, so rows are large and the server page size will be small --
  truncation here is likely if the fix did not land.
  **Failure looks like:** fewer than the portal shows.

  > **ADDED to PR #64 7.3.** `-AccessPackage 'oer-live-ap'` is a display NAME here, not a GUID, so
  > `ExistsReads` must be **0** and `RequestCount` must be `1 (the displayName eq query) + Pages`.
  > That distinguishes this check from 3.3 and pins the other half of #71's cost model: a display
  > name pays a filtered query, a GUID pays an id-addressed probe, and neither pays both.
  **Result:**
  
  ```powershell
> $M = Measure-OerRequest -Label 'assignments' {  
> Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose # a display NAME: ExistsReads must be 0  
> }  
> $M | Format-List OutputCount, Pages, RequestCount, ExistsReads  
  
OutputCount : 1  
Pages : 1  
RequestCount : 2  
ExistsReads : 0

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): left ticked, and here is the split, so a later reader is
# not misled by the box alone. The #71 half IS verified: -AccessPackage took a display NAME, so
# ExistsReads is 0 and RequestCount is 1 (the displayName eq query) + Pages 1 = 2, exactly as the
# ADDED note requires. Together with check 3.3 that pins both halves of #71's cost model -- a display
# name pays a filtered query, a GUID pays an id-addressed probe, and neither pays both.
# The PAGING half is NOT verified: OutputCount 1 on Pages 1, and the portal count was not recorded.
# If you would rather the box reflect the paging half, this is a '- [~]' on the same grounds as 3.6
# and 4.4.
  ```

- [x] (verified 2026-09-11) **4.7 The PIM-for-Groups rule read is complete.** *(PR #64 7.4, unchanged.)*

  ```powershell
  Get-OERGroupPimPolicy -Group $PimGroup -AccessType member | Format-List *
  ```

  **Expect:** every policy field populated as before. This endpoint returns roughly 17 rules, below
  any page size, so this is a regression guard rather than a truncation check.
  **Failure looks like:** any field that was populated before now empty.

  > **Traced:** `-AccessType` is `[ValidateSet('member', 'owner')]` with a default of `'member'`, so
  > the argument as written binds. Output comes from `ConvertTo-OERGroupPimPolicy`.
  **Result:**
  
  ```powershell
> Get-OERGroupPimPolicy -Group $PimGroup -AccessType member | Format-List *  
  
GroupId : 00000000-0000-0000-0000-000000000009  
PolicyId : Group_00000000-0000-0000-0000-000000000009_00000000-0000-0000-0000-000000000024  
AccessType : member  
ActivationMaxHours : 8  
AuthenticationContextId :  
ActivationEnabledRules : {Justification}  
AllowPermanentEligibility : True  
EligibleDuration : P200D  
EligibleDurationDays : 200  
AllowPermanentActive : False  
ActiveDuration : P90D  
ActiveDurationDays : 90  
ActiveEnabledRules : {Justification}  
Notifications : @{EligibleAlert=System.Object[]; ActiveAlert=System.Object[]; ActivationAlert=System.Object[]}  
Rules : {Enablement_Admin_Eligibility, Expiration_Admin_Eligibility, Notification_Admin_Admin_Eligibility, Notification_Requestor_Admin_Eligibility...}
  ```

---

## 5. Write checks

**Every destructive step below is run with `-WhatIf` first, and the plan is read before the switch
comes off.** Two steps (5.6 and 5.9) create or modify real objects; both are torn down in section T.

- [x] (verified 2026-09-11) **5.1 The documented policy round-trip still works.** *(PR #64 4.3; `<sub-id>` replaced by a
  variable.)* This is the regression guard for deliberately NOT adding pipeline binding to `-Role`.
  The piped policy object carries BOTH `PolicyId` (which `-PolicyId` binds through its `Id` alias)
  and `RoleDefinitionId` (which is an alias of `-Role`), so if `-Role` ever gained
  `ValueFromPipelineByPropertyName` a single piped policy would satisfy two mutually exclusive
  parameter sets at once.

  **Read the live value first and set a DIFFERENT one.** A fixed target hour is tenant-dependent:
  against a policy that already holds it, the cmdlet answers `NoChange`, which is correct behaviour
  but reads as a failed check.

  ```powershell
  $Sub    # set by the session block from Get-OERSubscription; %TEMP%\oer-s4\oer-s4-arm-baseline.json
          # holds the same subscription and the Contributor policy's ActivationMaxHours AS FOUND
  $Pol = Get-OERRoleManagementPolicy -Subscription $Sub -Role Contributor
  $Pol | Format-List PolicyId, RoleName, ActivationMaxHours
  # Pick a value in 1..24 that is NOT the one above. ActivationMaxHours is $null when Graph
  # expressed the maximum as something other than whole hours; 8 is "different" in that case too.
  $NewHours = if ($Pol.ActivationMaxHours -eq 8) { 7 } else { 8 }
  $Pol | Set-OERRoleManagementPolicy -ActivationMaxHours $NewHours -WhatIf
  ```

  **Expect:** the pipe binds `ByPolicyId` and a `What if:` plan names
  `role management policy '<the PolicyId printed above>'` together with the rule it would change.
  Nothing is written -- `-WhatIf` is on and must stay on.

  **A `NoChange` error is NOT a failure of this check.** `Set-OERRoleManagementPolicy` diffs against
  the live rules and emits `NoChange` **before** `ShouldProcess`, so `-WhatIf` does not suppress it:
  asking for a value the policy already holds produces `NoChange` even in a dry run. Seeing it means
  the `$NewHours` line happened to pick a value already in force -- choose another and re-run. The
  binding half of this check has already passed at that point, since `NoChange` is only reachable
  after the parameter set resolved and the policy was fetched by id.

  **Failure looks like:** `AmbiguousParameterSet` -- `-Role` wrongly gained a pipeline attribute and
  a piped policy now satisfies two mutually exclusive sets. A prompt for `-PolicyId` or for `-Role`
  is the other failure shape: the pipe did not bind at all.

  > **Traced, all three halves.** `PolicyId`, `RoleName` and `ActivationMaxHours` are real
  > properties of `ConvertTo-OERRoleManagementPolicy`. In `Set-OERRoleManagementPolicy`, `-Role`
  > carries `[Parameter(ParameterSetName = 'ByRole', Mandatory)]` with NO pipeline attribute, while
  > `-PolicyId` carries `[Parameter(ParameterSetName = 'ByPolicyId', Mandatory,
  > ValueFromPipelineByPropertyName)] [Alias('Id')]`. The `NoChange` `Write-CmdletError` sits above
  > the `ShouldProcess` call, and the ShouldProcess target is built as
  > `"role management policy '$ResolvedPolicyId'"` -- so the expected plan text is literal, not a
  > paraphrase. Needs `Connect-OER -IncludeARM`.
  **Result:**
  
  ```powershell
> $Sub # set by the session block from Get-OERSubscription; %TEMP%\oer-s4\oer-s4-arm-baseline.json  
00000000-0000-0000-0000-000000000010  
> # holds the same subscription and the Contributor policy's ActivationMaxHours AS FOUND  
> $Pol = Get-OERRoleManagementPolicy -Subscription $Sub -Role Contributor  
> $Pol | Format-List PolicyId, RoleName, ActivationMaxHours  
  
PolicyId : /subscriptions/00000000-0000-0000-0000-000000000010/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000011  
RoleName : Contributor  
ActivationMaxHours : 8  
  
> # Pick a value in 1..24 that is NOT the one above. ActivationMaxHours is $null when Graph  
> # expressed the maximum as something other than whole hours; 8 is "different" in that case too.  
> $NewHours = if ($Pol.ActivationMaxHours -eq 8) { 7 } else { 8 }  
> $Pol | Set-OERRoleManagementPolicy -ActivationMaxHours $NewHours -WhatIf  
What if: Performing the operation "Update rules: Expiration_EndUser_Assignment" on target "role management policy '/subscriptions/00000000-0000-0000-0000-000000000010/providers/Microsoft.Authorization/roleManagementPolicies/00000000-0000-0000-0000-000000000011'".
  ```

- [x] (verified 2026-09-11) **5.2 `New-OERAccessPackageAssignment` binds the PACKAGE id, not an assignment id.**
  *(PR #64 5.6; expectation CORRECTED -- see below.)*

  ```powershell
  $Src = Get-OERAccessPackageAssignment -AccessPackage $Package | Select-Object -First 1
  $Src | Format-List Id, AccessPackageId, TargetId, State

  # The What if: line goes to the HOST and reaches no capturable stream, so it is transcribed
  # rather than filtered out of $M.Verbose. The transcript is deleted in T.1.
  $Plan = Join-Path $LogDir 'whatif-5-2.log'
  Start-Transcript -Path $Plan | Out-Null
  # -User is DELIBERATELY ABSENT -- do not put it back. The piped $Src carries TargetId, which
  # binds -TargetId, and -TargetId takes precedence over -User: the cmdlet warns, ignores the -User
  # value and targets the EXISTING assignee anyway. Piping $Src is the whole point of this check
  # (it is what proves -AccessPackage binds the PACKAGE id and not the ASSIGNMENT id), so the
  # parameter that cannot bind is the one that goes. See finding F-E.
  $M = Measure-OerRequest -Label 'assignment repipe' {
      $Src | New-OERAccessPackageAssignment -Policy $PolicyId -WhatIf -Verbose
  }
  Stop-Transcript | Out-Null

  $M.Requests
  $M | Format-List RequestCount, ExistsReads
  $PlanLines = @(Get-Content -LiteralPath $Plan | Where-Object { $_ -match 'What if' })
  'plan lines captured: ' + $PlanLines.Count      # must be 1 before you read anything below
  $PlanLines
  # The assertion, mechanically:
  [pscustomobject]@{
      NamesPackageId    = [bool]@($PlanLines | Where-Object { $_ -match [regex]::Escape($Src.AccessPackageId) }).Count
      NamesAssignmentId = [bool]@($PlanLines | Where-Object { $_ -match [regex]::Escape($Src.Id) }).Count
  } | Format-List
  ```

  **Expect:** `plan lines captured: 1`, `NamesPackageId` **True**, `NamesAssignmentId` **False**, and
  `ExistsReads` **1**. The plan line itself reads
  `What if: Performing the operation "Assign to access package <the AccessPackageId printed above>"
  on target "<the resolved user's object id>"`.
  **The two GUIDs in the source object are what make this falsifiable**: `Id` (the ASSIGNMENT) and
  `AccessPackageId` (the PACKAGE) are different values, and the plan must name the second.
  `ConvertTo-OERAssignment` emits both, and `-AccessPackage` is deliberately NOT aliased to `Id` for
  exactly this reason.
  **Failure looks like:** `NamesAssignmentId` True.
  **`plan lines captured: 0` is an EVIDENCE failure, not a pass** -- it means the transcript did not
  capture the plan (or `ShouldProcess` was never reached, e.g. the pipe bound nothing). Fix the
  capture before reading the two booleans; both are `False` on an empty capture, which looks like a
  clean run and is not one.

  > **`$M.Verbose | Where-Object { $_ -match 'What if' }` DOES NOT WORK, and an earlier draft of
  > this check used it.** The `What if:` line is written by `ShouldProcess` straight to the PSHost;
  > it is not a verbose record and reaches neither stream 4 (which `Measure-OerRequest` merges) nor
  > stream 6. Measured in a clean `pwsh` against a synthetic `SupportsShouldProcess` function: the
  > line printed to the console, `$M.Verbose` held only the `[Invoke-OERGraphRequest]` line, the
  > `Where-Object` matched **0**, and `6>&1` captured 0 records as well. `Start-Transcript` captured
  > it, once, in full. An assertion built on that filter would have returned empty whatever the
  > cmdlet did -- indistinguishable from "no plan was emitted" -- which is the exact defect class
  > this document is held to. If you would rather not run a transcript, the plan is on your screen:
  > read it there and paste it into the result block yourself. What you must not do is filter
  > `$M.Verbose` for it.

  > **CORRECTED from PR #64 5.6, two ways.**
  >
  > 1. The original expected "the plan names `oer-live-ap`". It does not, and never did:
  >    `source/Public/New-OERAccessPackageAssignment.ps1` calls
  >    `$PSCmdlet.ShouldProcess($ResolvedTargetId, "Assign to access package $PackageId")`, so the
  >    plan names the package **id**, not its display name -- and when the value arrives by pipe it
  >    is a GUID all the way through. As written the check could only ever have failed, which is a
  >    different flavour of the same defect: a check nobody can tick. Comparing the plan's GUID
  >    against `$Src.AccessPackageId` is both correct and a stronger test, since the wrong answer
  >    (`$Src.Id`) is also a GUID and would otherwise read as a pass.
  > 2. The `$M.Requests` and `$M | Format-List RequestCount, ExistsReads` lines are new, and are the
  >    #71 half: the piped `AccessPackageId` is a GUID, so the resolver now issues one
  >    `GET .../accessPackages/<id>?$select=id` before the user lookup. `ExistsReads` is both
  >    PRINTED and ASSERTED, rather than asserted in prose against a `$M.Requests` dump the reader
  >    has to count by eye. Under `-WhatIf` the POST is suppressed but every read before
  >    `ShouldProcess` still goes out.
  >
  > **CORRECTED again 2026-09-11 by finding F-E: `-User` is gone from the block.** The run above
  > passed `-User $Assignee2` and the cmdlet warned that it was ignored -- the piped `$Src` carries
  > `TargetId`, `-TargetId` takes precedence, and the plan therefore targeted the EXISTING assignee.
  > All four assertions still held, which is exactly what made the dead parameter worth removing
  > rather than leaving: a parameter that cannot bind, in a block whose subject IS parameter
  > binding, reads to the next operator as though it bound. Of the two available fixes -- drop
  > `-User`, or stop piping `$Src` -- dropping `-User` is the only one that keeps the check: the
  > pipe is what makes `-AccessPackage` bind by property name, which is the behaviour under test.
  > One consequence to expect on the re-run: `RequestCount` stays **1** (the existence probe alone),
  > since no `-User` value means no principal lookup; `oer-live-assignee2` goes unused by this file.
  >
  > **NO OUTPUT AT ALL is a setup gap, not a defect.** This check needs an assignment that already
  > exists. If `Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap'` returns nothing, zero
  > objects reach the pipe and `New-OERAccessPackageAssignment` -- whose `-AccessPackage` and
  > `-Policy` are both mandatory -- never enters its `process` block, so it prints nothing rather
  > than complaining. That is step 2.3 having been skipped. If assignments plainly exist for that
  > package and the read still comes back empty, THAT is a real finding -- record it here rather
  > than treating it as setup.
  **Result:**
  
  ```powershell
> $Src = Get-OERAccessPackageAssignment -AccessPackage $Package | Select-Object -First 1  
> $Src | Format-List Id, AccessPackageId, TargetId, State  
  
Id : 00000000-0000-0000-0000-000000000003  
AccessPackageId : 00000000-0000-0000-0000-000000000001  
TargetId : 00000000-0000-0000-0000-000000000004  
State : delivered  
  
>  
> # The What if: line goes to the HOST and reaches no capturable stream, so it is transcribed  
> # rather than filtered out of $M.Verbose. The transcript is deleted in T.1.  
> $Plan = Join-Path $LogDir 'whatif-5-2.log'  
> Start-Transcript -Path $Plan | Out-Null  
> $M = Measure-OerRequest -Label 'assignment repipe' {  
> $Src | New-OERAccessPackageAssignment -Policy $PolicyId -User $Assignee2 -WhatIf -Verbose  
> }  
WARNING: -TargetId takes precedence: the supplied -User value is ignored and principal object id '00000000-0000-0000-0000-000000000004' is used. Supply only one.  
What if: Performing the operation "Assign to access package 00000000-0000-0000-0000-000000000001" on target "00000000-0000-0000-0000-000000000004".  
> Stop-Transcript | Out-Null  
>  
> $M.Requests  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/entitlementManagement/accessPackages/00000000-0000-0000-0000-000000000001?$select=id  
> $M | Format-List RequestCount, ExistsReads  
  
RequestCount : 1  
ExistsReads : 1  
  
> $PlanLines = @(Get-Content -LiteralPath $Plan | Where-Object { $_ -match 'What if' })  
> 'plan lines captured: ' + $PlanLines.Count # must be 1 before you read anything below  
plan lines captured: 1  
> $PlanLines  
What if: Performing the operation "Assign to access package 00000000-0000-0000-0000-000000000001" on target "00000000-0000-0000-0000-000000000004".  
> # The assertion, mechanically:  
> [pscustomobject]@{  
> NamesPackageId = [bool]@($PlanLines | Where-Object { $_ -match [regex]::Escape($Src.AccessPackageId) }).Count  
> NamesAssignmentId = [bool]@($PlanLines | Where-Object { $_ -match [regex]::Escape($Src.Id) }).Count  
> } | Format-List  
  
NamesPackageId : True  
NamesAssignmentId : False

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): ticked -- all four assertions hold: plan lines captured 1,
# NamesPackageId True, NamesAssignmentId False, ExistsReads 1.
# But read the WARNING in the transcript. The piped $Src carries TargetId, which binds -TargetId and
# TAKES PRECEDENCE, so "-User $Assignee2" was ignored and the plan targets the EXISTING assignee. That
# is documented cmdlet behaviour and the cmdlet says so out loud -- not a defect. It does mean
# RequestCount is 1 (the existence probe only; no user lookup ever happened) and that
# oer-live-assignee2 went unused in the entire run. The -User argument should come out of this block.
# See finding F-E.
  ```

- [x] (verified 2026-09-11) **5.3 `Set-OERAccessReviewDefinition` accepts a display name.** *(PR #64 6.3; expectation
  CORRECTED -- see below.)*

  ```powershell
  $M = Measure-OerRequest -Label 'set by name' {
      Set-OERAccessReviewDefinition -Id 'oer-live-ar-multistage' `
          -DisplayName 'oer-live-ar-multistage-renamed' -WhatIf -Verbose
  }
  $M.Requests
  ```

  **Expect:** exactly TWO requests, in this order:

  1. `GET v1.0/identityGovernance/accessReviews/definitions?$filter=displayName eq 'oer-live-ar-multistage'&$select=id,displayName`
  2. `GET v1.0/identityGovernance/accessReviews/definitions/<the definition id>`

  and nothing written. Request 2's id must equal `$DefId` from 2.6 -- **that** is the proof the name
  resolved.
  **Failure looks like:** a 404 / `AccessReviewDefinitionNotFound`, meaning the name was sent as an
  id; or an unfiltered paged walk of every definition in the tenant.

  > **CORRECTED from PR #64 6.3.** The original expectation was "the name resolves to a definition
  > id and the plan targets it". The plan cannot prove that:
  > `source/Public/Set-OERAccessReviewDefinition.ps1` calls
  > `$PSCmdlet.ShouldProcess($Id, 'Update access review definition')` with `$Id` -- the raw input --
  > so the `What if:` line echoes the display name you typed whether or not the resolve worked. The
  > check would have been ticked on evidence that could not distinguish pass from fail. The verbose
  > request PAIR is the real evidence, and request 2's id is the assertion.
  >
  > **Also re-verified against Sprint 3.** Commits `67188a9` and `b58f7a4` changed the definition
  > name lookup to a server-side `displayName eq` filter instead of reading every definition. That
  > is why request 1 above carries a `$filter`; the original check predates it. `displayName eq` was
  > measured live in Sprint 3 to be HONOURED on this endpoint (unlike `startswith`, which is
  > silently ignored), so a filtered single result is the expected shape.
  **Result:**
  
  ```powershell
> $M = Measure-OerRequest -Label 'set by name' {  
> Set-OERAccessReviewDefinition -Id 'oer-live-ar-multistage' `  
> -DisplayName 'oer-live-ar-multistage-renamed' -WhatIf -Verbose  
> }  
What if: Performing the operation "Update access review definition" on target "oer-live-ar-multistage".  
> $M.Requests  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions?$filter=displayName eq 'oer-live-ar-multistage'&$select=id,displayName  
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000005
  ```

- [x] (verified 2026-09-11) **5.4 Self-review mixed with a named reviewer is refused.** *(PR #64 6.5, unchanged.)*
  `New-OERAccessReviewDefinition` has **no `-Group` parameter** -- this module creates
  access-package-scoped reviews only, so the review is scoped with `-AccessPackage` plus
  `-AssignmentPolicy`, both mandatory, alongside mandatory `-DisplayName`,
  `-DescriptionForAdmins`, `-DescriptionForReviewers`, `-Recurrence` and `-StartDate`.

  ```powershell
  New-OERAccessReviewDefinition -DisplayName 'oer-live-mix' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage $Package -AssignmentPolicy $PolicyId `
      -Recurrence OneTime -StartDate (Get-Date) `
      -SelfReview -Reviewer $Reviewer -WhatIf
  ```

  **Expect:** a `MutuallyExclusiveReviewer` error, and NO Graph call beyond the auth handshake. The
  guard runs before scope resolution and before reviewer resolution, so neither `$PolicyId` nor
  `<reviewer-upn>` is looked up -- the check still holds even if one of them is wrong. Before the
  fix, `-SelfReview` was silently ignored and the named reviewer won.
  **Failure looks like:** the review being planned with the named reviewer and no complaint. A
  `PackageNotFound` / `AmbiguousAccessPackageName` / `UserNotFound` instead of
  `MutuallyExclusiveReviewer` is ALSO a failure: it means the guard ran too late.

  > **Traced:** in `source/Public/New-OERAccessReviewDefinition.ps1` the
  > `if ($SelfReview -and ($Manager -or $Reviewer -or $ReviewerGroup))` block sits ABOVE the
  > `Resolve-OERAccessReviewScopeTarget` call, which is the first thing in the cmdlet that touches
  > Graph. The ordering claim is read off the file, not assumed.
  **Result:**
  
  ```powershell
> New-OERAccessReviewDefinition -DisplayName 'oer-live-mix' `  
> -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `  
> -AccessPackage $Package -AssignmentPolicy $PolicyId `  
> -Recurrence OneTime -StartDate (Get-Date) `  
> -SelfReview -Reviewer $Reviewer -WhatIf  
New-OERAccessReviewDefinition: -SelfReview cannot be combined with -Reviewer, -ReviewerGroup, or -Manager. A self review leaves the reviewers collection empty; supply -SelfReview alone, or drop it and use the named-reviewer parameters instead.
  ```

- [x] (verified 2026-09-11) **5.5 The same guard on the update path.** *(PR #64 6.6, unchanged.)*

  ```powershell
  Set-OERAccessReviewDefinition -Id $DefId -SelfReview -Manager -WhatIf
  ```

  **Expect:** the same `MutuallyExclusiveReviewer` error, and no Graph call -- the guard sits above
  the id resolution and above the read-modify-write GET.
  **Failure looks like:** silence, or the definition being planned for update.
  **Result:**
  ```powershell
> Set-OERAccessReviewDefinition -Id $DefId -SelfReview -Manager -WhatIf  
Set-OERAccessReviewDefinition: -SelfReview cannot be combined with -Reviewer, -ReviewerGroup, or -Manager. A self review leaves the reviewers collection empty; supply -SelfReview alone, or drop it and use the named-reviewer parameters instead.
  ```

- [x] (verified 2026-09-11) **5.6 An existing apply-document with a mixed reviewer set still applies.** *(PR #64 6.7,
  unchanged.)* This is the back-compat guarantee -- the cmdlet errors, but the apply engine must
  warn and keep working, since such documents exist and worked before. **This step writes.**

  Write the document. It is the FULL document, not a fragment -- `version` is required at the root,
  and `displayName`, `accessPackage` and `assignmentPolicy` are required on every `accessReviews`
  element. The here-string is `@'...'@` (LITERAL, so nothing inside it is interpolated and a `$` in
  a JSON value cannot become a variable); the two real values are substituted afterwards, which is
  also what keeps a real policy GUID out of the checklist text.

  ```powershell
  $Doc56 = @'
{
  "version": "1.0",
  "tenantAlias": "Omnicit",
  "accessReviews": [
    {
      "displayName": "oer-live-ar-mixed",
      "accessPackage": "oer-live-ap",
      "assignmentPolicy": "@POLICYID@",
      "descriptionForAdmins": "Live verification of check 5.6. Safe to delete.",
      "descriptionForReviewers": "Live verification. No action needed.",
      "recurrence": "OneTime",
      "durationInDays": 5,
      "reviewers": [ "manager", "self" ],
      "fallbackReviewers": [ "@REVIEWER@" ]
    }
  ]
}
'@
  $Doc56.Replace('@POLICYID@', $PolicyId).Replace('@REVIEWER@', $Reviewer) |
      Set-Content -Path './live/oer-live-ar-mixed.json' -Encoding utf8
  Get-Content ./live/oer-live-ar-mixed.json
  ```

  **`fallbackReviewers` is load-bearing and must not be dropped.** A manager reviewer with no
  fallback is reported `Failed` by the handler by design (Graph rejects it as "Policy is invalid due
  to invalid criteria"), which would make this check fail for a reason that has nothing to do with
  the `self`/`manager` mix it exists to test. Validated offline as written, placeholders and all:
  `Test-OERStructure -Path ./live/oer-live-ar-mixed.json` returns `Valid : True` with an EMPTY `Errors`
  collection. Drop the `fallbackReviewers` line and `Errors` instead holds one item, of
  `Severity = Warning`, predicting exactly that `Failed`. `Errors` is the property name on the
  returned object -- there is no `Findings` member -- and it carries Warning-severity items too, so
  a non-empty `Errors` alongside `Valid : True` is a warning, not a schema error.

  ```powershell
  Test-OERStructure -Path ./live/oer-live-ar-mixed.json | Format-List Valid
  (Test-OERStructure -Path ./live/oer-live-ar-mixed.json).Errors |
      Format-List Section, Item, Path, Message, Severity

  Invoke-OERStructure -Path ./live/oer-live-ar-mixed.json -Include AccessReviews -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize

  # Read the plan above before this line. THIS ONE WRITES -- it creates the review T.1 deletes.
  Invoke-OERStructure -Path ./live/oer-live-ar-mixed.json -Include AccessReviews -Confirm:$false `
      -WarningVariable Warn -ErrorVariable Err |
      Format-Table Section, Item, Action, Detail -AutoSize
  @($Warn) | ForEach-Object { "WARNING: $_" }
  @($Err)  | Where-Object { $_.InvocationInfo.MyCommand.Name } |
      ForEach-Object { "ERROR: $($_.FullyQualifiedErrorId)" }
  ```

  **Expect:** a WARNING naming the element -- "reviewers[] declares 'self' together with a named or
  manager reviewer; Microsoft Graph's own resolution silently prefers the named/manager reviewers,
  so 'self' is dropped to match that outcome. Declare only one reviewer mode." -- the manager
  reviewer applied, and the result NOT `Failed`.
  **Failure looks like:** a `Failed` result -- an existing document stopped working.
  **Teardown is in T.1.**

  > **Traced:** the warning text above is verbatim from
  > `source/Private/Sync-OERStructureAccessReview.ps1`. `Valid` and `Errors` are the documented
  > properties of `Test-OERStructure`'s `Omnicit.EntraRBAC.StructureValidation` output.
  > `'AccessReviews'` is a member of `Invoke-OERStructure -Include`'s `ValidateSet`.
  **Result:**
  
  ```powershell
> Get-Content ./live/oer-live-ar-mixed.json  
{  
"version": "1.0",  
"tenantAlias": "Omnicit",  
"accessReviews": [  
{  
"displayName": "oer-live-ar-mixed",  
"accessPackage": "oer-live-ap",  
"assignmentPolicy": "00000000-0000-0000-0000-000000000002",  
"descriptionForAdmins": "Live verification of check 5.6. Safe to delete.",  
"descriptionForReviewers": "Live verification. No action needed.",  
"recurrence": "OneTime",  
"durationInDays": 5,  
"reviewers": [ "manager", "self" ],  
"fallbackReviewers": [ "person3@example.com" ]  
}  
]  
}  
> Test-OERStructure -Path ./live/oer-live-ar-mixed.json | Format-List Valid  
  
Valid : True  
  
> (Test-OERStructure -Path ./live/oer-live-ar-mixed.json).Errors |  
> Format-List Section, Item, Path, Message, Severity  
>  
> Invoke-OERStructure -Path ./live/oer-live-ar-mixed.json -Include AccessReviews -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
What if: Performing the operation "Create access review definition" on target "oer-live-ar-mixed".  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-live-ar-mixed Skipped would create access review 'oer-live-ar-mixed'  
  
>  
> # Read the plan above before this line. THIS ONE WRITES -- it creates the review T.1 deletes.  
> Invoke-OERStructure -Path ./live/oer-live-ar-mixed.json -Include AccessReviews -Confirm:$false `  
> -WarningVariable Warn -ErrorVariable Err |  
> Format-Table Section, Item, Action, Detail -AutoSize  
WARNING: Sync-OERStructureAccessReview: access review 'oer-live-ar-mixed' -- reviewers[] declares 'self' together with a named or manager reviewer; Microsoft Graph's own resolution silently prefers the named/manager reviewers, so 'self' is dropped to match that outcome. Declare only one reviewer mode.
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-live-ar-mixed Created created access review 'oer-live-ar-mixed' (recurrence: OneTime)  
  
> @($Warn) | ForEach-Object { "WARNING: $_" }  
WARNING: Sync-OERStructureAccessReview: access review 'oer-live-ar-mixed' -- reviewers[] declares 'self' together with a named or manager reviewer; Microsoft Graph's own resolution silently prefers the named/manager reviewers, so 'self' is dropped to match that outcome. Declare only one reviewer mode. 
> @($Err) | Where-Object { $_.InvocationInfo.MyCommand.Name } |  
> ForEach-Object { "ERROR: $($_.FullyQualifiedErrorId)" }
  ```

- [x] (verified 2026-09-11) **5.7 Non-positive occurrence and duration values are refused at bind time.** *(PR #64 6.8,
  unchanged.)* Same scope shape as 5.4 -- there is no `-Group`.

  ```powershell
  New-OERAccessReviewDefinition -DisplayName 'oer-live-x' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage $Package -AssignmentPolicy $PolicyId `
      -Recurrence OneTime -StartDate (Get-Date) `
      -Reviewer $Reviewer -Occurrences 0 -WhatIf

  New-OERAccessReviewDefinition -DisplayName 'oer-live-x' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage $Package -AssignmentPolicy $PolicyId `
      -Recurrence OneTime -StartDate (Get-Date) `
      -Reviewer $Reviewer -DurationInDays 0 -WhatIf
  ```

  **Expect:** a parameter-validation error naming the PUBLIC cmdlet, with no Graph call. `0` fails
  `ValidateRange(1, ...)` during parameter binding, so the surrounding values are never used -- they
  are present only so the binder has a resolvable parameter set to bind INTO. Before the fix,
  `-Occurrences 0` bound fine, reached Graph, and then died with an uncaught terminating error from
  a private helper -- immune to `-ErrorAction`.
  **Failure looks like:** an error naming `New-OERAccessReviewRecurrence`, or any Graph traffic.

  > **Traced:** both `-EndDate`'s sibling `-Occurrences` and `-DurationInDays` carry
  > `[ValidateRange(1, [int]::MaxValue)]` in `source/Public/New-OERAccessReviewDefinition.ps1`.
  **Result:**
  
  ```powershell
> New-OERAccessReviewDefinition -DisplayName 'oer-live-x' `  
> -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `  
> -AccessPackage $Package -AssignmentPolicy $PolicyId `  
> -Recurrence OneTime -StartDate (Get-Date) `  
> -Reviewer $Reviewer -Occurrences 0 -WhatIf  
New-OERAccessReviewDefinition:  
Line |  
5 | -Reviewer $Reviewer -Occurrences 0 -WhatIf  
| ~  
| Cannot validate argument on parameter 'Occurrences'. The 0 argument is less than the minimum allowed range of 1. Supply an argument that is greater than or equal to 1 and then try the command again.  
>  
> New-OERAccessReviewDefinition -DisplayName 'oer-live-x' `  
> -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `  
> -AccessPackage $Package -AssignmentPolicy $PolicyId `  
> -Recurrence OneTime -StartDate (Get-Date) `  
> -Reviewer $Reviewer -DurationInDays 0 -WhatIf  
New-OERAccessReviewDefinition:  
Line |  
5 | -Reviewer $Reviewer -DurationInDays 0 -WhatIf  
| ~  
| Cannot validate argument on parameter 'DurationInDays'. The 0 argument is less than the minimum allowed range of 1. Supply an argument that is greater than or equal to 1 and then try the command again.
  ```

- [x] (verified 2026-09-11) **5.8 A long duration is still allowed.** *(PR #64 6.9, unchanged.)* No upper bound was added,
  since Microsoft documents none.

  ```powershell
  New-OERAccessReviewDefinition -DisplayName 'oer-live-long' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage $Package -AssignmentPolicy $PolicyId `
      -Recurrence OneTime -StartDate (Get-Date) `
      -Reviewer $Reviewer -DurationInDays 400 -WhatIf
  ```

  **Expect:** accepted locally (Graph may still reject it -- that is fine and is their call), and a
  `What if:` plan naming `oer-live-long`.
  **Failure looks like:** a local `ValidateRange` error, meaning an upper bound crept in.
  **This one is NOT free.** Unlike 5.4, `-WhatIf` here suppresses only the POST: the access package,
  assignment policy and reviewer lookups all go out to Graph before `ShouldProcess` is reached. They
  are reads and harmless, but it does mean 5.8 needs REAL values in `$PolicyId` and
  `<reviewer-upn>` -- a `PackageNotFound` or `UserNotFound` here is a bad placeholder, not a
  finding. `-AccessPackage 'oer-live-ap'` is a display NAME, so no #71 existence read is involved.
  **Result:**
  ```powershell
> New-OERAccessReviewDefinition -DisplayName 'oer-live-long' `  
> -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `  
> -AccessPackage $Package -AssignmentPolicy $PolicyId `  
> -Recurrence OneTime -StartDate (Get-Date) `  
> -Reviewer $Reviewer -DurationInDays 400 -WhatIf  
What if: Performing the operation "Create access review definition" on target "oer-live-long".  
>
  ```

- [ ] **SUPERSEDED BY U.2 -- 5.9 A stale GUID in an apply document is a `Failed` row, and NEVER a create.** *(issue #71.)*
  **This step runs the apply engine for real; read the `-WhatIf` plan first.**

  > **RETIRED 2026-09-11. Do not run this block; run U.2 instead.** The 2026-09-11 pass proved by
  > execution that this check is UNRUNNABLE as written: the offline validator rejects the document
  > (`'catalog' is required at accessPackages[0]`, `StructureValidationFailed`), so
  > `Sync-OERStructureAccessPackage` is never entered and `Resolve-OERAccessPackageId` is never
  > called. The schema is not relaxed and the branch is not deleted -- ruling R-C1 says why, and
  > **chapter U.2** exercises the same #71 guard through `accessReviews[]`, a path that IS reachable
  > through `Invoke-OERStructure`. The box below stays `- [ ]` and the result block stays as it was
  > pasted: it is the evidence that retired the check, not a result that can be improved by
  > re-running it.

  Write a document whose `accessPackages[].displayName` is a GUID that is not an access package, and
  which declares **NO `catalog`** -- the no-catalog branch is the one that routes through
  `Resolve-OERAccessPackageId`.

  ```powershell
  # $NotAPackage is 3.1's GUID -- oer-live-pim's object id, which is syntactically a GUID and is
  # not an access package. It is substituted in below, so no real id is typed into this file.
  $Doc59 = @'
{
  "version": "1.0",
  "tenantAlias": "Omnicit",
  "accessPackages": [
    { "displayName": "@STALEGUID@", "description": "Live verification of check 5.9." }
  ]
}
'@
  $Doc59.Replace('@STALEGUID@', $NotAPackage) |
      Set-Content -Path './live/oer-live-stale-guid.json' -Encoding utf8
  Get-Content ./live/oer-live-stale-guid.json
  ```

  ```powershell
  $Before = @(Get-OERAccessPackage).Count
  $Before

  Invoke-OERStructure -Path ./live/oer-live-stale-guid.json -Include AccessPackages -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize

  # Read the plan above first. This run is real, and the whole point is that it creates NOTHING.
  Invoke-OERStructure -Path ./live/oer-live-stale-guid.json -Include AccessPackages `
      -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err59 |
      Format-Table Section, Item, Action, Detail -AutoSize
  @($Err59) | Where-Object { $_.InvocationInfo.MyCommand.Name } |
      ForEach-Object { "ERROR: $($_.FullyQualifiedErrorId)" }

  $After = @(Get-OERAccessPackage).Count
  [pscustomobject]@{ Before = $Before; After = $After; Unchanged = ($Before -eq $After) } | Format-List
  ```

  **Expect:** a single row with `Action` `Failed` and a `Detail` that names the id and ends with
  **"the access package was NOT created"**, plus a non-terminating error published to the caller.
  The package count is IDENTICAL before and after. Verify the absence explicitly -- the whole point
  of the throw is that the row is not a `Created`, and a count is the only thing that proves it.
  **Failure looks like:** an `Action` of `Created`, or the count going up by one. That is the
  pre-#71 behaviour: `$null` from the resolver read as "this name is free", and the engine creating
  an access package whose display name is a GUID.

  > **Traced:** the `else` branch of `source/Private/Sync-OERStructureAccessPackage.ps1` (the
  > no-catalog path) wraps `Resolve-OERAccessPackageId` in a `try`/`catch` that emits
  > `ConvertTo-OERStructureResult ... -Action 'Failed' -Detail "failed to resolve access package
  > '$Name': ...; the access package was NOT created"` after `$Caller.WriteError($PSItem)`. The
  > result object's properties are `Section`, `Item`, `Action`, `Detail`, `Error`.
  >
  > **Known limitation, recorded rather than worked around:** an entry that declares no `catalog`
  > and names a package that genuinely does NOT exist cannot be created at all --
  > `New-OERAccessPackage -Catalog` is `[Parameter(Mandatory)]`, so a `$null` catalog is a
  > parameter-binding failure rather than a clean row. That is pre-existing and is not what this
  > check measures; it is why the document above uses a GUID that will fail at the resolver, before
  > the create is ever attempted.
  **Result:**
  
  ```powershell
> $Doc59 = @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> { "displayName": "@STALEGUID@", "description": "Live verification of check 5.9." }  
> ]  
> }  
> '@  
> $Doc59.Replace('@STALEGUID@', $NotAPackage) |  
> Set-Content -Path './live/oer-live-stale-guid.json' -Encoding utf8  
> Get-Content ./live/oer-live-stale-guid.json  
{  
"version": "1.0",  
"tenantAlias": "Omnicit",  
"accessPackages": [  
{ "displayName": "00000000-0000-0000-0000-000000000009", "description": "Live verification of check 5.9." }  
]  
}  
> $Before = @(Get-OERAccessPackage).Count  
> $Before  
6  
>  
> Invoke-OERStructure -Path ./live/oer-live-stale-guid.json -Include AccessPackages -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
Invoke-OERStructure: Structure document failed validation: accessPackages[0]: 'catalog' is required at accessPackages[0].  
>  
> # Read the plan above first. This run is real, and the whole point is that it creates NOTHING.  
> Invoke-OERStructure -Path ./live/oer-live-stale-guid.json -Include AccessPackages `  
> -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err59 |  
> Format-Table Section, Item, Action, Detail -AutoSize  
> @($Err59) | Where-Object { $_.InvocationInfo.MyCommand.Name } |  
> ForEach-Object { "ERROR: $($_.FullyQualifiedErrorId)" }  
ERROR: StructureValidationFailed,Invoke-OERStructure  
>  
> $After = @(Get-OERAccessPackage).Count  
> [pscustomobject]@{ Before = $Before; After = $After; Unchanged = ($Before -eq $After) } | Format-List  
  
Before : 6  
After : 6  
Unchanged : True

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): THIS CHECK DID NOT RUN -- box un-ticked.
# The document was rejected by the OFFLINE validator: "Structure document failed validation:
# accessPackages[0]: 'catalog' is required at accessPackages[0]", FullyQualifiedErrorId
# StructureValidationFailed. Sync-OERStructureAccessPackage was never entered,
# Resolve-OERAccessPackageId was never called, and the expected Failed row ending "the access package
# was NOT created" was never produced. Before = After = 6 proves nothing was created; it proves
# nothing whatever about issue #71.
# The check is UNRUNNABLE AS WRITTEN: the schema in Get-OERStructureSchemaJson declares
# "required": [ "displayName", "catalog" ] on every accessPackages item, so the no-catalog branch this
# check deliberately targets cannot be reached through Invoke-OERStructure at all. Declaring a catalog
# would exercise a different branch, so that is not a fix. See finding F-C.
  ```

- [ ] **SUPERSEDED BY U.3 -- 5.10 Measure the real request growth on an apply run.** *(issue #71.)*

  `Resolve-OERAccessPackageId`'s `.DESCRIPTION` states the per-entry cost as **`1 + A + D + C`**
  extra probes, where `A` is the number of MISSING declared resource-role bindings added, `D` the
  number of undeclared bindings pruned (only under `-Prune`), and `C` the number of assignment
  policies created. The leading `1` is the assignment-policy read, which always runs. The upper
  bound `1 + 2R + P` (with R declared roles all missing, R live bindings all pruned, P policies
  created) is reached only in the worst case; **a fully converged entry pays only the leading 1.**

  Run it twice against a document with a known number of access packages, resource roles and
  assignment policies. **This document is ONE entry with R=1 declared resource role and P=1
  assignment policy**, so the model predicts `ExistsReads` of `1 + A + C` on the first (creating)
  run -- `1 + 1 + 1 = 3` -- and exactly `1` on the converged re-apply. Those two numbers are the
  whole check.

  It declares `oer-live-ap2`, a SECOND access package that does not exist yet, deliberately: a
  document aimed at `oer-live-ap` is converged from the first run and the creating half could not be
  measured at all. `oer-live-ap2` is removed in section T, and by
  `Initialize-OerS4Prereq.ps1 -SkipUsers -RestoreWrites`.

  ```powershell
  $Doc510 = @'
{
  "version": "1.0",
  "tenantAlias": "Omnicit",
  "accessPackages": [
    {
      "displayName": "oer-live-ap2",
      "catalog": "OER-CAT-A",
      "description": "Live verification of check 5.10 (request growth). Safe to delete.",
      "resourceRoles": [
        { "resource": "oer-live-res", "role": "Member" }
      ],
      "assignmentPolicies": [
        {
          "displayName": "oer-live-ap2-policy",
          "description": "Live verification of check 5.10. Admin assignment only.",
          "requestorScope": { "scope": "NoSubjects" }
        }
      ]
    }
  ]
}
'@
  $Doc510 | Set-Content -Path './live/oer-live-apply.json' -Encoding utf8
  Test-OERStructure -Path ./live/oer-live-apply.json | Format-List Valid
  (Test-OERStructure -Path ./live/oer-live-apply.json).Errors | Format-List Path, Message, Severity

  # The plan, before anything is created.
  Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  ```powershell
  # Read the plan above first. The first run CREATES oer-live-ap2; the second must change nothing.
  $Sw1 = [System.Diagnostics.Stopwatch]::StartNew()
  $First = Measure-OerRequest -Label 'first apply' {
      Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -Confirm:$false -Verbose
  }
  $Sec1 = [math]::Round($Sw1.Elapsed.TotalSeconds, 1)

  $Sw2 = [System.Diagnostics.Stopwatch]::StartNew()
  $Again = Measure-OerRequest -Label 'converged re-apply' {
      Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -Confirm:$false -Verbose
  }
  $Sec2 = [math]::Round($Sw2.Elapsed.TotalSeconds, 1)

  $First, $Again | Format-Table Label, RequestCount, ExistsReads, Pages -AutoSize
  [pscustomobject]@{
      Entries        = 1
      DeclaredRoles  = 1
      DeclaredPolicy = 1
      FirstSeconds   = $Sec1
      AgainSeconds   = $Sec2
      ModelFirst     = '1 + A + C, A and C both 1 on a create = 3'
      ModelConverged = '1'
  } | Format-List
  @($First.Output)  | Format-Table Section, Item, Action, Detail -AutoSize
  @($Again.Output)  | Format-Table Section, Item, Action, Detail -AutoSize
  ```

  > **`Format-Table` on `$M.Output` is deliberate.** `Measure-OerRequest` swallows the command's
  > objects into `Output` rather than letting them print, so without these two lines the apply rows
  > -- the evidence that the first run said `Created` and the second `Unchanged` -- never reach the
  > result block at all.

  **Record:** `ExistsReads` on each run, the number of entries in the document, and the elapsed time
  for each. **Expect:** the converged re-apply's `ExistsReads` equals the number of access package
  entries times 1 -- the leading `1` per entry and nothing more. The first (creating) run is higher
  by `A + C` per entry.
  **Failure looks like:** `ExistsReads` growing on a converged re-apply, meaning something probes
  per item rather than per operation; or a first-run count above `1 + 2R + P` per entry, meaning the
  documented model is wrong and the `.DESCRIPTION` needs correcting.
  **This is a measurement, not a pass/fail gate** -- the cost of the guarantee is what an operator
  will feel on a large document, and nobody has a number for it yet.
  **Result:**
  ```powershell
> $Doc510 | Set-Content -Path './live/oer-live-apply.json' -Encoding utf8   
> Test-OERStructure -Path ./live/oer-live-apply.json | Format-List Valid  
  
Valid : True  
  
> (Test-OERStructure -Path ./live/oer-live-apply.json).Errors | Format-List Path, Message, Severity  
  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-CAT-A' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
>  
> # The plan, before anything is created.  
> Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
What if: Performing the operation "Create access package" on target "oer-live-ap2".  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-live-ap2 Skipped would create access package oer-live-ap2  
accessPackages oer-live-ap2 Skipped would configure resourceRole 'oer-live-res' after access package is created  
accessPackages oer-live-ap2 Skipped would configure assignmentPolicy 'oer-live-ap2-policy' after access package is created  
  
> $Sw1 = [System.Diagnostics.Stopwatch]::StartNew()  
> $First = Measure-OerRequest -Label 'first apply' {  
> Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -Confirm:$false -Verbose  
> }  
Invoke-OERStructure:  
Line |  
2 | Invoke-OERStructure -Path ./live/oer-live-apply.json -Include A ...  
| ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  
| InvalidModel: The model is invalid.  
> $Sec1 = [math]::Round($Sw1.Elapsed.TotalSeconds, 1)  
>  
> $Sw2 = [System.Diagnostics.Stopwatch]::StartNew()  
> $Again = Measure-OerRequest -Label 'converged re-apply' {  
> Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -Confirm:$false -Verbose  
> }  
Invoke-OERStructure:  
Line |  
2 | Invoke-OERStructure -Path ./live/oer-live-apply.json -Include A ...  
| ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  
| InvalidModel: The model is invalid.  
> $Sec2 = [math]::Round($Sw2.Elapsed.TotalSeconds, 1)  
>  
> $First, $Again | Format-Table Label, RequestCount, ExistsReads, Pages -AutoSize  
  
Label RequestCount ExistsReads Pages  
----- ------------ ----------- -----  
first apply 18 3 5  
converged re-apply 10 2 4  
  
> [pscustomobject]@{  
> Entries = 1  
> DeclaredRoles = 1  
> DeclaredPolicy = 1  
> FirstSeconds = $Sec1  
> AgainSeconds = $Sec2  
> ModelFirst = '1 + A + C, A and C both 1 on a create = 3'  
> ModelConverged = '1'  
> } | Format-List  
  
Entries : 1  
DeclaredRoles : 1  
DeclaredPolicy : 1  
FirstSeconds : 6,4  
AgainSeconds : 3,9  
ModelFirst : 1 + A + C, A and C both 1 on a create = 3  
ModelConverged : 1  
  
> @($First.Output) | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-live-ap2 Created created access package oer-live-ap2 (00000000-0000-0000-0000-000000000014)  
accessPackages oer-live-ap2 Created added resourceRole 'Member' on 'oer-live-res'  
accessPackages oer-live-ap2 Failed failed to create assignmentPolicy 'oer-live-ap2-policy': InvalidModel: The model is invalid.  
  
> @($Again.Output) | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-live-ap2 Unchanged access package properties match  
accessPackages oer-live-ap2 Unchanged resourceRole 'Member' on 'oer-live-res' already bound  
accessPackages oer-live-ap2 Failed failed to create assignmentPolicy 'oer-live-ap2-policy': InvalidModel: The model is invalid.  

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): correctly left un-ticked, and this check found a DEFECT that
# is not in any of the four issues.
# The apply created oer-live-ap2 and bound the Member role, then failed on the assignment policy --
# "Failed / failed to create assignmentPolicy 'oer-live-ap2-policy': InvalidModel: The model is
# invalid." -- on BOTH the first and the converged run. The entry therefore never converges: the
# re-apply still reports Failed. oer-live-ap2 now exists in the tenant WITHOUT a policy; section T
# removes it by name.
# The equivalent cmdlet call succeeds (Initialize-OerS4Prereq.ps1 creates oer-live-ap-policy with
# New-OERAccessPackageAssignmentPolicy -RequestorScope (New-OERAccessPackageRequestorScope
# -AdminAssignmentOnly) -DurationInDays 365), so the body the apply engine builds on the CREATE path
# differs from the one the cmdlet sends. First suspect: no expiration/duration in the create body.
# CONSEQUENCE FOR THIS CHECK: the measurement is INVALID. ExistsReads 3 on the first run and 2 on the
# re-apply describe a run whose policy create failed twice, not the 1 + A + C / 1 model. Re-measure
# after the defect is fixed. See finding F-B.

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-13): SUPERSEDED BY CHECK U.3, which passed on
# 2026-09-12 after the F-B / issue #86 fix. The measurement recorded above describes a run whose
# policy create failed twice and is not a valid reading of the cost model; U.3 has the real numbers
# (ExistsReads 3 creating, 1 converged).
  ```

- [~] **5.11 THE IMPORTANT ONE -- the apply engine sees every resource role binding.**
  *(PR #64 7.5; result vocabulary CORRECTED -- see below.)*

  **CORRECTION carried forward from PR #64, and it matters for how you read the result.** An earlier
  draft of that checklist said a truncated read would, under `-Prune`, DELETE live bindings it had
  not seen. **That is wrong**: the prune loop iterates only the bindings it read, so an unseen
  binding is never a delete candidate. The two real harms of truncation are:

  1. **A spurious add** for a declared binding that happens to live on page 2 -- the engine cannot
     see it, so it tries to create it again.
  2. **Silent UNDER-pruning** -- an undeclared live binding on page 2 is never reported `Extra` and
     never removed, so `-Prune` reports a clean package while stale bindings survive. This is the
     quieter and more dangerous of the two, since it looks like success.

  With an access package carrying **more resource role bindings than one server page**, run
  `Invoke-OERStructure -WhatIf` on a document declaring exactly the bindings that already exist.

  **On the Omnicit tenant it does not carry more than one page, and that is decided before the run.**
  `oer-live-ap` has TWO bindings on `oer-live-res` (`Member` and `Owner`), and a second page needs
  roughly fifty new groups added as catalog resources -- see the Setup block's second table. **The
  PAGING claim of this check therefore cannot be verified, and therefore we do not know: mark 5.11
  `- [~]`.** What the block below still proves, and what is worth running, is the other half: that a
  declared binding which DOES exist is reported `Unchanged` with the traced `Detail`, and that no
  `would add resourceRole` row appears for it. Record both outcomes separately.

  The document declares only the `Member` binding. The `Owner` binding is left undeclared on
  purpose -- it is 5.12's `Extra` row, and the same file serves both checks.

  ```powershell
  $DocRoles = @'
{
  "version": "1.0",
  "tenantAlias": "Omnicit",
  "accessPackages": [
    {
      "displayName": "oer-live-ap",
      "catalog": "OER-CAT-A",
      "resourceRoles": [
        { "resource": "oer-live-res", "role": "Member" }
      ]
    }
  ]
}
'@
  $DocRoles | Set-Content -Path './live/oer-live-roles.json' -Encoding utf8
  Test-OERStructure -Path ./live/oer-live-roles.json | Format-List Valid

  # What the engine currently sees, so the plan below can be read against it.
  Get-OERAccessPackageResourceRole -AccessPackage $ApId |
      Format-Table RoleName, ResourceDisplayName, ScopeDisplayName -AutoSize

  Invoke-OERStructure -Path ./live/oer-live-roles.json -Include AccessPackages -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  > **`assignmentPolicies` is deliberately omitted from the document, and that is visible in the
  > plan.** An undeclared assignment policy is always reported `Extra` and is never removed (the
  > `.DESCRIPTION` of `Sync-OERStructureAccessPackage.ps1` says so in as many words), so expect one
  > `Extra` row naming `oer-live-ap-policy` alongside the resource-role rows. It is noise for this
  > check, not a finding, and declaring the policy instead would put a real GUID in the document for
  > no gain.

  **Expect:** every binding reported `Unchanged` with a `Detail` of
  `resourceRole '<role>' on '<resource>' already bound`, and **no** row whose `Detail` begins
  `would add resourceRole`.
  **Failure looks like:** a `Skipped` row reading `would add resourceRole '<role>' on '<resource>'`
  for a binding that demonstrably already exists.

  > **CORRECTED from PR #64 7.5: the engine has no `Add` action.** The original expected "no `Add`",
  > and a reader scanning the `Action` column for the literal string `Add` would find none no matter
  > what happened, and tick it. `ConvertTo-OERStructureResult`'s `Action` vocabulary on this path is
  > `Unchanged`, `Created`, `Skipped`, `Removed`, `Extra` and `Failed`; a spurious add reads as
  > `Skipped` under `-WhatIf` (detail `would add resourceRole ...`) and as `Created` (detail
  > `added resourceRole ...`) without it. The `Detail` string is what discriminates, and it is now
  > what the expectation names.
  **Result:**
  
  ```powershell
> $DocRoles | Set-Content -Path './live/oer-live-roles.json' -Encoding utf8  
> Test-OERStructure -Path ./live/oer-live-roles.json | Format-List Valid  
  
Valid : True  
  
>  
> # What the engine currently sees, so the plan below can be read against it.  
> Get-OERAccessPackageResourceRole -AccessPackage $ApId |  
> Format-Table RoleName, ResourceDisplayName, ScopeDisplayName -AutoSize  
  
RoleName ResourceDisplayName ScopeDisplayName  
-------- ------------------- ----------------  
Owner oer-live-res Root  
Member oer-live-res Root  
  
>  
> Invoke-OERStructure -Path ./live/oer-live-roles.json -Include AccessPackages -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-live-ap Unchanged access package properties match  
accessPackages oer-live-ap Unchanged resourceRole 'Member' on 'oer-live-res' already bound  
accessPackages oer-live-ap Extra undeclared resourceRole binding 'Owner|00000000-0000-0000-0000-000000000013' (use -Prune to remove)  
  
>

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): '- [~]'. The RESULT-VOCABULARY half passed: the declared
# Member binding is reported Unchanged with the traced Detail "resourceRole 'Member' on 'oer-live-res'
# already bound", and NO row begins "would add resourceRole" -- which is what the CORRECTED note under
# this check exists to pin. The Extra row naming Owner is check 5.12's and is expected here.
# The PAGING half is untested, and was declared unbuildable in the Setup block before the run started:
# oer-live-ap carries two bindings on one page, and a second page needs roughly fifty new groups added
# as catalog resources.
# What the tenant lacked: an access package with more resource role bindings than one server page.
  ```

- [~] **5.12 The under-pruning half.** *(PR #64 7.5b; result vocabulary CORRECTED -- see below.)*
  Add a resource role binding that the document does NOT declare, and make sure it is one that would
  land beyond the first page. Then run twice: without `-Prune`, and with `-Prune -WhatIf`.

  **The undeclared binding already exists: it is the `Owner` role on `oer-live-res`,** which
  `Initialize-OerS4Prereq.ps1` bound for exactly this purpose. Nothing has to be added by hand.
  What CANNOT be arranged is "make sure it lands beyond the first page" -- see 5.11 -- so the
  paging half of this check is `- [~]` too, and what the block below settles is the **result
  vocabulary**, which is what the CORRECTED note under it is about.

  ```powershell
  Invoke-OERStructure -Path ./live/oer-live-roles.json -Include AccessPackages -WhatIf |
      Where-Object { $_.Action -in 'Extra', 'Skipped' } | Format-Table Action, Detail -AutoSize
  Invoke-OERStructure -Path ./live/oer-live-roles.json -Include AccessPackages -Prune -WhatIf `
      -WarningVariable PruneWarn |
      Where-Object { $_.Action -in 'Extra', 'Skipped', 'Removed' } | Format-Table Action, Detail -AutoSize
  @($PruneWarn) | ForEach-Object { "WARNING: $_" }
  ```

  > **Do NOT drop `-WhatIf` here.** Without it the `Owner` binding is really removed, and it is the
  > only thing that makes this check repeatable -- a re-run afterwards finds nothing to report and
  > reads as a clean pass. `Removed` is already traced from source in the CORRECTED note below, and
  > `-WhatIf` proves everything up to the delete. If you do want the `Removed` row on the record,
  > run it last, and re-create the binding with
  > `Add-OERAccessPackageResourceRole -AccessPackage $ApId -Catalog $Catalog -Group $ResGroup -Role Owner`
  > before anything else is re-run.

  **Expect:**

  - **Without `-Prune`:** exactly one row with `Action` `Extra` and `Detail`
    `undeclared resourceRole binding '<key>' (use -Prune to remove)`, naming the binding you added.
  - **With `-Prune -WhatIf`:** exactly one row with `Action` `Skipped` and `Detail`
    `would remove undeclared resourceRole binding '<key>'`.
  - **Only if you drop `-WhatIf`** does the action become `Removed`, with `Detail`
    `removed undeclared resourceRole binding '<key>'`. Read both plans above before you do that.

  **Failure looks like:** a clean run reporting nothing -- the engine never saw the binding, so it
  silently left stale state behind while claiming convergence.

  > **CORRECTED from PR #64 7.5b.** The original expected "`Extra` (without `-Prune`) or `Removed`
  > (with it)", which is wrong for the `-Prune -WhatIf` combination the same check tells you to run
  > first: `Sync-OERStructureAccessPackage` emits `Skipped` there, not `Removed`. A reader following
  > the instruction literally would see `Skipped`, find neither expected value, and have no way to
  > tell a correct dry run from a broken one. All three strings are traced from
  > `source/Private/Sync-OERStructureAccessPackage.ps1`.
  **Result:**
  
  ```powershell
> Invoke-OERStructure -Path ./live/oer-live-roles.json -Include AccessPackages -Prune -WhatIf `  
> -WarningVariable PruneWarn |  
> Where-Object { $_.Action -in 'Extra', 'Skipped', 'Removed' } | Format-Table Action, Detail -AutoSize  
WARNING: Sync-OERStructureAccessPackage: would remove undeclared resourceRole binding 'Owner|00000000-0000-0000-0000-000000000013' from access package 'oer-live-ap'.  
What if: Performing the operation "Remove undeclared resourceRole binding 'Owner|00000000-0000-0000-0000-000000000013'" on target "oer-live-ap".  
  
Action Detail  
------ ------  
Skipped would remove undeclared resourceRole binding 'Owner|00000000-0000-0000-0000-000000000013'  
  
> @($PruneWarn) | ForEach-Object { "WARNING: $_" }  
WARNING: Sync-OERStructureAccessPackage: would remove undeclared resourceRole binding 'Owner|00000000-0000-0000-0000-000000000013' from access package 'oer-live-ap'.  
>

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-11): '- [~]'. Both traced strings matched VERBATIM, which
# settles the CORRECTED vocabulary this check exists to pin: without -Prune, Extra / "undeclared
# resourceRole binding 'Owner|<origin-id>' (use -Prune to remove)" -- pasted into 5.11's result block,
# which is where the non-prune run was run -- and under -Prune -WhatIf, Skipped / "would remove
# undeclared resourceRole binding 'Owner|<origin-id>'". Neither is the pre-correction 'Removed'.
# The PAGING half is untested for the same reason as 5.11: the undeclared binding the engine found
# sits on page one, so this run cannot show that a binding BEYOND the first page is seen -- which is
# the silent under-pruning this check is really about.
# What the tenant lacked: an access package with more resource role bindings than one server page.
  ```

---

## T. Teardown

- [ ] **T.1 Delete what this run created.** `-WhatIf` first, every time.

  **Use the prereq script.** It deletes, BY NAME, exactly the objects it and this checklist created,
  in the order the dependencies require -- the reviews first (they reference the package), then
  `oer-live-ap2` from 5.10, then the assignment 2.3 made (an access package with a live assignment
  cannot be deleted, and `adminRemove` is a request, not a delete, so it waits for it), then
  `oer-live-ap`, then the catalog resource, the catalog, and finally the two groups.

  **BY NAME, never by pattern.** Sprint 2's F1 finding is the whole reason this is written out:
  `Get-OERAccessReviewDefinition -All | Where DisplayName -Match OER` deleted an access package
  policy's own lifecycle review and left that policy un-updatable for the rest of the run. Do not
  reach for a wildcard here, in either direction.

  ```powershell
  # Plan first, every time. This prints one What if: line per object and removes nothing.
  & $S4 -SkipUsers -RestoreWrites -WhatIf -SkipVerify
  ```

  ```powershell
  # Then, having read the plan. Each delete still prompts -- these are ConfirmImpact = 'High'.
  & $S4 -SkipUsers -RestoreWrites
  ```

  ```powershell
  # The verify phase must now report the teardown state as a PASS, not a wall of red. That line is
  # in the script on purpose: Sprint 2 recorded a verify run that went red for the tenant being in
  # exactly the state teardown had just put it in.
  & $S4 -SkipUsers -SkipObjects
  ```

  ```powershell
  # The two transcripts and the scratch documents. $LogDir holds refresh-probe.log (3.10) and
  # whatif-5-2.log (5.2); ./live holds the four JSON documents sections 5.6, 5.9, 5.10 and
  # 5.11/5.12 wrote.
  Get-ChildItem $LogDir -Recurse -File | Select-Object FullName, Length
  Get-ChildItem ./live -File | Select-Object FullName, Length
  Remove-Item $LogDir -Recurse -Force
  Remove-Item ./live -Recurse -Force
  Test-Path $LogDir
  Test-Path ./live
  Disconnect-OER
  ```

  **Expect:** each delete prompts (these are `ConfirmImpact = 'High'`), the `What if:` line names
  the definition you meant, `False` from `Test-Path`, and a clean `Disconnect-OER`. The verify run
  in between reports **0 FAIL** with a single `[PASS] teardown state` line standing in for the
  objects that are now gone.
  **Watch for:** `$LogDir` holds **two** full PowerShell transcripts -- `refresh-probe.log` from
  check 3.10 and `whatif-5-2.log` from check 5.2. A transcript captures everything the console
  printed, which is exactly where an unredacted error record -- and therefore a bearer token --
  would be. **Delete both; do not commit them, do not copy from them without redacting.** `docs/live-verification/raw/` and `*.log` in this folder are
  git-ignored for that reason, but a file in `%TEMP%` is protected by nothing but this instruction.
  **Result:**
  ```powershell

  ```

- [ ] **T.2 What cannot be undone.**

  - **The assignment created by 2.3 stays** unless you remove it. It was deliberately not
    auto-applied away: 2.5 does not pass `-AutoApplyDecisions`, precisely so a completed review
    could not silently revoke it.
  - **The read load is in the tenant's Graph telemetry** and cannot be removed. Checks 3.4, 5.10 and
    U.3 are deliberately request-heavy; if your tenant alerts on Graph request volume, expect it to
    have fired.
  - **Checks 3.11 and U.4 each connected an app-only session**, as two different app registrations.
    Both sign-ins are in the tenant's sign-in logs and cannot be removed.
  - **Check 3.10 probe B, if you ran it, revoked a user's sessions.** That signs the account out
    everywhere, not just here.

  - **The three test users stay.** `-RestoreWrites` deliberately does not delete
    `oer-live-assignee`, `oer-live-assignee2` or `oer-live-reviewer`; they are unlicensed and
    sign-in-disabled. Delete them by hand, one call each and by name, if you want them gone.
  - **TWO app registrations were signed in as, and they are disposed of differently.** *(Corrected
    2026-09-13. This bullet used to read "There is no `oer-live-apponly` to clean up, and nothing
    here may be DELETED" -- true of the 2026-09-11 run, and false by the time chapter U had run.
    Do not act on the old reading: it would leave a live app registration standing.)* Check 3.11
    used the tenant's **standing** registration for this module on 2026-09-11 (placeholder row 15),
    because `-IncludeAppOnly` had not been run and `oer-live-apponly` did not exist yet. Check U.4
    used **`oer-live-apponly`** (row 26) on 2026-09-12 and 2026-09-13, after the prereq script
    created it. Take both in turn:
    - **The STANDING registration: nothing to delete, one thing to confirm.** It is not a test
      object, so it is never removed. But 3.11's step 1 disabled its service principal and step 3
      puts it back -- confirm `accountEnabled` reads `True` before you close the windows. **This is
      the one item in T.2 that is an outage if it is skipped**, since anything else in the tenant
      authenticating through that registration is down until it is reversed.
    - **`oer-live-apponly`: a test object this sprint created, and its disposal is a DECISION to
      record.** The prereq script created it, consented `EntitlementManagement.Read.All` to it, and
      a client secret was minted for it in the portal. Either **delete the app registration
      outright** -- which removes the secret and the consented permission with it, and is the
      cleanest end state -- or **keep it and rotate the secret**. U.4 also disabled and re-enabled
      its service principal twice; `accountEnabled` was confirmed `True` at 2026-09-13 11:16:12, so
      if you keep it, it is already in the right state. Write down which way you decided; "kept,
      secret rotated" and "deleted" are both results, and a blank is not.
    - **Neither secret is in this file, so `README.md`'s rotate-on-leak rule is not triggered by
      either.** Both were typed at a `Read-Host` prompt. Rotation is therefore a judgement call
      rather than an obligation -- but a credential handled by hand, outside the store it lives in,
      is still a credential with a history. Record the call, do not leave it implied.

  **Record:** anything that fired, was alerted on, or has to be told to someone. Write "nothing
  fired" if that is what you saw -- an empty block is an unrun check, not a "nothing happened".

  ```powershell
  [pscustomobject]@{
      TestUsersLeftInPlace   = 'oer-live-assignee, oer-live-assignee2, oer-live-reviewer (disabled, unlicensed)'
      StandingAppReEnabled   = 'yes / no -- 3.11 disabled its service principal; this is the outage item'
      StandingAppSecret      = 'rotated / not rotated, deliberately'
      AppOnlyTestAppDisposal = 'deleted / kept and secret rotated / kept and secret NOT rotated -- oer-live-apponly, created by the prereq script'
      AppOnlyTestAppReEnabled = 'yes / no -- U.4 disabled its service principal twice'
      GraphVolumeAlert       = 'fired / did not fire'
      SessionsRevoked        = '3.10 probe B run? yes / no'
      AssignmentRevoked      = 'T.1 revoked the 2.3 assignment? yes / no'
  } | Format-List
  ```
  **Result:**
  ```powershell


# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-13): PRE-FILLED from what the run actually did. Teardown
# itself has NOT been run -- this block records the irreversible half only.
# oer-live-apponly: CREATED by Initialize-OerS4Prereq.ps1 -IncludeAppOnly, consented
#   EntitlementManagement.Read.All, and used by check U.4. Its service principal was disabled and
#   re-enabled twice (2026-09-12 and 2026-09-13); accountEnabled confirmed True at 2026-09-13
#   11:16:12. A client secret was minted in the portal for it, entered through Read-Host, and never
#   written to this file. Decide whether to rotate it or delete the app outright in teardown.
# 2026-09-11 only: check 3.11's first attempt used the PRE-EXISTING app registration
#   <the module's own pre-existing app registration -- REDACTED>, not oer-live-apponly, because
#   -IncludeAppOnly had not been run yet. Rows 15 and 26 of the placeholder table are the two
#   client ids. That service principal was disabled and re-enabled too, and anything else
#   authenticating through it was unavailable for roughly two minutes -- confirm nothing scheduled
#   ran in that window. The display name is written with the same stand-in the 3.11 result block
#   uses: it is a STANDING tenant object, not a test object this run created.
# 3.10 probe B was NOT run: no user's sessions were revoked.
# Graph read volume: checks 3.4, 5.10 and U.3 are request-heavy. Record whether any volume alert
#   fired, or write "nothing fired" -- an empty line is an unrun check.
# The 2.3 assignment and the three test users remain until T.1 is run.
  ```

---

## Verification pass (2026-09-11) -- box states corrected against the pasted evidence

Every box above was re-read against its own `Expect:`/`Record:` before this line was written. Twelve
box states were corrected and the reason is written into the check's own result block as a
`# Verification note` comment. Nothing pasted by the operator was altered.

| Corrected | From | To | Why |
|---|---|---|---|
| 3.1 | `[x]` | `[ ]` | Category `OperationStopped` and Graph's own message, not `ObjectNotFound` and the resolver's tailored text -- the throw never fired (F-A) |
| 3.5 | `[~~]` | `[~]` | `~~` is not one of the three house states |
| 3.6 | `[x]` | `[~]` | `Pages` 1 -- the check's own instruction |
| 3.8 | `[x]` | `[~]` | the check says in bold "Do not tick it" |
| 3.10 | `[ ]` | `[~]` | outcome table row 4, plus the arithmetic that makes probe A impossible here (F-J) |
| 3.11 | `[x]` | `[~]` | the service principal was re-enabled BEFORE the probe ran (F-I) |
| 4.2 | `[ ]` | `[x]` | the Expect is met exactly -- eight properties plus the `Id` alias |
| 4.4 | `[x]` | `[~]` | 1 decision on 1 page; the portal count was never compared |
| 4.5 | `[x]` | `[~]` | 1 instance -- the check's own vacuity warning |
| 5.9 | `[x]` | `[ ]` | the check did not run: the offline validator rejected the document (F-C) |
| 5.11 | `[ ]` | `[~]` | vocabulary confirmed, paging untested |
| 5.12 | `[x]` | `[~]` | same split |

**Left ticked after review:** 1.1, 2.1-2.9, 3.2, 3.3, 3.4, 3.7, 4.1, 4.3, 4.6, 4.7, 5.1, 5.2, 5.3,
5.4, 5.5, 5.6, 5.7, 5.8. Six of them carry a note recording something a later reader needs: 1.1 (the
outcome row to apply), 2.5 and 2.7 (why the reading differs from the Expect), 3.2 (the HTTP status is
missing), 3.4 (3N, not 2N), 3.7 (block noise) and 5.2 (`-User` was ignored). **4.6 is the one
judgement call**: its #71 half is verified and its paging half is not, and the note under it says how
to flip the box if you would rather it read the paging half.

**Still open, and CHAPTER U below is where the runnable part of it now lives.** 3.1, 5.10 and 3.11
are re-run there as U.1, U.3 and U.4; 5.9 is RETIRED and U.2 stands in its place on a path that is
actually reachable. 3.2's record item 2 (the HTTP status) is a two-line addition to its own block,
to be run in U.1's session. **3.10 is not re-run:** probe A is arithmetically impossible on this
tenant and probe B needs a throwaway delegated account, which is a setup task rather than a
checklist step -- the arithmetic is now written into 3.10 itself so nobody spends an afternoon
waiting for a window that does not exist. **Section T has not been run.** The tenant currently holds
`oer-live-ar-mixed` (5.6) and `oer-live-ap2` (5.10, with a `Member` binding and no policy); U.3
removes `oer-live-ap2` before it re-measures, and re-creates it.

**Ten findings came out of this pass.** Four were source defects, fixed in commit `72b3477`: **F-A**
(the not-found code set), **F-B** (`noSubjects` is not a v1.0 enum member), **F-C** (5.9's branch is
unreachable through the public entry point), **F-D** (the pipeline costs 3N, not 2N). Six were
checklist defects, fixed in the checks themselves above, each carrying an `APPLIED` line in its own
verification note: **F-D** again (3.4's heading, `Expect` and column), **F-E** (5.2's dead `-User`),
**F-G** (3.7's unguarded iteration), **F-H** (3.2's unread status and its lying `Format-List`),
**F-I** (3.11's block order), **F-J** (3.10's arithmetic) and **F-K** (the recurring review's
instance id needed its own placeholder row).

---


## U. Re-runs after the source fixes of commit `72b3477`

**What this chapter is.** The 2026-09-11 pass found four source defects and six checklist defects.
The source defects were fixed in commit `72b3477`; the checklist defects were fixed in the checks
themselves, above, each carrying an `APPLIED` line in its own verification note. Four checks cannot
be settled by either edit alone -- they have to be RUN again -- and this chapter is those four, in
one place, so the re-run is one session rather than a hunt through the file.

Every box here is UNTICKED on purpose. Every `Expect:` below was traced to the code that is in the
tree right now, not to the code the original check was written against. Every evidence command
prints something whatever happened -- the counts are there so an empty table announces itself
instead of reading as a clean pass, which is the defect class this file is held to and which three
of its own commands failed on before they were fixed by execution.

| Re-run | Replaces / repeats | Follows | Why it cannot be settled on paper |
|---|---|---|---|
| U.1 | check 3.1 | commit `72b3477`, finding F-A (ruling R-A1) | the not-found code set was narrowed to the MEASURED pair; only a live 404 shows the tailored record now fires |
| U.2 | check 5.9, retired | ruling R-C1 | 5.9's branch is unreachable through the public entry point; this is the same guard on a path that exists |
| U.3 | check 5.10 | commit `72b3477`, finding F-B (ruling R-B1) | the old run's policy create was rejected by Graph, so its request-count measurement measured a failure |
| U.4 | check 3.11 | finding F-I, no source change | the probe ran against an already-re-enabled principal; the block order is fixed, the measurement is not |

**Run them in one connection**, after `Import-OerBuild` reports a build made at or after `72b3477`.
U.1 and U.3 both fail meaninglessly against an older build: U.1 would reproduce the pre-fix
`OperationStopped`, and U.3 would reproduce the `InvalidModel` rejection. **Build first.**

**Run this chapter BEFORE section T, even though it is printed after it.** All four checks read
objects section 2 built (`oer-live-pim`, `OER-CAT-A`, `oer-live-res`, `oer-live-ap`), and teardown
removes them. U.3 removes and re-creates `oer-live-ap2` and its policy; section T clears both
afterwards. Nothing in this chapter leaves an object behind on a passing run except
`oer-live-ap2`/`oer-live-ap2-policy` from U.3 and the two JSON documents under `./live`, which T.1
already deletes -- U.2's whole point is that it creates nothing.

**This PR does not merge until every box in this chapter carries a written result**, on the same
terms as the rest of the file: a box with no result line is an unrun check, and a check that turns
out to be impossible says "cannot be verified, and therefore we do not know" and why.

- [x] (verified 2026-09-12) **U.1 Check 3.1 again: a stale GUID now produces the RESOLVER's error, not Graph's.**
  *(Repeats 3.1 against commit `72b3477`. Run 3.2's two added lines in this same session -- same
  connection, same `$NotAPackage` -- and paste their output into 3.2's result block.)*

  Commit `72b3477` narrowed `Resolve-OERAccessPackageId`'s `-ExpectedErrorCode` from the guessed
  four-code superset to **`'AccessPackageNotFound', 'NotFound'`** -- the code check 3.2 measured on
  this endpoint, plus `Convert-GraphHttpException`'s status-derived label for a 404 whose body
  carried no parseable code. The 2026-09-11 run got `Category = OperationStopped` and Graph's own
  terse "The access package was not found." because the real code fell outside the declared set, so
  the `Omnicit.EntraRBAC.GraphExpectedError` marker was never produced and the tailored `throw`
  never ran.

  ```powershell
  # The same id 3.1 and 3.2 used: oer-live-pim's object id -- syntactically a GUID, and not an
  # access package. Re-asserted here so this step stands on its own in a fresh session.
  $NotAPackage = (Get-OERGroup -Group $PimGroup).Id
  $Out = @(Get-OERAccessPackageAssignment -AccessPackage $NotAPackage `
      -ErrorAction SilentlyContinue -ErrorVariable Err)
  'output objects: ' + $Out.Count         # must print 0

  # Narrow to the record the CMDLET published. -ErrorVariable also collects the engine's own
  # captures of the inner throw, which carry the bare id and no Command; asserting over the join of
  # all of them passes even with the fix reverted.
  $Published = @($Err | Where-Object { $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageAssignment' })
  'published records: ' + $Published.Count    # must print 1 before you read anything below
  $Published | ForEach-Object {
      [pscustomobject]@{
          Id              = [string]$_.FullyQualifiedErrorId
          Category        = [string]$_.CategoryInfo.Category
          MessageIsTheirs = ([string]$_.Exception.Message).StartsWith("The access package id '")
          NamesTheId      = ([string]$_.Exception.Message).Contains($NotAPackage)
          Message         = [string]$_.Exception.Message
      }
  } | Format-List
  ```

  **Expect:** `output objects: 0`, `published records: 1`, and on that one record:

  - `Id` is `AccessPackageNotFound,Get-OERAccessPackageAssignment`,
  - `Category` is **`ObjectNotFound`** (it was `OperationStopped` before the fix),
  - `MessageIsTheirs` **True** and `NamesTheId` **True** -- the message is the resolver's own and
    begins *"The access package id '...' does not resolve to an access package in this tenant."*,
    continuing *"It was accepted as an id because it is a GUID, but entitlement management has no
    access package with that id -- it may be stale, mistyped, or belong to another tenant."*

  **Failure looks like:** `Category = OperationStopped` with the message
  `AccessPackageNotFound: The access package was not found.` -- that is Graph's own text and the
  pre-fix behaviour. Before calling it a defect, check the build: `Import-OerBuild` prints the
  build time, and a build older than `72b3477` cannot contain the narrowed set.
  **`published records: 0` is an EVIDENCE failure, not a pass.** Every field below it would be
  unread and the block would print a clean nothing.

  > **Traced against current source.** `source/Private/Resolve-OERAccessPackageId.ps1` issues
  > `GET .../accessPackages/{id}?$select=id` with
  > `-ExpectedErrorCode 'AccessPackageNotFound', 'NotFound'`, tests the response for the
  > `Omnicit.EntraRBAC.GraphExpectedError` type name, and throws
  > `[ErrorRecord]::new([Exception]::new("The access package id '$DisplayName' does not resolve to
  > an access package in this tenant. ..."), 'AccessPackageNotFound',
  > [ErrorCategory]::ObjectNotFound, $DisplayName)`.
  > `source/Public/Get-OERAccessPackageAssignment.ps1` catches it, scrubs it with
  > `Remove-OERErrorRecord`, rejects the ambiguity branch, and re-publishes the record verbatim
  > through `$PSCmdlet.WriteError($PSItem)` -- which is what appends
  > `,Get-OERAccessPackageAssignment` to the id and leaves the category untouched.
  **Result:**
  ```powershell
> $NotAPackage = (Get-OERGroup -Group $PimGroup).Id  
> $Out = @(Get-OERAccessPackageAssignment -AccessPackage $NotAPackage `  
> -ErrorAction SilentlyContinue -ErrorVariable Err)  
> 'output objects: ' + $Out.Count # must print 0  
output objects: 0  
>  
> # Narrow to the record the CMDLET published. -ErrorVariable also collects the engine's own  
> # captures of the inner throw, which carry the bare id and no Command; asserting over the join of  
> # all of them passes even with the fix reverted.  
> $Published = @($Err | Where-Object { $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageAssignment' })  
> 'published records: ' + $Published.Count # must print 1 before you read anything below  
published records: 1  
> $Published | ForEach-Object {  
> [pscustomobject]@{  
> Id = [string]$_.FullyQualifiedErrorId  
> Category = [string]$_.CategoryInfo.Category  
> MessageIsTheirs = ([string]$_.Exception.Message).StartsWith("The access package id '")  
> NamesTheId = ([string]$_.Exception.Message).Contains($NotAPackage)  
> Message = [string]$_.Exception.Message  
> }  
> } | Format-List  
  
Id : AccessPackageNotFound,Get-OERAccessPackageAssignment  
Category : ObjectNotFound  
MessageIsTheirs : True  
NamesTheId : True  
Message : The access package id '00000000-0000-0000-0000-000000000009' does not resolve to an access package in this tenant. It was accepted as an id because it is a GUID, but entitlement management has no access package with that id -- it may be stale, mistype  
d, or belong to another tenant. Re-run with the access package display name, or with an id from Get-OERAccessPackage.

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-12): PASS, every assertion.
# 'output objects: 0' and 'published records: 1' -- the narrowing worked, so this is the record the
# CMDLET published and not an engine capture. Id AccessPackageNotFound,Get-OERAccessPackageAssignment;
# Category ObjectNotFound; MessageIsTheirs True; NamesTheId True.
# Compare check 3.1's 2026-09-11 run, which gave Category OperationStopped and Graph's terse "The
# access package was not found." Finding F-A is fixed and VERIFIED LIVE: the code the resolver
# declares now includes the one entitlement management actually answers with, so the tailored
# ErrorRecord reaches the caller. Issue #71's stated deliverable is delivered.
  ```

- [x] (verified 2026-09-12) **U.2 A stale GUID in an apply document is a `Failed` row, and NEVER a create.** *(issue #71.
  REPLACES check 5.9, which is retired -- see below. Follows ruling R-C1.)*

  **Why 5.9 is retired, and what still exists.** 5.9 aimed at the no-catalog branch of
  `Sync-OERStructureAccessPackage` -- the one place the apply engine calls
  `Resolve-OERAccessPackageId` directly. That branch **cannot be reached through
  `Invoke-OERStructure` at all**: `Get-OERStructureSchemaJson` declares
  `"required": [ "displayName", "catalog" ]` on every `accessPackages` item, and
  `Invoke-OERStructure` refuses a failing document with no `-SkipValidation` escape. The
  2026-09-11 run proved it by execution -- the document was rejected offline with
  `StructureValidationFailed`, and `Sync-OERStructureAccessPackage` was never entered. **The branch
  is NOT deleted and the schema is NOT relaxed**: the catalog is what scopes the resolution, and a
  tenant-wide lookup throws `AmbiguousName` whenever a display name is reused across catalogs,
  which is the exact problem the catalog-scoped branch exists to avoid. The branch stays correct
  for the PRIVATE entry point the unit suite calls directly, and commit `72b3477` records that in
  the source.

  **The reachable path, traced.** `accessReviews[]` requires `displayName`, `accessPackage` and
  `assignmentPolicy` and nothing else. `source/Private/Sync-OERStructureAccessReview.ps1` passes
  `AccessPackage = $Item.accessPackage` to `New-OERAccessReviewDefinition`, which calls
  `Resolve-OERAccessReviewScopeTarget`, which calls `Resolve-OERAccessPackageId` -- and resolves the
  ACCESS PACKAGE FIRST, before the catalog and before the assignment policy, so a stale GUID there
  reaches issue #71's guard with nothing else in the way.

  ```powershell
  # $NotAPackage is U.1's GUID -- oer-live-pim's object id. It is substituted in below, so no real
  # id is typed into this file. The reviewer is substituted for the same reason; it is never
  # resolved, since the scope resolution fails first (reviewers are mapped after it).
  $DocU2 = @'
{
  "version": "1.0",
  "tenantAlias": "Omnicit",
  "accessReviews": [
    {
      "displayName": "oer-live-ar-stale",
      "accessPackage": "@STALEGUID@",
      "assignmentPolicy": "oer-live-ap-policy",
      "descriptionForAdmins": "Live verification of check U.2. Creates nothing. Safe to delete.",
      "descriptionForReviewers": "Live verification. No action needed.",
      "recurrence": "OneTime",
      "durationInDays": 5,
      "reviewers": [ "@REVIEWER@" ]
    }
  ]
}
'@
  $DocU2.Replace('@STALEGUID@', $NotAPackage).Replace('@REVIEWER@', $Reviewer) |
      Set-Content -Path './live/oer-live-ar-stale.json' -Encoding utf8
  Get-Content ./live/oer-live-ar-stale.json

  # It MUST pass the offline validator -- that is the whole difference from the retired 5.9.
  Test-OERStructure -Path ./live/oer-live-ar-stale.json | Format-List Valid
  'validation findings: ' + @((Test-OERStructure -Path ./live/oer-live-ar-stale.json).Errors).Count
  (Test-OERStructure -Path ./live/oer-live-ar-stale.json).Errors |
      Format-List Section, Item, Path, Message, Severity
  ```

  ```powershell
  $Before = @(Get-OERAccessReviewDefinition -All).Count
  'definitions before: ' + $Before

  Invoke-OERStructure -Path ./live/oer-live-ar-stale.json -Include AccessReviews -WhatIf |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  ```powershell
  # Read the plan above first. This run is real, and the whole point is that it creates NOTHING.
  $R = @(Invoke-OERStructure -Path ./live/oer-live-ar-stale.json -Include AccessReviews `
          -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable ErrU2)
  $R | Format-Table Section, Item, Action, Detail -AutoSize

  $Failed = @($R | Where-Object { $_.Action -eq 'Failed' })
  'failed rows: ' + $Failed.Count          # must print 1 before you read anything below
  $Failed | ForEach-Object {
      [pscustomobject]@{
          Section       = $_.Section
          Item          = $_.Item
          Action        = $_.Action
          Detail        = $_.Detail
          DetailNamesId = ([string]$_.Detail).Contains($NotAPackage)
          ErrorId       = [string]$_.Error.FullyQualifiedErrorId
          ErrorCategory = [string]$_.Error.CategoryInfo.Category
          ErrorTarget   = [string]$_.Error.TargetObject
      }
  } | Format-List
  'engine error records: ' + @($ErrU2 | Where-Object { $_.InvocationInfo.MyCommand.Name }).Count

  $After = @(Get-OERAccessReviewDefinition -All).Count
  [pscustomobject]@{
      Before      = $Before
      After       = $After
      Unchanged   = ($Before -eq $After)
      StaleExists = [bool]@(Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-stale' `
                        -ErrorAction SilentlyContinue).Count
  } | Format-List
  ```

  **Expect, in order:**

  1. `Valid : True`, and `validation findings:` either `0` or a count whose findings are all
     `Severity = Warning`. A `Severity = Error` here means the document is wrong, not the code --
     fix the document and start again.
  2. Under `-WhatIf`: exactly one row, `accessReviews` / `oer-live-ar-stale` / **`Skipped`** /
     `would create access review 'oer-live-ar-stale'`. The plan is emitted from the ShouldProcess
     gate, which sits BEFORE the create and therefore before the resolution -- so `-WhatIf` proves
     nothing about issue #71 and is here only so the real run is not the first thing you see.
  3. On the real run: exactly one row, `Action` **`Failed`**, `Detail` beginning
     `access review creation failed: The access package id '` and naming the stale GUID
     (`DetailNamesId` **True**).
  4. `ErrorId` is `AccessPackageNotFound,Invoke-OERStructure` -- the id `Write-CmdletError` set, plus
     the command name `WriteError` appends. **The command name is the OUTER cmdlet the operator
     invoked, not the inner one that raised the record**: the handler catches
     `New-OERAccessReviewDefinition`'s terminating error and re-publishes it from
     `Invoke-OERStructure`, and `WriteError` stamps the republishing command -- so read the suffix as
     "where the record surfaced", never as "where it came from". *(Corrected 2026-09-13: this line
     predicted `,New-OERAccessReviewDefinition`. The run measured `,Invoke-OERStructure`.)*
     **What is load-bearing is the FIRST comma-separated segment, `AccessPackageNotFound`**; if
     PowerShell has composed the rest differently on your build, record what you got and read the
     segment. `ErrorCategory` is **`ObjectNotFound`**, and `ErrorTarget` is the stale GUID.
  5. `engine error records:` at least `1` -- the handler calls `$Caller.WriteError($PSItem)` before
     it builds the `Failed` row, so the failure reaches the caller's error stream as well as the
     result collection.
  6. `Unchanged` **True** and `StaleExists` **False**. **Nothing was created.**

  **Failure looks like:** an `Action` of `Created` (the guard did not fire and a review now exists
  scoped at nothing -- delete it and report it); or a `Failed` row whose `Detail` reads
  `manager reviewer requires fallbackReviewers` (the `reviewers` array did not survive into the
  document, so the handler defaulted to a manager reviewer and short-circuited BEFORE the create --
  fix the document, this is not a code finding); or `ErrorCategory = OperationStopped`, which is
  U.1's pre-fix shape arriving by this route.

  > **Traced against current source, property by property.** `ConvertTo-OERStructureResult` is the
  > single owner of the result shape and emits exactly `Section`, `Item`, `Action`, `Detail` and
  > `Error` -- `Error` being the `ErrorRecord`, which is where `ErrorId`, `ErrorCategory` and
  > `ErrorTarget` are read from. The `Failed` row and its `-ErrorRecord` come from the catch around
  > `New-OERAccessReviewDefinition @NewParams -ErrorAction Stop` in
  > `source/Private/Sync-OERStructureAccessReview.ps1`, whose `Detail` is
  > `"access review creation failed: $($PSItem.Exception.Message)"`.
  >
  > **The `FailedErrorId`/`FailedMessage`/`FailedCategory` channel is INTERNAL, and is what makes
  > the three `Error*` values above what they are.** It is not a property of the result object.
  > `Resolve-OERAccessReviewScopeTarget` catches the resolver's throw, takes the FIRST
  > comma-separated segment of `FullyQualifiedErrorId` as `FailedErrorId`, the exception message as
  > `FailedMessage`, and the record's own `CategoryInfo.Category` as `FailedCategory` -- populated
  > on EVERY throw out of `Resolve-OERAccessPackageId`, not only on the ambiguity path, so a 403 or
  > an exhausted 429 from the existence read arrives as itself rather than as a not-found.
  > `New-OERAccessReviewDefinition` then prefers all three over its own generic construction
  > (`$Target.FailedCategory` outranks both the `Ambiguous*` special case and the `ObjectNotFound`
  > default) and emits them through
  > `Write-CmdletError -ErrorId $ScopeErrorId -Category $ScopeCategory -TargetObject $Target.FailedValue`,
  > non-terminating. The `-ErrorAction Stop` in the handler is what turns that into the catch above.
  >
  > **Why `reviewers` is declared.** With `reviewers` absent the handler sets `$AddManager = $true`,
  > and the manager-requires-fallback guard returns a `Failed` row BEFORE
  > `New-OERAccessReviewDefinition` is ever called -- the resolver would never be reached and the
  > check would measure nothing. One named reviewer takes the plain path and fires none of the
  > pre-scope guards (`MutuallyExclusiveParameter`, `MutuallyExclusiveReviewer`), so
  > `Resolve-OERAccessReviewScopeTarget` is the first thing that runs.
  **Result:**
  ```powershell
> $DocU2 = @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessReviews": [  
> {  
> "displayName": "oer-live-ar-stale",  
> "accessPackage": "@STALEGUID@",  
> "assignmentPolicy": "oer-live-ap-policy",  
> "descriptionForAdmins": "Live verification of check U.2. Creates nothing. Safe to delete.",  
> "descriptionForReviewers": "Live verification. No action needed.",  
> "recurrence": "OneTime",  
> "durationInDays": 5,  
> "reviewers": [ "@REVIEWER@" ]  
> }  
> ]  
> }  
> '@  
> $DocU2.Replace('@STALEGUID@', $NotAPackage).Replace('@REVIEWER@', $Reviewer) |  
> Set-Content -Path './live/oer-live-ar-stale.json' -Encoding utf8  
> Get-Content ./live/oer-live-ar-stale.json  
{  
"version": "1.0",  
"tenantAlias": "Omnicit",  
"accessReviews": [  
{  
"displayName": "oer-live-ar-stale",  
"accessPackage": "00000000-0000-0000-0000-000000000009",  
"assignmentPolicy": "oer-live-ap-policy",  
"descriptionForAdmins": "Live verification of check U.2. Creates nothing. Safe to delete.",  
"descriptionForReviewers": "Live verification. No action needed.",  
"recurrence": "OneTime",  
"durationInDays": 5,  
"reviewers": [ "person3@example.com" ]  
}  
]  
}   
>  
> # It MUST pass the offline validator -- that is the whole difference from the retired 5.9.  
> Test-OERStructure -Path ./live/oer-live-ar-stale.json | Format-List Valid  
  
Valid : True  
  
> 'validation findings: ' + @((Test-OERStructure -Path ./live/oer-live-ar-stale.json).Errors).Count  
validation findings: 0  
> (Test-OERStructure -Path ./live/oer-live-ar-stale.json).Errors |  
> Format-List Section, Item, Path, Message, Severity  
> $Before = @(Get-OERAccessReviewDefinition -All).Count  
> 'definitions before: ' + $Before  
definitions before: 9  
>  
> Invoke-OERStructure -Path ./live/oer-live-ar-stale.json -Include AccessReviews -WhatIf |  
> Format-Table Section, Item, Action, Detail -AutoSize  
What if: Performing the operation "Create access review definition" on target "oer-live-ar-stale".  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-live-ar-stale Skipped would create access review 'oer-live-ar-stale'  
  
> # Read the plan above first. This run is real, and the whole point is that it creates NOTHING.  
> $R = @(Invoke-OERStructure -Path ./live/oer-live-ar-stale.json -Include AccessReviews `  
> -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable ErrU2)  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-live-ar-stale Failed access review creation failed: The access package id '00000000-0000-0000-0000-000000000009' does not resolve to an access package in this tenant. It was accepted as an id because it is a GUID, but entitlement management has no ac...  
>  
> $Failed = @($R | Where-Object { $_.Action -eq 'Failed' })  
> 'failed rows: ' + $Failed.Count # must print 1 before you read anything below  
failed rows: 1  
> $Failed | ForEach-Object {  
> [pscustomobject]@{  
> Section = $_.Section  
> Item = $_.Item  
> Action = $_.Action  
> Detail = $_.Detail  
> DetailNamesId = ([string]$_.Detail).Contains($NotAPackage)  
> ErrorId = [string]$_.Error.FullyQualifiedErrorId  
> ErrorCategory = [string]$_.Error.CategoryInfo.Category  
> ErrorTarget = [string]$_.Error.TargetObject  
> }  
> } | Format-List  
  
Section : accessReviews  
Item : oer-live-ar-stale  
Action : Failed  
Detail : access review creation failed: The access package id '00000000-0000-0000-0000-000000000009' does not resolve to an access package in this tenant. It was accepted as an id because it is a GUID, but entitlement management has no access package with that i  
d -- it may be stale, mistyped, or belong to another tenant. Re-run with the access package display name, or with an id from Get-OERAccessPackage. 
DetailNamesId : True  
ErrorId : AccessPackageNotFound,Invoke-OERStructure  
ErrorCategory : ObjectNotFound  
ErrorTarget : 00000000-0000-0000-0000-000000000009  
  
> 'engine error records: ' + @($ErrU2 | Where-Object { $_.InvocationInfo.MyCommand.Name }).Count  
engine error records: 2  
>  
> $After = @(Get-OERAccessReviewDefinition -All).Count  
> [pscustomobject]@{  
> Before = $Before  
> After = $After  
> Unchanged = ($Before -eq $After)  
> StaleExists = [bool]@(Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-stale' `  
> -ErrorAction SilentlyContinue).Count  
> } | Format-List  
  
Before : 9  
After : 9  
Unchanged : True  
StaleExists : False

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-12): PASS, all six points of the ordered Expect.
# 1. Valid True, validation findings 0 -- the document passes the offline validator, which is the
#    whole difference from the retired 5.9.
# 2. -WhatIf: exactly one Skipped row, 'would create access review'.
# 3. Real run: exactly one Failed row, DetailNamesId True.
# 4. ErrorCategory ObjectNotFound, ErrorTarget the stale GUID.
# 5. engine error records: 2 (>= 1).
# 6. Before 9 / After 9 / Unchanged True / StaleExists False. NOTHING was created.
#
# ONE RECORDED DEVIATION, and the check anticipated it. ErrorId came back as
# 'AccessPackageNotFound,Invoke-OERStructure', not the predicted
# 'AccessPackageNotFound,New-OERAccessReviewDefinition'. The Expect says the load-bearing part is the
# FIRST comma-separated segment, and that segment is right. The fact behind the difference is worth
# keeping: the record is republished at the OUTER cmdlet the operator invoked, not at the inner one
# that raised it. Correct the Expect to name Invoke-OERStructure.
#
# Ruling R-C1 is vindicated by execution: the accessReviews[] path does reach
# Resolve-OERAccessPackageId, so retiring 5.9 rather than relaxing the schema was the right call.
  ```

- [x] (verified 2026-09-12) **U.3 Check 5.10 again: the policy is CREATED, the entry CONVERGES, and the `1 + A + C` model
  gets measured for the first time.** *(issue #71 and finding F-B / ruling R-B1; follows commit
  `72b3477`.)*

  **What changed.** `{"requestorScope":{"scope":"NoSubjects"}}` used to put `noSubjects` on the
  wire. `noSubjects` is the legacy BETA `requestorSettings.scopeType` spelling and is **not a member
  of the v1.0 `allowedTargetScope` enum at all**, so entitlement management rejected the whole model
  with `InvalidModel: The model is invalid.` -- on the first apply AND on the converging one, so the
  entry never converged and the request counts the old 5.10 recorded describe a run whose policy
  create failed twice. Commit `72b3477` keeps `NoSubjects` bindable in
  `New-OERAccessPackageRequestorScope` and maps it to `notSpecified` -- the same state,
  administrator direct assignment only -- with a `Write-Warning` naming the substitution. The
  builder is the single owner: both the cmdlet path and the apply path funnel through it.

  **REMOVE `oer-live-ap2` FIRST. Do not reuse it.** The failed run left it in the tenant WITH its
  `Member` resource-role binding and WITHOUT a policy. Reusing it makes the first apply a
  non-creating run -- the package exists (no create), the binding is already bound (`A = 0`), only
  the policy is missing (`C = 1`) -- so `ExistsReads` would be `1 + 0 + 1 = 2`, which is neither
  the creating number nor the converged one and settles nothing. The check needs a clean create.

  ```powershell
  # Confirm what is there, then remove it. -WhatIf first, every time.
  Get-OERAccessPackage -DisplayName 'oer-live-ap2' | Format-Table Id, DisplayName, CatalogId
  'policies on it: ' + @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap2' `
      -ErrorAction SilentlyContinue).Count      # expected 0 -- the failed run created none
  Remove-OERAccessPackage -DisplayName 'oer-live-ap2' -WhatIf
  Remove-OERAccessPackage -DisplayName 'oer-live-ap2'
  'still present: ' + @(Get-OERAccessPackage -DisplayName 'oer-live-ap2' `
      -ErrorAction SilentlyContinue).Count      # must print 0 before you go on
  ```

  ```powershell
  # The document is 5.10's, unchanged -- "NoSubjects" stays, because the substitution is the thing
  # under test. ONE entry, R = 1 declared resource role, P = 1 assignment policy.
  $Doc510 = @'
{
  "version": "1.0",
  "tenantAlias": "Omnicit",
  "accessPackages": [
    {
      "displayName": "oer-live-ap2",
      "catalog": "OER-CAT-A",
      "description": "Live verification of check U.3 (request growth). Safe to delete.",
      "resourceRoles": [
        { "resource": "oer-live-res", "role": "Member" }
      ],
      "assignmentPolicies": [
        {
          "displayName": "oer-live-ap2-policy",
          "description": "Live verification of check U.3. Admin assignment only.",
          "requestorScope": { "scope": "NoSubjects" }
        }
      ]
    }
  ]
}
'@
  $Doc510 | Set-Content -Path './live/oer-live-apply.json' -Encoding utf8
  Test-OERStructure -Path ./live/oer-live-apply.json | Format-List Valid
  (Test-OERStructure -Path ./live/oer-live-apply.json).Errors | Format-List Path, Message, Severity

  # The plan, before anything is created. No warning is expected from this one -- see the trace.
  Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -WhatIf `
      -WarningVariable WarnPlan |
      Format-Table Section, Item, Action, Detail -AutoSize
  'plan warnings: ' + @($WarnPlan).Count
  ```

  ```powershell
  # Read the plan above first. The first run CREATES oer-live-ap2; the second must change nothing.
  #
  # '3>&1', NOT '-WarningVariable'. A '-WarningVariable Warn1' written INSIDE this scriptblock sets
  # $Warn1 in the scriptblock's own CHILD scope -- '&' on a scriptblock creates one -- so the outer
  # $Warn1 would keep whatever it held and the warning count below would read 0 whether the
  # substitution warned or not. Measured in a clean pwsh on 2026-09-11: a preset sentinel survived
  # the call untouched, while '3>&1' delivered the WarningRecord into the collected output. Same
  # trap as check 3.11's ErrorIds line, and the same reason it is not used here.
  $Sw1 = [System.Diagnostics.Stopwatch]::StartNew()
  $First = Measure-OerRequest -Label 'first apply' {
      Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages `
          -Confirm:$false -Verbose 3>&1
  }
  $Sec1 = [math]::Round($Sw1.Elapsed.TotalSeconds, 1)

  $Sw2 = [System.Diagnostics.Stopwatch]::StartNew()
  $Again = Measure-OerRequest -Label 'converged re-apply' {
      Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages `
          -Confirm:$false -Verbose 3>&1
  }
  $Sec2 = [math]::Round($Sw2.Elapsed.TotalSeconds, 1)

  # Split the collected output by type: the WarningRecords are the substitution warnings, the rest
  # are the StructureResult rows.
  $IsWarn = { $_ -is [System.Management.Automation.WarningRecord] }
  $Warn1  = @($First.Output | Where-Object $IsWarn)
  $Rows1  = @($First.Output | Where-Object { -not ($_ -is [System.Management.Automation.WarningRecord]) })
  $Warn2  = @($Again.Output | Where-Object $IsWarn)
  $Rows2  = @($Again.Output | Where-Object { -not ($_ -is [System.Management.Automation.WarningRecord]) })

  $First, $Again | Format-Table Label, RequestCount, ExistsReads, Pages -AutoSize
  [pscustomobject]@{
      Entries        = 1
      DeclaredRoles  = 1
      DeclaredPolicy = 1
      FirstSeconds   = $Sec1
      AgainSeconds   = $Sec2
      ModelFirst     = '1 + A + C, A = 1 binding added and C = 1 policy created, so 3'
      ModelConverged = '1'
      FirstMatches   = ($First.ExistsReads -eq 3)
      AgainMatches   = ($Again.ExistsReads -eq 1)
  } | Format-List

  # Measure-OerRequest swallows the command's objects into Output rather than letting them print,
  # so without these lines the apply rows never reach the result block at all.
  'first-run rows: ' + $Rows1.Count
  $Rows1 | Format-Table Section, Item, Action, Detail -AutoSize
  'converged-run rows: ' + $Rows2.Count
  $Rows2 | Format-Table Section, Item, Action, Detail -AutoSize

  # The substitution warning, on both runs, with a count so an empty list announces itself.
  'first-run warnings: ' + $Warn1.Count
  $Warn1 | ForEach-Object { "WARNING: $_" }
  'converged-run warnings: ' + $Warn2.Count
  $Warn2 | ForEach-Object { "WARNING: $_" }
  ```

  **Expect, and all four parts are the check:**

  1. **The first apply creates all three things.** `first-run rows: 3`, all `Created`:
     `created access package oer-live-ap2 (<id>)`, `added resourceRole 'Member' on 'oer-live-res'`,
     and `created assignmentPolicy 'oer-live-ap2-policy'`. **No `Failed` row.** A `Failed` row
     reading `failed to create assignmentPolicy 'oer-live-ap2-policy': InvalidModel: The model is
     invalid.` is the pre-fix behaviour -- check the build before calling it a regression.
  2. **The converged re-apply changes nothing.** `converged-run rows: 3`, all `Unchanged`:
     `access package properties match`, `resourceRole 'Member' on 'oer-live-res' already bound`,
     and `assignmentPolicy 'oer-live-ap2-policy' matches`. An `Updated` row on the second run is a
     NON-CONVERGENCE and is a finding in its own right -- record which field it names. A row count
     of `0` on either run means the output never reached `$Rows*` -- an evidence failure, not a
     quiet success.
  3. **The warning names the substitution, on BOTH real runs.** `first-run warnings` and
     `converged-run warnings` are each at least `1`, and the text reads
     `[New-OERAccessPackageRequestorScope] -Scope NoSubjects is the legacy beta
     requestorSettings.scopeType spelling and is not a v1.0 allowedTargetScope value; ... Sending
     allowedTargetScope 'notSpecified' instead -- the same state (administrator direct assignment
     only). Use -AdminAssignmentOnly or -Scope NotSpecified to silence this warning.`
     `plan warnings: 0` is the expected reading for the `-WhatIf` plan -- see the trace.
  4. **The request model, measured for the first time.** `FirstMatches` **True**
     (`ExistsReads = 3`) and `AgainMatches` **True** (`ExistsReads = 1`). Record `FirstSeconds` and
     `AgainSeconds` too: nobody has a number yet for what the probe costs on an apply run, and this
     is the smallest possible document, so it is a floor rather than a forecast.

  **Failure looks like:** `ExistsReads` of `2` on the first run -- `oer-live-ap2` was not removed
  first and the run was not a creating one. Or `ExistsReads` above `3`: something is probing per
  item rather than per operation, which is the cost model breaking.
  **A zero warning count on either real run is a finding**, not a tidier run: the substitution is
  silent, and a document declaring `NoSubjects` then gets admin-assignment-only with nothing said.

  > **Traced against current source.** `source/Public/New-OERAccessPackageRequestorScope.ps1` maps
  > `NoSubjects = 'notSpecified'` in `$ScopeMap` and emits the `Write-Warning` above it whenever
  > `$Scope -eq 'NoSubjects'`; that warning text is quoted verbatim from the file. The apply engine
  > reaches it through `Build-OERPolicyParts`, which calls `New-OERAccessPackageRequestorScope` for
  > every declared policy entry on **every** run -- create and converged alike -- which is why part
  > 3 expects the warning twice. Under `-WhatIf` against a package that does not exist yet,
  > `source/Private/Sync-OERStructureAccessPackage.ps1` returns from its own `ShouldProcess` gate
  > with `Skipped` rows for the package and each declared child and never builds the policy parts,
  > so no warning is emitted from the plan -- that is what `plan warnings: 0` records.
  >
  > The six `Detail` strings are verbatim from the same handler:
  > `"created access package $Name ($ApId)"`, `"added resourceRole '$RoleName' on '$ResName'"`,
  > `"created assignmentPolicy '$PolName'"`, `'access package properties match'`,
  > `"resourceRole '$RoleName' on '$ResName' already bound"` and
  > `"assignmentPolicy '$PolName' matches"`.
  >
  > The `1 + A + C` model is `Resolve-OERAccessPackageId`'s own `.DESCRIPTION`: one
  > `accessPackages[]` entry costs `1 + A + D + C` probes, where `A` is the missing declared
  > resource-role bindings it adds, `D` the undeclared ones it prunes (only under `-Prune`, and this
  > document uses none), and `C` the assignment policies it creates -- one probe each, plus one for
  > the assignment-policy read that always runs. "An entry that is already converged pays only the
  > 1." `Measure-OerRequest`'s `ExistsReads` counts exactly the
  > `/accessPackages/<id>?$select=id` shape, so it is the probe count and nothing else.
  **Result:**
  ```powershell
> # Confirm what is there, then remove it. -WhatIf first, every time.  
> Get-OERAccessPackage -DisplayName 'oer-live-ap2' | Format-Table Id, DisplayName, CatalogId  
> 'policies on it: ' + @(Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap2' `  
> -ErrorAction SilentlyContinue).Count # expected 0 -- the failed run created none  
policies on it: 0  
> Remove-OERAccessPackage -DisplayName 'oer-live-ap2' -WhatIf  
Remove-OERAccessPackage: Access package not found.  
> Remove-OERAccessPackage -DisplayName 'oer-live-ap2'  
Remove-OERAccessPackage: Access package not found.  
> 'still present: ' + @(Get-OERAccessPackage -DisplayName 'oer-live-ap2' `  
> -ErrorAction SilentlyContinue).Count # must print 0 before you go on  
still present: 0  
>
> $Doc510 = @'  
> {  
> "version": "1.0",  
> "tenantAlias": "Omnicit",  
> "accessPackages": [  
> {  
> "displayName": "oer-live-ap2",  
> "catalog": "OER-CAT-A",  
> "description": "Live verification of check U.3 (request growth). Safe to delete.",  
> "resourceRoles": [  
> { "resource": "oer-live-res", "role": "Member" }  
> ],  
> "assignmentPolicies": [  
> {  
> "displayName": "oer-live-ap2-policy",  
> "description": "Live verification of check U.3. Admin assignment only.",  
> "requestorScope": { "scope": "NoSubjects" }  
> }  
> ]  
> }  
> ]  
> }  
> '@  
> $Doc510 | Set-Content -Path './live/oer-live-apply.json' -Encoding utf8  
> Test-OERStructure -Path ./live/oer-live-apply.json | Format-List Valid  
  
Valid : True  
  
> (Test-OERStructure -Path ./live/oer-live-apply.json).Errors | Format-List Path, Message, Severity  
  
Path : accessPackages[0].catalog  
Message : Catalog 'OER-CAT-A' is not declared in this document. It may already exist in the tenant.  
Severity : Warning  
  
>  
> # The plan, before anything is created. No warning is expected from this one -- see the trace.  
> Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages -WhatIf `  
> -WarningVariable WarnPlan |  
> Format-Table Section, Item, Action, Detail -AutoSize  
What if: Performing the operation "Create access package" on target "oer-live-ap2".  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-live-ap2 Skipped would create access package oer-live-ap2  
accessPackages oer-live-ap2 Skipped would configure resourceRole 'oer-live-res' after access package is created  
accessPackages oer-live-ap2 Skipped would configure assignmentPolicy 'oer-live-ap2-policy' after access package is created  
  
> 'plan warnings: ' + @($WarnPlan).Count  
plan warnings: 0

> $Sw1 = [System.Diagnostics.Stopwatch]::StartNew()  
> $First = Measure-OerRequest -Label 'first apply' {  
> Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages `  
> -Confirm:$false -Verbose 3>&1  
> }   
> $Sec1 = [math]::Round($Sw1.Elapsed.TotalSeconds, 1)  
>  
> $Sw2 = [System.Diagnostics.Stopwatch]::StartNew()  
> $Again = Measure-OerRequest -Label 'converged re-apply' {  
> Invoke-OERStructure -Path ./live/oer-live-apply.json -Include AccessPackages `  
> -Confirm:$false -Verbose 3>&1  
> }  
> $Sec2 = [math]::Round($Sw2.Elapsed.TotalSeconds, 1)  
>  
> # Split the collected output by type: the WarningRecords are the substitution warnings, the rest  
> # are the StructureResult rows.  
> $IsWarn = { $_ -is [System.Management.Automation.WarningRecord] }  
> $Warn1 = @($First.Output | Where-Object $IsWarn)  
> $Rows1 = @($First.Output | Where-Object { -not ($_ -is [System.Management.Automation.WarningRecord]) })  
> $Warn2 = @($Again.Output | Where-Object $IsWarn)  
> $Rows2 = @($Again.Output | Where-Object { -not ($_ -is [System.Management.Automation.WarningRecord]) })  
>  
> $First, $Again | Format-Table Label, RequestCount, ExistsReads, Pages -AutoSize  
  
Label RequestCount ExistsReads Pages  
----- ------------ ----------- -----  
first apply 18 3 5  
converged re-apply 8 1 4  
  
> [pscustomobject]@{  
> Entries = 1  
> DeclaredRoles = 1  
> DeclaredPolicy = 1  
> FirstSeconds = $Sec1  
> AgainSeconds = $Sec2  
> ModelFirst = '1 + A + C, A = 1 binding added and C = 1 policy created, so 3'  
> ModelConverged = '1'  
> FirstMatches = ($First.ExistsReads -eq 3)  
> AgainMatches = ($Again.ExistsReads -eq 1)  
> } | Format-List  
  
Entries : 1  
DeclaredRoles : 1  
DeclaredPolicy : 1  
FirstSeconds : 6,2  
AgainSeconds : 1,9  
ModelFirst : 1 + A + C, A = 1 binding added and C = 1 policy created, so 3  
ModelConverged : 1  
FirstMatches : True  
AgainMatches : True  
  
>  
> # Measure-OerRequest swallows the command's objects into Output rather than letting them print,  
> # so without these lines the apply rows never reach the result block at all.  
> 'first-run rows: ' + $Rows1.Count  
first-run rows: 3  
> $Rows1 | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-live-ap2 Created created access package oer-live-ap2 (00000000-0000-0000-0000-000000000025)  
accessPackages oer-live-ap2 Created added resourceRole 'Member' on 'oer-live-res'  
accessPackages oer-live-ap2 Created created assignmentPolicy 'oer-live-ap2-policy'  
  
> 'converged-run rows: ' + $Rows2.Count  
converged-run rows: 3  
> $Rows2 | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-live-ap2 Unchanged access package properties match  
accessPackages oer-live-ap2 Unchanged resourceRole 'Member' on 'oer-live-res' already bound  
accessPackages oer-live-ap2 Unchanged assignmentPolicy 'oer-live-ap2-policy' matches  
  
>  
> # The substitution warning, on both runs, with a count so an empty list announces itself.  
> 'first-run warnings: ' + $Warn1.Count  
first-run warnings: 1  
> $Warn1 | ForEach-Object { "WARNING: $_" }  
WARNING: [New-OERAccessPackageRequestorScope] -Scope NoSubjects is the legacy beta requestorSettings.scopeType spelling and is not a v1.0 allowedTargetScope value; entitlement manageme  
lowedTargetScope 'notSpecified' instead -- the same state (administrator direct assignment only). Use -AdminAssignmentOnly or -Scope NotSpecified to silence this warning.  
> 'converged-run warnings: ' + $Warn2.Count  
converged-run warnings: 1  
> $Warn2 | ForEach-Object { "WARNING: $_" }  
WARNING: [New-OERAccessPackageRequestorScope] -Scope NoSubjects is the legacy beta requestorSettings.scopeType spelling and is not a v1.0 allowedTargetScope value; entitlement manageme  
lowedTargetScope 'notSpecified' instead -- the same state (administrator direct assignment only). Use -AdminAssignmentOnly or -Scope NotSpecified to silence this warning.  
>

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-12): PASS, and this is the one that settles the most.
# 1. first-run rows: 3, all Created -- access package, resourceRole 'Member', AND
#    assignmentPolicy 'oer-live-ap2-policy'. The policy create is precisely what finding F-B broke.
# 2. converged-run rows: 3, all Unchanged. THE ENTRY CONVERGES. On 2026-09-11 the re-apply still
#    reported Failed, so this is the difference the fix made.
# 3. first-run warnings: 1 and converged warnings: 1, both naming the substitution -- NoSubjects is
#    the legacy beta requestorSettings.scopeType spelling, mapped to allowedTargetScope
#    'notSpecified'. A silent substitution would have been a finding; it is not silent.
# 4. THE REQUEST MODEL, MEASURED FOR THE FIRST TIME. FirstMatches True (ExistsReads 3 = 1 + A + C
#    with A = 1 binding added and C = 1 policy created) and AgainMatches True (ExistsReads 1 on a
#    converged entry). Resolve-OERAccessPackageId's .DESCRIPTION claims exactly this and it holds.
#    FirstSeconds 6,2 and AgainSeconds 1,9 -- a floor for the smallest possible document, not a
#    forecast. Nobody had a number for this before.
# oer-live-ap2 was removed first ('still present: 0'), so this was a genuine creating run and the
# ExistsReads of 3 is the creating number, not the 2 a reused package would have produced.
# Issue #86 is verified live.
  ```

- [x] (verified 2026-09-13) **U.4 Check 3.11 again, with the blocks in execution order.** *(finding F-I. No source change
  -- the checklist was the defect.)*

  The 2026-09-11 run disabled the service principal, saw the app-only window answer **HTTP 401
  `Authorization_IdentityDisabled`, "The authenticating application principal is disabled."** --
  which is exactly the state the wrapper's 401 branch exists for, a token inside its lifetime that
  the service no longer accepts -- and then **re-enabled the principal before running the probe**,
  because the re-enable block was printed above the probe block. The probe met an enabled principal:
  `Refreshes = 0`, `Requests = 2`, `ErrorIds` empty, no "Token rejected" line.
  `AppOnlyTokenRefreshUnsatisfiable` was never reached.

  **Run check 3.11 exactly as it now reads**, step 0 (connect app-only) then step 1 (disable, second
  window) then step 2 (probe, app-only window) then step 3 (re-enable, second window, LAST). Do not
  re-order them and do not run step 3 early. Everything else about the check is unchanged, including
  the `AppOnlySessionCredentialUnavailable` near-miss warning, which is still the most likely wrong
  answer.

  **Expect:** `AuthMethod` reads `ClientSecret`, and `ErrorIds` NAMES
  **`AppOnlyTokenRefreshUnsatisfiable,Get-OERAccessPackageAssignment`** -- category
  `AuthenticationError`, message naming the auth method and directing you to re-run `Connect-OER`.
  **Expect a SECOND id beside it**, `AppOnlySessionCredentialUnavailable,Initialize-OERAuth`, also
  `AuthenticationError`: the `begin` block's refusal, published first and non-fatally. `ErrorIds` is
  a `'; '`-joined string, so read it for the presence of the wrapper's id rather than comparing it
  whole. **No browser window opens at any point.**

  **`Refreshes` of `0` and `token-rejected lines: 0` are the PASS here, and this is the one place in
  the file where that is true.** Read the branch: on an app-only session the wrapper THROWS
  `AppOnlyTokenRefreshUnsatisfiable` *before* it writes the "Token rejected" verbose line and before
  it calls `Initialize-OERAuth -ForceRefresh` -- not calling either is the whole point of the
  branch. So `Refreshes` is `0` on a pass AND `0` on the 2026-09-11 wrong-order run, and it cannot
  discriminate between them. **`ErrorIds` is the discriminator**: `AppOnlyTokenRefreshUnsatisfiable`
  means the branch fired; an EMPTY `ErrorIds` means the read simply succeeded and the probe met an
  enabled principal, which is what happened before.
  **`AppOnlySessionCredentialUnavailable` on its own is NOT a pass -- but it does NOT mean the
  wrapper was skipped, and this line used to say that it did.** *(Corrected 2026-09-13 against the
  run below, which measured both ids from one invocation.)* The two are not alternatives. The
  cmdlet's `begin` calls `Initialize-OERAuth`, which refuses the pre-emptive refresh on an app-only
  session and publishes `AppOnlySessionCredentialUnavailable,Initialize-OERAuth`; that refusal is
  **not fatal**, so the cmdlet carries on into `process`, sends its one request, takes the 401, and
  the wrapper's app-only branch throws
  `AppOnlyTokenRefreshUnsatisfiable,Get-OERAccessPackageAssignment`. One logical failure, two records,
  in that order. **The discriminator is therefore the PRESENCE of
  `AppOnlyTokenRefreshUnsatisfiable`, never the ABSENCE of the other id.** Read the whole `ErrorIds`
  string: if it names `AppOnlyTokenRefreshUnsatisfiable` anywhere, the branch fired and this box is a
  pass, whatever else stands beside it. Only an `ErrorIds` with no
  `AppOnlyTokenRefreshUnsatisfiable` in it is short of a pass -- record the ids you actually got and
  leave this box `- [~]`.
  **Propagation is not instant.** If the probe simply succeeds, wait and re-run; if it never fails,
  that is `- [~]` with "the service principal disable did not produce a 401 within the time waited",
  which is a fact about propagation and not about the module.
  **Whatever happens, step 3 runs.** Confirm `accountEnabled` reads `True` before you close the
  windows, and record that in T.2.

  > **Traced against current source, and the ORDER of two statements is what part of this Expect
  > turns on.** In `source/Private/Invoke-OERGraphRequest.ps1`'s token-rejected branch, the app-only
  > guard (`$script:_OERAuthState.AuthMethod -in 'ClientSecret', 'ClientCertificate'`) throws
  > `AppOnlyTokenRefreshUnsatisfiable` / `AuthenticationError` **above** the
  > `Write-Verbose "[Invoke-OERGraphRequest] Token rejected (status=$StatusCode). Forcing
  > re-authentication and retrying once..."` line and above the `Initialize-OERAuth @RefreshParams`
  > call. `Measure-OerRequest`'s `Refreshes` counter matches that verbose string, so it stays `0` on
  > an app-only pass by construction. `source/Public/Get-OERAccessPackageAssignment.ps1` re-publishes
  > the thrown record through `$PSCmdlet.WriteError($PSItem)` -- from the resolver catch when
  > `-AccessPackage` is a display name, or from the main read's catch otherwise -- which is what
  > appends `,Get-OERAccessPackageAssignment` to the id. The near-miss id
  > `AppOnlySessionCredentialUnavailable` comes from the `$InheritIdentity` app-only guard in
  > `source/Private/Initialize-OERAuth.ps1`, which is reached from the cmdlet's `begin` block and
  > not from the wrapper. Both are unchanged by commit `72b3477`; this re-run is about the order the
  > checklist put them in, not about the code.
  **READ THIS BEFORE THE RESULT BLOCK -- this box is ticked on an operator-recorded READING, not on
  a captured transcript, and it is the only box in this file of which that is true.** The console
  output pasted below is the **2026-09-12 FIRST ATTEMPT**, which did NOT reach the branch: its two
  probe runs both report `ErrorCount 0` and an empty `ErrorIds`, which by this check's own near-miss
  rule is short of a pass. The **2026-09-13 re-run** is what passed, and its scrollback was not
  captured -- the operator's contemporaneous reading of it is written out under
  `# 2026-09-13 RE-RUN` at the end of the block, in the same field-by-field form the probe prints.
  A reader must not have to infer any of that from timestamps a hundred lines apart, and must not
  read the transcript's empty `ErrorIds` as the evidence for the tick. It is not.

  **Result:**
  ```powershell
# =========================================================================================
# 2026-09-12 FIRST ATTEMPT -- CAPTURED TRANSCRIPT. This attempt did NOT reach the branch.
# The disable had not propagated to the token-validating endpoint by the time the probe ran, so the
# read simply succeeded. Two probe runs are below, at 11:31:06 and 11:31:32, and BOTH report
# ErrorCount 0 with an empty ErrorIds -- the "probe met an enabled principal" outcome, not a pass.
# The timing note at the end of this block describes THIS attempt when it says
# "11:30:37 disable -> 11:31:06 probe -> 11:33:03 re-enable": that window measures the FIRST of the
# two probe runs. The second, at 11:31:32, is a repeat inside the same window and answered the same.
# Everything below this line up to the 2026-09-13 marker is that attempt.
# =========================================================================================

# Interactive Window with time stamps.
[11:29:23]  
> Connect-MgGraph -TenantId 00000000-0000-0000-0000-000000000016 -NoWelcome -Scopes 'Application.ReadWrite.All'  
WARNING: Note: Sign in by Web Account Manager (WAM) is enabled by default on Windows. If using an embedded terminal, the interactive browser window may be hidden behind other windows.  
[11:30:16]  
> $AppId = Read-Host 'app-only application (client) id'  
app-only application (client) id: 00000000-0000-0000-0000-000000000026  
[11:30:30]  
> $Sp = @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `  
> -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,displayName,accountEnabled").value)[0]  
[11:30:37]  
> $Sp | Format-List displayName, accountEnabled # confirm the TARGET before the next line  
  
displayName : oer-live-apponly  
accountEnabled : True  
  
[11:30:37]  
> Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)" `  
> -Body '{"accountEnabled":false}' -ContentType 'application/json'  
[11:31:15]  
> $Sp = @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `  
> -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,displayName,accountEnabled").value)[0]  
[11:31:56]  
> $Sp | Format-List displayName, accountEnabled # confirm the TARGET before the next line  
  
displayName : oer-live-apponly  
accountEnabled : False  
  
[11:31:58]  
> # In the second window, once the probe above has answered -- not before.  
[11:33:03]  
> Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)" `  
> -Body '{"accountEnabled":true}' -ContentType 'application/json'  
[11:33:03]  
> @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `  
> -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)?`$select=accountEnabled")).accountEnabled  
True  
[11:33:05]  
>

# App Only Window with timestamps.
[11:28:00]  
> $TenantIdValue = & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.TenantId }  
[11:28:01]  
> $TenantIdValue  
00000000-0000-0000-0000-000000000016  
[11:28:03]  
> $AppId = Read-Host 'app-only application (client) id'  
app-only application (client) id: 00000000-0000-0000-0000-000000000026  
[11:28:19]  
> $Secret = Read-Host 'client secret' -AsSecureString  
client secret: ****************************************  
[11:28:29]  
> Disconnect-OER  
[11:30:54]  
> Connect-OER -TenantId $TenantIdValue -ClientId $AppId -ClientSecret $Secret  
[11:30:59]  
> Remove-Variable Secret -ErrorAction SilentlyContinue  
[11:31:03]  
> & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.AuthMethod }  
ClientSecret  
[11:31:06]  
> $M = Measure-OerRequest -Label 'app-only after SP disable' {  
> Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose 2>&1  
> }  
[11:31:30]  
> $ErrRecords = @($M.Output |  
> Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo.MyCommand.Name })  
[11:31:31]  
> [pscustomobject]@{  
> Refreshes = $M.Refreshes  
> Requests = $M.RequestCount  
> ErrorCount = $ErrRecords.Count  
> ErrorIds = ($ErrRecords | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join '; '  
> Categories = ($ErrRecords | ForEach-Object { [string]$_.CategoryInfo.Category }) -join '; '  
> } | Format-List  
  
Refreshes : 0  
Requests : 2  
ErrorCount : 0  
ErrorIds :  
Categories :  
  
[11:31:31]  
> # Two evidence lines, each of which prints something whatever happened. EXPECT 0 HERE, and read  
[11:31:31]  
> # the Expect below before treating that as a failure: on an app-only session the wrapper throws  
[11:31:31]  
> # ABOVE the "Token rejected" verbose line, so Refreshes and this count are both 0 on a PASS.  
[11:31:31]  
> # ErrorIds is the discriminator, not Refreshes.  
[11:31:31]  
> 'token-rejected lines: ' + @($M.Verbose | Where-Object { $_ -match 'Token rejected' }).Count  
token-rejected lines: 0  
[11:31:32]  
> $M.Verbose | Where-Object { $_ -match 'Token rejected' }  
[11:31:32]  
> $M = Measure-OerRequest -Label 'app-only after SP disable' {  
> Get-OERAccessPackageAssignment -AccessPackage $Package -Verbose 2>&1  
> }  
[11:32:14]  
> $ErrRecords = @($M.Output |  
> Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.InvocationInfo.MyCommand.Name })  
[11:32:14]  
> [pscustomobject]@{  
> Refreshes = $M.Refreshes  
> Requests = $M.RequestCount  
> ErrorCount = $ErrRecords.Count  
> ErrorIds = ($ErrRecords | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join '; '  
> Categories = ($ErrRecords | ForEach-Object { [string]$_.CategoryInfo.Category }) -join '; '  
> } | Format-List  
  
Refreshes : 0  
Requests : 2  
ErrorCount : 0  
ErrorIds :  
Categories :  
  
[11:32:14]  
> # Two evidence lines, each of which prints something whatever happened. EXPECT 0 HERE, and read  
[11:32:15]  
> # the Expect below before treating that as a failure: on an app-only session the wrapper throws  
[11:32:15]  
> # ABOVE the "Token rejected" verbose line, so Refreshes and this count are both 0 on a PASS.  
[11:32:15]  
> # ErrorIds is the discriminator, not Refreshes.  
[11:32:15]  
> 'token-rejected lines: ' + @($M.Verbose | Where-Object { $_ -match 'Token rejected' }).Count  
token-rejected lines: 0  
[11:32:15]  
> $M.Verbose | Where-Object { $_ -match 'Token rejected' }  
[11:32:18]  
>

# =========================================================================================
# 2026-09-13 RE-RUN -- OPERATOR-RECORDED READING, NOT A CAPTURED TRANSCRIPT.
#
# This is the run that passed, and this is the evidence the box is ticked on. The console
# scrollback was not captured; what follows is the operator's contemporaneous reading of the same
# [pscustomobject] the probe block prints, field for field, plus the two evidence lines under it.
# It is recorded here rather than only described in prose so that the values a later reader checks
# sit beside the run they belong to. Its provenance differs from every other result in this file
# and is stated so it can be weighed: no transcript exists to re-read, so these numbers cannot be
# re-derived from this file, only re-measured against the tenant.
#
# Disable 11:09:42 -> probe 11:12:20, about 2 min 40 s of propagation, against oer-live-apponly's
# service principal (placeholder row 26).
#
#   Refreshes            : 0
#   Requests             : 1
#   ErrorCount           : 2
#   ErrorIds             : AppOnlySessionCredentialUnavailable,Initialize-OERAuth; AppOnlyTokenRefreshUnsatisfiable,Get-OERAccessPackageAssignment
#   Categories           : AuthenticationError; AuthenticationError
#   token-rejected lines : 0
#   browser prompt       : none opened
#
# Read against the Expect: Requests 1 (not the 2 of a succeeding read), ErrorCount 2, and
# AppOnlyTokenRefreshUnsatisfiable PRESENT -- which is the discriminator. Refreshes 0 and
# token-rejected lines 0 are the pass here by construction, since the app-only guard throws above
# both. Contrast the 2026-09-12 transcript above: Requests 2, ErrorCount 0, ErrorIds empty.
# =========================================================================================

# ----------------------------------------------------------------------------------------
# Verification note (Cowork, 2026-09-13): PASS -- and issue #75's fifth acceptance criterion,
# the one this branch's own notes called possibly-never-tickable, is now ticked on live evidence.
# Refreshes 0, Requests 1, ErrorCount 2, token-rejected lines 0, and the discriminator present:
#   AppOnlySessionCredentialUnavailable,Initialize-OERAuth
#   AppOnlyTokenRefreshUnsatisfiable,Get-OERAccessPackageAssignment
# both category AuthenticationError. No browser window opened.
# AppOnlyTokenRefreshUnsatisfiable is thrown in exactly one place -- Invoke-OERGraphRequest's
# token-rejected branch, ABOVE both the "Token rejected" verbose line and the
# Initialize-OERAuth -ForceRefresh call -- and the ,Get-OERAccessPackageAssignment suffix is what
# WriteError appends on republication. Its presence is positive proof the wrapper was reached and the
# branch fired. Refreshes 0 and token-rejected lines 0 are the PASS here, exactly as the Expect says,
# because the throw happens above the lines that would increment them.
#
# THE EXPECT'S NEAR-MISS PARAGRAPH IS WRONG AND MUST BE CORRECTED. It reads
# "AppOnlySessionCredentialUnavailable ... means the cmdlet's begin block refused the pre-emptive
# refresh and THE WRAPPER WAS NEVER REACHED", i.e. an either/or. This run shows BOTH fired in ONE
# invocation, in that order: begin's Initialize-OERAuth refused the pre-emptive refresh, the cmdlet
# continued into process anyway, issued its single request, took the 401, and the wrapper's branch
# fired. The presence of the first id says nothing about whether the wrapper was reached. The
# discriminator is the PRESENCE of AppOnlyTokenRefreshUnsatisfiable, not the ABSENCE of the other.
#
# OPEN DESIGN QUESTION FOR THE MAINTAINER, not a checklist matter. The begin-block failure was not
# fatal: the cmdlet went on to send a request with a token it had just been told it could not
# refresh. One logical auth failure therefore surfaces as two AuthenticationError records with
# different ids, and an operator running $ErrorActionPreference = 'Stop' catches the FIRST and less
# informative one. Decide whether begin should stop the invocation or whether the wrapper is meant to
# have the last word.
#
# TIMING, because the first attempt failed on it. 2026-09-12 11:30:37 disable -> 11:31:06 probe ->
# 11:33:03 re-enable gave ~67 s of confirmed-disabled window and the probe simply SUCCEEDED
# (ErrorCount 0, ErrorIds empty) -- the disable had not propagated to the token-validating endpoint.
# 2026-09-13 11:09:42 disable -> 11:12:20 probe, about 2 min 40 s, reached the branch. Propagation is
# not instant in either direction and this checklist will not invent a number for it; allow minutes,
# and re-probe rather than concluding.
# The service principal 'oer-live-apponly' was re-enabled and confirmed: accountEnabled False ->
# PATCH -> True at 2026-09-13 11:16:12. Recorded again in T.2.
  ```

  **FINDING F-L -- one logical auth failure publishes TWO error records, and `-ErrorAction Stop`
  catches the wrong one.**

  **Found by U.4 on 2026-09-13. NOT a merge blocker, and NOT in this PR's scope** -- it is recorded
  here because U.4 is the only place it has ever been observed, and the observation would otherwise
  be lost in a result block.

  **What the 2026-09-13 re-run reported -- an OPERATOR-RECORDED READING, not a captured transcript**
  (same source as U.4's tick; see the provenance marker in U.4's result block, and weigh it
  accordingly). One `Get-OERAccessPackageAssignment` call against an app-only session whose service
  principal had been disabled reported `ErrorCount 2`:

  - `AppOnlySessionCredentialUnavailable,Initialize-OERAuth` -- category `AuthenticationError`,
    from the `$InheritIdentity` app-only guard in the cmdlet's `begin` block;
  - `AppOnlyTokenRefreshUnsatisfiable,Get-OERAccessPackageAssignment` -- category
    `AuthenticationError`, from `Invoke-OERGraphRequest`'s token-rejected branch.

  With `Refreshes 0`, `Requests 1`, zero "Token rejected" verbose lines and no browser prompt. The
  `begin` block's refusal did not stop the invocation: the cmdlet went on to send a request carrying
  a token it had just been told could not be refreshed.

  **Why it did not stop, which the source does not make obvious.** The guard raises through
  `Write-CmdletError ... -Terminating`, and `Initialize-OERAuth`'s own `.DESCRIPTION` calls it
  terminating -- so the code reads as though `begin` should abort. It does not, and that is
  PowerShell's own rule rather than anything this module chose: `ThrowTerminatingError` raised inside
  a nested advanced function is **statement**-terminating, not pipeline-terminating for the caller.
  It ends the `Initialize-OERAuth` call and nothing more, so the calling cmdlet's `begin` runs on to
  its next statement and its `process` block still executes. That is exactly what U.4 observed, and
  it is why the second record can exist at all.

  **The ruling -- recorded here, not decided here: the call continuing is CORRECT, and the wrapper
  is meant to have the last word.** A pre-emptive-refresh refusal fires inside the last five minutes
  of a token's life, and a token still inside its lifetime is normally still accepted. Hard-failing
  in `begin` would make every app-only session unusable for the last five minutes of every token,
  for no correctness gain, and would turn a request that would have succeeded into a failure.
  Nothing about the continuation is to be changed.

  **What IS wrong is the SHAPE of the `begin`-block refusal.** A condition the module itself treats
  as non-fatal is published as an error record, so an operator running
  `$ErrorActionPreference = 'Stop'` aborts on the FIRST and less informative of the two -- the one
  that says the credential is unavailable rather than the one that says the service rejected the
  token. The fix is to emit that refusal as a Warning or a Verbose line instead of an error record,
  so one logical authentication failure yields exactly one error record and it is the informative
  one. **That belongs in its own change, with its own tests** -- it touches
  `source/Private/Initialize-OERAuth.ps1`, which nothing in this branch modifies, and it changes an
  error contract that the unit suite asserts on.

---

## S. Sign-off

- [ ] Every box above carries a written result **either in its own result block or in the successor
      named at the front of its text** -- **including all four boxes of chapter U**, which are the
      re-runs the 2026-09-11 source fixes require. **Three boxes are SUPERSEDED rather than unrun**,
      and each says so in its own first line: **3.1 by U.1**, **5.10 by U.3**, and **5.9**, which is
      RETIRED, **by U.2** on a path that is actually reachable. A superseded box keeps its pasted
      pre-fix evidence and stays `- [ ]` -- the house has three box states and none of them means
      "replaced" -- but its verdict lives in its successor and this line is ticked on that basis, not
      in spite of it. Do NOT tick a superseded box itself: that would assert the pre-fix run passed.
- [ ] Any check that could not be run says so explicitly, with the reason. Every `- [~]` box says
      what data the tenant lacked.
- [ ] Check 1.1 ran, and its outcome has been applied to
      `source/Public/Get-OERAccessPackageAssignment.ps1` before merge. *(Done: outcome row 1,
      case-INsensitive, no code change; the comment was updated in commit `72b3477`.)*
- [ ] Any defect found has been reported back before merge. *(Ten findings from the 2026-09-11 pass
      are listed under "Verification pass" above; four are fixed in `72b3477` and six in this file.
      An eleventh, **F-L**, came out of chapter U and is written up under U.4 -- out of this PR's
      scope by ruling, and recorded rather than fixed.)*

**Section T is tenant cleanup, not a code gate, and it runs AFTER this.** T.1 has not been run and
its result block is empty; T.2 is pre-filled with the irreversible half of what the run already did,
which is a record, not a completed teardown. Nothing in T bears on whether the code on this branch is
correct, so the four boxes above are read against sections 1-5 and chapter U alone. **T.1, T.2 and
the sign-off boxes above are all ticked at the end, once teardown has actually been run** -- which is
why they stand unticked here. The `AppSecretRotated`, `ServicePrincipalReEnabled` and
`GraphVolumeAlert` decisions in T.2 are what make the defect-reported box true for the tenant as well
as for the code.

**Verified by:** ______________________  **Date:** ______________
