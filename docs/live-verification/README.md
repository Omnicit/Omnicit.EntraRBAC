# Live verification checklists

This folder holds the live-verification checklists for this module. Each one is written while a
branch is in flight and is then run BY HAND, by Philip, against a real Entra ID tenant. Nothing in
CI and nothing Claude runs ever authenticates -- the module carries Global-Admin-class privilege
across customer tenants, so a live run is always a deliberate human act. The checklists record what
was actually executed and what came back, which is what lets a later reader tell a verified claim
from an assumed one.

That also makes this folder the one place in the repository where live tenant console output is
pasted in on purpose. The rules below exist so the output can be kept without keeping the tenant
data inside it.

## Editing rule -- redact before you commit

Before a checklist is committed, every tenant identifier pasted from console output is replaced with
a placeholder:

- **Object ids** become `00000000-0000-0000-0000-0000000000NN`. `NN` counts up from `01` per
  DISTINCT identifier, in first-appearance order, and restarts in each file. The same identifier
  always gets the same placeholder within a file. If it does not, the checklist's own traceability
  breaks: several checks turn on two ids being the same, or on two ids differing.
- **An abbreviated id** in console output -- the `abcd1234-...` form some views print -- is redacted
  too, and is written out as the FULL placeholder, not an abbreviated one. Eight hex characters of a
  real object id is still a correlatable partial identifier, and a file showing a real prefix beside
  a placeholder for the same object contradicts itself.
- **Email addresses** outside `example.com` and `contoso.com` become `person1@example.com`,
  `person2@example.com`, ... on the same per-file, first-appearance rule.
- **Credentials never go in at all -- and a credential is ROTATED, not redacted.** See the section
  below; this is the one rule here that redaction does not solve.

**Display names of test objects may stay.** A name a checklist created for its own run is not an
identifier: it is what makes the checklist readable, and it resolves to nothing outside the tenant
that no longer holds the object.

**The mapping from a real value to its placeholder is never written down in this repository.** Not
in a comment, not in a checklist appendix, not in a commit message, not in a scratch file inside the
worktree. A mapping table turns every placeholder back into the identifier it replaced, which undoes
the whole exercise. For the same reason, a real value never goes into an assertion message, a test
name, a commit message or a report -- refer to a hit by file and line number only.

## The placeholder register

Placeholders are allocated under two different rules, and confusing them is how they collide.

- **Inside a live-verification checklist**, `NN` restarts at `01` per file, as the rule above says.
  The same `NN` therefore denotes a DIFFERENT object in a different checklist, and that is fine:
  each checklist is read on its own.
- **Everywhere else** -- `source/`, `tests/`, `docs/examples/`, the issue templates -- a placeholder
  is allocated GLOBALLY and means one slot across the whole repository, because the same fixture is
  read from several files at once.

The register below is the second rule's allocation. **Its only purpose is to stop two different
objects from being given the same placeholder**, which is the defect this programme has hit more
often than any other: a redaction pass reuses a number, and from then on two unrelated objects look
like one. That is also a defect no automated gate can see. `tests/QA/dochygiene.tests.ps1` checks
that every identifier IS a placeholder; nothing in it can check that a placeholder means what the
last person thought it meant. **The unique description per row is that check.** Writing one forces
you to say what slot you are taking, and a slot that is already described is a collision you can see
before you commit.

Each row is a placeholder, a GENERIC description of the slot, and whether it is taken. **A
description says what KIND of object occupies the slot and where it is read -- never which object.**
Naming the object in clear text would rebuild the mapping this file just forbade.

