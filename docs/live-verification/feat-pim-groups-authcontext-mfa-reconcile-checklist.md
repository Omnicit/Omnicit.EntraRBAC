# Live verification checklist -- feat/pim-groups-authcontext-mfa-reconcile (issue #54)

**This branch does not merge until every box below has a written result.** A box with no result
line filled in is not a passed check -- it is an unrun one. If a check turns out to be impossible
to run, write "cannot be verified, and therefore we do not know" on its result line and say why; do
not leave it blank and do not tick it.

## What changed and why this needs a live tenant

Entra PIM treats an enabled Conditional Access **authentication context** and
**MultiFactorAuthentication on activation** as mutually exclusive -- a policy cannot require both at
once. The Azure PIM (ARM) write path already reconciled this; the Graph PIM-for-groups write path
did not, so a group's `Set-OERGroupPimPolicy` call could silently leave (or create) a policy Graph
itself will never actually enforce as configured. This branch:

- extracts the exclusion rule into one shared, transport-free decision helper,
  `Resolve-OERPimActivationConflict`;
- migrates the existing ARM patch builder onto it, behaviour-preservingly;
- makes `Set-OERGroupPimPolicy` enforce the rule, validate a supplied `-AuthenticationContextId`
  against the tenant's actual Conditional Access authentication contexts, and report exactly what
  it sent (not merely what was asked for);
- makes the apply-engine diff (`Resolve-OERGroupPimPolicyChange`) reconcile the same rule, so a
  document declaring both converges to a stable state instead of flapping on every re-apply;
- adds a new public read cmdlet, `Get-OERAuthenticationContext`;
- adds an offline `Test-OERStructure` Warning for a document declaring both; and
- documents the rule at `docs/development/rationale.md#mfa-authcontext-exclusion`.

None of this is exercised by the mocked unit suite in any way that proves Entra PIM itself behaves
as the module now assumes. Every check below writes to, or reads from, a real tenant.

