# Live verification checklist -- pipeline binding and converter ownership

**SUPERSEDED.** 29 of this checklist's 88 checks were never run in the sprints since it merged --
mostly the S1-S9 block that builds a multi-stage access review, plus the sections 6 and 7 that hang
on it. All 29 have been carried forward, re-read against current source, into
`docs/live-verification/fix-auth-refresh-paging-and-resolver-checklist.md`, which also covers
issues #71, #72, #73 and #75 against the SAME shared tenant setup (one access package, one
assignment policy, a delivered assignment, a multi-stage access review, a paged read) rather than
building it twice -- which is exactly why the 29 were never run. Four of the carried checks needed a
CORRECTED expectation and say so in place; the import line in S1 named a module version that has
never existed on this branch. Run that file instead. This file is kept, unchanged below, because its
59 ticked boxes are the verification record for what WAS run here, and because it carries the
authoring pattern the new one continues.

**This PR does not merge until every box below has a written result.** A box with no result line
filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible to run,
write "cannot be verified, and therefore we do not know" on its result line and say why; do not
leave it blank and do not tick it.

This file lives on the branch rather than in the PR description for two reasons: a completed
checklist is larger than GitHub's 65,536-character body limit, and results written here land in the
diff, where they are reviewable and versioned instead of being edited invisibly. The PR body carries
the summary, the contracts verified against Microsoft Learn, and the lists of what needs no live
test and what was deliberately not fixed; it links here.

**Why this PR needs live checks at all.** 26 of its 37 findings are pipeline-binding changes. A
mocked test proves that a parameter *has* an attribute; only a real pipe against a real tenant
proves that the attribute binds the value you meant. Where a binding change lands on a cmdlet that
WRITES, a mis-bind does not fail -- it succeeds against the wrong object. Sections 2, 4, 5 and 6 are
the ones where that can happen.

**Order.** Run section 1 first: it is read-only and it establishes that the alias reorder targets
the parent group rather than the member, which every later group check depends on. Then 2, then 3.
Sections 4-7 can run in any order. Section 8 is the destructive set -- run it last, on throwaway
objects, and read every `-WhatIf` plan before dropping the switch.

---

## Setup, once

Use a throwaway tenant or a disposable slice of a test tenant. You need:

- One security group `oer-live-a` with **two members: one user and one nested group**. The nested
  group is what makes the alias-order checks meaningful -- with a user member the old behaviour
  errors, with a group member the old behaviour silently succeeds against the wrong object.
- One PIM-onboarded group `oer-live-pim` with **different settings on its member and owner
  policies** (for example activation max 8 hours on member, 4 on owner). Section 3 cannot
  discriminate without that difference.
- One catalog `OER-CAT-A` with at least one resource, and an access package `oer-live-ap` in it with
  **at least one assignment policy, at least one resource role, and at least one ASSIGNMENT**. The
  assignment is the one that is easy to miss and it is not optional: check 5.6 pipes an existing
  assignment, and with none in the tenant it produces no output at all and reads as a broken cmdlet.
  The block below creates it.
- One administrative unit `oer-live-au` with at least one member and one scoped role assignment.
- One access review on `oer-live-ap` -- but **do not create it by hand**. Section 6 needs a
  MULTI-STAGE review plus a definition id, an instance id and a stage id, and none of that is
  reachable from a single-stage review. Section **6.0 Setup for section 6** below builds all four
  from nothing; run it before any `6.x` check. It also says how to add the RECURRING definition that
  check 7.2 needs in order to have **more than one instance**.
- A subscription and a management group you can read, plus one resource group `oer-live-rg`.
- Optionally, for section 7: a collection with **more than one page**. Graph's default page size
  varies by endpoint; an access review instance with more than 100 decisions is the easiest to
  produce, by scoping the review at an access package that has more than 100 assignments. It cannot
  be produced by scoping a review at a large GROUP: `New-OERAccessReviewDefinition` has no `-Group`
  parameter, and this module creates access-package-scoped reviews only.

```powershell
Import-Module ./output/module/Omnicit.EntraRBAC/2.0.0/Omnicit.EntraRBAC.psd1 -Force
Connect-OER -TenantAlias '<your-alias>' -IncludeARM

# The assignment policy. Copy the Id you want to use into <policy-guid>; it is needed by 5.6, by
# 6.0, and by the corrected 6.5 / 6.8 / 6.9 commands.
Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap' |
    Format-Table Id, DisplayName, DurationInDays

# The assignment check 5.6 pipes. Run the Get- line first; only run the New- line if it is empty.
Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' | Format-Table Id, TargetId, State
New-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' -Policy '<policy-guid>' -User '<assignee-upn>'
```

`-Policy` takes a GUID and refuses anything else locally (that is check 5.7), so `<policy-guid>` must
be an `Id` from the first command, not a policy display name. Delivery is not instant: re-run the
`Get-OERAccessPackageAssignment` line until `State` settles on `delivered`. An assignment stuck in
`deliveryFailed` is worth fixing before you start, because a review over a package with no delivered
assignment can produce an instance with zero decisions, and check 7.1 then has nothing to page.

**A note on reading results.** Several checks below distinguish "errors loudly" from "succeeds
against the wrong object". When a check says **Failure looks like: a SUCCESS**, that is not a typo --
the pre-fix behaviour for that case was a successful call against the wrong target, which is exactly
why it needed fixing. Capture the actual object the call touched, not just whether it threw.

---

## 1. Group alias order -- the parent group, not the member (read-only)

Closes `T1NEW-group-reader-id-alias-first-misbinds` and
`A-group-read-cmdlets-missing-displayname-alias`.

Before the fix, `-Group` on these cmdlets listed `Id` before `GroupId`. A piped `GroupMember`
carries both -- `Id` is the PRINCIPAL, `GroupId` is the group -- so the principal id bound as the
group.

- [x] **1.1 The reader pipe now targets the parent group.**

  ```powershell
  Get-OERGroupMember -Group oer-live-a | Get-OERGroupEligibility -ErrorAction Continue
  ```

  **Expect:** every piped member produces eligibilities **for `oer-live-a`**, so the same result
  repeated once per member (or an empty list if the group has none) -- and NO error.
  **Failure looks like:** a 404 / `GroupNotFound` for the user member, and for the nested-group
  member a successful read of the NESTED group's eligibilities.
  **Result:**

- [x] **1.2 The same, through the PIM policy reader.**

  ```powershell
  Get-OERGroupMember -Group oer-live-a | Get-OERGroupPimPolicy -ErrorAction Continue
  ```

  **Expect:** the policy of `oer-live-a` (or a clean `PimPolicyNotFound` if it is not PIM-onboarded),
  once per member. **Failure looks like:** `PimPolicyNotFound` naming a member's id, or a real
  policy belonging to the nested group.
  **Result:**

- [x] **1.3 A display name now binds on the two readers.** This alias did not exist before.

  ```powershell
  [pscustomobject]@{ DisplayName = 'oer-live-a' } | Get-OERGroupMember
  ```

  **Expect:** the members of `oer-live-a`. **Failure looks like:** "The input object cannot be bound"
  -- the alias did not land.
  **Result:**

- [x] **1.4 `Get-OERGroup` pipes are unchanged.** `ConvertTo-OERGroup` emits `Id` and `DisplayName`
  and no `GroupId`, so the reorder must be inert here.

  ```powershell
  Get-OERGroup -Group oer-live-a | Get-OERGroupMember
  ```

  **Expect:** identical output to `Get-OERGroupMember -Group oer-live-a`.
  **Failure looks like:** any difference at all. This is the regression guard for the reorder.
  **Result:**

- [x] **1.5 The self-pipe behaviour change is understood and acceptable.** This is a DELIBERATE
  behaviour change, recorded so you can veto it.

  ```powershell
  Get-OERGroupMember -Group oer-live-a | Get-OERGroupMember
  ```

  **Expect:** `oer-live-a`'s members, listed once per member (N x N). Before the fix this walked
  INTO each member -- expanding the nested group and erroring on the user.
  **Failure looks like:** neither of those two shapes.
  **Decision to confirm:** is the new shape acceptable, or should this pipe be blocked outright?
  **Result:**

---

## 2. Group WRITE cmdlets -- the alias reorder changes what gets written

Closes the write half of `T1NEW-group-reader-id-alias-first-misbinds`. **These are the sharpest
checks in the PR.** Before the fix, piping a group member into any of these bound the MEMBER as the
target. Where the member was itself a group, that was a real, wrong, successful write.

Run each with `-WhatIf` first and read the target named in the plan.

- [x] **2.1 `Set-OERGroup` targets the parent.**

  ```powershell
  Get-OERGroupMember -Group oer-live-a | Set-OERGroup -Description 'live check 2.1' -WhatIf
  ```

  **Expect:** every `What if:` line names **`oer-live-a`** (or its id).
  **Failure looks like:** a line naming the nested member group -- a SUCCESSFUL write plan against
  the wrong group. `Set-OERGroup` has default ConfirmImpact, so without `-WhatIf` this would not
  even have prompted.
  **Result:**

- [x] **2.2 `Set-OERGroupPimPolicy` targets the parent.**

  ```powershell
  Get-OERGroupMember -Group oer-live-pim | Set-OERGroupPimPolicy -ActivationMaxHours 6 -WhatIf
  ```

  **Expect:** the plan names `oer-live-pim`.
  **Failure looks like:** it names a member.
  **Result:**

