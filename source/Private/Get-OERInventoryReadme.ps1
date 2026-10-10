function Get-OERInventoryReadme {
    <#
    .SYNOPSIS
    Returns the Markdown README written into an Export-OERInventory bundle folder.

    .DESCRIPTION
    Produces the run-folder README that explains what each generated file is and the next steps in
    the inventory -> LLM -> apply workflow. Pure string builder: no Graph, ARM, or filesystem access.

    The README opens with a section named "What this export could not read", right after its first
    paragraph. It lists every entry of the three lists the export reports as incomplete, so a reader
    of the bundle alone (an LLM, say) can tell a collection that was not read from one that is empty.
    The three parameters are mandatory on purpose: a caller that forgot them would get a README that
    claims a complete read. When all three hold nothing but blank entries, the section says that
    nothing was left unread. Each entry is written as a Markdown code span, so an entry such as
    '<all Azure scopes: scope enumeration failed>' is shown and not swallowed as an HTML tag.

    .PARAMETER IncompleteReads
    The Entra ID entries Export-OERInventory reports as incompletely read (the IncompleteReads list
    of its output): collections or objects that could not be read, could not be written without an
    empty name, or were left out because two or more live objects share a name. Pass an empty array
    when there are none.

    .PARAMETER SkippedScopes
    The Azure scopes whose role assignments and role management policies could not be read (the
    SkippedScopes list of the Export-OERInventory output), absent from roleAssignments.json and
    roleManagementPolicies.json. Pass an empty array when there are none.

    .PARAMETER SkippedEligibilityScopes
    The Azure scopes whose PIM eligibility could not be read (the SkippedEligibilityScopes list of
    the Export-OERInventory output), absent from azurePimEligibility.json. Pass an empty array when
    there are none.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
    Returns the README Markdown as a single string. Its "What this export could not read" section
    says that nothing was left unread.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @('groupsRoster') -SkippedScopes @('<all Azure scopes: scope enumeration failed>') -SkippedEligibilityScopes @('<all Azure scopes: scope enumeration failed>')
    Returns the README Markdown with one bullet per entry under "What this export could not read".
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$IncompleteReads,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$SkippedScopes,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$SkippedEligibilityScopes
    )

    # One bullet per non-blank entry, in the order each list holds them. An entry is written as a
    # Markdown code span so '<all Azure scopes: scope enumeration failed>' is shown, not swallowed
    # as an HTML tag. CR and LF become a space, so a bullet stays on one line. The fence is one
    # backtick longer than the longest run of backticks inside the entry (a single backtick when the
    # entry holds none, two for an entry with a lone backtick), padded with a space each side so an
    # entry that starts or ends with a backtick still closes cleanly.
    $Bullets = [System.Collections.Generic.List[string]]::new()
    $Lists = @(
        @{ Label = 'Entra ID'; Entries = $IncompleteReads }
        @{ Label = 'Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`'; Entries = $SkippedScopes }
        @{ Label = 'Azure scope, absent from `azurePimEligibility.json`'; Entries = $SkippedEligibilityScopes }
    )
    foreach ($List in $Lists) {
        foreach ($Entry in @($List.Entries)) {
            if ([string]::IsNullOrWhiteSpace($Entry)) { continue }
            $OneLine = $Entry -replace '\r\n|\r|\n', ' '
            $LongestRun = 0
            foreach ($Run in [regex]::Matches($OneLine, '`+')) {
                if ($Run.Length -gt $LongestRun) { $LongestRun = $Run.Length }
            }
            $CodeSpan = if ($LongestRun -eq 0) {
                '`' + $OneLine + '`'
            } else {
                $Fence = '`' * ($LongestRun + 1)
                "$Fence $OneLine $Fence"
            }
            $Bullets.Add("- $($List.Label): $CodeSpan")
        }
    }

    $CouldNotRead = if ($Bullets.Count -gt 0) {
        $Partial = @'
## What this export could not read

This bundle is PARTIAL: `Export-OERInventory` could not read, or could not write, everything it was
asked to, so do not treat it as a full tenant snapshot. Each entry below names collections or objects
that could not be read, could not be written without an empty name, or were left out because two or
more live objects share a name; none of them is stated as a fact in this bundle. "Unread
collections" below says how an unread collection is written; an object left out for a shared name is
absent from `inventory.json` and the per-area files, which does not mean the tenant has none.
'@
        $Partial + "`n`n" + ($Bullets -join "`n")
    } else {
        @'
## What this export could not read

Nothing. `Export-OERInventory` read everything it was asked to read: no collection, section, group
roster or Azure scope was reported as unread, and no `InventoryPartial` error was raised. The
coverage limits below still apply -- they describe what this bundle never captures, not a read
that failed.
'@
    }

    $Readme = @'
# OER RBAC Inventory Bundle

This folder was produced by `Export-OERInventory`. It captures the RBAC-relevant slice of your
tenant's current posture -- see Coverage limits below for what is deliberately excluded -- and
includes a predefined prompt that turns it into appliable improvement proposals.

@@COULD-NOT-READ@@

## Files

- `inventory.json` -- the canonical, round-trippable inventory, in the exact apply-document shape,
  subject to the coverage limits below (for example, only access-package-scoped access reviews
  are captured).
