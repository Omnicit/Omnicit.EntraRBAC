function Sync-OERStructureCatalog {
    <#
    .SYNOPSIS
    Reconciles one catalogs[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single catalog entry from the structure document. It is called by
    the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult records
    describing what was created, updated, removed, skipped, or left unchanged.

    displayName is the match key: an existing catalog is matched and updated by it. To rename a
    catalog, the document declares its new name as displayName and its current name as
    previousDisplayName (BL-128), and both names are resolved on every run before anything is read or
    written. Resolve-OERStructureRename owns the decision, its error ids and its texts:
    - Both resolve to DIFFERENT catalogs: the item emits exactly one Failed row and a non-terminating
      CatalogRenameConflict error (category ResourceExists, target the new name), and nothing else is
      read or written for it -- the document never merges two catalogs.
    - Only previousDisplayName resolves: that catalog takes the existing-catalog path, and the rename
      is folded into the step-1 property update (Set-OERCatalog -NewDisplayName, in the same PATCH as
      every other changed property), reported as one Updated row "renamed catalog '<previous>' to
      '<new>'". When that update fails, the Failed row is the last one: no resource of the catalog is
      reconciled.
    - Both resolve to the SAME catalog, or only displayName resolves: the item is applied normally.
    - Neither resolves: the item emits exactly one Failed row and a non-terminating
      CatalogRenameNotFound error (category ObjectNotFound, target the new name), and nothing is
      created, read or written for it, and under -WhatIf nothing is added to -PlannedCatalog. A
      document that declares a rename names a catalog that already exists; a catalog is created only
      by an entry WITHOUT previousDisplayName.
    A previousDisplayName matching several catalogs throws AmbiguousName, as an ambiguous displayName
    does, and the item fails with nothing created or renamed. previousDisplayName also accepts the
    catalog's object id, which is the way to rename a catalog whose old name is ambiguous. An object
    id is verified with one read (v1.0/identityGovernance/entitlementManagement/catalogs/<id>, with no
    $select) rather than through Resolve-OERCatalogId, which returns an object id verbatim without
    any request: an id that no longer names a catalog counts as not matching, so a stale id never
    reports a false conflict (with displayName resolving, the item is applied normally; with it not
    resolving, the item fails as above), and any other failure of that read throws, again with
    nothing created or renamed.

    Microsoft Graph's displayName lookup can follow a rename with a delay. On the run that renames
    the catalog, a reference to the NEW name elsewhere in the same document can therefore fail to
    resolve; the access packages section reads the rename map (-RenameMap) for a package declared in
    the renamed catalog, and a reference by name anywhere else fails loudly and is safe to re-run once
    the new name resolves. Keep previousDisplayName in the document until the new name resolves: a
    run after that finds the catalog under displayName and reports it Unchanged, and a re-run inside
    the window in which neither name resolves yet fails with CatalogRenameNotFound instead of creating
    a second catalog. Once the new name resolves, remove previousDisplayName: a catalog created later
    under the old name makes the item fail.

    Processing order within a single catalog entry:

    1. Create the catalog when absent, or diff and update the mutable description and externallyVisible
       properties (and the display name, when previousDisplayName renames the catalog) when it already
       exists.
    2. Reconcile declared resources (add missing by type/name; emit Extra or prune undeclared with
       -Prune). A Group or Application resource is matched by OBJECT ID: its declared name (or object
       id) is resolved to the group's, or the enterprise application's service principal's, object
       id, and compared with the live resource's originId. The display name a catalog records for a
       resource is never compared: Graph keeps the name the resource had when it was added, also
       after the group or application is renamed (measured live 2026-09-30), so a match on it would
       read a renamed group's resource as undeclared and, under -Prune, remove it. A SharePoint Online
       site is matched by its display name, and by OriginId so a site declared by url round-trips.

    When -Prune is set, undeclared current resources are removed (with Write-Warning) after a
    ShouldProcess gate. Without -Prune those extras are reported as Extra (informational) and left
    alone.

    Withheld prune: a declared Group or Application whose name resolves to no object -- or to several
    (AmbiguousGroupName / AmbiguousApplicationName, with the candidate ids) -- reports Failed with its
    own error, and while any declared resource is unresolved every undeclared live resource is
    reported Skipped with a Detail starting "prune withheld:", with or without -Prune; nothing is
    removed or reported Extra (ConvertTo-OERPruneWithheldResult owns the rule and the text). A lookup
    that FAILS, rather than finding nothing, is never read as "not there": it throws, and the engine
    reports the item Failed before any prune runs.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false; the handler
    emits Skipped records instead of calling child cmdlets. When the catalog itself does not exist and
    its creation is skipped under -WhatIf, no child read or write calls are made.

    Under -WhatIf, a catalog reported as "would create catalog" is also added to -PlannedCatalog, so
    that Sync-OERStructureAccessPackage, which Invoke-OERStructure dispatches after this handler, plans
    a package declared in that catalog as created instead of failing its catalog lookup. A creation
    skipped any other way (a declined -Confirm, where -WhatIf is not in force) adds nothing, and nor
    does a real run, an existing catalog or a call without the list.

    .PARAMETER Item
    One element from the catalogs[] array in the structure document, as a PSCustomObject produced by
    ConvertFrom-Json.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set, current resources not in the declared set are removed after a ShouldProcess gate.
    Without this switch, extra resources are only reported as Extra and never deleted. An omitted
    resources key still reconciles this way; an explicit "resources": null does not reconcile at
    all -- null, not an omitted key, is how a catalog is declared without touching its resources.
    While a declared Group or Application resource cannot be resolved, nothing is removed or
    reported Extra: every undeclared resource is reported Skipped ("prune withheld:").

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Currently unused by this handler but
    accepted for a uniform Sync-OERStructure* signature.

    .PARAMETER PlannedCatalog
    Optional list that collects the names of the catalogs a -WhatIf plan would create. This handler
    adds the entry's displayName to it, only under -WhatIf and only when it reports "would create
    catalog"; Invoke-OERStructure passes one list per run to this handler and to
    Sync-OERStructureAccessPackage, which reads it. Omit it to collect nothing.

    .PARAMETER RenameMap
    The run-scoped rename map Invoke-OERStructure creates once per document and passes to this handler,
    to Sync-OERStructureGroup, to Sync-OERStructureAdministrativeUnit and to the access package handler.
    For an entry that declares previousDisplayName, Resolve-OERStructureRename registers the outcome
    under 'catalogs|<new name>' in lower case: the id of the catalog the entry renames, or a refused
    entry when its rename conflicts or finds nothing. The registration is made when the decision is, so
    under -WhatIf too and before the rename is sent; Get-OERStructureRenameTarget reads it, so an access
    package declared in the renamed catalog is read and created against the catalog's id. Optional:
    without it the decision is the same and nothing is registered.

    .EXAMPLE
    Sync-OERStructureCatalog -Item $DocItem -Caller $PSCmdlet -Prune -TenantAlias 'omnicit'
    Reconciles one catalog entry from the document, pruning undeclared resources, resolving the
    caller from the engine PSCmdlet.

    .EXAMPLE
    Sync-OERStructureCatalog -Item $DocItem -Caller $PSCmdlet -RenameMap $RenameMap
    With an entry whose displayName is 'CAT-IT-Core-EMEA' and whose previousDisplayName is
    'CAT-IT-Core', renames the catalog found under 'CAT-IT-Core' in the same update as its other
    changed properties, and registers the catalog's id under 'catalogs|cat-it-core-emea' in the map.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'TenantAlias',
        Justification = 'TenantAlias is part of the uniform Sync-OERStructure* handler signature; accepted for future use and caller consistency even though this handler does not resolve tenant defaults.'
    )]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias,
        [System.Collections.Generic.List[string]]$PlannedCatalog,
        [System.Collections.Generic.Dictionary[string, object]]$RenameMap
    )
    process {
        # -- Resolve the display name -------------------------------------------------------
        $Name = $Item.displayName

        # -- Check existence ----------------------------------------------------------------
        $CatId = Resolve-OERCatalogId -DisplayName $Name

        # -- Rename through previousDisplayName (BL-128, A5) -------------------------------
        # Both names are resolved before anything is read or written for the entry, on every run.
        # Resolve-OERStructureRename owns the decision, the error ids and the texts. Not wrapped in
        # try: a name matching several catalogs throws AmbiguousName exactly as an ambiguous
        # displayName does, and the engine reports the item Failed with nothing written for it.
        $RenameFrom = $null
        if (Test-OERDeclaredProperty -Node $Item -Name 'previousDisplayName') {
            $PrevName = [string]$Item.previousDisplayName
            if (Test-OERGuid -Value $PrevName) {
                # An object id: Resolve-OERCatalogId returns a GUID verbatim, with no request, so it
                # would "find" a catalog that was deleted. One read settles it; the not-found answer is
                # declared to the transport and means "no catalog under that id", any other failure
                # throws and the item fails with nothing written. No $select (Ruling R6).
                $PrevProbe = Invoke-OERGraphRequest -Uri "v1.0/identityGovernance/entitlementManagement/catalogs/$PrevName" `
                    -ExpectedErrorCode 'CatalogNotFound', 'NotFound'
                $PrevCatId = if (@($PrevProbe.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') { $null } else { $PrevName }
            } else {
                $PrevCatId = Resolve-OERCatalogId -DisplayName $PrevName
            }
            $Rename = Resolve-OERStructureRename -Section 'catalogs' -Name $Name -PreviousName $PrevName `
                -Id $CatId -PreviousId $PrevCatId -RenameMap $RenameMap
            if ($Rename.Outcome -eq 'Conflict' -or $Rename.Outcome -eq 'NotFound') {
                $Caller.WriteError($Rename.ErrorRecord)
                $Rename.Result
                return
            }
            $CatId = $Rename.Id
            $RenameFrom = $Rename.RenameFrom
        }

        # -- Create or update the catalog object --------------------------------------------
        if (-not $CatId) {
            # Catalog does not exist -- create it.
            if (-not $Caller.ShouldProcess($Name, 'Create catalog')) {
                # Under -WhatIf: emit Skipped for the catalog and all declared resources, then return.
                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Skipped' -Detail "would create catalog $Name"
                # BL-128 (A5): record the catalog this -WhatIf plan would create, so the access
                # packages declared in it are planned as created instead of failing their catalog
                # lookup. Only under -WhatIf: a declined -Confirm leaves the catalog uncreated, and its
                # packages must stay Failed, exactly as a real run would find them.
                if ($WhatIfPreference -and $null -ne $PlannedCatalog) { $PlannedCatalog.Add([string]$Name) }

                if (Test-OERDeclaredProperty -Node $Item -Name 'resources') {
                    foreach ($Res in @($Item.resources)) {
                        $ResName = if (Test-OERDeclaredProperty -Node $Res -Name 'name') { $Res.name } else { '?' }
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Skipped' -Detail "would configure resource '$ResName' after catalog is created"
                    }
                }
                return
            }

            # Build creation params
            $NewParams = @{ DisplayName = $Name; Confirm = $false }
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') { $NewParams.Description = $Item.description }
            if ((Test-OERDeclaredProperty -Node $Item -Name 'externallyVisible') -and ([bool]$Item.externallyVisible)) {
                $NewParams.ExternallyVisible = $true
            }

            $Created = $null
            try {
                $Created = New-OERCatalog @NewParams -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail "catalog creation failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                return
            }

            if (-not $Created) {
                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail 'New-OERCatalog returned no object'
                return
            }

            $CatId = $Created.Id
            ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Created' -Detail "created catalog $Name ($CatId)"

            # After create: current resources are empty
            $CurrentResources = @()

        } else {
            # Catalog exists -- diff mutable properties (description, externallyVisible) and, when
            # previousDisplayName renames it, send the new display name in the same update.
            $Cur = Get-OERCatalog -Id $CatId

            $UpdateParams = @{}
            # A rename through previousDisplayName travels in the same PATCH as every other changed
            # property, so the catalog is renamed and updated in one call.
            if ($RenameFrom) {
                $UpdateParams.NewDisplayName = $Name
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') {
                if ($Cur.Description -ne $Item.description) {
                    $UpdateParams.Description = $Item.description
                }
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'externallyVisible') {
                if ([bool]$Cur.ExternallyVisible -ne [bool]$Item.externallyVisible) {
                    $UpdateParams.ExternallyVisible = [bool]$Item.externallyVisible
                }
            }

            if ($UpdateParams.Count -gt 0) {
                # The rename is reported on its own terms; the other changed keys keep the wording
                # every property update has always had.
                $PropertyKeys = @($UpdateParams.Keys | Where-Object { $_ -ne 'NewDisplayName' })
                $PropertyList = $PropertyKeys -join ', '
                if ($RenameFrom) {
                    $UpdateAction = "Rename catalog '$RenameFrom' to '$Name'"
                    $UpdatedDetail = "renamed catalog '$RenameFrom' to '$Name'"
                    $PlannedDetail = "would rename catalog '$RenameFrom' to '$Name'"
                    if ($PropertyKeys.Count -gt 0) {
                        $UpdateAction += " and update catalog properties ($PropertyList)"
                        $UpdatedDetail += "; updated catalog properties ($PropertyList)"
                        $PlannedDetail += "; would update catalog properties ($PropertyList)"
                    }
                } else {
                    $UpdateAction = 'Update catalog properties'
                    $UpdatedDetail = "updated catalog properties ($PropertyList)"
                    $PlannedDetail = "would update catalog properties ($PropertyList)"
                }
                if ($Caller.ShouldProcess($Name, $UpdateAction)) {
                    try {
                        Set-OERCatalog -Id $CatId @UpdateParams -Confirm:$false -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Updated' -Detail $UpdatedDetail
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail "update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        # The catalog still carries its previous name, not the one the document
                        # declares, so none of its resources is reconciled under the new name.
                        if ($RenameFrom) { return }
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Skipped' -Detail $PlannedDetail
                }
            } else {
                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Unchanged' -Detail 'catalog properties match'
            }

            # Read current resources for reconciliation
            $CurrentResources = @(Get-OERCatalogResource -Catalog $CatId)
        }

        # -- Step 2: resources --------------------------------------------------------------
        # A Group or Application resource is identified by its OBJECT ID: the declared name is
        # resolved (a group through Resolve-OERGroupId, an application's service principal through
        # Resolve-OERApplicationId; an object id is taken as it is) and matched against the live
        # resource's originId -- never against the display name the catalog recorded when the
        # resource was added, which Graph does not refresh when the group or application is renamed
        # (measured live 2026-09-30). A SharePoint Online site keeps its name/url keys: it is onboarded
        # by URL, which Graph stores as the originId, and the display name is only the site title.
        $DeclaredResourceKey = [System.Collections.Generic.List[string]]::new()
        # Lower-cased object ids of the declared Group and Application resources.
        $DeclaredOriginId = [System.Collections.Generic.List[string]]::new()
        # Declared Group/Application resources whose name resolved to no object: they cannot protect
        # their live resource, so while this list is non-empty the Extra/prune pass below withholds
        # every candidate (ConvertTo-OERPruneWithheldResult owns the rule and the text).
        $ResourceUnresolved = [System.Collections.Generic.List[string]]::new()
        # An omitted 'resources' key has always meant "no add-list, but the prune/Extra loop below
        # still runs against whatever it finds" -- that is intentional, existing, tested behavior
        # (an absent collection is not an instruction to leave live state alone; only an EXPLICIT
        # null is). So the add loop is gated on Test-OERDeclaredProperty (skips on both absent and
        # null), while the prune/Extra loop below is gated on the narrower $ResourcesDeclaredNull so
        # it keeps running when the key is merely absent and only backs off on an explicit null.
        $ResourcesDeclaredNull = Test-OERDeclaredNull -Node $Item -Name 'resources'

        if (Test-OERDeclaredProperty -Node $Item -Name 'resources') {
            foreach ($ResEntry in @($Item.resources)) {
                $ResType = $ResEntry.type
                $ResName = $ResEntry.name
                $ResUrl  = if (Test-OERDeclaredProperty -Node $ResEntry -Name 'url') { [string]$ResEntry.url } else { $null }
                # The SharePoint identifier is the url when declared, otherwise a name that is
                # already a URL (the pre-url hand-authored form, kept working for back-compat).
                $ResIdentifier = if ($ResType -eq 'SharePointSite' -and $ResUrl) { $ResUrl } else { $ResName }

                # Map the declared type to the right Add-OERCatalogResource parameter. An
                # unrecognized type is a Failed item (the schema validator normally rejects bad
                # types upstream, but the handler must not silently mis-add as a Group).
                if ($ResType -notin @('Group', 'Application', 'SharePointSite')) {
                    ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail "unrecognized resource type '$ResType' for resource '$ResName'; expected Group, Application, or SharePointSite"
                    continue
                }

                $AddParams = @{ Catalog = $CatId; Confirm = $false }
                if ($ResType -eq 'SharePointSite') {
                    $DeclaredResourceKey.Add([string]$ResName)
                    if ($ResUrl) { $DeclaredResourceKey.Add($ResUrl) }
                    $AlreadyPresent = $CurrentResources | Where-Object {
                        $_.DisplayName -eq $ResName -or
                        ($ResIdentifier -and [string]$_.OriginId -eq $ResIdentifier)
                    }
                    $AddParams.SharePointSite = $ResIdentifier
                } else {
                    # Resolve the declared name to the object id. Not found is reported here and
                    # withholds the prune; an ambiguous name is refused with its candidates, the same
                    # way. Any other failure of the lookup throws: a read that failed is never taken
                    # as "not there", and the engine reports the item Failed before any prune runs.
                    $ResolvedId = $null
                    try {
                        $ResolvedId = if (Test-OERGuid -Value ([string]$ResName)) {
                            [string]$ResName
                        } elseif ($ResType -eq 'Group') {
                            Resolve-OERGroupId -DisplayName $ResName
                        } else {
                            Resolve-OERApplicationId -DisplayName $ResName
                        }
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        if (-not (Test-OERAmbiguousNameError -Record $PSItem)) { throw }
                        $AmbiguousId = if ($ResType -eq 'Group') { 'AmbiguousGroupName' } else { 'AmbiguousApplicationName' }
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new($PSItem.Exception.Message), $AmbiguousId,
                            [System.Management.Automation.ErrorCategory]::InvalidArgument, $ResName)
                        $Caller.WriteError($ErrRec)
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' `
                            -Detail "$ResType resource '$ResName' is ambiguous: $($PSItem.Exception.Message)" -ErrorRecord $ErrRec
                        $ResourceUnresolved.Add([string]$ResName)
                        continue
                    }
                    if (-not $ResolvedId) {
                        $NotFoundId = if ($ResType -eq 'Group') { 'GroupNotFound' } else { 'ApplicationNotFound' }
                        $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new("$ResType '$ResName' not found: no $(if ($ResType -eq 'Group') { 'group' } else { 'enterprise application' }) carries that name, so the catalog resource it names cannot be identified."),
                            $NotFoundId, [System.Management.Automation.ErrorCategory]::ObjectNotFound, $ResName)
                        $Caller.WriteError($ErrRec)
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' `
                            -Detail "$ResType resource '$ResName' could not be resolved to an object id; nothing was added for it" -ErrorRecord $ErrRec
                        $ResourceUnresolved.Add([string]$ResName)
                        continue
                    }
                    $ResolvedId = ([string]$ResolvedId).ToLowerInvariant()
                    $DeclaredOriginId.Add($ResolvedId)
                    $AlreadyPresent = $CurrentResources | Where-Object { ([string]$_.OriginId).ToLowerInvariant() -eq $ResolvedId }
                    if ($ResType -eq 'Group') { $AddParams.GroupId = $ResolvedId } else { $AddParams.ApplicationId = $ResolvedId }
                }

                if ($AlreadyPresent) {
                    ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Unchanged' -Detail "resource '$ResName' already present"
                } elseif ($Caller.ShouldProcess($Name, "Add $ResType resource '$ResName'")) {
                    try {
                        Add-OERCatalogResource @AddParams -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Updated' -Detail "added $ResType resource '$ResName'"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail "failed to add resource '$ResName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        continue
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Skipped' -Detail "would add $ResType resource '$ResName'"
                }
            }
        }

        # Extra/prune undeclared current resources. A Group or Application resource (originSystem
        # AadGroup / AadApplication) counts as declared when its originId is one of the declared
        # resources' object ids; any other resource -- a SharePoint site -- when its display name or
        # its originId (the site URL) is among the declared names and urls. While a declared Group or
        # Application could not be resolved, nothing is removed or reported Extra: every undeclared
        # resource is reported Skipped with a Detail starting "prune withheld:".
        # Skipped ONLY when 'resources' is explicitly null -- an omitted key still reconciles
        # against an empty declared set (existing behavior), but an explicit null is a distinct
        # "leave resources alone" signal and must not report every live resource as Extra or,
        # worse under -Prune, remove them all.
        if (-not $ResourcesDeclaredNull) {
            foreach ($CurRes in $CurrentResources) {
                $IsDeclared = if ([string]$CurRes.OriginSystem -in @('AadGroup', 'AadApplication')) {
                    $CurRes.OriginId -and ($DeclaredOriginId -contains ([string]$CurRes.OriginId).ToLowerInvariant())
                } else {
                    ($DeclaredResourceKey -contains $CurRes.DisplayName) -or
                    ($CurRes.OriginId -and ($DeclaredResourceKey -contains [string]$CurRes.OriginId))
                }
                if (-not $IsDeclared) {
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'catalogs' -Item $Name -Unresolved $ResourceUnresolved -Candidate "undeclared resource '$($CurRes.DisplayName)'"
                    if ($Withheld) { $Withheld; continue }
                    if ($Prune) {
                        $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                        Write-Warning "Sync-OERStructureCatalog: $PruneVerb undeclared resource '$($CurRes.DisplayName)' from catalog '$Name'."
                        if ($Caller.ShouldProcess($Name, "Remove undeclared resource '$($CurRes.DisplayName)'")) {
                            try {
                                Remove-OERCatalogResource -ResourceId $CurRes.Id -Catalog $CatId -Confirm:$false -ErrorAction Stop
                                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Removed' -Detail "removed undeclared resource '$($CurRes.DisplayName)'"
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail "failed to remove resource '$($CurRes.DisplayName)': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Skipped' -Detail "would remove undeclared resource '$($CurRes.DisplayName)'"
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Extra' -Detail "undeclared resource '$($CurRes.DisplayName)' (use -Prune to remove)"
                    }
                }
            }
        }
    }
}
