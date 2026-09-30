function Get-OERInventoryReadme {
    <#
    .SYNOPSIS
    Returns the Markdown README written into an Export-OERInventory bundle folder.

    .DESCRIPTION
    Produces the run-folder README that explains what each generated file is and the next steps in
    the inventory -> LLM -> apply workflow. Pure string builder: no Graph, ARM, or filesystem access.

    .EXAMPLE
    Get-OERInventoryReadme
    Returns the README Markdown as a single string.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    @'
# OER RBAC Inventory Bundle

This folder was produced by `Export-OERInventory`. It captures the RBAC-relevant slice of your
tenant's current posture -- see Coverage limits below for what is deliberately excluded -- and
includes a predefined prompt that turns it into appliable improvement proposals.

## Files

- `inventory.json` -- the canonical, round-trippable inventory, in the exact apply-document shape,
  subject to the coverage limits below (for example, only access-package-scoped access reviews
  are captured).
- `groups.json`, `administrativeUnits.json`, `catalogs.json`, `accessPackages.json`,
  `accessReviews.json`, `roleAssignments.json`, `roleManagementPolicies.json` -- the same data
  split per area, so you can feed an LLM one area at a time without hitting its context limit.
- `groupsRoster.json` -- a lightweight roster of EVERY group in the tenant, of every group type
  (names + flags), read unfiltered. Read-only context, not an apply document. It is deliberately
  wider than `inventory.json`: see "Which groups are covered" below.
- `scopeHierarchy.json` -- the management group / subscription tree. Read-only context, not an
  apply document.
- `azurePimEligibility.json` -- the Azure PIM eligible role assignments at the scopes in
  `scopeHierarchy.json`, written only when an Azure section (`RoleAssignments` or
  `RoleManagementPolicies`) is included. Read-only context, not an apply document -- see "Azure PIM
  eligibility" under Coverage limits below.
- `schema.json` -- a formal JSON Schema (draft-07) for the apply document, so a proposal can be
  validated without the module (for example with Test-Json).
- `rbac-architect-prompt.md` -- the predefined prompt. Open it, optionally edit the
  "USER PREFERENCES" block, then give it to any LLM together with the JSON files above.

## Which groups are covered

`inventory.json` and `groups.json` carry SECURITY-ENABLED groups only. They are read with the
`securityEnabled eq true` filter that `Get-OERInventory` applies by default, so a distribution
group, and a Microsoft 365 group whose `securityEnabled` is false, appear in neither -- at any
detail level, `-AllGroupsDetailed` included. Their absence from those files is not evidence of
their absence from the tenant: `groupsRoster.json` is read unfiltered and lists them.

That scope is deliberate rather than an oversight. `inventory.json` is the apply document, and
widening it widens what `Invoke-OERStructure` reconciles and, under `-Prune`, deletes. To widen it
anyway, read the inventory yourself and supply the filter you want:
`Get-OERInventory -GroupFilter "<odata filter>"`.

## Coverage limits

The apply document has nine sections only: groups, administrativeUnits, catalogs, accessPackages,
accessReviews, directoryRoleManagementPolicies, directoryRoleAssignments, roleAssignments and
roleManagementPolicies. `directoryRoleManagementPolicies` (the PIM settings of Microsoft Entra
directory roles) and `directoryRoleAssignments` (eligible and active assignments of Microsoft Entra
directory roles) are both captured in `inventory.json` (policies for roles with at least one eligible
or active assignment unless the export used `-AllDirectoryRolePolicies`; assignments that are direct
and at tenant scope -- activations and assignments inherited through a group are not listed), and may
be proposed. Four areas fall outside that model, each differently -- do not read this bundle as a
complete picture of the tenant:

- Azure resource groups and individual Azure resources are not created or managed by the document.
  A role assignment at a resource-group or resource scope does apply, but `scopeHierarchy.json`
  lists management groups and subscriptions only, so no resource-group names are available to
  propose against. Use `New-OERResourceGroup` and `Get-OERResource`.
- Eligible Azure PIM assignments are in `azurePimEligibility.json` as read-only context, not an apply section.
  Neither `roleAssignments[]` (permanent Azure RBAC only) nor `roleManagementPolicies[]` (only the
  PIM policy that governs eligibility) grants, captures or removes one. Manage them with
  `New-OEREligibleRoleAssignment` and `Remove-OEREligibleRoleAssignment`.
  Active PIM assignments that are not permanent are not captured anywhere in this bundle; use
  `New-OERActiveRoleAssignment` and `Get-OERActiveRoleAssignment`.
- A multi-stage access review is SKIPPED entirely, not exported lossily: its reviewers live under
  `stageSettings`, which `accessReviews[]` does not model, so it is skipped with a warning instead
  of being fabricated as a single-stage self review. It never appears in `accessReviews.json` or
  `inventory.json` -- its absence here is not evidence the tenant has none. Manage it directly with
  `New-OERAccessReviewStage`.
- Only ACCESS-PACKAGE-SCOPED reviews are captured at all, regardless of stage count or the
  `-AccessReviewFilter` narrowing. A review scoped to a group, an application or a directory role
  is skipped entirely and never appears in `accessReviews.json` or `inventory.json` -- again, its
  absence here is not evidence the tenant has none.

## Next steps

1. Open `rbac-architect-prompt.md`. Leave the USER PREFERENCES block untouched for best-practice
   defaults, or fill in your naming standard and depth.
2. Provide the prompt and the JSON files to any capable LLM.
3. The LLM returns three proposals: Foundational, Recommended, Advanced -- each a complete apply
   document.
4. Save a proposal as e.g. `proposal.json` and validate it offline:
   `Test-OERStructure -Path ./proposal.json`
5. Preview the changes, then apply:
   `Invoke-OERStructure -Path ./proposal.json -WhatIf`
   `Invoke-OERStructure -Path ./proposal.json`
'@
}
