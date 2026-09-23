function Sync-OERStructureRoleAssignment {
    <#
    .SYNOPSIS
    Reconciles one roleAssignments[] document entry against the live Azure tenant.

    .DESCRIPTION
    The orchestration handler for a single role assignment entry from the structure document. It is
    called by the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult
    records describing what was created, removed, skipped, or left unchanged.

    Scope DSL: the document scope field is parsed into an ARM scope by a nested Get-ScopeSplat
    helper before passing to Resolve-OERScope.
    - 'mg:<name>' or 'mg:<displayName>' -> -ManagementGroup <name>
    - 'subscription:<name>'/'sub:<name>' -> -Subscription <name>
    - Any other value starting with '/' -> -Scope <raw> (passed through)

    Per-item processing:
    1. Resolve the ARM scope via Get-ScopeSplat + Resolve-OERScope (throws -> Failed + return).
    2. Resolve the principal object id via Resolve-OERStructurePrincipal (returns $null -> Failed + return).
       When the document item has an optional 'principalType' property (User, Group, or ServicePrincipal),
       the type hint is forwarded to Resolve-OERStructurePrincipal via -Type. Without principalType the
       existing heuristic applies: an '@'-containing value triggers a user lookup; anything else triggers
       a group-then-user lookup.
    3. Resolve the full ARM role definition id via Resolve-OERRoleDefinitionId (throws -> Failed + return).
    4. Read current at-scope assignments via Get-OERRoleAssignment -AtScope (throws -> Failed + return).
    5. If a current assignment with matching PrincipalId + RoleDefinitionId exists AND is DEFINED at
       this scope, compare the declared condition, conditionVersion and description against it. A match
       reports Unchanged; a difference is applied in place with Set-OERRoleAssignment against the
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
    6. Otherwise (no assignment for this principal+role anywhere at or above the scope) gate via
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
    $DeclaredAtScope into a declared 'PrincipalId|RoleDefinitionId' key set, then iterates $Current
    and compares each assignment against it. Only assignments DEFINED at this scope are
    considered: atScope() also returns assignments inherited from ancestor scopes (e.g. a subscription
    read includes its parent management groups' assignments), and those are skipped here because they
    belong to the ancestor, are usually declared in the document under that ancestor scope, and cannot
    be removed at this scope. Any remaining current assignment whose 'PrincipalId|RoleDefinitionId'
    composite key is absent from the declared set is treated as undeclared and reported with its own
    identity (role -> principal @ scope) in the result Item:
    - While any sibling is unresolved (see below): emit Skipped with the withheld reason, with or
      without -Prune. No warning is written, no ShouldProcess prompt is issued, nothing is removed.
    - Otherwise, with -Prune: Write-Warning, gate $Caller.ShouldProcess, call Remove-OERRoleAssignment
      -Id <RoleAssignmentId> -Confirm:$false (throws -> Failed + continue), emit Removed.
      Under -WhatIf ShouldProcess returns $false -> emit Skipped.
    - Otherwise, without -Prune: emit Extra (informational).

    A sibling in $DeclaredAtScope whose principal or role lookup gives nothing, or throws, carries no
    key, so the pass cannot tell which live assignment it names -- its own live counterpart would look
    undeclared. Such a sibling therefore withholds the prune for the WHOLE scope: every undeclared
    candidate at this scope is reported Skipped, with a Detail that starts
    "prune withheld: declared entry '<role> -> <principal> @ <scope>' could not be resolved", with or
    without -Prune, and nothing at the scope is removed until that entry is fixed or removed from the
    document (ConvertTo-OERPruneWithheldResult owns the rule and the text). A thrown sibling lookup is
    scrubbed and does not abort the pass, and no error is written for it here: the sibling's own
    invocation of this handler writes its error and reports its Failed record, under the same
    '<role> -> <principal> @ <scope>' label the withheld Detail names, so the rows can be correlated.

    The pass runs only in the invocation for the FIRST item of each scope. When that item's own scope,
    principal, role or current-assignment read fails, the handler returns before the pass: nothing at
    that scope is pruned or reported Extra, and no withheld Skipped rows appear either -- only that
    item's own Failed record.

    Every write is gated by $Caller.ShouldProcess. Reads (Resolve-OERScope,
    Get-OERRoleAssignment) always execute even under -WhatIf because they provide the diff/plan.

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
    lookup gave nothing or threw), nothing at the scope is removed or reported Extra: every
    undeclared assignment there is reported Skipped with a Detail starting "prune withheld:", with or
    without this switch.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Currently unused by this handler but
    accepted for a uniform Sync-OERStructure* signature.

    .PARAMETER DeclaredAtScope
    All document roleAssignment items sharing this item's scope string, this item included (the
    engine groups on the scope text as written in the document, not on the resolved ARM scope). Used
    during the scope-wide prune pass (when -ReconcileScope is set) to build the declared-key set. Each
    element is expected to have .principal and .role properties. Defaults to an empty array. One
    element whose principal or role cannot be resolved withholds the prune for the whole scope (see
    -Prune); that element's Failed record comes from its own invocation of this handler.

    .PARAMETER ReconcileScope
    When set, this invocation also performs the scope-wide Extra/prune pass after reconciling its
    own item. The engine sets this flag on the first item of each scope group. The pass is not
    reached when this item's own scope, principal, role or current-assignment read fails.

    .EXAMPLE
    Sync-OERStructureRoleAssignment -Item $DocItem -Caller $PSCmdlet -TenantAlias 'omnicit'
    Reconciles one role assignment entry from the document using the engine PSCmdlet as the caller.

    .EXAMPLE
    Sync-OERStructureRoleAssignment -Item $DocItem -Caller $PSCmdlet -Prune -ReconcileScope -DeclaredAtScope $SiblingItems
    Reconciles one role assignment and performs the scope-wide prune pass for undeclared extras.
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
        [object[]]$DeclaredAtScope = @(),
        [switch]$ReconcileScope
    )

    process {
        # Nested helper: parse the scope DSL string into a Resolve-OERScope splat hashtable.
        # Takes a named param to avoid the PSReviewUnusedParameter-closure gotcha.
        function Get-ScopeSplat {
            param([string]$Scope)
            if ($Scope -match '^(?i)mg:(.+)$')                   { return @{ ManagementGroup = $Matches[1] } }
            if ($Scope -match '^(?i)(?:subscription|sub):(.+)$') { return @{ Subscription = $Matches[1] } }
            return @{ Scope = $Scope }
        }

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

        $Label  = "$($Item.role) -> $($Item.principal) @ $($Item.scope)"
        $Section = 'roleAssignments'
        $PrincipalType = if (Test-DeclHas -Node $Item -Name 'principalType') { [string]$Item.principalType } else { $null }

        # -- 1. Resolve scope ---------------------------------------------------------------
        $ScopeSplat = Get-ScopeSplat -Scope $Item.scope
        $RawScope   = $null
        try {
            $RawScope = Resolve-OERScope @ScopeSplat
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not resolve scope '$($Item.scope)': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }

        # -- 2. Resolve principal id (for diff) --------------------------------------------
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

        # -- 3. Resolve role full id (for diff) -------------------------------------------
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

        # -- 4. Read current at-scope assignments once ------------------------------------
        $Current = $null
        try {
            $Current = @(Get-OERRoleAssignment @ScopeSplat -AtScope)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not read role assignments at scope '$RawScope': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }

        # -- 5. Check existence of THIS item ----------------------------------------------
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
        $Matching  = @($Current | Where-Object { $_.PrincipalId -eq $PrincipalObjId -and $_.RoleDefinitionId -eq $RoleFullId })
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
            # -- 6. Create (absent) -------------------------------------------------------
            if (-not $Caller.ShouldProcess($RawScope, "Create role assignment '$($Item.role)' for '$($Item.principal)'")) {
                ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Skipped' `
                    -Detail "would create role assignment '$($Item.role)' for '$($Item.principal)' at '$RawScope'"
            } else {
                $NewParams = @{ Role = $Item.role; Confirm = $false }
                # Merge scope params into NewParams
                foreach ($Key in $ScopeSplat.Keys) { $NewParams[$Key] = $ScopeSplat[$Key] }
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

        # Build the declared key set from all $DeclaredAtScope siblings. A sibling whose principal or
        # role cannot be resolved carries no key, so it cannot protect its own live assignment from
        # the candidate loop below. It is recorded in $SiblingUnresolved instead, under the sibling's
        # own result label, and while that list is non-empty every candidate at this scope is
        # withheld (ConvertTo-OERPruneWithheldResult owns that rule) rather than reported Extra or
        # removed.
        $DeclaredKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $SiblingUnresolved = [System.Collections.Generic.List[string]]::new()
        foreach ($Sibling in @($DeclaredAtScope)) {
            $SiblingLabel = "$($Sibling.role) -> $($Sibling.principal) @ $($Sibling.scope)"
            try {
                $SibParams = @{ Reference = $Sibling.principal }
                if (Test-OERDeclaredProperty -Node $Sibling -Name 'principalType') { $SibParams.Type = $Sibling.principalType }
                $SiblingPid  = Resolve-OERStructurePrincipal @SibParams
                $SiblingRole = Resolve-OERRoleDefinitionId -Role $Sibling.role -Scope $RawScope
                if ($SiblingPid -and $SiblingRole) {
                    $null = $DeclaredKeys.Add("$SiblingPid|$SiblingRole")
                } else {
                    $SiblingUnresolved.Add($SiblingLabel)
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # A sibling whose lookup throws does not abort the pass, but it is unresolved all the
                # same and withholds the prune at this scope. No error is written here: the sibling's
                # own invocation writes its own error and Failed record.
                $SiblingUnresolved.Add($SiblingLabel)
            }
        }

        foreach ($Cur in $Current) {
            # Only assignments DEFINED at this scope are candidates. atScope() also returns
            # assignments inherited from ancestor scopes (a subscription read includes its parent
            # management groups' assignments); those belong to the ancestor, are typically declared in
            # the document under THAT scope, and cannot be removed here -- so flagging them Extra/prune
            # against this scope's declared set is a false positive. Skip anything not owned by $RawScope.
            if ($Cur.Scope -and ($Cur.Scope -ne $RawScope)) { continue }

            $CurKey = "$($Cur.PrincipalId)|$($Cur.RoleDefinitionId)"
            if ($DeclaredKeys.Contains($CurKey)) { continue }

            # Each undeclared assignment gets its OWN Item label (role leaf -> principal @ scope) so the
            # results table shows distinct rows instead of repeating the triggering declared item.
            $CurRoleLeaf = ($Cur.RoleDefinitionId -split '/')[-1]
            $ExtraItem   = "$CurRoleLeaf -> $($Cur.PrincipalId) @ $($Cur.Scope)"
            $CurLabel    = "undeclared assignment '$($Cur.RoleDefinitionId)' for principal '$($Cur.PrincipalId)'"
            $Withheld = ConvertTo-OERPruneWithheldResult -Section $Section -Item $ExtraItem -Unresolved $SiblingUnresolved -Candidate $CurLabel
            if ($Withheld) { $Withheld; continue }
            if ($Prune) {
                $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                Write-Warning "Sync-OERStructureRoleAssignment: $PruneVerb $CurLabel at scope '$RawScope'."
                if ($Caller.ShouldProcess($RawScope, "Remove undeclared role assignment '$($Cur.RoleAssignmentId)'")) {
                    try {
                        $null = Remove-OERRoleAssignment -Id $Cur.RoleAssignmentId -Confirm:$false -ErrorAction Stop
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