**Run sections 1-9 in order** -- most of them build on the live state the previous one left behind
(the group's policy is deliberately walked through every case in sequence: context set, context
cleared, both requested, MFA requested against a live context, invalid ids, degraded read, then the
apply engine's own path over the same rule). Section 10 (ARM) is independent and can run any time
after section 1.

## Setup, once

You need:

- **One PIM-for-groups-onboarded security group** with at least one eligible member (member access
  type) -- add one first if needed: `Add-OERGroupEligibility -Group <group> -User <user> -AccessType
  member -DurationDays 30`. Note whether the group is otherwise used by anything else in this
  tenant; sections 2-9 repeatedly change its activation policy.
- **The eligible member's own credentials** (or the ability to sign in as them), for section 3.
- **A published Conditional Access authentication context** already defined in the tenant (Entra
  admin center > Protection > Conditional Access > Authentication contexts), and ideally a SECOND
  one left unpublished for check 7.2. If the tenant has none, create one (`c1`, "Live check context")
  and leave "Publish to apps and services" ON; create a second (`c2` or similar) and leave it OFF.
- **An Azure RBAC role assignment at a scope you can freely edit** (subscription, resource group, or
  management group) with Azure PIM already enabled, for section 10.
- **For section 8**, a second app registration (or other credential) granted `Group.Read.All` and
  `RoleManagementPolicy.ReadWrite.AzureADGroup` but explicitly NOT `AuthenticationContext.Read.All`.

Set these once and reuse them in every command block below:

```powershell
$Alias = '<your-tenant-alias>'
$Group = '<your-test-group>'        # PIM-onboarded, >= 1 eligible member
$Role  = '<your-test-role>'         # e.g. 'Reader'
$Sub   = '<your-test-subscription>' # or swap for -ResourceGroup / -ManagementGroup below

Connect-OER -TenantAlias $Alias -IncludeARM
$GroupObj = Get-OERGroup -DisplayName $Group
$RoleParams = @{ Role = $Role; Subscription = $Sub }
```

| Placeholder | What it is |
|---|---|
| `<your-tenant-alias>` | The `Get-OERConfiguration` alias for the test tenant. |
| `<your-test-group>` | The PIM-onboarded security group from Setup. |
| `<your-test-role>` / `<your-test-subscription>` | The Azure RBAC role/scope from Setup, used only in section 10. |
| `c1` | The claim value of the PUBLISHED authentication context from Setup. Every command below that names `c1` literally assumes this is the value you created; substitute your own if different. |
| `<unpublished-id>` | The claim value of the UNPUBLISHED authentication context from Setup, used only in check 7.2. |
| `<degraded-app-id>` / `<cert>` | The scoped-down credential from Setup, used only in section 8. |

---

### 1. Preparation

- [x] **1.1 Resolve the group and confirm a starting policy with MFA on activation.**

  ```powershell
  $Policy = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $Policy | Select-Object PolicyId, ActivationMaxHours, ActivationEnabledRules, AuthenticationContextId
  ```

  **Expect:** this succeeds and returns a `PolicyId` (a GUID). If it instead raises
  `PimPolicyNotFound`, the group is not yet onboarded -- run
  `Add-OERGroupEligibility -Group $Group -User <user> -AccessType member -DurationDays 30` and
  re-run. `AuthenticationContextId` should be empty at this point; if `ActivationEnabledRules` does
  not already contain `MultiFactorAuthentication`, set it now so the rest of this checklist has a
  real starting condition to reconcile away:
  `Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -ActivationEnabledRules
  MultiFactorAuthentication,Justification`.
  **Result:**

- [x] **1.2 Record the identifiers.**

  **Group id:** ______________________________
  **Policy id (member):** ______________________________

- [x] **1.3 `Get-OERAuthenticationContext` -- first live exercise of the new cmdlet.**

  ```powershell
  Get-OERAuthenticationContext | Format-Table AuthenticationContextId, DisplayName, IsAvailable, Description -AutoSize
  ```

  **Expect:** one row per Conditional Access authentication context defined in the tenant. Open
  Entra admin center > Protection > Conditional Access > Authentication contexts side by side and
  confirm: the same claim values (`c1`, `c2`, ...) and display names appear, and `IsAvailable` reads
  `True` only for a context whose "Publish to apps and services" toggle is ON in the portal --
  `False` for the one you deliberately left unpublished in Setup.
  **Failure looks like:** a context the portal shows is missing here, or `IsAvailable` disagrees
  with the portal's publish toggle for any row.
  **Record which contexts are `IsAvailable = True`** (only these are usable as `-AuthenticationContextId`
  values in checks 2 and 6 below): ______________________________
  **Result:**

---

### 2. Case B -- the headline fix (setting a context clears MFA, nothing else)

- [ ] **2.1 Record the pre-state precisely.**

  ```powershell
  $Before = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $Before | Select-Object ActivationMaxHours, ActivationEnabledRules, AuthenticationContextId
  ```

  **Result:**

- [x] **2.2 Set the authentication context, changing nothing else.**

  ```powershell
  $R = Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId 'c1' -WarningVariable ReconcileWarn
  $ReconcileWarn
  $R | Select-Object GroupId, PolicyId, AccessType, AuthenticationContextId, ActivationEnabledRules, Applied
  ```

  **Expect:** `$ReconcileWarn` contains a warning naming the policy id and the mutual-exclusion
  reason (text like `... mutually exclusive ...`); `$R.Applied` is `$true`;
  `$R.AuthenticationContextId` is `'c1'`; `$R.ActivationEnabledRules` no longer contains
  `MultiFactorAuthentication` but still contains every OTHER entry `$Before.ActivationEnabledRules`
  had (for example `Justification`).
  **Failure looks like:** an entry other than `MultiFactorAuthentication` also disappeared
  (over-correction), or `Applied` is `$false` with no error (a rule was silently declined).
  **Result:**

- [x] **2.3 Confirm the returned summary matches what the policy actually has.**

  ```powershell
  $After = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $After | Select-Object AuthenticationContextId, ActivationEnabledRules
  Compare-Object -ReferenceObject @($R.ActivationEnabledRules | Sort-Object) -DifferenceObject @($After.ActivationEnabledRules | Sort-Object)
  ```

  **Expect:** `Compare-Object` prints nothing -- the summary's `ActivationEnabledRules` is exactly
  what a fresh read of the policy shows, not a stale echo of the caller's own list.
  `$After.AuthenticationContextId` is `'c1'`.
  **Failure looks like:** any `Compare-Object` output -- the summary reported something Graph did
  not actually persist.
  **Result:**

---

### 3. End-to-end activation (does PIM actually challenge the context?)

- [x] **3.1 As the eligible member from Setup, activate the group.**

  Sign in as that user at https://myaccess.microsoft.com (or Entra admin center > Identity
  Governance > Privileged Identity Management > My roles > Groups) and activate membership on
  `$Group`.

  **Expect:** the activation flow now challenges for the Conditional Access authentication context
  `c1` -- for example, a specific credential, a compliant-device check, or whatever control the `c1`
  Conditional Access policy actually enforces -- INSTEAD OF a plain "verify your identity" MFA
  prompt with no context tie.
  **Failure looks like:** the activation only asks for ordinary MFA with no sign that a specific
  authentication context was evaluated, meaning the claim is not actually wired to an enforcing
  Conditional Access policy, or PIM ignored it.
  **Result:**

