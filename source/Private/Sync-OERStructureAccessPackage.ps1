function Sync-OERStructureAccessPackage {
    <#
    .SYNOPSIS
    Reconciles one accessPackages[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single access package entry from the structure document. It is
    called by the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult
    records describing what was created, updated, removed, skipped, or left unchanged.

    displayName is the match key within the declared catalog (names are unique per catalog, not
    tenant-wide): an existing package is matched and updated by it. Renaming through the document
    is not possible: this handler uses displayName purely to match, and never calls
    Set-OERAccessPackage -NewDisplayName -- a changed displayName creates a new package under the
    new name and leaves the old one in place, unreported. There is no top-level Extra reporting for
    access packages either, so the renamed-away package is left in place silently.

    Once the package has been resolved (or created), every downstream call that has to identify it --
    the property re-read, the resourceRoleScopes read, the resource role add and prune, the assignment
    policy read, and the assignment policy create -- passes the resolved access package ID, never the
    display name. Passing the display name would send those calls through Resolve-OERAccessPackageId,
    whose lookup is TENANT-WIDE, discarding the catalog scoping and either acting on an identically
    named package in another catalog or failing with AmbiguousName. Resolve-OERAccessPackageId treats
    a GUID as an id and returns it unchanged, so an id binds through every -AccessPackage parameter;
    since issue #71 that costs one existence read rather than no Graph call at all, which does not
    change the binding, only its price.

    Processing order within a single access package entry:

    1. Create the access package when absent, or diff and update the mutable description and the
       hidden flag when it already exists. The catalog property is creation-only and is never
       changed on an existing package.

    2. Reconcile declared resourceRoles (add missing bindings; emit Extra or prune undeclared
       bindings with -Prune, or report them Skipped while a declared resource cannot be resolved --
       see "Withheld prune" below). Each binding is identified by the resource display name
       (resolved to an OriginId via Get-OERCatalogResource, falling back to Resolve-OERGroupId) and
       the role display name. Existing bindings are read via a raw Graph call against
       resourceRoleScopes.
       NOTE: the $expand shape used for resourceRoleScopes is a live-verify item -- the mock tests
       fix the shape and live testing confirms it.

    3. Reconcile declared assignmentPolicies (UPSERT). When a declared policy's displayName matches
       an existing policy, the handler builds the desired policy parts from the declared entry fields
       (requestor scope, requestor settings, the full per-stage approver set, the approval toggles, the
       expiration, and the notification toggle), assembles a desired body with ConvertTo-OERPolicyBody,
       projects it with ConvertTo-OERAssignmentPolicy, and diffs that desired projection against the
       current policy projection (read via Get-OERAccessPackageAssignmentPolicy) with
       Resolve-OERAssignmentPolicyChange, comparing only the fields the entry actually declares. On a
       difference it calls Set-OERAccessPackageAssignmentPolicy with the declared sub-objects and
       scalars and reports Updated (with the changed field names); no difference reports Unchanged. An
       undeclared requestorScope is never sent on update -- the live scope (including any
       SpecificDirectoryUsers targets) is preserved by Set-OERAccessPackageAssignmentPolicy instead of
       being reset to the AllMemberUsers default. An absent policy is created from the same desired
       parts with New-OERAccessPackageAssignmentPolicy. Explicit per-approver identities ARE now
       diffed: -User/-Group, -Manager/-ManagerLevel,
       -InternalSponsor/-ExternalSponsor, -AlternateUser/-AlternateGroup, -EscalationDays,
       -RequireJustification, and -ApproverInfoVisibility all flow from the declared stage. The
       back-compat approver fallback is retained: ONLY for a stage that declares manager:false/absent
       AND no explicit users/groups/sponsors, the Tenant Profile PrimaryApprovers (primary) and
       EscalationApprovers (alternate) defaults are used. A stage with no manager, no explicit
       approvers, and no PrimaryApprovers default emits Failed for that policy and is skipped. A
       live policy whose displayName is not declared is reported as Extra and is NEVER removed by
       this handler, regardless of -Prune -- use Remove-OERAccessPackageAssignmentPolicy directly.

    When -Prune is set, current resource role bindings whose (role.displayName, scope.originId)
    pair is not declared are removed (with Write-Warning) after a ShouldProcess gate. Without
    -Prune those extras are reported as Extra (informational) and left alone. -Prune is scoped to
    resource role bindings only -- it never removes an undeclared assignment policy (see above).

    Withheld prune: a declared resourceRoles entry is unresolved when its resource name matches no
    resource in the catalog by display name and Resolve-OERGroupId finds no group by that name
    either. Such an entry carries no origin id, so the pass cannot tell which live binding it names,
    and its live counterpart would otherwise look undeclared. While any declared entry is unresolved,
    every undeclared live binding of the package is reported Skipped, with a Detail that starts
    "prune withheld: declared entry '<resource>' could not be resolved" (several unresolved entries:
    "declared entries '<resource1>', '<resource2>' could not be resolved"), with or without -Prune;
    no warning is written, no ShouldProcess prompt is issued, and no binding is removed until the
    entry is fixed or removed from the document (ConvertTo-OERPruneWithheldResult owns the rule and
    the text). The unresolved entry keeps its own Failed record (the record is lost only when the
    handler later throws for the same item, see below). A Resolve-OERGroupId lookup that THROWS, rather than
    finding nothing, is not caught by this handler: it ends the item where it is thrown, neither the
    resource role prune nor the assignment policy step runs, and the engine reports the item as one
    Failed ("handler error") record, discarding every record the handler had already emitted for it
    (a Created package or an added binding stands with no row).

    A failed read of the package's live state -- the resource role bindings, the assignment policies,
    or the declared catalog's resources -- reports Failed with the underlying ErrorRecord and
    reconciles nothing further for that item, so a Created row is never derived from a read that did
    not succeed; an empty read that SUCCEEDED still reconciles normally.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false; the handler
    emits Skipped records instead of calling child cmdlets. When the access package itself does not
    exist and its creation is skipped under -WhatIf, no child read or write calls are made.

    .PARAMETER Item
    One element from the accessPackages[] array in the structure document, as a PSCustomObject
    produced by ConvertFrom-Json.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set, current resource role bindings not in the declared set are removed after a
    ShouldProcess gate. Without this switch, extra bindings are only reported as Extra and never
    deleted. An omitted resourceRoles key still reconciles this way; an explicit
    "resourceRoles": null does not reconcile at all -- null, not an omitted key, is how a package
    is declared without touching its resource role bindings. Scoped to resource role bindings
    only: an undeclared assignment policy is always reported as Extra and is never removed, with
    or without -Prune -- call Remove-OERAccessPackageAssignmentPolicy directly to delete one.
    While a declared resourceRoles entry cannot be resolved (its resource matches no catalog
    resource and no group), no binding is removed or reported Extra: every undeclared live binding
    is reported Skipped with a Detail starting "prune withheld:", with or without this switch. A
    lookup that throws aborts the item instead, before the resource role prune.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded to Resolve-OERStructureDefault so that omitted
    assignmentPolicy approver fields can be resolved from the stored tenant defaults.

    .EXAMPLE
    Sync-OERStructureAccessPackage -Item $DocItem -Caller $PSCmdlet -Prune -TenantAlias 'omnicit'
    Reconciles one access package entry from the document, pruning undeclared resource role
    bindings and resolving approver defaults from the omnicit Tenant Profile.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns', 'Build-OERPolicyParts',
        Justification = 'Build-OERPolicyParts is a private nested helper whose plural noun accurately describes the composite parts object it returns; renaming would obscure intent.'
    )]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias
    )
    process {
        # -- Resolve the display name -------------------------------------------------------
        $Name = $Item.displayName

        # -- Check existence ----------------------------------------------------------------
        # Access package display names are unique per CATALOG, not per tenant, so resolve inside the
        # declared catalog. Get-OERAccessPackage's -DisplayName and -Catalog are mutually exclusive
        # parameter sets, so list by catalog and match the name client-side.
        $ApId = $null
        if (Test-OERDeclaredProperty -Node $Item -Name 'catalog') {
            # A throw here (forced by -ErrorAction Stop) is a transport/permission/throttling failure on
            # the catalog-scoped read itself, or the catalog failing to resolve -- NOT evidence that no
            # package exists. Get-OERAccessPackage -Catalog reports every one of those (catalog not
            # found, ambiguous catalog name, or the underlying Graph list call failing) as its own
            # non-terminating WriteError and simply emits no objects, so without -ErrorAction Stop this
            # read is indistinguishable from a genuine "no match" and would fall through to CREATE a
            # duplicate high-privilege access package. Catch it and stop instead of ever creating.
            $InCatalog = $null
            try {
                $InCatalog = @(Get-OERAccessPackage -Catalog $Item.catalog -ErrorAction Stop |
                        Where-Object { [string]$_.DisplayName -ieq $Name })
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to look up access packages in catalog '$($Item.catalog)': $($PSItem.Exception.Message); the access package was NOT created" `
                    -ErrorRecord $PSItem
                return
            }
            if ($InCatalog.Count -gt 1) {
                $Ids = ($InCatalog | ForEach-Object { [string]$_.Id }) -join ', '
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "catalog '$($Item.catalog)' holds $($InCatalog.Count) access packages named '$Name' ($Ids); the display name cannot identify one"
                return
            }
            if ($InCatalog.Count -eq 1) { $ApId = [string]$InCatalog[0].Id }
        } else {
            # THIS BRANCH IS UNREACHABLE THROUGH Invoke-OERStructure, and that is deliberate.
            # Get-OERStructureSchemaJson declares "required": [ "displayName", "catalog" ] on every
            # accessPackages item, Invoke-OERStructure refuses a document that fails validation, and
            # there is no -SkipValidation escape -- so no document applied through the public entry
            # point can reach a no-catalog accessPackages entry. Confirmed by tracing the schema and
            # the entry point on 2026-09-11.
            # The schema is NOT being relaxed to make it reachable. The catalog is what SCOPES the
            # resolution; without it the lookup is tenant-wide and throws AmbiguousName whenever a
            # display name is reused across catalogs, which is the exact problem the catalog-scoped
            # branch above exists to avoid. Relaxing a schema so a branch becomes testable is
            # backwards.
            # The branch is NOT deleted either: Sync-OERStructureAccessPackage is a private helper
            # the unit suite calls directly, and for that entry point the code below is correct and
            # is exercised. Keep both facts in view before changing either side.
            # A throw here is NOT "no such package": the resolver throws AmbiguousName when the name
            # matches several packages, AccessPackageNotFound when a GUID-shaped displayName does not
            # exist (issue #71), and re-raises any transport/permission/throttling failure of its own
            # lookup. Every one of those must land in the Failed channel, because the ONLY other exit
            # from here is $ApId = $null, which Step 1 reads as "create it" -- and creating on a
            # stale GUID would produce a live access package whose display name is that GUID. A
            # genuine no-match still returns $null and still creates, exactly as before.
            try {
                $ApId = Resolve-OERAccessPackageId -DisplayName $Name
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to resolve access package '$Name': $($PSItem.Exception.Message); the access package was NOT created" `
                    -ErrorRecord $PSItem
                return
            }
        }

        # -- Step 1: Create or update the access package object ----------------------------
        if (-not $ApId) {
            # Access package does not exist -- create it.
            if (-not $Caller.ShouldProcess($Name, 'Create access package')) {
                # Under -WhatIf: emit Skipped for the AP and all declared children, then return.
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would create access package $Name"

                if (Test-OERDeclaredProperty -Node $Item -Name 'resourceRoles') {
                    foreach ($Rr in @($Item.resourceRoles)) {
                        $RrRef = if (Test-OERDeclaredProperty -Node $Rr -Name 'resource') { $Rr.resource } else { '?' }
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would configure resourceRole '$RrRef' after access package is created"
                    }
                }

                if (Test-OERDeclaredProperty -Node $Item -Name 'assignmentPolicies') {
                    foreach ($Pol in @($Item.assignmentPolicies)) {
                        $PolRef = if (Test-OERDeclaredProperty -Node $Pol -Name 'displayName') { $Pol.displayName } else { '?' }
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would configure assignmentPolicy '$PolRef' after access package is created"
                    }
                }
                return
            }

            # Build creation params
            $NewParams = @{ DisplayName = $Name; Catalog = $Item.catalog; Confirm = $false }
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') { $NewParams.Description = $Item.description }
            if ((Test-OERDeclaredProperty -Node $Item -Name 'hidden') -and $Item.hidden -eq $true) { $NewParams.Hidden = $true }

            $Created = $null
            try {
                $Created = New-OERAccessPackage @NewParams -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "access package creation failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                return
            }

            if (-not $Created) {
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail 'New-OERAccessPackage returned no object'
                return
            }

            $ApId = $Created.Id
            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Created' -Detail "created access package $Name ($ApId)"

            # After create: current resourceRoles and policies are empty
            $CurrentBindings = @()
            $CurrentPolicies = @()

        } else {
            # Access package exists -- diff mutable properties (description and the hidden flag;
            # catalog is creation-only and is never changed on an existing package). $ApId is already
            # resolved above (either catalog-scoped or tenant-wide), so read by id directly rather than
            # by -DisplayName, whose ByName parameter set is tenant-wide and would emit every match.
            # A throw here (forced by -ErrorAction Stop) is a transport/permission/throttling failure on
            # the re-read, NOT evidence the properties match -- without it, a failed read silently
            # returns $null and the fall-through below would misreport a false Unchanged (or crash the
            # later Set-OERAccessPackage call on a null -Id) instead of surfacing the failure.
            try {
                $Cur = Get-OERAccessPackage -Id $ApId -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to re-read access package '$Name' ($ApId): $($PSItem.Exception.Message)" `
                    -ErrorRecord $PSItem
                return
            }

            $ApUpdateParams = @{}
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') {
                if ($Cur.Description -ne $Item.description) { $ApUpdateParams.Description = $Item.description }
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'hidden') {
                if ([bool]$Cur.IsHidden -ne [bool]$Item.hidden) { $ApUpdateParams.Hidden = [bool]$Item.hidden }
            }

            if ($ApUpdateParams.Count -gt 0) {
                if ($Caller.ShouldProcess($Name, "Update access package properties ($($ApUpdateParams.Keys -join ', '))")) {
                    try {
                        Set-OERAccessPackage -Id $Cur.Id @ApUpdateParams -Confirm:$false -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Updated' -Detail "updated access package properties ($($ApUpdateParams.Keys -join ', '))"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "access package update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would update access package properties ($($ApUpdateParams.Keys -join ', '))"
                }
            } else {
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Unchanged' -Detail 'access package properties match'
            }

            # Read current resource role bindings for reconciliation.
            # NOTE: the $expand shape (scope,role) is a live-verify item -- the mock tests fix
            # the shape returned and live testing against the real Graph confirms whether
            # role.displayName and scope.originId are populated at this expand depth.
            # A failed read is NOT an empty set of bindings. Substituting @() here made the add loop
            # below re-add every declared binding against a package that already has them -- a
            # duplicate-create attempt reported as Created (issue #60).
            $RrsResponse = $null
            try {
                $RrsResponse = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}/resourceRoleScopes?`$expand=scope,role" -f $ApId) -All
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the current resource role bindings of access package '$Name': $($PSItem.Exception.Message); no resourceRole or assignmentPolicy was created, updated or removed" `
                    -ErrorRecord $PSItem
                return
            }
            $CurrentBindings = if ($RrsResponse.value) { @($RrsResponse.value) } else { @() }

            # Read current assignment policies for reconciliation. Pass the RESOLVED $ApId, never
            # $Name: -AccessPackage funnels a non-GUID value into Resolve-OERAccessPackageId, whose
            # display-name lookup is TENANT-WIDE and throws AmbiguousName when the same name exists
            # in another catalog -- which would discard the catalog scoping the resolution above
            # just established. Resolve-OERAccessPackageId treats a GUID (Test-OERGuid) as an id and
            # returns it unchanged, so an id binds straight through. Since issue #71 that path costs
            # one existence read instead of no Graph call at all; the REASON for passing $ApId is
            # unchanged -- it is the tenant-wide display-name lookup that must be avoided, not the
            # read.
            # -ErrorAction Stop plus a catch, never SilentlyContinue: Get-OERAccessPackageAssignmentPolicy
            # reports a failed read as a non-terminating error and emits nothing, so suppressing it made
            # a 403, a transient 5xx or a resolve failure indistinguishable from "this package genuinely
            # has no policies" -- and Step 3 then took the CREATE branch against policies that already
            # exist (issue #60). An empty read that SUCCEEDED still reconciles normally.
            $CurrentPolicies = @()
            try {
                $CurrentPolicies = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId -ErrorAction Stop)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the current assignment policies of access package '$Name': $($PSItem.Exception.Message); no assignmentPolicy was created or updated" `
                    -ErrorRecord $PSItem
                return
            }
        }

        # -- Step 2: resourceRoles ---------------------------------------------------------
        # Track declared (originId, roleDisplayName) pairs for prune comparison.
        $DeclaredBindingKeys = [System.Collections.Generic.List[string]]::new()
        # Declared resources that could not be resolved to an origin id carry no binding key, so they
        # cannot protect their live bindings; while this list is non-empty the Extra/prune loop below
        # withholds every candidate (ConvertTo-OERPruneWithheldResult owns the rule).
        $ResourceRoleUnresolved = [System.Collections.Generic.List[string]]::new()
        # An omitted 'resourceRoles' key has always meant "no add-list, but the prune/Extra loop
        # below still runs against whatever it finds" -- that is intentional, existing, tested
        # behavior (an absent collection is not an instruction to leave live state alone; only an
        # EXPLICIT null is). So the add loop is gated on Test-OERDeclaredProperty (skips on both
        # absent and null), while the prune/Extra loop below is gated on the narrower
        # $ResourceRolesDeclaredNull so it keeps running when the key is merely absent and only
        # backs off on an explicit null.
        $ResourceRolesDeclaredNull = Test-OERDeclaredNull -Node $Item -Name 'resourceRoles'

        if (Test-OERDeclaredProperty -Node $Item -Name 'resourceRoles') {
            # Read the catalog's resources ONCE for the whole resourceRoles set (not per entry).
            # -ErrorAction Stop plus a catch: a suppressed failure left $CatResources empty, which
            # both sent every declared resource down the Resolve-OERGroupId fallback AND left
            # $DeclaredBindingKeys short -- so the Extra/prune pass below reported every live binding
            # as Extra, or removed them all under -Prune (issue #60).
            # Gated on there being at least one declared entry. "resourceRoles": [] enters this branch
            # (an empty array IS declared) but consumes $CatResources nowhere -- the foreach below runs
            # zero times -- while $ResourceRolesDeclaredNull stays false, so the Extra/prune pass still
            # runs and correctly prunes every live binding. Reading the catalog anyway turned that
            # correct outcome into a Failed row whenever the catalog read broke. A declared-null
            # resourceRoles never reaches this code at all, so the @($null).Count -eq 1 trap does not
            # apply to this count.
            $CatResources = @()
            if (@($Item.resourceRoles).Count -gt 0) {
                try {
                    $CatResources = @(Get-OERCatalogResource -Catalog $Item.catalog -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Caller.WriteError($PSItem)
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail "failed to read the resources of catalog '$($Item.catalog)': $($PSItem.Exception.Message); no resourceRole binding was added, reported Extra or removed" `
                        -ErrorRecord $PSItem
                    return
                }
            }
            foreach ($RrEntry in @($Item.resourceRoles)) {
                $ResName  = $RrEntry.resource
                $RoleName = $RrEntry.role

                # Resolve resource name to OriginId:
                # 1. Search catalog resources by display name.
                # 2. Fall back to Resolve-OERGroupId for AadGroup resources.
                $OriginId = $null
                $MatchedCatRes = $CatResources | Where-Object { $_.DisplayName -eq $ResName } | Select-Object -First 1
                if ($MatchedCatRes) {
                    $OriginId = $MatchedCatRes.OriginId
                }

                if (-not $OriginId) {
                    $OriginId = Resolve-OERGroupId -DisplayName $ResName
                }

                if (-not $OriginId) {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "could not resolve resource '$ResName' to an origin id in catalog '$($Item.catalog)'"
                    $ResourceRoleUnresolved.Add($ResName)
                    continue
                }

                # Build a lookup key for prune comparison.
                $BindingKey = "$RoleName|$OriginId"
                $DeclaredBindingKeys.Add($BindingKey)

                # Check if already present.
                $AlreadyBound = $CurrentBindings | Where-Object {
                    $_.role.displayName -eq $RoleName -and $_.scope.originId -eq $OriginId
                } | Select-Object -First 1

                if ($AlreadyBound) {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Unchanged' -Detail "resourceRole '$RoleName' on '$ResName' already bound"
                } else {
                    if ($Caller.ShouldProcess($Name, "Add resourceRole '$RoleName' on '$ResName'")) {
                        try {
                            # -AccessPackage takes the RESOLVED $ApId, not $Name -- see the note on
                            # the assignment policy read above: a display name here is resolved
                            # tenant-wide and ignores the declared catalog.
                            Add-OERAccessPackageResourceRole -AccessPackage $ApId -Catalog $Item.catalog -ResourceOriginId $OriginId -Role $RoleName -Confirm:$false -ErrorAction Stop | Out-Null
                            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Created' -Detail "added resourceRole '$RoleName' on '$ResName'"
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to add resourceRole '$RoleName' on '$ResName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would add resourceRole '$RoleName' on '$ResName'"
                    }
                }
            }
        }

        # Extra/prune undeclared current resource role bindings. Skipped ONLY when 'resourceRoles'
        # is explicitly null -- an omitted key still reconciles against an empty declared set
        # (existing behavior), but an explicit null is a distinct "leave bindings alone" signal and
        # must not report every live binding as Extra or, worse under -Prune, remove them all.
        if (-not $ResourceRolesDeclaredNull) {
            foreach ($CurBinding in $CurrentBindings) {
                $CurKey = "$($CurBinding.role.displayName)|$($CurBinding.scope.originId)"
                if ($DeclaredBindingKeys -notcontains $CurKey) {
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'accessPackages' -Item $Name -Unresolved $ResourceRoleUnresolved -Candidate "undeclared resourceRole binding '$CurKey'"
                    if ($Withheld) { $Withheld; continue }
                    if ($Prune) {
                        $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                        Write-Warning "Sync-OERStructureAccessPackage: $PruneVerb undeclared resourceRole binding '$CurKey' from access package '$Name'."
                        if ($Caller.ShouldProcess($Name, "Remove undeclared resourceRole binding '$CurKey'")) {
                            try {
                                # -AccessPackage takes the RESOLVED $ApId, not $Name. This one is a
                                # DELETE: a tenant-wide display-name resolve could target a binding
                                # on an identically named package in another catalog.
                                Remove-OERAccessPackageResourceRole -AccessPackage $ApId -ResourceRoleScopeId $CurBinding.id -Confirm:$false -ErrorAction Stop
                                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Removed' -Detail "removed undeclared resourceRole binding '$CurKey'"
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to remove resourceRole binding '$CurKey': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would remove undeclared resourceRole binding '$CurKey'"
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Extra' -Detail "undeclared resourceRole binding '$CurKey' (use -Prune to remove)"
                    }
                }
            }
        }

        # -- Step 3: assignmentPolicies (UPSERT) -------------------------------------------
        # An existing policy (matched by displayName) is reconciled by building the desired body from
        # the DECLARED entry fields, projecting it the same way the live policy is projected, and
        # diffing the two projections over only the declared fields (Resolve-OERAssignmentPolicyChange).
        # On a difference it calls Set with the declared sub-objects/scalars and reports Updated; no
        # difference reports Unchanged. An absent policy is created from the same desired parts. The
        # full per-approver set is now part of the diff; the only fallback is the back-compat Tenant
        # Profile PrimaryApprovers/EscalationApprovers default for a stage that declares no manager and
        # no explicit approvers.

        # Nested helper: build the desired requestor scope, requestor settings, approval stages, the
        # ConvertTo-OERPolicyBody scalar params, and the declared-field list -- shared by CREATE and
        # UPDATE. Returns
        #   @{ Success=[bool]; RequestorScope=<obj>; RequestorSettings=<obj>; Stages=<obj[]>;
        #      BodyScalars=<hashtable>; DeclaredFields=<string[]>; FailDetail=<string>; ErrorRecord=<er> }.
        function Build-OERPolicyParts {
            param(
                [PSCustomObject]$PolicyEntry,
                [string]$PolicyName,
                [string]$Alias
            )
            $DeclaredFields = [System.Collections.Generic.List[string]]::new()
            $BodyScalars = @{}

            # requestorScope: always built (defaults to AllMemberUsers). Declared when the entry carries
            # a requestorScope object (scope/users/groups).
            $HasRequestorScope = Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requestorScope'
            $ScopeValue = 'AllMemberUsers'
            $ScopeUsers = @()
            $ScopeGroups = @()
            if ($HasRequestorScope) {
                $DeclaredFields.Add('requestorScope')
                $RsEntry = $PolicyEntry.requestorScope
                $HasScopeValue = Test-OERDeclaredProperty -Node $RsEntry -Name 'scope'
                if ($HasScopeValue) { $ScopeValue = $RsEntry.scope }
                if (Test-OERDeclaredProperty -Node $RsEntry -Name 'users') { $ScopeUsers = @($RsEntry.users) }
                if (Test-OERDeclaredProperty -Node $RsEntry -Name 'groups') { $ScopeGroups = @($RsEntry.groups) }

                # Issue #69: a requestorScope that declares users/groups but no scope WOULD have
                # defaulted to AllMemberUsers, discarding the users/groups entirely --
                # New-OERAccessPackageRequestorScope only splats -User/-Group under -Scope
                # SpecificDirectoryUsers. That never actually reached a tenant: Test-OERStructureSchema
                # raised an ERROR for the shape and Invoke-OERStructure refuses any document with one,
                # with no -SkipValidation escape, so this handler was never handed such a document
                # through the public entry point. No live tenant carries a widened requestor scope
                # written by an earlier release; what the fix changes is that the document is now
                # ACCEPTED (with a Warning) and applied as intended. An explicit scope always
                # wins (this branch never runs when $HasScopeValue is true); only when scope is
                # undeclared AND the users/groups list is non-empty do we infer SpecificDirectoryUsers, so
                # a declared-empty list still falls back to AllMemberUsers instead of naming nobody.
                if ((-not $HasScopeValue) -and (($ScopeUsers.Count -gt 0) -or ($ScopeGroups.Count -gt 0))) {
                    $ScopeValue = 'SpecificDirectoryUsers'
                }
            }

            # description scalar.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'description') {
                $DeclaredFields.Add('description')
                $BodyScalars.Description = [string]$PolicyEntry.description
            }

            # approval toggles.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requireApproval') {
                $DeclaredFields.Add('requireApproval')
                $BodyScalars.RequireApproval = [bool]$PolicyEntry.requireApproval
            }
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requireRequestorJustification') {
                $DeclaredFields.Add('requireRequestorJustification')
                $BodyScalars.RequireRequestorJustification = [bool]$PolicyEntry.requireRequestorJustification
            }
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requireApprovalForUpdate') {
                $DeclaredFields.Add('requireApprovalForUpdate')
                $BodyScalars.RequireApprovalForUpdate = [bool]$PolicyEntry.requireApprovalForUpdate
            }

            # expiration: at most one of durationInDays / durationInHours / expirationDateTime.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'durationInDays') {
                $DeclaredFields.Add('expiration')
                $BodyScalars.DurationInDays = [int]$PolicyEntry.durationInDays
            } elseif (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'durationInHours') {
                $DeclaredFields.Add('expiration')
                $BodyScalars.DurationInHours = [int]$PolicyEntry.durationInHours
            } elseif (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'expirationDateTime') {
                $DeclaredFields.Add('expiration')
                $BodyScalars.ExpirationDateTime = [datetime]$PolicyEntry.expirationDateTime
            }

            # notificationsDisabled scalar.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'notificationsDisabled') {
                $DeclaredFields.Add('notificationsDisabled')
                $BodyScalars.DisableAssignmentNotifications = [bool]$PolicyEntry.notificationsDisabled
            }

            $BuiltSettings = $null
            $BuiltStages = [System.Collections.Generic.List[PSCustomObject]]::new()
            try {
                # requestorScope builder (pass users/groups only for SpecificDirectoryUsers).
                $ScopeParams = @{ Scope = $ScopeValue; ErrorAction = 'Stop' }
                if ($ScopeValue -eq 'SpecificDirectoryUsers') {
                    if ($ScopeUsers.Count -gt 0) { $ScopeParams.User = $ScopeUsers }
                    if ($ScopeGroups.Count -gt 0) { $ScopeParams.Group = $ScopeGroups }
                }
                $BuiltScope = New-OERAccessPackageRequestorScope @ScopeParams

                # requestorSettings builder (only when declared).
                if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requestorSettings') {
                    $DeclaredFields.Add('requestorSettings')
                    $RsObj = $PolicyEntry.requestorSettings
                    $SettingsParams = @{}
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowSelfRequest') -and ([bool]$RsObj.allowSelfRequest)) { $SettingsParams.AllowSelfRequest = $true }
                    $HasManagerRequest = (Test-OERDeclaredProperty -Node $RsObj -Name 'allowManagerRequest') -and ([bool]$RsObj.allowManagerRequest)
                    if ($HasManagerRequest) {
                        $SettingsParams.AllowManagerRequest = $true
                        if (Test-OERDeclaredProperty -Node $RsObj -Name 'managerLevel') { $SettingsParams.ManagerLevel = [int]$RsObj.managerLevel }
                    }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowCustomSchedule') -and ([bool]$RsObj.allowCustomSchedule)) { $SettingsParams.AllowCustomSchedule = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowSelfExtend') -and ([bool]$RsObj.allowSelfExtend)) { $SettingsParams.AllowSelfExtend = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowSelfRemove') -and ([bool]$RsObj.allowSelfRemove)) { $SettingsParams.AllowSelfRemove = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowOnBehalfUpdate') -and ([bool]$RsObj.allowOnBehalfUpdate)) { $SettingsParams.AllowOnBehalfUpdate = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowOnBehalfRemove') -and ([bool]$RsObj.allowOnBehalfRemove)) { $SettingsParams.AllowOnBehalfRemove = $true }
                    $BuiltSettings = New-OERAccessPackageRequestorSettings @SettingsParams -ErrorAction Stop
                }

                # approval stages (full declared approver set; back-compat default fallback retained).
                if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'approvalStages') {
                    $DeclaredFields.Add('approvalStages')
                    $StageIndex = 0
                    foreach ($StageEntry in @($PolicyEntry.approvalStages)) {
                        $StageIndex++

                        # Issue #70 site 3: route the read through Test-OERDeclaredProperty instead of
                        # casting $StageEntry.durationDays unguarded. -DurationDays on
                        # New-OERAccessPackageApprovalStage is a Mandatory [int], so the splat key can
                        # never be dropped -- the applied value stays 0 for an absent or explicit-null
                        # durationDays, unchanged from the prior [int]$null/[int]<missing> coercion.
                        # Measured, not assumed (a null does not always coerce the way it looks like it
                        # should): 0 is NOT a quiet "P0D" stage. New-OERAccessPackageApprovalStage's own
                        # ConvertTo-OERDuration -Days call carries [ValidateRange(1, ...)], so a
                        # DurationDays of 0 throws there, the throw is caught by this function's own try
                        # below, and the WHOLE assignmentPolicy is reported Failed instead of being
                        # created or updated. Test-OERStructureSchema below now warns offline about that
                        # outcome instead of the document silently discovering it at apply time.
                        $HasDurationDays = Test-OERDeclaredProperty -Node $StageEntry -Name 'durationDays'
                        $StageDurationDays = if ($HasDurationDays) { [int]$StageEntry.durationDays } else { 0 }
                        $StageParams = @{ DurationDays = $StageDurationDays; ErrorAction = 'Stop' }

                        $StageUsers = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'users') { @($StageEntry.users) } else { @() }
                        $StageGroups = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'groups') { @($StageEntry.groups) } else { @() }
                        $UseManager = (Test-OERDeclaredProperty -Node $StageEntry -Name 'manager') -and ([bool]$StageEntry.manager)
                        $UseInternal = (Test-OERDeclaredProperty -Node $StageEntry -Name 'internalSponsor') -and ([bool]$StageEntry.internalSponsor)
                        $UseExternal = (Test-OERDeclaredProperty -Node $StageEntry -Name 'externalSponsor') -and ([bool]$StageEntry.externalSponsor)
                        $HasExplicitApprover = ($StageUsers.Count -gt 0) -or ($StageGroups.Count -gt 0) -or $UseManager -or $UseInternal -or $UseExternal

                        if ($StageUsers.Count -gt 0) { $StageParams.User = $StageUsers }
                        if ($StageGroups.Count -gt 0) { $StageParams.Group = $StageGroups }
                        if ($UseManager) {
                            $StageParams.Manager = $true
                            if (Test-OERDeclaredProperty -Node $StageEntry -Name 'managerLevel') { $StageParams.ManagerLevel = [int]$StageEntry.managerLevel }
                        }
                        if ($UseInternal) { $StageParams.InternalSponsor = $true }
                        if ($UseExternal) { $StageParams.ExternalSponsor = $true }

                        $AltUsers = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'alternateUsers') { @($StageEntry.alternateUsers) } else { @() }
                        $AltGroups = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'alternateGroups') { @($StageEntry.alternateGroups) } else { @() }
                        if ($AltUsers.Count -gt 0) { $StageParams.AlternateUser = $AltUsers }
                        if ($AltGroups.Count -gt 0) { $StageParams.AlternateGroup = $AltGroups }

                        # fallbackUsers/fallbackGroups feed New-OERAccessPackageApprovalStage's -FallbackUser/
                        # -FallbackGroup, which both land on fallbackPrimaryApprovers only. There is no
                        # document-authorable equivalent for fallbackEscalationApprovers -- Learn documents
                        # the fallback mechanism in terms of a missing manager/sponsor on the PRIMARY
                        # approver, and the Entra UI exposes a single "Add fallback" control, so a second
                        # parameter pair would be surface without a verified use. This is a LOSS, not a
                        # tidy carve-out: fallbackEscalationApprovers is neither read into the projection
                        # nor authorable here, and every stage is rebuilt as a whole on update (Microsoft
                        # Graph takes the full approvalStages array, not a per-stage patch), so a stage
                        # rebuilt through this handler sends an empty escalation fallback and CLEARS a
                        # portal-set one. The exposure is narrow: -AlternateUser/-AlternateGroup (declared
                        # here as alternateUsers/alternateGroups) build user/group escalation approvers,
                        # which need no fallback -- the case that bites is a manager or sponsor escalation
                        # configured in the portal.
                        $FbUsers = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'fallbackUsers') { @($StageEntry.fallbackUsers) } else { @() }
                        $FbGroups = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'fallbackGroups') { @($StageEntry.fallbackGroups) } else { @() }
                        if ($FbUsers.Count -gt 0) { $StageParams.FallbackUser = $FbUsers }
                        if ($FbGroups.Count -gt 0) { $StageParams.FallbackGroup = $FbGroups }

                        if (Test-OERDeclaredProperty -Node $StageEntry -Name 'escalationDays') { $StageParams.EscalationDays = [int]$StageEntry.escalationDays }
                        if ((Test-OERDeclaredProperty -Node $StageEntry -Name 'requireApproverJustification') -and ([bool]$StageEntry.requireApproverJustification)) { $StageParams.RequireJustification = $true }
                        if (Test-OERDeclaredProperty -Node $StageEntry -Name 'approverInfoVisibility') { $StageParams.ApproverInfoVisibility = [string]$StageEntry.approverInfoVisibility }

                        if (-not $HasExplicitApprover) {
                            # Back-compat: fall back to the Tenant Profile approver defaults.
                            $Pa = Resolve-OERStructureDefault -TenantAlias $Alias -Name 'PrimaryApprovers'
                            $Ea = Resolve-OERStructureDefault -TenantAlias $Alias -Name 'EscalationApprovers'
                            if (-not $Pa) {
                                return @{ Success = $false; FailDetail = "assignmentPolicy '$PolicyName': an approval stage has no manager, no explicit approvers, and no Tenant Profile PrimaryApprovers default"; ErrorRecord = $null }
                            }

                            # Issue #68: this branch is reached by two different document shapes that mean
                            # different things to an operator, so distinguish them in the warning rather
                            # than documenting the substitution away:
                            #   - no approver keys declared at all -- the back-compat path, expected;
                            #   - approver keys declared but all empty -- the author tried to express "no
                            #     approvers" and got the Tenant Profile default instead, since
                            #     New-OERAccessPackageApprovalStage hard-rejects a zero-approver stage
                            #     (NoApprover) and there is no way to author a true zero-approver stage.
                            # The distinguishing clause is read with Test-OERDeclaredProperty, never an
                            # inline PSObject.Properties check, per the module's single "declared" owner.
                            $HasAnyApproverKey = (Test-OERDeclaredProperty -Node $StageEntry -Name 'users') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'groups') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'manager') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'internalSponsor') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'externalSponsor')
                            # $PaCount is safe as a bare @($Pa).Count: the guard two lines above already
                            # returned when $Pa was falsy, so $Pa is guaranteed non-null/non-empty here.
                            # $Ea carries no such guard -- Resolve-OERStructureDefault returns a bare $null
                            # when the profile has no EscalationApprovers default, and @($null).Count is 1,
                            # not 0 (a repeat offender in this module's own history). Route it through an
                            # explicit truthiness check so a genuinely empty default can never be
                            # misreported as "1 EscalationApprovers". $EaCount is now only ever RENDERED on
                            # the branch below that actually substituted the escalation default (which
                            # already requires $Ea to be truthy), so the guard is belt-and-braces -- keep it
                            # anyway, so the count cannot regress if that branch condition ever changes.
                            $PaCount = @($Pa).Count
                            $EaCount = if ($Ea) { @($Ea).Count } else { 0 }

                            # Issue #68: only substitute the escalation default when the document declared
                            # NO alternateUsers at all -- gated on Test-OERDeclaredProperty, not on
                            # $AltUsers.Count -eq 0 and not on -not $StageParams.ContainsKey('AlternateUser').
                            # Both rejected forms also hold true for a document that declared
                            # "alternateUsers": [] (an explicit "no escalation approvers"), because the
                            # -AlternateUser splat key above is only added when the array is non-empty; either
                            # rejected form would let this fallback silently override that explicit statement.
                            #
                            # The decision is taken HERE, above the warning, and the warning reads it --
                            # measured live: a stage declaring "users": [] with its own alternateUsers kept
                            # the document's escalation approver (issue #68's fix working), while the warning
                            # still printed the profile's EscalationApprovers count, naming a substitution
                            # that never happened and reading exactly like the pre-#68 behaviour it was added
                            # to make visible. The message names only what was actually substituted.
                            $SubstituteEscalation = [bool]($Ea -and -not (Test-OERDeclaredProperty -Node $StageEntry -Name 'alternateUsers'))
                            $Substituted = if ($SubstituteEscalation) {
                                "$PaCount PrimaryApprovers, $EaCount EscalationApprovers"
                            } else {
                                "$PaCount PrimaryApprovers"
                            }
                            if ($HasAnyApproverKey) {
                                Write-Warning "Sync-OERStructureAccessPackage: assignmentPolicy '$PolicyName' stage $StageIndex declared approver keys (users/groups/manager/internalSponsor/externalSponsor) that are all empty; substituting Tenant Profile '$Alias' defaults ($Substituted) instead of the zero-approver stage the document tried to express."
                            } else {
                                Write-Warning "Sync-OERStructureAccessPackage: assignmentPolicy '$PolicyName' stage $StageIndex declared no approver keys at all; substituting Tenant Profile '$Alias' defaults ($Substituted) (back-compat)."
                            }

                            $StageParams.User = @($Pa)
                            if ($SubstituteEscalation) {
                                $StageParams.AlternateUser = @($Ea)
                            }
                        }

                        $BuiltStages.Add((New-OERAccessPackageApprovalStage @StageParams))
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                return @{ Success = $false; FailDetail = "failed to build assignmentPolicy '$PolicyName': $($PSItem.Exception.Message)"; ErrorRecord = $PSItem }
            }

            return @{
                Success           = $true
                RequestorScope    = $BuiltScope
                RequestorSettings = $BuiltSettings
                Stages            = $BuiltStages.ToArray()
                BodyScalars       = $BodyScalars
                DeclaredFields    = $DeclaredFields.ToArray()
                FailDetail        = $null
                ErrorRecord       = $null
            }
        }

        $DeclaredPolicyNames = [System.Collections.Generic.List[string]]::new()
        if (Test-OERDeclaredProperty -Node $Item -Name 'assignmentPolicies') {
            foreach ($PolEntry in @($Item.assignmentPolicies)) {
                $PolName = $PolEntry.displayName
                $DeclaredPolicyNames.Add(([string]$PolName).ToLowerInvariant())
                $ExistingPol = $CurrentPolicies | Where-Object { $_.DisplayName -eq $PolName } | Select-Object -First 1

                # Build the desired parts once (used by the diff and by the Set/New call).
                $Parts = Build-OERPolicyParts -PolicyEntry $PolEntry -PolicyName $PolName -Alias $TenantAlias
                if (-not $Parts.Success) {
                    if ($Parts.ErrorRecord) { $Caller.WriteError($Parts.ErrorRecord) }
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail $Parts.FailDetail -ErrorRecord $Parts.ErrorRecord
                    continue
                }

                if ($ExistingPol) {
                    # -- Project the desired body and diff it over the declared fields only. --
                    $BodyParams = @{
                        DisplayName     = $PolName
                        AccessPackageId = $ApId
                        RequestorScope  = $Parts.RequestorScope
                    }
                    if ($Parts.RequestorSettings) { $BodyParams.RequestorSettings = $Parts.RequestorSettings }
                    # Declared-gate (issue #56). Behaviour-neutral here -- ConvertTo-OERPolicyBody is
                    # called without -Existing, so an omitted key and a declared [] both resolve to no
                    # stages -- but a count-based gate is the wrong predicate everywhere. See the Set
                    # splat below for the site where it actually changed behaviour.
                    if (@($Parts.DeclaredFields) -contains 'approvalStages') { $BodyParams.ApprovalStage = $Parts.Stages }
                    foreach ($K in $Parts.BodyScalars.Keys) { $BodyParams[$K] = $Parts.BodyScalars[$K] }

                    $Change = $null
                    try {
                        $DesiredBody = ConvertTo-OERPolicyBody @BodyParams -ErrorAction Stop
                        $DesiredProj = ConvertTo-OERAssignmentPolicy -InputObject $DesiredBody -AccessPackageId $ApId
                        $Change = Resolve-OERAssignmentPolicyChange -Desired $DesiredProj -Current $ExistingPol -DeclaredFields @($Parts.DeclaredFields)
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to diff assignmentPolicy '$PolName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        continue
                    }

                    if (-not $Change.Differs) {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Unchanged' -Detail "assignmentPolicy '$PolName' matches"
                        continue
                    }
                    if (-not $Caller.ShouldProcess($Name, "Update assignmentPolicy '$PolName'")) {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would update assignmentPolicy '$PolName'"
                        continue
                    }

                    # requestorScope is written ONLY when the document entry declared it; otherwise the
                    # policy keeps its live scope. Sending the AllMemberUsers default here used to reset
                    # a live SpecificDirectoryUsers scope whenever an unrelated field changed.
                    $SetParams = @{ Id = $ExistingPol.Id; DisplayName = $PolName; Confirm = $false }
                    if (@($Parts.DeclaredFields) -contains 'requestorScope') { $SetParams.RequestorScope = $Parts.RequestorScope }
                    if ($Parts.RequestorSettings) { $SetParams.RequestorSettings = $Parts.RequestorSettings }
                    # approvalStages is written ONLY when the document entry declared it, and this is the
                    # LOAD-BEARING one of the three declared-gates (issue #56).
                    # Set-OERAccessPackageAssignmentPolicy GETs the live policy and hands it to
                    # ConvertTo-OERPolicyBody as -Existing, so an OMITTED -ApprovalStage carries the live
                    # stages forward. The old count-based gate therefore made a declared
                    # "approvalStages": [] indistinguishable from an omitted key: the stages were carried
                    # forward every run and the document never converged. An empty $Parts.Stages binds
                    # fine -- there is no ValidateNotNullOrEmpty on -ApprovalStage and the per-entry type
                    # check iterates zero times -- so do NOT "simplify" this back to a Count check, and do
                    # not wrap $Parts.Stages in @() here without re-checking that the empty case binds.
                    if (@($Parts.DeclaredFields) -contains 'approvalStages') { $SetParams.ApprovalStage = $Parts.Stages }
                    foreach ($K in $Parts.BodyScalars.Keys) {
                        # Switch-typed cmdlet params take a [bool] value when declared; ints/datetime pass through.
                        $SetParams[$K] = $Parts.BodyScalars[$K]
                    }
                    try {
                        Set-OERAccessPackageAssignmentPolicy @SetParams -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Updated' -Detail "updated assignmentPolicy '$PolName' ($($Change.ChangedFields -join ', '))"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to update assignmentPolicy '$PolName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                    continue
                }

                # -- CREATE (absent) -- use the same desired parts.
                if ($Caller.ShouldProcess($Name, "Create assignmentPolicy '$PolName'")) {
                    # AccessPackage takes the RESOLVED $ApId, not $Name -- matching the UPDATE path
                    # above, which already identifies the package by id. A display name here is
                    # resolved tenant-wide and would create the policy on the wrong package (or
                    # fail with AmbiguousName) whenever the name is reused across catalogs.
                    $PolicyParams = @{ AccessPackage = $ApId; DisplayName = $PolName; RequestorScope = $Parts.RequestorScope; Confirm = $false }
                    if ($Parts.RequestorSettings) { $PolicyParams.RequestorSettings = $Parts.RequestorSettings }
                    # Declared-gate (issue #56). Behaviour-neutral on create -- there is no live policy to
                    # carry stages forward from -- but a count-based gate is the wrong predicate everywhere.
                    if (@($Parts.DeclaredFields) -contains 'approvalStages') { $PolicyParams.ApprovalStage = $Parts.Stages }
                    foreach ($K in $Parts.BodyScalars.Keys) { $PolicyParams[$K] = $Parts.BodyScalars[$K] }
                    try {
                        New-OERAccessPackageAssignmentPolicy @PolicyParams -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Created' -Detail "created assignmentPolicy '$PolName'"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to create assignmentPolicy '$PolName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        continue
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would create assignmentPolicy '$PolName'"
                }
            }

            # Undeclared live policies are reported, never deleted. -Prune is scoped to resource role
            # bindings on this handler (see .PARAMETER Prune): removing a self-service request policy is
            # a different blast radius, and Microsoft Learn does not state whether a package's last
            # policy may be deleted at all. Report it so it is visible instead of silently in force.
            foreach ($CurPol in $CurrentPolicies) {
                $CurPolName = [string]$CurPol.DisplayName
                if ($DeclaredPolicyNames -contains $CurPolName.ToLowerInvariant()) { continue }
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Extra' `
                    -Detail "undeclared assignmentPolicy '$CurPolName' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)"
            }
        }
    }
}
