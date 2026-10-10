function Export-OERInventory {
    <#
    .SYNOPSIS
    Reads a tenant's RBAC posture and writes a self-contained bundle (JSON + LLM prompt + README).

    .DESCRIPTION
    Composes the existing Get-OER* read cmdlets into a timestamped bundle folder containing the
    canonical round-trippable inventory.json, per-area JSON files -- including
    directoryRoleManagementPolicies.json and directoryRoleAssignments.json for the Microsoft Entra
    directory role sections -- read-only context (scopeHierarchy.json, groupsRoster.json,
    azurePimEligibility.json), a formal
    JSON Schema (schema.json), a predefined LLM prompt (rbac-architect-prompt.md), and a README. The
    bundle is designed to be handed to any LLM to produce appliable RBAC proposals. Only
    RBAC-relevant groups are kept in full detail in inventory.json: a role-assignable group, a group
    with PIM eligibility, a group carrying a pimPolicy block, and, with -IncludeSyncedGroups, a
    security group synchronized from on-premises Active Directory. Microsoft Graph lists
    PIM-for-groups policies for a group that was never used with PIM for Groups as well, so the
    export writes a pimPolicy block only for a group found to use PIM for Groups -- one with PIM
    eligibility, or one whose PIM-for-Groups policy has been modified -- and a group whose policies
    Graph merely lists is not kept in full detail on that account. -AllGroupsDetailed keeps every
    group inventory.json covers. The cmdlet reads only -- no tenant state changes -- and
    authenticates at entry; an ARM token is acquired only when -Include names RoleAssignments or
    RoleManagementPolicies, the two Azure sections.

    HOW THE GROUPS ARE READ. Without -AllGroupsDetailed the export decides which groups are relevant
    BEFORE it reads any group in full, so in a tenant with very many groups a group that is not
    relevant is never read in full. For each listed group it reads the PIM eligibility (one
    request); a group that is role-assignable, has eligibility, or is synchronized under
    -IncludeSyncedGroups is decided by that. Any other group costs one more request, a listing of
    its PIM-for-Groups policies that tells whether it uses PIM for Groups. A group the two requests
    find not relevant costs exactly those two: its members, owners and PIM policies are not read,
    and it is not in inventory.json. Every other group is read in full exactly as before. A group
    whose relevance could not be read -- its eligibility read or the policy listing failed -- is
    read in full as before too, kept or left out by the same criteria, and what could not be read
    about it is named in IncompleteReads; it is never dropped on a guess. -AllGroupsDetailed reads
    every listed security group in full, as before. While it reads the groups the export shows
    progress (Write-Progress, activity Export-OERInventory, one 'Group n of N' record per listed
    security group) and ends it when the read is done, also when the read stops on an error.

    WHICH GROUPS INVENTORY.JSON COVERS, AND WHICH IT DOES NOT. The Groups section is read with the
    'securityEnabled eq true' filter, the one Get-OERInventory applies by default, so it carries the
    SECURITY-ENABLED groups only -- a distribution group, and a Microsoft 365 group whose
    securityEnabled is false, are absent from it at every detail level, -AllGroupsDetailed
    included. That scope is deliberate: inventory.json is the apply-engine document, and widening
    it widens what Invoke-OERStructure reconciles and, under -Prune, deletes. -GroupFilter narrows
    that scope and never widens it. To widen it anyway, read the inventory yourself with
    Get-OERInventory -GroupFilter and supply the filter you want. groupsRoster.json is NOT
    filtered: it lists every group in the tenant, of every type, as read-only context, so the gap
    between the two files is visible rather than silent. Each of its rows carries onPremisesSynced,
    true for a group synchronized from on-premises Active Directory and false otherwise, and
    memberCount: the group's member count when the export read the group in full, and null
    otherwise -- for a group the export found not relevant, one outside -GroupFilter, one left out
    because another group shares its name, one whose members could not be read, and every group
    that is not security-enabled. Null means not known, which is not zero: a count would cost a
    request per group.

    Azure coverage is reported, not assumed. ScopesEnumerated is how many ARM scopes the walk found,
    ScopeCount is how many of them were actually read, and SkippedScopes names the ones that were
    not. When anything was skipped the bundle summary is still emitted first and is then followed by
    a non-terminating InventoryPartial error, so a caller using -ErrorAction Stop or a try/catch
    finds out that roleAssignments.json and roleManagementPolicies.json are incomplete instead of
    treating a truncated bundle as a full tenant snapshot. A level of the tree that could not be
    LISTED is skipped the same way: a refused or failed management-group listing is named in
    SkippedScopes and SkippedEligibilityScopes as '<management groups: the listing failed>' (a failed
    subscription listing as '<subscriptions: the listing failed>'), never read as "no management
    groups". A management group created in the last few minutes can be missing from the
    management-group list, and an export run in that window does not walk it -- nor name it as
    skipped -- because it cannot know it exists. Wait until Get-OERManagementGroup lists it before
    relying on an export that should include it.

    Azure PIM eligibility is read the same walk over, into azurePimEligibility.json, but only when an
    Azure section (RoleAssignments or RoleManagementPolicies) is included -- the file is absent
    otherwise. That is UNLIKE the two role-assignment files it sits beside: roleAssignments.json and
    roleManagementPolicies.json are always written, as an empty [] when no Azure section was
    requested, while azurePimEligibility.json is the one bundle file that is sometimes not written at
    all. One paged Get-OEREligibleRoleAssignment read runs per scope the walk visits: a management
    group scope is read with -AtScope (eligibilities at or above it); every other scope is read
    unfiltered, which also surfaces eligibilities below that scope -- Microsoft Learn's listForScope
    documents four filters (atScope(), principalId eq '{id}', assignedTo('{userId}') and asTarget())
    and no unfiltered semantics at all, so this was MEASURED rather than taken from documentation: in
    the step 5 live-verification checklist, section 4
    (docs/live-verification/feat-inventory-directory-roles-and-rename-checklist.md), one unfiltered
    subscription read returned an eligibility at a resource group below it (2026-09-30).
    Resolve-OERInventoryScopeTree enumerates management group and subscription scopes only, so a
    resource-group- or resource-scoped eligibility reaches this file ONLY through that unfiltered
    subscription read's below-scope behaviour. The results
    are deduplicated on the eligibility schedule id, so one eligibility
    visible from several scopes in the walk appears once -- for example a management-group
    eligibility, read once directly at the management group and again, inherited, from every
    subscription below it. The file is read-only context, exactly like scopeHierarchy.json and
    groupsRoster.json: it is never an apply-document section and no apply cmdlet reads it back. Every
    per-area file and azurePimEligibility.json alike is always a JSON array on disk, written as [] when
    it carries nothing. A scope whose eligibility read fails is named in SkippedEligibilityScopes and
    folds into the same trailing InventoryPartial error as a failed role-assignment scope.

    WHICH AZURE ROLE MANAGEMENT POLICIES ARE EXPORTED. A scope's policy list carries the policies of
    roles nobody uses or has changed there -- 963 of 967 on the one subscription measured -- so without
    -AllRolePolicies the RoleManagementPolicies section keeps a role's policy at a scope only when the
    role has an active role assignment or a PIM eligibility EXACTLY at that scope, or the policy has
    been changed. An assignment or an eligibility at a management group above the scope, or at a
    resource group below it, does not keep it. A policy counts as changed when the policy object the
    list returns for it carries a non-empty lastModifiedDateTime, or a lastModifiedBy with a non-empty
    id or displayName: measured on one subscription, every untouched policy carried no date and an
    empty lastModifiedBy, and every changed one a date and a display name. The policies are still read
    with the one paged policy list per scope, and nothing is requested per policy. The selection adds
    one paged role assignment list per scope (atScope(): the assignments at or above it), read just
    before that policy list, and uses the eligibility read described above, which the export makes for
    azurePimEligibility.json anyway. A policy that cannot be judged is kept, never dropped, and its
    scope is named in IncompleteReads (below): one not kept by a use or a change whose list row
    carries no policy object or no role definition id, or whose scope's role assignment read or
    eligibility read failed. A failed role assignment read writes one warning ('Could not read the
    role assignments at scope ...') and costs only the selection: the scope is still read. A failed
    policy list skips the scope exactly as before. -AllRolePolicies exports every policy at every
    scope the walk reads, with the call earlier versions made. Invoke-OERStructure reads and writes
    only the policies a document declares, so a policy the export leaves out stays as it is when the
    document, or a proposal built from it, is applied.

    Entra ID coverage is reported the same way. IncompleteReads carries, first, one entry for the
    Groups read when it left anything unread, then one entry per partial report from
    Get-OERInventory, which reads the other Entra ID sections. Each entry names the affected
    section/displayName/key triples -- so a single read that lost three collections reports one
    entry listing all three, not three entries -- and the entry groupsRoster is added when the group
    roster could not be read. A section whose whole list could not be read appears in those entries
    by its own name alone (groups also when the group read stops on an unforeseen error, with the
    warning 'Could not read groups: ...'), and is written as an empty array that does not mean the
    tenant has none; the entry groupsRoster likewise means groupsRoster.json is empty only because
    the roster read failed. Last, after every Entra ID entry, IncompleteReads carries one entry per
    Azure scope where at least one role management policy could not be judged (see WHICH AZURE ROLE
    MANAGEMENT POLICIES ARE EXPORTED above), reading 'roleManagementPolicies/role selection at' and
    the scope in its canonical form -- for a subscription,
    'roleManagementPolicies/role selection at /subscriptions/<id>'. Such an entry names no unread
    collection: every policy at that scope that could not be judged was kept, none of them left out
    -- where the scope's role assignment read or eligibility read failed, that is every policy of a
    role neither used nor changed there -- so roleManagementPolicies.json may hold policies of roles
    that are neither used nor changed at that scope. It does not mean every policy at the scope was
    kept: when only one row could not be judged, the other unused, unchanged policies there are still
    left out. The Count of IncompleteReads is therefore one for the Groups read when it left anything
    unread, plus the number of partial reports from Get-OERInventory, plus one when the group roster
    could not be read, plus one per such Azure scope, and not the number of unread collections; read
    the entries for that. The same non-terminating InventoryPartial error is raised here when
    IncompleteReads, SkippedScopes or SkippedEligibilityScopes is non-empty, and its message gives the
    causes of the unread group reads (Get-OERInventory's own InventoryPartial gives those of the other
    sections). The part of that message that counts partial Entra ID read entries counts the Entra ID
    entries only; the Azure scopes where policies could not be judged have a clause of their own,
    which names each of them. A members, scopedRoles, resources or resourceRoles collection that
    could not be read, or that has an entry the export could name by nothing the apply engine
    accepts, is NOT written into inventory.json as an empty one or with an empty name: its key is an
    explicit null, which the apply engine reads as "leave untouched". Do not hand-edit that null to
    [] -- under Invoke-OERStructure -Prune an empty declared collection deletes every live member,
    binding or resource. Any other collection IncompleteReads names is left out of the document or
    written only as far as it was read, as the Get-OERInventory help describes; Invoke-OERStructure
    never removes a catalog, access package or assignment policy that is absent from the document.

    The bundle says so itself. The generated README.md carries a section named "What this export
    could not read": one bullet per IncompleteReads, SkippedScopes and SkippedEligibilityScopes
    entry, an Azure scope where role management policies could not be judged under a label of its
    own, or the statement that nothing was left unread, so whoever receives the bundle
    (an LLM, say) can tell a collection that was not read from one that is empty. The lists go into
    README.md only, never into inventory.json or any other file that is validated or applied.

    inventory.json carries the top-level tenantId that Get-OERInventory writes -- the tenant ID the
    session's Microsoft Graph token was issued for -- so Invoke-OERStructure applies it only in that
    tenant and refuses it elsewhere with DocumentTenantMismatch; the Get-OERInventory help describes
    the rule.

    WHERE THE FILES LAND: nothing is ever written directly into -OutputPath. -OutputPath is only the
    PARENT directory; every file goes into a new timestamped subfolder beneath it named
    oer-inventory-<tenant>-<yyyyMMdd-HHmmss>, so inventory.json is at
    <OutputPath>/oer-inventory-<tenant>-<stamp>/inventory.json and NOT at <OutputPath>/inventory.json.
    <tenant> is the tenant as the session names it (an ID, or the domain given to -TenantId), which can
    differ from the tenantId inside inventory.json. Because the stamp is generated per run, the only
    reliable way to address the bundle afterwards is the BundlePath property of the returned
    Omnicit.EntraRBAC.InventoryBundle object -- an absolute path, populated under -WhatIf too (as the
    planned location). Capture the returned object and join onto its BundlePath rather than guessing
    the folder name; see the Test-OERStructure example below.

    The full export to LLM to Test-OERStructure to Invoke-OERStructure walkthrough is documented in
    the repository at docs/inventory-to-llm/README.md, and a worked apply document is kept in the
    repository at docs/examples/example-structure.json. Neither ships inside the installed module,
    so clone or browse the repository to read them.

    .PARAMETER OutputPath
    The PARENT directory under which the timestamped bundle folder is created; the bundle files are
    written into that subfolder, never directly into this directory. Defaults to the current
    directory. Use the returned object's BundlePath to address the files afterwards.

    .PARAMETER Include
    Which sections to gather from the tenant. Defaults to the Entra sections (Groups,
    AdministrativeUnits, Catalogs, AccessPackages, AccessReviews, DirectoryRoleManagementPolicies,
    DirectoryRoleAssignments) plus RoleAssignments. The two DirectoryRole* sections are Graph-only
    and never acquire an ARM token by themselves. RoleManagementPolicies, the Azure role management
    policies, is not in the default: named here, it exports the policies of the roles in use or
    changed at each scope the walk reads (see WHICH AZURE ROLE MANAGEMENT POLICIES ARE EXPORTED
    above), and every policy with -AllRolePolicies.

    .PARAMETER AllGroupsDetailed
    Read every group the Groups section covers in full, as earlier versions did, and keep each in
    full detail in inventory.json, not just the RBAC-relevant ones. Without it the export decides
    first which groups are relevant and reads only those in full (see HOW THE GROUPS ARE READ
    above). With it, groupsRoster.json carries the member count of every security group the read
    covers, null only for one whose members could not be read or that shares its name with another.
    That section is security-enabled-scoped, so this switch does not reach a distribution group or a
    Microsoft 365 group whose securityEnabled is false -- neither is in inventory.json at any detail
    level. Use Get-OERInventory -GroupFilter to widen the scope itself; groupsRoster.json already
    lists every group in the tenant unfiltered.

    .PARAMETER IncludeSyncedGroups
    Also keep, in full detail in inventory.json, every security group synchronized from on-premises
    Active Directory (onPremisesSynced: true), and read its members and owners for that. Such a
    group is never RBAC-relevant by the default criteria -- it cannot be role-assignable or managed
    in PIM for Groups -- so without this switch it costs the two requests that decide it is not
    relevant, appears only in groupsRoster.json, and has a null memberCount there. It is managed
    on-premises: Invoke-OERStructure writes nothing to it, and its onPremisesSynced key is
    information only. With -AllGroupsDetailed every group is read and kept already and this switch
    changes nothing.

    .PARAMETER AllDirectoryRolePolicies
    For the DirectoryRoleManagementPolicies section, export the policy of every Microsoft Entra
    directory role, instead of only the roles that have at least one row in the tenant-scope
    eligibility or assignment schedules (the default). Forwarded to the internal Get-OERInventory
    call; has no effect unless -Include names DirectoryRoleManagementPolicies.

    .PARAMETER AllRolePolicies
    For the RoleManagementPolicies section, export the policy of every Azure role at every scope the
    walk reads, as earlier versions did, instead of only the policies of roles with an active role
    assignment or a PIM eligibility exactly at that scope, or whose policy has been changed (the
    default; see WHICH AZURE ROLE MANAGEMENT POLICIES ARE EXPORTED above). The export then reads each
    scope with the call earlier versions made: no role assignment list is read for the selection, and
    no scope is named in IncompleteReads as kept without being judged. Has no effect unless -Include
    names RoleManagementPolicies; the DirectoryRoleManagementPolicies section has its own switch,
    -AllDirectoryRolePolicies.

    .PARAMETER ManagementGroup
    Narrow the Azure scope walk to a single management group branch identified by name or id.

    .PARAMETER Scope
    Narrow the Azure scope walk to a single raw ARM scope string (e.g. a subscription id path).

    .PARAMETER Force
    Overwrite an existing bundle folder of the same name. Without this switch an existing folder of the
    same name is left in place and its contents are merged with the new files. Use -WhatIf to preview
    the bundle plan without touching disk.

    .PARAMETER TenantId
    Optional tenant id or domain name forwarded to Initialize-OERAuth for explicit tenant targeting.
    The tenantId written into inventory.json is the tenant ID the session's Microsoft Graph token was
    issued for, not this value.

    .PARAMETER GroupFilter
    An OData filter that narrows the groups inventory.json is read from, for a tenant with very many
    groups. It is ANDed to the security-enabled filter inside parentheses, so the groups are listed
    with 'securityEnabled eq true and (your filter)', and it only narrows: the export also keeps only
    the groups the read itself shows as securityEnabled (a boolean true), so a filter that closes the
    parenthesis, for example 'x eq 1) or (securityEnabled eq false', cannot widen inventory.json to a
    group that is not security-enabled. Such a group is left out, with one warning that names how
    many were left out. With -AllGroupsDetailed a group the filter widens to is read in full before
    it is left out; the default read reads nothing of it. The expression is yours: it is sent as
    typed and never escaped, so double a single quote inside a quoted value yourself ('O''Brien'). It
    applies to the Groups section only: it changes nothing when -Include leaves Groups out, and
    groupsRoster.json is not filtered by it and still lists every group in the tenant, with a null
    memberCount for a security group the filter left out, since that group was not read. An empty or
    white space value is refused at binding.

    .EXAMPLE
    Export-OERInventory
    Reads the tenant and writes a bundle under the current directory.

    .EXAMPLE
    Export-OERInventory -GroupFilter "startswith(displayName,'role_')"
    Reads inventory.json's groups from the security-enabled groups whose display name starts with
    role_ only, so far fewer groups are read in a tenant with very many of them. groupsRoster.json
    still lists every group in the tenant.

    .EXAMPLE
    Export-OERInventory -OutputPath C:\Temp -Include Groups,AdministrativeUnits,Catalogs,AccessPackages,RoleAssignments,RoleManagementPolicies
    Reads the full posture (including tenant-wide Azure role assignments, and the PIM policies of the
    Azure roles in use or changed at each scope) into a bundle under
    C:\Temp\oer-inventory-<tenant>-<stamp>\, not into C:\Temp itself.

    .EXAMPLE
    Export-OERInventory -Include RoleAssignments,RoleManagementPolicies -AllRolePolicies
    Reads the Azure role assignments and the role management policy of every Azure role at every
    scope the walk reads, as earlier versions did. Without -AllRolePolicies, roleManagementPolicies.json
    holds only the policies of roles with an active role assignment or a PIM eligibility exactly at
    the policy's scope, or whose policy has been changed, and every policy that could not be judged.

    .EXAMPLE
    $Bundle = Export-OERInventory -OutputPath C:\Temp
    Test-OERStructure -Path (Join-Path $Bundle.BundlePath 'inventory.json')

    Captures the bundle summary and validates the exported inventory through the apply schema. Joining
    onto BundlePath is the supported way to reach the file: passing C:\Temp\inventory.json instead
    fails with "Structure document not found", because the export never writes into -OutputPath itself.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$OutputPath = '.',
        [ValidateSet('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews',
            'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments', 'RoleManagementPolicies')]
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews',
            'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments'),
        [switch]$AllGroupsDetailed,
        [switch]$IncludeSyncedGroups,
        [switch]$AllDirectoryRolePolicies,
        # A switch takes no position, so declaring it here leaves every positional parameter where it
        # was (see the -GroupFilter comment below).
        [switch]$AllRolePolicies,
        [string]$ManagementGroup,
        [string]$Scope,
        [switch]$Force,
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,
        # Declared LAST on purpose, as New-OERConfiguration's -Environment is. Positional binding
        # follows DECLARATION order, so a parameter inserted above -ManagementGroup, -Scope or
        # -TenantId would silently change what an existing positional argument binds to.
        # A filter of white space only is refused here, at binding, as an empty one is (the same
        # BL-96 pattern as New-OERConfiguration's -TenantId). The module supports PowerShell 7.2, which
        # has no [ValidateNotNullOrWhiteSpace()] (7.4+), so the same test runs as a script. Declared
        # ABOVE [ValidateNotNullOrEmpty()] on purpose: validation attributes run in reverse
        # declaration order (measured), so an empty or null value still reads the NotNullOrEmpty
        # message and white space reads this one.
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) }, ErrorMessage = 'The GroupFilter consists only of white space. Pass an OData filter, or leave the parameter out.')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupFilter
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        # Only the Azure sections need an ARM token. Acquiring one unconditionally also forced a
        # Graph re-authentication for app-only sessions: this cmdlet passes no -AuthMethod, so when
        # no ARM token is cached the passive-reuse check fails and the identity check then compares
        # the cached AuthMethod against the 'Interactive' default -- turning a pure-Entra export in a
        # ClientSecret session into an interactive sign-in prompt.
        if (@($Include | Where-Object { $_ -in @('RoleAssignments', 'RoleManagementPolicies') }).Count -gt 0) {
            $AuthParams.IncludeARM = $true
        }
        Initialize-OERAuth @AuthParams
        # BL-88 (A14): the tenant inventory.json names, captured here under the session this command
        # signed in under. It is this cmdlet's own capture, never the tenantId of the inventory
        # Get-OERInventory returns, so the document is assembled with the one value in both calls.
        $DocumentTenantId = Get-OERInventoryTenantId
    }
    process {
        # --- Gather the Entra ID sections (names only, for portability) ---
        # The Groups section is read by the group reader directly, not through Get-OERInventory, so
        # the export can ask it to decide RBAC relevance FIRST (A13): without -AllGroupsDetailed a
        # group costs two requests (its PIM eligibility and the PIM-in-use criterion) before anything
        # else is read, and only a group that is relevant -- or whose relevance could not be read --
        # has its members, owners and PIM policy read. -AllGroupsDetailed reads every group in full,
        # as before. The 'securityEnabled eq true' filter is the scope Get-OERInventory applies by
        # default, so inventory.json covers the same groups it always did. -ExcludeSharedName leaves
        # out groups that share a name, the rule Get-OERInventory applies to its own groups section.
        # The reader never writes an error record: what it could not read comes back in its Unread
        # and Causes lists, folded into IncompleteReads and the partial message below. It shows
        # progress under this cmdlet's own activity while it reads ('Group n of N') and ends it when
        # the read is done, also when it stops on an error, before the Azure scope walk starts its own.
        #
        # -GroupFilter narrows that scope and never widens it. It is ANDed to the security-enabled
        # filter inside parentheses, and it is the operator's OWN OData expression, so it is sent as
        # typed and never escaped through ConvertTo-OERODataFilterValue (that helper escapes a VALUE
        # for a quoted literal, and applied to a whole expression it would break the expression);
        # Get-OERGroup -Filter percent-encodes the whole expression once. The parentheses alone are
        # not the guard, since an expression can close them ('x eq 1) or (securityEnabled eq false'
        # lists every group the second operand matches). The guard is -SecurityEnabledOnly, which
        # keeps only the groups the read itself shows as securityEnabled, whatever the filter listed.
        $GroupRead = $null
        if ($Include -contains 'Groups') {
            $GroupReadParams = @{
                Filter              = if ($GroupFilter) { "securityEnabled eq true and ($GroupFilter)" } else { 'securityEnabled eq true' }
                IncludeId           = $true
                ExcludeSharedName   = $true
                SecurityEnabledOnly = $true
                ProgressActivity    = 'Export-OERInventory'
            }
            if (-not $AllGroupsDetailed) {
                $GroupReadParams.RelevantOnly = $true
                if ($IncludeSyncedGroups) { $GroupReadParams.IncludeSyncedGroups = $true }
            }
            # The reader catches what it expects (a failed list read, a failed collection read) and
            # names it in Unread and Causes. This catch is for the rest: an error nothing in the
            # reader catches ends the read, and the reader's progress try/finally unwinds it -- a
            # statement-terminating error as well as a throw -- so the call returns NOTHING. A
            # $GroupRead of $null would be read below as zero groups with nothing unread, which is
            # a failed read stated as an empty fact. So the stop is reported as what it is, the
            # groups section unread, with the reader's own wording for a list that could not be read:
            # the warning stands before the bundle's ShouldProcess (the read comes first), the cause
            # reaches the InventoryPartial message, and the rest of the export carries on.
            try {
                $GroupRead = Get-OERInventoryGroup @GroupReadParams
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $GroupReadCause = "Could not read groups: $($PSItem.Exception.Message)"
                Write-Warning $GroupReadCause
                $GroupRead = [PSCustomObject]@{
                    Groups = @()
                    Unread = @('groups')
                    Causes = @([PSCustomObject]@{ Cause = $GroupReadCause; Target = '' })
                }
            }
        }
        # DirectoryRoleManagementPolicies and DirectoryRoleAssignments are Graph-only, same as the
        # other four: they are deliberately absent from the ARM-triggering check above, so naming
        # either one alone never acquires an ARM token.
        $EntraSections = @($Include | Where-Object { $_ -in @('AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments') })
        # The ids the roster member-count join below is keyed on come from the group reader alone:
        # it is asked for -IncludeId above, PURELY to key that join on object id instead of display
        # name (Entra permits duplicate group display names -- Add-OERGroupMember.ps1:43-45 -- so a
        # display-name join can attribute one group's member count to a different, same-named
        # group). Get-OERInventory below reads the other sections and is not asked for ids, since
        # nothing here joins on them. inventory.json staying id-free is a documented portability
        # property of the export (Get-OERInventory's own .DESCRIPTION), so the ids the reader
        # stamped are stripped back out below, before the canonical inventory and the per-area files
        # are assembled and written; the same strip also covers any other section that arrives with
        # an id.
        $InventoryReadErrors = $null
        $Inv = if ($EntraSections.Count -gt 0) {
            # -ErrorAction Continue is PINNED here, not inherited, and deliberately not Stop.
            # Get-OERInventory now reports a collection it could not read as a non-terminating
            # InventoryPartial, and that must be folded into THIS cmdlet's single coverage signal
            # rather than aborting an otherwise usable bundle. Without the pin this call inherits
            # $ErrorActionPreference from the caller's scope, so under the very
            # Export-OERInventory -ErrorAction Stop that this cmdlet's own help tells operators to
            # adopt, the inner record would terminate HERE -- outside any try/catch, before a single
            # bundle file is written -- and the operator would get an exception and NO BUNDLE AT
            # ALL, instead of the documented "summary emitted first, then a loud error". Continue
            # keeps the record non-terminating while still delivering it to BOTH the caller's error
            # stream and $InventoryReadErrors; Export's own trailing Write-CmdletError is what
            # honours -ErrorAction Stop, and it runs after $Out has been emitted.
            #
            # -AllDirectoryRolePolicies is added to the splat only when the switch is actually set,
            # not forwarded unconditionally as -AllDirectoryRolePolicies:$AllDirectoryRolePolicies
            # would be: Get-OERInventory's own default behaviour (policy of only the in-use roles) is
            # what every OTHER -Include combination in this file's test suite already relies on, and
            # binding the parameter at all -- even to $false -- is observable to a caller's
            # -ParameterFilter, so adding it only when true keeps every existing call site untouched.
            $InvParams = @{
                Include       = $EntraSections
                ErrorAction   = 'Continue'
                ErrorVariable = 'InventoryReadErrors'
            }
            if ($AllDirectoryRolePolicies) { $InvParams.AllDirectoryRolePolicies = $true }
            Get-OERInventory @InvParams
        } else {
            ConvertTo-OERInventory -TenantId $DocumentTenantId
        }
        $IncompleteReads = [System.Collections.Generic.List[string]]::new()
        # The Groups read is reported FIRST, as ONE entry naming everything it could not read: the
        # same shape, and the same place, as the groups take in a Get-OERInventory report, which
        # reads them first. The null-filter keeps a blank entry out, so an IncompleteReads count
        # never stands for a gap that names nothing.
        $GroupUnread = @(if ($GroupRead) { @($GroupRead.Unread) | Where-Object { $_ } })
        if ($GroupUnread.Count -gt 0) { $IncompleteReads.Add(($GroupUnread -join ', ')) }
        foreach ($IErr in @($InventoryReadErrors)) {
            if ($null -eq $IErr) { continue }
            if ($IErr.FullyQualifiedErrorId -like 'InventoryPartial*') {
                # TargetObject carries the section/displayName/key triples, which is what makes the
                # summary entry name the affected object rather than merely count one. It is not
                # guaranteed to be populated (a caller-supplied mock, or a future variant of the
                # error), and an empty entry would make an IncompleteReads count assertion pass
                # while saying nothing -- fall back to the message rather than record a blank.
                $ReadDetail = [string]$IErr.TargetObject
                if (-not $ReadDetail) { $ReadDetail = [string]$IErr.Exception.Message }
                $IncompleteReads.Add($ReadDetail)
            }
        }

        # --- Naming auto-seed: the profile whose TenantId matches the connected tenant ---
        $NamingConvention = $null
        try {
            $ConnectedTenant = if ($script:_OERAuthState) { [string]$script:_OERAuthState.TenantId } else { $TenantId }
            # -ErrorAction Stop for the same reason as the per-scope read below: without it a
            # NON-terminating failure (a corrupt profile on disk now reports TenantProfileMalformed)
            # bypasses this catch entirely and leaks out of Export-OERInventory, setting $? false on
            # an otherwise complete bundle. InventoryPartial is the only coverage signal this cmdlet
            # raises; a profile that cannot be read is a missing prompt hint, not missing coverage.
            $Profiles = @(Get-OERConfiguration -ErrorAction Stop)
            $Match = @($Profiles | Where-Object { $_.TenantId -and $_.TenantId -eq $ConnectedTenant })
            if ($Match.Count -eq 0 -and $Profiles.Count -eq 1) { $Match = $Profiles }
            if ($Match.Count -ge 1 -and $Match[0].Naming) { $NamingConvention = [string]$Match[0].Naming.Group }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            # Verbose rather than a warning: the seed is a convenience that only shapes a hint line
            # in the LLM prompt, so its absence never makes the bundle wrong -- but a silent catch
            # gave an operator wondering why the prompt has no naming convention nothing to read.
            Write-Verbose "[Export-OERInventory] Could not auto-seed the naming convention from a tenant profile: $($PSItem.Exception.Message)"
        }

        # --- Tenant-wide Azure walk (RoleAssignments / RoleManagementPolicies) ---
        $AzureSections = @($Include | Where-Object { $_ -in @('RoleAssignments', 'RoleManagementPolicies') })
        $RoleAssignments = [System.Collections.Generic.List[object]]::new()
        $RoleManagementPolicies = [System.Collections.Generic.List[object]]::new()
        $ScopeHierarchy = [PSCustomObject]@{ managementGroups = @(); subscriptions = @() }
        # ScopesEnumerated is what the walk FOUND; ScopeCount is what it actually READ. Reporting
        # only the first overstated coverage: a run that skipped 40 of 50 scopes still said 50.
        $ScopeCount = 0
        $ScopesEnumerated = 0
        $SkippedScopes = [System.Collections.Generic.List[string]]::new()
        $AzureEligibilities = @()
        $SkippedEligibilityScopes = [System.Collections.Generic.List[string]]::new()

        # BL-107: without -AllRolePolicies the RoleManagementPolicies section keeps a role's policy at a
        # scope only when the role has an active assignment or an eligibility EXACTLY at that scope, or
        # the policy has been changed (Select-OERInventoryRolePolicy owns the rule). The policies are
        # then read per scope by Get-OERInventoryRolePolicy -- the same one paged list and the same
        # converters as Get-OERInventory -AllRolesAtScope -- and kept or omitted after the walk, once
        # the eligibility read below is in; nothing is requested per policy. -AllRolePolicies runs the
        # per-scope Get-OERInventory call exactly as before and selects nothing.
        $SelectRolePolicies = ($AzureSections -contains 'RoleManagementPolicies') -and -not $AllRolePolicies
        $ScopeSections = @(if ($SelectRolePolicies) { $AzureSections | Where-Object { $_ -ne 'RoleManagementPolicies' } } else { $AzureSections })
        $RolePolicyCandidates = [System.Collections.Generic.List[object]]::new()
        $RoleAssignmentFacts = [System.Collections.Generic.List[object]]::new()
        $RoleAssignmentUnreadScopes = [System.Collections.Generic.List[string]]::new()
        # The 'roleManagementPolicies/role selection at <scope>' entries, the scope in its canonical
        # form (ConvertTo-OERCanonicalScope: a trailing '/' trimmed, letter case kept; an ARM scope
        # reads 'roleManagementPolicies/role selection at /subscriptions/...'), in the shape of
        # Get-OERInventory's 'directoryRoleManagementPolicies/role selection': scopes where at least one
        # policy could not be judged and was kept. Kept apart from the Entra ID entries in
        # $IncompleteReads and appended after them, so the Entra ID entries keep their documented order
        # and own clause.
        $RolePolicySelectionReads = [System.Collections.Generic.List[string]]::new()

        if ($AzureSections.Count -gt 0) {
            $TreeParams = @{}
            if ($ManagementGroup) { $TreeParams.ManagementGroup = $ManagementGroup }
            if ($Scope) { $TreeParams.Scope = $Scope }
            $Tree = $null
            try {
                $Tree = Resolve-OERInventoryScopeTree @TreeParams
                $ScopeHierarchy = $Tree.Hierarchy
                $ScopesEnumerated = @($Tree.Scopes).Count
                # A level of the tree that could not be LISTED (a refused management-group listing,
                # say) was not walked at all: it is skipped for the role-assignment walk AND for
                # azurePimEligibility.json, which makes the bundle InventoryPartial below -- never
                # "no management groups".
                foreach ($TreeSkip in @($Tree.SkippedScopes)) {
                    if (-not $TreeSkip) { continue }
                    $SkippedScopes.Add([string]$TreeSkip)
                    $SkippedEligibilityScopes.Add([string]$TreeSkip)
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not enumerate Azure scopes: $($PSItem.Exception.Message)"
                $Tree = $null
                # Record the whole Azure walk as skipped so the partial-coverage error below fires.
                # Without this the bundle is written with ZERO role assignments and zero policies and
                # nothing but a warning says so, which leaves $? true and -ErrorAction Stop inert.
                $SkippedScopes.Add('<all Azure scopes: scope enumeration failed>')
                # Same reasoning for the eligibility read: with no scope tree there is nothing to walk
                # for azurePimEligibility.json either, and the gap must be named rather than silently
                # written as an empty (and therefore misleadingly "complete") file.
                $SkippedEligibilityScopes.Add('<all Azure scopes: scope enumeration failed>')
            }
            if ($Tree) {
                $SeenRa = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $SeenRmp = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $ScopeIndex = 0
                try {
                    foreach ($S in @($Tree.Scopes)) {
                        $ScopeIndex++
                        Write-Progress -Activity 'Export-OERInventory' -Status "Azure scope $ScopeIndex of $ScopesEnumerated" -PercentComplete (($ScopeIndex / [Math]::Max($ScopesEnumerated, 1)) * 100)
                        $ScopeInv = $null
                        $ScopeCandidates = @()
                        $ScopeAssignments = @()
                        $ScopeAssignmentsUnread = $false
                        try {
                            # Selecting, the call leaves RoleManagementPolicies (and -AllRolesAtScope)
                            # out and is not made at all when nothing is left; otherwise it is the call
                            # it always was.
                            if ($ScopeSections.Count -gt 0) {
                                $ScopeParams = @{ Include = $ScopeSections; Scope = $S }
                                if ($ScopeSections -contains 'RoleManagementPolicies') { $ScopeParams.AllRolesAtScope = $true }
                                # -ErrorAction Stop is load-bearing: without it a NON-terminating failure
                                # inside Get-OERInventory never reaches this catch under the default
                                # preference, so the scope contributed nothing and did not even warn.
                                $ScopeInv = Get-OERInventory @ScopeParams -ErrorAction Stop
                            }
                            if ($SelectRolePolicies) {
                                # The role assignments listed at (or above) the scope, FIRST: its sign-in
                                # check renews a token near expiry before the policy list, as the
                                # per-scope Get-OERRoleManagementPolicy call does with -AllRolePolicies.
                                # A failure here costs the selection, not the scope: the policies at the
                                # scope are then kept without being judged and named, never dropped.
                                try {
                                    $ScopeAssignments = @(Get-OERRoleAssignment -Scope $S -AtScope -ErrorAction Stop)
                                } catch {
                                    Remove-OERErrorRecord -Record $PSItem
                                    Write-Warning "Could not read the role assignments at scope '$S', so its role management policies are kept without being judged: $($PSItem.Exception.Message)"
                                    $ScopeAssignmentsUnread = $true
                                }
                                # A failed policy list reaches the catch below and skips the scope, as a
                                # failed policy read always has. -ErrorAction Stop for the same reason as
                                # above.
                                $ScopeCandidates = @(Get-OERInventoryRolePolicy -Scope $S -ErrorAction Stop)
                            }
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            Write-Warning "Skipping scope '$S': $($PSItem.Exception.Message)"
                            $SkippedScopes.Add([string]$S)
                            continue
                        }
                        # $ScopeInv is $null when no call was made, and @($null.X) is a one-element
                        # array holding $null, so every read of it drops nulls.
                        foreach ($Ra in @($ScopeInv.RoleAssignments | Where-Object { $null -ne $_ })) {
                            $Key = if ($Ra.PSObject.Properties.Name -contains 'id' -and $Ra.id) { [string]$Ra.id } else { '{0}|{1}|{2}' -f $Ra.scope, $Ra.role, $Ra.principal }
                            if ($SeenRa.Add($Key)) { $RoleAssignments.Add($Ra) }
                        }
                        # Non-empty only under -AllRolePolicies: selecting, the call reads no policy.
                        foreach ($Rmp in @($ScopeInv.RoleManagementPolicies | Where-Object { $null -ne $_ })) {
                            $Key = '{0}|{1}' -f $Rmp.scope, $Rmp.role
                            if ($SeenRmp.Add($Key)) { $RoleManagementPolicies.Add($Rmp) }
                        }
                        # The selection's inputs, from a scope that was read; decided after the walk.
                        foreach ($Candidate in $ScopeCandidates) { if ($null -ne $Candidate) { $RolePolicyCandidates.Add($Candidate) } }
                        foreach ($Fact in $ScopeAssignments) { if ($null -ne $Fact) { $RoleAssignmentFacts.Add($Fact) } }
                        if ($ScopeAssignmentsUnread) { $RoleAssignmentUnreadScopes.Add([string]$S) }
                        # Counted only here, after the scope has been read and merged, so ScopeCount
                        # reports coverage rather than intent.
                        $ScopeCount++
                    }
                } finally {
                    Write-Progress -Activity 'Export-OERInventory' -Completed
                }

                # R4: one bounded eligibility read of the SAME scope list, after the role-assignment /
                # policy walk above rather than interleaved with it, so a throttled or failing scope
                # is never charged against both files from the same failed request.
                $EligResult = Get-OERInventoryAzureEligibility -Scope @($Tree.Scopes)
                $AzureEligibilities = @($EligResult.Eligibilities)
                foreach ($SkEl in @($EligResult.SkippedScopes)) {
                    if ($SkEl) { $SkippedEligibilityScopes.Add([string]$SkEl) }
                }

                # BL-107: the selection, now that the eligibilities are read. A scope whose role
                # assignment read or eligibility read failed cannot be judged: its policies that are not
                # kept on other grounds are kept anyway, and the scope is named. The kept entries are
                # merged with the same scope|role rule as the -AllRolePolicies path above.
                if ($SelectRolePolicies) {
                    $SelectionUnread = @(@($RoleAssignmentUnreadScopes) + @($EligResult.SkippedScopes) |
                            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
                    $Selection = Select-OERInventoryRolePolicy `
                        -Policy $RolePolicyCandidates.ToArray() `
                        -Assignment $RoleAssignmentFacts.ToArray() `
                        -Eligibility @($EligResult.RoleScopes | Where-Object { $null -ne $_ }) `
                        -UnreadScope $SelectionUnread
                    foreach ($Kept in @($Selection.Kept | Where-Object { $null -ne $_ })) {
                        $Key = '{0}|{1}' -f $Kept.scope, $Kept.role
                        if ($SeenRmp.Add($Key)) { $RoleManagementPolicies.Add($Kept) }
                    }
                    foreach ($Unjudged in @($Selection.UnjudgedScopes)) {
                        if ($Unjudged) { $RolePolicySelectionReads.Add("roleManagementPolicies/role selection at $Unjudged") }
                    }
                }
            }
        }

        # --- Group split: RBAC-relevant kept in inventory.json; unfiltered roster written separately ---
        # The whole if/else is wrapped in @(...) because an empty 'else' result (no RBAC-relevant
        # groups) assigned straight from an if-statement collapses to $null, and a later @($null)
        # would inject a single null group that fails apply-schema validation. The null-item guard
        # keeps a stray null out of the filtered set. $AllGroups is what the group reader returned:
        # every group under -AllGroupsDetailed, otherwise the groups it found relevant and the ones
        # whose relevance it could not read. The filter below stays the final say either way, so a
        # group read in full only because its relevance was unknown is still not kept on that account.
        $AllGroups = @(if ($GroupRead) { @($GroupRead.Groups) | Where-Object { $null -ne $_ } })
        $DetailedGroups = @(
            if ($AllGroupsDetailed) {
                $AllGroups
            } else {
                $AllGroups | Where-Object {
                    # The null-filter inside the count is load-bearing: eligibility is ABSENT on a
                    # group whose eligibility read failed (issue #76), and @($null).Count is 1, so a
                    # bare count would class every such group as RBAC-relevant on evidence that does
                    # not exist.
                    $_.roleAssignable -eq $true -or
                    @($_.eligibility | Where-Object { $null -ne $_ }).Count -gt 0 -or
                    ($_.PSObject.Properties.Name -contains 'pimPolicy') -or
                    # A15: a group synchronized from on-premises is never kept by the three criteria
                    # above (it cannot be role-assignable or managed in PIM for Groups), so it is kept
                    # only on request. The group reader writes onPremisesSynced as a boolean true for
                    # such a group and never otherwise; anything else is not taken for it.
                    ($IncludeSyncedGroups -and $_.onPremisesSynced -is [bool] -and $_.onPremisesSynced)
                }
            }
        )

        # Member-count map keyed on object id (from the -IncludeId-stamped projection the group
        # reader returned): zero extra calls. id is the only join key: Entra permits duplicate group
        # display names (Add-OERGroupMember.ps1:43-45), so a display-name join would attribute one
        # same-named group's member count to another -- to a Microsoft 365 group the security-enabled
        # listing never held, for one.
        #
        # R3: the map holds the groups the reader READ IN FULL and nothing else. A group it did not
        # read in full -- every group of the roster that is not security-enabled, a security group
        # found not relevant (without -AllGroupsDetailed: decided from two requests, its members
        # never asked for), and a group left out for a shared name -- has no entry, so its roster
        # row gets $null below: the roster's existing "not known" value. A count for those would
        # cost a request per group, and the one-request form (groups/{id}/members/$count) needs the
        # ConsistencyLevel: eventual header, which this module's single Graph transport never sends,
        # answers from an index that can lag behind recent changes, and is not measured for service
        # principals, which the full read counts. Never fill an absent entry with 0: that states an
        # emptiness nothing measured. A group whose relevance could not be read IS read in full
        # (R2), so it has its count here although inventory.json may not keep it.
        $CountById = @{}
        foreach ($G in $AllGroups) {
            # members is null when the live read failed (issue #76). @($null).Count is 1, so a bare
            # count would report a group whose membership is UNKNOWN as having exactly one member.
            # $null is the roster's existing "not known" value and is what an unread membership gets.
            $MemberCount = if ($null -ne $G.members) { @($G.members).Count } else { $null }
            if ($G.PSObject.Properties.Name -contains 'id' -and $G.id) {
                $CountById[[string]$G.id] = $MemberCount
            }
        }

        # inventory.json staying id-free is a documented portability property of the export
        # (Get-OERInventory's own .DESCRIPTION) -- the reader's -IncludeId above exists purely to key
        # the join, so every id it stamped is removed again here, from the groups the reader
        # returned and, as a guard, from the other sections of $Inv, before the canonical inventory
        # is assembled. -IncludeId stamps more than the top-level id: a Groups eligibility entry
        # gets one too (Get-OERInventoryGroup.ps1's $EligProj.id), so the strip reaches that nested
        # collection as well.
        $StampedSections = @(
            $AllGroups, $Inv.AdministrativeUnits, $Inv.Catalogs,
            $Inv.AccessPackages, $Inv.AccessReviews,
            $Inv.DirectoryRoleManagementPolicies, $Inv.DirectoryRoleAssignments
        )
        foreach ($Section in $StampedSections) {
            foreach ($Item in @($Section)) {
                if (-not $Item) { continue }
                $Item.PSObject.Properties.Remove('id')
                if ($Item.PSObject.Properties.Name -contains 'eligibility') {
                    foreach ($Elig in @($Item.eligibility)) {
                        if ($Elig) { $Elig.PSObject.Properties.Remove('id') }
                    }
                }
            }
        }

        $Roster = @()
        if ($Include -contains 'Groups') {
            $RosterGroups = @()
            try {
                # -All, NOT -Filter 'securityEnabled eq true'. The roster is the one file in the
                # bundle that claims to be complete, and that filter made the claim false without
                # saying so: measured against a real tenant, 106 groups read back as 100 -- the 6
                # missing were 5 Microsoft 365 groups with securityEnabled false and 1 distribution
                # group. An operator comparing the roster against the portal found groups simply
                # absent, with nothing in the bundle to explain it. inventory.json keeps the
                # security-enabled scope on purpose (it is the apply document, and widening it
                # widens what -Prune deletes); the roster is read-only context and does not.
                $RosterGroups = @(Get-OERGroup -All -ErrorAction Stop)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -notlike 'GroupNotFound*') {
                    Write-Warning "Could not read the group roster: $($PSItem.Exception.Message)"
                    # A9: the same defect class as the unread sections -- the roster is written as []
                    # either way. It is read-only context, so it is named here, not in Get-OERInventory.
                    $IncompleteReads.Add('groupsRoster')
                }
            }
            $Roster = @(foreach ($Rg in $RosterGroups) {
                $RgId = [string]$Rg.Id
                $RgName = [string]$Rg.DisplayName
                # A roster group with no entry was not read in full: $null, not 0 (R3, above).
                $MemberCount = if ($CountById.ContainsKey($RgId)) { $CountById[$RgId] } else { $null }
                [PSCustomObject]@{
                    displayName      = $RgName
                    roleAssignable   = [bool]$Rg.IsAssignableToRole
                    dynamic          = ($Rg.GroupType -eq 'Dynamic')
                    onPremisesSynced = (Test-OERGroupOnPremisesSynced -Group $Rg)
                    memberCount      = $MemberCount
                }
            })
        }

        # --- Reassemble the canonical inventory object with the (possibly filtered) groups ---
        # The two directory-role sections are filtered with Where-Object { $null -ne $_ } rather than
        # a bare @(...) wrap: @($null) is a ONE-element array holding a null, not an empty one, and a
        # caller whose Get-OERInventory result omits these properties entirely (a $null property
        # read) would otherwise hand ConvertTo-OERInventory a single null entry -- which then fails
        # apply-schema validation ("'role' is required at directoryRoleManagementPolicies[0]")
        # instead of writing a genuinely empty section, same footgun $AllGroups above guards against.
        $Canonical = ConvertTo-OERInventory `
            -TenantId $DocumentTenantId `
            -Groups $DetailedGroups `
            -AdministrativeUnits @($Inv.AdministrativeUnits) `
            -Catalogs @($Inv.Catalogs) `
            -AccessPackages @($Inv.AccessPackages) `
            -AccessReviews @($Inv.AccessReviews) `
            -DirectoryRoleManagementPolicies @($Inv.DirectoryRoleManagementPolicies | Where-Object { $null -ne $_ }) `
            -DirectoryRoleAssignments @($Inv.DirectoryRoleAssignments | Where-Object { $null -ne $_ }) `
            -RoleAssignments $RoleAssignments.ToArray() `
            -RoleManagementPolicies $RoleManagementPolicies.ToArray()

        # --- Create the bundle folder ---
        $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $TenantLabel = if ($script:_OERAuthState -and $script:_OERAuthState.TenantId) { $script:_OERAuthState.TenantId } elseif ($TenantId) { $TenantId } else { 'tenant' }
        $FolderName = "oer-inventory-$TenantLabel-$Stamp"
        $BundlePath = Join-Path $OutputPath $FolderName

        # The bundle write is the only disk mutation in this cmdlet; the tenant read above is
        # side-effect free, so -WhatIf still produces a complete, accurate plan of what would be written.
        $ShouldWrite = $PSCmdlet.ShouldProcess($BundlePath, "Write inventory bundle ($($Include -join ', '))")

        if ((Test-Path $BundlePath) -and $Force -and $ShouldWrite) {
            Remove-Item $BundlePath -Recurse -Force
        }
        if ($ShouldWrite) {
            $null = New-Item -ItemType Directory -Path $BundlePath -Force
        }

        # --- Write the files ---
        $WrittenFiles = [System.Collections.Generic.List[string]]::new()
        function Write-OERBundleJson {
            param([string]$Name, [object]$Data)
            if ($ShouldWrite) {
                $Path = Join-Path $BundlePath $Name
                # -InputObject, NOT a pipe: PowerShell unrolls a piped collection into its elements,
                # so an EMPTY array piped into ConvertTo-Json sends zero objects down the pipeline --
                # ConvertTo-Json then emits nothing at all, Set-Content receives no input and silently
                # never creates the file, even though $WrittenFiles (below) still names it. -InputObject
                # passes the array as a single argument instead, so an empty $Data correctly serializes
                # to the literal "[]" and the file this cmdlet's help promises is actually written.
                (ConvertTo-Json -InputObject $Data -Depth 12) | Set-Content -Path $Path -Encoding utf8
            }
            # Recorded either way: under -WhatIf the Files list IS the plan.
            $WrittenFiles.Add($Name)
        }

        Write-OERBundleJson -Name 'inventory.json'              -Data $Canonical
        Write-OERBundleJson -Name 'groups.json'                 -Data @($Canonical.Groups)
        Write-OERBundleJson -Name 'administrativeUnits.json'    -Data @($Canonical.AdministrativeUnits)
        Write-OERBundleJson -Name 'catalogs.json'               -Data @($Canonical.Catalogs)
        Write-OERBundleJson -Name 'accessPackages.json'         -Data @($Canonical.AccessPackages)
        Write-OERBundleJson -Name 'accessReviews.json'          -Data @($Canonical.AccessReviews)
        Write-OERBundleJson -Name 'directoryRoleManagementPolicies.json' -Data @($Canonical.DirectoryRoleManagementPolicies)
        Write-OERBundleJson -Name 'directoryRoleAssignments.json'        -Data @($Canonical.DirectoryRoleAssignments)
        Write-OERBundleJson -Name 'roleAssignments.json'        -Data @($Canonical.RoleAssignments)
        Write-OERBundleJson -Name 'roleManagementPolicies.json' -Data @($Canonical.RoleManagementPolicies)
        Write-OERBundleJson -Name 'groupsRoster.json'           -Data $Roster
        Write-OERBundleJson -Name 'scopeHierarchy.json'         -Data $ScopeHierarchy
        if ($AzureSections.Count -gt 0) {
            Write-OERBundleJson -Name 'azurePimEligibility.json' -Data @($AzureEligibilities)
        }

        # --- Formal JSON Schema (so a consumer without the module can validate a proposal) ---
        if ($ShouldWrite) {
            (Get-OERStructureSchemaJson) | Set-Content -Path (Join-Path $BundlePath 'schema.json') -Encoding utf8
        }
        $WrittenFiles.Add('schema.json')

        # --- Prompt + README ---
        if ($ShouldWrite) {
            (Get-OERInventoryPromptTemplate -NamingConvention $NamingConvention) |
                Set-Content -Path (Join-Path $BundlePath 'rbac-architect-prompt.md') -Encoding utf8
        }
        $WrittenFiles.Add('rbac-architect-prompt.md')
        if ($ShouldWrite) {
            # All three lists are complete by now (the roster read above was the last to add an
            # IncompleteReads entry), and they go into the README alone: inventory.json is the apply
            # document and must stay exactly the shape the schema describes. The parameters are
            # mandatory, so a README that claims a complete read cannot be written by forgetting one.
            # The role policy selection's entries follow the Entra ID entries, as in the output object.
            (Get-OERInventoryReadme -IncompleteReads (@($IncompleteReads) + @($RolePolicySelectionReads)) -SkippedScopes @($SkippedScopes) -SkippedEligibilityScopes @($SkippedEligibilityScopes)) |
                Set-Content -Path (Join-Path $BundlePath 'README.md') -Encoding utf8
        }
        $WrittenFiles.Add('README.md')

        # --- Self-check: prove inventory.json round-trips through the apply schema ---
        try {
            $Validation = Test-OERStructureSchema -Document $Canonical
            if (-not $Validation.Valid) {
                Write-Warning "inventory.json did not pass apply-schema validation (run Test-OERStructure on it). First issue: $(@($Validation.Errors)[0].Message)"
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            # The self-check is the only thing that proves inventory.json can be fed back through
            # the apply engine, so its failure has to be visible: a silent catch made an unvalidated
            # bundle indistinguishable from a validated one.
            Write-Warning "Could not run the apply-schema self-check on inventory.json: $($PSItem.Exception.Message)"
        }

        $Out = [PSCustomObject]@{
            # Under -WhatIf the directory was never created, so Resolve-Path would fail; report the
            # planned absolute path instead so the plan names the exact location. $BundlePath can
            # already be rooted (e.g. an absolute -OutputPath), and Join-Path (unlike
            # [IO.Path]::Combine) does not special-case a rooted child, so that case is resolved
            # directly rather than joined onto the current directory.
            BundlePath             = if ($ShouldWrite) {
                (Resolve-Path $BundlePath).Path
            } elseif ([System.IO.Path]::IsPathRooted($BundlePath)) {
                [System.IO.Path]::GetFullPath($BundlePath)
            } else {
                [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $BundlePath))
            }
            TenantId               = $TenantLabel
            Generated              = $Stamp
            Groups                 = @($Canonical.Groups).Count
            AdministrativeUnits    = @($Canonical.AdministrativeUnits).Count
            Catalogs               = @($Canonical.Catalogs).Count
            AccessPackages         = @($Canonical.AccessPackages).Count
            AccessReviews          = @($Canonical.AccessReviews).Count
            DirectoryRoleManagementPolicies = @($Canonical.DirectoryRoleManagementPolicies).Count
            DirectoryRoleAssignments        = @($Canonical.DirectoryRoleAssignments).Count
            RoleAssignments        = @($Canonical.RoleAssignments).Count
            RoleManagementPolicies = @($Canonical.RoleManagementPolicies).Count
            RosterCount            = @($Roster).Count
            ScopeCount             = $ScopeCount
            ScopesEnumerated       = $ScopesEnumerated
            SkippedScopes          = @($SkippedScopes)
            AzurePimEligibility    = @($AzureEligibilities).Count
            SkippedEligibilityScopes = @($SkippedEligibilityScopes)
            # The Entra ID entries first, in their documented order, then the scopes where role
            # management policies that could not be judged were kept (BL-107).
            IncompleteReads        = @($IncompleteReads) + @($RolePolicySelectionReads)
            Files                  = $WrittenFiles.ToArray()
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryBundle')
        $Out

        # Emitted AFTER the summary so a caller still receives the bundle object it has to inspect,
        # then learns the coverage is incomplete. A warning alone left $? true, -ErrorAction Stop
        # inert and a try/catch seeing success, which is how a heavily truncated bundle reached the
        # LLM -> Invoke-OERStructure workflow looking exactly like a full tenant snapshot.
        if ($SkippedScopes.Count -gt 0 -or $SkippedEligibilityScopes.Count -gt 0 -or $IncompleteReads.Count -gt 0 -or $RolePolicySelectionReads.Count -gt 0) {
            $PartialParts = [System.Collections.Generic.List[string]]::new()
            # A '<...>' entry is not a scope that failed to READ: it names the whole walk that could not
            # start, or a level of the tree (management groups, subscriptions) that could not be LISTED,
            # so none of its scopes was enumerated. Counting it as "N of M scopes" would misstate which
            # scopes were read.
            $WalkFailed = (@($SkippedScopes) + @($SkippedEligibilityScopes)) -contains '<all Azure scopes: scope enumeration failed>'
            $DescribeSkip = {
                param([string[]]$Skipped, [string]$What)
                $Read = @($Skipped | Where-Object { -not ([string]$_).StartsWith('<') })
                $Levels = @($Skipped | Where-Object { ([string]$_).StartsWith('<') })
                $Parts = @()
                if ($Read.Count -gt 0) { $Parts += "$($Read.Count) of $ScopesEnumerated Azure scopes could not be read$What" }
                if ($Levels.Count -gt 0) { $Parts += "$($Levels.Count) level(s) of the Azure scope tree could not be listed, so none of their scopes was walked$What" }
                $Parts -join ', and '
            }
            if ($SkippedScopes.Count -gt 0) {
                # The "missing data is absent from ... Skipped: ..." clause is appended to BOTH
                # arms, not folded into the enumerated one. A failed scope WALK is exactly the case
                # where the operator most needs to be told which files are short and what was
                # skipped; burying that inside the $ScopesEnumerated -gt 0 arm silently drops it
                # from the louder of the two failures.
                $ScopeDetail = if (-not $WalkFailed) {
                    & $DescribeSkip @($SkippedScopes) ''
                } else {
                    'the Azure scope walk could not be started, so no Azure scope was read'
                }
                $PartialParts.Add(
                    "$ScopeDetail, and the missing data is absent from roleAssignments.json and " +
                    "roleManagementPolicies.json. Skipped: $($SkippedScopes -join ', ')")
            }
            if ($SkippedEligibilityScopes.Count -gt 0) {
                # A separate clause, not folded into the roleAssignments/roleManagementPolicies one
                # above: the eligibility read (R4) runs as its own pass over the same scope list, so a
                # scope can fail here without having failed the role-assignment walk, or vice versa,
                # and the operator needs to know which FILE is short. Same two-arm split as the
                # roleAssignments/roleManagementPolicies clause above, for the same reason: a failed
                # scope WALK (no tree at all) reads differently from N of M individual scopes failing
                # the eligibility read specifically.
                $EligDetail = if (-not $WalkFailed) {
                    & $DescribeSkip @($SkippedEligibilityScopes) ' for azurePimEligibility.json'
                } else {
                    'the Azure scope walk could not be started, so no scope was read for azurePimEligibility.json'
                }
                $PartialParts.Add(
                    "$EligDetail, and their eligible assignments are absent from it. " +
                    "Skipped: $($SkippedEligibilityScopes -join ', ')")
            }
            if ($IncompleteReads.Count -gt 0) {
                # The count is of ENTRIES, not collections: one Get-OERInventory run raises one
                # InventoryPartial error naming every triple it lost, and the Groups read is one
                # entry naming every group collection it lost, so a single entry here can stand for
                # seven unread collections; the groupsRoster entry is this cmdlet's own and not a
                # Get-OERInventory report at all. Saying "N collection read(s) failed" made
                # this message disagree with the seven triples printed right after it, and with
                # Get-OERInventory's own "7 collection(s)" on the same run. The help already states
                # the entry-per-report rule; the message now agrees with it.
                $IncompletePart = "$($IncompleteReads.Count) partial Entra ID read entry(ies) name collections or objects that could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are NOT stated as facts in the bundle -- one entry can name several collections, so read the entries rather than this count: $($IncompleteReads -join '; '). A members, scopedRoles, resources or resourceRoles key reported here is an explicit null, which the apply engine reads as leave untouched. A section named alone is written as an empty array, which does not mean the tenant has none, and the entry groupsRoster means groupsRoster.json is empty since the group roster could not be read"
                # WHY the group collections are missing. The group reader writes no error record, so
                # this message is the only error that carries its causes (the verbose stream shows
                # each as it is seen, and Get-OERInventory's own partial message carries the causes of
                # the other sections): the cause is what tells a 429 (retry the export) from a 403
                # (grant a scope). Format-OERUnreadCauseClause owns the wording,
                # the deduplication and the cap, and returns an empty string when there is none. Its
                # clause ends with a period, which is trimmed here because the parts are joined with
                # one below.
                if ($GroupRead) {
                    $GroupCauseClause = Format-OERUnreadCauseClause -Cause @($GroupRead.Causes) -Label 'Causes of the unread group reads'
                    if ($GroupCauseClause) { $IncompletePart += '.' + $GroupCauseClause.TrimEnd('.') }
                }
                $PartialParts.Add($IncompletePart)
            }
            if ($RolePolicySelectionReads.Count -gt 0) {
                # A clause of its own (BL-107), not folded into the Entra ID one above, whose count and
                # wording stay over the Entra ID entries only: these are Azure scopes, and no policy that
                # could not be judged was left out for them -- more was kept than the selection would
                # keep. It does not claim every policy at such a scope was kept: a scope is named also
                # when only one row could not be judged, and the other unused, unchanged policies there
                # are still left out.
                $PartialParts.Add(
                    "at $($RolePolicySelectionReads.Count) Azure scope(s) every role management policy that could not be judged was kept, none of them left out, " +
                    'since whether its role is used there, or whether it was changed, could not be read -- where a scope''s role assignment or ' +
                    'eligibility read failed, that is every policy of a role neither used nor changed there -- so ' +
                    'roleManagementPolicies.json may hold policies of roles that are neither used nor changed at those scopes: ' +
                    ($RolePolicySelectionReads -join '; '))
            }
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "This inventory bundle is PARTIAL: $($PartialParts -join '. '). " +
                    'Do not treat it as a full tenant snapshot.')) `
                -ErrorId 'InventoryPartial' `
                -Category LimitsExceeded `
                -TargetObject $Out.BundlePath `
                -Cmdlet $PSCmdlet
        }
    }
}
