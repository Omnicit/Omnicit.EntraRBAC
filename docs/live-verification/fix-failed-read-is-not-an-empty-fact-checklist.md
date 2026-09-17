# Live verification checklist -- fix/failed-read-is-not-an-empty-fact (issues #76, #60)

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
either rule.

---

## State of this run (re-run 2026-09-03, superseding 2026-09-02)

**Tally: 36 of 48 passed.** The twelve that did not: 1.4-1.8, 2.4, 3.11, 4.4, 5.1-5.3, 5.5. Where a
check was not re-run its 2026-09-02 result stands; every box carries the date of its evidence.

**Why this run is trustworthy and the first was not.** `Disconnect-OER` is not enough after a
consent change: AzAuth keeps ONE static `TokenCredential` per process with MSAL's cache behind it,
so the next `Connect-OER` for the same client id returns the SAME token -- old `roles` claim and all
-- for up to an hour. Only `Get-AzToken -Force` clears it. `Connect-Fr` now forces one and prints
the `roles` claim, and that printed line is what every route-dependent check rests on.

**All five routes were genuinely narrowed**, each provable from its own `Token roles (Narrow, N)`
line and, for route A, from the service principal's `appRoleAssignments` as well. **Routes C and D
are nevertheless UNUSABLE here:** with `Member.Read.Hidden` verifiably absent Graph still returned
the members of a hidden administrative unit (2.1, 2.4) and of a hidden Microsoft 365 group (5.5), so
`GroupMemberReadFailed`, `GroupOwnerReadFailed` and `AdministrativeUnitMemberReadFailed` have no
live proof and `groups[].members` is unverified end to end -- section 7.2b. Route A denies only on a
PIM-onboarded group (7.1b). Checks 1.4-1.7 were not re-run: no `Token roles` line behind them.

**Teardown has NOT been run.** T.1-T.7 plus the new T.1b are open. Standing writes: eligibility plus
an opened member PIM policy on `oer-fr-grp` (1.8), `oer-fr-au-c` created hidden (2.1), a member
added to `oer-fr-grp` (5.7), `ActivationMaxHours` on `oer-fr-grp` (5.8), two access reviews (6.1,
6.2), `DurationInDays` on `oer-fr-review` (6.3), an assignment policy on `oer-fr-ap` (6.4). The
narrow app is still narrowed and `$Work` still holds bundles carrying real tenant ids.

---

## 0. How the failure is provoked -- and why NOT a throttle

**Read this section before anything else. It exists so the next person does not spend two evenings
on the wrong provocation.**

Issue #76's own acceptance criterion says "provoke a throttle during an export". **Do not try.**

The arithmetic is settled and is not worth re-running. The module issues roughly 2 requests per
second against a per-identity bucket of roughly 350 per second (Graph's documented 3,500-8,000
ResourceUnits per 10 seconds, by tenant size) -- about two orders of magnitude below the limit. PR
#77's live run spent two evenings trying to reach it on a small tenant and recorded
`Throttled at all: False`; on the healthy call it also observed an empty
`x-ms-throttle-limit-percentage`, which Microsoft documents as the expected outcome below 80 percent
of quota, and which says the same thing a second way. That run is written up in
`docs/live-verification/fix-graph-retry-after-checklist.md`, whose sections 3-8 remain unrun for
exactly this reason.

**The guard this branch adds is the CATCH, not the status code.** In `Get-OERGroup` and
`Get-OERAdministrativeUnit` there is one catch per collection read, and every failure of that read
-- a 429, a 403, a 5xx, a dead transport, a token that expired mid-enumeration -- lands in the same
catch and takes the same path: scrub the record, omit the property, write a non-terminating error.
A permission-denied read is therefore not a weaker proof than a throttle. It is the same proof,
obtainable in a minute, and it is repeatable, which a throttle is not.

### The four provocation routes, and which collection each one reaches

Each route splits a permission the module's own `Get-OERRequiredScope` reports. Confirm the split
before you start:

```powershell
Get-OERRequiredScope -Name Get-OERGroup, Get-OERAdministrativeUnit | Format-List
```

| Route | Consent this | Withhold this | Denied read | ErrorId |
|---|---|---|---|---|
| **A** | `Group.Read.All` | `PrivilegedEligibilitySchedule.Read.AzureADGroup` | group PIM eligibility | `GroupPimEligibilityReadFailed` |
| **B** | `AdministrativeUnit.Read.All` | `RoleManagement.Read.Directory` | AU `/scopedRoleMembers` | `AdministrativeUnitScopedRoleReadFailed` |
| **C** | `AdministrativeUnit.Read.All` | `Member.Read.Hidden` | hidden-membership AU `/members` | `AdministrativeUnitMemberReadFailed` |
| **D** | `Group.Read.All` | `Member.Read.Hidden` | hidden-membership group `/members` | `GroupMemberReadFailed` |

**Route B is the primary one for this checklist.** `administrativeUnits[].scopedRoles` is one of the
only three keys that a failed read projects as an explicit JSON `null` (the other two are
`groups[].members` and `administrativeUnits[].members`), so route B alone drives the whole chain
end to end: `Get-OERAdministrativeUnit` -> `Get-OERInventory` -> `inventory.json` ->
`Invoke-OERStructure -Prune`. Sections 3 and 4 are written against it.

**Route A is the CLEANEST on paper, and it DOES provoke a real denial on this tenant -- but only
against the right group (2026-09-03, checks 1.8 and 3.13).** With both
`PrivilegedEligibilitySchedule.*` roles verifiably absent from the token, ten PIM-onboarded,
role-assignable groups answered `PermissionScopeNotGranted` and had their `eligibility` key omitted,
while `oer-fr-grp` -- the group check 1.8 happens to use -- answered 200 with an empty `value` and
kept succeeding even after it was onboarded to PIM for Groups. **Pick the group from the tenant's
PIM-onboarded set, not from the `oer-fr` fixtures.** Why `oer-fr-grp` is treated differently is
undetermined and is follow-up work. The eligibility-schedule endpoints list
`PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` as their only higher-privileged alternative
-- no `Directory.*` scope satisfies them at all -- so denying the one Read scope is genuinely
enough. Route B is the opposite: `Directory.Read.All` and `Directory.ReadWrite.All` both satisfy
`GET /administrativeUnits/{id}/scopedRoleMembers`, and `Directory.Read.All` is in the set
`Get-OERRequiredScope -Unique` reports, so it must be denied too. The setup section carries the
full per-route denial list; do not shortcut it.

**Do NOT try to provoke a failed MEMBER read by withholding `GroupMember.Read.All`.** An earlier
draft of this plan said to. It does not work: Microsoft documents `Group.Read.All` as a
higher-privileged permission for `GET /groups/{id}/members`, so it already covers the member read on
its own and withholding `GroupMember.Read.All` changes nothing.

**Routes C and D rest on `Member.Read.Hidden`,** which Microsoft documents as additionally required
to list the members of a hidden-membership group or administrative unit. Two cautions:

- **Use app-only.** The delegated form of the hidden-membership rule is satisfied when the signed-in
  user is a member of the object, so an interactive run as an administrator may read the members
  anyway. Sign in with a client secret or certificate on an app registration whose APPLICATION
  permissions are exactly the ones in the table.
- **Observe, do not assume, what Graph answers.** Whether a hidden-membership `/members` read
  returns `403 Authorization_RequestDenied` or simply an empty collection is a Graph behaviour this
  checklist does not take on trust. Checks 1.1 and 2.1 record it. **If it comes back empty rather
  than denied, that is not a defect in this branch** -- it means routes C and D are unusable on this
  tenant, and every later check that depends on them is answered from route B instead. Say so on the
  result line. **That is exactly what happened on 2026-09-03: EMPTY, on both routes, with the
  permission verifiably withheld** (2.1, 2.4, 5.5). Read section 7.2b before planning any further
  work on the member path.

**An administrative unit's `visibility` is NOT settable after creation.** An earlier draft of this
checklist said it was, and route C was written around
`Set-OERAdministrativeUnit -Visibility HiddenMembership` on an existing unit. Graph rejects that:

```text
Request_BadRequest: HiddenMembership can only be set during administrative unit creation.
```

That was observed live on 2026-09-02 (check 2.1), and it is a platform rule, not a permission
problem -- no amount of consent makes it work. **Route C therefore needs a unit that was created
hidden**, and the setup below creates `oer-fr-au-c` for exactly that. A unit created without
`-Visibility HiddenMembership` can never be used for route C and has to be replaced, not amended.

**A GROUP's `visibility` is creation-only too, for the same reason and with one extra constraint.**
Microsoft documents it twice over: `HiddenMembership` "can be set only for Microsoft 365 groups when
the groups are created. It can't be updated later", and visibility "is supported only for unified
groups; it is not supported for security groups." So **`oer-fr-hidden` must be created in the portal
as a Microsoft 365 group with Hidden membership from the start** -- it cannot be amended into one
afterwards, and a security group cannot be hidden at all, at creation or later. Route D is a
Microsoft 365 group or it is nothing.

That has one consequence which has already cost this checklist a run, so it is spelled out here
rather than left to be rediscovered: **`Get-OERInventory` defaults its group filter to
`securityEnabled eq true`, which excludes every Microsoft 365 group by construction.** Any check
that reads the DEFAULT inventory can never see `oer-fr-hidden` -- not as a null, not as an empty
array, not at all. Every inventory check on route D must pass `-GroupFilter` explicitly, e.g.
`-GroupFilter "groupTypes/any(c:c eq 'Unified')"` or a filter naming the group directly; checks 3.11
and 4.4 both do. **`Export-OERInventory` has no `-GroupFilter` parameter** and hardcodes the same
`securityEnabled eq true` for `groupsRoster.json`, so route D cannot be driven through the bundle
export at all -- that is why section 3's bundle checks are built on route B, and why 3.11 is
answered from `Get-OERInventory` instead.

### What this branch changed, in one paragraph

Before: a failed `/members`, `/owners`, PIM-eligibility or `/scopedRoleMembers` read substituted an
empty collection and wrote a warning. That empty collection then travelled: `Get-OERInventory` wrote
it into `inventory.json` as `"members": []`, a statement of fact, and `Invoke-OERStructure -Prune`
deleted every live member on the strength of it. After: the property is OMITTED and a
non-terminating error is written; the inventory projects an explicit `null` for the three keys where
an omitted key would still reconcile and still prune, and omits the key for the two where omission
already means hands-off; and five reads inside the apply engine that previously swallowed their
errors now report one `Failed` row and reconcile nothing for that item.

---

## Setup, once

> **The environment this run used (filled in 2026-09-02).** Everything below is created by
> `Initialize-OerFrPrereq.ps1`, which lives outside this repository. It now ends with a VERIFY phase
> that re-reads every object and both apps' effective consent and prints PASS/WARN/FAIL -- the
> `NARROW route X` line must read PASS before any route-X check is run, or the check proves nothing
> (that is exactly what went wrong on 2026-09-02).
>
> ```powershell
> $Pre = "C:\Obsidian\Philip Obsidian\Notes\Omnicit Entra RBAC\Initialize-OerFrPrereq.ps1"
> & $Pre -RotateClientSecret -RestoreWrites -NarrowRoute B   # once: rotate secrets, undo T.1 writes, create oer-fr-au-c, verify
> & $Pre -SkipObjects -NarrowRoute D                         # switch route + verify  (A | B | C | D | E | Full)
> & $Pre -SkipConsent -SkipObjects -NarrowRoute D            # verify only, no changes
> ```
>
> | Checklist name | What it was in this run |
> |---|---|
> | tenant | `00000000-0000-0000-0000-000000000001`, signed in interactively as `person3@example.com` via `00000000-0000-0000-0000-000000000002` |
> | `oer-fr-full` | an app registration, appId `00000000-0000-0000-0000-000000000003` |
> | `oer-fr-narrow` | a second app registration, appId `00000000-0000-0000-0000-000000000004` |
> | `<policy-name>` | `oer-fr-policy` (admin assignment only) |
> | `person1@example.com` / `person2@example.com` | two disabled, unlicensed test users |
> | `oer-fr-grp` | members person1 + person2, owner person1 |
> | `oer-fr-au` | member person1, scoped role *User Administrator* -> person1 |
> | `oer-fr-au-b` | member person2 |
> | `oer-fr-review` | Quarterly, reviewer person1 |
>
> **Redact every real value before any of this is pasted into the repository**
> (`docs/live-verification/README.md`).

**Client secrets.** Both app registrations' client secrets were pasted into this file during the
run and were removed again before it was committed. Redaction does not undo disclosure: **both
secrets must be ROTATED**, and a secret is never pasted into a tracked file in the first place.
`tests/QA/dochygiene.tests.ps1` now fails on a credential-shaped string in this folder, so the same
paste would be caught by the gate rather than by a reviewer.

Use a throwaway tenant or a disposable slice of a test tenant. **Nothing in this checklist is
allowed to run against a customer tenant.**

**Objects.** Create these before you start, under whatever principal you normally use:

| Object | Name used below | Notes |
|---|---|---|
| Security group | `oer-fr-grp` | At least two members and one owner. |
| Security group | `oer-fr-empty` | Zero members, zero owners. The control case. |
| Administrative unit | `oer-fr-au` | At least one member and one scoped role assignment. |
| Administrative unit | `oer-fr-au-b` | A second unit, at least one member. Section 3 needs two. |
| Administrative unit | `oer-fr-au-c` | Route C only. **Created with `New-OERAdministrativeUnit -HiddenMembership`**; at least one member. Visibility cannot be added afterwards -- see section 0. |
| Microsoft 365 group | `oer-fr-hidden` | Route D only. **Created in the portal as a Microsoft 365 group with Hidden membership** -- creation-only, and impossible on a security group (see section 0); at least two members. |
| Catalog | `OER-FR-CAT` | Holds the access package below. |
| Access package | `oer-fr-ap` | In `OER-FR-CAT`, with at least one resource role binding and one assignment policy. |
| Access review | `oer-fr-review` | On `oer-fr-ap`, recurring **Quarterly**. Section 6 needs a non-OneTime cadence. |

**Two app registrations.** Both need admin consent on APPLICATION permissions, and both live in the
same tenant:

- **`oer-fr-full`** -- every scope `Get-OERRequiredScope -Unique` reports for the cmdlets used here,
  **plus `Member.Read.Hidden`**. That last one is not in the module's required-scope map, since no
  cmdlet needs it against an ordinary object -- but without it the control principal cannot read the
  hidden-membership objects routes C and D create, and a control that also fails is not a control.
  With this set, every read in this checklist succeeds.
- **`oer-fr-narrow`** -- the same set minus the withheld permission for the route you are running,
  **and minus every documented HIGHER-PRIVILEGED alternative for that route's endpoint.** This is
  the trap that a naive "minus one scope" reading walks straight into. Microsoft grades each
  endpoint's permissions as one least-privileged entry plus a list of higher-privileged ones that
  ALSO satisfy it, and `Get-OERRequiredScope -Unique` reports `Directory.Read.All` (for
  `Get-OERInventory` and `Export-OERInventory`), which is a higher-privileged alternative for the AU
  and group collection reads. Withhold only the least-privileged scope and the read still returns
  200 -- and check 2.5 then reads as a regression when nothing is wrong. Withhold the whole row:

  | Route | Withhold ALL of these |
  |---|---|
  | **A** (group PIM eligibility) | `PrivilegedEligibilitySchedule.Read.AzureADGroup`, `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup` |
  | **B** (AU scoped roles) | `RoleManagement.Read.Directory`, `RoleManagement.ReadWrite.Directory`, `Directory.Read.All`, `Directory.ReadWrite.All` |
  | **C** (hidden-membership AU members) | `Member.Read.Hidden` only |
  | **D** (hidden-membership group members) | `Member.Read.Hidden` only |
  | **E** (section 5.1-5.4, entitlement management) | `EntitlementManagement.Read.All`, `EntitlementManagement.ReadWrite.All` -- app-only has no write-without-read scope; see the note at the top of section 5 |

  Routes C and D need no extra denials: hidden membership requires `Member.Read.Hidden`
  specifically, and no other scope substitutes for it.

  **Route B costs you `Directory.Read.All`,** which `Get-OERInventory` also uses to name principals
  through `directoryObjects/getByIds`. Expect friendly-name resolution to degrade to raw object ids
  in sections 3 and 4 under the narrow principal. That is expected and is not a finding -- the
  checks there assert on `scopedRoles` being null and on what `-Prune` plans, neither of which needs
  a resolved display name. Section 4 applies as `oer-fr-full`, so the plan itself reads normally.

Consent is per-route. When you move from route B to route A, C or D, edit `oer-fr-narrow`'s consent
and **wait for the change to take effect** -- an application permission change is not always
immediate, and a stale token will read fine and make you think the fix regressed. `Disconnect-OER`
then `Connect-OER` is NOT a fresh token: AzAuth caches the app token in-process for up to an hour
(see the helper block). Use `Connect-Fr`, which forces one, and read the `Token roles` line it
prints -- the withheld permission must be absent from it.

**Where files go.**

```powershell
$Work = Join-Path ([System.IO.Path]::GetTempPath()) 'oer-fr'
New-Item -ItemType Directory -Path $Work -Force | Out-Null
```

This is deliberately OUTSIDE the repository. Bundles written here carry real tenant object ids;
nothing from `$Work` is ever committed. Teardown deletes it.

## The helper block

Paste this once per session. It is the connect-as-narrow / connect-as-full switch every check below
refers to, plus the two assertions that recur throughout.

```powershell
$Tenant = '00000000-0000-0000-0000-000000000001'   # Omnicit AB

# Sign in app-only as one of the two registrations. Always disconnect first: a cached token from
# the other principal is the single most likely way to get a false PASS in this checklist.
#
# Disconnect-OER is NOT enough after a consent change. Connect-OER gets its token from AzAuth, and
# AzAuth keeps ONE static TokenCredential per process (TokenManager.credential) with MSAL's
# in-memory cache behind it. Disconnect-OER clears the module's own state but never that
# credential, so the next Connect-OER for the same client id hands back the SAME app token -- old
# roles claim and all -- for up to an hour. Only Get-AzToken -Force clears it
# (TokenManager.ClearCredential), so Connect-Fr forces a fresh token first, lets Connect-OER reuse
# the new credential, and prints the roles the token actually carries. Read that line before every
# route-dependent check: if the withheld permission is in it, the check that follows proves nothing.
function Connect-Fr {
    param([ValidateSet('Full', 'Narrow')][string]$As)
    Disconnect-OER -ErrorAction SilentlyContinue
    $ClientId = if ($As -eq 'Full') { '00000000-0000-0000-0000-000000000003' } else { '00000000-0000-0000-0000-000000000004' }   # Omnicit Entra RBAC / Omnicit Entra RBAC Dev
    $Secret   = Read-Host -Prompt "Client secret for $As" -AsSecureString
    $Plain    = [System.Net.NetworkCredential]::new('', $Secret).Password
    try {
        $Tok = Get-AzToken -Tenant $Tenant -ClientId $ClientId -ClientSecret $Plain -Resource 'https://graph.microsoft.com' -Force
    } finally { $Plain = $null }
    Connect-OER -TenantId $Tenant -ClientId $ClientId -ClientSecret $Secret
    $Payload = ($Tok.Token -split '\.')[1].Replace('-', '+').Replace('_', '/')
    $Payload += '=' * ((4 - $Payload.Length % 4) % 4)
    $Roles = @(([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload)) | ConvertFrom-Json).roles | Sort-Object)
    'Token roles ({0}, {1}): {2}' -f $As, $Roles.Count, ($Roles -join ', ')
}

# Presence, not truthiness. $null.PSObject.Properties.Name -contains 'X' is $false too, so always
# assert the object exists FIRST -- otherwise "the property is absent" also passes on "the cmdlet
# returned nothing at all", which is a different bug entirely.
function Test-FrProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return 'NO OBJECT AT ALL -- this is not the absence you are testing for' }
    '{0}: object present (Id {1}), property {2} present = {3}' -f `
        $Object.DisplayName, $Object.Id, $Name, ($Object.PSObject.Properties.Name -contains $Name)
}