- [x] **2.3 `Remove-OERGroupEligibility` targets the parent.** Do NOT drop `-WhatIf` here.

  ```powershell
  Get-OERGroupMember -Group oer-live-pim | Remove-OERGroupEligibility -WhatIf
  ```

  **Expect:** the plan names `oer-live-pim` as the group. Note this cmdlet also binds `-PrincipalId`
  from the same piped object, so before the fix it produced a coherent-looking "remove P's
  eligibility on group P".
  **Failure looks like:** group and principal being the same id.
  **Result:**

- [x] **2.4 `Remove-OERGroup` targets the parent.** `-WhatIf` only, always.

  ```powershell
  Get-OERGroupMember -Group oer-live-a | Remove-OERGroup -WhatIf
  ```

  **Expect:** the plan names `oer-live-a`.
  **Failure looks like:** a plan to delete the nested member group. This is the worst case the
  reorder fixes.
  **Result:**

- [x] **2.5 Named and positional calls are unaffected.** The reorder must not have touched them.

  ```powershell
  Get-OERGroupMember -Group oer-live-a
  Get-OERGroupMember -Id      oer-live-a
  Get-OERGroupMember -GroupId oer-live-a
  ```

  **Expect:** three identical results. **Failure looks like:** any of the three failing to bind.
  **Result:**

---

## 3. `-AccessType` -- parity and pipeline carry-through

Closes `A-groupmember-owners-switch-vs-accesstype` and
`CONS-pimpolicy-accesstype-never-binds-from-pipeline`.

- [x] **3.1 `Get-OERGroupMember -AccessType owner` returns owners.**

  ```powershell
  Get-OERGroupMember -Group oer-live-a -AccessType owner
  Get-OERGroupMember -Group oer-live-a -Owners
  ```

  **Expect:** identical output from both, and `MemberType` reads `Owner`.
  **Failure looks like:** `-AccessType owner` returning members.
  **Result:**

- [x] **3.2 The positional contract survived.** `-AccessType` was declared LAST specifically so this
  keeps working; `-TenantId` was position 1 before the change.

  ```powershell
  Get-OERGroupMember oer-live-a '<your-tenant-id-or-domain>'
  ```

  **Expect:** succeeds, using the second argument as the tenant.
  **Failure looks like:** a `ValidateSet` error complaining the tenant value is not `member`/`owner`
  -- meaning the new parameter stole position 1.
  **Result:**

- [x] **3.3 `-Owners` and a disagreeing `-AccessType` are refused.**

  ```powershell
  Get-OERGroupMember -Group oer-live-a -Owners -AccessType member
  ```

  **Expect:** an `AmbiguousAccessType` error and no Graph call.
  **Failure looks like:** owners returned silently, or members returned silently.
  **Result:**

- [x] **3.4 `-AccessType` now survives a Get-to-Set pipe.** This is the one that could previously
  write to the wrong policy. Set the member and owner policies to DIFFERENT activation maximums
  first, or this check cannot discriminate.

  ```powershell
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType owner |
      Set-OERGroupPimPolicy -ActivationMaxHours 5 -WhatIf
  ```

  **Expect:** the plan names the **owner** policy.
  **Failure looks like:** it names the member policy -- the old behaviour, which silently rewrote
  the wrong one.
  **Result:**

- [x] **3.5 Confirm the write actually lands on the owner policy.** Drop `-WhatIf` on 3.4, then:

  ```powershell
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType owner  | Format-List AccessType, ActivationMaxHours
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType member | Format-List AccessType, ActivationMaxHours
  ```

  **Expect:** owner is now 5 hours; **member is untouched**.
  **Failure looks like:** member changed to 5, owner unchanged.
  **Result:**

- [x] **3.6 A group eligibility now carries its own access type into the policy read.** DELIBERATE
  behaviour change -- record whether it is wanted.

  ```powershell
  Get-OERGroupEligibility -Group oer-live-pim | Get-OERGroupPimPolicy
  ```

  **Expect:** for an owner-scoped eligibility, the **owner** policy. Before the fix this always read
  the member policy.
  **Failure looks like:** always the member policy.
  **Result:**

---

## 4. Azure RBAC and PIM binding

Closes `CONS-rmp-managementgroup-not-pipeline-bound`,
`B-new-roleassignment-principal-not-pipeable`, `A-condition-version-no-validateset`,
`T1NEW-roledefinition-id-collides-policyid-alias`.

- [x] **4.1 A management group now pipes into the policy readers.**

  ```powershell
  Get-OERManagementGroup -ManagementGroup '<mg-name>' | Get-OERRoleManagementPolicy -CommonRoles
  ```

  **Expect:** policies scoped to that management group.
  **Failure looks like:** "The input object cannot be bound" -- the attribute did not land.
  **Result:**

- [x] **4.2 The same into the writer.**

  ```powershell
  Get-OERManagementGroup -ManagementGroup '<mg-name>' |
      Get-OERRoleManagementPolicy -CommonRoles |
      Select-Object -First 1 |
      Set-OERRoleManagementPolicy -ActivationMaxHours 4 -WhatIf
  ```

  **Expect:** a plan naming the management-group-scoped policy.
  **Failure looks like:** a bind failure, or `AmbiguousParameterSet`.
  **Result:**

