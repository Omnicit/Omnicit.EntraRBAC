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
    '<all Azure scopes: scope enumeration failed>' is shown and not swallowed as an HTML tag. An
    IncompleteReads entry that starts with 'roleManagementPolicies/' is an Azure scope where the
    export kept role management policies it could not judge, not an Entra ID read, and is listed
    under the label 'Azure role management policies kept without being judged'. An IncompleteReads
    entry that starts with 'roleAssignments/' names a row of roleAssignments.json whose principal could
    not be read (Sprint 11 step 6, BL-133), and is listed under the label 'Role assignment principal
    that could not be read'; the section's prose says how such a row is written: by the principal's
    object id with no principalStatus where its lookup failed ('/principal'), and with principalStatus
    Unresolved, its reason not known, where only its deleted items read failed ('/principalStatus').

    Directly after it comes the section "Members and owners left out as PIM for Groups access"
    (BL-125, A3). It says that inventory.json and groups.json write a group's standing members and
    owners only, why a member or owner whose access PIM for Groups holds is left out, and what was
    left out where the PIM for Groups assignments could not be read. Then it lists one bullet per
    -PimLeftOut entry: the group's name as a code span (the same fence rule as the entries above),
    how many members and owners were left out, and the basis -- an activation, or another active
    assignment that is not standing, such as a time-bound one, or, where the group's assignments could
    not be read, eligibility for the same access.
    It names groups only, never a principal. When -PimLeftOut is empty it says that none was left out.
    That parameter is mandatory for the same reason as the three above.

    Directly after it comes the section "Role assignments at the root scope (elevated access)"
    (BL-126). It says what the Azure root scope '/' is, that a role assignment there is elevated
    access and a finding to review, that inventory.json and roleAssignments.json never carry one and
    Invoke-OERStructure never creates or removes one, and that leaving them out changes nothing in the
    tenant. Then it gives the count and one bullet per -RootScopeAssignments row, in the order given:
    the role and the principal as code spans (the same fence rule as the entries above), and the
    principal type in parentheses when it is known. It never writes the role assignment id. When
    -RootScopeAssignments is empty it says that none was read. That parameter is mandatory for the same
    reason as the four above.

    Directly after it comes the section "Names two or more objects share" (BL-131). It says that
    Microsoft Entra ID does not keep display names unique and the apply engine refuses an ambiguous
    name, so every object whose name another object of its kind shares is left out of inventory.json
    and the per-area files, all of them, and is named under "What this export could not read" too;
    that groups are counted over every group in the tenant, Microsoft 365 and distribution groups
    included, an access package's name among the packages of its catalog, an assignment policy's
    among the policies of its own access package only, and the name of an administrative unit, a
    catalog or an access review among the ones the export read; how a reference to such an object
    elsewhere in the document is written (by its id); and that leaving them out changes nothing in
    the tenant. Then it lists one bullet per -SharedNames
    entry, in the order given: the name as a code span (the same fence rule as the entries above),
    how many objects carry it, and its section as a code span. When -SharedNames is empty it says
    that no two objects the export read share a name. That parameter is mandatory for the same
    reason as the five above.

    Directly after it comes the section "Role assignments whose principal the directory did not
    return" (Sprint 11 step 6, BL-133). It says that such an assignment stays in inventory.json and
    roleAssignments.json, written by the principal's object id with principalStatus, that
    Invoke-OERStructure never creates one and that removing its entry from the document lets -Prune
    remove it at a scope the document still declares, and that a principal whose lookup failed is
    named under "What this export could not read" instead. Then it gives the count and one bullet per
    -UnresolvedPrincipalAssignments row, in the order given: the role, the scope and the principal as
    code spans (the same fence rule as the entries above), the principal type in parentheses when it
    is known, and the status as a code span with its reason in words -- Deleted, found among the
    directory's deleted items; Unresolved, found neither in the directory nor among its deleted items
    (deleted beyond the retention period, a principal of another tenant, for example through Azure
    Lighthouse, or not readable). An Unresolved row whose StatusRead is not true -- its deleted items
    read failed, or the row does not say -- is given no reason as a fact: the bullet says that the read
    failed, so the reason is not known, and that the read is named under "What this export could not
    read". It never writes the role assignment id. When -UnresolvedPrincipalAssignments is empty it
    says that none was found. That parameter is mandatory for the same reason as the six above.

    Directly after it comes the section "Role assignments at a scope no document can declare" (A13,
    A15). It says that the validator refuses the spelling of such a scope, with a resource name that
    holds a '#' or a '%' as its example and without listing the rules (Get-OERScopeSpellingProblem
    owns them, and each row's Reason names the ones its scope breaks), that no document can declare
    such a scope and a document that carried one would be refused as a whole, so inventory.json and
    roleAssignments.json leave the assignment out, that Invoke-OERStructure never creates a role
    assignment at such a scope and never removes one, since it prunes only at a scope a document
    declares, that a role assignment at the root scope is listed in the root scope section only, and
    that leaving them out changes nothing in the tenant. Then it gives the count and one bullet per
    -UndeclarableScopeAssignments row, in the order given: the role, the scope and the principal as code
    spans (the same fence rule as the entries above), the principal type in parentheses when it is
    known, and the reason, the rules the scope breaks in words, on one line. It never writes the role
    assignment id. When -UndeclarableScopeAssignments is empty it says that none was read. That
    parameter is mandatory for the same reason as the seven above.

    Directly after it comes the section "Groups using PIM for Groups in a restricted management unit"
    (Sprint 11 step 6, BL-134). It says that Microsoft Learn states that Privileged Identity Management
    does not support a group in a restricted management administrative unit, so a group with PIM
    eligibility or a pimPolicy block that is a member of one is a finding to review; that inventory.json
    keeps the group and Invoke-OERStructure still sends the PIM settings and eligibility a document
    declares for it, and what Microsoft Graph answers to those writes has not been measured; that a unit
    left out of the document because another unit shares its name is not checked, and is named under
    "Names two or more objects share" and "What this export could not read"; and that listing a group
    changes nothing in the tenant. Then it gives the count and one bullet per -RestrictedUnitPimGroups
    row, in the order given: the group and each of its units as code spans (the same fence rule as the
    entries above), by display name. It never writes an object id. When -RestrictedUnitPimGroups is
    empty it says that none was found, that the check needs both Groups and AdministrativeUnits in the
    export, and which units were not checked. That parameter is mandatory for the same reason as the
    eight above.

    Directly after it comes the section "Azure Lighthouse delegations (access from another tenant)"
    (Sprint 11 step 6b, BL-133). It says that Azure Lighthouse lets another tenant manage subscriptions
    or resource groups of this one, that the access a delegation gives is not a role assignment of this
    tenant, so roleAssignments.json and inventory.json never show it and Invoke-OERStructure never
    creates or removes it, that lighthouseDelegations.json holds every delegation the export read as
    read-only context (the eligible, just-in-time authorizations apart), that a scope whose delegations
    could not be read is named under "What this export could not read" and its delegations are absent
    from the file, which does not mean it has none, and that listing a delegation changes nothing in
    the tenant. Then it gives the count and one bullet per -LighthouseDelegations row, in the order
    given: the scope, the managing tenant (name and id), the offer and the roles as code spans (the same
    fence rule as the entries above), how many authorizations and eligible authorizations the row
    holds, and 'not given' for a managing tenant name, tenant id or offer the row does not carry. The
    roles are the distinct role names (the role definition id for an authorization whose name is not
    known) over both lists, in the order first met. It never writes a principal. When
    -LighthouseDelegations is empty it says that none was read, and that delegations are read only when
    the export includes an Azure section. That parameter is mandatory for the same reason as the nine
    above.

    .PARAMETER IncompleteReads
    The IncompleteReads list of the Export-OERInventory output. First the Entra ID entries:
    collections or objects that could not be read, could not be written without an empty name, or
    were left out because two or more live objects share a name. Then one entry per role assignment
    principal that could not be read, reading 'roleAssignments/<role> -> <principal id> @ <scope>'
    followed by '/principal' (its lookup failed) or '/principalStatus' (only its deleted items read
    failed). Then, last, one entry per Azure scope where at least one role management policy could not
    be judged, reading
    'roleManagementPolicies/role selection at <scope>': every policy there that could not be judged
    was kept, none of them left out (where the scope's role assignment read or eligibility read
    failed, that is every policy of a role neither used nor changed there), so
    roleManagementPolicies.json may hold policies of roles that are neither used nor changed there.
    Pass an empty array when there are none.

    .PARAMETER SkippedScopes
    The Azure scopes whose role assignments and role management policies could not be read (the
    SkippedScopes list of the Export-OERInventory output), absent from roleAssignments.json and
    roleManagementPolicies.json. Pass an empty array when there are none.

    .PARAMETER SkippedEligibilityScopes
    The Azure scopes whose PIM eligibility could not be read (the SkippedEligibilityScopes list of
    the Export-OERInventory output), absent from azurePimEligibility.json. Pass an empty array when
    there are none.

    .PARAMETER PimLeftOut
    The groups that left members or owners out as PIM for Groups access (the PimLeftOut list of
    Get-OERInventoryGroup, which Export-OERInventory narrows to the groups inventory.json writes):
    one object per group with Group (the display name), Members and Owners (how many were left out)
    and Basis ('Assignments' or 'Eligibility'). Pass an empty array when there are none.

    .PARAMETER RootScopeAssignments
    The role assignments at the Azure root scope '/' the export left out of inventory.json and
    roleAssignments.json (BL-126), deduplicated by Export-OERInventory from the information records
    Get-OERInventory writes: one object per assignment with Role (the role name, or the role
    definition id when it has no name), Principal (the principal name as the export writes it) and
    PrincipalType (the principal type, or an empty string when unknown). Any other property, such as
    RoleAssignmentId, is not written. Pass an empty array when there are none.

    .PARAMETER SharedNames
    The names the export left out of inventory.json and the per-area files because two or more live
    objects share them (BL-131): the group reader's SharedNames list followed by the names
    Get-OERInventory hands over in its information records tagged Omnicit.EntraRBAC.SharedName. One
    object per name with Section (the document section, 'groups' for instance), Name (the name as
    reported) and Count (how many live objects carry it). Pass an empty array when there are none.

    .PARAMETER UnresolvedPrincipalAssignments
    The role assignments whose principal the directory did not return (Sprint 11 step 6, BL-133),
    written into inventory.json and roleAssignments.json by the principal's object id with
    principalStatus, and deduplicated by Export-OERInventory from the information records tagged
    Omnicit.EntraRBAC.UnresolvedPrincipal that Get-OERInventory writes: one object per assignment with
    Scope, Role, Principal (the object id), PrincipalType (the principal type, or an empty string when
    unknown), PrincipalStatus (Deleted or Unresolved) and StatusRead (true when the deleted items read
    behind PrincipalStatus succeeded; a Deleted status is always read). Any other property, such as
    RoleAssignmentId, is not written. Pass an empty array when there are none.

    .PARAMETER UndeclarableScopeAssignments
    The role assignments at a scope no document can declare (A13, A15), left out of inventory.json and
    roleAssignments.json, and deduplicated by Export-OERInventory from the information records tagged
    Omnicit.EntraRBAC.UndeclarableScope that Get-OERInventory writes: one object per assignment with
    Scope, Role, Principal (the principal name as the export would have written it), PrincipalType (the
    principal type, or an empty string when unknown) and Reason (the rules the scope breaks, in words).
    Any other property, such as RoleAssignmentId, is not written. Pass an empty array when there are
    none.

    .PARAMETER RestrictedUnitPimGroups
    The groups inventory.json writes with PIM eligibility or a pimPolicy block that are members of a
    restricted management administrative unit (Sprint 11 step 6, BL-134), as Export-OERInventory finds
    them: one object per group with Group (the group's display name) and Units (the display names of
    the restricted units it is a member of). Any other property, such as an object id, is not written.
    Pass an empty array when there are none.

    .PARAMETER LighthouseDelegations
    The Azure Lighthouse delegations the export read (Sprint 11 step 6b, BL-133), the rows written to
    lighthouseDelegations.json, in that file's order: one object per delegation with scope,
    managedByTenantId, managedByTenantName, offerName, authorizations and eligibleAuthorizations (each
    entry with roleName, which is null when the name is not known, and roleDefinitionId). Any other
    property, such as a principal, is not written. Pass an empty array when there are none.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @()
    Returns the README Markdown as a single string. Its "What this export could not read" section
    says that nothing was left unread, its "Members and owners left out as PIM for Groups access"
    section that none was left out, its "Role assignments at the root scope (elevated access)"
    section that none was read, its "Names two or more objects share" section that no two objects
    share a name, its "Role assignments whose principal the directory did not return" section that
    none was found, its "Role assignments at a scope no document can declare" section that none was
    read, its "Groups using PIM for Groups in a restricted management unit" section that none was
    found, and its "Azure Lighthouse delegations (access from another tenant)" section that none was
    read.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @('groupsRoster') -SkippedScopes @('<all Azure scopes: scope enumeration failed>') -SkippedEligibilityScopes @('<all Azure scopes: scope enumeration failed>') -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @()
    Returns the README Markdown with one bullet per entry under "What this export could not read".

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut $GroupRead.PimLeftOut -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @()
    Returns the README Markdown with one bullet per group under "Members and owners left out as PIM
    for Groups access".

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @([PSCustomObject]@{ Role = 'User Access Administrator'; Principal = 'person1@example.com'; PrincipalType = 'User' }) -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @()
    Returns the README Markdown with the count and one bullet per role assignment under "Role
    assignments at the root scope (elevated access)".

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @('groups/Admins') -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @([PSCustomObject]@{ Section = 'groups'; Name = 'Admins'; Count = 2 }) -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @()
    Returns the README Markdown with one bullet per name under "Names two or more objects share":
    the name, how many objects carry it and its section.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @([PSCustomObject]@{ Scope = '/subscriptions/11111111-1111-1111-1111-111111111111'; Role = 'Reader'; Principal = '22222222-2222-2222-2222-222222222222'; PrincipalType = 'User'; PrincipalStatus = 'Deleted'; StatusRead = $true }) -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @()
    Returns the README Markdown with the count and one bullet per role assignment under "Role
    assignments whose principal the directory did not return": the role, the scope, the principal, its
    type and the status with its reason.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @([PSCustomObject]@{ Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1/providers/Microsoft.Sql/servers/srv1/databases/db#1'; Role = 'Reader'; Principal = 'person1@example.com'; PrincipalType = 'User'; Reason = 'the scope holds a question mark or a number sign' }) -RestrictedUnitPimGroups @() -LighthouseDelegations @()
    Returns the README Markdown with the count and one bullet per role assignment under "Role
    assignments at a scope no document can declare": the role, the scope, the principal, its type and
    the rules the scope breaks.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @([PSCustomObject]@{ Group = 'role_sec_pim'; Units = @('Restricted AU') }) -LighthouseDelegations @()
    Returns the README Markdown with the count and one bullet per group under "Groups using PIM for
    Groups in a restricted management unit": the group and the restricted units it is a member of.

    .EXAMPLE
    Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @([PSCustomObject]@{ scope = '/subscriptions/11111111-1111-1111-1111-111111111111'; managedByTenantId = '22222222-2222-2222-2222-222222222222'; managedByTenantName = 'Contoso Corp.'; offerName = 'Managed Services'; authorizations = @([PSCustomObject]@{ roleName = 'Contributor'; roleDefinitionId = '33333333-3333-3333-3333-333333333333' }); eligibleAuthorizations = @() })
    Returns the README Markdown with the count and one bullet per delegation under "Azure Lighthouse
    delegations (access from another tenant)": the scope, the managing tenant, the offer, how many
    authorizations it holds and the roles.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$IncompleteReads,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$SkippedScopes,
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$SkippedEligibilityScopes,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PimLeftOut,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$RootScopeAssignments,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SharedNames,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$UnresolvedPrincipalAssignments,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$UndeclarableScopeAssignments,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$RestrictedUnitPimGroups,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$LighthouseDelegations
    )

    # A text written as a Markdown code span, so '<all Azure scopes: scope enumeration failed>' is
    # shown, not swallowed as an HTML tag. CR and LF become a space, so a bullet stays on one line. The
    # fence is one backtick longer than the longest run of backticks inside the text (a single
    # backtick when the text holds none, two for a text with a lone backtick), padded with a space
    # each side so a text that starts or ends with a backtick still closes cleanly.
    function Format-CodeSpan {
        param([string]$Text)
        $OneLine = $Text -replace '\r\n|\r|\n', ' '
        $LongestRun = 0
        foreach ($Run in [regex]::Matches($OneLine, '`+')) {
            if ($Run.Length -gt $LongestRun) { $LongestRun = $Run.Length }
        }
        if ($LongestRun -eq 0) {
            '`' + $OneLine + '`'
        } else {
            $Fence = '`' * ($LongestRun + 1)
            "$Fence $OneLine $Fence"
        }
    }

    # One bullet per non-blank entry, in the order each list holds them, each entry a code span.
    $Bullets = [System.Collections.Generic.List[string]]::new()
    # An IncompleteReads entry that starts with 'roleManagementPolicies/' is not an Entra ID read: it is
    # an Azure scope where Export-OERInventory kept role management policies it could not judge
    # (BL-107), appended after the Entra ID entries, so it gets its own label.
    $AzurePolicyPrefix = 'roleManagementPolicies/'
    $AzurePolicyLabel = 'Azure role management policies kept without being judged'
    # Sprint 11 step 6 (BL-133): an IncompleteReads entry that starts with 'roleAssignments/' is not an
    # Entra ID entry either: it names a row of roleAssignments.json whose principal could not be read,
    # which Export-OERInventory appends after the Entra ID entries and keeps apart from them in its help
    # and its InventoryPartial, so it gets its own label too.
    $PrincipalPrefix = 'roleAssignments/'
    $PrincipalLabel = 'Role assignment principal that could not be read'
    # The two scope lists never hold such an entry: theirs start with '/' or '<'.
    $Lists = @(
        @{ Label = 'Entra ID'; Entries = $IncompleteReads }
        @{ Label = 'Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`'; Entries = $SkippedScopes }
        @{ Label = 'Azure scope, absent from `azurePimEligibility.json`'; Entries = $SkippedEligibilityScopes }
    )
    foreach ($List in $Lists) {
        foreach ($Entry in @($List.Entries)) {
            if ([string]::IsNullOrWhiteSpace($Entry)) { continue }
            $Label = $List.Label
            if ($Entry.StartsWith($AzurePolicyPrefix, [System.StringComparison]::Ordinal)) { $Label = $AzurePolicyLabel }
            elseif ($Entry.StartsWith($PrincipalPrefix, [System.StringComparison]::Ordinal)) { $Label = $PrincipalLabel }
            $Bullets.Add("- $($Label): $(Format-CodeSpan -Text $Entry)")
        }
    }

    $CouldNotRead = if ($Bullets.Count -gt 0) {
        $Partial = @'
## What this export could not read

This bundle is PARTIAL: `Export-OERInventory` could not read, or could not write, everything it was
asked to, so do not treat it as a full tenant snapshot. Apart from the entries labelled "Azure role
management policies kept without being judged" and "Role assignment principal that could not be
read", each entry below names collections or objects that could not be read, could not be written
without an empty name, or were left out because two or more live objects share a name; none of them
is stated as a fact in this bundle. An entry labelled "Role assignment principal that could not be
read" names a row of `roleAssignments.json` as `roleAssignments/<role> -> <principal id> @ <scope>`,
followed by `/principal` or `/principalStatus`. With `/principal`, the lookup of the principal
failed: the row is written by the principal's object id with no `principalStatus`, so whether the
directory holds the principal is not known. With `/principalStatus`, the directory did not return
the principal and the read of its deleted items failed: the row is written with `principalStatus`
`Unresolved`, and the reason is not known. "Unread collections"
below says how an unread collection is written; an object left out for a shared name is absent from
`inventory.json` and the per-area files, which does not mean the tenant has none. An entry labelled
"Azure role management policies kept without being judged" names an Azure scope where the export
could not tell, for at least one policy, whether its role is used there or whether the policy was
changed, since a read it needed failed or the policy list gave nothing to judge by. Every policy
there that it could not judge was kept, none of them left out -- where a role assignment or
eligibility read failed, that is every policy of a role neither used nor changed at the scope -- so
`roleManagementPolicies.json` may hold policies of roles that are neither used nor changed there. It
does not mean every policy at the scope was kept: when only one policy could not be judged, the
other unused, unchanged policies there are still left out.
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

    # BL-125 (A3): the members and owners left out as PIM for Groups access, one bullet per group by
    # its name -- never a principal -- with how many and on which basis, in the order the export holds
    # them. The basis is worded here: 'Assignments' when the group's PIM for Groups assignments decided
    # it (an activation, or any other active assignment that is not standing), 'Eligibility' when they
    # could not be read and the eligibility decided it instead. The parameter is mandatory, so binding
    # has already refused a null entry.
    $PimBullets = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($PimLeftOut)) {
        $BasisText = if ([string]$Entry.Basis -eq 'Eligibility') {
            "eligible for the same access; the group's PIM for Groups assignments could not be read"
        } else {
            'an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'
        }
        $PimBullets.Add("- $(Format-CodeSpan -Text ([string]$Entry.Group)): $([int]$Entry.Members) member(s) and $([int]$Entry.Owners) owner(s) left out -- $BasisText")
    }
    $PimIntro = @'
## Members and owners left out as PIM for Groups access

`inventory.json` and `groups.json` write a group's standing members and owners only. A member or
owner whose access PIM for Groups holds -- an activation, or another active assignment that is not
standing, such as a time-bound one -- is left out, since applying it would make access that PIM for
Groups grants standing, past PIM's time limit, approval and multi-factor authentication. Where the
PIM for Groups assignments of a group could not be read, every member or owner that is also eligible
for the same access was left out, and the group is listed under "What this export could not read";
where its eligibility could not be read either, its members and owners are not written -- `members`
as `null`, `owners` left out -- unless they were read empty. A member or owner left out is still a
member or owner in the tenant: leaving it out of the export changes nothing there.
'@
    $PimLeftOutSection = if ($PimBullets.Count -gt 0) {
        $PimIntro + "`n`n" + ($PimBullets -join "`n")
    } else {
        $PimIntro + "`n`n" + 'None. This export left no member or owner out as PIM for Groups access.'
    }

    # BL-126 (R4): the role assignments at the Azure root scope '/' the export left out, one bullet per
    # row in the order the export holds them (sorted and deduplicated there): the role and the
    # principal as code spans, and the type in parentheses when it is known. Never the role assignment
    # id. The parameter is mandatory, so binding has already refused a null entry.
    $RootBullets = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($RootScopeAssignments)) {
        $RootType = [string]$Entry.PrincipalType
        $RootBullets.Add("- $(Format-CodeSpan -Text ([string]$Entry.Role)) for $(Format-CodeSpan -Text ([string]$Entry.Principal))" + $(if ($RootType) { " ($RootType)" } else { '' }))
    }
    $RootIntro = @'
## Role assignments at the root scope (elevated access)

The root scope `/` stands above every management group and subscription in the tenant, so a role
assignment there reaches every Azure resource. It is elevated access -- most often User Access
Administrator, which the Microsoft Entra setting "Access management for Azure resources" grants a
Global Administrator -- and a finding to review, not part of the RBAC model this bundle describes.
`inventory.json` and `roleAssignments.json` never carry a role assignment at the root scope, and
`Invoke-OERStructure` never creates or removes one, even when a document declares it. Leaving them
out of the export changes nothing in the tenant.
'@
    $RootScopeSection = if ($RootBullets.Count -gt 0) {
        $RootIntro + "`n`n" + "This export read $($RootBullets.Count) role assignment(s) at the root scope:" + "`n`n" + ($RootBullets -join "`n")
    } else {
        $RootIntro + "`n`n" + "None. No role assignment this export read is at the root scope ``/``. Role assignments are read only`nwhen the export includes ``RoleAssignments``."
    }

    # BL-131 (R-3): the names two or more live objects share, one bullet per entry in the order the
    # export holds them (the group reader's first, then Get-OERInventory's): the name and the section as
    # code spans, and how many objects carry the name. The parameter is mandatory, so binding has
    # already refused a null entry.
    $SharedBullets = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($SharedNames)) {
        $SharedBullets.Add("- $(Format-CodeSpan -Text ([string]$Entry.Name)) -- $([int]$Entry.Count) objects, section $(Format-CodeSpan -Text ([string]$Entry.Section))")
    }
    $SharedIntro = @'
