function Sync-OERStructureDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Reconciles one directoryRoleAssignments[] document entry against the live eligible or active
    assignments of a Microsoft Entra directory role.

    .DESCRIPTION
    The orchestration handler for a single directoryRoleAssignments entry from the structure document.
    It is called by the Invoke-OERStructure engine and emits one ConvertTo-OERStructureResult record,
    labelled "<role> -> <principal> (<assignmentType>)", describing what was created, updated, left
    unchanged, skipped or failed. The engine labels a handler error for the same entry the same way, so
    the two rows correlate.

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
       optional principalType (User, Group or ServicePrincipal) as -Type; without it the resolver's
       heuristic applies. No match, or a lookup that throws, reports Failed.
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

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false and the handler
    emits Skipped, naming the planned change, instead of calling the New cmdlet. Reads always execute
    even under -WhatIf so the plan is built from the live state. Every call goes through Microsoft
    Graph; no Azure Resource Manager token is needed.

    -Prune and -TenantAlias are accepted for a uniform Sync-OERStructure* signature; this handler
    reconciles the declared entry only and removes nothing.

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
    Accepted for handler signature uniformity. This handler reconciles the declared entry only and
    never removes an assignment.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Accepted for handler signature uniformity
    but not used by this handler.

    .EXAMPLE
    Sync-OERStructureDirectoryRoleAssignment -Item $DocItem -Caller $PSCmdlet
    Reconciles one directory role assignment entry from the document against the live assignments of
    its role and principal.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'TenantAlias',
        Justification = 'TenantAlias is part of the uniform Sync-OERStructure* handler signature; accepted for future use and caller consistency even though this handler does not resolve tenant defaults.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Prune',
        Justification = 'Prune is part of the uniform Sync-OERStructure* handler signature; this handler reconciles the declared entry only, so the switch is accepted for caller uniformity.'
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
        $Section = 'directoryRoleAssignments'
        $Kind = Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -Value ([string]$Item.assignmentType)
        # An out-of-enum assignmentType keeps its written value in the label, as the engine's
        # handler-error label does, so the Failed row below still names what the document says.
        $KindText = if ($Kind) { $Kind } else { [string]$Item.assignmentType }
        $Label = "$($Item.role) -> $($Item.principal) ($KindText)"
        $PrincipalType = if (Test-OERDeclaredProperty -Node $Item -Name 'principalType') { [string]$Item.principalType } else { $null }

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
