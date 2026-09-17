function Export-OERInventory {
    <#
    .SYNOPSIS
    Reads a tenant's RBAC posture and writes a self-contained bundle (JSON + LLM prompt + README).

    .DESCRIPTION
    Composes the existing Get-OER* read cmdlets into a timestamped bundle folder containing the
    canonical round-trippable inventory.json, per-area JSON files, read-only context
    (scopeHierarchy.json, groupsRoster.json), a formal JSON Schema (schema.json), a predefined LLM
    prompt (rbac-architect-prompt.md), and a README. The bundle is designed to be handed to any LLM to produce appliable RBAC
    proposals. Only RBAC-relevant groups (role-assignable, PIM-onboarded, or with eligibility) are
    kept in full detail in inventory.json; -AllGroupsDetailed keeps every group inventory.json
    covers. The cmdlet reads only -- no tenant state changes -- and authenticates at entry; an ARM
    token is acquired only when -Include names RoleAssignments or RoleManagementPolicies, the two
    Azure sections.

    WHICH GROUPS INVENTORY.JSON COVERS, AND WHICH IT DOES NOT. The Groups section is read with the
    'securityEnabled eq true' filter Get-OERInventory applies by default, so it carries the
    SECURITY-ENABLED groups only -- a distribution group, and a Microsoft 365 group whose
    securityEnabled is false, are absent from it at every detail level, -AllGroupsDetailed
    included. That scope is deliberate: inventory.json is the apply-engine document, and widening
    it widens what Invoke-OERStructure reconciles and, under -Prune, deletes. To widen it anyway,
    read the inventory yourself with Get-OERInventory -GroupFilter and supply the filter you want.
    groupsRoster.json is NOT filtered: it lists every group in the tenant, of every type, as
    read-only context, so the gap between the two files is visible rather than silent.

    Azure coverage is reported, not assumed. ScopesEnumerated is how many ARM scopes the walk found,
    ScopeCount is how many of them were actually read, and SkippedScopes names the ones that were
    not. When anything was skipped the bundle summary is still emitted first and is then followed by
    a non-terminating InventoryPartial error, so a caller using -ErrorAction Stop or a try/catch
    finds out that roleAssignments.json and roleManagementPolicies.json are incomplete instead of
    treating a truncated bundle as a full tenant snapshot.
    Entra ID coverage is reported the same way. IncompleteReads carries one entry per partial
    report from Get-OERInventory, each naming the affected section/displayName/key triples -- so a
    single run that lost three collections reports one entry listing all three, not three entries.
    Its Count is therefore the number of partial reports, not the number of unread collections; read
    the entries themselves for that. The same non-terminating InventoryPartial error is raised here when
    IncompleteReads or SkippedScopes is non-empty. Such a collection is NOT written into
    inventory.json as an empty one: a members or scopedRoles key it names is an explicit null, which
    the apply engine reads as "leave untouched". Do not hand-edit that null to [] -- under
    Invoke-OERStructure -Prune an empty declared collection deletes every live member.

    WHERE THE FILES LAND: nothing is ever written directly into -OutputPath. -OutputPath is only the
    PARENT directory; every file goes into a new timestamped subfolder beneath it named
    oer-inventory-<tenantId>-<yyyyMMdd-HHmmss>, so inventory.json is at
    <OutputPath>/oer-inventory-<tenantId>-<stamp>/inventory.json and NOT at <OutputPath>/inventory.json.
    Because the stamp is generated per run, the only reliable way to address the bundle afterwards is
    the BundlePath property of the returned Omnicit.EntraRBAC.InventoryBundle object -- an absolute
    path, populated under -WhatIf too (as the planned location). Capture the returned object and join
    onto its BundlePath rather than guessing the folder name; see the Test-OERStructure example below.

    The full export to LLM to Test-OERStructure to Invoke-OERStructure walkthrough is documented in
    the repository at docs/inventory-to-llm/README.md, and a worked apply document is kept in the
    repository at docs/examples/example-structure.json. Neither ships inside the installed module,
    so clone or browse the repository to read them.

    .PARAMETER OutputPath
    The PARENT directory under which the timestamped bundle folder is created; the bundle files are
    written into that subfolder, never directly into this directory. Defaults to the current
    directory. Use the returned object's BundlePath to address the files afterwards.

    .PARAMETER Include
    Which sections to gather from the tenant. Defaults to the Entra sections plus RoleAssignments.

    .PARAMETER AllGroupsDetailed
    Keep every group the Groups section covers in full detail in inventory.json, not just the
    RBAC-relevant ones. That section is security-enabled-scoped, so this switch does not reach a
    distribution group or a Microsoft 365 group whose securityEnabled is false -- neither is in
    inventory.json at any detail level. Use Get-OERInventory -GroupFilter to widen the scope
    itself; groupsRoster.json already lists every group in the tenant unfiltered.

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

    .EXAMPLE
    Export-OERInventory
    Reads the tenant and writes a bundle under the current directory.

    .EXAMPLE
    Export-OERInventory -OutputPath C:\Temp -Include Groups,AdministrativeUnits,Catalogs,AccessPackages,RoleAssignments,RoleManagementPolicies
    Reads the full posture (including tenant-wide Azure role assignments and PIM policies) into a
    bundle under C:\Temp\oer-inventory-<tenantId>-<stamp>\, not into C:\Temp itself.

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
        [ValidateSet('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'RoleAssignments', 'RoleManagementPolicies')]
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'RoleAssignments'),
        [switch]$AllGroupsDetailed,
        [string]$ManagementGroup,
        [string]$Scope,
        [switch]$Force,
        [string]$TenantId
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
    }
    process {
        # --- Gather the Entra ID sections (names only, for portability) ---
        $EntraSections = @($Include | Where-Object { $_ -in @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews') })
        # -IncludeId is threaded through PURELY to key the roster member-count join on object id
        # instead of display name below (Entra permits duplicate group display names --
        # Add-OERGroupMember.ps1:43-45 -- so a display-name join can attribute one group's member
        # count to a different, same-named group). inventory.json staying id-free is a documented
        # portability property of the export (Get-OERInventory's own .DESCRIPTION), so every id
        # -IncludeId stamps is stripped back out below, before the canonical inventory and the
        # per-area files are assembled and written.
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
            Get-OERInventory -Include $EntraSections -IncludeId -ErrorAction Continue -ErrorVariable InventoryReadErrors
        } else {
            ConvertTo-OERInventory
        }
        $IncompleteReads = [System.Collections.Generic.List[string]]::new()
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

        if ($AzureSections.Count -gt 0) {
            $TreeParams = @{}
            if ($ManagementGroup) { $TreeParams.ManagementGroup = $ManagementGroup }
            if ($Scope) { $TreeParams.Scope = $Scope }
            $Tree = $null
            try {
                $Tree = Resolve-OERInventoryScopeTree @TreeParams
                $ScopeHierarchy = $Tree.Hierarchy
                $ScopesEnumerated = @($Tree.Scopes).Count
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not enumerate Azure scopes: $($PSItem.Exception.Message)"
                $Tree = $null
                # Record the whole Azure walk as skipped so the partial-coverage error below fires.
                # Without this the bundle is written with ZERO role assignments and zero policies and
                # nothing but a warning says so, which leaves $? true and -ErrorAction Stop inert.
                $SkippedScopes.Add('<all Azure scopes: scope enumeration failed>')
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
            }
        }

        # --- Group split: RBAC-relevant kept in inventory.json; unfiltered roster written separately ---
        # The whole if/else is wrapped in @(...) because an empty 'else' result (no RBAC-relevant
        # groups) assigned straight from an if-statement collapses to $null, and a later @($null)
        # would inject a single null group that fails apply-schema validation. The null-item guard
        # keeps a stray null out of the filtered set.
        $AllGroups = @($Inv.Groups | Where-Object { $null -ne $_ })
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
                    ($_.PSObject.Properties.Name -contains 'pimPolicy')
                }
            }
        )

        # Member-count map keyed on object id (from the -IncludeId-stamped projection gathered
        # above), with a display-name map kept only as a fallback for a roster group the detailed
        # projection did not include -- zero extra calls either way. id is the correct join key:
        # Entra permits duplicate group display names (Add-OERGroupMember.ps1:43-45), so a
        # display-name-only join silently attributes one same-named group's member count to another.
        $CountById = @{}
        $CountByName = @{}
        foreach ($G in $AllGroups) {
            # members is null when the live read failed (issue #76). @($null).Count is 1, so a bare
            # count would report a group whose membership is UNKNOWN as having exactly one member.
            # $null is the roster's existing "not known" value and is what an unread membership gets.
            $MemberCount = if ($null -ne $G.members) { @($G.members).Count } else { $null }
            if ($G.PSObject.Properties.Name -contains 'id' -and $G.id) {
                $CountById[[string]$G.id] = $MemberCount
            }
            $CountByName[[string]$G.displayName] = $MemberCount
        }

        # inventory.json staying id-free is a documented portability property of the export
        # (Get-OERInventory's own .DESCRIPTION) -- -IncludeId above exists purely to key the join,
        # so every id it stamped is removed again here, before anything below reads from $Inv or
        # the canonical inventory is assembled. -IncludeId stamps more than the top-level id: a
        # Groups eligibility entry gets one too (Get-OERInventory.ps1's $EligProj.id), so the strip
        # reaches that nested collection as well.
        $StampedSections = @(
            $Inv.Groups, $Inv.AdministrativeUnits, $Inv.Catalogs,
            $Inv.AccessPackages, $Inv.AccessReviews
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
                }
            }
            $Roster = @(foreach ($Rg in $RosterGroups) {
                $RgId = [string]$Rg.Id
                $RgName = [string]$Rg.DisplayName
                $MemberCount = if ($CountById.ContainsKey($RgId)) {
                    $CountById[$RgId]
                } elseif ($CountByName.ContainsKey($RgName)) {
                    $CountByName[$RgName]
                } else {
                    $null
                }
                [PSCustomObject]@{
                    displayName    = $RgName
                    roleAssignable = [bool]$Rg.IsAssignableToRole
                    dynamic        = ($Rg.GroupType -eq 'Dynamic')
                    memberCount    = $MemberCount
                }
            })
        }

        # --- Reassemble the canonical inventory object with the (possibly filtered) groups ---
        $Canonical = ConvertTo-OERInventory `
            -Groups $DetailedGroups `
            -AdministrativeUnits @($Inv.AdministrativeUnits) `
            -Catalogs @($Inv.Catalogs) `
            -AccessPackages @($Inv.AccessPackages) `
            -AccessReviews @($Inv.AccessReviews) `
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
                ($Data | ConvertTo-Json -Depth 12) | Set-Content -Path $Path -Encoding utf8
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
        Write-OERBundleJson -Name 'roleAssignments.json'        -Data @($Canonical.RoleAssignments)
        Write-OERBundleJson -Name 'roleManagementPolicies.json' -Data @($Canonical.RoleManagementPolicies)
        Write-OERBundleJson -Name 'groupsRoster.json'           -Data $Roster
        Write-OERBundleJson -Name 'scopeHierarchy.json'         -Data $ScopeHierarchy

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
            (Get-OERInventoryReadme) | Set-Content -Path (Join-Path $BundlePath 'README.md') -Encoding utf8
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
            RoleAssignments        = @($Canonical.RoleAssignments).Count
            RoleManagementPolicies = @($Canonical.RoleManagementPolicies).Count
            RosterCount            = @($Roster).Count
            ScopeCount             = $ScopeCount
            ScopesEnumerated       = $ScopesEnumerated
            SkippedScopes          = @($SkippedScopes)
            IncompleteReads        = @($IncompleteReads)
            Files                  = $WrittenFiles.ToArray()
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryBundle')
        $Out

        # Emitted AFTER the summary so a caller still receives the bundle object it has to inspect,
        # then learns the coverage is incomplete. A warning alone left $? true, -ErrorAction Stop
        # inert and a try/catch seeing success, which is how a heavily truncated bundle reached the
        # LLM -> Invoke-OERStructure workflow looking exactly like a full tenant snapshot.
        if ($SkippedScopes.Count -gt 0 -or $IncompleteReads.Count -gt 0) {
            $PartialParts = [System.Collections.Generic.List[string]]::new()
            if ($SkippedScopes.Count -gt 0) {
                # The "missing data is absent from ... Skipped: ..." clause is appended to BOTH
                # arms, not folded into the enumerated one. A failed scope WALK is exactly the case
                # where the operator most needs to be told which files are short and what was
                # skipped; burying that inside the $ScopesEnumerated -gt 0 arm silently drops it
                # from the louder of the two failures.
                $ScopeDetail = if ($ScopesEnumerated -gt 0) {
                    "$($SkippedScopes.Count) of $ScopesEnumerated Azure scopes could not be read"
                } else {
                    'the Azure scope walk could not be started, so no Azure scope was read'
                }
                $PartialParts.Add(
                    "$ScopeDetail, and the missing data is absent from roleAssignments.json and " +
                    "roleManagementPolicies.json. Skipped: $($SkippedScopes -join ', ')")
            }
            if ($IncompleteReads.Count -gt 0) {
                # The count is of REPORTS, not collections: one Get-OERInventory run raises one
                # InventoryPartial error naming every triple it lost, so a single entry here can
                # stand for seven unread collections. Saying "N collection read(s) failed" made this
                # message disagree with the seven triples printed right after it, and with
                # Get-OERInventory's own "7 collection(s)" on the same run. The help already states
                # the entry-per-report rule; the message now agrees with it.
                $PartialParts.Add("$($IncompleteReads.Count) partial Entra ID read report(s) name collections that could not be read and are NOT stated as facts in inventory.json -- one report can name several collections, so read the entries rather than this count: $($IncompleteReads -join '; '). A members or scopedRoles key reported here is an explicit null, which the apply engine reads as leave untouched")
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