## Names two or more objects share

Microsoft Entra ID does not keep display names unique, and `Invoke-OERStructure` refuses a name that
more than one live object answers to. So every object whose name another object of its kind shares,
compared without regard to letter case, is left out of `inventory.json` and the per-area files -- all
of them -- and is named under "What this export could not read" too. Groups are counted over every
group in the tenant, Microsoft 365 groups and distribution groups included, so a security group that
shares its name with one of those is left out as well; when the group roster could not be read
(`groupsRoster` under "What this export could not read"), groups are counted among the security
groups the export read. An access package's name is counted among the packages of its catalog, and
an assignment policy's among the policies of its own access package only; a policy is listed with
section `assignmentPolicies` as `<package>/<policy>`. The name of an administrative unit, a catalog or
an access review is counted among the ones this export read, an access review's among the
access-package reviews it captured. A reference to such an object elsewhere in the document is
written as the object's id: the catalog of an access package, the access package and assignment
policy of an access review, and a group named as the principal of a role assignment or a directory
role assignment, written with `principalType` `Group`. A group named in any other place -- an
eligibility principal, a reviewer, a catalog resource, a resource role, a member of a group or an
administrative unit -- still carries its name (or its id where the export always writes ids), and an
ambiguous name there is refused when applied, with nothing written for it. Leaving them out of the
export changes nothing in the tenant.
'@
    $SharedNameSection = if ($SharedBullets.Count -gt 0) {
        $SharedIntro + "`n`n" + ($SharedBullets -join "`n")
    } else {
        $SharedIntro + "`n`n" + 'None. No two objects this export read share a name.'
    }

    # Sprint 11 step 6 (BL-133, A18): the role assignments whose principal the directory did not return,
    # one bullet per row in the order the export holds them (deduplicated there): the role, the scope and
    # the principal as code spans, the type in parentheses when it is known, and the status as a code span
    # with its reason in words. Never the role assignment id. The parameter is mandatory, so binding has
    # already refused a null entry.
    $UnresolvedBullets = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($UnresolvedPrincipalAssignments)) {
        $UnresolvedType = [string]$Entry.PrincipalType
        $UnresolvedStatus = [string]$Entry.PrincipalStatus
        # An Unresolved status whose deleted items read failed was never searched for, so its reason is not
        # stated as a fact. Only an explicit StatusRead true counts as read.
        $UnresolvedReason = if ($UnresolvedStatus -eq 'Deleted') {
            'found among the directory''s deleted items'
        } elseif ($Entry.StatusRead -ne $true) {
            'not returned by the directory, and the read of its deleted items failed, so the reason is not known; that read is named under "What this export could not read"'
        } else {
            'found neither in the directory nor among its deleted items (deleted beyond the retention period, a principal of another tenant, for example through Azure Lighthouse, or not readable)'
        }
        $UnresolvedBullets.Add("- $(Format-CodeSpan -Text ([string]$Entry.Role)) at $(Format-CodeSpan -Text ([string]$Entry.Scope)) for $(Format-CodeSpan -Text ([string]$Entry.Principal))" +
            $(if ($UnresolvedType) { " ($UnresolvedType)" } else { '' }) + ": $(Format-CodeSpan -Text $UnresolvedStatus), $UnresolvedReason")
    }
    $UnresolvedIntro = @'