- [x] **3.2 Confirm from the audit trail, not just the prompt UI.**

  Read Entra admin center > Identity Governance > PIM > Groups > Audit history (or Entra ID
  sign-in logs) for the activation event.

  **Expect:** the event's authentication requirement shows the `c1` authentication context claim
  was satisfied, not a bare `mfa` control with no context reference.
  **Result:**

---

### 4. Case D -- disabling a context never re-adds MFA

- [x] **4.1 Record the pre-state.**

  ```powershell
  $Before = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $Before | Select-Object AuthenticationContextId, ActivationEnabledRules
  ```

  **Result:**

- [x] **4.2 Disable the context with an explicit empty string.**

  ```powershell
  $R = Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId '' -WarningVariable D4Warn
  $D4Warn
  $R | Select-Object AuthenticationContextId, ActivationEnabledRules, Applied
  ```

  **Expect:** no mutual-exclusion reconcile warning at all (this case takes no reconcile branch --
  disabling is a one-sided change); `$R.AuthenticationContextId` is empty; and
  `$R.ActivationEnabledRules` is ABSENT from `$R` entirely (the Enablement rule was never touched
  this call, so Set-OERGroupPimPolicy's honest-summary contract omits it, rather than reporting it
  present-and-unchanged).
  **Failure looks like:** `MultiFactorAuthentication` shows up in the read-back in step 4.3 below --
  disabling a context must never resurrect MFA.
  **Result:**

- [ ] **4.3 Confirm the live read.**

  ```powershell
  $After = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $After | Select-Object AuthenticationContextId, ActivationEnabledRules
  ```

  **Expect:** `AuthenticationContextId` empty; `ActivationEnabledRules` identical to
  `$Before.ActivationEnabledRules` from 4.1 -- untouched by this call.
  **Result:**

---

### 5. Case A -- both parameters in one call is refused, and nothing is patched

- [x] **5.1 Re-establish a KNOWN-GOOD live context (isolating the conflict from validation).**

  ```powershell
  Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId 'c1' | Out-Null
  $Before = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $Before | Select-Object AuthenticationContextId, ActivationEnabledRules
  ```

  **Result:**

- [x] **5.2 Request both in the same call.**

  ```powershell
  Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId 'c1' -ActivationEnabledRules MultiFactorAuthentication,Justification -ErrorVariable ConflictErr
  $ConflictErr[-1].FullyQualifiedErrorId
  ```

  **Expect:** `$ConflictErr[-1].FullyQualifiedErrorId` matches
  `MfaAuthContextConflict,Set-OERGroupPimPolicy`; the command prints NO summary object; no `Applied`
  or patch output of any kind.
  **Note:** this check deliberately uses a KNOWN-GOOD id (`c1`, confirmed to exist and be published
  in check 1.3). With an UNKNOWN context id, validation runs BEFORE the conflict check, so the
  operator would see `AuthenticationContextNotFound` instead of `MfaAuthContextConflict` -- that is
  expected, documented behaviour, exercised separately in check 7.1, not a defect of this check.
  **Result:**

- [x] **5.3 Confirm NOTHING was patched -- read the policy back and compare.**

  ```powershell
  $After = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $After | Select-Object AuthenticationContextId, ActivationEnabledRules
  Compare-Object -ReferenceObject @($Before.ActivationEnabledRules | Sort-Object) -DifferenceObject @($After.ActivationEnabledRules | Sort-Object)
  '{0} -> {1}' -f $Before.AuthenticationContextId, $After.AuthenticationContextId
  ```

  **Expect:** `Compare-Object` prints nothing, and the before/after `AuthenticationContextId` line
  shows the same value on both sides -- the read-back after the refused call is byte-identical to
  the read-back before it.
  **Failure looks like:** any difference -- the guard let a partial patch through before refusing.
  **Result:**