# Every published error record, with the id and the message that carries the CAUSE.
function Show-FrError {
    param($ErrorRecords)
    @($ErrorRecords) | Where-Object { $null -ne $_ } |
        Select-Object @{ n = 'ErrorId';  e = { $_.FullyQualifiedErrorId } },
                      @{ n = 'Category'; e = { $_.CategoryInfo.Category } },
                      @{ n = 'Target';   e = { [string]$_.TargetObject } },
                      @{ n = 'Message';  e = { $_.Exception.Message } } |
        Format-List
}
```

`-ErrorVariable` on a live call carries only real records, so `$Err[0].FullyQualifiedErrorId` can be
read directly. (The `$Published`-filter idiom in the unit tests exists only to strip Pester's own
mock-invocation bookkeeping and has no live equivalent.)

---

### 1. `Get-OERGroup` -- a failed collection read omits the property (checks 1.x)

Route A for eligibility; route D for members and owners. Run 1.2, 1.3 and 1.9 whatever else you
skip: they are the controls, and a fix that broke them would be worse than the defect it closes.

- [x] **1.1 Establish what Graph actually answers for a hidden-membership member read (route D).** -- 2026-09-02

  ```powershell
  Connect-Fr -As Narrow   # Group.Read.All, NOT Member.Read.Hidden
  $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorVariable Err
  Test-FrProperty -Object $G -Name 'Members'
  Show-FrError -ErrorRecords $Err
  ```

  **Record:** whether the read was DENIED (an error record appears, `Members` absent) or merely came
  back EMPTY (no error, `Members` present with count 0). This decides whether route D is usable at
  all on this tenant. If it came back empty, write that here, tick nothing that depends on route D,
  and answer section 1 from route A and sections 3-4 from route B.

  *Record (2026-09-02): the read SUCCEEDED -- `Members` present, no error record. That is not a
  Graph finding. `oer-fr-narrow` still held `Member.Read.Hidden` when this ran, so the caller was
  authorized and route D was never narrowed. What Graph answers an UNAUTHORIZED caller on a
  hidden-membership `/members` read is therefore still unknown, and every route D check below is
  unrun rather than failed. Re-run after an actual consent switch.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow # Group.Read.All, NOT Member.Read.Hidden  
Client secret for Narrow: ****************************************  
> $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorVariable Err  
> Test-FrProperty -Object $G -Name 'Members'  
oer-fr-hidden: object present (Id 00000000-0000-0000-0000-000000000022), property Members present = True  
> Show-FrError -ErrorRecords $Err
  ```


- [x] **1.2 CONTROL -- full consent, members present and correct.** -- 2026-09-02

  ```powershell
  Connect-Fr -As Full
  $G = Get-OERGroup -Group 'oer-fr-grp' -IncludeMembers -IncludeOwners -IncludePimEligibility -ErrorVariable Err
  Test-FrProperty -Object $G -Name 'Members'
  @($G.Members).Count
  @($Err).Count
  ```

  **Expect:** `Members` present, count equal to the number of members you actually created, zero
  errors. **Failure looks like:** any error at all, or a count that does not match the portal.
  **Result:**
  ```powershell
> $G = Get-OERGroup -Group 'oer-fr-grp' -IncludeMembers -IncludeOwners -IncludePimEligibility -ErrorVariable Err
> Test-FrProperty -Object $G -Name 'Members'
oer-fr-grp: object present (Id 00000000-0000-0000-0000-000000000006), property Members present = True
> @($G.Members).Count
2
> @($Err).Count
0
  ```


- [x] **1.3 CONTROL -- a group that genuinely has no members still reports `Members` present, count 0.** -- 2026-09-02

  This is the case the fix must NOT break. An empty collection has to keep meaning "there are none".

  ```powershell
  $E = Get-OERGroup -Group 'oer-fr-empty' -IncludeMembers -IncludeOwners -ErrorVariable Err
  Test-FrProperty -Object $E -Name 'Members'
  @($E.Members).Count
  @($E.Owners).Count
  @($Err).Count
  ```

  **Expect:** `Members` present = `True`, count `0`; `Owners` present = `True`, count `0`; zero
  errors. **Failure looks like:** the property absent, or an error -- the fix has over-corrected and
  "there are none" is now indistinguishable from "could not read" in the other direction.
  **Result:**
  ```powershell
> $E = Get-OERGroup -Group 'oer-fr-empty' -IncludeMembers -IncludeOwners -ErrorVariable Err  
> Test-FrProperty -Object $E -Name 'Members'  
oer-fr-empty: object present (Id 00000000-0000-0000-0000-000000000007), property Members present = True  
> @($E.Members).Count  
0  
> @($E.Owners).Count  
0  
> @($Err).Count  
0
  ```

- [ ] **1.4 A failed member read omits `Members` and writes an error (route D).**

  *STILL UNRUN (2026-09-03). The result below carries no `Token roles` line, so nothing shows route
  D was in force, and it prints `Members present = True` with an empty error id -- the same
  authorized read as 2026-09-02, not the denied read the Expect is written against.*

  Skip if 1.1 recorded "came back empty".

  ```powershell
  Connect-Fr -As Narrow
  $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorVariable Err
  Test-FrProperty -Object $G -Name 'Members'
  @($Err)[0].FullyQualifiedErrorId
  ```

  **Expect:** the object IS returned (`Id` and `DisplayName` printed) and `Members` present =
  `False`; `FullyQualifiedErrorId` matches `GroupMemberReadFailed`.
  **Failure looks like:** `Members` present with count 0 (the old behaviour), or no object at all --
  a different bug, in which the whole group read died rather than just the collection.

  *UNRUN (2026-09-02): could not be provoked -- `oer-fr-narrow` still held `Member.Read.Hidden`, the
  permission route D withholds, so the read the check needs to fail succeeded instead. The output
  below is the evidence that the route was not narrowed, not a module result. Must be re-run after
  an actual consent switch.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
> $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorVariable Err  
> Test-FrProperty -Object $G -Name 'Members'  
oer-fr-hidden: object present (Id 00000000-0000-0000-0000-000000000022), property Members present = True  
> @($Err)[0].FullyQualifiedErrorId  
>
  ```

- [ ] **1.5 It is an ERROR, not a warning.**

  *STILL UNRUN (2026-09-03). No `Token roles` line, and the output is `0` errors and `0` warnings --
  an authorized read with nothing to classify, which the Expect explicitly is not.*

  ```powershell
  $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorVariable Err -WarningVariable Warn
  @($Err).Count
  @($Warn).Count
  ```

  **Expect:** at least one error record, and ZERO warnings. The old code wrote
  `Could not read members for group ...` as a warning, which left `$?` true and `-ErrorAction Stop`
  inert. **Failure looks like:** a warning instead of, or in addition to, the error.

  *UNRUN (2026-09-02): could not be provoked -- `oer-fr-narrow` still held `Member.Read.Hidden`, the
  permission route D withholds, so the read succeeded and there was nothing to classify. Zero errors
  and zero warnings is what an authorized read looks like, not a result for this check. Must be
  re-run after an actual consent switch.*
  **Result:**
  ```powershell
> $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorVariable Err -WarningVariable Warn  
> @($Err).Count  
0  
> @($Warn).Count  
0  
>
  ```

- [ ] **1.6 `-ErrorAction Stop` now stops.**

  *STILL UNRUN (2026-09-03). No `Token roles` line, and the output literally prints `DID NOT STOP`
  where the Expect is `STOPPED: GroupMemberReadFailed...` -- the read succeeded, so there was
  nothing for `-ErrorAction Stop` to stop on.*

  ```powershell
  try { Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorAction Stop; 'DID NOT STOP' }
  catch { "STOPPED: $($_.FullyQualifiedErrorId)" }
  ```

  **Expect:** `STOPPED: GroupMemberReadFailed...`. This is the consumer-visible behaviour change the
  release note calls out: a script under `$ErrorActionPreference = 'Stop'` now stops here where it
  used to continue with an empty collection.

  *UNRUN (2026-09-02): could not be provoked -- `oer-fr-narrow` still held `Member.Read.Hidden`, the
  permission route D withholds. `DID NOT STOP` is the correct answer for a read that SUCCEEDED, so
  it says nothing about the guard. Must be re-run after an actual consent switch. The equivalent
  proof on route B, check 2.6, did stop.*
  **Result:**
  ```powershell
> try { Get-OERGroup -Group 'oer-fr-hidden' -IncludeMembers -ErrorAction Stop; 'DID NOT STOP' }  
> catch { "STOPPED: $($_.FullyQualifiedErrorId)" }  
  
DisplayName GroupType Id  
----------- --------- --  
oer-fr-hidden Regular 00000000-0000-0000-0000-000000000022  
DID NOT STOP  
  
>
  ```

- [ ] **1.7 A failed owner read omits `Owners` (route D).**

  *STILL UNRUN (2026-09-03). No `Token roles` line, and the output is `Owners present = True` with
  an empty error id -- an authorized owner read, which answers neither the Expect nor the Record.*

  ```powershell
  $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeOwners -ErrorVariable Err
  Test-FrProperty -Object $G -Name 'Owners'
  @($Err)[0].FullyQualifiedErrorId
  ```

  **Expect:** object present, `Owners` present = `False`, error id matches `GroupOwnerReadFailed`.
  **Record** if the owners read SUCCEEDS where the members read failed -- the owners of a
  hidden-membership group may not themselves be hidden, in which case this check is answered
  "cannot be provoked by route D" and the owner path stays unproven live.

  *UNRUN (2026-09-02): could not be provoked -- `oer-fr-narrow` still held `Member.Read.Hidden`, the
  permission route D withholds, so `Owners present = True` records an authorized read and not the
  owner-specific question this check asks. Must be re-run after an actual consent switch. The owner
  path has no live proof on this branch.*
  **Result:**
  ```powershell
> $G = Get-OERGroup -Group 'oer-fr-hidden' -IncludeOwners -ErrorVariable Err  
> Test-FrProperty -Object $G -Name 'Owners'  
oer-fr-hidden: object present (Id 00000000-0000-0000-0000-000000000022), property Owners present = True  
> @($Err)[0].FullyQualifiedErrorId  
>
  ```

- [ ] **1.8 A failed PIM eligibility read omits `PimEligibility`, and costs nothing else (route A).**

  Re-consent `oer-fr-narrow` to the route A row of the setup table -- withhold BOTH
  `PrivilegedEligibilitySchedule.Read.AzureADGroup` and
  `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup`, and nothing else -- then reconnect. No
  `Directory.*` scope satisfies these endpoints, so no further denial is needed here.

  ```powershell
  Connect-Fr -As Narrow
  $G = Get-OERGroup -Group 'oer-fr-grp' -IncludeMembers -IncludePimEligibility -ErrorVariable Err
  Test-FrProperty -Object $G -Name 'Members'
  Test-FrProperty -Object $G -Name 'PimEligibility'
  @($Err)[0].FullyQualifiedErrorId
  ```

  **Expect:** `Members` present = `True` with the right count (that read succeeded and must be
  unaffected), `PimEligibility` present = `False`, error id matches `GroupPimEligibilityReadFailed`.
  The collections are independent: one failing must not cost the others.
  **Failure looks like:** `Members` absent too -- a failure in one collection is aborting the whole
  object.

  *UNRUN (2026-09-02): could not be provoked -- `oer-fr-narrow` still held BOTH
  `PrivilegedEligibilitySchedule.Read.AzureADGroup` and
  `PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup`, the two permissions route A withholds, so
  the eligibility read succeeded and `PimEligibility present = True` is the correct answer for an
  authorized caller. Must be re-run after an actual consent switch.*

  *NOT PROVOKED ON `oer-fr-grp` (2026-09-03) -- but route A DOES work, and this file proves it a few
  checks further down. Re-run with the consent switch actually in force
  and verified two ways: the service principal's appRoleAssignments held neither
  `PrivilegedEligibilitySchedule.*` role (15 of 17), and the `roles` claim of the token
  `Connect-Fr` acquired with `Get-AzToken -Force` listed the same 15, so neither the earlier
  consent defect nor AzAuth's in-process token cache applies here. The read STILL succeeded:
  `PimEligibility present = True`, `$Err` empty. A raw GET of
  `beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?$filter=groupId eq
  '``<id>`` with that same token answered **200 with an empty `value`** -- not 403
  `Authorization_RequestDenied`, and not 400 `ResourceTypeNotSupported` either, so the module's
  non-onboarded carve-out (`Get-OERGroup.ps1:193`) is not what swallowed it. The group was then
  onboarded to PIM for Groups (`Add-OERGroupEligibility` as `oer-fr-full`, one member eligibility
  for person2, request `Provisioned`) to rule out a "nothing to authorize" answer, and the narrow
  read succeeded again, unchanged.*

  *Conclusion (corrected on the evidence in 3.13). **Route A works. `oer-fr-grp` is simply the wrong
  group to run it against.** Under the very same 15-role token, check 3.13's `Get-OERInventory` run
  printed `Unread: groups/<name>/eligibility` for TEN groups, each with
  `Causes: Could not read PIM eligibility for group <id>: ... PermissionScopeNotGranted ...
  PrivilegedEligibilitySchedule.Read.AzureADGroup ...`. That message is written only by
  `Get-OERGroup.ps1:198`, with `-ErrorId 'GroupPimEligibilityReadFailed'`, and that
  `section/displayName/key` triple is added only at `Get-OERInventory.ps1:402`, in the `else` branch
  reached only when the `PimEligibility` property was OMITTED -- and `Get-OERInventory` always asks
  for it (`Get-OERInventory.ps1:217`). So both halves of this branch's contract are live-proven on
  route A: Graph DOES refuse the endpoint to an app lacking both PES scopes, the module writes
  `GroupPimEligibilityReadFailed`, and the property is omitted rather than reported empty.*

  *What is still unexplained is narrower and is a Graph question, not a module one: why the same
  token gets a 200 with an empty `value` for `oer-fr-grp` while it gets
  `PermissionScopeNotGranted` for those ten. The ten are PIM-onboarded, role-assignable groups;
  `oer-fr-grp` was onboarded during this check and still answered 200. Determining what separates
  them is follow-up work.*

  *This box nevertheless stays UNTICKED, because the commands IN it were run against the wrong
  group: its own output reads `PimEligibility present = True` with an empty error id, and the
  "`Members` present, the collections are independent" half has no output from a group whose
  eligibility read actually failed. To close it, re-run exactly these four lines against one of the
  ten groups 3.13 names. Section 0's "route A is the CLEANEST" claim and section 7's item 1b are
  corrected accordingly.*

  *Tenant state after this check: `oer-fr-grp` now carries a member eligibility for person2 and
  its member policy was opened for permanent eligibility (`Add-OERGroupEligibility` warned so).
  T.1 removes the eligibility; the policy setting is restored by T.1's pimPolicy step only if
  `-RestoreWrites` is extended to it -- record what `Get-OERGroupPimPolicy` shows.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow
Client secret for Narrow: ****************************************
Token roles (Narrow, 15): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $G = Get-OERGroup -Group 'oer-fr-grp' -IncludeMembers -IncludePimEligibility -ErrorVariable Err
> Test-FrProperty -Object $G -Name 'Members'
oer-fr-grp: object present (Id 00000000-0000-0000-0000-000000000006), property Members present = True
> Test-FrProperty -Object $G -Name 'PimEligibility'
oer-fr-grp: object present (Id 00000000-0000-0000-0000-000000000006), property PimEligibility present = True
> @($Err)[0].FullyQualifiedErrorId

> try { Invoke-MgGraphRequest -Method GET -Uri "beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=groupId eq '00000000-0000-0000-0000-000000000006'" -OutputType PSObject } catch { $_.Exception.Message; $_.ErrorDetails.Message }

@odata.context                                                                                                    value
--------------                                                                                                    -----
https://graph.microsoft.com/beta/$metadata#identityGovernance/privilegedAccess/group/eligibilityScheduleInstances {}

> Connect-Fr -As Full
Token roles (Full, 17): ... PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup ...
> Add-OERGroupEligibility -Group 'oer-fr-grp' -User 'person2@example.com' -AccessType member
WARNING: This eligibility requires opening the PIM-for-groups policy for group '00000000-0000-0000-0000-000000000006' (member access) to allow PERMANENT eligible assignments, which affects ALL member eligibility for this group.

GroupId                              PrincipalId                          AccessType Action      Status      RequestId
-------                              -----------                          ---------- ------      ------      ---------
00000000-0000-0000-0000-000000000006 <person2-object-id>                  member     adminAssign Provisioned <redacted>

> Connect-Fr -As Narrow    # route A
Token roles (Narrow, 15): (same 15 as above, no PrivilegedEligibilitySchedule.*)
> $G = Get-OERGroup -Group 'oer-fr-grp' -IncludeMembers -IncludePimEligibility -ErrorVariable Err
> Test-FrProperty -Object $G -Name 'Members'
oer-fr-grp: object present (Id 00000000-0000-0000-0000-000000000006), property Members present = True
> Test-FrProperty -Object $G -Name 'PimEligibility'
oer-fr-grp: object present (Id 00000000-0000-0000-0000-000000000006), property PimEligibility present = True
> @($Err)[0].FullyQualifiedErrorId

  ```

  Still to record before this box is closed out: the four lines above, re-run against one of the ten
  groups check 3.13 names as unread. `@($G.PimEligibility).Count` on `oer-fr-grp` under narrow is
  worth having alongside it -- it separates "an undocumented permission satisfies the endpoint for
  this group" from "Graph filters to empty rather than refusing" -- but it is not what closes the
  box.

- [x] **1.9 CONTROL -- a group not onboarded to PIM for Groups is NOT a failure.** -- 2026-09-02

  Run with FULL consent against a group that has never been PIM-enabled.

  ```powershell
  Connect-Fr -As Full
  $E = Get-OERGroup -Group 'oer-fr-empty' -IncludePimEligibility -ErrorVariable Err -WarningVariable Warn
  Test-FrProperty -Object $E -Name 'PimEligibility'
  @($E.PimEligibility).Count
  @($Err).Count; @($Warn).Count
  ```

  **Expect:** `PimEligibility` present = `True`, count `0`, zero errors, zero warnings. Graph answers
  `ResourceTypeNotSupported` for a group that was never onboarded, and that is a read that
  SUCCEEDED: the group genuinely has no eligibility. This carve-out is load-bearing and is the one
  place an error would be wrong. **Failure looks like:** an error, or the property absent -- every
  non-PIM group in the tenant would then raise `InventoryPartial` on every export.
  **Result:**
  ```powershell
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
> $E = Get-OERGroup -Group 'oer-fr-empty' -IncludePimEligibility -ErrorVariable Err -WarningVariable Warn  
> Test-FrProperty -Object $E -Name 'PimEligibility'  
oer-fr-empty: object present (Id 00000000-0000-0000-0000-000000000007), property PimEligibility present = True  
> @($E.PimEligibility).Count  
0  
> @($Err).Count; @($Warn).Count  
0  
0
  ```

---

### 2. `Get-OERAdministrativeUnit` -- the same contract (checks 2.x)

Route B for scoped roles; route C for members.

- [x] **2.1 Establish what Graph answers for a hidden-membership AU member read (route C).** -- 2026-09-03

  Use `oer-fr-au-c`, the unit the setup creates HIDDEN. `visibility` cannot be added to an existing
  administrative unit -- see section 0 -- so a unit created without it can never be used here.

  ```powershell
  Connect-Fr -As Full
  # The unit must be CREATED hidden. Graph rejects Set-OERAdministrativeUnit -Visibility
  # HiddenMembership on an existing unit with
  # 'Request_BadRequest: HiddenMembership can only be set during administrative unit creation.'
  New-OERAdministrativeUnit -DisplayName 'oer-fr-au-c' -HiddenMembership
  Add-OERAdministrativeUnitMember -AdministrativeUnit 'oer-fr-au-c' -User 'person4@example.com'
  Connect-Fr -As Narrow    # AdministrativeUnit.Read.All, NOT Member.Read.Hidden
  $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-c' -IncludeMembers -ErrorVariable Err
  Test-FrProperty -Object $A -Name 'Members'
  Show-FrError -ErrorRecords $Err
  ```

  **Record:** denied, or empty? Same decision as check 1.1. If empty, route C is unusable and
  check 2.4 is answered from it.

  *UNRUN (2026-09-02): the run used `oer-fr-au-b`, an existing unit, and tried to make it hidden
  afterwards. Graph refused -- the output below is that refusal -- so no hidden-membership unit
  existed and the members read that followed was an ordinary authorized read. Two things must change
  before this is re-run: the unit has to be CREATED hidden (fixed above), and `oer-fr-narrow` has to
  actually lose `Member.Read.Hidden`, which it still held. This is a checklist defect, not a module
  one.*

  *Record (2026-09-03), and this is the answer the check asks for: **EMPTY, not denied -- so route C
  is unusable on this tenant.** Both defects were fixed first. `oer-fr-au-c` was created hidden
  (`New-OERAdministrativeUnit -HiddenMembership` succeeded) and the narrow token verifiably lacked
  `Member.Read.Hidden` (`Token roles (Narrow, 16)`, against `Token roles (Full, 17)` which has it).
  The members read then returned `Members present = True` with no error record at all. Per this
  check's own instruction, 2.4 is answered from it and stays unticked, and
  `AdministrativeUnitMemberReadFailed` has no live proof -- see section 7.2b.*
  **Result:**
  ```powershell
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
Token roles (Full, 17): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> # The unit must be CREATED hidden. Graph rejects Set-OERAdministrativeUnit -Visibility  
> # HiddenMembership on an existing unit with  
> # 'Request_BadRequest: HiddenMembership can only be set during administrative unit creation.'  
> New-OERAdministrativeUnit -DisplayName 'oer-fr-au-c' -HiddenMembership  
  
