# Live verification checklist -- fix/graph-retry-after

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

Where a check says **Record:** instead of **Expect:**, the outcome is genuinely not known in
advance. Write down what actually happened. A recorded observation is the deliverable there -- do
not substitute a guess, and do not tick the box because the number you got looked plausible.

## What happened when this was actually run -- and why it stops here for now

Sections 1 through 4.1 were run against a real tenant on 2026-08-27/28. **The tenant never
throttled.** The provocation in section 2 could not have succeeded on it: check 2.1 issued 11
requests in 5 s and check 2.2 ran 10 rounds over 8 definitions in 473 s, which is roughly 2 requests
a second against an identity bucket of roughly 350 a second (Graph's documented 3,500-8,000
ResourceUnits per 10 s, by tenant size) -- about two orders of magnitude below the limit.
`x-ms-throttle-limit-percentage` came back empty on the healthy call in check 1.4, which Microsoft
documents as the expected outcome below 80% of quota, and which says the same thing a second way.

Following the instruction section 2.2 gives for exactly this outcome, every check in sections 3
through 8 that needs a live 429 now reads "cannot be verified, and therefore we do not know" on its
result line, and none of those boxes is ticked. The handful of checks in those sections that are
answerable WITHOUT a throttle are left as they were, unrun.

**This checklist is resumable.** Nothing above has to be redone; the sections that need a 429 are
still open and can be run later against a larger or busier tenant -- one whose access review surface
is big enough for the fan-out to reach the limit -- by re-running section 2 and continuing from
there.

**This is a legitimate outcome of the exercise, and it is not evidence that the fix is broken.**
Evidence against the fix would be a 429 that DID occur while the module still waited 1-2-4 seconds
from the exponential fallback. No 429 occurred at all. What this run establishes is that the fix
remains UNVERIFIED against live Graph, which is a different statement -- and the one this document
now records.

## Why the unit suite cannot settle any of this, and this document can

