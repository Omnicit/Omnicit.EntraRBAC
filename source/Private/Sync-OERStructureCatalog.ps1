function Sync-OERStructureCatalog {
    <#
    .SYNOPSIS
    Reconciles one catalogs[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single catalog entry from the structure document. It is called by
    the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult records
    describing what was created, updated, removed, skipped, or left unchanged.

    displayName is the match key: an existing catalog is matched and updated by it. Renaming through
    the document is not possible: this handler uses displayName purely to match, and never calls
    Set-OERCatalog -NewDisplayName -- a changed displayName creates a new catalog under the new name
    and leaves the old one in place, unreported.

    Processing order within a single catalog entry:

    1. Create the catalog when absent, or diff and update the mutable description and externallyVisible
       properties when it already exists.
    2. Reconcile declared resources (add missing by type/name; emit Extra or prune undeclared with
       -Prune). Resources are matched by DisplayName, and additionally by OriginId for a SharePoint
       Online site so a site declared by url round-trips.

    When -Prune is set, current resources whose DisplayName is not in the declared resources set are
    removed (with Write-Warning) after a ShouldProcess gate. Without -Prune those extras are reported
    as Extra (informational) and left alone.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false; the handler
    emits Skipped records instead of calling child cmdlets. When the catalog itself does not exist and
    its creation is skipped under -WhatIf, no child read or write calls are made.

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

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Currently unused by this handler but
    accepted for a uniform Sync-OERStructure* signature.

    .EXAMPLE
    Sync-OERStructureCatalog -Item $DocItem -Caller $PSCmdlet -Prune -TenantAlias 'omnicit'
    Reconciles one catalog entry from the document, pruning undeclared resources, resolving the
    caller from the engine PSCmdlet.
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
        [string]$TenantAlias
    )
    process {
        # -- Resolve the display name -------------------------------------------------------
        $Name = $Item.displayName

        # -- Check existence ----------------------------------------------------------------
        $CatId = Resolve-OERCatalogId -DisplayName $Name

        # -- Create or update the catalog object --------------------------------------------
        if (-not $CatId) {
            # Catalog does not exist -- create it.
            if (-not $Caller.ShouldProcess($Name, 'Create catalog')) {
                # Under -WhatIf: emit Skipped for the catalog and all declared resources, then return.
                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Skipped' -Detail "would create catalog $Name"

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
            # Catalog exists -- diff mutable properties (description, externallyVisible).
            $Cur = Get-OERCatalog -Id $CatId

            $UpdateParams = @{}
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
                if ($Caller.ShouldProcess($Name, 'Update catalog properties')) {
                    try {
                        Set-OERCatalog -Id $CatId @UpdateParams -Confirm:$false -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Updated' -Detail "updated catalog properties ($($UpdateParams.Keys -join ', '))"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail "update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Skipped' -Detail "would update catalog properties ($($UpdateParams.Keys -join ', '))"
                }
            } else {
                ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Unchanged' -Detail 'catalog properties match'
            }

            # Read current resources for reconciliation
            $CurrentResources = @(Get-OERCatalogResource -Catalog $CatId)
        }

        # -- Step 2: resources --------------------------------------------------------------
        # A resource is identified by its declared name, EXCEPT a SharePoint Online site, which is
        # onboarded by URL (Graph stores that URL as the resource originId; the display name is only
        # the site title). Track BOTH keys so an existing site matches on its originId and is never
        # re-added or pruned as undeclared.
        $DeclaredResourceKey = [System.Collections.Generic.List[string]]::new()
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

                $DeclaredResourceKey.Add([string]$ResName)
                if ($ResUrl) { $DeclaredResourceKey.Add($ResUrl) }

                $AlreadyPresent = $CurrentResources | Where-Object {
                    $_.DisplayName -eq $ResName -or
                    ($ResIdentifier -and [string]$_.OriginId -eq $ResIdentifier)
                }
                if ($AlreadyPresent) {
                    ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Unchanged' -Detail "resource '$ResName' already present"
                } else {
                    # Map the declared type to the right Add-OERCatalogResource parameter. An
                    # unrecognized type is a Failed item (the schema validator normally rejects bad
                    # types upstream, but the handler must not silently mis-add as a Group).
                    $AddParams = @{ Catalog = $CatId; Confirm = $false }
                    $KnownType = $true
                    switch ($ResType) {
                        'Group'          { $AddParams.Group          = $ResName }
                        'Application'    { $AddParams.Application     = $ResName }
                        'SharePointSite' { $AddParams.SharePointSite  = $ResIdentifier }
                        default          { $KnownType = $false }
                    }
                    if (-not $KnownType) {
                        ConvertTo-OERStructureResult -Section 'catalogs' -Item $Name -Action 'Failed' -Detail "unrecognized resource type '$ResType' for resource '$ResName'; expected Group, Application, or SharePointSite"
                        continue
                    }
                    if ($Caller.ShouldProcess($Name, "Add $ResType resource '$ResName'")) {
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
        }

        # Extra/prune undeclared current resources. A resource counts as declared when EITHER its
        # display name or its originId (the SharePoint site URL) appears in the declared key set.
        # Skipped ONLY when 'resources' is explicitly null -- an omitted key still reconciles
        # against an empty declared set (existing behavior), but an explicit null is a distinct
        # "leave resources alone" signal and must not report every live resource as Extra or,
        # worse under -Prune, remove them all.
        if (-not $ResourcesDeclaredNull) {
            foreach ($CurRes in $CurrentResources) {
                $IsDeclared = ($DeclaredResourceKey -contains $CurRes.DisplayName) -or
                              ($CurRes.OriginId -and ($DeclaredResourceKey -contains [string]$CurRes.OriginId))
                if (-not $IsDeclared) {
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