DisplayName MembershipType IsMemberManagementRestricted Id  
----------- -------------- ---------------------------- --  
oer-fr-au-c Assigned False 00000000-0000-0000-0000-000000000023  
  
> Add-OERAdministrativeUnitMember -AdministrativeUnit 'oer-fr-au-c' -User 'person4@example.com'  
> Connect-Fr -As Narrow # AdministrativeUnit.Read.All, NOT Member.Read.Hidden  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 16): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-c' -IncludeMembers -ErrorVariable Err  
> Test-FrProperty -Object $A -Name 'Members'  
oer-fr-au-c: object present (Id 00000000-0000-0000-0000-000000000023), property Members present = True  
> Show-FrError -ErrorRecords $Err
  ```

- [x] **2.2 CONTROL -- full consent, members and scoped roles present and correct.** -- 2026-09-02

  ```powershell
  Connect-Fr -As Full
  $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeMembers -IncludeScopedRoles -ErrorVariable Err
  Test-FrProperty -Object $A -Name 'Members'
  Test-FrProperty -Object $A -Name 'ScopedRoles'
  @($A.Members).Count; @($A.ScopedRoles).Count; @($Err).Count
  ```

  **Expect:** both present, counts matching the portal, zero errors. **Result:**
  ```powershell
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
> $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeMembers -IncludeScopedRoles -ErrorVariable Err  
> Test-FrProperty -Object $A -Name 'Members'  
oer-fr-au: object present (Id 00000000-0000-0000-0000-000000000009), property Members present = True  
> Test-FrProperty -Object $A -Name 'ScopedRoles'  
oer-fr-au: object present (Id 00000000-0000-0000-0000-000000000009), property ScopedRoles present = True  
> @($A.Members).Count; @($A.ScopedRoles).Count; @($Err).Count  
1  
1  
0
  ```

- [x] **2.3 CONTROL -- an AU with no scoped role still reports `ScopedRoles` present, count 0.** -- 2026-09-02

  ```powershell
  $B = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-b' -IncludeScopedRoles -ErrorVariable Err
  Test-FrProperty -Object $B -Name 'ScopedRoles'
  @($B.ScopedRoles).Count; @($Err).Count
  ```

  **Expect:** present = `True`, count `0`, zero errors. **Result:**
  ```powershell
> $B = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-b' -IncludeScopedRoles -ErrorVariable Err   
> Test-FrProperty -Object $B -Name 'ScopedRoles'  
oer-fr-au-b: object present (Id 00000000-0000-0000-0000-000000000008), property ScopedRoles present = True  
> @($B.ScopedRoles).Count; @($Err).Count  
0  
0
  ```

- [ ] **2.4 A failed member read omits `Members` (route C).**

  *NOT A PASS (2026-09-03). Route C WAS in force this time -- `Token roles (Narrow, 16)` with
  `Member.Read.Hidden` absent -- and the unit was genuinely created hidden, yet the output reads
  `oer-fr-au-c: ... Members present = True` with a blank error id. The Expect is `False` plus
  `AdministrativeUnitMemberReadFailed`. Graph answered the members of a hidden-membership unit to a
  caller without `Member.Read.Hidden`, so route C provokes nothing on this tenant -- see 2.1 and
  section 7.2b.*

  ```powershell
  Connect-Fr -As Narrow
  $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-c' -IncludeMembers -ErrorVariable Err
  Test-FrProperty -Object $A -Name 'Members'
  @($Err)[0].FullyQualifiedErrorId
  ```

  **Expect:** object present, `Members` present = `False`, error id matches
  `AdministrativeUnitMemberReadFailed`.

  *UNRUN (2026-09-02): could not be provoked -- two reasons, either of which is fatal on its own.
  `oer-fr-narrow` still held `Member.Read.Hidden`, the permission route C withholds; and the unit
  under test was never hidden at all, since check 2.1's setup step was rejected by Graph. The output
  below records an ordinary authorized members read. Must be re-run against `oer-fr-au-c` after an
  actual consent switch.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 16): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-c' -IncludeMembers -ErrorVariable Err  
> Test-FrProperty -Object $A -Name 'Members'  
oer-fr-au-c: object present (Id 00000000-0000-0000-0000-000000000023), property Members present = True  
> @($Err)[0].FullyQualifiedErrorId  
>
  ```

- [x] **2.5 A failed scoped-role read omits `ScopedRoles` (route B) -- the primary provocation.** -- 2026-09-02

  Re-consent `oer-fr-narrow` to the route B row of the setup table -- withhold ALL of
  `RoleManagement.Read.Directory`, `RoleManagement.ReadWrite.Directory`, `Directory.Read.All` and
  `Directory.ReadWrite.All`. **Withholding only `RoleManagement.Read.Directory` is not enough:**
  `Directory.Read.All` is a documented higher-privileged alternative for this endpoint and is in the
  set `Get-OERRequiredScope -Unique` reports, so leaving it consented makes this read return 200 and
  makes the check below look like a regression when nothing is wrong. Reconnect, then:

  ```powershell
  Connect-Fr -As Narrow
  $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeMembers -IncludeScopedRoles -ErrorVariable Err
  Test-FrProperty -Object $A -Name 'Members'
  Test-FrProperty -Object $A -Name 'ScopedRoles'
  @($Err)[0].FullyQualifiedErrorId
  ```

  **Expect:** `Members` present = `True` with the right count, `ScopedRoles` present = `False`,
  error id matches `AdministrativeUnitScopedRoleReadFailed`. **This is the state sections 3 and 4
  build on -- do not proceed past it until it reads as expected.**
  **Failure looks like:** `ScopedRoles` present with count 0 (old behaviour), or `Members` absent
  too.

  *Record (2026-09-02): the headline holds -- `Members present = True`, `ScopedRoles present =
  False`, and the cmdlet wrote `Could not read scoped roles for administrative unit ...:
  Authorization_RequestDenied ... The ScopedRoles property is omitted rather than reported as
  empty.` Two steps of this check were NOT run: `@($Err)[0].FullyQualifiedErrorId` printed nothing,
  so the error id was never confirmed HERE (check 2.6 confirms it separately as
  `AdministrativeUnitScopedRoleReadFailed,Get-OERAdministrativeUnit`), and the `Members` COUNT was
  never printed, so "with the right count" is unverified. Route B is the only route this run
  actually narrowed.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 14): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeMembers -IncludeScopedRoles -ErrorVariable Err  
Get-OERAdministrativeUnit: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.
> Test-FrProperty -Object $A -Name 'Members'  
oer-fr-au: object present (Id 00000000-0000-0000-0000-000000000009), property Members present = True  
> Test-FrProperty -Object $A -Name 'ScopedRoles'  
oer-fr-au: object present (Id 00000000-0000-0000-0000-000000000009), property ScopedRoles present = False  
> @($Err)[0].FullyQualifiedErrorId  
>

  ```

- [x] **2.6 It is an ERROR, not a warning, and `-ErrorAction Stop` stops.** -- 2026-09-02

  ```powershell
  $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles -ErrorVariable Err -WarningVariable Warn
  @($Err).Count; @($Warn).Count
  try { Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles -ErrorAction Stop; 'DID NOT STOP' }
  catch { "STOPPED: $($_.FullyQualifiedErrorId)" }
  ```

  **Expect:** at least one error, zero warnings, and
  `STOPPED: AdministrativeUnitScopedRoleReadFailed...`.

  *Record (2026-09-02): both halves hold -- zero warnings, and
  `STOPPED: AdministrativeUnitScopedRoleReadFailed,Get-OERAdministrativeUnit`. But `@($Err).Count`
  was **9**, not 1, for a single failed read. Eight of those nine are foreign records the module
  never published, and one of them renders a plain-text bearer token; check 2.7 shows all nine and
  check 2.8 is the guard that should have caught it. The "at least one error" the Expect asks for is
  met, so this box stands; the surplus is a separate defect, not a failure of this check.*
  **Result:**
  ```powershell
> $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles -ErrorVariable Err -WarningVariable Warn
Get-OERAdministrativeUnit: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.
> @($Err).Count; @($Warn).Count  
9  
0  
> try { Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles -ErrorAction Stop; 'DID NOT STOP' }  
> catch { "STOPPED: $($_.FullyQualifiedErrorId)" }  
STOPPED: AdministrativeUnitScopedRoleReadFailed,Get-OERAdministrativeUnit
  ```

- [x] **2.7 The error record names the AU, and its message carries the transport reason.** -- 2026-09-02

  ```powershell
  Show-FrError -ErrorRecords $Err
  ```

  Graph text (for route B, an authorization / insufficient-privileges message). This message is the
  only place the CAUSE lives once the record is consolidated by `Get-OERInventory` in section 3, so
  transcribe it -- redacted -- on the result line.

Record (2026-09-02): the Expect is MET. The module's own record -- the last of the nine, id
  `AdministrativeUnitScopedRoleReadFailed,Get-OERAdministrativeUnit` -- carries `Target` = the
  administrative unit's object id and a `Message` reading `Could not read scoped roles for
  administrative unit `<id>`: Authorization_RequestDenied: Insufficient privileges to complete the
  operation.. The ScopedRoles property is omitted rather than reported as empty. This box is
  ticked on that.

  The check also exposed something its `Expect` never asked about, which is why the output below is
  kept in full. **Eight FOREIGN records accompany the module's own** in the caller's
  `-ErrorVariable`: two entirely empty, one `InvokeGraphHttpResponseException` whose `TargetObject`
  is the raw `HttpRequestMessage` -- rendering `Authorization: Bearer <token>` in plain text -- one
  `InvalidOperationException: ... "The given header was not found."`, and four bare
  `Authorization_RequestDenied`. The token has been redacted here; the surrounding record structure
  is left intact because that SHAPE is the evidence. `-ErrorVariable` is filled by the engine from
  the error stream and captures records from nested calls even where an inner catch swallowed them,
  and `Remove-OERErrorRecord` only removes one entry from `$global:Error` by exception identity --
  it never touches the caller's `-ErrorVariable`. **Check 2.8 below is the check that would have
  caught this**, and it is the one to run once the fix lands.
  
  **Result:**

  ```powershell
  Show-FrError -ErrorRecords $Err  
    
  ErrorId :  
  Category :  
  Target :  
  Message :  
    
  ErrorId : InvokeGraphHttpResponseException,Microsoft.Graph.PowerShell.Authentication.Cmdlets.InvokeMgGraphRequest  
  Category : InvalidOperation  
  Target : Method: GET, RequestUri: 'https://graph.microsoft.com/v1.0/directory/administrativeUnits/00000000-0000-0000-0000-000000000009/scopedRoleMembers', Version: 2.0, Content: <null>, Headers:  
  {  
  User-Agent: Mozilla/5.0 (Windows NT 10.0; Microsoft Windows 10.0.26100; sv-SE) PowerShell/7.6.5 Invoke-MgGraphRequest  
  FeatureFlag: 00000003  
  Cache-Control: no-store, no-cache  
  Authorization: Bearer <bearer-token-REDACTED>  
  SdkVersion: graph-powershell/2.37.0  
  client-request-id: 00000000-0000-0000-0000-000000000010  
  Accept-Encoding: gzip, deflate, br  
  }  
  Message : Response status code does not indicate success: Forbidden (Forbidden).  
    
  ErrorId : InvalidOperationException  
  Category : NotSpecified  
  Target :  
  Message : Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
    
  ErrorId : Authorization_RequestDenied  
  Category : OperationStopped  
  Target :  
  Message : Authorization_RequestDenied: Insufficient privileges to complete the operation.  
    
  ErrorId : Authorization_RequestDenied  
  Category : OperationStopped  
  Target :  
  Message : Authorization_RequestDenied: Insufficient privileges to complete the operation.  
    
  ErrorId : Authorization_RequestDenied  
  Category : OperationStopped  
  Target :  
  Message : Authorization_RequestDenied: Insufficient privileges to complete the operation.  
    
  ErrorId :  
  Category :  
  Target :  
  Message :  
    
  ErrorId : Authorization_RequestDenied  
  Category : OperationStopped  
  Target :  
  Message : Authorization_RequestDenied: Insufficient privileges to complete the operation.  
    
  ErrorId : AdministrativeUnitScopedRoleReadFailed,Get-OERAdministrativeUnit  
  Category : ReadError  
  Target : 00000000-0000-0000-0000-000000000009  
  Message : Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property i  
  s omitted rather than reported as empty.
  
  ```

- [x] **2.8 NO record reachable from a failed read renders a bearer token.** -- 2026-09-03

  *Record (2026-09-03): PASSED on route B (`Token roles (Narrow, 14)`, `RoleManagement.*` and
  `Directory.*` absent, the scoped-role read denied). `ErrorVariable: 9 record(s), 0 rendering a
  token` and `global:Error: 1 record(s), 0 rendering a token` -- zero for both collections, which is
  the Expect exactly. This is the live proof of this branch's security fix: 2.7 recorded the same
  nine records BEFORE it, one of which rendered `Authorization: Bearer <jwt>` in full. The surplus
  count of nine is unchanged and remains the separate finding 2.6 records.*

  **This is the check that would have caught the leak check 2.7 exposed, and it did not exist when
  this run happened.** It writes nothing and reads nothing new -- it inspects the records the
  preceding check already produced -- so it is safe to run at any point after 2.5, and it needs no
  consent change. Run it on route B.

  A failed Graph read leaves records in TWO separate collections: the caller's `-ErrorVariable`,
  which the ENGINE fills from the error stream (including records from nested calls that an inner
  catch already swallowed), and `$global:Error`. `Remove-OERErrorRecord` acts only on the second.
  Neither collection may contain a rendered token, and the token does not live in a message -- it
  lives on the `HttpRequestMessage` that a record's `TargetObject` points at, which every reference
  to that object shares.

  ```powershell
  Connect-Fr -As Narrow    # route B
  $Global:Error.Clear()
  $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles -ErrorVariable Err

  # Render every record the way a transcript, a log or a CI run would, and look for the header.
  function Test-FrTokenLeak {
      param($Records, [string]$Label)
      $Leaks = @(
          foreach ($Rec in @($Records)) {
              if ($null -eq $Rec) { continue }
              $Rendered = @(
                  [string]$Rec.TargetObject
                  [string]$Rec.Exception
                  [string]$Rec.ErrorDetails
                  ($Rec | Format-List * -Force | Out-String)
              ) -join "`n"
              if ($Rendered -match 'Bearer\s+ey' -or $Rendered -match 'Authorization:\s*\S') { $Rec }
          }
      )
      '{0}: {1} record(s), {2} rendering a token' -f $Label, @($Records).Count, $Leaks.Count
  }

  Test-FrTokenLeak -Records $Err           -Label 'ErrorVariable'
  Test-FrTokenLeak -Records $Global:Error  -Label 'global:Error'
  ```

  **Expect:** `0 rendering a token` for BOTH collections. The record COUNT is deliberately printed
  too but is not what this check asserts -- a surplus of foreign records is a separate finding
  (2.6), whereas one token in one of them is a credential disclosure into every transcript and CI
  log that ever renders the error.
  **Failure looks like:** any non-zero count. Do not paste the offending record into this file to
  show the failure -- record the count and the record's `FullyQualifiedErrorId` only, and treat the
  token as disclosed and in need of ROTATION.
  **Result:**
  ```powershell
> Connect-Fr -As Narrow # route B  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 14): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $Global:Error.Clear()  
> $A = Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles -ErrorVariable Err  
Get-OERAdministrativeUnit: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.
>  
> # Render every record the way a transcript, a log or a CI run would, and look for the header.  
> function Test-FrTokenLeak {  
> param($Records, [string]$Label)  
> $Leaks = @(  
> foreach ($Rec in @($Records)) {  
> if ($null -eq $Rec) { continue }  
> $Rendered = @(  
> [string]$Rec.TargetObject  
> [string]$Rec.Exception  
> [string]$Rec.ErrorDetails  
> ($Rec | Format-List * -Force | Out-String)  
> ) -join "`n"  
> if ($Rendered -match 'Bearer\s+ey' -or $Rendered -match 'Authorization:\s*\S') { $Rec }  
> }  
> )  
> '{0}: {1} record(s), {2} rendering a token' -f $Label, @($Records).Count, $Leaks.Count  
> }  
>  
> Test-FrTokenLeak -Records $Err -Label 'ErrorVariable'  
ErrorVariable: 9 record(s), 0 rendering a token  
> Test-FrTokenLeak -Records $Global:Error -Label 'global:Error'  
global:Error: 1 record(s), 0 rendering a token  
>
  ```

---

### 3. `Get-OERInventory` and `Export-OERInventory` (checks 3.x)

Run this whole section on route B, connected as `oer-fr-narrow` unless a check says otherwise.

- [x] **3.1 A failed scoped-role read projects an explicit `null`, not `[]`.** -- 2026-09-02

  ```powershell
  Connect-Fr -As Narrow
  $Inv  = Get-OERInventory -Include AdministrativeUnits -ErrorVariable Err
  $Unit = $Inv.AdministrativeUnits | Where-Object displayName -eq 'oer-fr-au'
  $Unit.PSObject.Properties.Name -contains 'scopedRoles'   # key PRESENT
  $null -eq $Unit.scopedRoles                              # value is NULL
  $Unit | ConvertTo-Json -Depth 10
  ```

  **Expect:** the key is present AND its value is `$null`; the JSON shows `"scopedRoles": null`.
  **Failure looks like:** `"scopedRoles": []` -- the defect this branch exists to fix, on which
  `-Prune` deletes every live scoped role -- or the key missing entirely, which is just as
  destructive here, since an OMITTED `scopedRoles` key still reconciles and still prunes.

  *Record (2026-09-02): the Expect is MET -- the key is present and the JSON reads
  `"scopedRoles": null`. Separately, the transcript below carries **56**
  `WARNING: Could not read administrative units:` lines for what is one failed read per unit across
  seven units. That is the defect check 3.6 is about; it does not change this check's result.*
  **Result:**

  ```powershell
  > Connect-Fr -As Narrow  
  WARNING: You're using Az version 15.4.0. The latest version of Az is 16.3.0. Upgrade your Az modules using the following commands:  
  Update-PSResource Az -WhatIf -- Simulate updating your Az modules.  
  Update-PSResource Az -- Update your Az modules.  
  There will be breaking changes from 15.4.0 to 16.3.0. Open https://go.microsoft.com/fwlink/?linkid=2241373 and check the details.  
  Client secret for Narrow: ****************************************  
  > $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorVariable Err  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
  WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
  WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
  WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
  WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
  WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
  WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
  WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  WARNING: Could not read administrative units:  
  WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
  Get-OERInventory: This inventory is PARTIAL: 7 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..
  > $Unit = $Inv.AdministrativeUnits | Where-Object displayName -eq 'oer-fr-au'  
  > $Unit.PSObject.Properties.Name -contains 'scopedRoles' # key PRESENT  
  True  
  > $null -eq $Unit.scopedRoles # value is NULL  
  True  
  > $Unit | ConvertTo-Json -Depth 10  
  {  
  "displayName": "oer-fr-au",  
  "description": "oer-fr live verification, route B. Safe to delete.",  
  "restricted": false,  
  "dynamic": false,  
  "hiddenMembership": false,  
  "members": [  
  "00000000-0000-0000-0000-000000000016"  
  ],  
  "scopedRoles": null  
  }
  ```

- [x] **3.2 A read that SUCCEEDED and found nothing still projects an empty array.** -- 2026-09-02

  The two states must stay distinguishable in the DOCUMENT, not only on the object.

  ```powershell
  Connect-Fr -As Full
  $InvFull = Get-OERInventory -Include AdministrativeUnits
  $B = $InvFull.AdministrativeUnits | Where-Object displayName -eq 'oer-fr-au-b'
  $null -eq $B.scopedRoles      # expect False
  @($B.scopedRoles).Count       # expect 0
  ```

  **Expect:** `False` then `0` -- an empty array, not a null. **Result:**
  ```powershell
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
> $InvFull = Get-OERInventory -Include AdministrativeUnits  
> $B = $InvFull.AdministrativeUnits | Where-Object displayName -eq 'oer-fr-au-b'  
> $null -eq $B.scopedRoles # expect False  
False   
> @($B.scopedRoles).Count # expect 0  
0
  ```

- [x] **3.3 `InventoryPartial` is raised, and it names section, object and key.** -- 2026-09-02

  ```powershell
  Connect-Fr -As Narrow
  $Inv = Get-OERInventory -Include Groups, AdministrativeUnits -ErrorVariable Err
  $P = @($Err) | Where-Object FullyQualifiedErrorId -like 'InventoryPartial*'
  @($P).Count
  $P[0].Exception.Message
  [string]$P[0].TargetObject
  ```

  **Expect:** exactly one `InventoryPartial` record; the message opens `This inventory is PARTIAL:`
  and lists `administrativeUnits/oer-fr-au/scopedRoles`; `TargetObject` carries the same triple.

  *Record (2026-09-02): the first two thirds hold -- exactly one `InventoryPartial` record, and the
  message opens `This inventory is PARTIAL: 7 collection(s) could not be read ...` naming
  `administrativeUnits/oer-fr-au/scopedRoles` first. **The `TargetObject` step was never run**: the
  `[string]$P[0].TargetObject` line was interrupted (`^C` in the transcript at the top of 3.4's
  result), so the third assertion is unverified and must be re-run. The transcript also carries
  roughly 72 `Could not read groups:` warnings, from the PIM carve-out that is meant to be silent --
  again the 3.6 defect, not this one.*
  **Result:**
  ```powershell
 > Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