---

### 6. Case C -- MFA requested against a policy with a live context

- [x] **6.1 Confirm the pre-state (context live from 5.1, no MFA).**

  ```powershell
  Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member | Select-Object AuthenticationContextId, ActivationEnabledRules
  ```

  **Result:**

- [ ] **6.2 Request MFA without touching the context parameter.**

  ```powershell
  $R = Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -ActivationEnabledRules MultiFactorAuthentication,Justification -WarningVariable CaseCWarn
  $CaseCWarn
  $R | Select-Object AuthenticationContextId, ActivationEnabledRules, Applied
  ```

  **Expect:** `$CaseCWarn` names the claim value that was disabled -- the warning text matches
  `*c1*` (not merely "a context was disabled"); `$R.Applied` is `$true`; `$R.AuthenticationContextId`
  in the summary is `''` (disabled); `$R.ActivationEnabledRules` contains both
  `MultiFactorAuthentication` and `Justification`; and **no `PolicyRulesRejected` error is written**
  -- both rules must land, not one.
  **Failure looks like:** the warning never names `c1`; or the context is left enabled; or -- the
  defect this section caught on the first live run -- a second warning says
  `Rule 'Enablement_EndUser_Assignment' was not applied: MfaAndAcrsConflict: The Mfa and Acrs policy
  settings cannot be enabled simultaneously.` followed by a `PolicyRulesRejected` error, `Applied`
  `$false`, and a policy left with the context disabled and MFA never added -- NEITHER the old
  protection nor the requested one in force. That is a PATCH-ordering failure, not a reconcile
  failure: see `docs/development/rationale.md#mfa-authcontext-exclusion`.
  **Result:**

- [ ] **6.3 Confirm the live read (tick predates the corrected Expect below; re-run).**

  ```powershell
  Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member | Select-Object AuthenticationContextId, ActivationEnabledRules
  ```

  **Expect:** `AuthenticationContextId` empty **and** `ActivationEnabledRules` contains
  `MultiFactorAuthentication` and `Justification`. Both halves must hold together -- an empty
  context with MFA still absent is the failure shape from 6.2, not a pass.
  **Result:**

- [ ] **6.4 The same collision with BOTH parameters bound explicitly (no reconcile at all).**

  This is what proves the PATCH ordering is general rather than a patch on the reconcile path: here
  `-AuthenticationContextId` IS bound, so no `Resolution` is produced and both rules come straight
  from the caller's own binding. Re-enable the context first so the collision is real.

  ```powershell
  Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId 'c1' -WarningAction SilentlyContinue | Out-Null
  Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member | Select-Object AuthenticationContextId, ActivationEnabledRules
  $R = Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId '' -ActivationEnabledRules MultiFactorAuthentication,Justification -WarningVariable ExplicitWarn
  $ExplicitWarn
  $R | Select-Object AuthenticationContextId, ActivationEnabledRules, Applied
  Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member | Select-Object AuthenticationContextId, ActivationEnabledRules
  ```

  **Expect:** the read between the two calls shows `AuthenticationContextId` `c1` (the collision is
  real); `$R.Applied` is `$true` with no `PolicyRulesRejected` error; `$ExplicitWarn` carries NO
  reconcile warning (nothing was reconciled -- the caller asked for both changes itself); the final
  read shows the context empty AND `MultiFactorAuthentication` present.
  **Failure looks like:** the same `MfaAndAcrsConflict` rejection as 6.2. If 6.2 passes and this
  fails, the ordering was fixed only on the reconcile path.
  **Result:**

---

### 7. Validation -- an id that cannot be used is refused, and nothing is patched

- [x] **7.1 A non-existent claim value.**

  ```powershell
  $Before = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId 'c999' -ErrorVariable NotFoundErr
  $NotFoundErr[-1].FullyQualifiedErrorId
  $NotFoundErr[-1].Exception.Message
  $After = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $Before.AuthenticationContextId -eq $After.AuthenticationContextId
  ```

  **Expect:** `FullyQualifiedErrorId` matches `AuthenticationContextNotFound,Set-OERGroupPimPolicy`;
  the message lists the tenant's defined contexts (from check 1.3) or says "(none defined in this
  tenant)"; no object is printed; the before/after comparison is `True` -- nothing was patched.
  **Result:**