- `groups.json`, `administrativeUnits.json`, `catalogs.json`, `accessPackages.json`,
  `accessReviews.json`, `directoryRoleManagementPolicies.json`, `directoryRoleAssignments.json`,
  `roleAssignments.json`, `roleManagementPolicies.json` -- the same data split per area, so you can
  feed an LLM one area at a time without hitting its context limit.
- `groupsRoster.json` -- a lightweight roster of EVERY group in the tenant, of every group type
  (names + flags, including `onPremisesSynced`), read unfiltered. Read-only context, not an apply
  document. It is deliberately wider than `inventory.json`: see "Which groups are covered" below.
  Its `memberCount` is the group's member count when the export read the group in full (every
  security group with `-AllGroupsDetailed`), and `null` otherwise -- not known, which is not zero:
  a count would cost a request per group. A group left out of `inventory.json` and `groups.json`
  because another group shares its name has a `null` count too. So has a security group outside the
  export's `-GroupFilter`, which was not read.
- `scopeHierarchy.json` -- the management group / subscription tree. Read-only context, not an
  apply document.
- `azurePimEligibility.json` -- the Azure PIM eligible role assignments at the scopes in
  `scopeHierarchy.json`, written only when an Azure section (`RoleAssignments` or
  `RoleManagementPolicies`) is included. Read-only context, not an apply document -- see the
  eligible Azure PIM assignments under Coverage limits below.
- `schema.json` -- a formal JSON Schema (draft-07) for the apply document, so a proposal can be
  validated without the module (for example with Test-Json).
- `rbac-architect-prompt.md` -- the predefined prompt. Open it, optionally edit the
  "USER PREFERENCES" block, then give it to any LLM together with this README and the JSON files
  above.

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

Unless the export ran with `-AllGroupsDetailed`, `inventory.json` details only the RBAC-relevant
security groups: role-assignable ones, ones with PIM eligibility, ones found to use PIM for Groups
(written with a `pimPolicy` block), and synchronized ones when the export ran with
`-IncludeSyncedGroups`. The export decided that before reading any group in full, so a group it
found not relevant had no members, owners or PIM policy read at all, and its absence from
`inventory.json` says nothing about them. A group whose relevance could not be decided was read in
full, and what could not be read about it is listed under "What this export could not read". The
export's own `-GroupFilter` only narrows this scope: `inventory.json` then covers only security
groups the filter matched, never a group that is not security-enabled, while `groupsRoster.json`
still lists every group.

A group synchronized from on-premises Active Directory (`onPremisesSynced` true in
`groupsRoster.json`) is managed there and read-only in the cloud: it cannot be role-assignable or
managed in PIM for Groups, so `inventory.json` details it only when the export ran with
`-IncludeSyncedGroups` or `-AllGroupsDetailed`, and there it carries `onPremisesSynced: true`.
`Invoke-OERStructure` writes nothing to such a group.

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

## Unread collections

When a read of a `members`, `scopedRoles`, `resources` or `resourceRoles` collection fails -- a
refused, throttled or failed call -- the export never writes that collection as empty. The key is
written as `null`, which `Invoke-OERStructure` reads as "leave untouched". Do not change such a
`null` to `[]`: under `-Prune` an empty collection removes every live entry. An entry is never
written with an empty name. A group or application binding whose name cannot be read is written
under its object id, and a catalog resource with a blank name under its origin id; an entry the
export could name by nothing the apply engine accepts (a SharePoint binding with no name, for
example) makes its whole collection `null`, named in `InventoryPartial`, exactly like an unread one.
`Export-OERInventory` ends with an `InventoryPartial` error naming each collection it reports as
unread, these four and any other; the others are left out or written only as far as they were read,
so their absence is not evidence the tenant has none. A section that could not be read at all (the
group list, the administrative unit list or the access review list) is reported by a warning and
through `InventoryPartial` under the section's own name (`groups`, `administrativeUnits` or
`accessReviews`), and is written as an empty array. The group roster that could not be read is named
`groupsRoster` in the export's `IncompleteReads` and written as an empty array in
`groupsRoster.json`. An empty section reported that way is not evidence the tenant has none.
`Export-OERInventory` lists each such report, and each Azure scope it could not read, under "What
this export could not read" above.

## Next steps

1. Open `rbac-architect-prompt.md`. Leave the USER PREFERENCES block untouched for best-practice
   defaults, or fill in your naming standard and depth.
2. Provide the prompt, this README and the JSON files to any capable LLM.
3. The LLM returns three proposals: Foundational, Recommended, Advanced -- each a complete apply
   document.
4. Save a proposal as e.g. `proposal.json` and validate it offline:
   `Test-OERStructure -Path ./proposal.json`
5. Preview the changes, then apply:
   `Invoke-OERStructure -Path ./proposal.json -WhatIf`
   `Invoke-OERStructure -Path ./proposal.json`

A proposal that keeps the `tenantId` of `inventory.json` is applied only in the tenant this export
came from: `Invoke-OERStructure` refuses it anywhere else. To apply it in another tenant, change or
remove `tenantId` first.
'@

    $Readme.Replace('@@COULD-NOT-READ@@', $CouldNotRead)
}