## Role assignments whose principal the directory did not return

A role assignment can name a principal that Microsoft Entra ID does not return: one that was
deleted, or one this directory cannot read. Such an assignment stays in `inventory.json` and
`roleAssignments.json`, with its principal written as the object id and `principalStatus` saying
why: `Deleted` or `Unresolved`. Where this section lists an assignment, its entry says what its
status means. `Invoke-OERStructure` never creates such an assignment, and removing its entry from the
document lets `-Prune` remove it, like any undeclared assignment, at a scope the document still
declares. A principal whose lookup failed is not listed here: it is written by its object id
without `principalStatus` and named under "What this export could not read". Where the read of its
deleted items failed, the principal is listed here as `Unresolved` with the reason not known, and
that read is named there too.
'@
    $UnresolvedPrincipalSection = if ($UnresolvedBullets.Count -gt 0) {
        $UnresolvedIntro + "`n`n" + "This export read $($UnresolvedBullets.Count) such role assignment(s):" + "`n`n" + ($UnresolvedBullets -join "`n")
    } else {
        $UnresolvedIntro + "`n`n" + "None. No role assignment this export read names a principal that the directory did not return, apart`nfrom any whose lookup failed, which are named under `"What this export could not read`". Role`nassignments are read only when the export includes ``RoleAssignments``."
    }

    # A13, A15: the role assignments at a scope no document can declare, one bullet per row in the order
    # the export holds them (deduplicated there): the role, the scope and the principal as code spans, the
    # type in parentheses when it is known, and the reason in words, kept on one line. Never the role
    # assignment id. The parameter is mandatory, so binding has already refused a null entry.
    $UndeclarableBullets = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($UndeclarableScopeAssignments)) {
        $UndeclarableType = [string]$Entry.PrincipalType
        $UndeclarableReason = ([string]$Entry.Reason) -replace '\r\n|\r|\n', ' '
        $UndeclarableBullets.Add("- $(Format-CodeSpan -Text ([string]$Entry.Role)) at $(Format-CodeSpan -Text ([string]$Entry.Scope)) for $(Format-CodeSpan -Text ([string]$Entry.Principal))" +
            $(if ($UndeclarableType) { " ($UndeclarableType)" } else { '' }) + $(if ($UndeclarableReason) { ": $UndeclarableReason" } else { '' }))
    }
    $UndeclarableIntro = @'
