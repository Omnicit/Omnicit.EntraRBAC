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
    RBAC-relevant groups (role-assignable, carrying a pimPolicy block, or with eligibility) are kept
    in full detail in inventory.json. Microsoft Graph lists PIM-for-groups policies for a group that
    was never used with PIM for Groups as well, so Get-OERInventory exports a pimPolicy block only
    for a group that uses PIM for Groups -- one with PIM eligibility, or one whose PIM-for-Groups
    policy has been modified -- and a group whose policies Graph merely lists is not kept in full
    detail on that account. -IncludeSyncedGroups also keeps the security groups synchronized from
    on-premises Active Directory. -AllGroupsDetailed keeps every group inventory.json covers. The
    cmdlet reads only -- no tenant state changes -- and authenticates at entry; an ARM token is
    acquired only when -Include names RoleAssignments or RoleManagementPolicies, the two Azure
    sections.

    WHICH GROUPS INVENTORY.JSON COVERS, AND WHICH IT DOES NOT. The Groups section is read with the
    'securityEnabled eq true' filter Get-OERInventory applies by default, so it carries the
    SECURITY-ENABLED groups only -- a distribution group, and a Microsoft 365 group whose
    securityEnabled is false, are absent from it at every detail level, -AllGroupsDetailed
    included. That scope is deliberate: inventory.json is the apply-engine document, and widening
    it widens what Invoke-OERStructure reconciles and, under -Prune, deletes. To widen it anyway,
    read the inventory yourself with Get-OERInventory -GroupFilter and supply the filter you want.
    groupsRoster.json is NOT filtered: it lists every group in the tenant, of every type, as
    read-only context, so the gap between the two files is visible rather than silent. Each of its
    rows carries onPremisesSynced, true for a group synchronized from on-premises Active Directory
    and false otherwise.

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

    Entra ID coverage is reported the same way. IncompleteReads carries, first, one entry for the
    Groups read when it left anything unread, then one entry per partial report from
    Get-OERInventory, which reads the other Entra ID sections. Each entry names the affected
    section/displayName/key triples -- so a single read that lost three collections reports one
    entry listing all three, not three entries -- and the entry groupsRoster is added when the group
    roster could not be read. A section whose whole list could not be read appears in those entries
    by its own name alone, and is written as an empty array that does not mean the tenant has none;
    the entry groupsRoster likewise means groupsRoster.json is empty only because the roster read
    failed. Its Count is therefore one for the Groups read when it left anything unread, plus the
    number of partial reports from Get-OERInventory, plus one when the group roster could not be
    read, and not the number of unread collections; read the entries themselves for that. The same
    non-terminating InventoryPartial error is raised here when IncompleteReads, SkippedScopes or
    SkippedEligibilityScopes is non-empty, and its message gives the causes of the unread group
    reads (Get-OERInventory's own InventoryPartial gives those of the other sections). A members,
    scopedRoles, resources or resourceRoles collection that could not be read, or that has an entry
    the export could name by nothing the apply engine accepts, is NOT written into inventory.json as
    an empty one or with an empty name: its key is an explicit null, which the apply engine reads as
    "leave untouched". Do not hand-edit that null to [] -- under Invoke-OERStructure -Prune an
    empty declared collection deletes every live member, binding or resource. Any other collection
    IncompleteReads names is left out of the document or written only as far as it was read, as the
    Get-OERInventory help describes; Invoke-OERStructure never removes a catalog, access package or
    assignment policy that is absent from the document.

    The bundle says so itself. The generated README.md carries a section named "What this export
    could not read": one bullet per IncompleteReads, SkippedScopes and SkippedEligibilityScopes
    entry, or the statement that nothing was left unread, so whoever receives the bundle (an LLM,
    say) can tell a collection that was not read from one that is empty. The lists go into README.md
    only, never into inventory.json or any other file that is validated or applied.

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
    and never acquire an ARM token by themselves.

    .PARAMETER AllGroupsDetailed
    Keep every group the Groups section covers in full detail in inventory.json, not just the
    RBAC-relevant ones. That section is security-enabled-scoped, so this switch does not reach a
    distribution group or a Microsoft 365 group whose securityEnabled is false -- neither is in
    inventory.json at any detail level. Use Get-OERInventory -GroupFilter to widen the scope
    itself; groupsRoster.json already lists every group in the tenant unfiltered.

    .PARAMETER IncludeSyncedGroups
    Also keep, in full detail in inventory.json, every security group synchronized from on-premises
    Active Directory (onPremisesSynced: true). Such a group is never RBAC-relevant by the default
    criteria -- it cannot be role-assignable or managed in PIM for Groups -- so without this switch
    it appears only in groupsRoster.json. It is managed on-premises: Invoke-OERStructure writes
    nothing to it, and its onPremisesSynced key is information only. With -AllGroupsDetailed every
    group is kept already and this switch changes nothing.

    .PARAMETER AllDirectoryRolePolicies
    For the DirectoryRoleManagementPolicies section, export the policy of every Microsoft Entra
    directory role, instead of only the roles that have at least one row in the tenant-scope
    eligibility or assignment schedules (the default). Forwarded to the internal Get-OERInventory
    call; has no effect unless -Include names DirectoryRoleManagementPolicies.

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
    many were left out. The expression is yours: it is sent as typed and never escaped, so double a
    single quote inside a quoted value yourself ('O''Brien'). groupsRoster.json is not filtered by
    it and still lists every group in the tenant. An empty or white space value is refused at
    binding.

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
    Reads the full posture (including tenant-wide Azure role assignments and PIM policies) into a
    bundle under C:\Temp\oer-inventory-<tenant>-<stamp>\, not into C:\Temp itself.

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
        # and Causes lists, folded into IncompleteReads and the partial message below.
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
            }
            if (-not $AllGroupsDetailed) {
                $GroupReadParams.RelevantOnly = $true
                if ($IncludeSyncedGroups) { $GroupReadParams.IncludeSyncedGroups = $true }
            }
            $GroupRead = Get-OERInventoryGroup @GroupReadParams
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
                        try {
                            $ScopeParams = @{ Include = $AzureSections; Scope = $S }
                            if ($AzureSections -contains 'RoleManagementPolicies') { $ScopeParams.AllRolesAtScope = $true }
                            # -ErrorAction Stop is load-bearing: without it a NON-terminating failure
                            # inside Get-OERInventory never reaches this catch under the default
                            # preference, so the scope contributed nothing and did not even warn.
                            $ScopeInv = Get-OERInventory @ScopeParams -ErrorAction Stop
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            Write-Warning "Skipping scope '$S': $($PSItem.Exception.Message)"
                            $SkippedScopes.Add([string]$S)
                            continue
                        }
                        foreach ($Ra in @($ScopeInv.RoleAssignments)) {
                            $Key = if ($Ra.PSObject.Properties.Name -contains 'id' -and $Ra.id) { [string]$Ra.id } else { '{0}|{1}|{2}' -f $Ra.scope, $Ra.role, $Ra.principal }
                            if ($SeenRa.Add($Key)) { $RoleAssignments.Add($Ra) }
                        }
                        foreach ($Rmp in @($ScopeInv.RoleManagementPolicies)) {
                            $Key = '{0}|{1}' -f $Rmp.scope, $Rmp.role
                            if ($SeenRmp.Add($Key)) { $RoleManagementPolicies.Add($Rmp) }
                        }
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
            (Get-OERInventoryReadme -IncompleteReads @($IncompleteReads) -SkippedScopes @($SkippedScopes) -SkippedEligibilityScopes @($SkippedEligibilityScopes)) |
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
            IncompleteReads        = @($IncompleteReads)
            Files                  = $WrittenFiles.ToArray()
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryBundle')
        $Out

        # Emitted AFTER the summary so a caller still receives the bundle object it has to inspect,
        # then learns the coverage is incomplete. A warning alone left $? true, -ErrorAction Stop
        # inert and a try/catch seeing success, which is how a heavily truncated bundle reached the
        # LLM -> Invoke-OERStructure workflow looking exactly like a full tenant snapshot.
        if ($SkippedScopes.Count -gt 0 -or $SkippedEligibilityScopes.Count -gt 0 -or $IncompleteReads.Count -gt 0) {
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