Get-OERInventory: This inventory is PARTIAL: 7 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..
> $P = @($Err) | Where-Object FullyQualifiedErrorId -like 'InventoryPartial*'  
> @($P).Count  
1  
> $P[0].Exception.Message
This inventory is PARTIAL: 7 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..
  ```

- [x] **3.4 The `Causes:` clause distinguishes a 403 from a 429.** -- 2026-09-02

  ```powershell
  $P[0].Exception.Message -match 'Causes: '
  ($P[0].Exception.Message -split 'Causes: ')[1]
  ```

  **Expect:** a `Causes:` clause is present and carries the underlying Graph reason -- for route B,
  an authorization / insufficient-privileges message. This is what tells an operator whether to
  retry the export or grant a scope, and without it `InventoryPartial` names the object but never
  the reason. **Failure looks like:** no `Causes:` clause, or a dangling `Causes: .` with nothing
  after it. **Result:**
  ```powershell
> [string]$P[0].TargetObject^C  
> $P[0].Exception.Message -match 'Causes: '  
True  
> ($P[0].Exception.Message -split 'Causes: ')[1]
Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..
  ```

- [x] **3.5 The cause is deduplicated across objects that failed for the same reason.** -- 2026-09-02

  Assign a scoped role to `oer-fr-au-b` as well, so two units fail the same read, and re-run 3.3.

  ```powershell
  Connect-Fr -As Full
  Add-OERAdministrativeUnitScopedRole -AdministrativeUnit 'oer-fr-au-b' -RoleName 'User Administrator' -User 'person2@example.com'
  Connect-Fr -As Narrow    # route B
  $Inv = Get-OERInventory -Include Groups, AdministrativeUnits -ErrorVariable Err
  $P = @($Err) | Where-Object FullyQualifiedErrorId -like 'InventoryPartial*'
  ($P[0].Exception.Message -split 'Causes: ')[0]     # Unread: both units?
  ($P[0].Exception.Message -split 'Causes: ')[1]     # one cause, or two?
  ```

  **Expect:** BOTH units named in the `Unread:` list, and the identical cause counted ONCE in the
  `Causes:` clause. **Record** the exact clause: if the transport embeds the object id in its
  message, the two causes differ by id and will NOT dedupe. That is a known and accepted limitation,
  not a failure -- say which you saw.

  *Record (2026-09-02): both units are named in `Unread:`, so the first half of the Expect holds.
  The `Causes:` clause did NOT dedupe: **seven distinct causes for seven units**, one per unit. This
  is the second of the two forms the Record anticipated, and it is worse than "may not dedupe" --
  the message interpolates the unit's object id, so every cause string differs by construction and
  the dedupe can never fire for this collection at all. The "very long clause on a large tenant"
  risk in section 7.4 is therefore certain, not hypothetical, for AU scoped roles.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
> $Inv = Get-OERInventory -Include Groups, AdministrativeUnits -ErrorVariable Err
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups:  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Response status code does not indicate success: Forbidden (Forbidden).  
WARNING: Could not read administrative units: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
Get-OERInventory: This inventory is PARTIAL: 7 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..
> $P = @($Err) | Where-Object FullyQualifiedErrorId -like 'InventoryPartial*'  
> @($P).Count  
1  
> $P[0].Exception.Message
This inventory is PARTIAL: 7 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..
> [string]$P[0].TargetObject  
administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles
  ```

- [x] **3.6 The same failure is NOT also re-reported as an opaque section-level warning.** -- 2026-09-03

  ```powershell
  $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorVariable Err -WarningVariable Warn
  @($Warn)
  ```

  **Expect:** no `Could not read administrative units: ...` warning. A per-collection failure is
  accounted for by name in `InventoryPartial`; a second, vaguer report of the same fact is noise.

  *FAILED, and it is a real module defect being fixed on this branch -- so the box is unticked and
  this check must be RE-RUN after the fix, not closed on this result. `@($Warn)` printed **56**
  warnings for seven units. `Get-OERInventory` suppresses only records whose
  `FullyQualifiedErrorId` matches its own ids, and the module's own records carry the cmdlet name as
  the id suffix while the foreign records check 2.7 exposed carry nothing recognisable -- so all
  eight strays per failed read fall through to `Write-Warning`. Seven units times eight strays is
  the 56 observed, and the same mechanism produces the roughly 72 `Could not read groups:` lines in
  3.3 where the PIM carve-out is supposed to be silent. The real signal drowns in the noise.*

  *Record (2026-09-03): RE-RUN after the fix and now PASSED, which is why the box above is ticked.
  `@($Warn)` printed nothing at all -- zero warnings for eight failed scoped-role reads -- while the
  single `InventoryPartial` record still names every one of the eight collections and carries the
  `Causes:` clause. The paragraph above is kept as the record of what the pre-fix behaviour was.*
  **Result:**
  ```powershell
> $Inv = Get-OERInventory -Include AdministrativeUnits -ErrorVariable Err -WarningVariable Warn  
Get-OERInventory: This inventory is PARTIAL: 8 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au-c/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/oer-live-au/scopedRoles, ad  
ministrativeUnits/Testar/scopedRoles, administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles. A members or scopedRoles key reported here is an explicit n  
ull, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000023: Authorization_Request  
Denied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..
> @($Warn)  
>
  ```

- [x] **3.7 One failed collection costs one collection, not the rest of the section.** -- 2026-09-02

  ```powershell
  @($Inv.AdministrativeUnits).Count
  $Inv.AdministrativeUnits | Select-Object displayName, @{ n = 'members'; e = { @($_.members).Count } }
  ```

  **Expect:** every administrative unit in the tenant is still present in the document, and the
  units whose `members` read succeeded still carry their members. A per-object collection failure
  must not abort the enumeration. **Failure looks like:** a short list, or an empty section -- the
  read is still running under `-ErrorAction Stop` somewhere.
  **Result:**
  ```powershell
> @($Inv.AdministrativeUnits).Count  
7  
> $Inv.AdministrativeUnits | Select-Object displayName, @{ n = 'members'; e = { @($_.members).Count } }  
  
displayName members  
----------- -------  
oer-fr-au 1  
Guests 0  
OER-AU-Demo 1  
oer-fr-au-b 1  
oer_probe_au 1  
Testar 1  
oer-live-au 1
  ```

- [x] **3.8 `Export-OERInventory` reports the gap on the bundle summary as `IncompleteReads`.** -- 2026-09-02

  ```powershell
  $Bundle = Export-OERInventory -OutputPath $Work -Include Groups, AdministrativeUnits -ErrorVariable Err
  $Bundle.IncompleteReads
  @($Bundle.IncompleteReads).Count
  @($Err) | Where-Object FullyQualifiedErrorId -like 'InventoryPartial*' |
      Select-Object -ExpandProperty FullyQualifiedErrorId
  ```

  **Expect:** `IncompleteReads` is non-empty and its entry names
  `administrativeUnits/oer-fr-au/scopedRoles`; the error id is
  `InventoryPartial,Export-OERInventory`. Note that `Count` is the number of PARTIAL REPORTS, not
  the number of unread collections -- one report holding three comma-joined triples is one entry.

  *Record (2026-09-02): the Expect is MET -- `IncompleteReads` is non-empty, names
  `administrativeUnits/oer-fr-au/scopedRoles`, and the error id is
  `InventoryPartial,Export-OERInventory`. Also recorded, since it contradicts itself on the same
  screen: the summary message says `1 Entra ID collection read(s) failed` and then lists SEVEN
  triples, while `Get-OERInventory` on the same run says `7 collection(s)`. The count printed is the
  number of REPORTS, which is what the note above already says `Count` means -- but the message
  calls them collections. Two headline numbers on one export disagree; that is a message defect, not
  a failure of this check.*
  **Result:**
  ```powershell
> $Bundle = Export-OERInventory -OutputPath $Work -Include Groups, AdministrativeUnits -ErrorVariable Err
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding
mulitple WARNINGS....
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
Get-OERInventory: This inventory is PARTIAL: 7 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles,  
administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles,  
administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not  
treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to  
complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011:  
Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit  
00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped  
roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as  
empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is  
omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the  
operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied:  
Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..  
Export-OERInventory: This inventory bundle is PARTIAL: 1 Entra ID collection read(s) failed and are NOT stated as facts in inventory.json: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched. Do not treat it as a full tenant snapshot.
> $Bundle.IncompleteReads  
administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles, administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles, administrativeUnits/oer-live-au/scopedRoles
> @($Bundle.IncompleteReads).Count  
1  
> @($Err) | Where-Object FullyQualifiedErrorId -like 'InventoryPartial*' |  
> Select-Object -ExpandProperty FullyQualifiedErrorId  
InventoryPartial,Get-OERInventory  
InventoryPartial,Export-OERInventory
  ```

- [x] **3.9 `Export-OERInventory -ErrorAction Stop` still WRITES the bundle before it errors.** -- 2026-09-02

  A partial inner read must not cost the operator the entire bundle.

  ```powershell
  try { Export-OERInventory -OutputPath $Work -Include Groups, AdministrativeUnits -ErrorAction Stop; 'DID NOT STOP' }
  catch { "STOPPED: $($_.FullyQualifiedErrorId)" }
  $New = Get-ChildItem $Work -Directory | Sort-Object CreationTime | Select-Object -Last 1
  Get-ChildItem $New.FullName -Filter '*.json' | Select-Object Name, Length
  ```

  **Expect:** the call STOPS with `InventoryPartial,Export-OERInventory`, AND a new bundle folder
  exists holding `inventory.json`, `groupsRoster.json` and `schema.json` at non-zero length. The
  error follows the summary; it does not replace it.
  **Failure looks like:** no new folder, or an empty one -- the operator lost the bundle and the
  data both, which is the opposite of what the loud error is for.
  **Result:**
  ```powershell
> try { Export-OERInventory -OutputPath $Work -Include Groups, AdministrativeUnits -ErrorAction Stop; 'DID NOT STOP' }  
> catch { "STOPPED: $($_.FullyQualifiedErrorId)" }  
WARNING: Could not read groups:  
WARNING: Could not read groups: Response status code does not indicate success: BadRequest (Bad Request).  
WARNING: Could not read groups: Exception calling "GetValues" with "1" argument(s): "The given header was not found."  
WARNING: Could not read groups: ResourceTypeNotSupported: Resource type not supported for onboarding
mulitple WARNING...
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
WARNING: Could not read administrative units:  
WARNING: Could not read administrative units: Authorization_RequestDenied: Insufficient privileges to complete the operation.  
Get-OERInventory: This inventory is PARTIAL: 7 collection(s) could not be read and are not stated as facts in the document. Unread: administrativeUnits/oer-fr-au/scopedRoles, administrativeUnits/Guests/scopedRoles,  
administrativeUnits/OER-AU-Demo/scopedRoles, administrativeUnits/oer-fr-au-b/scopedRoles, administrativeUnits/oer_probe_au/scopedRoles, administrativeUnits/Testar/scopedRoles,  
administrativeUnits/oer-live-au/scopedRoles. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not  
treat this document as a full tenant snapshot. Causes: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to  
complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000011:  
Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit  
00000000-0000-0000-0000-000000000012: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped  
roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as  
empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000013: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is  
omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000014: Authorization_RequestDenied: Insufficient privileges to complete the  
operation.. The ScopedRoles property is omitted rather than reported as empty.; Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000015: Authorization_RequestDenied:  
Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty..  
  
BundlePath Groups Roster RoleAssignments RoleMgmtPolicies Scopes  
---------- ------ ------ --------------- ---------------- ------  
C:\Users\<user>\AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148 91 100 0 0 0  
STOPPED: InventoryPartial,Export-OERInventory

> $New = Get-ChildItem $Work -Directory | Sort-Object CreationTime | Select-Object -Last 1  
> Get-ChildItem $New.FullName -Filter '*.json' | Select-Object Name, Length  
  
Name Length  
---- ------  
administrativeUnits.json 1874  
groups.json 101018  
groupsRoster.json 13383  
inventory.json 110588  
schema.json 21373  
scopeHierarchy.json 56

  ```

- [x] **3.10 `inventory.json` on disk carries the null, not an empty array.** -- 2026-09-02

  ```powershell
  $Json = Join-Path $New.FullName 'inventory.json'
  Select-String -Path $Json -Pattern '"scopedRoles"' -Context 0,1
  $Doc = Get-Content $Json -Raw | ConvertFrom-Json
  $D = $Doc.administrativeUnits | Where-Object displayName -eq 'oer-fr-au'
  $D.PSObject.Properties.Name -contains 'scopedRoles'
  $null -eq $D.scopedRoles
  ```

  **Expect:** the raw file shows `"scopedRoles": null`, and the round-tripped object has the key
  present with a null value. A JSON null survives `ConvertFrom-Json` as `$null`, which is the whole
  distinction this branch turns on -- if it does not survive here, nothing downstream works.
  **Result:**
  ```powershell
> $Json = Join-Path $New.FullName 'inventory.json'  
> Select-String -Path $Json -Pattern '"scopedRoles"' -Context 0,1  
  
> AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3690: "scopedRoles": null  
AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3691: },  
> AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3699: "scopedRoles": null  
AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3700: },  
> AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3710: "scopedRoles": null  
AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3711: },  
> AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3721: "scopedRoles": null  
AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3722: },  
> AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3732: "scopedRoles": null  
AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3733: },  
> AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3743: "scopedRoles": null  
AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3744: },  
> AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3754: "scopedRoles": null  
AppData\Local\Temp\oer-fr\oer-inventory-00000000-0000-0000-0000-000000000001-20260902-113148\inventory.json:3755: }  
  
> $Doc = Get-Content $Json -Raw | ConvertFrom-Json  
> $D = $Doc.administrativeUnits | Where-Object displayName -eq 'oer-fr-au'  
> $D.PSObject.Properties.Name -contains 'scopedRoles'  
True  
> $null -eq $D.scopedRoles  
True
  ```

- [ ] **3.11 An unread membership counts as `null`, not `1` -- and it needs an explicit
  `-GroupFilter` to be reachable at all.**

  *NOT A PASS (2026-09-03). The guard printed `1`, so the filter admitted the group and the check
  did measure something -- but `$null -eq $HG.members` printed **False** and `@($HG.members).Count`
  printed **3**. That is a membership that was READ, not an unread one: the member read succeeded
  under the narrow principal. The Expect is an explicit null and a printed `1`.*

  Needs a group whose MEMBER read failed, so this is route D, so it is a **Microsoft 365 group**:
  `HiddenMembership` is supported only on unified groups and only at creation, and visibility is not
  supported on security groups at all. **`Get-OERInventory` defaults its group filter to
  `securityEnabled eq true`, which excludes every Microsoft 365 group by construction, so the
  default read can never see the group this check is about -- pass `-GroupFilter` explicitly.**

  ```powershell
  Connect-Fr -As Narrow    # route D: Member.Read.Hidden withheld
  $InvR = Get-OERInventory -Include Groups -GroupFilter "groupTypes/any(c:c eq 'Unified')" -ErrorVariable Err
  $HG   = $InvR.Groups | Where-Object displayName -eq 'oer-fr-hidden'

  # Guard first: did the filter admit the group at all? An absent row is NOT a null membership.
  @($HG).Count                                        # must be 1, not 0
  $HG.PSObject.Properties.Name -contains 'members'    # key PRESENT
  $null -eq $HG.members                               # value is NULL
  @($HG.members).Count                                # the trap: 1, for a membership of UNKNOWN size
  ```

  **Expect:** the guard prints `1`; the `members` key is present with a `$null` value. The last line
  printing `1` is the whole point of the check -- `@($null).Count` is `1`, so any consumer that
  counts without testing for null first reports a group of UNKNOWN size as having exactly one
  member. The projection must therefore hand on the null itself, not a count.
  **Failure looks like:** `members` typed as `[]`, or the key absent. A guard of `0` is not a pass
  and not a failure: the filter did not admit the group and the check measured nothing -- fix the
  filter and re-run.

  **`groupsRoster.json` cannot carry this case, and that is a stated limit rather than a gap in the
  run.** `Export-OERInventory` builds the roster from a hardcoded
  `Get-OERGroup -Filter 'securityEnabled eq true'` and exposes no `-GroupFilter` of its own, so a
  Microsoft 365 group never reaches the roster -- and since visibility is unsupported on security
  groups, no group that CAN reach the roster can have its member read denied. The roster's own
  `null`-vs-`1` join is therefore unreachable live by any of the four routes; it is covered by unit
  test only. Do not spend an evening looking for the row.

  *UNPROVABLE AS RUN (2026-09-02). The run read `groupsRoster.json` from a default bundle export.
  No row carried `memberCount: null` and none could have: `oer-fr-hidden` is a Microsoft 365 group,
  excluded by the roster's `securityEnabled eq true` filter, and the two rows that did appear --
  `oer-fr-empty` (0) and `oer-fr-grp` (2) -- are groups whose member reads SUCCEEDED. Compounding
  it, `oer-fr-narrow` still held `Member.Read.Hidden`, so no member read was denied anywhere in the
  run. Re-run in the form above, against a genuinely narrowed route D.*
  **Result:**
  ```powershell
> $InvR = Get-OERInventory -Include Groups -GroupFilter "groupTypes/any(c:c eq 'Unified')" -ErrorVariable Err  
> $HG = $InvR.Groups | Where-Object displayName -eq 'oer-fr-hidden'  
>  
> # Guard first: did the filter admit the group at all? An absent row is NOT a null membership.  
> @($HG).Count # must be 1, not 0  
1  
> $HG.PSObject.Properties.Name -contains 'members' # key PRESENT  
True  
> $null -eq $HG.members # value is NULL  
False  
> @($HG.members).Count # the trap: 1, for a membership of UNKNOWN size  
3  
>
  ```

- [x] **3.12 The partial `inventory.json` still validates against the schema shipped beside it.** -- 2026-09-02

  > **`Errors` is not an error count.** `Test-OERStructure` returns
  > `Errors = @($Findings)` -- EVERY finding, `Warning`-severity ones included -- while `Valid` is
  > computed from `Error`-severity findings only. `@($_.Errors).Count` therefore counts warnings as
  > errors, and a document can legitimately read `Valid True / Errors 1`. Count the severities
  > separately, as below, or the two columns contradict each other and neither can be acted on.
  > The same correction applies to checks 6.1 and 6.4.

  ```powershell
  Test-OERStructure -Path $Json |
      Select-Object Valid,
          @{ n = 'ErrorCount';   e = { @($_.Errors | Where-Object Severity -eq 'Error').Count } },
          @{ n = 'WarningCount'; e = { @($_.Errors | Where-Object Severity -eq 'Warning').Count } }
  $Schema = Get-Content (Join-Path $New.FullName 'schema.json') -Raw | ConvertFrom-Json
  $Schema.properties.administrativeUnits.items.properties.scopedRoles.type
  $Schema.properties.administrativeUnits.items.properties.members.type
  $Schema.properties.groups.items.properties.members.type
  ```

  **Expect:** `Valid` is `True` with `ErrorCount` `0`, and all three keys type as `array, null`.
  `WarningCount` is recorded, not asserted -- a warning does not invalidate a document. Before this
  branch the schema typed them `array` only, so the schema written INSIDE a bundle rejected the
  document in that same bundle. **Failure looks like:** `Valid` `False`, a non-zero `ErrorCount`, or
  a bare `array`.

  *Record (2026-09-02): passed. `Valid True`, zero findings of any severity, and all three keys
  typed `array` + `null`. The run used the old `@($_.Errors).Count` form, which happened to agree
  here since there were no warnings either; checks 6.1 and 6.4 are where the two forms diverged.*
  **Result:**
  ```powershell
> Test-OERStructure -Path $Json | Select-Object Valid, @{ n = 'Errors'; e = { @($_.Errors).Count } }  
  
Valid Errors  
----- ------  
True 0  
  
> $Schema = Get-Content (Join-Path $New.FullName 'schema.json') -Raw | ConvertFrom-Json  
> $Schema.properties.administrativeUnits.items.properties.scopedRoles.type  
array  
null   
> $Schema.properties.administrativeUnits.items.properties.members.type  
array  
null  
> $Schema.properties.groups.items.properties.members.type  
array  
null
  ```