- [ ] **4.3 The documented policy round-trip still works.** This is the regression guard for
  deliberately NOT adding pipeline binding to `-Role`. The piped policy object carries BOTH
  `PolicyId` (which `-PolicyId` binds through its `Id` alias) and `RoleDefinitionId` (which is an
  alias of `-Role`), so if `-Role` ever gained `ValueFromPipelineByPropertyName` a single piped
  policy would satisfy two mutually exclusive parameter sets at once.

  **Read the live value first and set a DIFFERENT one.** A fixed target hour is tenant-dependent:
  against a policy that already holds it, the cmdlet answers `NoChange`, which is correct behaviour
  but reads as a failed check.

  ```powershell
  $Pol = Get-OERRoleManagementPolicy -Subscription '<sub-id>' -Role Contributor
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
  binding half of this check has already passed at that point, because `NoChange` is only reachable
  after the parameter set resolved and the policy was fetched by id.

  **Failure looks like:** `AmbiguousParameterSet` -- `-Role` wrongly gained a pipeline attribute and
  a piped policy now satisfies two mutually exclusive sets. A prompt for `-PolicyId` or for `-Role`
  is the other failure shape: the pipe did not bind at all.
  **Result:**

- [x] **4.4 A principal now pipes into the create cmdlets (tick predates the corrected command below -- re-confirm or re-run).**

  ```powershell
  Get-OEREligibleRoleAssignment -Subscription '<sub-id>' |
      Select-Object -First 1 |
      New-OERActiveRoleAssignment -Subscription '<sub-id>' -Role Reader -Duration 'PT2H' -WhatIf
  ```

  **Expect:** the plan names the piped `PrincipalId`.
  **Failure looks like:** a `NoPrincipal` error -- the parameter did not bind.
  **CORRECTED 2026-08-27 -- the tick above predates this command.** It previously read
  `-DurationHours 2`. `New-OERActiveRoleAssignment` has no such parameter and no such alias -- it
  takes `-Duration` (a raw ISO 8601 string) or `-DurationDays` (a whole-unit int). `-DurationHours`
  belongs to `Enable-OEREligibleRoleAssignment`, a different cmdlet. As written the call died with
  "A parameter cannot be found that matches parameter name 'DurationHours'" before any binding
  happened, so it could not have tested what this check is about. The tick was left in place
  because you may well have adapted the command at the keyboard -- only you can say. Re-confirm it
  against the form above, or re-run it, and write the answer on the result line.
  **Result:**

- [x] **4.4b A named principal supplied alongside a pipe of assignment objects is REFUSED.** Whole-
  branch review finding I-1. Every assignment-shaped object carries `PrincipalId`, which takes
  precedence over the friendly parameters, so before this guard the named user was silently ignored
  and one assignment was created per piped object -- for that object's OWN principal.

  ```powershell
  Get-OERRoleAssignment -Subscription '<sub-id>' |
      Select-Object -First 1 |
      New-OERRoleAssignment -Role Reader -User '<upn>' -Scope '/subscriptions/<sub-id>' -WhatIf
  ```

  **Expect:** a non-terminating `AmbiguousPrincipal,New-OERRoleAssignment` error naming the piped
  object's own `PrincipalId`, and no plan line at all -- nothing is created. Repeat for
  `New-OERActiveRoleAssignment` (with `-Group`) and `New-OEREligibleRoleAssignment` (with
  `-ServicePrincipal`); all three carry the same guard.
  **Failure looks like:** a `-WhatIf` plan naming the PIPED principal instead of `<upn>` -- the guard
  did not fire, and a real run would have granted the role to a principal the caller never named.
  The opposite failure matters just as much: if 4.5 below now reports `AmbiguousPrincipal`, the guard
  is too wide. It is deliberately keyed on the piped item's OWN `PrincipalId`, so a scope-shaped
  object (subscription, resource group, resource, role definition) must never trip it.
  **Result:**

- [x] **4.5 A subscription piped in does NOT hijack the principal.** `ConvertTo-OERSubscription`
  emits `DisplayName`; `-Group` deliberately did not gain a `DisplayName` alias precisely so this
  documented pipe keeps working.

  ```powershell
  Get-OERSubscription -Subscription '<sub-id>' |
      New-OERRoleAssignment -Role Reader -User '<upn>' -WhatIf
  ```

  **Expect:** succeeds; the principal is the named user.
  **Failure looks like:** `AmbiguousPrincipal`, or the subscription's display name being resolved as
  a group.
  **Result:**

- [x] **4.6 Positional calls to the create cmdlets are unaffected.** `-PrincipalId` was declared LAST
  for this reason. Run whatever positional form you actually use in scripts, and record it here
  verbatim.

  **Expect:** binds exactly as before.
  **Failure looks like:** an argument landing in `-PrincipalId`.
  **Result:**

- [x] **4.7 `-ConditionVersion` now rejects anything but 2.0.**

  ```powershell
  New-OERRoleAssignment -Role Reader -User '<upn>' -Subscription '<sub-id>' `
      -Condition "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'x'" `
      -ConditionVersion '1.0' -WhatIf
  ```

  **Expect:** a local parameter-validation error before any ARM call.
  **Failure looks like:** an ARM 400 -- meaning the ValidateSet is missing.
  **Result:**

- [x] **4.8 `Set-OERRoleAssignment` was deliberately EXCLUDED from that ValidateSet**, because it is
  read-modify-write and must be able to edit a legacy 1.0 assignment.

  ```powershell
  Get-Command Set-OERRoleAssignment | ForEach-Object { $_.Parameters['ConditionVersion'].Attributes } |
      Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
  ```

  **Expect:** NO output -- no ValidateSet on this cmdlet.
  **Failure looks like:** a ValidateSet listing `2.0`, which would block editing a legacy assignment.
  **Result:**

- [x] **4.9 The role definition shape no longer carries a bare `Id`.** BREAKING, decided
  deliberately.

  ```powershell
  $Rd = Get-OERRoleDefinition -Subscription '<sub-id>' -Role Contributor
  $Rd | Format-List *
  $Rd.PSObject.Properties.Name
  ```

  **Expect:** `RoleDefinitionId` and `ResourceId` present; **`Id` absent**; `Name` still the ARM
  resource name (a GUID) and `RoleName` still the display name.
  **Failure looks like:** `Id` still present, or `RoleName` missing.
  **Result:**

- [x] **4.10 The collision it existed to fix is gone.**

  ```powershell
  Get-OERRoleDefinition -Subscription '<sub-id>' -Role Contributor | Get-OERRoleManagementPolicy
  ```

  **Expect:** a clean bind failure -- there is no longer any property that satisfies `-PolicyId`.
  **Failure looks like:** a request going out against a `roleDefinitions` path as if it were a
  policy id. Check `-Verbose` output for the URI.
  **Result:**

- [x] **4.11 The same collision on the eligibility path.** This one was UNGUARDED and wrote the bogus
  id into the request body as `linkedRoleEligibilityScheduleId`.

  ```powershell
  Get-OERRoleDefinition -Subscription '<sub-id>' -Role Contributor |
      Enable-OEREligibleRoleAssignment -User '<upn>' -Subscription '<sub-id>' -DurationHours 1 -WhatIf -Verbose
  ```

  **Expect:** no `roleDefinitions` path appears as a linked eligibility id.
  **Failure looks like:** one does.
  **Result:**

- [x] **4.12 The pipe that MUST still work.** `New-OERRoleAssignment` binds a piped role definition
  through `-Role [Alias('RoleDefinitionId')]`, which the new shape keeps.

  ```powershell
  Get-OERRoleDefinition -Subscription '<sub-id>' -Role Contributor |
      New-OERRoleAssignment -User '<upn>' -Subscription '<sub-id>' -WhatIf
  ```

  **Expect:** succeeds, role resolved to Contributor.
  **Failure looks like:** a bind failure -- dropping `Id` broke more than intended.
  **Result:**

- [x] **4.13 `-PrincipalType` reaches the request body.** Added beyond the audit's scope, on
  `New-OERRoleAssignment` ONLY. ARM uses `principalType` to accept an assignment for a principal
  that has not yet replicated, which is the canonical reason to use a raw `-PrincipalId`.

  ```powershell
  New-OERRoleAssignment -Role Reader -PrincipalId '<a freshly created SP object id>' `
      -PrincipalType ServicePrincipal -Subscription '<sub-id>' -Confirm:$false -Verbose
  ```

  **Expect:** succeeds. The real test is a genuinely fresh service principal -- create one and
  assign within a few seconds. **Failure looks like:** `PrincipalNotFound` from ARM despite the
  principal existing, which is the replication-delay symptom `principalType` exists to prevent.
  **Result:**

- [x] **4.14 `principalType` is OMITTED, not sent as null, when unknown.**

  ```powershell
  New-OERRoleAssignment -Role Reader -PrincipalId '<an existing principal id>' `
      -Subscription '<sub-id>' -Confirm:$false
  ```

  **Expect:** succeeds. ARM's documented body omits `principalType` entirely; a literal
  `"principalType": null` is not a valid shape.
  **Failure looks like:** an ARM 400 complaining about the property.
  **Result:**

- [x] **4.15 The two PIM cmdlets deliberately have NO `-PrincipalType`.** Their schedule-request API
  treats it as response-only.

  ```powershell
  (Get-Command New-OERActiveRoleAssignment).Parameters.ContainsKey('PrincipalType')
  (Get-Command New-OEREligibleRoleAssignment).Parameters.ContainsKey('PrincipalType')
  ```

  **Expect:** `False` twice. **Failure looks like:** `True` -- it would send a property the API
  ignores at best and rejects at worst.
  **Result:**

- [x] **4.16 KNOWN NARROW HAZARD -- confirm the behaviour is acceptable.** Because `-PrincipalType`
  binds from the pipeline, explicitly overriding `-PrincipalId` on a pipe leaves the PIPED
  `PrincipalType` in force, so a mismatched pair can be sent.

  ```powershell
  Get-OERRoleAssignment -Subscription '<sub-id>' | Select-Object -First 1 |
      New-OERRoleAssignment -PrincipalId '<a DIFFERENT principal of a different type>' `
      -Role Reader -Subscription '<sub-id>' -WhatIf -Verbose
  ```

  **Expect:** decide whether the mismatch matters. ARM treats `principalType` as a replication hint,
  so the likely outcome is that it is ignored. **Failure looks like:** ARM rejecting the assignment.
  This is a documented consequence of the binding choice, not a defect -- record your judgement.
  **Result:**

---

## 5. Entitlement management

Closes `CONS-em-read-cmdlets-accept-no-pipeline-input`,
`B-em-catalogresource-remove-missing-catalog-property`, `B-em-catalog-name-vs-id-pipe-mismatch`,
`B-em-setpolicy-mandatory-scope-breaks-pipe`, `A-ap-assignment-accesspackage-policy-no-pipe`,
`A-ap-resource-role-origin-id-only`, and issue **#58**.

- [x] **5.1 A catalog now pipes into the package reader.**

  ```powershell
  Get-OERCatalog -DisplayName 'OER-CAT-A' | Get-OERAccessPackage -Verbose
  ```

  **Expect:** the packages in that catalog, and the verbose URI shows
  `$filter=catalog/id eq '<catalog id>'`.
  **Failure looks like:** a bind failure, or the catalog's DisplayName hijacking the `ByName` set and
  returning a package lookup by name.
  **Result:**

- [x] **5.2 The catalog resource shape now carries its catalog, so the removal pipe works.**
  `-WhatIf` first.

  ```powershell
  Get-OERCatalogResource -Catalog 'OER-CAT-A' | Select-Object -First 1 |
      Remove-OERCatalogResource -WhatIf -Verbose
  ```

  **Expect:** succeeds; the request body carries the RESOURCE id and the CATALOG id, and they
  differ. **Failure looks like:** a prompt for a mandatory `-Catalog` -- the property did not land.
  **Result:**

- [x] **5.3 The new double-bind guard fires.** Adding `CatalogId` to the Catalog type made a piped
  CATALOG satisfy both `-ResourceId [Alias('Id')]` and `-Catalog [Alias('CatalogId')]`, which would
  otherwise be a wrong-target removal.

  ```powershell
  Get-OERCatalog -DisplayName 'OER-CAT-A' | Remove-OERCatalogResource -WhatIf
  ```

  **Expect:** a `ResourceIdEqualsCatalogId` error and no request.
  **Failure looks like:** a plan to remove a "resource" whose id equals the catalog id -- a SUCCESS
  where an error is required.
  **Result:**

- [x] **5.4 The assignment policy pipe no longer hangs on a mandatory prompt.**

  ```powershell
  Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap' | Select-Object -First 1 |
      Set-OERAccessPackageAssignmentPolicy -DurationInDays 60 -WhatIf
  ```

  **Expect:** succeeds with no prompt; the plan carries the policy's OWN display name, unchanged.
  **Failure looks like:** an interactive prompt for `-DisplayName`, or a renamed policy.
  **Result:**

- [x] **5.5 Confirm the policy was not silently renamed.** Drop `-WhatIf` on 5.4, then re-read.

  ```powershell
  Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap' | Format-Table DisplayName, DurationInDays
  ```

  **Expect:** duration 60, display name unchanged.
  **Failure looks like:** a changed display name.
  **Result:**

