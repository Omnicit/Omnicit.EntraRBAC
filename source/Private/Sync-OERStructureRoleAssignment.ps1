function Sync-OERStructureRoleAssignment {
    <#
    .SYNOPSIS
    Reconciles one roleAssignments[] document entry against the live Azure tenant.

    .DESCRIPTION
    The orchestration handler for a single role assignment entry from the structure document. It is
    called by the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult
    records describing what was created, removed, skipped, or left unchanged.

    Scope: the engine resolves the scope (see Invoke-OERStructure) and passes the canonical resolved
    scope as -ResolvedScope. The handler never resolves it again and uses that exact string for every
    Azure Resource Manager call and for the at-scope comparison. The scope text the document wrote is
    used only in the labels of this item's rows.

    Per-item processing:
    1. Resolve the principal object id via Resolve-OERStructurePrincipal (returns $null -> Failed + return).
       When the document item has an optional 'principalType' property (User, Group, or ServicePrincipal),
       the type hint is forwarded to Resolve-OERStructurePrincipal via -Type. Without principalType the
       existing heuristic applies: an '@'-containing value triggers a user lookup; anything else triggers
       a group-then-user lookup.
    2. Resolve the full ARM role definition id via Resolve-OERRoleDefinitionId (throws -> Failed + return).
    3. Read current at-scope assignments via Get-OERRoleAssignment -AtScope (throws -> Failed + return).
    4. If a current assignment with matching PrincipalId + role definition exists AND is DEFINED at
       this scope, compare the declared condition, conditionVersion and description against it. The
       role definition matches on its GUID, the last segment of its id, without regard to letter case,
       never on the whole path: a role definition id is anchored at whatever scope it was read from (a
       live assignment at a resource group carries the subscription-anchored id, while the resolver
       anchors a GUID at the scope it was given), whereas a GUID names one role definition everywhere.
       A match reports Unchanged; a difference is applied in place with Set-OERRoleAssignment against the
       existing assignment id and reports Updated. Those three fields are the only ones Azure allows
       editing on an existing assignment, and the engine never deletes a live high-privilege assignment
       to re-create it.
       Scope safety: atScope() returns assignments at AND above the scope, so a principal+role match may
       belong to an ancestor (a subscription- or management group-wide grant inherited here). Such a
       match is NEVER written -- neither updated nor duplicated -- because an in-place edit would rewrite
       the ANCESTOR grant (widening or narrowing access far beyond the declared scope) while reporting
       the declared scope, and a create at this scope -- which Azure Resource Manager would accept, since
       uniqueness is per (scope, principal, role) -- would add a second grant that survives removal of
       the ancestor one. It is reported as a Skipped record naming the ancestor scope and the assignment
       id, with a warning. A current assignment carrying no Scope value at all counts as at-scope, the
       same convention the prune pass below uses.
    5. Otherwise (no assignment for this principal+role anywhere at or above the scope) gate via
       $Caller.ShouldProcess:
       - Under -WhatIf (returns $false): emit Skipped with planned-action Detail.
       - Otherwise: call New-OERRoleAssignment (throws -> Failed; succeeds -> Created inside try),
         forwarding the declared description, condition and conditionVersion (conditionVersion
         defaults to 2.0 when a condition is declared without one).
       Principal type is resolved from the optional 'principalType' document property: ServicePrincipal
       uses -ServicePrincipal; User uses -User; Group uses -Group. Without principalType the heuristic
       applies: an '@'-containing value uses -User; anything else uses -Group (New-OERRoleAssignment
       resolves the friendly value internally).

    Scope-wide prune pass (only when -ReconcileScope is set):
    After reconciling this item the handler resolves the principal and role of every sibling in
    $DeclaredAtScope into a declared '<principal object id>|<role definition GUID>' key set, then
    iterates $Current and compares each assignment against it. The key holds the role definition's
    GUID (the last segment of its id), compared without regard to letter case, never the whole path,
    for the reason step 4 gives. Only assignments DEFINED at this scope are
    considered: atScope() also returns assignments inherited from ancestor scopes (e.g. a subscription
    read includes its parent management groups' assignments), and those are skipped here because they
    belong to the ancestor, are usually declared in the document under that ancestor scope, and cannot
    be removed at this scope. Any remaining current assignment whose principal and role GUID
    composite key is absent from the declared set is treated as undeclared and reported with its own
    identity (role -> principal @ scope) in the result Item:
    - While any sibling is unresolved, or the scope of any entry of the section is (see below): emit
      Skipped with the withheld reason, with or without -Prune. No warning is written, no
      ShouldProcess prompt is issued, nothing is removed.
    - Otherwise, with -Prune: Write-Warning, gate $Caller.ShouldProcess, call Remove-OERRoleAssignment
      -Id <RoleAssignmentId> -Confirm:$false (throws -> Failed + continue), emit Removed.
      Under -WhatIf ShouldProcess returns $false -> emit Skipped.
    - Otherwise, without -Prune: emit Extra (informational).

    A sibling in $DeclaredAtScope whose principal or role lookup gives nothing, or throws, carries no
    key, so the pass cannot tell which live assignment it names -- its own live counterpart would look
    undeclared. Such a sibling therefore withholds the prune for the WHOLE scope: every undeclared
    candidate at this scope is reported Skipped, with a Detail that starts
    "prune withheld: declared entry '<role> -> <principal> @ <scope>' could not be resolved"
    (several: "declared entries '<a>', '<b>' could not be resolved", each in that label form), with
    or without -Prune, and nothing at the scope is removed until that entry is fixed or removed from
    the document (ConvertTo-OERPruneWithheldResult owns the rule and the text). A thrown sibling
    lookup is scrubbed and does not abort the pass, and no error is written for it here: the
    sibling's own invocation of this handler writes its error and reports its Failed record, under
    the same '<role> -> <principal> @ <scope>' label the withheld Detail names, so the rows can be
    correlated.

    An entry ANYWHERE in the section whose SCOPE could not be resolved is a different case. The
    engine never dispatches it, so it is in no -DeclaredAtScope, and it carries no scope: it may be
    another spelling of any scope in the section, and its own live assignment would look undeclared
    in the group of whichever scope it names. The engine therefore hands every dispatched entry the
    labels of those entries as -ScopeUnresolved, and while that list is non-empty every undeclared
    candidate at EVERY scope of the section is reported Skipped, with or without -Prune, with a
    Detail that starts "prune withheld:" and names the entries whose scope could not be resolved:
    "the scope of declared entry '<role> -> <principal> @ <scope>' could not be resolved" for one,
    "the scopes of declared entries '<a>', '<b>' could not be resolved" for several. When an
    unresolved sibling (above) withholds the same candidate, its sentence comes first and the scope
    sentence follows it. The entry keeps its own Failed record, which the engine writes.

    Duplicate entries: two entries of one resolved scope that name the same principal and the same
    role are ONE assignment declared twice. The key is '<principal object id>|<role definition
    GUID>', compared without regard to letter case, and the engine passes the document index of the
    entry (-ItemIndex) and of every entry of the scope (-DeclaredAtScopeIndex). Right after the
    principal and the role are resolved, and before the current assignments are read, an entry whose
    key equals the key of an entry with a LOWER document index is reported Failed -- no error
    record is written, as for an unresolved principal -- with a Detail that names the earlier entry
    by its index and label, and nothing is read or written for it: no create, no in-place update,
    and no prune pass. The earlier entry owns the assignment. The key of the later entry stays in
    the declared set, so the prune pass never removes the assignment. An earlier entry that carries
    no key (its principal or role did not resolve) never counts as a duplicate. The keys of the
    entries of a scope are resolved through one nested function and kept in -SiblingKeyCache, so
    they are looked up at most once per run for both the duplicate check and the prune pass.

    The pass runs only in the invocation for the FIRST item of each resolved scope. When that item's
    own principal, role or current-assignment read fails, the handler returns before the pass: nothing
    at that scope is pruned or reported Extra, and no withheld Skipped rows appear either -- only that
    item's own Failed record.

    Every write is gated by $Caller.ShouldProcess. Reads (Resolve-OERStructurePrincipal,
    Resolve-OERRoleDefinitionId, Get-OERRoleAssignment) always execute even under -WhatIf because they
    provide the diff/plan.

    .PARAMETER Item
    One element from the roleAssignments[] array in the structure document, as a PSCustomObject
    produced by ConvertFrom-Json. Expected properties: scope (string), role (string),
    principal (string). The optional property principalType (User, Group, or ServicePrincipal) enables
    type-directed resolution and controls which switch is passed to New-OERRoleAssignment. The optional
    properties condition, conditionVersion and description carry the ABAC condition and free-text
    description onto a newly created assignment and are compared against an existing one. An explicit
    JSON null on any optional property counts as NOT DECLARED -- the live value is left untouched --
    the same rule the offline validator and the other apply diffs apply.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set (together with -ReconcileScope), undeclared current assignments at the scope are
    removed after a ShouldProcess gate. Without this switch they are only reported as Extra.
    Either way, while a sibling in -DeclaredAtScope could not be resolved (its principal or role
    lookup gave nothing or threw), or an entry anywhere in the section has a scope that could not be
    resolved (-ScopeUnresolved), nothing at the scope is removed or reported Extra: every
    undeclared assignment there is reported Skipped with a Detail starting "prune withheld:", with or
    without this switch.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Currently unused by this handler but
    accepted for a uniform Sync-OERStructure* signature.

    .PARAMETER ResolvedScope
    The canonical Azure Resource Manager scope the engine resolved this item's scope to (see
    Invoke-OERStructure and Resolve-OERStructureRoleAssignmentScope). Every item of one resolved scope
    is handed the same string. The handler never resolves the scope again: it passes this exact
    string to Resolve-OERRoleDefinitionId, Get-OERRoleAssignment and New-OERRoleAssignment, and
    compares a live assignment's scope against it.

    .PARAMETER DeclaredAtScope
    All document roleAssignment items that resolve to this item's scope, this item included (the
    engine groups on the canonical RESOLVED scope, compared without regard to letter case, never on
    the scope text as written in the document). Used by the duplicate check (when -ItemIndex is set)
    and, during the scope-wide prune pass (when -ReconcileScope is set), to build the declared-key
    set. Each element is expected to have
    .principal and .role properties. Defaults to an empty array. One element whose principal or role
    cannot be resolved withholds the prune for the whole scope (see -Prune); that element's Failed
    record comes from its own invocation of this handler.

    .PARAMETER ReconcileScope
    When set, this invocation also performs the scope-wide Extra/prune pass after reconciling its
    own item. The engine sets this flag on the first item of each resolved scope. The pass is not
    reached when this item's own principal, role or current-assignment read fails.

    .PARAMETER ScopeUnresolved
    The labels ('<role> -> <principal> @ <scope>', the scope as the document wrote it) of the
    roleAssignments entries of the whole section whose scope the engine could not resolve, in
    document order. The engine does not dispatch those entries, so none is in -DeclaredAtScope. Each
    may be another spelling of any scope in the section, so while the list is non-empty the scope-wide
    pass withholds every undeclared candidate (see -Prune). Optional, and empty by default.

    .PARAMETER ItemIndex
    The index of this entry in the document's roleAssignments array, which the engine passes. It makes
    the duplicate check run: this entry is Failed when an entry of -DeclaredAtScope with a LOWER
    document index resolves to the same principal and role. Optional; -1 (the default) means the
    caller gave no index, and no duplicate check is made.

    .PARAMETER DeclaredAtScopeIndex
    The document index of each element of -DeclaredAtScope, in the same order (parallel to it), which
    the engine passes. Without it an element's index is its position in -DeclaredAtScope. Optional,
    and empty by default.

    .PARAMETER SiblingKeyCache
    A hashtable the engine hands to every invocation for one resolved scope, so that the keys of the
    entries of -DeclaredAtScope are resolved once per run and shared by the duplicate check and the
    scope-wide prune pass. The handler stores the resolved rows in it under 'Rows'. Without it the
    keys are resolved again by each use. Optional.

    .EXAMPLE
    Sync-OERStructureRoleAssignment -Item $DocItem -Caller $PSCmdlet -ResolvedScope '/subscriptions/00000000-0000-0000-0000-000000000001' -TenantAlias 'omnicit'
    Reconciles one role assignment entry from the document using the engine PSCmdlet as the caller.

    .EXAMPLE
    Sync-OERStructureRoleAssignment -Item $DocItem -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune -ReconcileScope -DeclaredAtScope $SiblingItems
    Reconciles one role assignment and performs the scope-wide prune pass for undeclared extras.

    .EXAMPLE
    Sync-OERStructureRoleAssignment -Item $DocItem -Caller $PSCmdlet -ResolvedScope $ResolvedScope -Prune -ReconcileScope -DeclaredAtScope $SiblingItems -ScopeUnresolved @('Reader -> x @ sub:Gone')
    Reconciles one role assignment, but withholds the prune: the scope of another entry in the section
    could not be resolved, so every undeclared assignment is reported Skipped and none is removed.

    .EXAMPLE
    $KeyCache = @{}
    Sync-OERStructureRoleAssignment -Item $LaterItem -Caller $PSCmdlet -ResolvedScope $ResolvedScope -DeclaredAtScope @($EarlierItem, $LaterItem) -DeclaredAtScopeIndex @(0, 3) -ItemIndex 3 -SiblingKeyCache $KeyCache
    Reports the entry at document index 3 Failed, without reading or writing anything, when it resolves to
    the same principal and role as the entry at index 0.
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
        [Parameter(Mandatory)][string]$ResolvedScope,
        [switch]$Prune,
        [string]$TenantAlias,
        [object[]]$DeclaredAtScope = @(),
        [switch]$ReconcileScope,
        [string[]]$ScopeUnresolved = @(),
        [int]$ItemIndex = -1,
        [int[]]$DeclaredAtScopeIndex = @(),
        [hashtable]$SiblingKeyCache
    )

    process {
        # A property that is present but NULL counts as UNDECLARED, exactly as the offline validator's
        # Test-HasProp and the Resolve-OERRoleManagementPolicyChange / Resolve-OERAccessReviewChange
        # diffs do. The layers have to agree on what "declared" means: Invoke-OERStructure validates
        # with Test-OERStructureSchema (not Test-Json), so an explicit null reaches this handler.
        # Without the guard, "condition": null would cast to '' and CLEAR a live ABAC condition through
        # Set-OERRoleAssignment, which WIDENS the principal's access. An empty string is still a
        # declared value -- it stays the documented "remove the condition" request.
        # Delegates to Test-OERDeclaredProperty, the module's one owner of this rule.
        function Test-DeclHas {
            param([object]$Node, [string]$Name)
            Test-OERDeclaredProperty -Node $Node -Name $Name
        }

        # A role definition id is anchored at whatever scope it was read from: the resolver anchors a
        # GUID at the scope it was given, while Azure Resource Manager reports a live assignment at a
        # resource group with the SUBSCRIPTION-anchored id (measured live) and one at a management
        # group with the tenant-anchored id. The GUID, the last segment of the id, names one role
        # definition everywhere, so the match and the prune key compare that and never the whole path.
        function Get-RoleDefinitionGuid {
            param([string]$RoleDefinitionId)
            ($RoleDefinitionId.TrimEnd('/') -split '/')[-1]
        }

        # The key of every entry of the scope's group, in group order, as
        # [PSCustomObject]@{ Position; DocumentIndex; Label; Key }. Key is '<principal object id>|<role
        # definition GUID>', or $null when the principal or the role of that entry gave nothing or its
        # lookup threw. DocumentIndex is the entry's index in the document's roleAssignments array when
        # the engine passed one (-DeclaredAtScopeIndex, parallel to -DeclaredAtScope), else its
        # position in the group. The duplicate check and the prune pass both read the rows from here,
        # and the engine hands every invocation for one resolved scope the SAME cache, so the group's
        # entries are resolved at most once per run, however many of them are processed.
        function Get-SiblingKeyRow {
            param(
                [object[]]$Declared,
                [int[]]$DocumentIndex,
                [string]$Scope,
                [hashtable]$Cache
            )
            if ($null -ne $Cache -and $Cache.ContainsKey('Rows')) { return $Cache['Rows'] }

            $Rows = [System.Collections.Generic.List[object]]::new()
            $Position = 0
            foreach ($Entry in @($Declared)) {
                $EntryLabel = "$($Entry.role) -> $($Entry.principal) @ $($Entry.scope)"
                $EntryKey = $null
                try {
                    $EntryParams = @{ Reference = $Entry.principal }
                    if (Test-OERDeclaredProperty -Node $Entry -Name 'principalType') { $EntryParams.Type = $Entry.principalType }
                    $EntryPrincipalId = Resolve-OERStructurePrincipal @EntryParams
                    $EntryRole = Resolve-OERRoleDefinitionId -Role $Entry.role -Scope $Scope
                    if ($EntryPrincipalId -and $EntryRole) {
                        $EntryKey = "$EntryPrincipalId|$(Get-RoleDefinitionGuid -RoleDefinitionId $EntryRole)"
                    }
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    # An entry whose lookup throws carries no key, and the rows say so. No error is
                    # written here: the entry's own invocation of this handler writes its own error and
                    # reports its Failed record.
                }
                $EntryDocumentIndex = if ($null -ne $DocumentIndex -and $Position -lt $DocumentIndex.Count) { $DocumentIndex[$Position] } else { $Position }
                $Rows.Add([PSCustomObject]@{
                        Position      = $Position
                        DocumentIndex = $EntryDocumentIndex
                        Label         = $EntryLabel
                        Key           = $EntryKey
                    })
                $Position++
            }
            $Result = $Rows.ToArray()
            if ($null -ne $Cache) { $Cache['Rows'] = $Result }
            $Result
        }

        $Label  = "$($Item.role) -> $($Item.principal) @ $($Item.scope)"
        $Section = 'roleAssignments'
        $PrincipalType = if (Test-DeclHas -Node $Item -Name 'principalType') { [string]$Item.principalType } else { $null }

        # The engine resolved the scope before dispatch (Resolve-OERStructureRoleAssignmentScope) and
        # hands every item of one resolved scope the same canonical string. It is never resolved
        # again here: this exact string goes to every Azure Resource Manager call below and to the
        # at-scope comparisons, so a spelling of the scope can never split one scope in two.
        $RawScope = $ResolvedScope

        # -- 1. Resolve principal id (for diff) --------------------------------------------
        $PrincipalObjId = $null
        $ResolveParams = @{ Reference = $Item.principal }
        if ($PrincipalType) { $ResolveParams.Type = $PrincipalType }
        try {
            $PrincipalObjId = Resolve-OERStructurePrincipal @ResolveParams
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not resolve principal '$($Item.principal)': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }
        if (-not $PrincipalObjId) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "principal '$($Item.principal)' could not be resolved to an object id"
            return
        }

        # -- 2. Resolve role full id (for diff) -------------------------------------------
        $RoleFullId = $null
        try {
            $RoleFullId = Resolve-OERRoleDefinitionId -Role $Item.role -Scope $RawScope
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not resolve role '$($Item.role)' at scope '$RawScope': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }

        $RoleGuid = Get-RoleDefinitionGuid -RoleDefinitionId $RoleFullId

        # -- 2a. A second entry for the same assignment ------------------------------------
        # Two entries of one resolved scope that name the same principal and the same role (the key is
        # '<principal object id>|<role definition GUID>', compared without regard to letter case) are
        # ONE assignment declared twice. The earlier entry (the lower document index) owns it. This one
        # is reported Failed, as a document error and with no error record, and nothing is read or
        # written for it: reconciling it too would let a differing description, condition or
        # conditionVersion on it fight the earlier entry over the same assignment on every run. Its
        # key is still in the cache's rows, so the prune pass keeps the assignment declared and never
        # removes it. An earlier entry that carries no key (its principal or role did not resolve)
        # never matches, so a lookup failure is not mistaken for a duplicate.
        if ($ItemIndex -ge 0) {
            $OwnKey = "$PrincipalObjId|$RoleGuid"
            $Earlier = @(Get-SiblingKeyRow -Declared $DeclaredAtScope -DocumentIndex $DeclaredAtScopeIndex -Scope $RawScope -Cache $SiblingKeyCache |
                    Where-Object { $_.DocumentIndex -lt $ItemIndex -and $null -ne $_.Key -and $_.Key -eq $OwnKey } |
                    Sort-Object -Property DocumentIndex |
                    Select-Object -First 1)
            if ($Earlier.Count -gt 0) {
                ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                    -Detail "roleAssignments[$ItemIndex] resolves to the same assignment as roleAssignments[$($Earlier[0].DocumentIndex)] ('$($Earlier[0].Label)'): the same scope '$RawScope', principal and role. Nothing was written for this entry; keep one of the two entries."
                return
            }
        }

        # -- 3. Read current at-scope assignments once ------------------------------------
        $Current = $null
        try {
            $Current = @(Get-OERRoleAssignment -Scope $RawScope -AtScope)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not read role assignments at scope '$RawScope': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }

        # -- 4. Check existence of THIS item ----------------------------------------------
        # Azure Resource Manager enforces uniqueness on (scope, principal, roleDefinition) whether or
        # not a condition is present, so an assignment is matched on that tuple alone. Only condition,
        # conditionVersion and description are editable on an existing assignment, and only by writing
        # to the SAME roleAssignment id -- which is exactly what Set-OERRoleAssignment does. Drift on
        # those three fields is therefore applied in place and reported as Updated; the engine never
        # deletes and re-creates a live high-privilege assignment to apply a field edit.
        $DeclaredCondition        = if (Test-DeclHas -Node $Item -Name 'condition') { [string]$Item.condition } else { $null }
        $DeclaredConditionVersion = if (Test-DeclHas -Node $Item -Name 'conditionVersion') { [string]$Item.conditionVersion } else { $null }
        $DeclaredDescription      = if (Test-DeclHas -Node $Item -Name 'description') { [string]$Item.description } else { $null }

        # Only an assignment DEFINED at this scope is a candidate for an in-place edit. atScope() also
        # returns assignments inherited from ancestor scopes, and Set-OERRoleAssignment writes to the
        # assignment id -- so updating an ancestor-owned match would rewrite the ancestor's grant while
        # the result reported the declared (child) scope. Same predicate as the prune pass below: a
        # current object with no Scope value counts as at-scope, because ConvertTo-OERRoleAssignment
        # always projects the ARM scope and only a scope-less fixture can reach this.
        # The role matches on its GUID, compared without regard to letter case (-eq), never on the whole
        # id: the live assignment's id may be anchored at a different scope than the one resolved above.
        $Matching  = @($Current | Where-Object { $_.PrincipalId -eq $PrincipalObjId -and (Get-RoleDefinitionGuid -RoleDefinitionId ([string]$_.RoleDefinitionId)) -eq $RoleGuid })
        $Existing  = $Matching | Where-Object { (-not $_.Scope) -or ([string]$_.Scope -eq $RawScope) } | Select-Object -First 1
        $Inherited = $null
        if (-not $Existing) { $Inherited = $Matching | Select-Object -First 1 }

        if ($Existing) {
            $Drift = [System.Collections.Generic.List[string]]::new()
            if ($null -ne $DeclaredCondition -and ([string]$Existing.Condition) -ne $DeclaredCondition) {
                $Drift.Add("condition (live '$([string]$Existing.Condition)', declared '$DeclaredCondition')")
            }
            if ($null -ne $DeclaredConditionVersion -and ([string]$Existing.ConditionVersion) -ne $DeclaredConditionVersion) {
                $Drift.Add("conditionVersion (live '$([string]$Existing.ConditionVersion)', declared '$DeclaredConditionVersion')")
            }
            if ($null -ne $DeclaredDescription -and ([string]$Existing.Description) -ne $DeclaredDescription) {
                $Drift.Add("description (live '$([string]$Existing.Description)', declared '$DeclaredDescription')")
            }

            if ($Drift.Count -gt 0) {
                # Only condition, conditionVersion and description are editable on an existing
                # assignment, and only by writing to the SAME assignment id -- which is exactly what
                # Set-OERRoleAssignment does. The engine never deletes and re-creates a live
                # high-privilege assignment to apply a field edit.
                if (-not $Caller.ShouldProcess($RawScope, "Update role assignment '$($Item.role)' for '$($Item.principal)' ($($Drift -join '; '))")) {
                    ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Skipped' `
                        -Detail "would update role assignment at '$RawScope' -- differs on $($Drift -join '; ')"
                } else {
                    $SetParams = @{ Id = $Existing.RoleAssignmentId; Confirm = $false }
                    if ($null -ne $DeclaredDescription)      { $SetParams.Description = $DeclaredDescription }
                    if ($null -ne $DeclaredCondition)        { $SetParams.Condition = $DeclaredCondition }
                    if ($null -ne $DeclaredConditionVersion) { $SetParams.ConditionVersion = $DeclaredConditionVersion }
                    try {
                        $null = Set-OERRoleAssignment @SetParams -ErrorAction Stop
                        ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Updated' `
                            -Detail "updated role assignment at '$RawScope' -- $($Drift -join '; ')"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                            -Detail "failed to update role assignment: $($PSItem.Exception.Message)" `
                            -ErrorRecord $PSItem
                    }
                }
            } else {
                ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Unchanged' `
                    -Detail "role assignment already exists at '$RawScope'"
            }
        } elseif ($Inherited) {
            # The principal+role matches, but the assignment is DEFINED at an ancestor scope. Nothing is
            # written, in either direction:
            #  - Set-OERRoleAssignment writes to the assignment id, so an in-place edit here would change
            #    the ANCESTOR grant (for example rewriting a subscription-wide ABAC condition) while the
            #    result claimed the resource group the document declared.
            #  - New-OERRoleAssignment at this scope would succeed (Azure Resource Manager's uniqueness
            #    rule is per (scope, principal, role)), but it would add a second, narrower grant that
            #    outlives removal of the ancestor one -- a durable access change nobody asked for.
            # The drift is therefore surfaced as a visible Skipped record naming the ancestor, never as
            # a misleading Updated or a silent Unchanged.
            $AncestorScope = [string]$Inherited.Scope
            Write-Warning "Sync-OERStructureRoleAssignment: '$($Item.role)' for '$($Item.principal)' is not defined at '$RawScope' -- it is inherited from the ancestor scope '$AncestorScope'. Nothing was written; declare this entry under scope '$AncestorScope' to manage it there."
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Skipped' `
                -Detail "no role assignment is defined at '$RawScope': the principal holds this role here through the assignment defined at the ancestor scope '$AncestorScope' ($($Inherited.RoleAssignmentId)). Nothing was written -- editing that assignment would change the ancestor grant, and creating one here would add a grant that survives removal of the ancestor. Declare this entry under scope '$AncestorScope' to manage it"
        } else {
            # -- 5. Create (absent) -------------------------------------------------------
            if (-not $Caller.ShouldProcess($RawScope, "Create role assignment '$($Item.role)' for '$($Item.principal)'")) {
                ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Skipped' `
                    -Detail "would create role assignment '$($Item.role)' for '$($Item.principal)' at '$RawScope'"
            } else {
                $NewParams = @{ Role = $Item.role; Scope = $RawScope; Confirm = $false }
                # Choose -ServicePrincipal/-User/-Group based on principalType or the @ heuristic
                if ($PrincipalType -eq 'ServicePrincipal') {
                    $NewParams.ServicePrincipal = $Item.principal
                } elseif ($PrincipalType -eq 'User') {
                    $NewParams.User = $Item.principal
                } elseif ($PrincipalType -eq 'Group') {
                    $NewParams.Group = $Item.principal
                } elseif ($Item.principal -like '*@*') {
                    $NewParams.User = $Item.principal
                } else {
                    $NewParams.Group = $Item.principal
                }
                if ($null -ne $DeclaredDescription) { $NewParams.Description = $DeclaredDescription }
                if ($null -ne $DeclaredCondition) {
                    $NewParams.Condition = $DeclaredCondition
                    # ARM defaults conditionVersion to 2.0 when a condition is supplied without one.
                    $NewParams.ConditionVersion = $(if ($null -ne $DeclaredConditionVersion) { $DeclaredConditionVersion } else { '2.0' })
                }
                try {
                    $null = New-OERRoleAssignment @NewParams -ErrorAction Stop
                    ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Created' `
                        -Detail "created role assignment '$($Item.role)' for '$($Item.principal)' at '$RawScope'"
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Caller.WriteError($PSItem)
                    ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                        -Detail "failed to create role assignment: $($PSItem.Exception.Message)" `
                        -ErrorRecord $PSItem
                }
            }
        }

        # -- Scope-wide prune/extra pass (only when -ReconcileScope) ----------------------
        if (-not $ReconcileScope) { return }

        # Build the declared key set from all $DeclaredAtScope siblings, through Get-SiblingKeyRow: the
        # same rows the duplicate check read, resolved at most once per run. A sibling whose principal
        # or role cannot be resolved, or whose lookup throws, carries no key, so it cannot protect its
        # own live assignment from the candidate loop below. It is recorded in $SiblingUnresolved
        # instead, under the sibling's own result label, and while that list is non-empty every
        # candidate at this scope is withheld (ConvertTo-OERPruneWithheldResult owns that rule) rather
        # than reported Extra or removed. A thrown lookup does not abort the pass, and no error is
        # written for it here: the sibling's own invocation writes its own error and Failed record.
        # $ScopeUnresolved (the engine's labels of entries whose SCOPE did not resolve, which it never
        # dispatches) withholds the same way: such an entry may name any scope in the section.
        $DeclaredKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $SiblingUnresolved = [System.Collections.Generic.List[string]]::new()
        foreach ($SiblingRow in @(Get-SiblingKeyRow -Declared $DeclaredAtScope -DocumentIndex $DeclaredAtScopeIndex -Scope $RawScope -Cache $SiblingKeyCache)) {
            if ($null -ne $SiblingRow.Key) {
                $null = $DeclaredKeys.Add($SiblingRow.Key)
            } else {
                $SiblingUnresolved.Add($SiblingRow.Label)
            }
        }

        foreach ($Cur in $Current) {
            # Only assignments DEFINED at this scope are candidates. atScope() also returns
            # assignments inherited from ancestor scopes (a subscription read includes its parent
            # management groups' assignments); those belong to the ancestor, are typically declared in
            # the document under THAT scope, and cannot be removed here -- so flagging them Extra/prune
            # against this scope's declared set is a false positive. Skip anything not owned by $RawScope.
            if ($Cur.Scope -and ($Cur.Scope -ne $RawScope)) { continue }

            $CurKey = "$($Cur.PrincipalId)|$(Get-RoleDefinitionGuid -RoleDefinitionId ([string]$Cur.RoleDefinitionId))"
            if ($DeclaredKeys.Contains($CurKey)) { continue }

            # Each undeclared assignment gets its OWN Item label (role leaf -> principal @ scope) so the
            # results table shows distinct rows instead of repeating the triggering declared item.
            $CurRoleLeaf = ($Cur.RoleDefinitionId -split '/')[-1]
            $ExtraItem   = "$CurRoleLeaf -> $($Cur.PrincipalId) @ $($Cur.Scope)"
            $CurLabel    = "undeclared assignment '$($Cur.RoleDefinitionId)' for principal '$($Cur.PrincipalId)'"
            $Withheld = ConvertTo-OERPruneWithheldResult -Section $Section -Item $ExtraItem -Unresolved $SiblingUnresolved -UnresolvedScope $ScopeUnresolved -Candidate $CurLabel
            if ($Withheld) { $Withheld; continue }
            if ($Prune) {
                $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                Write-Warning "Sync-OERStructureRoleAssignment: $PruneVerb $CurLabel at scope '$RawScope'."
                if ($Caller.ShouldProcess($RawScope, "Remove undeclared role assignment '$($Cur.RoleAssignmentId)'")) {
                    try {
                        $null = Remove-OERRoleAssignment -Id $Cur.RoleAssignmentId -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop
                        ConvertTo-OERStructureResult -Section $Section -Item $ExtraItem -Action 'Removed' `
                            -Detail "removed $CurLabel"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section $Section -Item $ExtraItem -Action 'Failed' `
                            -Detail "failed to remove $CurLabel`: $($PSItem.Exception.Message)" `
                            -ErrorRecord $PSItem
                        continue
                    }
                } else {
                    ConvertTo-OERStructureResult -Section $Section -Item $ExtraItem -Action 'Skipped' `
                        -Detail "would remove $CurLabel"
                }
            } else {
                ConvertTo-OERStructureResult -Section $Section -Item $ExtraItem -Action 'Extra' `
                    -Detail "$CurLabel (use -Prune to remove)"
            }
        }
    }
}
