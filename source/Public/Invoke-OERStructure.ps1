function Invoke-OERStructure {
    <#
    .SYNOPSIS
    Applies a Phase 5 structure document to a live Entra ID (and optionally Azure) tenant.

    .DESCRIPTION
    The top-level apply engine for Phase 5 JSON Orchestration. Reads a structure document from
    -Path or -Json, validates it offline with Test-OERStructureSchema (aborting before any write
    if invalid), authenticates, then iterates every declared section in dependency order --
    Groups, AdministrativeUnits, Catalogs, AccessPackages, AccessReviews, RoleAssignments,
    RoleManagementPolicies -- and calls the matching Sync-OERStructure* handler for each item.

    Dependency order: Groups must exist before AUs can reference them as members; Catalogs before
    AccessPackages; all Entra sections before the Azure sections that may reference Entra objects.
    The engine always follows this order regardless of the key order in the JSON document.

    Administrative unit pre-pass: a group can also be created INTO an administrative unit
    (New-OERGroup -AdministrativeUnit), which is the reverse dependency from the one above. Before
    the dependency-ordered dispatch loop runs, the engine ensures -- via
    Sync-OERStructureAdministrativeUnit -EnsureOnly -- that every administrative unit named by a
    declared group's administrativeUnit property exists, creating it if the document also declares
    it. This runs only when both Groups and AdministrativeUnits are selected via -Include and both
    sections are present in the document. A group that names an administrative unit the document does
    not declare at all still fails when the groups section runs -- correctly, since there is nothing
    the pre-pass could create. The administrativeUnits section below still reconciles that unit's own
    members, scoped roles and other properties in full; the pre-pass only guarantees the object exists
    early enough for the group creation to succeed.

    Per-item continuation: a handler error (thrown exception) is caught, written as a non-
    terminating error, recorded as a Failed StructureResult, and the engine continues to the next
    item. A single bad item never aborts the run.

    Prune mode (-Prune): passed through to every handler. Each handler gates its prune pass
    with $Caller.ShouldProcess, honouring -WhatIf. Prune is child-scope only -- no handler ever
    deletes a top-level object (a group, catalog, etc.) that is absent from the document.

    WhatIf plan mode (-WhatIf): handlers receive the engine's $PSCmdlet as -Caller and read
    ShouldProcess from it. Under -WhatIf all writes return Skipped results; reads (diff queries)
    still execute so the plan is complete. The engine does NOT call ShouldProcess itself.

    Include filter (-Include): only sections listed in -Include are dispatched. Sections whose
    key is absent from the document or whose array is empty are also silently skipped.

    ARM sections: RoleAssignments and RoleManagementPolicies require an ARM token. If either is
    selected (via -Include) or -IncludeARM is explicitly set, Initialize-OERAuth is called with
    -IncludeARM so the ARM token is acquired up front. For a pure Entra document that does not
    include those sections and does not pass -IncludeARM, no ARM token is requested.

    RoleAssignments scope grouping: the engine groups declared role assignment items by their
    scope string and passes -ReconcileScope on the first item of each unique scope. This signals
    the handler to run its prune pass for that scope after processing the item.

    Returns zero or more tagged Omnicit.EntraRBAC.StructureResult records, one per reconcile
    action. A one-line verbose summary of counts per Action is written after all sections.

    A worked apply document showing every section this engine understands is kept in the repository
    at docs/examples/example-structure.json, and the full export to apply walkthrough is documented
    in the repository at docs/inventory-to-llm/README.md. Neither ships inside the installed module,
    so clone or browse the repository to read them.

    .PARAMETER Path
    Path to a JSON structure document file. Mutually exclusive with -Json and -InputObject.

    .PARAMETER Json
    A literal JSON string containing the structure document. Mutually exclusive with -Path and
    -InputObject.

    .PARAMETER InputObject
    The document to apply: a PSCustomObject (such as the output of Get-OERInventory) to apply
    directly, eliminating the need for a manual ConvertTo-Json / ConvertFrom-Json round-trip; OR a
    file to read -- either a path string or a System.IO.FileInfo (for example piped from
    Get-ChildItem or Get-Item), read from disk exactly like -Path. A System.IO.DirectoryInfo is an
    error. Mutually exclusive with -Path and -Json.

    .PARAMETER Prune
    When set, each section handler removes child-scope objects that are present in the tenant but
    absent from the document (for example undeclared group members or undeclared role assignments
    at a declared scope). Each removal is gated by ShouldProcess so -WhatIf shows the plan without
    making changes. Top-level objects (groups, catalogs, etc.) are never deleted by the engine.

    .PARAMETER Include
    Restricts the sections the engine dispatches. Defaults to all seven sections. Pass a subset
    to limit the apply run (for example -Include Groups,Catalogs to skip Azure sections).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER IncludeARM
    Acquire an ARM token before dispatching. Required explicitly only if the document does not
    contain Azure sections but ARM is needed for another reason; the engine infers it automatically
    when -Include contains RoleAssignments or RoleManagementPolicies.

    .EXAMPLE
    Invoke-OERStructure -Path ./infra/rbac.json -WhatIf
    Shows what the apply run would do without making any changes to the tenant.

    .EXAMPLE
    Invoke-OERStructure -Path ./infra/rbac.json -Confirm:$false
    Applies the full document to the tenant without per-operation confirmation prompts.

    .EXAMPLE
    Invoke-OERStructure -Json $StructureJson -Include Groups,Catalogs,AccessPackages -Prune
    Applies only the Entra ID sections and removes undeclared child-scope objects.

    .EXAMPLE
    Invoke-OERStructure -Path ./rbac.json -Include RoleAssignments -IncludeARM -Prune
    Applies the role assignments section against Azure, removing undeclared assignments at each
    declared scope.

    .EXAMPLE
    Get-OERInventory | Invoke-OERStructure -WhatIf
    Shows the apply plan for the current tenant inventory without making any changes.

    .EXAMPLE
    Get-ChildItem ./structures/*.json | Invoke-OERStructure -WhatIf
    Shows the apply plan for every JSON file in the folder without making any changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Path')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory)][string]$Path,
        [Parameter(ParameterSetName = 'Json', Mandatory)][string]$Json,
        [Parameter(ParameterSetName = 'InputObject', Mandatory, ValueFromPipeline)]
        [Alias('Inventory', 'Document')]
        [object]$InputObject,
        [switch]$Prune,
        [ValidateSet('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'RoleAssignments', 'RoleManagementPolicies')]
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'RoleAssignments', 'RoleManagementPolicies'),
        [string]$TenantId,
        [switch]$IncludeARM
    )
    process {
        # -- 1. Parse document ----------------------------------------------------------
        $ReadParams = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Path') { $ReadParams.Path = $Path }
        elseif ($PSCmdlet.ParameterSetName -eq 'Json') { $ReadParams.Json = $Json }
        else { $ReadParams.InputObject = $InputObject }
        $DocumentTarget = if ($Path) { $Path } else { $PSCmdlet.ParameterSetName }
        $Document = try {
            Read-OERStructureDocument @ReadParams
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new("Could not read the structure document: $($PSItem.Exception.Message)")) `
                -ErrorId 'InvalidStructureDocument' -Category InvalidData -TargetObject $DocumentTarget -Cmdlet $PSCmdlet
            return
        }

        # -- 2. Validate (abort before any write) ----------------------------------------
        $Validation = Test-OERStructureSchema -Document $Document
        if (-not $Validation.Valid) {
            $Msgs = (@($Validation.Errors | Where-Object { $_.Severity -eq 'Error' }) | ForEach-Object { "$($_.Path): $($_.Message)" }) -join '; '
            Write-CmdletError -Message ([System.Exception]::new("Structure document failed validation: $Msgs")) `
                -ErrorId 'StructureValidationFailed' -Category InvalidData -TargetObject $DocumentTarget -Cmdlet $PSCmdlet
            return
        }

        # -- 3. Resolve tenant alias from document ---------------------------------------
        $TenantAlias = if ($Document.PSObject.Properties.Name -contains 'tenantAlias') { [string]$Document.tenantAlias } else { '' }

        # -- 4. Decide ARM ---------------------------------------------------------------
        # ARM is needed only when an Azure section is BOTH selected via -Include AND actually
        # declared in the document (so a pure-Entra document on the default -Include does not force
        # an ARM token), or when -IncludeARM is explicit.
        $AzureInInclude = ($Include -contains 'RoleAssignments') -or ($Include -contains 'RoleManagementPolicies')
        $AzureInDoc     = ($Document.PSObject.Properties.Name -contains 'roleAssignments') -or
                          ($Document.PSObject.Properties.Name -contains 'roleManagementPolicies')
        $NeedArm        = $IncludeARM -or ($AzureInInclude -and $AzureInDoc)

        # -- 5. Authenticate -------------------------------------------------------------
        $AuthParams = @{}
        if ($TenantId)  { $AuthParams.TenantId   = $TenantId }
        if ($NeedArm)   { $AuthParams.IncludeARM  = $true }
        Initialize-OERAuth @AuthParams

        # -- 6. Dispatch sections in dependency order ------------------------------------
        $Results = [System.Collections.Generic.List[object]]::new()

        # Section map: Include name -> document key -> handler name. This list IS the hardcoded
        # dependency order: groups -> administrativeUnits -> catalogs -> accessPackages ->
        # accessReviews -> roleAssignments -> roleManagementPolicies.
        $SectionOrder = @(
            [PSCustomObject]@{ IncludeName = 'Groups';                 DocKey = 'groups';                 Handler = 'Sync-OERStructureGroup' }
            [PSCustomObject]@{ IncludeName = 'AdministrativeUnits';    DocKey = 'administrativeUnits';    Handler = 'Sync-OERStructureAdministrativeUnit' }
            [PSCustomObject]@{ IncludeName = 'Catalogs';               DocKey = 'catalogs';               Handler = 'Sync-OERStructureCatalog' }
            [PSCustomObject]@{ IncludeName = 'AccessPackages';         DocKey = 'accessPackages';         Handler = 'Sync-OERStructureAccessPackage' }
            [PSCustomObject]@{ IncludeName = 'AccessReviews';          DocKey = 'accessReviews';          Handler = 'Sync-OERStructureAccessReview' }
            [PSCustomObject]@{ IncludeName = 'RoleAssignments';        DocKey = 'roleAssignments';        Handler = 'Sync-OERStructureRoleAssignment' }
            [PSCustomObject]@{ IncludeName = 'RoleManagementPolicies'; DocKey = 'roleManagementPolicies'; Handler = 'Sync-OERStructureRoleManagementPolicy' }
        )

        # Per-scope tracking for the RoleAssignments section, so the scope-wide reconcile/prune pass
        # runs once per declared scope (on the first item of that scope).
        $SeenRaScopes = @{}

        # -- 6a. Pre-pass: ensure an administrative unit a declared group is created INTO -----------
        # A group can be created INTO an administrative unit (New-OERGroup -AdministrativeUnit), but the
        # dispatch order below puts groups first so that AUs can reference groups as members. On a first
        # apply that leaves the AU missing when the group is created, which fails the whole group entry
        # -- members, eligibility and pimPolicy included. Ensure just the AU OBJECTS a group names exist
        # first; their members and scoped roles still reconcile in the administrativeUnits pass below.
        $AuNamesNeeded = [System.Collections.Generic.List[string]]::new()
        if ($Include -contains 'Groups' -and $Include -contains 'AdministrativeUnits' -and
            ($Document.PSObject.Properties.Name -contains 'groups') -and
            ($Document.PSObject.Properties.Name -contains 'administrativeUnits')) {
            foreach ($G in @($Document.groups)) {
                if (Test-OERDeclaredProperty -Node $G -Name 'administrativeUnit') {
                    $AuNamesNeeded.Add([string]$G.administrativeUnit)
                }
            }
        }
        if ($AuNamesNeeded.Count -gt 0) {
            foreach ($AuItem in @($Document.administrativeUnits)) {
                if (@($AuNamesNeeded) -notcontains [string]$AuItem.displayName) { continue }
                try {
                    $Records = Sync-OERStructureAdministrativeUnit -Item $AuItem -Caller $PSCmdlet -EnsureOnly -TenantAlias $TenantAlias
                    foreach ($Rec in @($Records)) { $Results.Add($Rec) }
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    $Results.Add((ConvertTo-OERStructureResult -Section 'administrativeUnits' -Item ([string]$AuItem.displayName) -Action 'Failed' -Detail "pre-pass handler error: $($PSItem.Exception.Message)" -ErrorRecord $PSItem))
                }
            }
        }

        foreach ($Section in $SectionOrder) {
            if ($Include -notcontains $Section.IncludeName) { continue }
            if ($Document.PSObject.Properties.Name -notcontains $Section.DocKey) { continue }
            $Items = @($Document.($Section.DocKey))
            if ($Items.Count -eq 0) { continue }

            foreach ($It in $Items) {
                # RoleAssignments take two extra params so prune is scoped per declared scope.
                $ExtraParams = @{}
                if ($Section.IncludeName -eq 'RoleAssignments') {
                    $ScopeKey = [string]$It.scope
                    $ExtraParams.DeclaredAtScope = @($Items | Where-Object { [string]$_.scope -eq $ScopeKey })
                    $ExtraParams.ReconcileScope  = -not $SeenRaScopes.ContainsKey($ScopeKey)
                    $SeenRaScopes[$ScopeKey] = $true
                }
                try {
                    $Records = & $Section.Handler -Item $It -Caller $PSCmdlet -Prune:$Prune -TenantAlias $TenantAlias @ExtraParams
                    foreach ($Rec in @($Records)) { $Results.Add($Rec) }
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    # Name the item. This used to be the literal '(item)', which lost the identity of
                    # every entry whose handler threw -- exactly the row an operator has to act on,
                    # and unusable in a run over many entries. Most sections identify an entry by
                    # displayName; the two ARM sections carry none and are labelled by role, target
                    # principal and scope, matching what Sync-OERStructureRoleAssignment and
                    # Sync-OERStructureRoleManagementPolicy compose for their own rows. The literal
                    # stays as the last resort, since -Item is a mandatory non-empty string and a
                    # document entry carrying neither field must not turn this catch into a binding
                    # failure that loses the original error.
                    $ItemLabel = [string]$It.displayName
                    if ([string]::IsNullOrWhiteSpace($ItemLabel)) {
                        $ItemRole = [string]$It.role
                        if ($ItemRole) {
                            $ItemLabel = $ItemRole
                            $ItemPrincipal = [string]$It.principal
                            $ItemScope = [string]$It.scope
                            if ($ItemPrincipal) { $ItemLabel = "$ItemLabel -> $ItemPrincipal" }
                            if ($ItemScope) { $ItemLabel = "$ItemLabel @ $ItemScope" }
                        }
                    }
                    if ([string]::IsNullOrWhiteSpace($ItemLabel)) { $ItemLabel = '(item)' }
                    $Results.Add((ConvertTo-OERStructureResult -Section $Section.DocKey -Item $ItemLabel -Action 'Failed' -Detail "handler error: $($PSItem.Exception.Message)" -ErrorRecord $PSItem))
                }
            }
        }

        # -- 7. Verbose summary ----------------------------------------------------------
        $ActionCounts = $Results | Group-Object -Property Action | ForEach-Object { "$($_.Name)=$($_.Count)" }
        Write-Verbose "Invoke-OERStructure complete. $($Results.Count) record(s): $($ActionCounts -join ', ')"

        # -- 8. Emit results -------------------------------------------------------------
        foreach ($R in $Results) { $R }
    }
}