- [ ] **5.6 `New-OERAccessPackageAssignment` binds the PACKAGE id, not an assignment id.**

  ```powershell
  Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' | Select-Object -First 1 |
      New-OERAccessPackageAssignment -Policy '<policy-guid>' -User '<upn>' -WhatIf -Verbose
  ```

  **Expect:** the plan names `oer-live-ap`. `ConvertTo-OERAssignment` emits both `Id` (the
  ASSIGNMENT) and `AccessPackageId`, and `Id` was deliberately NOT aliased for this reason.
  **Failure looks like:** the assignment id being used as the package id.

  **NO OUTPUT AT ALL is a setup gap, not a defect.** This check needs an assignment that already
  exists. If `Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap'` returns nothing, zero
  objects reach the pipe, and `New-OERAccessPackageAssignment` -- whose `-AccessPackage` and
  `-Policy` are both mandatory -- never enters its `process` block, so it prints nothing rather than
  complaining. That is the assignment step of "Setup, once" having been skipped. Create the
  assignment, wait for `State` to reach `delivered`, and re-run. Confirm the read first:

  ```powershell
  Get-OERAccessPackage -DisplayName 'oer-live-ap' | Format-Table Id, DisplayName, CatalogId
  Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' |
      Format-Table Id, TargetId, State, AccessPackageDisplayName
  ```

  If assignments plainly exist for that package id and the read still comes back empty, THAT is a
  real finding -- record it here rather than treating it as setup.
  **Result:**

- [x] **5.7 A non-GUID policy is refused locally.**

  ```powershell
  New-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' -Policy 'not-a-guid' -User '<upn>' -WhatIf
  ```

  **Expect:** an `InvalidPolicyId` error before any Graph call.
  **Failure looks like:** a Graph 400.
  **Result:**

- [x] **5.8 A resource role can now be bound by friendly name.**

  ```powershell
  Add-OERAccessPackageResourceRole -AccessPackage 'oer-live-ap' -Catalog 'OER-CAT-A' `
      -Group '<a group already onboarded to the catalog>' -Role Member -WhatIf -Verbose
  ```

  **Expect:** the group resolves to an origin id and the plan names the right resource.
  **Failure looks like:** `CatalogResourceNotFound` -- the name was passed through unresolved.
  **Result:**

- [x] **5.9 An ambiguous group name surfaces the candidates.**

  ```powershell
  Add-OERAccessPackageResourceRole -AccessPackage 'oer-live-ap' -Catalog 'OER-CAT-A' `
      -Group '<a display name shared by two groups>' -Role Member -WhatIf
  ```

  **Expect:** `AmbiguousGroupName` **listing the candidate ids**.
  **Failure looks like:** a first match being used silently.
  **Result:**

- [x] **5.10 `-ResourceOriginId` still binds where it did.** It became non-mandatory; that must not
  have changed the positional or named contract.

  ```powershell
  Add-OERAccessPackageResourceRole -AccessPackage 'oer-live-ap' -Catalog 'OER-CAT-A' `
      -ResourceOriginId '<origin-id>' -Role Member -WhatIf
  ```

  **Expect:** unchanged behaviour. **Failure looks like:** a parameter-set resolution error.
  **Result:**

- [x] **5.11 Issue #58 -- `-IncludePolicies` actually returns policies.** It was inert: the request
  built the `$expand` correctly and the converter threw the result away.

  ```powershell
  $Ap = Get-OERAccessPackage -DisplayName 'oer-live-ap' -IncludePolicies
  $Ap.AssignmentPolicies | Format-Table DisplayName, Id
  ```

  **Expect:** one row per policy on the package.
  **Failure looks like:** the property missing or empty.
  **Result:**

- [x] **5.12 Issue #58 -- `-IncludeResourceRoles` actually returns roles.**

  ```powershell
  $Ap = Get-OERAccessPackage -DisplayName 'oer-live-ap' -IncludeResourceRoles
  $Ap.ResourceRoleScopes | Format-Table OriginId, RoleName, ResourceDisplayName
  ```

  **Expect:** one row per bound resource role. **`ResourceDisplayName` will be `$null`** -- that is
  documented and deliberate, because the display name comes from a second Graph call that only
  `Get-OERAccessPackageResourceRole` makes.
  **Failure looks like:** the property missing or empty. A populated `ResourceDisplayName` is ALSO a
  finding -- it would mean a converter is making a transport call.
  **Result:**

- [x] **5.13 Neither collection appears when not asked for.**

  ```powershell
  (Get-OERAccessPackage -DisplayName 'oer-live-ap').PSObject.Properties.Name
  ```

  **Expect:** the original five properties only, no `AssignmentPolicies`, no `ResourceRoleScopes`.
  **Failure looks like:** empty collections appearing unconditionally, which would change every
  existing caller's output shape.
  **Result:**

- [x] **5.13b THE ONE #58 CASE MOCKS CANNOT SETTLE -- an EMPTY expanded relationship.** The whole
  "presence, not truthiness" contract rests on Graph emitting the key for a relationship that
  exists but is empty. Nothing offline can prove Graph does that. Use an access package in a fresh
  catalog with **zero** assignment policies and **zero** resource roles.

  ```powershell
  $Empty = Get-OERAccessPackage -DisplayName '<a package with no policies and no resource roles>' -IncludePolicies -IncludeResourceRoles
  $Empty.PSObject.Properties.Name
  @($Empty.AssignmentPolicies).Count
  @($Empty.ResourceRoleScopes).Count
  ```

  **Expect:** BOTH property names present, and both counts `0`.
  **Failure looks like:** the property names absent. That would mean Graph omits the key entirely
  for an empty expansion, and the documented contract -- "if the property is present, the expansion
  was requested" -- is only half true. Report it; the help says so explicitly and would need
  softening.
  **Result:**

- [x] **5.14 The nested collection does NOT change outer binding.** It looks like it should work
  once the collection is visible, and it must not.

  ```powershell
  Get-OERAccessPackage -DisplayName 'oer-live-ap' -IncludePolicies |
      Set-OERAccessPackageAssignmentPolicy -DurationInDays 30 -WhatIf
  ```

  **Expect:** the PACKAGE's own id binds `-Id` (and the call fails or targets the package), NOT a
  nested policy. The binder does not descend into collections.
  **Failure looks like:** a nested policy being targeted.
  **Result:**

---

## 6. Access reviews

Closes `B-ar-stage-decision-not-pipeable`, `A-ar-set-definition-id-only-no-displayname`,
`A-ar-selfreview-mixing-not-guarded`, `A-ar-public-int-params-lack-validaterange`.

### 6.0 Setup for section 6 -- from nothing to a definition id, an instance id and a stage id

**Run this whole block before any `6.x` check.** Section 6 starts from `-Definition '<def-id>'`,
`$Inst.Stages` and a stage id and assumes all three already exist. None of them exist until you
create a review definition AND the Graph service materializes an instance for it. These nine steps
are setup, not findings, but they carry result lines for the same reason every other box does: what
an id turned out to be, and how long it took to appear, is the part nobody can reconstruct later.

**READ THIS BEFORE YOU CONCLUDE ANYTHING IS BROKEN.** An `accessReviewInstance` is created by the
**Microsoft Graph service**, never by the caller. There is no `New-OERAccessReviewInstance` in this
module and no Graph API to create one. `Get-OERAccessReviewInstance` returning **nothing** straight
after the definition is created is a legitimate result, not a defect. See S7.

**The one thing that decides whether 6.1 and 6.2 can run at all: the review must be MULTI-STAGE.**
Microsoft Graph creates an instance's `stages` collection only from the definition's `stageSettings`.
Learn documents `stages` on `accessReviewInstance` as "If the instance has multiple stages, this
returns the collection of stages ... The existence, number, and settings of stages on a review
instance are created based on the **accessReviewStageSettings** on the parent
accessReviewScheduleDefinition"
(https://learn.microsoft.com/graph/api/resources/accessreviewinstance?view=graph-rest-1.0); the List
method is titled "Retrieve the stages in a **multi-stage** access review instance"; the
`accessReviewStage` resource says the same from the other side, "If the parent
accessReviewScheduleDefinition **has defined the stageSettings property**, the accessReviewInstance
is comprised of up to three subsequent stages"
(https://learn.microsoft.com/graph/api/resources/accessreviewstage?view=graph-rest-1.0); and
`stageSettings` is documented as "Required only for a **multi-stage** access review"
(https://learn.microsoft.com/graph/api/resources/accessreviewscheduledefinition?view=graph-rest-1.0).
A single-stage review therefore has no `stages` to read, `$Inst.Stages` comes back empty, and 6.1 and
6.2 cannot run. **Create the review with `-Stage`, not with `-Reviewer`.**

A second consequence of the same Learn text: "A new stage will only be created when the previous
stage ends." Even on a two-stage review you will see ONE stage at a time, not two. That is enough --
6.1 and 6.2 both take `Select-Object -First 1`.

**Placeholders**, all in one place:

| Placeholder | What it is |
| --- | --- |
| `<your-alias>` | The `Get-OERConfiguration` alias for the test tenant, as in "Setup, once". |
| `<policy-guid>` | The GUID `Id` of the assignment policy on `oer-live-ap` you want reviewed, captured in "Setup, once" and re-confirmed in S2. Not a display name. |
| `<assignee-upn>` | The ordinary user assigned to `oer-live-ap` so the review has something to review. Keep it different from the reviewer. |
| `<reviewer-upn>` | The user who reviews. A UPN or a user object id. Any licensed user will do; they do not have to act. |
| `<def-id>` | The access review definition id. A GUID. Captured in S6. This is section 6's `<def-id>` in 6.1 and 6.6, and its `<def-guid>` in 6.4. |
| `<inst-id>` | The access review instance id. A GUID. Captured in S7. Section 7.1 calls this `<inst-id>`. |
| `<stage-id>` | The access review stage id. Captured in S8. See the note in S8 about its format. |

**What is already covered elsewhere.** "Setup, once" owns the catalog `OER-CAT-A`, the access package
`oer-live-ap`, its assignment policy, its resource role and its assignment. Do not create those again
here -- S2 and S3 only verify them and capture the ids.

- [ ] **S1 Connect, with the scopes access reviews need.**

  ```powershell
  Import-Module ./output/module/Omnicit.EntraRBAC/2.0.0/Omnicit.EntraRBAC.psd1 -Force
  Connect-OER -TenantAlias '<your-alias>'
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
  **Failure looks like:** a consent error on the first Graph call in S2 rather than here --
  `Connect-OER` succeeding is not proof the scopes were granted.
  **Result:**