## Role assignments at a scope no document can declare

Azure Resource Manager can return a role assignment at a scope whose spelling the validator
(`Test-OERStructure`, which `Invoke-OERStructure` runs first) refuses, for example the scope of a
resource whose name holds a `#` or a `%`. Where this section lists an assignment, its entry names the
rules its scope breaks. No document can declare such a scope, and a document that carried one would
be refused as a whole, so `inventory.json` and `roleAssignments.json` leave the assignment out.
`Invoke-OERStructure` never creates a role assignment at such a scope, and never removes one, since
it prunes only at a scope a document declares. A role assignment at the root scope is listed under
"Role assignments at the root scope (elevated access)" only. Leaving them out of the export changes
nothing in the tenant.
'@
    $UndeclarableScopeSection = if ($UndeclarableBullets.Count -gt 0) {
        $UndeclarableIntro + "`n`n" + "This export read $($UndeclarableBullets.Count) such role assignment(s):" + "`n`n" + ($UndeclarableBullets -join "`n")
    } else {
        $UndeclarableIntro + "`n`n" + "None. No role assignment this export read is at a scope a document cannot declare. Role assignments are`nread only when the export includes ``RoleAssignments``."
    }

    # Sprint 11 step 6 (BL-134): the groups inventory.json writes with PIM eligibility or a pimPolicy block
    # that are members of a restricted management unit, one bullet per group in the order the export holds
    # them: the group and each of its units as code spans, by display name -- never an id. The parameter is
    # mandatory, so binding has already refused a null entry.
    $RestrictedBullets = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($RestrictedUnitPimGroups)) {
        $RestrictedUnitSpans = @(foreach ($RestrictedUnit in @($Entry.Units)) { Format-CodeSpan -Text ([string]$RestrictedUnit) }) -join ', '
        $RestrictedBullets.Add("- $(Format-CodeSpan -Text ([string]$Entry.Group)) -- member of the restricted management unit(s) $RestrictedUnitSpans")
    }
    $RestrictedIntro = @'