The defect this branch fixes survived a green test suite, a code review, and an earlier PR
(`76c1f64`, shipped in PR #53) that claimed to have fixed it. It survived all three for one reason:
**every throttle test in the suite built an exception shape Microsoft Graph never actually
produces.** Two of them went further and pinned the defect as though it were the design, with an
honest comment describing exactly what was wrong.

`Invoke-MgGraphRequest` never surfaces a bare 429. Kiota's `RetryHandler` consumes the 429, retries
internally, and on exhaustion throws an `AggregateException` wrapping
`Microsoft.Kiota.Abstractions.ApiException` -- a type with **no `.Response` member at all**. The
wrapper read `Retry-After` from `$Exception.Response.Headers` and nowhere else. In PowerShell
`$null.Headers.RetryAfter` is `$null` rather than an error, so nothing ever failed loudly: the
header was never once honoured in production, every wait came from the `2^n` fallback, and with a
ceiling of three retries the module's total throttle tolerance was **seven seconds** (1 + 2 + 4).

What shipped on this branch (`39f3948`, `02957a0`):

- `Retry-After` is read from the real Kiota shape -- `ResponseHeaders` and `ResponseStatusCode`,
  by NAME through the PowerShell property bag, walking the exception chain breadth-first to any
  depth. The old `.Response.Headers` reads are kept as a SECONDARY path so an
  `HttpRequestException` still works. Both RFC 9110 header forms are handled: delta-seconds and
  HTTP-date.
- The retry COUNT becomes two nested wait BUDGETS: **300 s per request** (per PAGE under `-All`)
  and **900 s per call** (one `-All` read is many requests inside one call). The per-call bound is
  enforced only at the decision to WAIT, never by halting the paging loop -- halting would return a
  partial collection as though it were complete.
- `ThrottleRetryHardCap = 10` guards the one pathological regime a budget alone does not bound: a
  server answering `Retry-After: 1` forever.
- The 120 s per-sleep clamp is unchanged. The per-sleep floor moved 0 -> 1 so the budget always
  advances.
- The verbose line now names the wait, its **provenance** (`server-directed` vs
  `exponential fallback`) and both remaining budgets.

The mocked suite now proves that IF the header arrives on the Kiota shape, it is read and honoured.
It cannot prove that Graph sends the header on these endpoints, that it arrives on the shape the
extraction was written against in a real tenant, or that a session bounded at 900 s is bearable to
sit through. Only a tenant can answer those. **That is what this document is for.**

## The known-bad baseline you already have

You personally saw the pre-fix failure during the PR #64 checklist run, on
`Get-OERAccessReviewInstance -Definition <id>`: two verbose lines and then a stall. The pre-fix
line had this exact shape (`19fc447:source/Private/Invoke-OERGraphRequest.ps1:254`), with no
provenance word and no budget clause:

```
[Invoke-OERGraphRequest] Throttled. Waiting 1 s before retry 1 of 3...
[Invoke-OERGraphRequest] Throttled. Waiting 2 s before retry 2 of 3...
```

If any line in this checklist's captures still looks like that, you are not running the built
module from this branch. Check 1.1 exists to rule that out before anything else.

## This checklist deliberately generates load against your own tenant

Section 2 asks you to provoke a real Microsoft Graph throttle on purpose. That means issuing a
burst of reads until the service pushes back with HTTP 429.

- **Every command in this document is a READ.** Nothing writes, creates, updates or deletes.
  Section 8 uses `-WhatIf` precisely so the apply engine computes a diff without applying it.
- **A 429 has a blast radius.** Graph throttles per app plus tenant, so while the window is open
  OTHER work by the same app registration in the same tenant will also be throttled. Run this out
  of hours, and not against a tenant a customer is actively using.
- **Ctrl+C stops any loop below immediately.** No loop holds state that a stop can corrupt --
  worst case you lose the in-flight read. The provocation loops also carry their own round and
  wall-clock ceilings so they end on their own if you walk away.
- **If you need the tenant back now**, stop the loop and wait. A Graph throttle window is
  self-clearing; nothing here needs an undo.

## Setup, once

You need:

- **The built module from this branch.** `./build.ps1 -Tasks build` must have been run on
  `fix/graph-retry-after`; the output lands in `output/module/Omnicit.EntraRBAC/2.0.0/`.
- **A tenant with a real access review surface.** At least one access review definition, and
  ideally one definition with many instances (a recurring review that has run for a while). A
  tenant with three definitions and one instance each will not throttle, and several sections below
  will end in "cannot be verified".
- **`AccessReview.Read.All`** on the identity you connect as -- confirmed in check 1.5.
- **A delegated (interactive) session is easiest**, because sections 3-7 want you watching the
  verbose stream as it happens.

Set these once and reuse them in every command block below:

```powershell
$Alias  = 'omnicit'
$LogDir = Join-Path ([System.IO.Path]::GetTempPath()) 'oer-throttle-live'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogDir

Import-Module ./output/module/Omnicit.EntraRBAC/2.0.0/Omnicit.EntraRBAC.psd1 -Force
Connect-OER -TenantAlias $Alias
```

`$LogDir` deliberately sits in the system temp directory, **not** in the repo. The verbose captures
below contain live definition and instance ids; `./live/` is not covered by `.gitignore` and a
`git add .` would stage them.

| Placeholder | What it is |
|---|---|
| `omnicit` | The `Get-OERConfiguration` alias for the test tenant. |
| `<fat-definition-id>` | The access review definition with the MOST instances, chosen in check 1.3. This is the fan-out target for every provocation below; the checklist refers to it as `$FatDef`. |
| `<instance-id>` | Any single instance id from `<fat-definition-id>`, used in check 5.3. |
| `<known-converged-document>` | A structure document you have applied before and know reports `Unchanged` on this tenant. Used only in section 8. |
| `$LogDir` | Where every verbose capture lands. Outside the repo, on purpose. |

**Sections 3 through 8 all depend on section 2 having left the tenant in a throttled state**, and
on the capture files section 2 writes. Sections 1 and 9 are independent and can run at any time.
Run 1 and 2 first, then 3-8 in order without a long pause -- a throttle window closes on its own
and you will have to re-provoke.

---

### 1. Baseline -- what this tenant looks like when nothing is throttled

- [x] **1.1 Prove you are running the fixed module before measuring anything.**

  ```powershell
  $M = Get-Module Omnicit.EntraRBAC
  "$($M.Name) $($M.Version)"
  $M.Path
  Select-String -Path $M.Path -Pattern '^\s*\[int\]\$(ThrottleWaitBudgetSeconds|CallDeadlineSeconds|ThrottleRetryHardCap) = \d+' |
      ForEach-Object { $_.Line.Trim() }
  @(Select-String -Path $M.Path -Pattern 'function Get-ResponseFactFromException').Count
  ```

  **Expect:** version `2.0.0`; a path ending
  `output\module\Omnicit.EntraRBAC\2.0.0\Omnicit.EntraRBAC.psm1`; exactly these three lines, in
  this order:

  ```
  [int]$ThrottleWaitBudgetSeconds = 300
  [int]$CallDeadlineSeconds = 900
  [int]$ThrottleRetryHardCap = 10
  ```

  and `1` for the helper count.
  **Failure looks like:** no matches at all, or a `MaxThrottleRetries = 3` line instead -- you have
  imported a stale build, or the source tree rather than the build output. Re-run
  `./build.ps1 -Tasks build` and re-import before going any further. Every measurement in this
  document is meaningless against the wrong module.
  **Result:**
  ```
  [int]$ThrottleWaitBudgetSeconds = 300
  [int]$CallDeadlineSeconds = 900
  [int]$ThrottleRetryHardCap = 10
  ```

- [x] **1.2 List the tenant's access review definitions and time an unthrottled read.**

  ```powershell
  $Start = Get-Date
  $Defs  = @(Get-OERAccessReviewDefinition -All)
  $Baseline = (Get-Date) - $Start
  "Definitions: $($Defs.Count)   Elapsed: $([int]$Baseline.TotalSeconds) s"
  $Defs | Select-Object Id, DisplayName, Status | Format-Table -AutoSize
  ```

  **Expect:** this completes without a throttle. Everything below is measured against this number,
  so write the elapsed seconds down.
  **Record:** definition count and baseline elapsed seconds: ______________________________
  **Result:**
  Definitions: 8   Elapsed: 1 s

  Id DisplayName Status
00000000-0000-0000-0000-000000000001 AccessReview Test                                  InProgress
00000000-0000-0000-0000-000000000002 AccessRevuew Test                                  Completed
00000000-0000-0000-0000-000000000003 AR-OER-Demo                                        InProgress
00000000-0000-0000-0000-000000000004 OER-DIAG-B-betascope-userReviewer                  InProgress
00000000-0000-0000-0000-000000000005 OER-DIAG-A-v1scope-userReviewer                    InProgress
00000000-0000-0000-0000-000000000006 AR-Test                                            InProgress
00000000-0000-0000-0000-000000000007 Inactive Guest Accounts removal flow (60 days)     InProgress
00000000-0000-0000-0000-000000000008 Anyomous Sharing Links - Eligible - Initial Policy InProgress


- [x] **1.3 Find the fan-out target -- the definition with the most instances.**

  ```powershell
  $Counts = foreach ($D in $Defs) {
      $N = @(Get-OERAccessReviewInstance -Definition $D.Id).Count
      [PSCustomObject]@{ Id = $D.Id; DisplayName = $D.DisplayName; Instances = $N }
  }
  $Counts | Sort-Object Instances -Descending | Format-Table -AutoSize
  $FatDef = ($Counts | Sort-Object Instances -Descending | Select-Object -First 1)
  $FatDef
  ```

  **Expect:** a table, and `$FatDef` set to the definition with the most instances. This check is
  one non-fanned-out paged read per definition, so on a small tenant it should not throttle.
  **Record:** `<fat-definition-id>` and its instance count: ______________________________
  **If the largest count is under about ten**, section 2 is unlikely to provoke anything. Say so
  here rather than pretending later sections passed.
  **Result:**
Id                                   DisplayName                                        Instances

00000000-0000-0000-0000-000000000008 Anyomous Sharing Links - Eligible - Initial Policy         5
00000000-0000-0000-0000-000000000007 Inactive Guest Accounts removal flow (60 days)             3
00000000-0000-0000-0000-000000000001 AccessReview Test                                          2
00000000-0000-0000-0000-000000000003 AR-OER-Demo                                                2
00000000-0000-0000-0000-000000000004 OER-DIAG-B-betascope-userReviewer                          2
00000000-0000-0000-0000-000000000005 OER-DIAG-A-v1scope-userReviewer                            2
00000000-0000-0000-0000-000000000006 AR-Test                                                    2
00000000-0000-0000-0000-000000000002 AccessRevuew Test                                          1  

Id                                   DisplayName                                        Instances

00000000-0000-0000-0000-000000000008 Anyomous Sharing Links - Eligible - Initial Policy         5

- [x] **1.4 Read the throttle headroom Graph reports on a HEALTHY call.**

  This is the one check that goes around the module deliberately. `Invoke-OERGraphRequest` does not
  surface response headers to callers -- by design, since headers can carry correlation and, on
  some shapes, authentication material -- so the only way to see the early-warning signal is a raw
  SDK call in your own console. **This is an operator diagnostic, not a licence to add a raw
  `Invoke-MgGraphRequest` call anywhere in `source/`;** the wrapper remains the only caller
  (`CLAUDE.md`, "Graph Requests").

  ```powershell
  $null = Invoke-MgGraphRequest -Method GET `
      -Uri 'v1.0/identityGovernance/accessReviews/definitions?$top=1' `
      -ResponseHeadersVariable Rh -StatusCodeVariable Sc
  "Status: $Sc"
  @($Rh.Keys) -join ', '
  $Rh['x-ms-throttle-limit-percentage']
  ```

  **Record:** the status, whether `x-ms-throttle-limit-percentage` is present at all on a healthy
  response in this tenant, and its value if so. Microsoft documents this header as appearing past
  80% of quota, so its ABSENCE on an idle tenant is the expected, uninteresting outcome -- record
  that too.
  **Security note:** print header NAMES freely; do not paste header VALUES other than the two named
  here into this document.
  **Result:**
  Status: 200
  Transfer-Encoding, Vary, Strict-Transport-Security, request-id, client-request-id, x-ms-ags-diagnostic, OData-Version, Date, Content-Type
  $Rh['x-ms-throttle-limit-percentage'] = No result at all (empty/null response)

- [x] **1.5 Confirm the required scope, so a later failure is not misdiagnosed as a permission problem.**

  ```powershell
  Get-OERRequiredScope -Cmdlet Get-OERAccessReviewInstance, Get-OERAccessReviewDefinition |
      Format-Table Cmdlet, Transport, @{ n = 'GraphScope'; e = { $_.GraphScope -join ', ' } }, Verified -AutoSize
  ```

  **Expect:** `AccessReview.Read.All` for both, `Transport` `Graph`, `Verified` `True`. Confirm the
  connected identity actually holds it -- a 403 mid-provocation looks nothing like a 429, but a
  tired operator at 22:00 will read them as the same "it broke".
  **Result:**
Cmdlet                        Transport GraphScope            Verified
Get-OERAccessReviewInstance   Graph     AccessReview.Read.All     True
Get-OERAccessReviewDefinition Graph     AccessReview.Read.All     True
---

### 2. Provoke a real throttle on purpose

**Everything from here to section 8 depends on this section succeeding.** The reliable provocation
is the N+1 fan-out recorded as **issue #74**: `Get-OERAccessReviewInstance -IncludeStages
-IncludeDecisions` pages all instances, then pages `/stages` and `/decisions` for each one, with no
pacing. A definition with 30 instances is 60+ paged reads in a tight loop.

- [x] **2.1 One fan-out pass over the fat definition. This may be enough on its own.**

  ```powershell
  $Log   = Join-Path $LogDir 'provoke-1.log'
  $Start = Get-Date
  $Inst  = @(Get-OERAccessReviewInstance -Definition $FatDef.Id -IncludeStages -IncludeDecisions `
                 -Verbose -WarningVariable Warn1 4> $Log)
  $Elapsed = (Get-Date) - $Start
  "Instances returned: $($Inst.Count)   Elapsed: $([int]$Elapsed.TotalSeconds) s"
  "Warnings: $(@($Warn1).Count)"
  "Throttled at all: $(Select-String -Path $Log -Pattern 'Throttled\.' -Quiet)"
  @(Select-String -Path $Log -Pattern '^\[Invoke-OERGraphRequest\] (GET|POST|PATCH|PUT|DELETE) ').Count
  ```

  **Record:** whether `Throttled at all` came back `True`, the elapsed seconds, the instance count,
  and how many requests the call issued. If it is `True`, go straight to section 3 -- do not
  generate more load than you need.
  **Failure looks like:** the call throwing before it finishes. That is not a failed check by
  itself; capture the error and carry it into check 6.4, which is where a give-up is assessed.
  **Result:**
Instances returned: 5   Elapsed: 5 s
Warnings: 0
Throttled at all: False
11

- [x] **2.2 If 2.1 did not throttle, escalate -- a bounded loop over every definition.**

  This loop stops the moment a throttle appears, after 10 rounds, or after 20 minutes, whichever
  comes first. **Ctrl+C ends it safely at any point.**

  ```powershell
  $Log = Join-Path $LogDir 'provoke-2.log'
  if (Test-Path $Log) { Remove-Item $Log }
  $Start = Get-Date; $Round = 0; $Throttled = $false; $AllWarn = $null
  while (-not $Throttled -and $Round -lt 10 -and ((Get-Date) - $Start).TotalMinutes -lt 20) {
      $Round++
      Write-Host "Round $Round ..."
      foreach ($D in $Defs) {
          $null = Get-OERAccessReviewInstance -Definition $D.Id -IncludeStages -IncludeDecisions `
                      -Verbose -WarningVariable +AllWarn 4>> $Log
          if (Select-String -Path $Log -Pattern 'Throttled\.' -Quiet) { $Throttled = $true; break }
      }
  }
  "Throttle observed: $Throttled after $Round round(s), $([int]((Get-Date) - $Start).TotalSeconds) s"
  ```

  **Record:** whether a throttle was ever observed, and after how many rounds and seconds. **How
  hard this tenant is to throttle is itself a finding** -- Graph's identity bucket is 3,500-8,000
  ResourceUnits per 10 s depending on tenant size, so a large tenant may simply absorb this.
  **If no throttle appears after the full 20 minutes:** write "cannot be verified, and therefore we
  do not know" on the result line of every check in sections 3 through 8 that needs a live 429, and
  say that this tenant would not throttle under the module's heaviest read. Do not tick them. That
  outcome is a legitimate result of this exercise and it is worth more than a fabricated pass.
  **Result:**
  Round 1 ...
Round 2 ...
Round 3 ...
Round 4 ...
Round 5 ...
Round 6 ...
Round 7 ...
Round 8 ...
Round 9 ...
Round 10 ...
                                                                                         
❯ "Throttle observed: $Throttled after $Round round(s), $([int]((Get-Date) - $Start).TotalSeconds) s"
Throttle observed: False after 10 round(s), 473 s

- [ ] **2.3 Name the capture file the rest of this checklist reads.**

  ```powershell
  $Log = Join-Path $LogDir 'provoke-1.log'   # or 'provoke-2.log' if 2.2 was the one that throttled
  Select-String -Path $Log -Pattern 'Throttled\.' | Select-Object -First 5 | ForEach-Object { $_.Line }
  ```

  **Expect:** at least one line beginning `[Invoke-OERGraphRequest] Throttled.`
  **Record:** which file, and the first throttle line verbatim: ______________________________
  **Result:**
```
❯ Select-String -Path $Log -Pattern 'Throttled\.' | Select-Object -First 5 | ForEach-Object { $_.Line }

