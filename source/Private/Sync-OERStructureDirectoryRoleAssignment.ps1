function Sync-OERStructureDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Reconciles one directoryRoleAssignments[] document entry against the live eligible or active
    assignments of a Microsoft Entra directory role, and runs the section-wide prune pass once.

    .DESCRIPTION
    The orchestration handler for a single directoryRoleAssignments entry from the structure document.
    It is called by the Invoke-OERStructure engine and emits one ConvertTo-OERStructureResult record,
    labelled "<role> -> <principal> (<assignmentType>)", describing what was created, updated, left
    unchanged, skipped or failed. The engine labels a handler error for the same entry the same way, so
    the two rows correlate. The invocation that carries -ReconcileSection also emits the rows of the
    section-wide prune pass described below, ahead of its own row.

    An entry is matched on role, principal and assignmentType. assignmentType Eligible reconciles an
    eligible assignment (Get-/New-OEREligibleDirectoryRoleAssignment) and Active an active one
    (Get-/New-OERActiveDirectoryRoleAssignment); an Eligible entry never reads or writes active
    assignments, and the reverse. A directory role assignment here always lives at tenant scope, so an
    entry carries no scope field.

    Flow:
    0. An assignmentType that is neither Eligible nor Active reports Failed before any lookup or read.
       The engine validates the document first, so only a direct call of this handler reaches it.
    1. The role (a display name or role definition id) is resolved to its role definition id with
       Resolve-OERDirectoryRoleDefinitionId. No match, or a lookup that throws (an ambiguous name
       included), reports Failed and nothing is read or written.
    2. The principal is resolved to an object id with Resolve-OERStructurePrincipal, forwarding the
       optional principalType (User, Group or ServicePrincipal) as -Type; without it, or with an
       empty one, the resolver's heuristic applies. The prune pass below decides principalType the
       same way. No match, or a lookup that throws, reports Failed. A service principal display name
       that matches more than one service principal is refused (AmbiguousName, naming the candidate
       ids) and reports Failed the same way; it never acts on one of them. Name a service principal by
       its object id (Test-OERStructureSchema warns about a ServicePrincipal entry named by display
       name).
    3. The live schedules of that role and principal are read with -ErrorAction Stop, so a refused
       read lands in a Failed row and is never mistaken for an absent assignment. Only the rows
       Select-OERManagedDirectoryRoleAssignment keeps may stand for the entry: tenant scope, a DIRECT
       assignment (one the principal holds through a group is managed through that group and is never
       a match), and for Active an Assigned schedule. An Activated schedule is an activation of an
       eligible assignment, created by the principal and ended by PIM; it never satisfies a declared
       active assignment.
    4. Resolve-OERDirectoryRoleAssignmentChange diffs the declared window against the kept schedule.
       durationDays makes the entry time-bound; an entry without durationDays is permanent, whether it
       declares permanent true or nothing at all (the offline validator refuses durationDays together
       with permanent true, and permanent false without durationDays). A missing assignment is created
       with -Action adminAssign and reports Created; a changed window or permanence is re-issued with
       -Action adminUpdate and reports Updated, so a live assignment is never removed to be re-created.
       A matching window reports Unchanged.

    justification, when declared, is sent as -Justification with a create or an update; it is never
    compared, so a changed justification alone changes nothing. Without it the cmdlets send their own
    standard justification. A permanent assignment the role's policy does not allow is refused by the
    New cmdlet before any write, and that refusal is reported Failed; the policy is declared under
    directoryRoleManagementPolicies, which the engine applies first.

    Section-wide prune pass (only when -ReconcileSection is set):
    The engine sets -ReconcileSection on the section's FIRST item only and passes the whole section as
    -DeclaredInSection to every item, so the pass runs once per apply run. It runs at the top of that
    invocation, BEFORE the item's own reconcile and whatever that item's own outcome: a first item
    whose role, principal or read fails still gets the pass, and its own row follows the pass rows.
    (The roleAssignments pass differs here: it is skipped when its first item fails.)
    - Keys. Every declared entry's role is resolved to its role definition id and its principal to an
      object id. The pass is keyed on these RESOLVED ids, so one role written by name in one entry and
      by its role definition id in another is one pair, and neither entry's live assignment is ever
      reported Extra or removed. An entry whose assignmentType is neither Eligible nor Active is left
      out of the pass; its own invocation reports it Failed.
    - Pairs. Only the (role, assignmentType) pairs the document declares are read, one
      Get-OEREligibleDirectoryRoleAssignment or Get-OERActiveDirectoryRoleAssignment -Role call per
      pair, with -ErrorAction Stop. A role the document does not name is never read or touched, and a
      role declared only for Eligible never has its active assignments read, and the reverse. A read
      that fails, or that reports a non-terminating error, is one Failed row for that pair, labelled
      "<role definition id> (<assignmentType>)", and its error is written; nothing in that pair is
      removed or reported Extra, since a failed read is not an empty one. The other pairs still run.
    - Candidates. Only the rows Select-OERManagedDirectoryRoleAssignment keeps, and only those of the
      pair's own role, are candidates: an activation (an Activated schedule), a member's assignment
      inherited through a group and one scoped to an administrative unit are never counted and never
      pruned. A role-assignable group's own direct assignment is a candidate like any other, so
      removing it ends the role for every member who holds it through the group. A candidate whose
      principal a declared entry of the same pair names is kept. Every other one is
      an undeclared assignment, reported under its own label "<role> -> <principal id>
      (<assignmentType>)".
    - Guards, in this order, for every undeclared candidate:
      1. The step 1 rule, through ConvertTo-OERPruneWithheldResult, called first. An entry whose
         PRINCIPAL cannot be resolved (nothing found, or the lookup throws) withholds its own pair;
         an entry whose ROLE cannot be resolved withholds every pair of its assignmentType, since its
         pair is unknown. A withheld candidate is reported Skipped, with or without -Prune, with a
         Detail starting "prune withheld: declared entry" when one entry is unresolved, or
         "prune withheld: declared entries" when several are, each named as
         '<role> -> <principal> (<assignmentType>)' (ConvertTo-OERPruneWithheldResult owns the
         wording). A failed entry lookup writes no error here: that entry's own invocation writes
         its error and reports its Failed row under the same label.
      2. The signed-in identity is unknown: Get-OERSignedInObjectId returns the object id recorded
         from the Microsoft Graph token's oid claim (delegated and app-only alike, never /me); when
         it returns nothing, every candidate is reported Skipped with a Detail starting
         "prune withheld: the signed-in identity's object id is unknown", with or without -Prune.
      3. The candidate is the signed-in identity's own assignment: it is reported Skipped, with or
         without -Prune, and never removed.
      4. Otherwise, without -Prune the candidate is reported Extra. With -Prune the handler writes a
         warning naming it, gates $Caller.ShouldProcess, and removes it with
         Remove-OEREligibleDirectoryRoleAssignment or Remove-OERActiveDirectoryRoleAssignment
         -Role <id> -PrincipalId <id> -Confirm:$false, reporting Removed; a removal that fails is
         reported Failed and its error is written. Under -WhatIf, or when the prompt is declined, it
         is reported Skipped ("would remove ...").
      Guards 2 and 3 are this module's own, not a Graph rejection, and their Details say so.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false and the handler
    emits Skipped, naming the planned change, instead of calling the New or Remove cmdlet. Reads always
    execute even under -WhatIf so the plan is built from the live state. Every call goes through
    Microsoft Graph; no Azure Resource Manager token is needed. -TenantAlias is accepted for a uniform
    Sync-OERStructure* signature and is not used.

    .PARAMETER Item
    One element from the directoryRoleAssignments[] array in the structure document, as a
    PSCustomObject produced by ConvertFrom-Json. Required properties: role (a directory role display
    name or role definition id), principal (a user principal name, group or service principal display
    name, or object id) and assignmentType (Eligible or Active). Optional: principalType, durationDays,
    permanent and justification. An explicit JSON null on an optional property counts as not declared.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set (together with -ReconcileSection), an undeclared direct, tenant-scope assignment in a
    (role, assignmentType) pair the section declares is removed after a ShouldProcess gate; without
    it, such an assignment is only reported Extra. Activations, a member's assignments inherited
    through a group, assignments scoped to an administrative unit, roles and kinds the document does
    not declare, and the signed-in identity's own direct assignments are never removed. A
    role-assignable group's own direct assignment is an ordinary candidate: when the document
    declares a pair without that group, it is removed, and with it the role of every member who
    holds it through the group, the signed-in identity included. A candidate a guard withholds (an
    unresolved entry, an unknown signed-in identity, or the identity's own assignment) is reported
    Skipped with or without this switch.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Accepted for handler signature uniformity
    but not used by this handler.

    .PARAMETER DeclaredInSection
    Every entry of the document's directoryRoleAssignments section, this item included. The prune
    pass builds its declared pairs and keys from it (see the pass above); an entry whose role or
    principal cannot be resolved withholds the prune as described there, and its Failed row comes
    from its own invocation. Used only with -ReconcileSection. Defaults to an empty array.

    .PARAMETER ReconcileSection
    When set, this invocation runs the section-wide prune pass once, before reconciling its own item
    and independently of that item's outcome. The engine sets it on the section's first item only.

    .EXAMPLE
    Sync-OERStructureDirectoryRoleAssignment -Item $DocItem -Caller $PSCmdlet
    Reconciles one directory role assignment entry from the document against the live assignments of
    its role and principal.

    .EXAMPLE
    Sync-OERStructureDirectoryRoleAssignment -Item $Items[0] -Caller $PSCmdlet -DeclaredInSection $Items -ReconcileSection -Prune
    Runs the section-wide prune pass over every (role, assignmentType) pair the section declares,
    removing the undeclared direct assignments no guard withholds, then reconciles the first entry.
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
        [object[]]$DeclaredInSection = @(),
        [switch]$ReconcileSection
    )

    process {
        $Section = 'directoryRoleAssignments'
        $Kind = Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -Value ([string]$Item.assignmentType)
        # An out-of-enum assignmentType keeps its written value in the label, as the engine's
        # handler-error label does, so the Failed row below still names what the document says.
        $KindText = if ($Kind) { $Kind } else { [string]$Item.assignmentType }
        $Label = "$($Item.role) -> $($Item.principal) ($KindText)"
        # A principalType counts only when declared AND non-empty -- the pass below decides it the same way.
        $PrincipalType = if (Test-OERDeclaredProperty -Node $Item -Name 'principalType') { [string]$Item.principalType } else { $null }

        if ($ReconcileSection) {
            # -- Section-wide prune pass (runs once, before this item, whatever this item's own fate) --
            # Keyed on RESOLVED role ids, so one role written by name in one entry and by id in another
            # is one pair. Only pairs the document declares are read, so a role or kind the document does
            # not name is never touched.
            $DeclaredKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $PairUnresolved = [ordered]@{}
            $KindUnresolved = @{
                Eligible = [System.Collections.Generic.List[string]]::new()
                Active   = [System.Collections.Generic.List[string]]::new()
            }
            foreach ($Entry in @($DeclaredInSection)) {
                $EntryKind = Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -Value ([string]$Entry.assignmentType)
                if (-not $EntryKind) { continue }
                $EntryLabel = "$($Entry.role) -> $($Entry.principal) ($EntryKind)"
                $EntryRoleId = $null
                try { $EntryRoleId = Resolve-OERDirectoryRoleDefinitionId -Role ([string]$Entry.role) }
                catch { Remove-OERErrorRecord -Record $PSItem }
                if (-not $EntryRoleId) {
                    # Its pair is unknown, so it may be the counterpart of a candidate in ANY pair of
                    # its kind: withhold them all. Its own invocation reports its Failed row.
                    $KindUnresolved[$EntryKind].Add($EntryLabel)
                    continue
                }
                $PairKey = "$EntryRoleId|$EntryKind"
                if (-not $PairUnresolved.Contains($PairKey)) {
                    $PairUnresolved[$PairKey] = [System.Collections.Generic.List[string]]::new()
                }
                # principalType is decided exactly as the item part decides it (declared AND
                # non-empty), so the pass never fails a lookup the item itself makes.
                $EntryType = if (Test-OERDeclaredProperty -Node $Entry -Name 'principalType') { [string]$Entry.principalType } else { $null }
                $EntryParams = @{ Reference = [string]$Entry.principal }
                if ($EntryType) { $EntryParams.Type = $EntryType }
                $EntryPrincipalId = $null
                try { $EntryPrincipalId = Resolve-OERStructurePrincipal @EntryParams }
                catch { Remove-OERErrorRecord -Record $PSItem }
                if (-not $EntryPrincipalId) { $PairUnresolved[$PairKey].Add($EntryLabel); continue }
                $null = $DeclaredKeys.Add("$EntryRoleId|$EntryPrincipalId|$EntryKind")
            }

            $SignedInId = Get-OERSignedInObjectId
            foreach ($PairKey in @($PairUnresolved.Keys)) {
                $PairRoleId, $PairKind = $PairKey -split '\|', 2
                $Unresolved = @($PairUnresolved[$PairKey]) + @($KindUnresolved[$PairKind])
                $Live = $null
                try {
                    $Live = if ($PairKind -eq 'Eligible') { @(Get-OEREligibleDirectoryRoleAssignment -Role $PairRoleId -ErrorAction Stop) }
                            else { @(Get-OERActiveDirectoryRoleAssignment -Role $PairRoleId -ErrorAction Stop) }
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Caller.WriteError($PSItem)
                    ConvertTo-OERStructureResult -Section $Section -Item "$PairRoleId ($PairKind)" -Action 'Failed' `
                        -Detail "could not read the $($PairKind.ToLowerInvariant()) assignments of directory role '$PairRoleId', so nothing in this pair was pruned or reported Extra: $($PSItem.Exception.Message)" `
                        -ErrorRecord $PSItem
                    continue
                }
                foreach ($Candidate in @(Select-OERManagedDirectoryRoleAssignment -Assignment $Live -Kind $PairKind)) {
                    if ($Candidate.RoleDefinitionId -ne $PairRoleId) { continue }
                    if ($DeclaredKeys.Contains("$PairRoleId|$($Candidate.PrincipalId)|$PairKind")) { continue }
                    $RoleText = if ($Candidate.RoleName) { $Candidate.RoleName } else { $PairRoleId }
                    $CandItem = "$RoleText -> $($Candidate.PrincipalId) ($PairKind)"
                    $CandLabel = "undeclared $($PairKind.ToLowerInvariant()) assignment of directory role '$RoleText' for principal '$($Candidate.PrincipalId)'"
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section $Section -Item $CandItem -Unresolved $Unresolved -Candidate $CandLabel
                    if ($Withheld) { $Withheld; continue }
                    if (-not $SignedInId) {
                        ConvertTo-OERStructureResult -Section $Section -Item $CandItem -Action 'Skipped' `
                            -Detail "prune withheld: the signed-in identity's object id is unknown (it could not be determined from the session's Microsoft Graph token), so $CandLabel may be its own assignment and is left in place (our own guard, not a Graph rejection). Sign in again with Connect-OER; if the token carries no oid claim, reconcile this pair from a session that does."
                        continue
                    }
                    if ($Candidate.PrincipalId -eq $SignedInId) {
                        ConvertTo-OERStructureResult -Section $Section -Item $CandItem -Action 'Skipped' `
                            -Detail "$CandLabel belongs to the signed-in identity itself; the apply engine never removes the signed-in identity's own directory role assignments (our own guard, not a Graph rejection)"
                        continue
                    }
                    if ($Prune) {
                        $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                        Write-Warning "Sync-OERStructureDirectoryRoleAssignment: $PruneVerb $CandLabel."
                        if ($Caller.ShouldProcess($CandItem, "Remove undeclared $($PairKind.ToLowerInvariant()) directory role assignment")) {
                            try {
                                $RemoveParams = @{ Role = $PairRoleId; PrincipalId = $Candidate.PrincipalId; Confirm = $false; ErrorAction = 'Stop' }
                                $null = if ($PairKind -eq 'Eligible') { Remove-OEREligibleDirectoryRoleAssignment @RemoveParams -WarningAction SilentlyContinue }
                                        else { Remove-OERActiveDirectoryRoleAssignment @RemoveParams -WarningAction SilentlyContinue }
                                ConvertTo-OERStructureResult -Section $Section -Item $CandItem -Action 'Removed' -Detail "removed $CandLabel"
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section $Section -Item $CandItem -Action 'Failed' `
                                    -Detail "failed to remove $CandLabel`: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section $Section -Item $CandItem -Action 'Skipped' -Detail "would remove $CandLabel"
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section $Section -Item $CandItem -Action 'Extra' -Detail "$CandLabel (use -Prune to remove)"
                    }
                }
            }
        }

        # -- 0. The assignment kind --------------------------------------------------------
        # Only reachable by a direct call (the engine validates first); without this the handler
        # would throw at Select-OERManagedDirectoryRoleAssignment -Kind $null after a Graph read.
        if (-not $Kind) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "assignmentType '$($Item.assignmentType)' is not Eligible or Active"
            return
        }

        # -- 1. Resolve the role -----------------------------------------------------------
        $RoleId = $null
        try {
            $RoleId = Resolve-OERDirectoryRoleDefinitionId -Role $Item.role
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not resolve directory role '$($Item.role)': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
            return
        }
        if (-not $RoleId) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "directory role '$($Item.role)' could not be resolved to a role definition id"
            return
        }

        # -- 2. Resolve the principal ------------------------------------------------------
        $ResolveParams = @{ Reference = [string]$Item.principal }
        if ($PrincipalType) { $ResolveParams.Type = $PrincipalType }
        $PrincipalObjId = $null
        try {
            $PrincipalObjId = Resolve-OERStructurePrincipal @ResolveParams
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not resolve principal '$($Item.principal)': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
            return
        }
        if (-not $PrincipalObjId) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "principal '$($Item.principal)' could not be resolved to an object id"
            return
        }

        # -- 3. Read the live assignment of this principal and role -------------------------
        # -ErrorAction Stop: a refused read must land in the catch, never read as "absent".
        $Live = $null
        try {
            $Live = if ($Kind -eq 'Eligible') {
                @(Get-OEREligibleDirectoryRoleAssignment -Role $RoleId -PrincipalId $PrincipalObjId -ErrorAction Stop)
            } else {
                @(Get-OERActiveDirectoryRoleAssignment -Role $RoleId -PrincipalId $PrincipalObjId -ErrorAction Stop)
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not read the $($Kind.ToLowerInvariant()) assignments of '$($Item.role)': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
            return
        }
        # Only a direct, tenant-scope schedule -- and for Active an Assigned one, never an
        # activation -- may stand for the declared entry (Select-OERManagedDirectoryRoleAssignment).
        $Current = @(Select-OERManagedDirectoryRoleAssignment -Assignment $Live -Kind $Kind |
                Where-Object { $_.RoleDefinitionId -eq $RoleId -and $_.PrincipalId -eq $PrincipalObjId }) | Select-Object -First 1

        # -- 4. Diff and write -------------------------------------------------------------
        $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Item -Current $Current
        if (-not $Change.Changed) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Unchanged' -Detail $Change.Detail
            return
        }
        $Action = if ($Change.Reason -eq 'Absent') { 'adminAssign' } else { 'adminUpdate' }
        $Verb = if ($Action -eq 'adminAssign') { 'create' } else { 'update' }
        if (-not $Caller.ShouldProcess($Label, "$Verb $($Kind.ToLowerInvariant()) directory role assignment")) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Skipped' `
                -Detail "would $Verb the $($Kind.ToLowerInvariant()) assignment ($($Change.Detail))"
            return
        }
        $NewParams = @{ Role = $RoleId; PrincipalId = $PrincipalObjId; Action = $Action; Confirm = $false; ErrorAction = 'Stop' }
        if ($Change.Permanent) { $NewParams.Permanent = $true } else { $NewParams.DurationDays = $Change.DurationDays }
        if (Test-OERDeclaredProperty -Node $Item -Name 'justification') { $NewParams.Justification = [string]$Item.justification }
        try {
            $null = if ($Kind -eq 'Eligible') { New-OEREligibleDirectoryRoleAssignment @NewParams }
                    else { New-OERActiveDirectoryRoleAssignment @NewParams }
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action $(if ($Action -eq 'adminAssign') { 'Created' } else { 'Updated' }) `
                -Detail "$($Verb)d the $($Kind.ToLowerInvariant()) assignment ($($Change.Detail))"
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "failed to $Verb the $($Kind.ToLowerInvariant()) assignment: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
        }
    }
}