| Placeholder | Slot (generic) | Status |
|---|---|---|
| `...000` - `...045` | the checklists' per-file numbering, plus the conventional "any id" stand-in in help examples and the issue template | taken, under the per-file rule |
| `...046` | a subscription id in the worked apply-document example | taken |
| `...047` | a principal id in the worked apply-document example | taken |
| `...048` | a directory role template id in a private helper's help example | taken |
| `...049` | a user id inside a reviewer-scope query, in a help example and the matching tests | taken |
| `...050` | a group id serving as an access-package resource-role origin id, converter tests | taken |
| `...051` | an access-package assignment id, converter and read-path tests | taken |
| `...052` | a delegated-managed-identity registration assignment id, ARM role-assignment tests | taken |
| `...053` | an access package id, apply-engine access-package tests | taken |
| `...054` | a group id serving as an access-package resource root scope, read-path tests | taken |
| `...055` | a business-flow id quoted inside a Graph error detail, assignment-policy tests | taken |
| `...056` | an Azure role definition id, ARM role-definition resolver tests | taken |
| `...057` | an Azure role definition id, ARM role-assignment converter tests | taken |
| `...058` | a principal id, ARM role-assignment converter and read-path tests | taken |
| `...059` | an Azure role assignment name, ARM role-assignment tests | taken |
| `...060` | an Azure subscription id, ARM subscription and scope-resolution tests | taken |
| `...061` | an Azure tenant id, ARM subscription converter tests | taken |
| `...062` | a deliberately non-existent tenant alias suffix, base-path cohort test | taken |
| `...063` and up | -- | **FREE. Allocate from here.** |
| `...099` | a deliberately non-existent object id, used in a checklist to prove a not-found path | taken |
| `...0aa` | an assignment target principal id, access-package assignment tests | taken |
| `...abc` | an administrative unit id, group-creation tests | taken |

Addresses follow the same global rule outside the checklists:

| Placeholder | Slot (generic) | Status |
|---|---|---|
| `person1` - `person13`, `person15` - `person45` | reviewers, requestors, group members and guests across the checklists and the payload's help examples | taken |
| `person14` | -- | allocated in an earlier scrub and never used; left reserved, do not reuse |
| `person46` and up | -- | **FREE. Allocate from here.** |

`...0aa`, `...abc` and `...099` sit outside the counting sequence for historical reasons and are
listed so they are not handed out twice. Allocate new object ids from `...063` and new addresses
from `person46`, and add a row here in the same commit that uses them -- a placeholder that is used
but not registered is exactly the state the next person allocates over.

**Three v4-shaped values in `source/` are deliberately NOT placeholders**, and they are not in this
register because they name nothing in any tenant: the module's own GUID in the manifest, the
Microsoft Graph Command Line Tools first-party application id, and the Azure built-in role
definition id for Reader. They are pinned by name in `tests/QA/dochygiene.tests.ps1`, which fails if
one of them stops being used. That pinned list is not a place to put a new value -- see "What
enforces this" below for what the gate does instead.

## Credentials -- the rule redaction cannot satisfy

Console output from this module contains credentials, not only identifiers. Two arrive routinely:

- **A client secret**, pasted into a setup section so the run can be repeated.
- **A bearer token**, which nobody pastes on purpose. A failed Graph read produces an `ErrorRecord`
  whose `TargetObject` is the raw `HttpRequestMessage`, and rendering that record -- with
  `Format-List`, in a transcript, or by pasting a console scrollback -- prints
  `Authorization: Bearer <jwt>` in full. It appears in the middle of an otherwise ordinary error
  dump, which is exactly why it gets missed.

**An object id is a name; a credential is access.** Replacing an id with a placeholder closes that
leak. Replacing a credential with a placeholder closes nothing: by the time anyone notices, the
value has been committed, pushed, fetched by CI and cloned. So the rule is different in kind from
the two above:

1. **Never paste one into a tracked file.** Not even briefly, not even "to be cleaned up before the
   PR". Redaction is the recovery path, not the plan.
2. **If one did reach a tracked file, ROTATE it.** Delete the secret in the app registration and
   issue a new one; a leaked bearer token expires on its own, but the secret that minted it does
   not. Then redact the file. Redaction alone is not a fix and must never be recorded as one.
3. **The record's SHAPE may stay.** Keeping
   `Authorization: Bearer <bearer-token-REDACTED>` inside a quoted error record is correct and often
   the point of the write-up -- the header's presence is the finding. Keep the structure, drop the
   value.