Get-Content $Log
[Initialize-OERAuth] Returning cached auth state for tenant '00000000-0000-0000-0000-000000000009'.
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000010/stages
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000010/decisions
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000011/stages
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000011/decisions
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000012/stages
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000012/decisions
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000013/stages
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000013/decisions
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000014/stages
[Invoke-OERGraphRequest] Fetching page 1...
[Invoke-OERGraphRequest] GET v1.0/identityGovernance/accessReviews/definitions/00000000-0000-0000-0000-000000000008/instances/00000000-0000-0000-0000-000000000014/decisions
```
---

### 3. The proof -- does the wait come from Graph, or from the module guessing?

**This is the check the whole branch exists for.** One observation settles it: whether the verbose
line reports the SERVER's number with the word `server-directed`, or the fallback's 1/2/4 with the
words `exponential fallback`. Depends on section 2.

- [ ] **3.1 Read the provenance of every wait in the capture.**

  ```powershell
  $Waits = Select-String -Path $Log -Pattern 'Throttled\. Waiting (\d+) s \(([^)]+)\)' |
      ForEach-Object { [PSCustomObject]@{ Seconds = [int]$_.Matches[0].Groups[1].Value; Source = $_.Matches[0].Groups[2].Value } }
  $Waits | Format-Table -AutoSize
  $Waits | Group-Object Source | Select-Object Name, Count | Format-Table -AutoSize
  "Total waited: $(($Waits | Measure-Object Seconds -Sum).Sum) s over $($Waits.Count) retries"
  ```

  **Expect:** the line emitted at `source/Private/Invoke-OERGraphRequest.ps1:478-479` has exactly
  this shape:

  ```
  [Invoke-OERGraphRequest] Throttled. Waiting <N> s (server-directed) before retry <A>; <P> s of per-REQUEST and <C> s of per-CALL budget remain.
  ```

  A `Source` of `server-directed` on a real 429 means the header was found on the real Kiota shape
  and honoured -- the fix works. `exponential fallback` on a real 429 means it was not.
  **Record:** the count of each provenance, and the distinct `Seconds` values seen. **Do not
  predict what Graph will ask for.** Whatever it sends is the finding; those seconds values are
  being written down here for the first time in this project's history.
  **Failure looks like:** every wait reading `(exponential fallback)` with seconds 1, 2, 4, 8 -- the
  header was not reachable on this tenant's exception shape, and the fix is inert in production
  exactly as its predecessor was. That is a merge blocker, not a nit. Go to check 4.1, which reads
  the shape directly and will tell you why.
  **Result:**
Total waited:  s over 0 retries

  **Bookkeeping, added after the run -- the result above stands unchanged:** cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **3.2 Confirm the 120 s per-sleep clamp was never exceeded.**

  ```powershell
  ($Waits | Measure-Object Seconds -Maximum).Maximum
  @($Waits | Where-Object Seconds -gt 120).Count
  ```

  **Expect:** the maximum is at most `120`, and the count of over-120 waits is `0`. The clamp is
  unchanged by this branch and bounds any SINGLE unresponsive interval; the budgets bound the total.
  **Failure looks like:** any wait over 120 -- the clamp has been bypassed on the new extraction
  path, and a hostile or absurd `Retry-After` could pin a single request open.
  **Result:**
  0

  **Bookkeeping, added after the run -- the result above stands unchanged:** cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **3.3 Confirm no header material reached the verbose stream.**

  ```powershell
  Select-String -Path $Log -Pattern '(?i)authorization|bearer|client-request-id|request-id|x-ms-' |
      ForEach-Object { $_.Line }
  ```

  **Expect:** no output at all. The extraction reads exactly one entry out of the header collection
  and never returns, logs or writes the collection itself. The unit suite plants an
  `Authorization: Bearer` value beside `Retry-After` and asserts it never reaches the stream; this
  is the same assertion against a real response.
  **Failure looks like:** any match. Stop and treat it as a token-exposure incident before doing
  anything else -- do not paste the matched line into this document.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

---

### 4. The real exception shape, read outside the module

The wrapper converts a Graph failure through `Convert-GraphHttpException`, which deliberately does
NOT chain the original exception (it holds the bearer-carrying `HttpRequestMessage`). So the Kiota
exception is unreachable from the module's error record by design, and the only way to see the
shape this tenant actually produces is to reproduce it with a raw SDK call. Depends on section 2.

- [ ] **4.1 Walk the exception chain of a raw throttled call and record what is really on it.**

  Run this while the throttle window from section 2 is still open. It prints header NAMES and the
  `Retry-After` value only -- never other header values.

  ```powershell
  $Err = $null
  try {
      Invoke-MgGraphRequest -Method GET `
          -Uri "v1.0/identityGovernance/accessReviews/definitions/$($FatDef.Id)/instances" `
          -ErrorAction Stop | Out-Null
  } catch { $Err = $_ }

  if ($null -eq $Err) {
      'No error -- the tenant is not throttled right now. Re-run section 2 and come straight back.'
  } else {
      $Queue = [System.Collections.Generic.Queue[System.Exception]]::new()
      $Queue.Enqueue($Err.Exception)
      $Facts = while ($Queue.Count -gt 0) {
          $E          = $Queue.Dequeue()
          $StatusProp = $E.PSObject.Properties['ResponseStatusCode']
          $HeaderProp = $E.PSObject.Properties['ResponseHeaders']
          $RetryAfter = ''
          if ($HeaderProp -and $HeaderProp.Value) {
              foreach ($K in @($HeaderProp.Value.Keys)) {
                  if ("$K" -eq 'Retry-After') { $RetryAfter = [string](@($HeaderProp.Value[$K]) | Select-Object -First 1) }
              }
          }
          [PSCustomObject]@{
              Type       = $E.GetType().FullName
              StatusCode = if ($StatusProp) { $StatusProp.Value } else { '(no ResponseStatusCode member)' }
              RetryAfter = $RetryAfter
              HeaderKeys = if ($HeaderProp -and $HeaderProp.Value) { (@($HeaderProp.Value.Keys) -join ', ') } else { '(no ResponseHeaders member)' }
          }
          if ($E -is [System.AggregateException]) { foreach ($N in $E.InnerExceptions) { if ($N) { $Queue.Enqueue($N) } } }
          elseif ($E.InnerException) { $Queue.Enqueue($E.InnerException) }
      }
      $Facts | Format-List
  }
  ```

  **Expect, if the investigation's model of production is right:** an outer
  `System.AggregateException` with `(no ResponseStatusCode member)` and
  `(no ResponseHeaders member)`, wrapping a `Microsoft.Kiota.Abstractions.ApiException` carrying
  `StatusCode 429` and a `Retry-After` value. That is the exact shape
  `Get-ResponseFactFromException` was written against.
  **Record:** the full chain -- every type name, at what depth the `ApiException` sits, whether
  `Retry-After` is present, its literal value, and its casing as it appears in `HeaderKeys`. **The
  casing is an assumption only a live capture can retire.** The extraction matches
  case-insensitively on purpose (Kiota keys that dictionary ordinally), so a lower-case
  `retry-after` is handled -- but nobody has ever seen which one Graph sends.
  **Failure looks like:** an `ApiException` present with a `Retry-After` header, while section 3
  reported `exponential fallback`. That combination means the header IS there and the extraction
  still missed it -- most likely the chain is deeper than the walk reaches (the walk stops after 32
  visits), or the header sits on a differently named member. Record the depth and the exact key.
  **Result:**
  Ran once and got. No error -- the tenant is not throttled right now. Re-run section 2 and come straight back.
  Ran again directly after 2.2:
  No error -- the tenant is not throttled right now. Re-run section 2 and come straight back.

  **Bookkeeping, added after the run -- the result above stands unchanged:** cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **4.2 Record the delta-seconds versus HTTP-date question.**

  From 4.1's output: is the `Retry-After` value a bare integer (`60`) or an HTTP-date
  (`Wed, 21 Oct 2015 07:28:00 GMT`)?

  **Record:** which form this tenant returns: ______________________________
  Both are handled (`ConvertFrom-RetryAfterHeader` parses delta-seconds first, then
  `DateTimeOffset` under `InvariantCulture`), so either answer is a pass. The point of recording it
  is that the HTTP-date branch has never run against real data, and if this tenant only ever sends
  delta-seconds then that branch remains unverified in production -- say so.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

---

### 5. The read that used to fail now completes

This is the regression you personally hit. Depends on sections 2 and 3.

- [ ] **5.1 Re-run the exact command that stalled, and let it finish.**

  ```powershell
  $Log5  = Join-Path $LogDir 'read-completes.log'
  $Start = Get-Date
  $Inst5 = @(Get-OERAccessReviewInstance -Definition $FatDef.Id -Verbose -WarningVariable Warn5 4> $Log5)
  $Elapsed5 = (Get-Date) - $Start
  "Instances: $($Inst5.Count)   Elapsed: $([int]$Elapsed5.TotalSeconds) s   Warnings: $(@($Warn5).Count)"
  "Pages fetched: $(@(Select-String -Path $Log5 -Pattern 'Fetching page').Count)"
  Select-String -Path $Log5 -Pattern 'Throttled\.' | ForEach-Object { $_.Line }
  ```

  **Expect:** the command RETURNS, with an instance count matching what check 1.3 recorded for this
  definition. If throttle lines appear in the capture, they are `server-directed` waits followed by
  a completed read -- that is the whole point.
  **Failure looks like:** a stall you have to Ctrl+C (the budget is not bounding anything), or a
  thrown error where 1.3 succeeded (the read got WORSE). A clean, promptly-thrown `TooManyRequests`
  after the budget is genuinely spent is NOT a failure of this check -- that is check 6.4's
  subject. The failure here is specifically hanging, or returning fewer instances than 1.3 saw.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **5.2 Compare the instance count against the unthrottled baseline.**

  ```powershell
  "Baseline (check 1.3): $($FatDef.Instances)   Now: $($Inst5.Count)   Match: $($FatDef.Instances -eq $Inst5.Count)"
  ```

  **Expect:** `Match: True`.
  **Failure looks like:** `Now` lower than the baseline with no error and no warning. That is the
  single most dangerous outcome in this entire document -- see section 7.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **5.3 A single-instance read is unaffected.**

  ```powershell
  $One = $Inst5 | Select-Object -First 1
  Get-OERAccessReviewInstance -Definition $FatDef.Id -Instance $One.Id |
      Select-Object Id, Status, StartDateTime, EndDateTime
  ```

  **Expect:** one instance, matching the row for `$One.Id` in `$Inst5`. This path issues one
  non-paged GET with no `-All` and no fan-out -- it was the recommended workaround before this
  branch, and it must still behave identically.
  **Result:**

---

### 6. The budgets, and what fifteen minutes actually feels like

Depends on section 2. The two bounds are 300 s per REQUEST (per page) and 900 s per CALL. Neither
is a public parameter; both are internal constants in `Invoke-OERGraphRequest.ps1`, and check 1.1
already confirmed their values in the built module.

- [ ] **6.1 Add up what a single call actually spent waiting, and against which budget.**

  ```powershell
  $Waits6 = Select-String -Path $Log -Pattern 'Throttled\. Waiting (\d+) s \(([^)]+)\) before retry (\d+); (\d+) s of per-REQUEST and (\d+) s of per-CALL' |
      ForEach-Object {
          $G = $_.Matches[0].Groups
          [PSCustomObject]@{
              Seconds        = [int]$G[1].Value
              Source         = $G[2].Value
              Retry          = [int]$G[3].Value
              RequestRemains = [int]$G[4].Value
              CallRemains    = [int]$G[5].Value
          }
      }
  $Waits6 | Format-Table -AutoSize
  "Max retry number on any single request: $(($Waits6 | Measure-Object Retry -Maximum).Maximum)"
  "Lowest per-REQUEST remaining: $(($Waits6 | Measure-Object RequestRemains -Minimum).Minimum)"
  "Lowest per-CALL remaining:    $(($Waits6 | Measure-Object CallRemains -Minimum).Minimum)"
  ```

  **Expect:** `RequestRemains` never below 0 and never above 300; `CallRemains` never below 0 and
  never above 900; `Retry` never above 10. Within one command's capture `CallRemains` must be
  monotonically non-increasing -- it is shared by every page of the call, by reference, and a value
  that goes back UP means the per-call budget is being reset per page and does not bind at all.
  **Failure looks like:** `CallRemains` resetting to 900 partway through a `-All` read. That is the
  exact defect review round 1 fixed (a hashtable, not two scalars) and it would return the module
  to a per-page-only bound with a ceiling the operator cannot predict.
  **Record:** the three numbers printed: ______________________________
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **6.2 Record how long the worst single command held the prompt.**

  Take the largest elapsed figure from checks 2.1, 2.2 and 5.1.

  **Record:** worst elapsed, in seconds: ______________________________
  **Record, in your own words, what it felt like to sit through.** Was the verbose stream enough to
  tell that something sensible was happening, or did it look hung? Would you have killed it if you
  had not written this checklist? **This is a real finding, not a soft one.** 900 s was chosen on
  the argument that "fifteen minutes is about the limit of interactive patience", and nobody has
  tested that claim against a human. If the honest answer is that you would have hit Ctrl+C at four
  minutes, the number is wrong and should be argued down before this merges.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **6.3 Record whether the hard cap of 10 was ever the thing that stopped it.**

  ```powershell
  Select-String -Path (Join-Path $LogDir '*.log') -Pattern 'Reached the hard cap of 10 throttle retries' |
      ForEach-Object { "$($_.Filename): $($_.Line)" }
  ```

  **Expect:** most likely no output. The cap binds in neither realistic regime -- server-directed
  60 s waits exhaust the 300 s budget after five retries, and the exponential fallback exhausts it
  after eight. It exists only for a server answering `Retry-After: 1` forever.
  **Record:** if it DID fire, this tenant returned very small `Retry-After` values repeatedly.
  Write down the values from check 3.1 alongside it -- that is a regime nobody has observed, and it
  changes the argument for the cap's value.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **6.4 If anything gave up, confirm it gave up cleanly and said which budget ran out.**

  ```powershell
  Select-String -Path (Join-Path $LogDir '*.log') -Pattern 'Giving up\.' |
      ForEach-Object { "$($_.Filename): $($_.Line)" }
  ```

  **Expect:** if a give-up happened, exactly one of these three shapes, and the caller received a
  terminating error rather than a hang or a short result:

  ```
  [Invoke-OERGraphRequest] Throttled. The next wait needs <N> s (<source>) but only <C> s of the 900 s per-CALL budget remain. Giving up.
  [Invoke-OERGraphRequest] Throttled. The next wait needs <N> s (<source>) but only <P> s of the 300 s per-REQUEST budget remain. Giving up.
  [Invoke-OERGraphRequest] Throttled. Reached the hard cap of 10 throttle retries with <P> s of per-REQUEST budget still unspent. Giving up.
  ```

  When both budgets are gone the per-CALL line is the one that must appear -- it is checked first,
  deliberately, so the operator is told about the bound that ends the COMMAND rather than the one
  that ends the page.
  **Then capture the error the caller actually saw:**

  ```powershell
  $E6 = $null
  Get-OERAccessReviewInstance -Definition $FatDef.Id -IncludeStages -IncludeDecisions `
      -ErrorVariable E6 -ErrorAction SilentlyContinue | Out-Null
  if (@($E6).Count) { $E6[-1].FullyQualifiedErrorId; $E6[-1].Exception.Message }
  ```

  **Record:** the `FullyQualifiedErrorId` and the message verbatim. `TooManyRequests` or
  `activityLimitReached` is what the converter produces when Graph's JSON body reaches it;
  `GraphError` is the documented fallback when the body carries no code at all
  (`Convert-GraphHttpException`). **Any of the three is acceptable** -- what matters is that the
  operator got one clean, diagnosable error and not a silent short result. Write down which one
  this tenant produced.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