- [x] **3.13 `owners` and `eligibility` are OMITTED, not nulled.** -- 2026-09-03

  Needs a group with a failed owners or eligibility read -- route A gives you eligibility.

  ```powershell
  Connect-Fr -As Narrow          # route A consent
  $InvA = Get-OERInventory -Include Groups -ErrorVariable Err
  $GG = $InvA.Groups | Where-Object displayName -eq 'oer-fr-grp'
  $GG.PSObject.Properties.Name -contains 'eligibility'
  ```

  **Expect:** `False` -- the key is absent entirely. For `owners` and `eligibility` an OMITTED key
  already means "never reconciled, never pruned", so omission is the correct hands-off form and a
  null would be redundant surface. The asymmetry against `members`/`scopedRoles` is deliberate, and
  the schema deliberately does NOT widen these two to accept a null.

  *UNRUN (2026-09-02): could not be provoked -- `oer-fr-narrow` still held both
  `PrivilegedEligibilitySchedule.*` roles, so the eligibility read never failed and the `True`
  below is the key being present after a SUCCESSFUL read. That is the opposite condition to the one
  this check asks about, and says nothing either way about omission on failure. Must be re-run
  after an actual consent switch to route A.*

  *Record (2026-09-03): PASSED, though not on the row the snippet looks at. Route A was verified in
  force (`Token roles (Narrow, 15)`, neither `PrivilegedEligibilitySchedule.*` role present). The
  `oer-fr-grp` row still reads `True`, since that group's eligibility read SUCCEEDS for the narrow
  principal -- see 1.8 -- so that line answers nothing. The proof is in the same output's
  `InventoryPartial` record: `Unread: groups/<name>/eligibility` for TEN groups, with
  `Causes: ... PermissionScopeNotGranted ... PrivilegedEligibilitySchedule.Read.AzureADGroup ...`.
  `Get-OERInventory` always requests `IncludePimEligibility` (`Get-OERInventory.ps1:217`) and adds
  that triple only where the property came back OMITTED (`Get-OERInventory.ps1:402`, the `else`
  branch), so for those ten the `eligibility` key is absent from the projection -- which is exactly
  what this check asserts, and the key was NOT nulled. Re-run the `-contains` line against one of
  the ten to have it printed directly.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 15): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $InvA = Get-OERInventory -Include Groups -ErrorVariable Err  
Get-OERInventory: This inventory is PARTIAL: 10 collection(s) could not be read and are not stated as facts in the document. Unread: groups/GDAP - Account Managers/eligibility, groups/GDAP - JIT Approvers/eligibility, groups/GDAP - Service desk/eligibility, groups/GDAP - Escalation Engineers/eligibility, groups/Lighthouse Account Manager Group/eligibility, groups/GDAP - JIT Only/eligibility, groups/GDAP - Specialists/eligibility, groups/az_mg_root_owner/eligibility, groups/TestarAU/eligibility, groups/role_sec_identity_administrator/eligibility. A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot. Causes: Could not read PIM eligibility for group 00000000-0000-0000-0000-000000000024: UnauthorizedAccessException: {"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope PrivilegedEligibilitySchedule.Read.AzureADGroup,PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup,PrivilegedAccess.Read.AzureADGroup,PrivilegedAccess.ReadWrite.AzureADGroup.","instanceAnnotations":[]}. The PimEligibility property is omitted rather than reported as empty..
> $GG = $InvA.Groups | Where-Object displayName -eq 'oer-fr-grp'  
> $GG.PSObject.Properties.Name -contains 'eligibility'  
True  
>
  ```

---

### 4. The chain, end to end -- the section that matters most (checks 4.x)

This is what proves issue #76 is actually closed. It uses the partial `inventory.json` produced in
section 3 and it is `-WhatIf` throughout until 4.5.

- [x] **4.1 The partial document plans NO removal under `-Prune`.** -- 2026-09-02

  ```powershell
  Connect-Fr -As Full     # apply as the FULL principal: the live read must SUCCEED here
  Invoke-OERStructure -Path $Json -Include AdministrativeUnits -Prune -WhatIf |
      Where-Object Section -eq 'administrativeUnits' |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** for `oer-fr-au`, NO row with `Action` `Removed` or `Extra` naming a scoped role. The
  explicit null is read as "leave scoped roles untouched", so the prune pass never runs for that
  collection. **Failure looks like:** a `Removed` or `Extra` row naming the live scoped role -- the
  fix is not working, and applying this document would strip it.
  **Result:**
  ```powershell
> Connect-Fr -As Full # apply as the FULL principal: the live read must SUCCEED here  
Client secret for Full: ****************************************  
> Invoke-OERStructure -Path $Json -Include AdministrativeUnits -Prune -WhatIf |  
> Where-Object Section -eq 'administrativeUnits' |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
administrativeUnits oer-fr-au Unchanged administrative unit properties match  
administrativeUnits oer-fr-au Unchanged member '00000000-0000-0000-0000-000000000016' already present  
administrativeUnits Guests Unchanged administrative unit properties match  
administrativeUnits OER-AU-Demo Unchanged administrative unit properties match  
administrativeUnits OER-AU-Demo Unchanged member '00000000-0000-0000-0000-000000000017' already present  
administrativeUnits oer-fr-au-b Unchanged administrative unit properties match  
administrativeUnits oer-fr-au-b Unchanged member '00000000-0000-0000-0000-000000000018' already present  
administrativeUnits oer_probe_au Unchanged administrative unit properties match  
administrativeUnits oer_probe_au Unchanged member '00000000-0000-0000-0000-000000000019' already present  
administrativeUnits Testar Unchanged administrative unit properties match  
administrativeUnits Testar Unchanged member '00000000-0000-0000-0000-000000000020' already present  
administrativeUnits oer-live-au Unchanged administrative unit properties match  
administrativeUnits oer-live-au Unchanged member '00000000-0000-0000-0000-000000000019' already present
  ```

- [x] **4.2 The before/after that proves it: hand-edit the null to `[]` in a COPY.** -- 2026-09-02

  **The edited copy must NEVER be applied without `-WhatIf`.** It is a demonstration of the damage
  the old behaviour caused, and applying it for real would cause exactly that damage to a live
  tenant.

  ```powershell
  $Bad = Join-Path $Work 'inventory-DEMO-DO-NOT-APPLY.json'
  (Get-Content $Json -Raw) -replace '"scopedRoles":\s*null', '"scopedRoles": []' |
      Set-Content $Bad -Encoding utf8
  Invoke-OERStructure -Path $Bad -Include AdministrativeUnits -Prune -WhatIf |
      Where-Object Section -eq 'administrativeUnits' |
      Format-Table Section, Item, Action, Detail -AutoSize
  ```

  **Expect:** the plan NOW contains a row for the live scoped role on `oer-fr-au` that it did not
  contain in 4.1, carrying a `Detail` of
  `would remove undeclared scopedRole '<role>' for '<principal>'`. **Under `-WhatIf` that row's
  `Action` is `Skipped`, not `Removed` and not `Extra`** -- an earlier draft of this check named
  those two and was wrong: `Removed` is what the same row becomes when the command runs for real,
  and `Extra` is what a prune-less run reports. Match on the `Detail`, and on the row existing at
  all, rather than on the `Action` string. That row is what the old code shipped into production on
  a partial export. Confirm before you run it that the command carries `-WhatIf` and that every row
  is planned only.

  *Record (2026-09-02): the headline holds -- the edited copy plans removal of a live scoped role
  that the un-edited document left alone, on FIVE units including `oer-fr-au`, each with a matching
  `What if:` line. Every planned row read `Skipped`, which is what prompted the Expect correction
  above.*
  **Result:**
  ```powershell
> $Bad = Join-Path $Work 'inventory-DEMO-DO-NOT-APPLY.json'  
> (Get-Content $Json -Raw) -replace '"scopedRoles":\s*null', '"scopedRoles": []' |  
> Set-Content $Bad -Encoding utf8  
> Invoke-OERStructure -Path $Bad -Include AdministrativeUnits -Prune -WhatIf |  
> Where-Object Section -eq 'administrativeUnits' |  
> Format-Table Section, Item, Action, Detail -AutoSize
> WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared scopedRole 'User Administrator' (principal '00000000-0000-0000-0000-000000000016') from unit 'oer-fr-au'.  
What if: Performing the operation "Remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000016'" on target "oer-fr-au".  
WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared scopedRole 'User Administrator' (principal '00000000-0000-0000-0000-000000000017') from unit 'OER-AU-Demo'.  
What if: Performing the operation "Remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000017'" on target "OER-AU-Demo".  
WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared scopedRole 'User Administrator' (principal '00000000-0000-0000-0000-000000000019') from unit 'oer-fr-au-b'.  
What if: Performing the operation "Remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000019'" on target "oer-fr-au-b".  
WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared scopedRole 'Attribute Assignment Administrator' (principal '00000000-0000-0000-0000-000000000019') from unit 'Testar'.  
What if: Performing the operation "Remove undeclared scopedRole 'Attribute Assignment Administrator' for '00000000-0000-0000-0000-000000000019'" on target "Testar".  
WARNING: Sync-OERStructureAdministrativeUnit: would remove undeclared scopedRole 'User Administrator' (principal '00000000-0000-0000-0000-000000000021') from unit 'oer-live-au'.  
What if: Performing the operation "Remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000021'" on target "oer-live-au".  
  
Section Item Action Detail  
------- ---- ------ ------  
administrativeUnits oer-fr-au Unchanged administrative unit properties match  
administrativeUnits oer-fr-au Unchanged member '00000000-0000-0000-0000-000000000016' already present  
administrativeUnits oer-fr-au Skipped would remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000016'  
administrativeUnits Guests Unchanged administrative unit properties match  
administrativeUnits OER-AU-Demo Unchanged administrative unit properties match  
administrativeUnits OER-AU-Demo Unchanged member '00000000-0000-0000-0000-000000000017' already present  
administrativeUnits OER-AU-Demo Skipped would remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000017'  
administrativeUnits oer-fr-au-b Unchanged administrative unit properties match  
administrativeUnits oer-fr-au-b Unchanged member '00000000-0000-0000-0000-000000000018' already present  
administrativeUnits oer-fr-au-b Skipped would remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000019'  
administrativeUnits oer_probe_au Unchanged administrative unit properties match  
administrativeUnits oer_probe_au Unchanged member '00000000-0000-0000-0000-000000000019' already present  
administrativeUnits Testar Unchanged administrative unit properties match  
administrativeUnits Testar Unchanged member '00000000-0000-0000-0000-000000000020' already present  
administrativeUnits Testar Skipped would remove undeclared scopedRole 'Attribute Assignment Administrator' for '00000000-0000-0000-0000-000000000019'  
administrativeUnits oer-live-au Unchanged administrative unit properties match  
administrativeUnits oer-live-au Unchanged member '00000000-0000-0000-0000-000000000019' already present  
administrativeUnits oer-live-au Skipped would remove undeclared scopedRole 'User Administrator' for '00000000-0000-0000-0000-000000000021'
  ```

- [x] **4.3 Delete the demonstration file immediately.** -- 2026-09-02

  ```powershell
  Remove-Item $Bad -Force
  Test-Path $Bad
  ```

  **Expect:** `False`. Leaving a document on disk that empties a live collection is exactly the
  hazard this branch closes. **Result:**
  ```powershell
 > Remove-Item $Bad -Force   
> Test-Path $Bad  
False
  ```

- [ ] **4.4 The same, for group members (route D).**

  *NOT A PASS (2026-09-03). `Select-String` returned `"members": [` followed by
  `"person5@example.com",` where the Expect is `"members": null`, so the member read succeeded and
  the document states a membership as fact. The two plans that follow are byte-identical
  `Unchanged` tables -- the `-replace '"members":\s*null'` had nothing to replace, so the second
  plan is the FIRST document applied twice and demonstrates no before/after at all. This is the
  load-bearing check for `groups[].members`, the exact key issue #76 was filed against, and it is
  still unproven end to end.*

  Repeat 4.1 and 4.2 against `groups[].members` on `oer-fr-hidden`, using a document produced by
  `Get-OERInventory -GroupFilter "displayName eq 'oer-fr-hidden'"` (the bundle export has no
  `-GroupFilter`, so write the document out yourself with `ConvertTo-Json -Depth 20`). Skip and say
  so if check 1.1 recorded "came back empty".

  **The `-GroupFilter` is not optional and is not a convenience.** `oer-fr-hidden` is a Microsoft 365
  group -- route D admits no other kind, since visibility is unsupported on security groups -- and
  `Get-OERInventory` defaults to `securityEnabled eq true`, so a default read returns a document that
  does not mention the group at all. Without the explicit filter this check silently measures an
  empty document and reads as a pass.

  ```powershell
  # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute D   (if not already on route D)
  Connect-Fr -As Narrow
  $InvD  = Get-OERInventory -Include Groups -GroupFilter "displayName eq 'oer-fr-hidden'" -ErrorVariable Err
  $JsonD = Join-Path $Work 'inventory-hidden.json'
  $InvD | ConvertTo-Json -Depth 20 | Set-Content $JsonD -Encoding utf8
  Select-String -Path $JsonD -Pattern '"members"' -Context 0,1          # expect "members": null

  Connect-Fr -As Full
  Invoke-OERStructure -Path $JsonD -Include Groups -Prune -WhatIf |
      Where-Object Section -eq 'groups' | Format-Table Section, Item, Action, Detail -AutoSize   # no Removed/Extra

  $BadD = Join-Path $Work 'inventory-hidden-DEMO-DO-NOT-APPLY.json'
  (Get-Content $JsonD -Raw) -replace '"members":\s*null', '"members": []' | Set-Content $BadD -Encoding utf8
  Invoke-OERStructure -Path $BadD -Include Groups -Prune -WhatIf |
      Where-Object Section -eq 'groups' | Format-Table Section, Item, Action, Detail -AutoSize   # Removed rows appear
  Remove-Item $BadD -Force; Test-Path $BadD                                                      # False
  ```

  **Expect:** the same shape -- an explicit null plans no member removal, `[]` plans removal of
  every live member. As in 4.2, the removal row's `Action` under `-WhatIf` is `Skipped`; match on
  the `Detail` and on the row existing.

  *UNRUN (2026-09-02). The result line read, in full, `SAME RESULT/SHAPE.` with no console output
  behind it, so there is nothing to verify and nothing to point at. Two independent reasons it could
  not have run as written even if the commands were issued: `oer-fr-narrow` still held
  `Member.Read.Hidden`, so the member read on `oer-fr-hidden` would have SUCCEEDED and the document
  would have carried a real member list rather than `"members": null`; and route D was never
  consented at all. **This is the load-bearing check of the whole file** -- `groups[].members` is
  the exact key issue #76 was filed against, and section 7.2 already says route B on `scopedRoles`
  is a strong inference and not a substitute. It must be re-run, with the output pasted, before that
  key can be called live-verified.*
  **Result:**
  ```powershell
> # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute D (if not already on route D)  
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
> $InvD = Get-OERInventory -Include Groups -GroupFilter "displayName eq 'oer-fr-hidden'" -ErrorVariable Err  
> $JsonD = Join-Path $Work 'inventory-hidden.json'  
> $InvD | ConvertTo-Json -Depth 20 | Set-Content $JsonD -Encoding utf8  
> Select-String -Path $JsonD -Pattern '"members"' -Context 0,1 # expect "members": null  
  
> AppData\Local\Temp\oer-fr\inventory-hidden.json:10: "members": [  
AppData\Local\Temp\oer-fr\inventory-hidden.json:11: "person5@example.com",  
  
>  
> Connect-Fr -As Full  
Client secret for Full: ***************************************                                                  # False
> Invoke-OERStructure -Path $JsonD -Include Groups -Prune -WhatIf |  
> Where-Object Section -eq 'groups' | Format-Table Section, Item, Action, Detail -AutoSize # no Removed/Extra  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-fr-hidden Unchanged group properties match  
groups oer-fr-hidden Unchanged member 'person5@example.com' already present  
groups oer-fr-hidden Unchanged member 'person6@example.com' already present  
groups oer-fr-hidden Unchanged member 'person7@example.com' already present  
groups oer-fr-hidden Unchanged owner 'person6@example.com' already present  
groups oer-fr-hidden Unchanged pimPolicy (member) already matches  
groups oer-fr-hidden Unchanged pimPolicy (owner) already matches  
  
>  
> $BadD = Join-Path $Work 'inventory-hidden-DEMO-DO-NOT-APPLY.json'  
> (Get-Content $JsonD -Raw) -replace '"members":\s*null', '"members": []' | Set-Content $BadD -Encoding utf8  
> Invoke-OERStructure -Path $BadD -Include Groups -Prune -WhatIf |  
> Where-Object Section -eq 'groups' | Format-Table Section, Item, Action, Detail -AutoSize # Removed rows appear  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-fr-hidden Unchanged group properties match  
groups oer-fr-hidden Unchanged member 'person5@example.com' already present  
groups oer-fr-hidden Unchanged member 'person6@example.com' already present  
groups oer-fr-hidden Unchanged member 'person7@example.com' already present  
groups oer-fr-hidden Unchanged owner 'person6@example.com' already present  
groups oer-fr-hidden Unchanged pimPolicy (member) already matches  
groups oer-fr-hidden Unchanged pimPolicy (owner) already matches  
  
> Remove-Item $BadD -Force; Test-Path $BadD # False
  ```

- [x] **4.5 Applying the partial document for real changes nothing it could not read.** -- 2026-09-02

  **This check WRITES to the tenant.** It is the first command in section 4 that is not `-WhatIf`.
  Run it only after 4.1 read clean, and only once you are satisfied the plan it printed is the plan
  you want. Drop `-WhatIf`; keep `-Prune`.

  ```powershell
  Invoke-OERStructure -Path $Json -Include AdministrativeUnits -Prune |
      Format-Table Section, Item, Action, Detail -AutoSize
  (Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles).ScopedRoles |
      Select-Object RoleName, PrincipalId
  ```

  **Expect:** the scoped role you created is still there, unchanged, and the result rows show no
  removal. Verify in the portal too, not only through the module -- the module reading its own write
  back is a weaker proof than the portal agreeing.
  **Result:**
  ```powershell
> Invoke-OERStructure -Path $Json -Include AdministrativeUnits -Prune |  
> Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
administrativeUnits oer-fr-au Unchanged administrative unit properties match  
administrativeUnits oer-fr-au Unchanged member '00000000-0000-0000-0000-000000000016' already present  
administrativeUnits Guests Unchanged administrative unit properties match  
administrativeUnits OER-AU-Demo Unchanged administrative unit properties match  
administrativeUnits OER-AU-Demo Unchanged member '00000000-0000-0000-0000-000000000017' already present  
administrativeUnits oer-fr-au-b Unchanged administrative unit properties match  
administrativeUnits oer-fr-au-b Unchanged member '00000000-0000-0000-0000-000000000018' already present  
administrativeUnits oer_probe_au Unchanged administrative unit properties match  
administrativeUnits oer_probe_au Unchanged member '00000000-0000-0000-0000-000000000019' already present  
administrativeUnits Testar Unchanged administrative unit properties match  
administrativeUnits Testar Unchanged member '00000000-0000-0000-0000-000000000020' already present  
administrativeUnits oer-live-au Unchanged administrative unit properties match  
administrativeUnits oer-live-au Unchanged member '00000000-0000-0000-0000-000000000019' already present  
  
> (Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles).ScopedRoles |  
> Select-Object RoleName, PrincipalId  
  
RoleName PrincipalId  
-------- -----------  
User Administrator 00000000-0000-0000-0000-000000000016
  ```

---

### 5. Apply engine -- a failed live read is `Failed`, never `Created` (checks 5.x)

These exercise the five reads that previously swallowed their errors. Run as `oer-fr-narrow`, with
the scope named in each check withheld. The assignment policy that already exists on `oer-fr-ap` is
`oer-fr-policy` (created by `Initialize-OerFrPrereq.ps1`).

> **Caveat for 5.1-5.4, found while writing the snippets.** Under app-only auth there is no
> entitlement-management scope that allows a write but denies a read: `EntitlementManagement.ReadWrite.All`
> satisfies every read endpoint. Route E therefore withholds BOTH `EntitlementManagement.Read.All` and
> `EntitlementManagement.ReadWrite.All`. With both gone, the FIRST read in the handler --
> `Get-OERAccessPackage -Catalog` (`Sync-OERStructureAccessPackage.ps1:141`) -- fails before the policy,
> resource-role or catalog-resource reads are ever reached, so the `Detail` you will most likely see is
> `failed to look up access packages in catalog 'OER-FR-CAT': ...`, not the one each check names. That
> still proves the item-level guarantee (one `Failed` row, zero `Created`, nothing pruned) but NOT the three
> specific reads. Record which `Detail` you actually got; if it is the catalog lookup, write "cannot be
> provoked by permission split; catalog lookup fails first" on 5.1-5.4 and leave them unticked.