4. **Never quote the value in a commit message, a PR body, a test name or an assertion message.**
   That copies it out of the file it was removed from.

`tests/QA/dochygiene.tests.ps1` fails on a JWT-shaped string, an `Authorization:` header carrying an
actual value, or a client-secret-shaped string in any tracked file under `docs/`, `specs/`, `source/`
or `tests/` -- this folder included. Like the other two checks it reports file and line and never the
value. Prose that merely names the header, and a `<...>` or `REDACTED` stand-in, both pass -- the
gate is aimed at values, not at vocabulary.

**A test fixture that has to be token-shaped says so in the value itself.** The bearer-scrub
regression tests cannot do their job without handing the module something shaped like a token, so
forbidding the shape under `tests/` would delete the module's most important security tests. Such a
fixture carries `NOT-A-REAL-TOKEN` inside the value, and the gate accepts that exactly as it accepts
`REDACTED`. The marker has to be in the VALUE, not in a comment beside it, so the declaration
belongs to that literal and cannot be borrowed by a real token pasted next to one -- which is also
why a real credential pasted while debugging can never satisfy it by accident.

A placeholder is only opaque while the real value it replaced appears nowhere else in the tree, so
redact every copy of a value, not just the first. Redaction changes files going forward; it never
rewrites history that already holds the original.

## Where raw output goes

Unredacted console output belongs in `docs/live-verification/raw/`, or in a `*.log` file in this
folder. Both are git-ignored, so the raw material stays on disk while a run is being written up and
is never staged. Redact on the way into the checklist; never paste an unredacted block into a
tracked `.md`.

`.gitignore` does not untrack anything already tracked, and that is deliberate here: the checklists
are the verification record and stay tracked. Only the raw material is ignored.

## What enforces this

`tests/QA/dochygiene.tests.ps1` runs as part of `./build.ps1 -Tasks test`. It covers every TRACKED
file under `docs/`, `specs/`, `source/` and `tests/` -- these checklists, the design specs,
`docs/examples/`, the payload that ships inside the built module, and the test fixtures. It reports
the file and line of every hit and never prints the value it matched; printing it would copy the
identifier, or the credential, into every CI log, which is precisely the leak the gate exists to
prevent.

The email and credential rules are the same everywhere. The **object-id** rule is not, because the
two halves of the tree are different kinds of writing:

- **Under `docs/` and `specs/` every GUID is prose**, pasted out of a console. The rule is absolute:
  it must be a `00000000-0000-0000-0000-0000000000NN` placeholder.
- **Under `source/` and `tests/` a GUID is a fixture**, typed on purpose. About seventy distinct ones
  exist -- `11111111-...`, `aaaaaaaa-...-0001` and so on -- and they are readable precisely because
  they are not interchangeable. The rule there keys on the one structural property that separates a
  real identifier from an invented one: **a tenant-generated Entra ID object id, and an ARM
  subscription or resource id, is a version-4 UUID**, and no hand-written fixture needs to be. A
  v4-shaped GUID under `source/` or `tests/` is therefore either a real identifier or a fixture typed
  to look like one -- which is indistinguishable from the first by inspection, and just as bad.

  It is a shape heuristic, not a proof, and it is worth knowing which way it errs. Some well-known
  Microsoft identifiers are deliberately not v4 -- the Microsoft Graph service principal's own
  application id is hand-assigned in the all-zeros style -- and the check lets those through, which
  is right: a non-random id is a published constant, the same in every tenant, not somebody's
  directory object. The residual gap is the mirror image, a tenant identifier that is somehow not
  v4. Nothing generates one today. Redacting as you write, and the register above, stay the primary
  control.

That second rule is about SHAPE, not a list of approved values, and that is deliberate: it cannot be
satisfied by adding an entry to something. The three pinned exceptions named in the register above
are the whole of the list and do not grow.

The gate is a backstop, not a substitute for redacting as you write. It cannot see the one failure
the register above exists to prevent -- a placeholder that means two different things -- because
every value involved is already a valid placeholder.