---

### 7. Is a partial collection ever returned as complete?

**The most dangerous possible regression, and the reason the per-call budget is enforced at the
decision to WAIT rather than by halting the paging loop.** The apply engine diffs against what it
reads: a short read looks like drift and provokes a WRITE. Depends on section 2.

Two shapes exist in the module today and they behave differently. Both must be recorded.

- [ ] **7.1 A top-level paged read must fail loudly, never return short.**

  ```powershell
  $Log7 = Join-Path $LogDir 'partial-top.log'
  $E7 = $null
  $Top = @(Get-OERAccessReviewInstance -Definition $FatDef.Id -Verbose `
               -ErrorVariable E7 -ErrorAction SilentlyContinue 4> $Log7)
  "Returned: $($Top.Count)   Baseline: $($FatDef.Instances)   Errors: $(@($E7).Count)"
  "Pages: $(@(Select-String -Path $Log7 -Pattern 'Fetching page').Count)"
  ```

  **Expect:** either the full baseline count with zero errors, or zero rows with one error. **Never
  a count between 1 and baseline-1 with no error.** When `Invoke-GraphSingle` finally throws for
  page N it propagates out of the paging loop and the already-fetched pages are discarded, so a
  paged read is all-or-nothing (that discard is **issue #73**, and it is a real cost -- but it is
  the SAFE failure).
  **Failure looks like:** a count strictly between 1 and baseline-1 with `Errors: 0`. Stop the
  merge. That is a silently truncated enumeration and it is worse than any amount of waiting.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **7.2 A sub-read (`-IncludeStages` / `-IncludeDecisions`) degrades to an EMPTY collection plus a Warning.**

  This is pre-existing behaviour, not a regression from this branch -- but the branch changes how
  often it fires, so it must be recorded now.

  ```powershell
  $Log7b = Join-Path $LogDir 'partial-sub.log'
  $Warn7 = $null
  $Sub = @(Get-OERAccessReviewInstance -Definition $FatDef.Id -IncludeStages -IncludeDecisions `
               -Verbose -WarningVariable Warn7 4> $Log7b)
  @($Warn7) | ForEach-Object { $_.ToString() }
  $Sub | Select-Object Id, @{ n = 'Stages'; e = { @($_.Stages).Count } }, @{ n = 'Decisions'; e = { @($_.Decisions).Count } } |
      Format-Table -AutoSize
  ```

  **Expect:** if any warning matches `Could not read stages for access review instance <id>:` or
  `Could not read decisions for access review instance <id>:`, then the corresponding row shows
  `0` -- and that zero is **indistinguishable from a genuinely empty stage or decision list.** The
  Warning is the only signal. `Get-OERAccessReviewDefinition -IncludeInstances` and
  `Get-OERGroup -IncludeMembers` carry the same swallow-to-empty-plus-Warning shape.
  **Record:** how many warnings fired, and whether any object came back with an empty `Stages` or
  `Decisions` while a warning named that same instance id.
  **The operational rule this establishes, which belongs in the PR body:** any `Could not read ...`
  warning means the returned object's sub-collections are NOT authoritative and must not be fed to
  a diff. Confirm you agree with that wording, or correct it.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

- [ ] **7.3 An inventory export degrades a whole SECTION the same way.**

  ```powershell
  $Warn7c = $null
  $Inv = Get-OERInventory -Include AccessReviews -WarningVariable Warn7c
  @($Warn7c) | ForEach-Object { $_.ToString() }
  "AccessReviews captured: $(@($Inv.AccessReviews).Count)"
  ```

  **Expect:** if the warning `Could not read access reviews:` appears, `AccessReviews` is `0` and
  the inventory object is still returned as though it were complete. Compare against the definition
  count from check 1.2 -- remembering that `Get-OERInventory` deliberately skips reviews that are
  not access-package-scoped and skips multi-stage reviews, so a lower number is not automatically a
  truncation.
  **Record:** the warning text if any, the captured count, and whether it matches what 1.2 saw
  after allowing for the documented skips.
  **Why this matters:** an inventory exported while throttled produces a document that
  under-declares. Applied with `-Prune` it would remove real objects. `-Prune` is opt-in and
  child-scope only, which is the mitigation -- confirm you are satisfied that is enough, or file it.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

---

### 8. The apply engine reads under throttle without being provoked into a write

Depends on section 2. **Every command here uses `-WhatIf`. Nothing is applied.**

- [ ] **8.1 Validate a document offline first, so a later diff cannot be blamed on the document.**

  ```powershell
  $Doc = '<known-converged-document>'
  $V = Test-OERStructure -Path $Doc
  $V.Valid
  $V.Errors | Format-List Section, Item, Path, Severity, Message
  ```

  **Expect:** `Valid` is `$true`. Use a document you have applied before and know converges to
  `Unchanged` on a healthy tenant -- otherwise check 8.2 measures the document, not the throttle.
  **If you have no such document**, write "cannot be verified, and therefore we do not know" on 8.1
  and 8.2 and say that no known-converged document exists for this tenant.
  **Result:**

- [ ] **8.2 Run the diff while the tenant is throttled and confirm it does not invent drift.**

  ```powershell
  $Warn8 = $null
  Invoke-OERStructure -Path $Doc -WhatIf -WarningVariable Warn8 |
      Format-Table Section, Item, Action, Detail -AutoSize
  @($Warn8) | ForEach-Object { $_.ToString() }
  ```

  **Expect:** every row `Unchanged`, exactly as it would be on a healthy tenant.
  **Failure looks like:** create/add rows for objects that demonstrably exist, alongside a
  `Could not read ...` warning naming them. That is a degraded read being read as drift.
  `Sync-OERStructureGroup` reads live state with
  `Get-OERGroup -Id <id> -IncludeMembers -IncludeOwners -IncludePimEligibility`, and that cmdlet
  swallows a throttled member read into an empty list plus a Warning (see 7.2) -- so a throttled
  group read makes an existing member look absent. This branch makes it much less likely by riding
  out the throttle; it does not eliminate it.
  **Record:** every non-`Unchanged` row and the warning, if any, that explains it. If you see this
  combination, file it -- it is a distinct defect from anything on this branch.
  **Result:**
  cannot be verified, and therefore we do not know -- this tenant would not throttle under the module's heaviest read (see 2.2).

---

### 9. Everything that is not a throttle is unchanged

Independent of section 2. Run these on a tenant that is NOT currently throttled.

- [ ] **9.1 An ordinary read is no slower than the pre-fix baseline.**

  ```powershell
  $Start = Get-Date
  $Defs9 = @(Get-OERAccessReviewDefinition -All)
  "Definitions: $($Defs9.Count)   Elapsed: $([int]((Get-Date) - $Start).TotalSeconds) s   Baseline (1.2): $([int]$Baseline.TotalSeconds) s"
  ```

  **Expect:** the same count and materially the same elapsed time as check 1.2. The new extraction
  runs only on the FAILURE path; it must cost a successful call nothing.
  **Failure looks like:** a healthy read that is noticeably slower, or that now emits throttle
  verbose lines when nothing was throttled -- the classification has started matching non-429
  failures.
  **Result:**

- [ ] **9.2 A non-throttle failure still fails immediately, with its own error.**

  ```powershell
  $Log9 = Join-Path $LogDir 'notfound.log'
  $E9 = $null
  $Start = Get-Date
  Get-OERAccessReviewInstance -Definition '00000000-0000-0000-0000-000000000000' `
      -Verbose -ErrorVariable E9 -ErrorAction SilentlyContinue 4> $Log9 | Out-Null
  "Elapsed: $([int]((Get-Date) - $Start).TotalSeconds) s"
  if (@($E9).Count) { $E9[-1].FullyQualifiedErrorId; $E9[-1].Exception.Message }
  "Throttle lines: $(@(Select-String -Path $Log9 -Pattern 'Throttled\.').Count)"
  ```

  **Expect:** a prompt failure (a second or two, not minutes), an `ErrorId` beginning
  `AccessReviewDefinitionNotFound`, and **zero** throttle lines. A 403 or 404 must never be dragged
  into the retry loop: the status wins whenever it resolves to a real HTTP code, and only a missing
  or zero status falls through to the message-based classification.
  **Failure looks like:** any throttle line at all, or an elapsed time in the tens of seconds -- a
  non-retryable error is being retried, which turns a clear "not found" into a long wait ending in
  the same message.
  **Result:**

- [ ] **9.3 Record whether the 401 token-refresh path ever fired during this run.**

  ```powershell
  Select-String -Path (Join-Path $LogDir '*.log') -Pattern 'Token rejected \(status=|ACRS claims challenge detected' |
      ForEach-Object { "$($_.Filename): $($_.Line)" }
  ```

  **Record:** whether either line appeared. This is deliberately a record and not an expectation:
  **issue #75** notes that the 401 force-refresh path still reads
  `[int]$AttemptError.Exception.Response.StatusCode` and is blind to the Kiota shape in exactly the
  way the throttle path used to be, so a Kiota-shaped 401 would never trigger it. This branch did
  not touch that path. If your session ran long enough for a token to expire and NO
  `Token rejected` line appeared while calls still failed, say so -- that is live evidence for #75.
  **Result:**

---

### Teardown

- [ ] **T.1 Delete the capture files.**

  ```powershell
  Get-ChildItem $LogDir -Filter '*.log' | Select-Object Name, Length
  Remove-Item $LogDir -Recurse -Force
  Test-Path $LogDir
  ```

  **Expect:** `False`. The captures contain live definition and instance ids. They were written
  outside the repo on purpose; delete them anyway once the results above are transcribed.
  **Result:**

- [ ] **T.2 Disconnect.**

  ```powershell
  Disconnect-OER
  ```

  **Result:**

- [ ] **T.3 What cannot be undone, and what needs no undoing.**

  - **Nothing was written to the tenant.** Every command in this document is a read; section 8 used
    `-WhatIf`. There is no state to restore.
  - **The throttle you provoked cannot be cancelled.** Graph's token bucket refills on its own over
    the following minutes; there is no API to clear a throttle window early. If other work in this
    tenant was affected while you ran section 2, it recovers without intervention.
  - **The load you generated is in the tenant's sign-in and Graph telemetry**, and cannot be
    removed. If your tenant has alerting on Graph request volume, expect it to have fired.
  - **Any `Could not read ...` warning you saw in section 7 describes a read that really did come
    back empty.** If you exported an inventory during this run (check 7.3), do not keep it -- it may
    under-declare, and applying it later with `-Prune` would delete real objects.

  **Record:** anything that fired, was alerted on, or has to be told to someone:
  ______________________________
  **Result:**