- [ ] **5.1 A failed assignment-policy read reports `Failed`, and creates nothing.**

  *CANNOT BE PROVOKED BY PERMISSION SPLIT; CATALOG LOOKUP FAILS FIRST (2026-09-03). Route E was
  genuinely in force -- `Token roles (Narrow, 15)`, neither `EntitlementManagement.*` role present
  -- and the `Detail` is `failed to look up access packages in catalog 'OER-FR-CAT': Catalog
  'OER-FR-CAT' not found.`, with `Error.FullyQualifiedErrorId` `CatalogNotFound,Invoke-OERStructure`,
  not the assignment-policy read the Expect names. The item-level guarantee (one `Failed` row, zero
  `Created`) holds, but the specific read does not, so the section 5 caveat applies verbatim and
  this box stays unticked.*

  Consent `oer-fr-narrow` WITHOUT `EntitlementManagement.Read.All`, keeping whatever write scope it
  needs so that a create would genuinely be attempted if the engine tried one. Apply a document
  declaring `oer-fr-ap` -- which already exists -- with an assignment policy that also already
  exists.

  ```powershell
  $ApDoc = Join-Path $Work 'ap.json'
  @'
{ "version": "1.0",
  "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",
    "assignmentPolicies": [ { "displayName": "oer-fr-policy" } ] } ] }
'@ | Set-Content $ApDoc -Encoding utf8
  # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute E
  Connect-Fr -As Narrow
  $R = Invoke-OERStructure -Path $ApDoc -Include AccessPackages
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  @($R | Where-Object Action -eq 'Created').Count
  ($R | Where-Object Action -eq 'Failed').Error.FullyQualifiedErrorId
  ```

  **Expect:** exactly one `Failed` row whose `Detail` reads
  `failed to read the current assignment policies of access package 'oer-fr-ap': ...`, its `Error`
  property populated with a real `ErrorRecord`, and ZERO `Created` rows.
  **Failure looks like:** a `Created` row -- the engine took a suppressed read for "this package has
  no policies" and tried to create one that already exists.

  *UNRUN (2026-09-02): could not be provoked -- `oer-fr-narrow` still held BOTH
  `EntitlementManagement.Read.All` and `EntitlementManagement.ReadWrite.All`, the two permissions
  route E withholds. Every read succeeded, so the plan below is an ordinary clean reconcile: zero
  `Created` rows and zero `Failed` rows, which is the right answer for an AUTHORIZED run and no
  answer at all for this check. Must be re-run after an actual consent switch to route E.*
  **Result:**
  ```powershell
> $ApDoc = Join-Path $Work 'ap.json'  
> @'  
> { "version": "1.0",  
> "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",  
> "assignmentPolicies": [ { "displayName": "oer-fr-policy" } ] } ] }  
> '@ | Set-Content $ApDoc -Encoding utf8  
> # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute E  
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 15): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $R = Invoke-OERStructure -Path $ApDoc -Include AccessPackages  
Invoke-OERStructure: Catalog 'OER-FR-CAT' not found.  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-fr-ap Failed failed to look up access packages in catalog 'OER-FR-CAT': Catalog 'OER-FR-CAT' not found.; the access package was NOT created  
  
> @($R | Where-Object Action -eq 'Created').Count  
0  
> ($R | Where-Object Action -eq 'Failed').Error.FullyQualifiedErrorId  
CatalogNotFound,Invoke-OERStructure  
> test-path $apdoc  
True  
> Get-OERCatalog -DisplayName 'OER-FR-CAT'  
Get-OERCatalog: UnAuthorized: User is not authorized to perform the operation. Reason: Unauthorized  
  ```

- [ ] **5.2 A failed resource-role-scope read reports `Failed` and creates nothing.**

  *CANNOT BE PROVOKED BY PERMISSION SPLIT; CATALOG LOOKUP FAILS FIRST (2026-09-03). Same `Detail`
  as 5.1 -- the catalog lookup -- where the Expect names
  `failed to read the current resource role bindings of access package 'oer-fr-ap'`. Unticked per
  the section 5 caveat.*

  Same principal. Declare a `resourceRoles` block on `oer-fr-ap` naming a binding that already
  exists.

  ```powershell
  $RrDoc = @'
{ "version": "1.0",
  "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",
    "resourceRoles": [ { "resource": "oer-fr-grp", "role": "Member" } ] } ] }
'@
  $R = Invoke-OERStructure -Json $RrDoc -Include AccessPackages
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  @($R | Where-Object Action -eq 'Created').Count                       # expect 0
  ($R | Where-Object Action -eq 'Failed').Detail
  ```

  **Expect:** one `Failed` row whose `Detail` reads
  `failed to read the current resource role bindings of access package 'oer-fr-ap': ...`, and zero
  `Created` rows. **Failure looks like:** a `Created` row attempting to add a binding that is
  already there.

  *UNRUN (2026-09-02): could not be provoked -- same cause as 5.1. `oer-fr-narrow` still held both
  `EntitlementManagement.*` roles, so the resource-role read succeeded and the row below reads
  `Unchanged resourceRole 'Member' on 'oer-fr-grp' already bound`. Must be re-run after an actual
  consent switch to route E.*
  **Result:**
  ```powershell
> $RrDoc = @'  
> { "version": "1.0",  
> "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",  
> "resourceRoles": [ { "resource": "oer-fr-grp", "role": "Member" } ] } ] }  
> '@  
> $R = Invoke-OERStructure -Json $RrDoc -Include AccessPackages  
Invoke-OERStructure: Catalog 'OER-FR-CAT' not found.  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-fr-ap Failed failed to look up access packages in catalog 'OER-FR-CAT': Catalog 'OER-FR-CAT' not found.; the access package was NOT created  
  
> @($R | Where-Object Action -eq 'Created').Count # expect 0  
0  
> ($R | Where-Object Action -eq 'Failed').Detail  
failed to look up access packages in catalog 'OER-FR-CAT': Catalog 'OER-FR-CAT' not found.; the access package was NOT created  
>
  ```

- [ ] **5.3 A failed catalog-resource read prunes NOTHING.**

  *CANNOT BE PROVOKED BY PERMISSION SPLIT; CATALOG LOOKUP FAILS FIRST (2026-09-03). Same `Detail`
  as 5.1 -- the catalog lookup -- where the Expect names
  `failed to read the resources of catalog 'OER-FR-CAT'`. The no-prune half is real and worth
  having: zero `Extra`/`Removed` rows under `-WhatIf` and for real, and the live `Member` binding on
  `oer-fr-grp` was still present afterwards. Unticked per the section 5 caveat.*

  Same principal. Declare `resourceRoles` with one entry, and pass `-Prune`. Run `-WhatIf` first and
  read the plan before you let it act.

  ```powershell
  $R = Invoke-OERStructure -Json $RrDoc -Include AccessPackages -Prune -WhatIf
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  @($R | Where-Object { $_.Action -in 'Extra', 'Removed' }).Count     # expect 0
  ($R | Where-Object Action -eq 'Failed').Detail
  # Only if the -WhatIf plan above holds no Extra/Removed row:
  $R = Invoke-OERStructure -Json $RrDoc -Include AccessPackages -Prune
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  Connect-Fr -As Full
  Get-OERAccessPackageResourceRole -AccessPackage 'oer-fr-ap' | Format-Table   # binding still there
  ```

  **Expect:** one `Failed` row reading `failed to read the resources of catalog 'OER-FR-CAT': ...`,
  and NO `Extra` and NO `Removed` row. Confirm in the portal that every live resource-role binding
  on `oer-fr-ap` is still there.
  **Failure looks like:** the live bindings reported `Extra`, or removed. This is the worst of the
  three, since a destructive pass would then be running against a binding list the engine failed to
  verify.

  *UNRUN (2026-09-02): could not be provoked -- same cause as 5.1 and 5.2. The catalog read
  succeeded, so "no `Extra` and no `Removed` row" below is what a correct AUTHORIZED prune produces
  and says nothing about the guard. The live binding was confirmed still present afterwards, which
  is worth having but is not this check. Must be re-run after an actual consent switch to route E.*
  **Result:**
  ```powershell
> $R = Invoke-OERStructure -Json $RrDoc -Include AccessPackages -Prune -WhatIf  
Invoke-OERStructure: Catalog 'OER-FR-CAT' not found.  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-fr-ap Failed failed to look up access packages in catalog 'OER-FR-CAT': Catalog 'OER-FR-CAT' not found.; the access package was NOT created  
  
> @($R | Where-Object { $_.Action -in 'Extra', 'Removed' }).Count # expect 0  
0  
> ($R | Where-Object Action -eq 'Failed').Detail  
failed to look up access packages in catalog 'OER-FR-CAT': Catalog 'OER-FR-CAT' not found.; the access package was NOT created  
> # Only if the -WhatIf plan above holds no Extra/Removed row:  
> $R = Invoke-OERStructure -Json $RrDoc -Include AccessPackages -Prune  
Invoke-OERStructure: Catalog 'OER-FR-CAT' not found.  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-fr-ap Failed failed to look up access packages in catalog 'OER-FR-CAT': Catalog 'OER-FR-CAT' not found.; the access package was NOT created  
  
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
Token roles (Full, 17): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> Get-OERAccessPackageResourceRole -AccessPackage 'oer-fr-ap' | Format-Table # binding still there  
  
RoleName ResourceDisplayName OriginId ResourceRoleScopeId  
-------- ------------------- -------- -------------------  
Member oer-fr-grp 00000000-0000-0000-0000-000000000025 00000000-0000-0000-0000-000000000026_00000000-0000-0000-0000-000000000027  
  
>
  ```

- [x] **5.4 `"resourceRoles": []` with `-Prune` STILL prunes, even when the catalog read is broken.** -- 2026-09-02

  An empty declared array needs no catalog resources at all, so a broken catalog read must not
  abandon a prune pass that can run correctly. Declare `"resourceRoles": []` on `oer-fr-ap`, keep
  `EntitlementManagement.Read.All` withheld, pass `-Prune`.

  ```powershell
  Connect-Fr -As Narrow    # route E still
  $EmptyRr = @'
{ "version": "1.0",
  "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT", "resourceRoles": [] } ] }
'@
  $R = Invoke-OERStructure -Json $EmptyRr -Include AccessPackages -Prune -WhatIf
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  @($R | Where-Object Action -eq 'Failed').Count                        # expect 0 (see caveat above)
  # WRITES -- only if you accept the removal; T.1 re-creates the binding:
  # $R = Invoke-OERStructure -Json $EmptyRr -Include AccessPackages -Prune
  ```

  **Expect:** the live bindings ARE reported `Removed` (or `Extra` without `-Prune`), and there is
  NO `Failed` row about the catalog read -- that read was never issued.
  **Failure looks like:** a `Failed` row and no prune -- correct behaviour turned into a failure by
  over-cautious error handling.
  **This check WRITES to the tenant.** Run `-WhatIf` first, record the plan, then either accept the
  removal and re-create the binding in teardown, or stop at the plan and say so.

  *Record (2026-09-02): the headline holds under `-WhatIf` -- the live binding IS planned for
  removal (`would remove undeclared resourceRole binding 'Member|<id>'`, `Action` `Skipped` as in
  4.2) and `@($R | Where-Object Action -eq 'Failed').Count` is `0`, so an empty declared array still
  drives a prune. **The real write was NOT run** -- the un-`-WhatIf` line was left commented out and
  the plan is the whole of the evidence, so the binding survives and T.1 has nothing to restore for
  this check. Note also that the catalog read was never actually broken here, since `oer-fr-narrow`
  still held both `EntitlementManagement.*` roles: what is proven is that the prune plans correctly
  on an empty array, not that it still plans correctly when the catalog read has failed. That
  second half needs a genuine route E.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow # route E still  
Client secret for Narrow: ****************************************  
> $EmptyRr = @'  
> { "version": "1.0",  
> "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT", "resourceRoles": [] } ] }  
> '@  
> $R = Invoke-OERStructure -Json $EmptyRr -Include AccessPackages -Prune -WhatIf  
WARNING: Sync-OERStructureAccessPackage: would remove undeclared resourceRole binding 'Member|00000000-0000-0000-0000-000000000006' from access package 'oer-fr-ap'.  
What if: Performing the operation "Remove undeclared resourceRole binding 'Member|00000000-0000-0000-0000-000000000006'" on target "oer-fr-ap".  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-fr-ap Unchanged access package properties match  
accessPackages oer-fr-ap Skipped would remove undeclared resourceRole binding 'Member|00000000-0000-0000-0000-000000000006'  
  
> @($R | Where-Object Action -eq 'Failed').Count # expect 0 (see caveat above)  
0  
> # WRITES -- only if you accept the removal; T.1 re-creates the binding:  
> # $R = Invoke-OERStructure -Json $EmptyRr -Include AccessPackages -Prune
  ```

- [ ] **5.5 A failed live group read reports `Failed` and reconciles nothing.**

  *NOT A PASS (2026-09-03). Route D was genuinely in force this time -- `Token roles (Narrow, 16)`
  with `Member.Read.Hidden` absent -- and the hidden group's member read STILL succeeded: the plan
  shows `Unchanged member ... already present` plus three `Extra` rows, and
  `($R | Where-Object Action -eq 'Failed').Detail` printed nothing. The Expect is one `Failed` row.
  Nothing failed, so there is no guard behaviour to observe -- see section 7.2b.*

  Route D. Apply a document that declares members on `oer-fr-hidden`.D

  ```powershell
  # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute D
  Connect-Fr -As Narrow
  $GDoc = @'
{ "version": "1.0",
  "groups": [ { "displayName": "oer-fr-hidden", "members": [ "person4@example.com" ] } ] }
'@
  $R = Invoke-OERStructure -Json $GDoc -Include Groups
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  ($R | Where-Object Action -eq 'Failed').Detail
  @($R | Where-Object { $_.Action -in 'Created', 'Updated', 'Removed' }).Count   # expect 0
  ```

  `oer-fr-hidden` is a Microsoft 365 group, not a security group. **Record** if the handler cannot
  resolve it at all (a "not found" `Failed` row is a different result than a failed member read).

  **Expect:** one `Failed` row reading `failed to read the current state of group 'oer-fr-hidden':
  ...; no property, member, owner or eligibility change was made`, with `Error` populated, and no
  `Created` / `Updated` / `Removed` row for that group.

  *UNRUN (2026-09-02), and it surfaced a separate defect. The route was never switched -- the
  `Initialize-OerFrPrereq.ps1 -NarrowRoute D` line is commented out in the transcript and
  `oer-fr-narrow` still held `Member.Read.Hidden` -- so whatever denied this read, it was not the
  hidden-membership rule this check is written against. A `Failed` row did appear, but NOT the one
  the Expect names: it reads `groups (item) Failed handler error: Authorization_RequestDenied ...`,
  which is the generic OUTER per-item catch, not the group handler's own guard. Two things are
  wrong with that row and both are module-side: the item is labelled `(item)` although the
  document's `displayName` was in scope, and the guard's own message -- the one naming the group and
  stating that no change was made -- never appears. Re-run after an actual consent switch to
  route D, and expect the label defect to be visible again until it is fixed.*
  **Result:**
  ```powershell
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 16): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, PrivilegedEligibilitySchedule.Read.AzureADGroup, PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $GDoc = @'  
> { "version": "1.0",  
> "groups": [ { "displayName": "oer-fr-hidden", "members": [ "person4@example.com" ] } ] }  
> '@  
> $R = Invoke-OERStructure -Json $GDoc -Include Groups  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-fr-hidden Unchanged group properties match  
groups oer-fr-hidden Unchanged member 'person4@example.com' already present  
groups oer-fr-hidden Extra undeclared member '00000000-0000-0000-0000-000000000028' (use -Prune to remove)  
groups oer-fr-hidden Extra undeclared member '00000000-0000-0000-0000-000000000029' (use -Prune to remove)  
groups oer-fr-hidden Extra undeclared member '00000000-0000-0000-0000-000000000030' (use -Prune to remove)  
  
> ($R | Where-Object Action -eq 'Failed').Detail  
> @($R | Where-Object { $_.Action -in 'Created', 'Updated', 'Removed' }).Count # expect 0  
0   
>
  ```

- [x] **5.6 A failed live AU read reports `Failed` and reconciles nothing.** -- 2026-09-02

  Route C. Apply a document that declares members on `oer-fr-au-b`.

  ```powershell
  # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute C    (oer-fr-au-b must still be HiddenMembership from 2.1)
  Connect-Fr -As Narrow
  $AuDoc = @'
{ "version": "1.0",
  "administrativeUnits": [ { "displayName": "oer-fr-au-b", "members": [ "person2@example.com" ] } ] }
'@
  $R = Invoke-OERStructure -Json $AuDoc -Include AdministrativeUnits
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  ($R | Where-Object Action -eq 'Failed').Detail
  @($R | Where-Object { $_.Action -in 'Created', 'Updated', 'Removed' }).Count   # expect 0
  ```

  **Expect:** one `Failed` row reading `failed to read the current state of administrative unit
  'oer-fr-au-b': ...; no property, member or scopedRole change was made`.
  **Result:**
  ```powershell
> # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute C (oer-fr-au-b must still be HiddenMembership from 2.1)  
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
> $AuDoc = @'  
> { "version": "1.0",  
> "administrativeUnits": [ { "displayName": "oer-fr-au-b", "members": [ "person2@example.com" ] } ] }  
> '@
> $R = Invoke-OERStructure -Json $AuDoc -Include AdministrativeUnits  
Invoke-OERStructure: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
administrativeUnits oer-fr-au-b Failed failed to read the current state of administrative unit 'oer-fr-au-b': Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authori...
> ($R | Where-Object Action -eq 'Failed').Detail  
failed to read the current state of administrative unit 'oer-fr-au-b': Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000008: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty.; no property, member or scopedRole change was made
> @($R | Where-Object { $_.Action -in 'Created', 'Updated', 'Removed' }).Count # expect 0  
0

  ```

- [x] **5.7 The conditional-switch fix: a members-only document still applies when the ELIGIBILITY -- 2026-09-03
  read is broken.**

  This is the counterweight to 5.5. The group handler now asks for `-IncludeOwners` and
  `-IncludePimEligibility` only when the document entry actually declares `owners`, `eligibility` or
  `pimPolicy`, so a broken eligibility read must NOT block a members-only document. Route A
  (`PrivilegedEligibilitySchedule.Read.AzureADGroup` withheld), applying:

  ```json
  { "version": "1.0",
    "groups": [ { "displayName": "oer-fr-grp", "members": [ "person1@example.com" ] } ] }
  ```

  ```powershell
  # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute A
  Connect-Fr -As Narrow
  $MDoc = @'
{ "version": "1.0",
  "groups": [ { "displayName": "oer-fr-grp", "members": [ "person4@example.com" ] } ] }
'@
  $R = Invoke-OERStructure -Json $MDoc -Include Groups
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  @($R | Where-Object Action -eq 'Failed').Count                        # expect 0
  ```

  **Expect:** the member reconciles normally -- an `Unchanged` row if already a member, an
  `Updated` row if not -- and ZERO `Failed` rows. The eligibility read was never issued.
  **Failure looks like:** a `Failed` row about reading the group -- the handler is still asking for
  a collection this document cannot consume, and one broken permission is blocking unrelated work.

  *UNRUN (2026-09-02): the route was never switched. `oer-fr-narrow` still held both
  `PrivilegedEligibilitySchedule.*` roles, so route A was not in force, and the `Failed` count of
  `1` below is NOT the failure this check is written against -- the row is the generic
  `groups (item) Failed handler error: Authorization_RequestDenied ...` from the outer per-item
  catch, the same defective row as in 5.5, produced under whatever consent was actually live. This
  check asserts the ABSENCE of a failure, so a stray failure from an unrelated cause makes it
  unreadable rather than red. Must be re-run after an actual consent switch to route A.*
  **Result:**
  ```powershell
> # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute A  
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
Token roles (Narrow, 15): AccessReview.Read.All, AccessReview.ReadWrite.All, AdministrativeUnit.Read.All, AdministrativeUnit.ReadWrite.All, AuthenticationContext.Read.All, Directory.Read.All, EntitlementManagement.Read.All, EntitlementManagement.ReadWrite.All, Group.Read.All, Group.ReadWrite.All, Member.Read.Hidden, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory, RoleManagementPolicy.Read.AzureADGroup, RoleManagementPolicy.ReadWrite.AzureADGroup
> $MDoc = @'  
> { "version": "1.0",  
> "groups": [ { "displayName": "oer-fr-grp", "members": [ "person4@example.com" ] } ] }  
> '@  
> $R = Invoke-OERStructure -Json $MDoc -Include Groups  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Add member '00000000-0000-0000-0000-000000000031'" on target "oer-fr-grp".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  Y
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-fr-grp Unchanged group properties match  
groups oer-fr-grp Updated added member 'person4@example.com'  
groups oer-fr-grp Extra undeclared member '00000000-0000-0000-0000-000000000029' (use -Prune to remove)  
groups oer-fr-grp Extra undeclared member '00000000-0000-0000-0000-000000000030' (use -Prune to remove)  
  
> @($R | Where-Object Action -eq 'Failed').Count # expect 0  
0  
>
  ```

- [x] **5.8 The narrowing fix: a pimPolicy-only document still applies when the ELIGIBILITY -- 2026-09-02
  read is broken.**

  This is the case commit 278f2e3 actually fixed, and it is not the same as 5.7. The handler used
  to also request `-IncludePimEligibility` when the entry declared `pimPolicy`, but Step 4's
  pimPolicy reconciliation reads live state solely through `Get-OERGroupPimPolicy` and never
  consults the eligibility collection -- so a document declaring only `pimPolicy` was requesting a
  collection it could not consume. Before the fix, a denied read on that unused collection failed
  the WHOLE item, including property and member reconciliation, for a document that applies cleanly
  today. Still route A (`PrivilegedEligibilitySchedule.Read.AzureADGroup` withheld) -- `oer-fr-narrow`
  is already consented for it from 5.7. Applying:

  ```json
  { "version": "1.0",
    "groups": [ { "displayName": "oer-fr-grp",
      "pimPolicy": { "member": { "activationMaxHours": 4 } } } ] }
  ```

  **This check WRITES to the tenant** -- it reconciles a real PIM policy rule on `oer-fr-grp`. T.1
  restores it.

  ```powershell
  Connect-Fr -As Full
  Get-OERGroupPimPolicy -Group 'oer-fr-grp' -AccessType member | Format-List   # record the BEFORE state for T.1
  Connect-Fr -As Narrow    # route A still
  $PimDoc = @'
{ "version": "1.0",
  "groups": [ { "displayName": "oer-fr-grp",
    "pimPolicy": { "member": { "activationMaxHours": 4 } } } ] }
'@
  $R = Invoke-OERStructure -Json $PimDoc -Include Groups
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  @($R | Where-Object Action -eq 'Failed').Count                        # expect 0
  ```

  `oer-fr-grp` was never onboarded to PIM for Groups. **Record** what the policy read answers for a
  non-onboarded group; if it fails for that reason rather than for eligibility, say so.

  **Expect:** the pimPolicy reconciles normally -- an `Unchanged` row if it already matches, an
  `Updated` row if it does not -- and ZERO `Failed` rows for `oer-fr-grp`. The eligibility read was
  never issued.
  **Failure looks like:** a `Failed` row reading `failed to read the current state of group
  'oer-fr-grp': ...` -- the handler is still requesting a collection this document never mentioned.

  *Record (2026-09-02): the headline holds -- ZERO `Failed` rows, and the pimPolicy reconciled with
  `Updated pimPolicy (member) set: activationMaxHours=4`, alongside an `Unchanged` properties row
  and two `Extra` member rows. Two qualifications. First, the policy read the check asks about
  answered normally for `oer-fr-grp` even though it was never onboarded to PIM for Groups -- the
  BEFORE readback returned a full policy with `ActivationMaxHours : 8`, so the non-onboarded case
  the Record asks about did not arise. Second, and this is what the tick does NOT cover: the
  eligibility read was never actually broken, since `oer-fr-narrow` still held both
  `PrivilegedEligibilitySchedule.*` roles. What is proven is that a pimPolicy-only document applies
  cleanly; what is NOT proven is that it still applies when the eligibility read is denied, which is
  the whole point of the narrowing fix in commit 278f2e3. Re-run on a genuine route A.
  **This check WROTE to the tenant and the write stands:** `ActivationMaxHours` on `oer-fr-grp`'s
  member policy went 8 -> 4, and T.1 must put back 8.*
  **Result:**
  ```powershell
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
> Get-OERGroupPimPolicy -Group 'oer-fr-grp' -AccessType member | Format-List # record the BEFORE state for T.1  
  
GroupId : 00000000-0000-0000-0000-000000000006  
PolicyId : Group_00000000-0000-0000-0000-000000000006_00000000-0000-0000-0000-000000000024  
AccessType : member  
ActivationMaxHours : 8  
AuthenticationContextId :  
ActivationEnabledRules : {Justification}  
AllowPermanentEligibility : False  
EligibleDuration : P365D  
EligibleDurationDays : 365  
AllowPermanentActive : False  
ActiveDuration : P180D  
ActiveDurationDays : 180  
ActiveEnabledRules : {Justification}  
Notifications : @{EligibleAlert=System.Object[]; ActiveAlert=System.Object[]; ActivationAlert=System.Object[]}  
Rules : {Expiration_Admin_Eligibility, Enablement_Admin_Eligibility, Notification_Admin_Admin_Eligibility, Notification_Requestor_Admin_Eligibility...}  
  
> Connect-Fr -As Narrow # route A still  
Client secret for Narrow: ****************************************  
> $PimDoc = @'  
> { "version": "1.0",  
> "groups": [ { "displayName": "oer-fr-grp",  
> "pimPolicy": { "member": { "activationMaxHours": 4 } } } ] }  
> '@  
> $R = Invoke-OERStructure -Json $PimDoc -Include Groups  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Set PIM policy (member): activationMaxHours=4" on target "oer-fr-grp".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
groups oer-fr-grp Unchanged group properties match  
groups oer-fr-grp Extra undeclared member '00000000-0000-0000-0000-000000000016' (use -Prune to remove)  
groups oer-fr-grp Extra undeclared member '00000000-0000-0000-0000-000000000018' (use -Prune to remove)  
groups oer-fr-grp Updated pimPolicy (member) set: activationMaxHours=4  
  
> @($R | Where-Object Action -eq 'Failed').Count # expect 0  
0
  ```

- [x] **5.9 The AU twin: `"scopedRoles": null` lets a members-only apply proceed on route B.** -- 2026-09-02

  With `RoleManagement.Read.Directory` still withheld, apply:

  ```json
  { "version": "1.0",
    "administrativeUnits": [ { "displayName": "oer-fr-au", "scopedRoles": null,
      "members": [ "person1@example.com" ] } ] }
  ```

  ```powershell
  # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute B
  Connect-Fr -As Narrow
  # The member is given as an OBJECT ID: route B withholds Directory.Read.All, and the narrow set
  # holds no User.Read.All either, so a UPN cannot be resolved -- that would be a resolve failure,
  # not the scoped-role read this check is about.
  $AuNull = @'
{ "version": "1.0",
  "administrativeUnits": [ { "displayName": "oer-fr-au", "scopedRoles": null,
    "members": [ "00000000-0000-0000-0000-000000000016" ] } ] }
'@
  $R = Invoke-OERStructure -Json $AuNull -Include AdministrativeUnits
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  @($R | Where-Object Action -eq 'Failed').Count                        # expect 0

  # The contrast: same document with the scopedRoles key REMOVED.
  $AuAbsent = @'
{ "version": "1.0",
  "administrativeUnits": [ { "displayName": "oer-fr-au",
    "members": [ "00000000-0000-0000-0000-000000000016" ] } ] }
'@
  $R = Invoke-OERStructure -Json $AuAbsent -Include AdministrativeUnits
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  ($R | Where-Object Action -eq 'Failed').Detail                        # expect the Failed row back

  Connect-Fr -As Full
  (Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles).ScopedRoles |
      Select-Object RoleName, PrincipalId                               # still there
  ```

  **Expect:** the member reconciles, ZERO `Failed` rows, and the live scoped role untouched. An
  EXPLICIT null is the only thing that lets the scoped-role read be skipped here -- an ABSENT
  `scopedRoles` key still runs the prune pass and therefore still needs the read, so repeat this
  check with the key removed and **expect** the `Failed` row to come back. That contrast is the
  point. **Result:**
  ```powershell
 > # .\Initialize-OerFrPrereq.ps1 -SkipObjects -NarrowRoute B  
> Connect-Fr -As Narrow  
Client secret for Narrow: ****************************************  
> # The member is given as an OBJECT ID: route B withholds Directory.Read.All, and the narrow set  
> # holds no User.Read.All either, so a UPN cannot be resolved -- that would be a resolve failure,  
> # not the scoped-role read this check is about.  
> $AuNull = @'  
> { "version": "1.0",  
> "administrativeUnits": [ { "displayName": "oer-fr-au", "scopedRoles": null,  
> "members": [ "00000000-0000-0000-0000-000000000016" ] } ] }  
> '@  
> $R = Invoke-OERStructure -Json $AuNull -Include AdministrativeUnits  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
administrativeUnits oer-fr-au Unchanged administrative unit properties match  
administrativeUnits oer-fr-au Unchanged member '00000000-0000-0000-0000-000000000016' already present  
  
> @($R | Where-Object Action -eq 'Failed').Count # expect 0  
0   
>  
> # The contrast: same document with the scopedRoles key REMOVED.  
> $AuAbsent = @'  
> { "version": "1.0",  
> "administrativeUnits": [ { "displayName": "oer-fr-au",  
> "members": [ "00000000-0000-0000-0000-000000000016" ] } ] }  
> '@  
> $R = Invoke-OERStructure -Json $AuAbsent -Include AdministrativeUnits
Invoke-OERStructure: Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorization_RequestDenied: Insufficient privileges to complete the operation.. The ScopedRoles property is omitted rather than reported as empty
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
administrativeUnits oer-fr-au Failed failed to read the current state of administrative unit 'oer-fr-au': Could not read scoped roles for administrative unit 00000000-0000-0000-0000-000000000009: Authorizati...
>  
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
> (Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au' -IncludeScopedRoles).ScopedRoles |  
> Select-Object RoleName, PrincipalId # still there  
  
RoleName PrincipalId  
-------- -----------  
User Administrator 00000000-0000-0000-0000-000000000016
  ```

---

### 6. An explicit `null` behaves exactly like an omitted key (checks 6.x)

Run as `oer-fr-full`. These are the four sites where a declared null used to be treated as a
declared VALUE rather than as "not declared".

- [x] **6.1 `"recurrence": null` creates a one-time review, not a validation failure.** -- 2026-09-02

  Apply a document declaring an access review that does NOT yet exist, with an explicit null
  recurrence:

  ```json
  { "version": "1.0",
    "accessReviews": [ { "displayName": "oer-fr-null-recurrence", "recurrence": null,
      "accessPackage": "oer-fr-ap", "catalog": "OER-FR-CAT", "reviewers": [ "./manager" ] } ] }
  ```

  The schema requires `assignmentPolicy` on every access review, and a `manager` reviewer requires
  `fallbackReviewers`, so the runnable form names the policy and a user reviewer:

  ```powershell
  Connect-Fr -As Full
  $Ar1 = @'
{ "version": "1.0",
  "accessReviews": [ { "displayName": "oer-fr-null-recurrence", "recurrence": null,
    "accessPackage": "oer-fr-ap", "assignmentPolicy": "oer-fr-policy", "catalog": "OER-FR-CAT",
    "reviewers": [ "person1@example.com" ] } ] }
'@
  # Errors holds findings of EVERY severity; Valid is Error-severity only. Count them separately or
  # the two columns contradict each other -- see the note at check 3.12.
  Test-OERStructure -Json $Ar1 |
      Select-Object Valid,
          @{ n = 'ErrorCount';   e = { @($_.Errors | Where-Object Severity -eq 'Error').Count } },
          @{ n = 'WarningCount'; e = { @($_.Errors | Where-Object Severity -eq 'Warning').Count } }
  $R = Invoke-OERStructure -Json $Ar1 -Include AccessReviews
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessReviewDefinition -DisplayName 'oer-fr-null-recurrence' | Select-Object DisplayName, Recurrence, DurationInDays, Status
  ```

  **Expect:** `Valid` `True` with `ErrorCount` `0`, a `Created` row, and the review created as a
  ONE-TIME review. `WarningCount` is recorded, not asserted.
  **Failure looks like:** a `Failed` row reading `unrecognised recurrence value ''` -- the old
  behaviour, where a declared null reached the recurrence validator as an empty value.

  *Record (2026-09-02): passed. `Valid True`, `Created ... (recurrence: OneTime)`, and the readback
  shows the recurrence `pattern` empty, which is what a one-time review looks like. The run used
  the old `@($_.Errors).Count` form and printed `Errors 0`; it agreed here since there were no
  warnings, but see 6.4 for the case where the same form printed `Valid True / Errors 1` and read
  as a contradiction.*
  **Result:**
  ```powershell
> Connect-Fr -As Full  
Client secret for Full: ****************************************  
> $Ar1 = @'  
> { "version": "1.0",  
> "accessReviews": [ { "displayName": "oer-fr-null-recurrence", "recurrence": null,  
> "accessPackage": "oer-fr-ap", "assignmentPolicy": "oer-fr-policy", "catalog": "OER-FR-CAT",  
> "reviewers": [ "person1@example.com" ] } ] }  
> '@  
> Test-OERStructure -Json $Ar1 | Select-Object Valid, @{ n = 'Errors'; e = { @($_.Errors).Count } }  
  
Valid Errors  
----- ------  
True 0  
  
> $R = Invoke-OERStructure -Json $Ar1 -Include AccessReviews  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Create access review definition" on target "oer-fr-null-recurrence".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-fr-null-recurrence Created created access review 'oer-fr-null-recurrence' (recurrence: OneTime)  
  
> Get-OERAccessReviewDefinition -DisplayName 'oer-fr-null-recurrence' | Select-Object DisplayName, Recurrence, DurationInDays, Status  
  
DisplayName Recurrence DurationInDays Status  
----------- ---------- -------------- ------  
oer-fr-null-recurrence {[range, System.Collections.Hashtable], [pattern, ]} 0 Initializing
  ```

- [x] **6.2 The omitted-key control produces the identical result.** -- 2026-09-02

  ```powershell
  $Ar2 = @'
{ "version": "1.0",
  "accessReviews": [ { "displayName": "oer-fr-omitted-recurrence",
    "accessPackage": "oer-fr-ap", "assignmentPolicy": "oer-fr-policy", "catalog": "OER-FR-CAT",
    "reviewers": [ "person1@example.com" ] } ] }
'@
  $R = Invoke-OERStructure -Json $Ar2 -Include AccessReviews
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessReviewDefinition -DisplayName 'oer-fr-omitted-recurrence' | Select-Object DisplayName, Recurrence, DurationInDays, Status
  ```

  Apply the same document with the `recurrence` key REMOVED entirely, under a different display
  name. **Expect:** a `Created` row and a one-time review -- behaviour identical to 6.1. That
  equivalence is the whole point of routing the check through its single owner rather than
  re-implementing it inline. **Result:**
  ```powershell
> $Ar2 = @'  
> { "version": "1.0",  
> "accessReviews": [ { "displayName": "oer-fr-omitted-recurrence",  
> "accessPackage": "oer-fr-ap", "assignmentPolicy": "oer-fr-policy", "catalog": "OER-FR-CAT",  
> "reviewers": [ "person1@example.com" ] } ] }  
> '@   
> $R = Invoke-OERStructure -Json $Ar2 -Include AccessReviews  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Create access review definition" on target "oer-fr-omitted-recurrence".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-fr-omitted-recurrence Created created access review 'oer-fr-omitted-recurrence' (recurrence: OneTime)  
  
> Get-OERAccessReviewDefinition -DisplayName 'oer-fr-omitted-recurrence' | Select-Object DisplayName, Recurrence, DurationInDays, Status  
  
DisplayName Recurrence DurationInDays Status  
----------- ---------- -------------- ------  
oer-fr-omitted-recurrence {[range, System.Collections.Hashtable], [pattern, ]} 0 NotStarted
  ```

- [x] **6.3 `"recurrence": null` does NOT downgrade a live quarterly cadence on an unrelated update.** -- 2026-09-02

  `oer-fr-review` is quarterly. Apply a document that changes only `durationInDays` while carrying
  an explicit null recurrence:

  ```json
  { "version": "1.0",
    "accessReviews": [ { "displayName": "oer-fr-review", "recurrence": null, "durationInDays": 7,
      "accessPackage": "oer-fr-ap", "catalog": "OER-FR-CAT" } ] }
  ```

  ```powershell
  Get-OERAccessReviewDefinition -DisplayName 'oer-fr-review' | Select-Object Recurrence, DurationInDays   # BEFORE: Quarterly / 14
  $Ar3 = @'
{ "version": "1.0",
  "accessReviews": [ { "displayName": "oer-fr-review", "recurrence": null, "durationInDays": 7,
    "accessPackage": "oer-fr-ap", "assignmentPolicy": "oer-fr-policy", "catalog": "OER-FR-CAT" } ] }
'@
  $R = Invoke-OERStructure -Json $Ar3 -Include AccessReviews
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessReviewDefinition -DisplayName 'oer-fr-review' | Select-Object Recurrence, DurationInDays   # AFTER: Quarterly / 7
  ```

  **Expect:** an `Updated` row naming `durationInDays` only, and the review still QUARTERLY in the
  portal afterwards. **Failure looks like:** the cadence silently changed to one-time. This is the
  sharpest regression in section 6 -- a review that quietly stops recurring is not visible in any
  result row -- so check the portal, not just the output.

  *Record (2026-09-02): the headline holds -- one `Updated` row naming `durationInDays=7` only, and
  the AFTER readback still shows a populated recurrence `pattern`, so the cadence survived. **The
  BEFORE readback was never run**, so "Quarterly / 14" is taken from the setup table rather than
  observed on the day, and the before/after comparison this check is built on is one-sided. Re-run
  with the first line included. The AFTER state is also not raw enough to read the cadence off
  directly -- `Recurrence` prints as a nested hashtable, so a populated `pattern` is the tell, and
  the portal was the intended confirmation. **This check WROTE to the tenant and the write stands:**
  `oer-fr-review` `DurationInDays` went 14 -> 7, and T.1 must put back 14.*
  **Result:**
  ```powershell
> $Ar3 = @'  
> { "version": "1.0",  
> "accessReviews": [ { "displayName": "oer-fr-review", "recurrence": null, "durationInDays": 7,  
> "accessPackage": "oer-fr-ap", "assignmentPolicy": "oer-fr-policy", "catalog": "OER-FR-CAT" } ] }  
> '@  
> $R = Invoke-OERStructure -Json $Ar3 -Include AccessReviews  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Update access review definition" on target "oer-fr-review".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
  
Section Item Action Detail  
------- ---- ------ ------  
accessReviews oer-fr-review Updated updated access review 'oer-fr-review' (durationInDays=7)  
  
> Get-OERAccessReviewDefinition -DisplayName 'oer-fr-review' | Select-Object Recurrence, DurationInDays # AFTER: Quarterly / 7  
  
Recurrence DurationInDays  
---------- --------------  
{[range, System.Collections.Hashtable], [pattern, System.Collections.Hashtable]} 7
  ```

- [x] **6.4 A null `requestorScope` field falls back to the default rather than binding a -- 2026-09-02
  one-element null array.**

  **This check WRITES to the tenant** -- it creates or updates a real assignment policy and its
  requestor scope. T.1 restores it. On `oer-fr-ap`, apply an assignment policy declaring
  `"requestorScope": { "scope": "SpecificDirectoryUsers", "users": null, "groups": null }`.

  The policy is declared under a NEW name, `oer-fr-policy-64`, so `oer-fr-policy` (which
  `oer-fr-review` hangs off) is never touched; T.1 deletes it.

  ```powershell
  $Ap4a = @'
{ "version": "1.0",
  "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",
    "assignmentPolicies": [ { "displayName": "oer-fr-policy-64",
      "requestorScope": { "scope": "SpecificDirectoryUsers", "users": null, "groups": null } } ] } ] }
'@
  # Errors holds findings of EVERY severity; Valid is Error-severity only -- see the note at 3.12.
  # $Ap4a is exactly the case that makes the difference visible: it validates, and still carries one
  # Warning-severity finding.
  Test-OERStructure -Json $Ap4a |
      Select-Object Valid,
          @{ n = 'ErrorCount';   e = { @($_.Errors | Where-Object Severity -eq 'Error').Count } },
          @{ n = 'WarningCount'; e = { @($_.Errors | Where-Object Severity -eq 'Warning').Count } }
  $R = Invoke-OERStructure -Json $Ap4a -Include AccessPackages
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-fr-ap' |
      Where-Object DisplayName -eq 'oer-fr-policy-64' | Select-Object DisplayName, RequestorScope | Format-List

  $Ap4b = @'
{ "version": "1.0",
  "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",
    "assignmentPolicies": [ { "displayName": "oer-fr-policy-64",
      "requestorScope": { "scope": null } } ] } ] }