- [ ] **S2 Re-confirm the package and the policy GUID.**

  ```powershell
  Get-OERAccessPackage -DisplayName 'oer-live-ap' | Format-Table Id, DisplayName, CatalogId
  Get-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap' |
      Format-Table Id, DisplayName, DurationInDays
  ```

  **Expect:** exactly one package, and at least one policy. Copy the `Id` of the policy you intend to
  review into `<policy-guid>`. If there is more than one, pick one and stay with it for the whole of
  section 6 -- the review scope pins ONE package plus ONE policy, and assignments made under a
  different policy are invisible to the review. Confirm `CatalogId` is the catalog you expect: a
  leftover duplicate `oer-live-ap` in another catalog resolves cleanly and reviews nothing.
  **Failure looks like:** an empty policy list -- "Setup, once" is not done. Create one with
  `New-OERAccessPackageAssignmentPolicy -AccessPackage 'oer-live-ap' -DisplayName '<name>'
  -RequestorScope (New-OERAccessPackageRequestorScope -AdminAssignmentOnly)` and start again.
  **Result:**

- [ ] **S3 Confirm at least one principal is in scope.** A review over an access package reviews its
  ASSIGNMENTS. With no delivered assignment under `<policy-guid>` there is nothing to decide.

  ```powershell
  Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' | Format-Table Id, TargetId, State
  # only if that is empty:
  New-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' -Policy '<policy-guid>' -User '<assignee-upn>'
  ```

  **Expect:** at least one assignment reaching `delivered`. Delivery is not instant; re-run the
  `Get-` line until `State` settles.
  **Failure looks like:** the assignment stuck in `delivering` or landing on `deliveryFailed`. Fix
  that before creating the review.
  **Result:**

- [ ] **S4 Build the two stage objects.** These are LOCAL objects. `New-OERAccessReviewStage` calls
  Graph only to resolve the reviewer name, and creates nothing in the tenant.

  ```powershell
  $StageOne = New-OERAccessReviewStage -StageId '1' -DurationInDays 3 -Reviewer '<reviewer-upn>'
  $StageTwo = New-OERAccessReviewStage -StageId '2' -DependsOn '1' -DurationInDays 2 `
      -Reviewer '<reviewer-upn>' -DecisionsThatMoveToNextStage NotReviewed
  $StageOne, $StageTwo | Format-Table StageId, DurationInDays, ReviewerCount
  ```

  **Expect:** two objects, `ReviewerCount` 1 on each. `-DecisionsThatMoveToNextStage` accepts only
  `Approve`, `Deny`, `Recommendation`, `NotReviewed`.
  **Failure looks like:** a `UserNotFound` naming `<reviewer-upn>`, or `ReviewerCount` 0.
  **Do NOT use `-Manager` here.** `New-OERAccessReviewDefinition` refuses a manager reviewer with no
  fallback (`ManagerFallbackRequired`), and it is an unnecessary variable in a setup step.
  **Result:**

- [ ] **S5 Create the multi-stage definition.**

  ```powershell
  $Def = New-OERAccessReviewDefinition `
      -DisplayName             'oer-live-ar-multistage' `
      -DescriptionForAdmins    'Live verification of section 6. Safe to delete.' `
      -DescriptionForReviewers 'Live verification. No action needed.' `
      -AccessPackage           'oer-live-ap' `
      -AssignmentPolicy        '<policy-guid>' `
      -Stage                   $StageOne, $StageTwo `
      -Recurrence              OneTime `
      -StartDate               (Get-Date) `
      -DurationInDays          5
  $Def | Format-List Id, DisplayName, Status, StageCount
  ```

  **Expect:** one object with a GUID `Id`, `StageCount` 2, and a `Status` of `NotStarted` or
  `Initializing`.
  **Failure looks like:** a parameter binding error. `-Stage` lives in the `MultiStage` parameter set,
  which does NOT contain `-Reviewer`, `-ReviewerGroup`, `-Manager`, `-SelfReview`,
  `-FallbackReviewer` or `-FallbackReviewerGroup`. Adding any of those to this call makes the command
  unresolvable. For a multi-stage review, reviewers live on the stage objects only.

  **Why these values.**

  - `-Recurrence OneTime` is the fastest cadence to an instance. The module emits NO `recurrence`
    object at all for `OneTime` -- the private builder returns nothing and the caller omits the key --
    so there is no future schedule for the service to wait on. Learn: "In the case of a one-time
    review, only one instance is created per resource."
  - `-StartDate (Get-Date)` is REQUIRED by the binder but is **discarded** when `-Recurrence` is
    `OneTime`, because it is used only to build the recurrence range. Pass it to satisfy the binder;
    do not expect it to influence anything.
  - `-DurationInDays 5` is the sum of the two stage durations (3 + 2). Learn documents the stage
    `endDateTime` as "the cumulative total of the durationInDays for all stages", and documents that
    where `stageSettings` is defined its settings are used instead of the definition's, so the
    per-stage values are the ones that govern. Keeping the total consistent avoids arguing with the
    service about which number wins.
  - Deliberately NOT passed: `-AutoApplyDecisions`. If decisions auto-apply, the review can REMOVE
    the assignment from S3. See Teardown.
  - **If you also need the recurring definition check 7.2 asks for** (`<recurring-def-id>`, more than
    one instance), create a SECOND definition -- do not turn this one into a recurring review.
    Section 6 is far easier to reason about on a one-time review with exactly one instance. The
    second definition is single-stage and lives in the `SingleStage` set:

    ```powershell
    $RecDef = New-OERAccessReviewDefinition `
        -DisplayName             'oer-live-ar-recurring' `
        -DescriptionForAdmins    'Live verification of check 7.2. Safe to delete.' `
        -DescriptionForReviewers 'Live verification. No action needed.' `
        -AccessPackage           'oer-live-ap' `
        -AssignmentPolicy        '<policy-guid>' `
        -Reviewer                '<reviewer-upn>' `
        -Recurrence              Weekly `
        -StartDate               (Get-Date) `
        -Occurrences             3 `
        -DurationInDays          3
    ```
  **Result:**

- [ ] **S6 Capture the definition id.**

  ```powershell
  $DefId = $Def.Id
  # or, in a fresh session:
  $DefId = (Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage').Id
  $DefId
  ```

  **Expect:** one GUID. This is section 6's `<def-id>` in 6.1 and 6.6 and its `<def-guid>` in 6.4,
  and the display name `oer-live-ar-multistage` is check 6.3's `<the review display name>`. (`Id` is
  an `AliasProperty` of `AccessReviewDefinitionId`; both spellings return the same value.)
  **Failure looks like:** more than one result, meaning a review of that name already exists. Rename
  the new one or delete the old one -- an ambiguous display name makes 6.3 unreadable.
  **Result:**