## Groups using PIM for Groups in a restricted management unit

A group that uses PIM for Groups -- one with PIM eligibility or a `pimPolicy` block -- and is a
member of a restricted management administrative unit is a case Microsoft documents as unsupported:
Microsoft Learn states that Privileged Identity Management does not support a group in a restricted
management administrative unit. `inventory.json` keeps such a group, and `Invoke-OERStructure` still
sends the PIM settings and eligibility a document declares for it; what Microsoft Graph answers to
those writes has not been measured. Review each group below as a finding before applying a document
that declares it. Only a group `inventory.json` writes is listed, against a restricted unit whose
members this export read and which it kept in the document: a unit left out of the document because
another unit shares its name is not checked here, and is named under "Names two or more objects share"
and "What this export could not read". Listing a group changes nothing in the tenant and leaves
nothing out of the export.
'@
    $RestrictedUnitSection = if ($RestrictedBullets.Count -gt 0) {
        $RestrictedIntro + "`n`n" + "This export found $($RestrictedBullets.Count) such group(s):" + "`n`n" + ($RestrictedBullets -join "`n")
    } else {
        $RestrictedIntro + "`n`n" + "None. No group that ``inventory.json`` writes with PIM eligibility or a ``pimPolicy`` block is a member of a`nrestricted management unit this export checked. The check needs both ``Groups`` and ``AdministrativeUnits`` in`nthe export; a unit whose members could not be read, and a unit left out of the document because another unit`nshares its name, were not checked, and each is named under `"What this export could not read`"."
    }

    # Sprint 11 step 6b (BL-133): the Azure Lighthouse delegations the export read, one bullet per row in
    # the order the export holds them (sorted there): the scope, the managing tenant (name and id), the
    # offer and the roles as code spans, how many authorizations and eligible authorizations the row
    # holds, and 'not given' for a managing tenant name, tenant id or offer the row does not carry. The
    # roles are the distinct role names (the role definition id for an authorization whose name is not
    # known) over both lists in the order first met. Never a principal. The parameter is mandatory, so
    # binding has already refused a null entry.
    $LighthouseBullets = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @($LighthouseDelegations)) {
        $AuthorizationList = @($Entry.authorizations | Where-Object { $null -ne $_ })
        $EligibleList = @($Entry.eligibleAuthorizations | Where-Object { $null -ne $_ })
        $SeenRole = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $RoleSpans = @(foreach ($Authorization in @($AuthorizationList) + @($EligibleList)) {
                $RoleText = if (-not [string]::IsNullOrWhiteSpace([string]$Authorization.roleName)) { [string]$Authorization.roleName } else { [string]$Authorization.roleDefinitionId }
                if (-not [string]::IsNullOrWhiteSpace($RoleText) -and $SeenRole.Add($RoleText)) { Format-CodeSpan -Text $RoleText }
            })
        $TenantName = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.managedByTenantName)) { Format-CodeSpan -Text ([string]$Entry.managedByTenantName) } else { 'not given' }
        $TenantId = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.managedByTenantId)) { Format-CodeSpan -Text ([string]$Entry.managedByTenantId) } else { 'not given' }
        $OfferText = if (-not [string]::IsNullOrWhiteSpace([string]$Entry.offerName)) { Format-CodeSpan -Text ([string]$Entry.offerName) } else { 'not given' }
        $RolesText = if ($RoleSpans.Count -gt 0) { $RoleSpans -join ', ' } else { 'none' }
        $LighthouseBullets.Add("- $(Format-CodeSpan -Text ([string]$Entry.scope)) -- managing tenant $TenantName ($TenantId), offer $($OfferText): $($AuthorizationList.Count) authorization(s) and $($EligibleList.Count) eligible authorization(s), roles $RolesText")
    }
    $LighthouseIntro = @'
## Azure Lighthouse delegations (access from another tenant)

Azure Lighthouse lets another tenant -- a service provider, for example -- manage subscriptions or
resource groups of this tenant: a delegation gives principals of that managing tenant Azure built-in
roles over the delegated scope. That access is not listed as a role assignment of this tenant, so
`roleAssignments.json` and `inventory.json` never show it, and `Invoke-OERStructure` never creates or
removes it. `lighthouseDelegations.json` holds every delegation this export read, as read-only
context: the delegated scope, the managing tenant, the offer and each authorization, with the
eligible (just-in-time) ones apart. Review each delegation below as a finding. A scope whose
delegations could not be read is named under "What this export could not read", and its delegations
are absent from the file, which does not mean it has none. Listing a delegation changes nothing in
the tenant.
'@
    $LighthouseSection = if ($LighthouseBullets.Count -gt 0) {
        $LighthouseIntro + "`n`n" + "This export read $($LighthouseBullets.Count) delegation(s):" + "`n`n" + ($LighthouseBullets -join "`n")
    } else {
        $LighthouseIntro + "`n`n" + "None. This export read no Azure Lighthouse delegation. Delegations are read only when the export includes`n``RoleAssignments`` or ``RoleManagementPolicies``, at the subscriptions its Azure walk visits; a`nscope whose delegations could not be read is named under `"What this export could not read`"."
    }

    $Readme = @'
# OER RBAC Inventory Bundle

This folder was produced by `Export-OERInventory`. It captures the RBAC-relevant slice of your
tenant's current posture -- see Coverage limits below for what is deliberately excluded -- and
includes a predefined prompt that turns it into appliable improvement proposals.

@@COULD-NOT-READ@@

@@PIM-LEFT-OUT@@

@@ROOT-SCOPE@@

@@SHARED-NAMES@@

@@UNRESOLVED-PRINCIPALS@@

@@UNDECLARABLE-SCOPES@@

@@RESTRICTED-UNIT-PIM@@

@@LIGHTHOUSE@@

## Files

- `inventory.json` -- the canonical, round-trippable inventory, in the exact apply-document shape,
  subject to the coverage limits below (for example, only access-package-scoped access reviews
  are captured).
- `groups.json`, `administrativeUnits.json`, `catalogs.json`, `accessPackages.json`,
  `accessReviews.json`, `directoryRoleManagementPolicies.json`, `directoryRoleAssignments.json`,
  `roleAssignments.json`, `roleManagementPolicies.json` -- the same data split per area, so you can
  feed an LLM one area at a time without hitting its context limit.
- `groupsRoster.json` -- a lightweight roster of EVERY group in the tenant, of every group type,
  read unfiltered: one row per group with its `id` and `displayName`, its type (`securityEnabled`,
  `mailEnabled` and `groupTypes`), `visibility`, `createdDateTime` and flags, including
  `onPremisesSynced`. The `id` tells apart two groups that share a name. Read-only context, not an
  apply document. It is deliberately wider than `inventory.json`: see "Which groups are covered"
  below.
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
- `lighthouseDelegations.json` -- the Azure Lighthouse delegations at the subscriptions in
  `scopeHierarchy.json`, written only when an Azure section is included: access that principals of
  another tenant hold here, which is not listed as a role assignment. Read-only context, not an apply
  document -- see "Azure Lighthouse delegations (access from another tenant)" above.
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
be proposed. `roleManagementPolicies` (the PIM settings of Azure roles) holds, unless the export used
`-AllRolePolicies`, only the policy of a role with an active role assignment or a PIM eligibility
exactly at the policy's scope, or whose policy has been changed, and every policy the export could
not judge, at a scope listed under "What this export could not read" as kept without being judged.
A policy absent from it was left out by the export, not missing from the tenant, and applying a
document that does not declare it leaves it untouched. Four areas fall outside that model, each
differently -- do not read this bundle as a complete picture of the tenant:

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

    $Readme.Replace('@@COULD-NOT-READ@@', $CouldNotRead).Replace('@@PIM-LEFT-OUT@@', $PimLeftOutSection).Replace('@@ROOT-SCOPE@@', $RootScopeSection).Replace('@@SHARED-NAMES@@', $SharedNameSection).Replace('@@UNRESOLVED-PRINCIPALS@@', $UnresolvedPrincipalSection).Replace('@@UNDECLARABLE-SCOPES@@', $UndeclarableScopeSection).Replace('@@RESTRICTED-UNIT-PIM@@', $RestrictedUnitSection).Replace('@@LIGHTHOUSE@@', $LighthouseSection)
}