'@
  # RECORD: does the offline validator take a null scope? (It does not -- see the Expect below.)
  Test-OERStructure -Json $Ap4b |
      Select-Object Valid,
          @{ n = 'ErrorCount';   e = { @($_.Errors | Where-Object Severity -eq 'Error').Count } },
          @{ n = 'WarningCount'; e = { @($_.Errors | Where-Object Severity -eq 'Warning').Count } }
  $R = Invoke-OERStructure -Json $Ap4b -Include AccessPackages
  $R | Format-Table Section, Item, Action, Detail -AutoSize
  Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-fr-ap' |
      Where-Object DisplayName -eq 'oer-fr-policy-64' | Select-Object DisplayName, RequestorScope | Format-List
  ```

  **Expect, part A (`$Ap4a`, null `users` / `groups` under a named scope):** `Valid` `True` with
  `ErrorCount` `0`, the policy is created or updated, and its requestor scope is set without error;
  no request carries an array holding a single null. `WarningCount` `1` is expected and correct
  here -- the document names a catalog it does not itself declare -- and it is precisely why this
  check counts severities separately.

  **Expect, part B (`$Ap4b`, a null `scope`): the document is REJECTED by `Test-OERStructure`, and
  `Invoke-OERStructure` never reaches the handler.** `Valid` is `False`, and the apply fails with
  `Structure document failed validation: accessPackages[0].assignmentPolicies[0].requestorScope.scope:
  'requestorScope.scope' ... must be a non-empty string.` An earlier draft of this check expected
  the null to fall back to All member users; that is wrong. `schema.json` types
  `requestorScope.scope` as a non-empty string, and a declared null is a value that fails that type
  -- **the fallback holds only for an ABSENT `scope` key**, where nothing is declared for the
  handler to read. The live policy must be unchanged afterwards, still carrying the scope part A
  set. **Failure looks like:** the apply proceeding past validation, or the live scope changing.
  A `Failed` row from the ValidateSet on `-Scope`, or a scope naming an unresolvable principal,
  would also be failures -- but of part A, not part B.

  *Record (2026-09-02): both parts behaved as now written. Part A: `Valid True`, one
  Warning-severity finding (printed as the contradictory-looking `Valid True / Errors 1` by the old
  single-count form), `Created assignmentPolicy 'oer-fr-policy-64'`, and the readback shows
  `scope=SpecificDirectoryUsers` with empty `users` and `groups` arrays -- no single-null array
  anywhere. Part B: `Valid False`, and the apply refused with the validation message quoted above,
  leaving the live policy exactly as part A left it. The old Expect was the defect, not the module.
  **This check WROTE to the tenant and the write stands:** `oer-fr-policy-64` exists on `oer-fr-ap`
  with a live `SpecificDirectoryUsers` requestor scope, and T.1 must delete it.*
  **Result:**
  ```powershell
> $Ap4a = @'  
> { "version": "1.0",  
> "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",  
> "assignmentPolicies": [ { "displayName": "oer-fr-policy-64",  
> "requestorScope": { "scope": "SpecificDirectoryUsers", "users": null, "groups": null } } ] } ]  
> '@  
> Test-OERStructure -Json $Ap4a | Select-Object Valid, @{ n = 'Errors'; e = { @($_.Errors).Count } }  
  
Valid Errors  
----- ------  
True 1  
  
> $R = Invoke-OERStructure -Json $Ap4a -Include AccessPackages  
  
Confirm  
Are you sure you want to perform this action?  
Performing the operation "Create assignmentPolicy 'oer-fr-policy-64'" on target "oer-fr-ap".  
[Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Y"):  
> $R | Format-Table Section, Item, Action, Detail -AutoSize
Section Item Action Detail  
------- ---- ------ ------  
accessPackages oer-fr-ap Unchanged access package properties match  
accessPackages oer-fr-ap Extra undeclared resourceRole binding 'Member|00000000-0000-0000-0000-000000000006' (use -Prune to remove)  
accessPackages oer-fr-ap Created created assignmentPolicy 'oer-fr-policy-64'  
accessPackages oer-fr-ap Extra undeclared assignmentPolicy 'oer-fr-policy' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)
> Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-fr-ap' |  
> Where-Object DisplayName -eq 'oer-fr-policy-64' | Select-Object DisplayName, RequestorScope | Format-List  
  
DisplayName : oer-fr-policy-64  
RequestorScope : @{scope=SpecificDirectoryUsers; users=System.Object[]; groups=System.Object[]}  
   
>  
> $Ap4b = @'  
> { "version": "1.0",  
> "accessPackages": [ { "displayName": "oer-fr-ap", "catalog": "OER-FR-CAT",  
> "assignmentPolicies": [ { "displayName": "oer-fr-policy-64",  
> "requestorScope": { "scope": null } } ] } ] }  
> '@  
> Test-OERStructure -Json $Ap4b | Select-Object Valid, @{ n = 'Errors'; e = { @($_.Errors).Count } } # RECORD: does the offline validator take a null scope?  
  
Valid Errors  
----- ------  
False 2  
  
> $R = Invoke-OERStructure -Json $Ap4b -Include AccessPackages
Invoke-OERStructure: Structure document failed validation: accessPackages[0].assignmentPolicies[0].requestorScope.scope: 'requestorScope.scope' at accessPackages[0].assignmentPolicies[0] must be a non-empty string.
> $R | Format-Table Section, Item, Action, Detail -AutoSize  
> Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-fr-ap' |  
> Where-Object DisplayName -eq 'oer-fr-policy-64' | Select-Object DisplayName, RequestorScope | Format-List  
  
DisplayName : oer-fr-policy-64  
RequestorScope : @{scope=SpecificDirectoryUsers; users=System.Object[]; groups=System.Object[]}
  ```

---

### 7. What this checklist does NOT prove

No boxes here. This section is a statement of limits and is part of the deliverable: it is what
lets a later reader tell a verified claim from an assumed one.

1. **The throttle form is deliberately unproven.** No check above provokes a 429, and none is meant
   to. Section 0 gives the arithmetic: roughly 2 requests per second against a bucket of roughly 350
   per second means the module cannot reach the limit on a small tenant, and PR #77's live run
   measured exactly that (`Throttled at all: False`, over two evenings). What IS proven here is that
   the catch a throttled read would take now omits the property and reports the error. What is NOT
   proven is the shape of a live Graph 429 arriving at that catch -- that is the subject of PR #77
   and `docs/live-verification/fix-graph-retry-after-checklist.md`, whose sections 3-8 remain unrun
   for the same reason.

1b. **Route A IS proven, but not by the check written for it (2026-09-03).** With both
   `PrivilegedEligibilitySchedule.*` application permissions verifiably absent from the token, ten
   PIM-onboarded groups answered `PermissionScopeNotGranted` during check 3.13's inventory run and
   had their `eligibility` key OMITTED -- a path reachable only when the module's own
   `GroupPimEligibilityReadFailed` catch fired. `GroupPimEligibilityReadFailed` and the omitted
   `eligibility` key therefore have live proof, and 3.13 is ticked on it. What is NOT proven is the
   cmdlet-level shape check 1.8 asks for, because 1.8 was run against `oer-fr-grp`, whose
   eligibility read returns 200 with an empty `value` under the same token even after PIM
   onboarding; 1.8 stays unticked until it is re-run against one of the ten. Why that one group is
   answered differently is undetermined -- Learn documents no alternative permission for the
   endpoint -- and finding out is follow-up work.

2. **Routes C and D may turn out not to be provokable at all.** If checks 1.1 and 2.1 recorded "came
   back empty", then `GroupMemberReadFailed` and `AdministrativeUnitMemberReadFailed` are proven
   only by unit test on this branch, and `groups[].members` -- the exact key issue #76 was reported
   against -- has no live proof. Route B proves the identical code path on `scopedRoles`, which is a
   strong inference and not a substitute. Say plainly which one you got.

   **`groups[].members` IS provable, but only on both conditions at once:** route D against a
   Microsoft 365 group created hidden from the start -- no security group can ever be hidden -- AND
   an explicit `-GroupFilter` on every inventory check, since the default `securityEnabled eq true`
   excludes that group by construction. Miss either one and the key cannot be proven at all, which
   is exactly what happened on 2026-09-02: the narrow app kept `Member.Read.Hidden`, and 3.11 read a
   default bundle export that could not contain the group. The roster's own `memberCount` join in
   `groupsRoster.json` stays unreachable live under any route (see 3.11) and is covered by unit test
   only.

   *After the 2026-09-02 run this is where things stand, for a third reason the paragraph did not
   anticipate: routes C and D were never NARROWED, so neither "denied" nor "empty" was established.
   `GroupMemberReadFailed`, `GroupOwnerReadFailed` and `AdministrativeUnitMemberReadFailed` have no
   live proof at all, and neither does `groups[].members` end to end (4.4).*

2b. **Routes C and D are UNUSABLE on this tenant -- settled on 2026-09-03, and this is the largest
   gap in the file.** The question the paragraph above leaves open is now answered: EMPTY, not
   denied. Both routes were genuinely narrowed this time, which the earlier run never managed, and
   both still returned data:

   - **Route C (check 2.1, and 2.4 which depends on it).** `oer-fr-au-c` was created hidden with
     `New-OERAdministrativeUnit -HiddenMembership`, and the narrow token verifiably lacked
     `Member.Read.Hidden` -- `Token roles (Narrow, 16)` against `Token roles (Full, 17)`, which
     carries it. `Get-OERAdministrativeUnit -IncludeMembers` answered `Members present = True` with
     no error record and a blank `FullyQualifiedErrorId`.
   - **Route D (check 5.5).** Same 16-role token, applying a members document against the hidden
     Microsoft 365 group `oer-fr-hidden`. The plan came back
     `Unchanged member ... already present` plus three `Extra` undeclared-member rows, and
     `($R | Where-Object Action -eq 'Failed').Detail` printed nothing. The group's live membership
     was read in full by a caller without `Member.Read.Hidden`.

   Consequently **`GroupMemberReadFailed`, `GroupOwnerReadFailed` and
   `AdministrativeUnitMemberReadFailed` have NO live proof on this branch** -- they are covered by
   unit test only -- and **`groups[].members`, the exact key issue #76 was filed against, is not
   verified end to end** (4.4 and 3.11 both stand unticked for this reason). Route B proves the
   identical catch shape, the identical `null` projection and the identical prune behaviour on
   `administrativeUnits[].scopedRoles`, which is a strong inference from shared code and is not a
   substitute for observing the member path itself.

   Finding a working provocation for those three is FOLLOW-UP WORK and is not attempted here.
   Candidates, none of them tried: a hidden-membership object in a tenant where the app is not
   otherwise privileged; a different denial than `Member.Read.Hidden` on the `/members` endpoint;
   or an injected transport failure. Until one of them lands, do not describe `groups[].members` as
   live-verified.

3. **A 5xx, a dead transport, and a token that expires mid-enumeration are not exercised.** They
   reach the same catch by inspection, not by observation here.

4. **Nothing here measures behaviour at scale.** The `Causes:` clause deduplicates by DISTINCT
   message, so a transport that embeds the object id in its message will not dedupe, and a 200-group
   partial export could produce a very long clause. Check 3.5 records which form this tenant
   produces over two objects; it does not tell you what 200 look like.

5. **Only checks 4.5, 5.4, 5.8 and section 6 write to the tenant.** Everything else is a read or a
   `-WhatIf`. The teardown below assumes that split; if you ran anything else for real, add it to
   T.1.

   *In the 2026-09-02 run, 5.4's write was NOT taken -- it stopped at the plan -- so the writes
   that stand from that run are 5.8, 6.1, 6.2, 6.3 and 6.4. Check 3.5's setup also added a second
   scoped role, which T.1 already removes.*

   *The 2026-09-03 re-run added THREE more writes the split above did not anticipate, and all three
   still stand: check 2.1 CREATED the administrative unit `oer-fr-au-c` (T.2, corrected below);
   check 1.8 added a member eligibility on `oer-fr-grp` and, with it, opened that group's member
   PIM policy for permanent eligibility (T.1); and check 5.7 ADDED a real member to `oer-fr-grp`
   -- it answered `Y` to the `Add member` confirmation and returned
   `Updated added member 'person4@example.com'` (T.1b, added below).*

6. **Nine records still reach the caller for one failed read; none of them renders a bearer token
   any more.** Check 2.7 shows the pre-fix state, with the token rendered in full from the
   `HttpRequestMessage` behind one record's `TargetObject`. Check 2.8 is the guard, and it ran green
   on 2026-09-03: `0 rendering a token` from both the caller's `-ErrorVariable` (9 records) and
   `$global:Error` (1 record). The surplus of eight foreign records is unchanged and is a separate,
   still-open finding (2.6) -- noise, not disclosure. Both were measured on route B only.

---

### Teardown
**Teardown has NOT been run.** It was deliberately deferred until the run's findings had been
reviewed, and that review is what produced the corrections in this file. Every box below is still
open and the tenant is still dirty -- see "State of this run" at the top for the list of writes that
stand.
- [ ] **T.1 Restore what the write checks changed.**

  Re-create any resource-role binding removed by check 5.4; restore the `member` pimPolicy on
  `oer-fr-grp` to whatever it was before if check 5.8 reported an `Updated` row (no undo needed if
  it reported `Unchanged`); restore `oer-fr-review`'s cadence and duration if check 6.3 changed
  them; delete the reviews created by 6.1 and 6.2; and restore the assignment policy on `oer-fr-ap`
  that check 6.4 created or updated -- 6.4 writes a real `requestorScope`, so put the scope back to
  whatever it was before, or delete the policy if 6.4 created it. Check 4.5 also writes, but by
  design it changes nothing, so it needs no undo unless its result line says otherwise.
  ```powershell
  Connect-Fr -As Full
  # 3.5  -- the second scoped role
  Remove-OERAdministrativeUnitScopedRole -AdministrativeUnit 'oer-fr-au-b' -RoleName 'User Administrator' -User 'person2@example.com'
  # 1.8  -- the eligibility added on 2026-09-03 to onboard the group (and check the member policy:
  #         Add-OERGroupEligibility opened it for permanent eligibility)
  Remove-OERGroupEligibility -Group 'oer-fr-grp' -User 'person2@example.com' -AccessType member
  Get-OERGroupPimPolicy -Group 'oer-fr-grp' -AccessType member | Select-Object ActivationMaxHours, AllowPermanentEligibility
  # 5.4  -- only if the prune ran for real
  Add-OERAccessPackageResourceRole -AccessPackage 'oer-fr-ap' -Catalog 'OER-FR-CAT' -Group 'oer-fr-grp' -Role 'Member'
  # 5.8  -- only if it reported Updated; put back the BEFORE value you recorded.
  #         The 2026-09-02 run DID report Updated: the BEFORE value it read back was 8.
  Set-OERGroupPimPolicy -Group 'oer-fr-grp' -AccessType member -ActivationMaxHours 8
  # 6.1 / 6.2
  Remove-OERAccessReviewDefinition -DisplayName 'oer-fr-null-recurrence'
  Remove-OERAccessReviewDefinition -DisplayName 'oer-fr-omitted-recurrence'
  # 6.3 -- 6.3 only changes the duration, so restore only that. (-Recurrence needs -StartDate
  #        alongside it; pass both only if the cadence itself was lost.)
  $Rv = Get-OERAccessReviewDefinition -DisplayName 'oer-fr-review'
  Set-OERAccessReviewDefinition -Id $Rv.AccessReviewDefinitionId -DurationInDays 14
  Get-OERAccessReviewDefinition -DisplayName 'oer-fr-review' | Select-Object Recurrence, DurationInDays
  # 6.4
  Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-fr-ap' |
      Where-Object DisplayName -eq 'oer-fr-policy-64' | Remove-OERAccessPackageAssignmentPolicy
  ```

  **Record:** what was changed and what was restored.
  **Result:**

- [ ] **T.1b Remove the member check 5.7 added to `oer-fr-grp`.**

  Nothing above restores this and section 7's write split did not anticipate it. Check 5.7 is not a
  `-WhatIf`: on 2026-09-03 it answered `Y` to `Performing the operation "Add member ..." on target
  "oer-fr-grp"` and returned `Updated added member 'person4@example.com'`. That membership is live.

  ```powershell
  Connect-Fr -As Full
  Remove-OERGroupMember -Group 'oer-fr-grp' -User 'person4@example.com'
  Get-OERGroup -Group 'oer-fr-grp' -IncludeMembers | Select-Object -ExpandProperty Members
  ```

  **Expect:** the member is gone and the two original test users remain. Check 5.5 declared the same
  user on `oer-fr-hidden`, but that row reported `Unchanged member ... already present` -- it was
  already a member, so nothing was added there and nothing is to be removed. **Result:**

- [ ] **T.2 Delete the hidden-membership administrative unit.**

  Visibility cannot be removed from an administrative unit any more than it can be added -- see
  section 0 -- so `oer-fr-au-c` is deleted rather than restored. It exists only for route C.

  ```powershell
  Connect-Fr -As Full
  Remove-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-c'
  Get-OERAdministrativeUnit -AdministrativeUnit 'oer-fr-au-c' -ErrorAction SilentlyContinue
  ```

  **Expect:** nothing comes back. **This step IS required after the 2026-09-03 re-run.** The
  2026-09-02 note that said otherwise -- `oer-fr-au-c` was never created, and `oer-fr-au-b` was
  never made HiddenMembership because Graph refused the attempt -- was true of that run only.
  Check 2.1 was re-run on 2026-09-03 and its output shows
  `New-OERAdministrativeUnit -DisplayName 'oer-fr-au-c' -HiddenMembership` returning the created
  unit, which then appears again in 2.4 and in 3.6's `Unread:` list. The unit exists, it is hidden,
  and hidden cannot be removed -- so delete it. **Result:**

- [ ] **T.3 Restore consent on the narrow app registration, or delete it.**

  A registration left standing with a deliberately incomplete permission set is a trap for whoever
  picks it up next, and a confusing one -- it fails only on the collection reads. Prefer deleting
  `oer-fr-narrow` outright.
  `oer-fr-narrow` is the standing **Omnicit Entra RBAC Dev** registration, so restore rather than delete:

  ```powershell
  & "C:\Obsidian\Philip Obsidian\Notes\Omnicit Entra RBAC\Initialize-OerFrPrereq.ps1" -SkipObjects -NarrowRoute Full
  ```

  Then remove the `oer-fr live verification` client secrets from both registrations in the portal
  (Entra ID > App registrations > Certificates & secrets), or leave them to expire after 14 days.

  **Result:**

- [ ] **T.4 Delete the working directory.**

  ```powershell
  Get-ChildItem $Work -Recurse -File | Select-Object FullName, Length
  Remove-Item $Work -Recurse -Force
  Test-Path $Work
  ```

  **Expect:** `False`. The bundles under `$Work` carry real tenant object ids and the whole group
  roster. They were written outside the repository on purpose; delete them anyway once the results
  above are transcribed and redacted. **Result:**

- [ ] **T.5 Disconnect.**

  ```powershell
  Disconnect-OER
  ```

  **Result:**

- [ ] **T.6 What cannot be undone.**

  - The reads and the writes are in the tenant's sign-in and Graph telemetry and cannot be removed.
  - Any `inventory.json` produced during this run may UNDER-declare. If one escaped `$Work`, delete
    it: applying it later with `-Prune` is precisely the damage issue #76 describes.
  - An application permission granted and then revoked leaves an audit trail on the app
    registration, and the consent changes themselves are logged.

  **Record:** anything that fired, was alerted on, or has to be told to someone:
  **Result:**

- [ ] **T.7 Optional -- delete every `oer-fr` object.** Only once every result line above is written.

  ```powershell
  Connect-Fr -As Full
  Remove-OERAccessReviewDefinition -DisplayName 'oer-fr-review'
  Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-fr-ap' | Remove-OERAccessPackageAssignmentPolicy
  Remove-OERAccessPackage -DisplayName 'oer-fr-ap'          # fails at Graph if assignments remain
  Remove-OERCatalog -DisplayName 'OER-FR-CAT'
  'oer-fr-au', 'oer-fr-au-b' | ForEach-Object { Remove-OERAdministrativeUnit -AdministrativeUnit $_ }
  'oer-fr-grp', 'oer-fr-empty', 'oer-fr-hidden' | ForEach-Object { Remove-OERGroup -Group $_ }
  Disconnect-OER
  Connect-MgGraph -TenantId '00000000-0000-0000-0000-000000000001' -Scopes User.ReadWrite.All -NoWelcome
  'person1@example.com', 'person2@example.com' | ForEach-Object { Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$_" }
  Disconnect-MgGraph
  ```

  **Result:**