- [x] **7.2 A defined-but-unpublished claim value.**

  Use the unpublished context from Setup (claim value `<unpublished-id>`, `IsAvailable = False` in
  check 1.3).

  ```powershell
  $Before = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  Set-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member -AuthenticationContextId '<unpublished-id>' -ErrorVariable NotAvailErr
  $NotAvailErr[-1].FullyQualifiedErrorId
  $NotAvailErr[-1].Exception.Message
  $After = Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member
  $Before.AuthenticationContextId -eq $After.AuthenticationContextId
  ```

  **Expect:** `FullyQualifiedErrorId` matches
  `AuthenticationContextNotAvailable,Set-OERGroupPimPolicy`; the message names the context's display
  name and says it exists but is not published; no object is printed; before/after comparison is
  `True`.
  **Result:**

---

### 8. Degraded read -- validation must never harden into a permission requirement

- [x] **8.1 Connect as an identity that can write the policy but cannot read authentication contexts.**

  Using the second credential from Setup (granted `Group.Read.All` and
  `RoleManagementPolicy.ReadWrite.AzureADGroup`, explicitly NOT `AuthenticationContext.Read.All`),
  open a fresh session (a new terminal, so the earlier session's cached auth state is not reused)
  and connect:

  ```powershell
  Connect-OER -TenantId <tenant-id> -ClientId <degraded-app-id> -ClientCertificate <cert>
  # or: Connect-OER -TenantId <tenant-id> -ClientId <degraded-app-id> -ClientSecret <secret>
  ```

  **Result:**

- [x] **8.2 Attempt to set a context you know is valid.**

  ```powershell
  $R = Set-OERGroupPimPolicy -Group '<group-id-from-1.2>' -AccessType member -AuthenticationContextId 'c1' -WarningVariable DegradedWarn
  $DegradedWarn
  $R | Select-Object AuthenticationContextId, Applied
  ```

  **Expect:** a warning starting with `Could not verify authentication context 'c1' against the
  tenant:` and ending `Proceeding without validation.`; AND the write still succeeds --
  `$R.Applied` is `$true` and `$R.AuthenticationContextId` is `'c1'`.
  **Result:**

- [x] **8.3 Confirm the write really landed, using the ORIGINAL (fully-privileged) session.**

  ```powershell
  Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member | Select-Object AuthenticationContextId
  ```

  **Expect:** `'c1'`. This is the check that proves the new validation never hardened into a
  permission requirement -- an identity that cannot read authentication contexts must still be able
  to set one it already knows is valid, with only a warning, not a refusal.
  **Failure looks like:** a terminating or non-terminating error instead of a warning, or the write
  silently not happening despite no error.
  **Result:**

---

### 9. Apply convergence -- a document declaring both settles instead of flapping

- [x] **9.1 Offline: confirm the new schema Warning fires, and does not block validation.**

  ```powershell
  New-Item -ItemType Directory -Path './live' -Force | Out-Null
  @"
  {
    "version": "1.0",
    "tenantAlias": "$Alias",
    "groups": [
      {
        "displayName": "$Group",
        "pimPolicy": {
          "authenticationContextId": "c1",
          "activationEnablement": [ "MultiFactorAuthentication", "Justification" ]
        }
      }
    ]
  }
  "@ | Set-Content -Path './live/pim-conflict.json' -Encoding utf8

  $Validation = Test-OERStructure -Path './live/pim-conflict.json'
  $Validation.Valid
  $Validation.Errors | Where-Object Severity -eq 'Warning' | Format-List Section, Item, Path, Message
  ```

  **Expect:** `$Validation.Valid` is `$true` (a Warning never blocks an apply), and exactly one
  Warning finding whose `Message` matches `*mutually exclusive*` and whose `Path` is
  `groups[0].pimPolicy`.
  **Failure looks like:** no Warning finding at all -- the offline gate does not catch what the
  write path is about to resolve; or `Valid` is `$false` -- the Warning was shipped as an Error and
  would block every apply of a document that used to validate cleanly.
  **Result:**

- [x] **9.2 First apply -- must report `Updated`.**

  ```powershell
  Invoke-OERStructure -Path './live/pim-conflict.json' -Confirm:$false
  ```

  **Expect:** one `Updated` record for `pimPolicy (member)` on `$Group`, whose detail text names the
  reconcile (for example `activationEnablement=[Justification] (...)`, with the parenthetical
  carrying the same mutual-exclusion reason text used elsewhere).
  **Result:**

- [x] **9.3 Second apply, same document, unchanged -- the convergence proof.**

  ```powershell
  Invoke-OERStructure -Path './live/pim-conflict.json' -Confirm:$false
  ```

  **Expect:** `Unchanged` for `pimPolicy (member)` -- NOT another `Updated`. Run 1 clears MFA out of
  the live rule; run 2 must see the reconciled state as already matching rather than sending MFA
  back and clearing the context on the run after that.
  **Failure looks like:** `Updated` again on run 2, or (if you re-run a third and fourth time) an
  alternating Updated/Updated pattern -- the pre-fix flapping bug.
  **Result:**

- [x] **9.4 Confirm the resulting live state.**

  ```powershell
  Get-OERGroupPimPolicy -Group $GroupObj.Id -AccessType member | Select-Object AuthenticationContextId, ActivationEnabledRules
  ```

  **Expect:** `AuthenticationContextId` is `'c1'`; `ActivationEnabledRules` contains `Justification`
  but not `MultiFactorAuthentication`.
  **Result:**

---

### 10. ARM regression -- Set-OERRoleManagementPolicy is unchanged by the migration

This section exercises `source/Private/Resolve-OERPolicyRulePatch.ps1` after it was migrated onto
the shared `Resolve-OERPimActivationConflict` helper. The mocked regression suite already proved
the decision logic is behaviourally identical; this is the first time it runs against a real ARM
policy.

- [x] **10.1 A context alone.**

  ```powershell
  Get-OERRoleManagementPolicy @RoleParams | Select-Object AuthenticationContextId, RequireMfaOnActivation
  Set-OERRoleManagementPolicy @RoleParams -AuthenticationContextId 'c1'
  Get-OERRoleManagementPolicy @RoleParams | Select-Object AuthenticationContextId, RequireMfaOnActivation
  ```

  **Expect:** succeeds; `AuthenticationContextId` is now `'c1'`; `RequireMfaOnActivation` is
  unchanged (assume `$false` going in -- confirm with the first read).
  **Result:**

- [x] **10.2 MFA alone, while the context from 10.1 is still live.**

  ```powershell
  Set-OERRoleManagementPolicy @RoleParams -RequireMfaOnActivation $true
  Get-OERRoleManagementPolicy @RoleParams | Select-Object AuthenticationContextId, RequireMfaOnActivation
  ```

  **Expect:** succeeds; `RequireMfaOnActivation` is now `$true`; AND `AuthenticationContextId` is now
  empty. This call never mentioned the context, but ARM's full-rule-set PATCH means a pre-existing
  invalid combination is resolved even on an unrelated change -- this is the
  `-ResolveUnrequestedConflict` behaviour that is deliberately ARM-only (see
  `docs/development/rationale.md#mfa-authcontext-exclusion`) and existed BEFORE this branch; confirm
  it survived the migration unchanged.
  **Result:**

- [x] **10.3 Both explicitly in the same call -- must be refused, and must throw the mutual-exclusion error.**

  ```powershell
  Set-OERRoleManagementPolicy @RoleParams -AuthenticationContextId 'c1' -RequireMfaOnActivation $true -ErrorVariable ArmConflictErr
  $ArmConflictErr[-1].FullyQualifiedErrorId
  $ArmConflictErr[-1].Exception.Message
  Get-OERRoleManagementPolicy @RoleParams | Select-Object AuthenticationContextId, RequireMfaOnActivation
  ```

  **Expect:** `FullyQualifiedErrorId` matches `InvalidPolicyChange,Set-OERRoleManagementPolicy`; the
  message is byte-identical to `Cannot enable both multi-factor authentication and an authentication
  context on activation; Azure PIM treats them as mutually exclusive. Set only one.` (this ARM path
  keeps the word "Azure" -- unlike the Graph/groups path's wording, which does not name a specific
  cloud); and the trailing read shows the policy unchanged from whatever 10.2 left it as -- nothing
  was patched by the refused call.
  **Result:**

- [x] **10.4 Restore the test policy afterward, for tenant hygiene.**

  ```powershell
  Set-OERRoleManagementPolicy @RoleParams -AuthenticationContextId '' -RequireMfaOnActivation $false
  ```

  **Result:**