- [ ] **S7 Wait for the SERVICE to create the instance, then capture its id.** This is the step most
  likely to look broken when it is not. Re-read the warning at the top of 6.0: instances are created
  by Microsoft Graph, and an empty result here immediately after S5 is normal.

  ```powershell
  Get-OERAccessReviewInstance -Definition $DefId |
      Format-Table Id, Status, StartDateTime, EndDateTime
  ```

  **Expect:** eventually exactly one instance -- a one-time review has exactly one -- with a GUID
  `Id` and a `Status` moving `Initializing` -> `NotStarted` -> `InProgress`. Copy `Id` into
  `<inst-id>`. An instance sitting in `NotStarted` is already usable for 6.1 and 6.2: Learn describes
  `accessReviewInstance.startDateTime` as "DateTime when review instance is scheduled to start.
  **May be in the future**", so the object can exist before it starts.

  **How long this takes is not documented as a number, and this block will not invent one.** What
  Learn does say: "When creating an access review, you're able to specify the start date, but the
  start time could vary a few hours based on system processing ... could be delayed due to system
  processing"
  (https://learn.microsoft.com/entra/id-governance/create-access-review#create-a-single-stage-access-review).
  A processing delay is documented; **its magnitude is not**, and no figure at all is given for the
  shape used here (no recurrence object, starting immediately). **Poll -- re-run the command every
  few minutes -- rather than concluding failure.** Write the wait you actually observed on the result
  line; it is the only measurement anyone will have.

  **Failure looks like:** still nothing after a long wait AND a definition `Status` stuck at
  `Initializing`, which usually means the scope query matched no assignments. Go back to S3.
  **If you cannot get an instance at all,** write "cannot be verified, and therefore we do not know"
  on 6.1 and 6.2, say the instance never materialized, and do not tick them.
  **Result:**

- [ ] **S8 Capture the stage id.**

  ```powershell
  $Inst = Get-OERAccessReviewInstance -Definition $DefId -IncludeStages
  $Inst | Format-Table Id, Status
  $Inst.Stages | Format-Table AccessReviewStageId, Status, StartDateTime, EndDateTime
  ```

  **Expect:** `$Inst.Stages` is non-empty. Because "a new stage will only be created when the
  previous stage ends", expect ONE stage here -- stage 1 -- not two. Copy `AccessReviewStageId` into
  `<stage-id>`.
  **On the id format:** Learn documents `accessReviewStage.id` only as "Unique identifier of the
  stage. Read-only." and states no format. It is NOT promised to be the `'1'` / `'2'` passed to
  `New-OERAccessReviewStage -StageId` -- that value goes into the definition's `stageSettings`, which
  is a different object. Write down what you actually see.
  **Failure looks like:** `$Inst.Stages` empty while the definition has two stages configured. Confirm
  the review really is multi-stage first:
  `(Get-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage').StageSettings`. An empty
  `StageSettings` means the create fell into the single-stage path and 6.1/6.2 cannot run against it.
  **Careful:** where a definition has several instances, `$Inst` is an ARRAY and `$Inst.Stages`
  unrolls across all of them. The one-time review from S5 has exactly one instance, which is why
  6.1's `$Inst.Stages` is safe as written -- do not point `$Inst` at `oer-live-ar-recurring`.
  **Result:**

- [ ] **S9 Confirm the three ids satisfy section 6 before you start it.**

  ```powershell
  [pscustomobject]@{
      DefinitionId = $DefId
      InstanceId   = $Inst.Id
      StageId      = ($Inst.Stages | Select-Object -First 1).AccessReviewStageId
  } | Format-List
  $Inst.Stages | Select-Object -First 1 |
      Format-List AccessReviewStageId, AccessReviewInstanceId, AccessReviewDefinitionId
  ```

  **Expect:** three non-empty values in the first block, and all three properties populated in the
  second. The second block is a dry run of check 6.2 -- if it passes here, 6.1 and 6.2 are runnable.
  **Failure looks like:** `AccessReviewInstanceId` or `AccessReviewDefinitionId` `$null`. That is
  check 6.2's own failure mode, so do not "fix" it in setup -- record it as 6.2's result.
  **Result:**

### 6.0 teardown -- run after section 6, and after section 7 if it reused these reviews

```powershell
# 1. the reviews created above
Remove-OERAccessReviewDefinition -DisplayName 'oer-live-ar-multistage' -WhatIf
# and the recurring one, if you created it
# Remove-OERAccessReviewDefinition -DisplayName 'oer-live-ar-recurring' -WhatIf

# 2. the assignment, ONLY if S3 created it
Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap' -User '<assignee-upn>' |
    ForEach-Object { Remove-OERAccessPackageAssignment -AssignmentId $_.Id -WhatIf }
```

Read both `-WhatIf` plans before dropping the switch, as section 8 requires. Leave the assignment in
place if check 5.6 has not been run yet -- it needs one.

**What cannot be removed, honestly:**

- **Instances.** There is no delete for an `accessReviewInstance`, in this module or in Graph.
  `Stop-OERAccessReviewInstance -Definition '<def-id>' -Instance '<inst-id>'` ends a running instance
  but does not delete it, and Learn notes "You can't restart a review after it's stopped." Instances
  disappear only when their parent definition is deleted.
- **Stages.** The same: no delete. They exist and disappear with the instance.
- **Decisions and their effects.** If a decision was recorded and applied, the resulting change to the
  access package assignment is a real change, and deleting the review does not reverse it. This is
  why S5 does not pass `-AutoApplyDecisions`. If you enabled it anyway, re-check S3's assignment after
  teardown and re-create it if the review revoked it.
- **The catalog, access package, policy and resource roles.** Leave them. Sections 4 and 5 use them,
  and "Setup, once" owns their lifecycle, not this block.

### 6.0 -- what could NOT be determined while writing this block

Carried here rather than dropped, so nobody re-derives it. None of these are defects; they are gaps
in what Microsoft documents or in what this repository can prove offline.

1. **How long an instance takes to appear.** Learn documents that a delay exists ("the start time
   could vary a few hours based on system processing") but gives no figure, and none at all for the
   shape S5 uses. No number has been invented. S7 says to poll and to record the observed wait.
2. **Whether a `OneTime` review with no `recurrence` produces an instance measurably faster than a
   `Weekly` review starting today.** The reasoning in S5 comes from the shape of the request body (no
   schedule to wait on), not from a documented statement, and no Learn page comparing the two was
   found. If S7 is slow with `OneTime`, that reasoning is wrong -- say so on S7's result line.
3. **The exact format of `accessReviewStage.id`.** Learn documents it only as "Unique identifier of
   the stage. Read-only." Whether it is a GUID or the `stageId` string supplied in `stageSettings`
   could not be confirmed from Learn or from this repository. S8 asks the operator to record it.
4. **Whether an instance and a stage are still created when the scope query matches zero
   assignments.** Learn does not say. S3 sidesteps the question by ensuring at least one assignment
   exists; what happens without one could not be established.
5. **Whether Graph accepts a definition body with no `recurrence` key in every tenant.** This
   module's `OneTime` path omits the key entirely, and `docs/live-verification/pr53-checklist.md`
   check 6.11 shows a `OneTime` review already living in this tenant with no recurrence pattern, so it
   evidently works here. No Learn statement was found declaring `settings.recurrence` optional -- only
   examples that always include it.
6. **Whether `-DurationInDays` on the definition has any effect once `stageSettings` is present.**
   Learn says stage settings are used "instead of the corresponding settings in the
   accessReviewScheduleDefinition object and its settings, reviewers, and fallbackReviewers
   properties", which implies the definition-level duration is ignored, but does not name
   `instanceDurationInDays` specifically. S5 keeps the numbers consistent rather than relying on
   either reading.
7. **Whether the tenant already has a usable multi-stage review.** `pr53-checklist.md` checks 5.8 and
   5.9 refer to a `<two-stage-review>` that was run against successfully on 2026-08-24. If it still
   exists, S4-S6 can be skipped and its id used directly -- but its display name was never recorded,
   so it could not be named here.

---

- [ ] **6.1 A stage now pipes into the decision reader.** **Requires the MULTI-STAGE review from 6.0.**
  Graph builds an instance's `stages` collection only from the definition's `stageSettings`, so on a
  single-stage review `$Inst.Stages` is legitimately EMPTY, nothing reaches the pipe, and the cmdlet
  prints nothing. That is not a failure of this check -- it means the review under test is
  single-stage. Go back to 6.0 S5 and create one with `-Stage`.

  ```powershell
  $Inst = Get-OERAccessReviewInstance -Definition '<def-id>' -IncludeStages
  $Inst.Stages | Select-Object -First 1 | Get-OERAccessReviewInstanceDecision -Verbose
  ```

  **Expect:** the stage-scoped decisions, and the verbose URI ends
  `.../definitions/<def>/instances/<inst>/stages/<stage>/decisions`. **The URI is the proof, not the
  row count** -- a stage that has not started yet can legitimately carry zero decisions, and this
  check is about where the request went.
  **Failure looks like:** prompts for `-Definition` and `-Instance` -- the parent ids did not land on
  the stage shape.
  **Result:**

- [ ] **6.2 The stage shape carries its parents.** **Requires the MULTI-STAGE review from 6.0**, for
  the same reason as 6.1: with no `stageSettings` on the definition there is no `stages` collection,
  `$Inst.Stages` is empty, `Select-Object -First 1` yields nothing and `Format-List` prints nothing.
  Empty output here means single-stage, not a missing property.

  ```powershell
  $Inst.Stages | Select-Object -First 1 | Format-List *
  ```

  **Expect:** `AccessReviewStageId`, `AccessReviewInstanceId`, `AccessReviewDefinitionId` all
  populated, alongside the original six properties.
  **Failure looks like:** any of the three missing or `$null`.
  **Result:**

- [ ] **6.3 `Set-OERAccessReviewDefinition` accepts a display name.**

  ```powershell
  Set-OERAccessReviewDefinition -Id '<the review display name>' -DisplayName '<new name>' -WhatIf -Verbose
  ```

  **Expect:** the name resolves to a definition id and the plan targets it.
  **Failure looks like:** a 404 / `AccessReviewDefinitionNotFound` -- the name was sent as an id.
  **Result:**

- [ ] **6.4 A GUID still short-circuits with no lookup.**

  ```powershell
  Set-OERAccessReviewDefinition -Id '<def-guid>' -DisplayName '<new name>' -WhatIf -Verbose
  ```

  **Expect:** no display-name query in the verbose output; straight to the definition.
  **Failure looks like:** a `displayName eq '<guid>'` filter going out.
  **Result:**

- [ ] **6.5 Self-review mixed with a named reviewer is refused.** `New-OERAccessReviewDefinition` has
  **no `-Group` parameter** -- this module creates access-package-scoped reviews only, so the review
  is scoped with `-AccessPackage` plus `-AssignmentPolicy`, both mandatory, alongside mandatory
  `-DisplayName`, `-DescriptionForAdmins`, `-DescriptionForReviewers`, `-Recurrence` and `-StartDate`.

  ```powershell
  New-OERAccessReviewDefinition -DisplayName 'oer-live-mix' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage 'oer-live-ap' -AssignmentPolicy '<policy-guid>' `
      -Recurrence OneTime -StartDate (Get-Date) `
      -SelfReview -Reviewer '<reviewer-upn>' -WhatIf
  ```

  **Expect:** a `MutuallyExclusiveReviewer` error, and NO Graph call beyond the auth handshake. The
  guard runs before scope resolution and before reviewer resolution, so neither `<policy-guid>` nor
  `<reviewer-upn>` is looked up -- the check still holds even if one of them is wrong. Before the fix,
  `-SelfReview` was silently ignored and the named reviewer won.
  **Failure looks like:** the review being planned with the named reviewer and no complaint. A
  `PackageNotFound` / `AmbiguousAccessPackageName` / `UserNotFound` instead of
  `MutuallyExclusiveReviewer` is ALSO a failure: it means the guard ran too late.
  **Result:**

- [ ] **6.6 The same guard on the update path.**

  ```powershell
  Set-OERAccessReviewDefinition -Id '<def-id>' -SelfReview -Manager -WhatIf
  ```

  **Expect:** the same error.
  **Failure looks like:** silence.
  **Result:**

- [ ] **6.7 An existing apply-document with a mixed reviewer set still applies.** This is the
  back-compat guarantee -- the cmdlet errors, but the apply engine must warn and keep working,
  because such documents exist and worked before.

  Save this as `oer-live-ar-mixed.json`. It is the FULL document, not a fragment -- `version` is
  required at the root, and `displayName`, `accessPackage` and `assignmentPolicy` are required on
  every `accessReviews` element:

  ```json
  {
    "version": "1.0",
    "accessReviews": [
      {
        "displayName": "oer-live-ar-mixed",
        "accessPackage": "oer-live-ap",
        "assignmentPolicy": "<policy-guid>",
        "descriptionForAdmins": "Live verification of check 6.7. Safe to delete.",
        "descriptionForReviewers": "Live verification. No action needed.",
        "recurrence": "OneTime",
        "durationInDays": 5,
        "reviewers": [ "manager", "self" ],
        "fallbackReviewers": [ "<reviewer-upn>" ]
      }
    ]
  }
  ```

  **`fallbackReviewers` is load-bearing and must not be dropped.** A manager reviewer with no
  fallback is reported `Failed` by the handler by design (Graph rejects it as "Policy is invalid due
  to invalid criteria"), which would make this check fail for a reason that has nothing to do with
  the `self`/`manager` mix it exists to test. Validated offline as written, placeholders and all:
  `Test-OERStructure -Path ./oer-live-ar-mixed.json` returns `Valid : True` with an EMPTY `Errors`
  collection. Drop the `fallbackReviewers` line and `Errors` instead holds one item, of
  `Severity = Warning`, predicting exactly that `Failed`. `Errors` is the property name on the
  returned object -- there is no `Findings` member -- and it carries Warning-severity items too, so
  a non-empty `Errors` alongside `Valid : True` is a warning, not a schema error.

  ```powershell
  Test-OERStructure -Path ./oer-live-ar-mixed.json | Format-List *
  Invoke-OERStructure -Path ./oer-live-ar-mixed.json -Include AccessReviews -WhatIf
  # then, to actually exercise the handler, re-run without -WhatIf
  ```

  **Expect:** a WARNING naming the element -- "reviewers[] declares 'self' together with a named or
  manager reviewer ... 'self' is dropped" -- the manager reviewer applied, and the result NOT
  `Failed`. **Failure looks like:** a `Failed` result -- an existing document stopped working.
  **Teardown:** `Remove-OERAccessReviewDefinition -DisplayName 'oer-live-ar-mixed' -WhatIf`, then
  again without the switch.
  **Result:**

- [ ] **6.8 Non-positive occurrence and duration values are refused at bind time.** Same scope shape
  as 6.5 -- there is no `-Group`.

  ```powershell
  New-OERAccessReviewDefinition -DisplayName 'oer-live-x' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage 'oer-live-ap' -AssignmentPolicy '<policy-guid>' `
      -Recurrence OneTime -StartDate (Get-Date) `
      -Reviewer '<reviewer-upn>' -Occurrences 0 -WhatIf

  New-OERAccessReviewDefinition -DisplayName 'oer-live-x' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage 'oer-live-ap' -AssignmentPolicy '<policy-guid>' `
      -Recurrence OneTime -StartDate (Get-Date) `
      -Reviewer '<reviewer-upn>' -DurationInDays 0 -WhatIf
  ```

  **Expect:** a parameter-validation error naming the PUBLIC cmdlet, with no Graph call. `0` fails
  `ValidateRange(1, ...)` during parameter binding, so the surrounding values are never used -- they
  are present only so the binder has a resolvable parameter set to bind INTO. Before the fix,
  `-Occurrences 0` bound fine, reached Graph, and then died with an uncaught terminating error from a
  private helper -- immune to `-ErrorAction`.
  **Failure looks like:** an error naming `New-OERAccessReviewRecurrence`, or any Graph traffic.
  **Result:**

- [ ] **6.9 A long duration is still allowed.** No upper bound was added, because Microsoft
  documents none.

  ```powershell
  New-OERAccessReviewDefinition -DisplayName 'oer-live-long' `
      -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
      -AccessPackage 'oer-live-ap' -AssignmentPolicy '<policy-guid>' `
      -Recurrence OneTime -StartDate (Get-Date) `
      -Reviewer '<reviewer-upn>' -DurationInDays 400 -WhatIf
  ```

  **Expect:** accepted locally (Graph may still reject it -- that is fine and is their call), and a
  `What if:` plan naming `oer-live-long`.
  **Failure looks like:** a local ValidateRange error, meaning an upper bound crept in.
  **This one is NOT free.** Unlike 6.5, `-WhatIf` here suppresses only the POST: the access package,
  assignment policy and reviewer lookups all go out to Graph before `ShouldProcess` is reached. They
  are reads and harmless, but it does mean 6.9 needs REAL values in `<policy-guid>` and
  `<reviewer-upn>` -- a `PackageNotFound` or `UserNotFound` here is a bad placeholder, not a finding.
  **Result:**

---

## 7. Paging

Not an audit finding -- a scoped addition from PR #36's "Deliberately NOT fixed", point 3. The
`@odata.nextLink` contract was verified against
https://learn.microsoft.com/graph/paging : the property is literally `@odata.nextLink`, it is an
absolute URL to be followed verbatim as an opaque string, and the final page simply omits it.

These checks need a collection larger than one server page. If you cannot produce one, say so on the
result line -- an unrun paging check is the one most likely to hide a real defect.

- [ ] **7.1 Access review decisions return every page.**

  ```powershell
  $D = Get-OERAccessReviewInstanceDecision -Definition '<def-id>' -Instance '<inst-id>'
  $D.Count
  ```

  **Expect:** the full decision count, matching what the portal shows.
  **Failure looks like:** a round number that smells like a page size (100, 200) and is less than the
  portal's count.
  **Result:**

- [ ] **7.2 Access review instances return every page.**

  ```powershell
  (Get-OERAccessReviewInstance -Definition '<recurring-def-id>').Count
  ```

  **Expect:** every instance of the recurring review.
  **Failure looks like:** truncation at a page boundary.
  **Result:**

- [ ] **7.3 Access package assignments return every page.**

  ```powershell
  (Get-OERAccessPackageAssignment -AccessPackage 'oer-live-ap').Count
  ```

  **Expect:** the full count. This read uses `$expand=target,accessPackage`, so rows are large and
  the server page size will be small -- truncation here is likely if the fix did not land.
  **Failure looks like:** fewer than the portal shows.
  **Result:**

- [ ] **7.4 The PIM-for-Groups rule read is complete.**

  ```powershell
  Get-OERGroupPimPolicy -Group oer-live-pim -AccessType member | Format-List *
  ```

  **Expect:** every policy field populated as before. This endpoint returns roughly 17 rules, below
  any page size, so this is a regression guard rather than a truncation check.
  **Failure looks like:** any field that was populated before now empty.
  **Result:**

- [ ] **7.5 THE IMPORTANT ONE -- the apply engine sees every resource role binding.**

  **CORRECTION, and it matters for how you read the result.** An earlier draft of this checklist
  said a truncated read would, under `-Prune`, DELETE live bindings it had not seen. **That is
  wrong**, and the Task 7 reviewer proved it: the prune loop iterates only the bindings it read, so
  an unseen binding is never a delete candidate. The two real harms of truncation are:

  1. **A spurious `Add`** for a declared binding that happens to live on page 2 -- the engine cannot
     see it, so it tries to create it again.
  2. **Silent UNDER-pruning** -- an undeclared live binding on page 2 is never reported `Extra` and
     never removed, so `-Prune` reports a clean package while stale bindings survive. This is the
     quieter and more dangerous of the two, because it looks like success.

  With an access package carrying **more resource role bindings than one server page**, run
  `Invoke-OERStructure -WhatIf` on a document declaring exactly the bindings that already exist.

  **Expect:** every binding reported `Unchanged`; no `Add`.
  **Failure looks like:** an `Add` record for a binding that demonstrably already exists.
  **Result:**

- [ ] **7.5b The under-pruning half.** Add a resource role binding that the document does NOT
  declare, and make sure it is one that would land beyond the first page. Then run with `-Prune`.

  **Expect:** exactly one `Extra` (without `-Prune`) or `Removed` (with it), naming that binding.
  **Failure looks like:** a clean run reporting nothing -- the engine never saw the binding, so it
  silently left stale state behind while claiming convergence. Read the `-WhatIf` plan first.
  **Result:**

---

## 8. Administrative units and the apply engine -- run these LAST

Closes `prom-au-crud-id-displayname-split`,
`CONS-au-member-surface-has-no-read-or-pipeline-story`, `A-au-scopedrole-role-no-paramset`,
`prom-au-scopedrole-principalid-inert-on-pipe`, `B-structure-path-not-pipeline`,
`A-inventory-catalog-inline-guid-branch`.

The AU cmdlets had their `-Id`/`-DisplayName` parameter sets collapsed into one
`-AdministrativeUnit` parameter with `[Alias('AdministrativeUnitId','Id','DisplayName')]`. Every old
spelling must still bind.

- [x] **8.1 All four spellings bind.**

  ```powershell
  Get-OERAdministrativeUnit -AdministrativeUnit   oer-live-au
  Get-OERAdministrativeUnit -Id                   oer-live-au
  Get-OERAdministrativeUnit -DisplayName          oer-live-au
  Get-OERAdministrativeUnit -AdministrativeUnitId oer-live-au
  ```

  **Expect:** four identical results.
  **Failure looks like:** any spelling failing -- that would be a breaking rename.
  **Result:**

- [x] **8.2 A GUID goes to the direct read, a name to the filter.**

  ```powershell
  Get-OERAdministrativeUnit -AdministrativeUnit '<au-guid>' -Verbose
  Get-OERAdministrativeUnit -AdministrativeUnit 'oer-live-au' -Verbose
  ```

  **Expect:** the first hits `administrativeUnits/<guid>` directly; the second issues a
  `displayName eq` filter. **Failure looks like:** a `displayName eq '<guid>'` filter -- the GUID
  dispatch is missing.
  **Result:**

- [x] **8.3 Splatting the old key still works.** The apply engine splats `@{ Id = ... }` in six
  places.

  ```powershell
  $P = @{ Id = 'oer-live-au' }
  Get-OERAdministrativeUnit @P
  ```

  **Expect:** succeeds. **Failure looks like:** a bind failure -- the apply engine would be broken.
  **Result:**

- [x] **8.4 An AU apply-document still applies.** Run your existing AU structure document through
  `Invoke-OERStructure -WhatIf`.

  **Expect:** the same plan as before this PR.
  **Failure looks like:** any bind failure or a changed plan.
  **Result:**

- [x] **8.5 The member shape carries its parent, and the member pipe targets correctly.**

  ```powershell
  $Au = Get-OERAdministrativeUnit -AdministrativeUnit oer-live-au -IncludeMembers
  $Au.Members | Select-Object -First 1 | Format-List *
  $Au.Members | Select-Object -First 1 | Remove-OERAdministrativeUnitMember -WhatIf -Verbose
  ```

  **Expect:** `AdministrativeUnitId` and `PrincipalId` present on the member; and the removal URI is
  `administrativeUnits/<AU id>/members/<principal id>` -- the AU id in the AU segment, the principal
  in the member segment.
  **Failure looks like:** the member's own id appearing in the AU segment.
  **Result:**

- [x] **8.6 Conflicting role inputs are refused.**

  ```powershell
  Add-OERAdministrativeUnitScopedRole -AdministrativeUnit oer-live-au -User '<upn>' `
      -RoleName 'User Administrator' -RoleId '<some-other-role-guid>' -WhatIf
  ```

  **Expect:** an `AmbiguousRole` error, no request. Before the fix, `-RoleId` silently won and the
  OUTPUT echoed the ignored `-RoleName`.
  **Failure looks like:** a plan that succeeds and reports the role name you did not get.
  **Result:**

- [x] **8.7 The emitted role name matches the role actually assigned.**

  ```powershell
  Add-OERAdministrativeUnitScopedRole -AdministrativeUnit oer-live-au -User '<upn>' -RoleId '<role-guid>'
  ```

  **Expect:** the returned object's `RoleName` is the display name OF THAT GUID.
  **Failure looks like:** a blank or wrong role name.
  **Result:**

- [x] **8.8 The ordinary scoped-role removal pipe still works.**

  ```powershell
  Get-OERAdministrativeUnitScopedRole -AdministrativeUnit oer-live-au | Remove-OERAdministrativeUnitScopedRole -WhatIf
  ```

  **Expect:** one plan per membership, no errors. This is the regression guard -- the naive fix for
  the next check would have broken exactly this.
  **Result:**

- [x] **8.9 A conflicting explicit principal on that pipe is refused.**

  ```powershell
  Get-OERAdministrativeUnitScopedRole -AdministrativeUnit oer-live-au |
      Remove-OERAdministrativeUnitScopedRole -PrincipalId '<a different principal guid>' -WhatIf
  ```

  **Expect:** an `AmbiguousPrincipal` error and no removal. Before the fix the explicit
  `-PrincipalId` was silently discarded.
  **Failure looks like:** removals planned against the piped memberships, ignoring what you asked
  for.
  **Result:**

- [x] **8.10 A piped file path now reaches the document reader.**

  ```powershell
  Get-ChildItem ./live/doc.json | Test-OERStructure
  './live/doc.json'              | Test-OERStructure
  ```

  **Expect:** both validate THE FILE'S CONTENT. Before the fix the first serialized the `FileInfo`
  object and validated that, and the second failed with "The structure document root must be a
  single JSON object."
  **Failure looks like:** a validation result that does not reflect the file.
  **Result:**

- [x] **8.11 The inventory object pipe still works.** Regression guard for 8.10.

  ```powershell
  Get-OERInventory -Include Groups | Test-OERStructure
  ```

  **Expect:** `Valid` as before.
  **Failure looks like:** the object being mistaken for a path.
  **Result:**

- [x] **8.12 The catalog filter is resolved once, not twice.**

  ```powershell
  Get-OERInventory -Catalog 'OER-CAT-A' -Verbose
  ```

  **Expect:** ONE catalog resolution in the verbose output, not two, and both the Catalogs and
  AccessPackages sections still populated identically to before.
  **Failure looks like:** two resolutions (the fix did not land), or a section that lost data (it
  landed wrong).
  **Result:**

- [x] **8.13 A narrowed include pays for no catalog call at all.**

  ```powershell
  Get-OERInventory -Include Groups -Catalog 'OER-CAT-A' -Verbose
  ```

  **Expect:** zero catalog reads.
  **Failure looks like:** a catalog read -- the hoist was made unconditional.
  **Result:**

---

## What needs NO live test, and why

These findings are fully provable from source, from a mocked test, or from documentation. Nothing on
this list touches a tenant.

| Finding | Why no live test |
|---|---|
| `A-scope-pipeline-binding-inconsistent` | Resolved as documentation only. Both verifier notes rejected the proposed code change; no behaviour changed. |
| `F-arm-id-vs-resourceid-split` | Documentation only. The four ARM inventory converters were deliberately NOT changed. |
| `T1NEW-ap-policy-displayname-alias-help-mismatch` | Documentation only. The proposed code fix was proven to raise `ParameterNameConflictsWithAlias` on every invocation and was rejected. |
| `C-convert-armhttpexception-stale-help` | Comment-based help in a private helper. |
| `T7+T8NEW-claudemd-armapiversion-list-incomplete` | Documentation. The api-version list was verified by grepping source, and a QA gate now pins it. |
| `E-common-role-set-only-five` | Documentation, plus a `TabExpansion2` registration test. The curated set was deliberately left at five. |
| `B-ar-converter-help-references-nonexistent-cmdlets` | One help line, plus a new static gate that resolves every `Verb-OER*` token in source against the real cmdlet roster. |
| `B-ar-instance-definitionid-dead-property` | Resolved as a documented exception with NO code change -- the drift the rule guards against is structurally impossible here (both copies are stamped from one local in one object literal). |
| `CONS-outputtype-missing-on-eleven-cmdlets` | `[OutputType]` is metadata and does not constrain runtime output. An AST gate now enforces it. |
| `CONS-duration-encoder-bypassed-in-new-oerpimruleset` | Unreachable behaviour change -- the sole caller is bounded by `[ValidateRange(1, 24)]`, for which both encoders produce identical output. A static gate now prevents recurrence. |
| `CONS-alias-property-sweep-stopped-at-three-shapes` | `AliasProperty` behaviour was verified empirically (binds through the pipeline, appears in `PSObject.Properties.Name`, survives `Select-Object`, serializes with `ConvertTo-Json`). Format views and pipes are covered by mocked tests. |
| `CONS-principal-name-resolution-has-two-owners` | An efficiency change. The output value is asserted unchanged by mocked tests; a live run would confirm only that it is faster. **If you want one thing checked: run `Get-OERInventory` against a subscription with many role assignments and confirm the display names still populate.** |
| `T7+T8NEW-new-assignment-cmdlets-inline-principal-fanout` | Refactor onto an existing helper. Its user-visible surface is covered by checks 4.4 through 4.6. |
| `A-condition-version-no-validateset` (apply path) | An apply document declaring `conditionVersion: "1.0"` failed at ARM before and fails locally now. Both are failures; only the message changed. |

---

## Sign-off

- [ ] Every box above carries a written result.
- [ ] Any check that could not be run says so explicitly, with the reason.
- [ ] Any defect found has been reported back before merge.

**Verified by:** ______________________  **Date:** ______________
