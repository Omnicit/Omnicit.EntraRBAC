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
