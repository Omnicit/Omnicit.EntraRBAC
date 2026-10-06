function Invoke-OERStructure {
    <#
    .SYNOPSIS
    Applies a Phase 5 structure document to a live Entra ID (and optionally Azure) tenant.

    .DESCRIPTION
    The top-level apply engine for Phase 5 JSON Orchestration. Reads a structure document from
    -Path or -Json, validates it offline with Test-OERStructureSchema (aborting before any write
    if invalid), authenticates, then iterates every declared section in dependency order --
    Groups, AdministrativeUnits, Catalogs, AccessPackages, AccessReviews,
    DirectoryRoleManagementPolicies, DirectoryRoleAssignments, RoleAssignments, RoleManagementPolicies
    -- and calls the matching Sync-OERStructure* handler for each item.

    Dependency order: Groups must exist before AUs can reference them as members; Catalogs before
    AccessPackages; the PIM settings of Microsoft Entra directory roles before the directory role
    assignments, so a policy that must allow a permanent assignment is applied first; all Entra sections,
    both directory role sections included, before the Azure sections that may reference Entra objects.
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
    deletes a top-level object (a group, catalog, etc.) that is absent from the document. A declared
    entry that cannot be resolved withholds the prune of its collection: every undeclared live entry
    in it is reported Skipped with a Detail starting "prune withheld:", with or without -Prune,
    instead of being removed or reported Extra. A group's service principal, as a member or an
    owner, is never removed (see -Prune). An OMITTED members, scopedRoles, resources or
    resourceRoles key still prunes, so before the first write the engine lists every such key in one
    warning (see -Prune).

    WhatIf plan mode (-WhatIf): handlers receive the engine's $PSCmdlet as -Caller and read
    ShouldProcess from it. Under -WhatIf all writes return Skipped results; reads (diff queries)
    still execute so the plan is complete. The engine does NOT call ShouldProcess itself.

    Include filter (-Include): only sections listed in -Include are dispatched. Sections whose
    key is absent from the document or whose array is empty are also silently skipped.

    ARM sections: RoleAssignments and RoleManagementPolicies require an ARM token. If either is
    selected (via -Include) or -IncludeARM is explicitly set, Initialize-OERAuth is called with
    -IncludeARM so the ARM token is acquired up front. For a pure Entra document that does not
    include those sections and does not pass -IncludeARM, no ARM token is requested.
    DirectoryRoleManagementPolicies and DirectoryRoleAssignments are NOT ARM sections: the PIM settings
    and the eligible and active assignments of a Microsoft Entra directory role are applied through
    Microsoft Graph only, so a document holding either section never requests an ARM token on its
    account.

    Pipeline session rule: without -TenantId the command acts only under the session it began with.
    A document is refused with SignInSuperseded, and nothing is signed in to or sent for it, when
    another command in the same pipeline signed in to a different tenant or identity, or
    disconnected, after this command began and before the document was processed -- for example
    Connect-OER, or a cmdlet naming another tenant, downstream of this command (every begin block of
    a pipeline runs before this command's process block, where it signs in), or a sign-in made
    upstream in the process block that emits the document. When the module held no session as this
    command began, any such sign-in counts, even one that names no tenant. Run such commands as
    separate statements. A document that cannot be read or does not validate reports its own error,
    as before. Several documents piped into one call are each compared with the session the last
    sign-in of this call left, whether that sign-in succeeded or was refused, or, before its first
    sign-in, with the session the call began with. So a first sign-in from no session does not refuse
    the next document, while a document refused with SignInSuperseded, or one that could not be read
    or did not validate, signs nothing in and moves nothing: the document after it is compared with
    the same session. With -TenantId the command signs in to that tenant as before.

    RoleAssignments scope grouping: before the first role assignment item is dispatched, the engine
    resolves every item's scope once (Resolve-OERStructureRoleAssignmentScope) and groups the items on
    the canonical RESOLVED scope, compared without regard to letter case -- never on the scope text
    the document wrote, so 'sub:<id>', 'subscription:<id>', '/subscriptions/<id>', a subscription's
    name, 'mg:<name>', 'mg:<displayName>' and the management group path are one scope. A scope
    written with a trailing '/' (other than '/' itself) or with '//' is not a spelling of another
    scope: the offline validation refuses the whole document before anything is resolved, so such a
    scope is never merged or pruned. Every item of a group is handed the same canonical resolved
    scope (-ResolvedScope), and -ReconcileScope is passed on the first item of each resolved scope,
    which signals the handler to run its prune pass for that scope after processing the item. A
    failed read of the live assignments at a scope reports the item Failed, with the read error
    published as itself, and no prune pass runs for that scope. An item whose scope cannot be
    resolved is reported Failed by the engine itself, with its error published as itself, and is not
    dispatched; its label is handed to every dispatched item, which withholds the prune of the whole
    section (see -Prune). Two entries that resolve to the same scope, principal and role are one
    assignment declared twice: the engine hands each item its document index, the document index of
    every item of its scope and one key cache per scope, and the handler reports the LATER entry
    Failed, naming the earlier one, without reading or writing anything for it. The earlier entry
    owns the assignment, and the prune never removes it. An explicit "roleAssignments": null is not
    declared: the section is skipped like an absent key, and the pre-pass never runs for it.

    DirectoryRoleAssignments section pass: the engine passes every directoryRoleAssignments entry to
    each invocation of its handler and sets -ReconcileSection on the first item only, so the handler
    runs its section-wide prune pass once, before that first item is reconciled and whatever that
    item's own outcome (see -Prune for what the pass may remove). When one principal holds both an
    eligible and an active assignment of a directory role and the engine updates one of them,
    Microsoft Graph may remove the other by itself (measured live); the next run creates it again, so
    a document that declares both kinds for one principal and role can need two runs to converge.

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

    A declared entry that cannot be resolved (for example a member whose principal lookup finds no
    object) withholds the prune of its whole collection, since its live counterpart cannot be told
    apart from an undeclared entry: every undeclared live entry in that collection is left in place and
    reported Skipped with a Detail starting "prune withheld:", with or without -Prune (instead of
    Extra when -Prune is not set), while the unresolved entry keeps its own Failed record. Fix or
    remove the unresolved entry to reconcile the collection.

    A service principal that is a member or an owner of a group is never removed. Microsoft Graph's
    v1.0 member and owner lists leave service principals out, so no earlier version of this module
    saw one in a group or pruned one, and no document an earlier version exported lists one. An
    undeclared service principal is therefore reported Extra without -Prune, and Skipped with a
    Detail starting "prune withheld:" with -Prune, with no warning and no ShouldProcess prompt; every
    other member and owner is pruned as described here. Remove one with Remove-OERGroupMember when
    it is meant to go.

    A roleAssignments entry whose SCOPE cannot be resolved withholds the prune of the whole
    roleAssignments section, not only of one scope: it may be another spelling of any scope in the
    section, so every undeclared live assignment at every scope is reported Skipped (with or without
    -Prune) with a Detail starting "prune withheld:" that names the entry, or the entries, whose scope
    could not be resolved (in a second sentence, after the one naming an unresolved sibling, when
    such a sibling withholds the same assignment too), and none is removed.

    directoryRoleAssignments is reconciled per pair of directory role and assignmentType, and only
    for the pairs the document declares: a directory role the document does not name, or names only
    for the other assignmentType, is never read or touched. An activation of an eligible assignment,
    a member's assignment inherited through a group and one scoped to an administrative unit are never
    counted and never removed, and neither is any direct assignment of the signed-in identity itself
    (reported Skipped); while that identity's object id cannot be determined, nothing in the section
    is removed. A role-assignable group's own direct assignment is a candidate: when the document
    declares a pair without that group, -Prune removes the group's assignment and with it the role of
    every member who holds it through the group -- unless the signed-in identity is a member of that
    group, directly or through nesting, in which case the assignment is left in place and reported
    Skipped. When the signed-in identity's group memberships cannot be read, every group (or
    unknown-type) candidate is withheld the same way. There the unit of the rule above is the pair:
    an entry whose principal cannot be resolved withholds the prune of its own pair, and an entry
    whose role cannot be resolved withholds every pair of its assignmentType. A pair whose live read
    fails is reported Failed, and nothing in it is removed or reported Extra.

    Five collections are reconciled even when their key is omitted, against an empty declared set,
    so -Prune removes every live entry in them (a group's service principals excepted, as above):
    groups[].members, administrativeUnits[].members, administrativeUnits[].scopedRoles,
    catalogs[].resources and accessPackages[].resourceRoles. When
    -Prune is set, one warning lists every such omitted key in a section selected by -Include before
    anything is written, under -WhatIf too. Declare the key (an empty array removes the entries
    deliberately), or set it to null to leave that collection untouched. The members key of a group
    or administrative unit the document declares "dynamic": true is not listed, since the handlers
    skip the member prune on a dynamic object. The exclusion trusts the document's dynamic flag: a
    group declared dynamic whose live group is static (Set-OERGroup cannot convert it), or an
    administrative unit whose conversion to dynamic is not applied in this run (-WhatIf, a declined
    prompt, a failed update, or no membershipRule available), still has its omitted members pruned,
    and this warning does not list them. Test-OERStructure reports the same omissions as Warning
    findings.

    .PARAMETER Include
    Restricts the sections the engine dispatches. Defaults to all nine sections. Pass a subset
    to limit the apply run (for example -Include Groups,Catalogs to skip Azure sections).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth. Without it
    the command acts only under the session it began with (see the pipeline session rule above).

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
        [ValidateSet('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments', 'RoleManagementPolicies')]
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews', 'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments', 'RoleManagementPolicies'),
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,
        [switch]$IncludeARM
    )
    begin {
        # SEC (BL-76): the session this command began with. Every begin block in a pipeline runs before
        # any process block, so this snapshot holds the module's sign-in identity from before any LATER
        # command in the pipeline signed in. This command signs in in its process block; without
        # -TenantId that sign-in inherits whatever session the module holds by then, so a downstream
        # command's begin block (Connect-OER, or any cmdlet naming another tenant) would otherwise
        # switch it -- and this command's document, -Prune deletions included, would go to that tenant
        # with no error (A20 cannot see it: the inherited sign-in remembers the switched identity).
        # Checkpoint-OERSignIn owns the snapshot (A6: the tenant is never re-named as -TenantId here).
        $SignInSnapshot = Checkpoint-OERSignIn
    }
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
        # an ARM token), or when -IncludeARM is explicit. directoryRoleManagementPolicies and
        # directoryRoleAssignments are deliberately absent from both tests: directory-role PIM
        # settings and directory role assignments are Graph-only.
        $AzureInInclude = ($Include -contains 'RoleAssignments') -or ($Include -contains 'RoleManagementPolicies')
        $AzureInDoc     = ($Document.PSObject.Properties.Name -contains 'roleAssignments') -or
                          ($Document.PSObject.Properties.Name -contains 'roleManagementPolicies')
        $NeedArm        = $IncludeARM -or ($AzureInInclude -and $AzureInDoc)

        # -- 5. Authenticate -------------------------------------------------------------
        $AuthParams = @{}
        if ($TenantId)  { $AuthParams.TenantId   = $TenantId }
        if ($NeedArm)   { $AuthParams.IncludeARM  = $true }
        # SEC (BL-76): without -TenantId, act only under the session this command began with (see
        # begin). A changed identity -- another tenant, application, method or cloud, or none at all
        # -- refuses this document with SignInSuperseded before anything is signed in to or sent. With
        # -TenantId nothing changes: the sign-in names its tenant, and A20 refuses the requests of
        # whichever command's sign-in that replaced.
        if (-not $TenantId -and (Checkpoint-OERSignIn -ChangedSince $SignInSnapshot)) {
            $PSCmdlet.WriteError((New-OERSignInSupersededError -Command $PSCmdlet.MyInvocation.MyCommand.Name))
            return
        }
        Initialize-OERAuth @AuthParams
        # The next piped document compares with the session this one signed in under: a first sign-in
        # from no session must not refuse the second document. Taken after every sign-in, refused or
        # not: without -TenantId a refused sign-in leaves the identity as it was, or sets the one this
        # command itself asked for.
        $SignInSnapshot = Checkpoint-OERSignIn

        # -- 6. Dispatch sections in dependency order ------------------------------------
        $Results = [System.Collections.Generic.List[object]]::new()

        # Section map: Include name -> document key -> handler name. This list IS the hardcoded
        # dependency order: groups -> administrativeUnits -> catalogs -> accessPackages ->
        # accessReviews -> directoryRoleManagementPolicies -> directoryRoleAssignments ->
        # roleAssignments -> roleManagementPolicies. The directory-role policies run after everything
        # their approvers may name, and before the directory role assignments, so a policy that must
        # allow a permanent assignment is in place first. The directory role assignments are the last
        # Entra (Graph) section, before the Azure sections.
        $SectionOrder = @(
            [PSCustomObject]@{ IncludeName = 'Groups';                          DocKey = 'groups';                          Handler = 'Sync-OERStructureGroup' }
            [PSCustomObject]@{ IncludeName = 'AdministrativeUnits';             DocKey = 'administrativeUnits';             Handler = 'Sync-OERStructureAdministrativeUnit' }
            [PSCustomObject]@{ IncludeName = 'Catalogs';                        DocKey = 'catalogs';                        Handler = 'Sync-OERStructureCatalog' }
            [PSCustomObject]@{ IncludeName = 'AccessPackages';                  DocKey = 'accessPackages';                  Handler = 'Sync-OERStructureAccessPackage' }
            [PSCustomObject]@{ IncludeName = 'AccessReviews';                   DocKey = 'accessReviews';                   Handler = 'Sync-OERStructureAccessReview' }
            [PSCustomObject]@{ IncludeName = 'DirectoryRoleManagementPolicies'; DocKey = 'directoryRoleManagementPolicies'; Handler = 'Sync-OERStructureDirectoryRoleManagementPolicy' }
            [PSCustomObject]@{ IncludeName = 'DirectoryRoleAssignments';        DocKey = 'directoryRoleAssignments';        Handler = 'Sync-OERStructureDirectoryRoleAssignment' }
            [PSCustomObject]@{ IncludeName = 'RoleAssignments';                 DocKey = 'roleAssignments';                 Handler = 'Sync-OERStructureRoleAssignment' }
            [PSCustomObject]@{ IncludeName = 'RoleManagementPolicies';          DocKey = 'roleManagementPolicies';          Handler = 'Sync-OERStructureRoleManagementPolicy' }
        )

        # The DirectoryRoleAssignments prune pass is section-wide: it runs once, on the first item.
        $DraReconciled = $false

        # -- Before the first write: omitted collection keys that -Prune still reconciles ------------
        # Five collections are reconciled against an empty declared set when their key is omitted, so
        # -Prune removes every live entry in them. Get-OEROmittedPruneCollection owns which keys those
        # are; list the ones in a section -Include selects, once, before the pre-pass below -- the first
        # code that can write. -WhatIf included, since that is where an operator reads the plan.
        if ($Prune) {
            $PruneDocKey = @($SectionOrder | Where-Object { $Include -contains $_.IncludeName } | ForEach-Object { $_.DocKey })
            $Omitted = @(Get-OEROmittedPruneCollection -Document $Document | Where-Object { $PruneDocKey -contains $_.Section })
            if ($Omitted.Count -gt 0) {
                $Verb = if ($WhatIfPreference) { 'would be removed' } else { 'will be removed' }
                Write-Warning "Invoke-OERStructure: -Prune is set and the document omits $($Omitted.Count) collection key(s) that are still reconciled when omitted, so every live entry in them $Verb`: $(($Omitted | ForEach-Object { "$($_.Section) '$($_.Item)' $($_.Collection)" }) -join '; '). Declare each key (an empty array removes the entries deliberately), or set it to null to leave that collection untouched."
            }
        }

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
            # An explicit top-level "roleAssignments": null is not declared (the validator says so),
            # yet @($null) is one element. The scope pre-pass below cannot take a null entry, and it
            # runs outside the per-entry try/catch, so drop the null here and skip the section when
            # nothing is left. Only this section: every other handler runs inside the per-entry catch.
            if ($Section.IncludeName -eq 'RoleAssignments') {
                $Items = @($Items | Where-Object { $null -ne $_ })
            }
            if ($Items.Count -eq 0) { continue }

            # roleAssignments: every entry's scope is resolved ONCE, before the first entry is
            # dispatched, and the entries are grouped on the canonical RESOLVED scope, compared without
            # regard to letter case -- never on the text the document wrote. sub:<id>, subscription:<id>,
            # /subscriptions/<id>, a subscription's name, mg:<name>, mg:<displayName> and the management
            # group path are all one scope, so their entries form one group with one prune pass. A
            # scope with a trailing '/' or with '//' never gets here: Test-OERStructureSchema refused
            # the document above (A15). Every entry of a group is handed the same string, the group's
            # first canonical scope, which the handler uses for every Azure Resource Manager call.
            #
            # An entry whose scope cannot be resolved is not dispatched and belongs to no group, yet it
            # may be another spelling of ANY scope in the section: its own live assignment would look
            # undeclared in the group of whichever scope it names. The labels of those entries
            # ($RaScopeUnresolved, in document order) are therefore handed to every dispatched entry,
            # and the prune of the whole section is withheld while the list is non-empty.
            $RaScope = @()
            $RaGroup = $null
            $RaScopeUnresolved = @()
            if ($Section.IncludeName -eq 'RoleAssignments') {
                $RaScope = @(Resolve-OERStructureRoleAssignmentScope -Item $Items)
                $RaScopeUnresolved = @($RaScope | Where-Object { $null -eq $_.Scope } | ForEach-Object { $_.Label })
                $RaGroup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($RaEntry in $RaScope) {
                    if ($null -eq $RaEntry.Scope) { continue }
                    if (-not $RaGroup.ContainsKey($RaEntry.Scope)) {
                        $RaGroup[$RaEntry.Scope] = [PSCustomObject]@{
                            Scope      = $RaEntry.Scope
                            Items      = [System.Collections.Generic.List[object]]::new()
                            Indices    = [System.Collections.Generic.List[int]]::new()
                            Reconciled = $false
                            KeyCache   = @{}
                        }
                    }
                    $RaGroup[$RaEntry.Scope].Items.Add($RaEntry.Item)
                    $RaGroup[$RaEntry.Scope].Indices.Add($RaEntry.Index)
                }
            }

            for ($ItemIndex = 0; $ItemIndex -lt $Items.Count; $ItemIndex++) {
                $It = $Items[$ItemIndex]
                # RoleAssignments take extra params so prune is scoped per resolved scope, and so the
                # handler can tell that an entry is a second spelling of an earlier one: the entry's
                # own document index, the document index of every entry of its scope, and ONE key
                # cache per scope, shared by every entry of it, so the scope's entries are resolved
                # once per run for both the duplicate check and the prune pass.
                # DirectoryRoleAssignments take the whole section, and the prune pass runs on the
                # first item only, whatever that item's own outcome.
                $ExtraParams = @{}
                if ($Section.IncludeName -eq 'RoleAssignments') {
                    $RaEntry = $RaScope[$ItemIndex]
                    if ($null -eq $RaEntry.Scope) {
                        # The entry's own row, exactly as the handler wrote it when it resolved the
                        # scope itself: the record is published as itself, and the entry is not
                        # dispatched.
                        $PSCmdlet.WriteError($RaEntry.ErrorRecord)
                        $Results.Add((ConvertTo-OERStructureResult -Section $Section.DocKey -Item $RaEntry.Label -Action 'Failed' `
                                    -Detail "could not resolve scope '$($RaEntry.RawScope)': $($RaEntry.ErrorRecord.Exception.Message)" `
                                    -ErrorRecord $RaEntry.ErrorRecord))
                        continue
                    }
                    $RaGroupOfItem = $RaGroup[$RaEntry.Scope]
                    $ExtraParams.ResolvedScope   = $RaGroupOfItem.Scope
                    $ExtraParams.DeclaredAtScope = @($RaGroupOfItem.Items)
                    $ExtraParams.ReconcileScope  = -not $RaGroupOfItem.Reconciled
                    $ExtraParams.ScopeUnresolved = $RaScopeUnresolved
                    $ExtraParams.ItemIndex            = $ItemIndex
                    $ExtraParams.DeclaredAtScopeIndex = @($RaGroupOfItem.Indices)
                    $ExtraParams.SiblingKeyCache      = $RaGroupOfItem.KeyCache
                    $RaGroupOfItem.Reconciled = $true
                }
                if ($Section.IncludeName -eq 'DirectoryRoleAssignments') {
                    $ExtraParams.DeclaredInSection = $Items
                    $ExtraParams.ReconcileSection  = -not $DraReconciled
                    $DraReconciled = $true
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
                    # Sync-OERStructureRoleManagementPolicy compose for their own rows. A
                    # directoryRoleManagementPolicies entry carries only role, so the same branch
                    # labels it by role alone, as Sync-OERStructureDirectoryRoleManagementPolicy
                    # labels its own rows. A directoryRoleAssignments entry carries role, principal and
                    # assignmentType, and gets '<role> -> <principal> (<assignmentType>)', the label
                    # Sync-OERStructureDirectoryRoleAssignment writes on its own rows. The literal
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
                            $ItemKind = [string]$It.assignmentType
                            if ($ItemKind) { $ItemLabel = "$ItemLabel ($ItemKind)" }
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
