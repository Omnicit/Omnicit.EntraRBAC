function Select-OERManagedDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Keeps only the live directory role assignments the apply engine may match or prune.

    .DESCRIPTION
    The single owner of which live Microsoft Entra directory role assignment a directoryRoleAssignments
    entry can stand for. Three guards, each on its own line so each stays independently provable:
    the assignment must be at tenant scope (DirectoryScopeId '/'; an administrative-unit-scoped one
    belongs to administrativeUnits[].scopedRoles); it must be DIRECT (MemberType 'Direct'; one that a
    principal holds through a group is managed through that group, never here); and an Active one
    must be ASSIGNED (AssignmentType 'Assigned'). An Activated schedule is an activation of an
    eligible assignment, created by the principal and ended by PIM: it is never a declared Active
    assignment, never counts as one, and is never pruned. Pure filter; no Graph call.

    With -Excluded it returns the other side instead: one object per assignment a guard drops, with
    the assignment in Assignment and every guard that drops it in Reason -- Scope (not at tenant
    scope), Group (not direct) and Activation (an Active one that is not Assigned), in that order.
    The guards are the same lines either way, so the two sides can never disagree.

    .PARAMETER Assignment
    Projected objects from Get-OEREligibleDirectoryRoleAssignment or Get-OERActiveDirectoryRoleAssignment.

    .PARAMETER Kind
    Eligible or Active -- which cmdlet the objects came from.

    .PARAMETER Excluded
    Return the dropped assignments, each with the reasons it is dropped, instead of the kept ones.

    .EXAMPLE
    Select-OERManagedDirectoryRoleAssignment -Assignment $Live -Kind Active
    Returns the direct, tenant-scope, Assigned active assignments in $Live.

    .EXAMPLE
    Select-OERManagedDirectoryRoleAssignment -Assignment $Live -Kind Active -Excluded
    Returns every other active assignment in $Live, with Reason naming why it is not managed.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()][object[]]$Assignment,
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Kind,
        [switch]$Excluded
    )
    foreach ($Candidate in @($Assignment)) {
        if ($null -eq $Candidate) { continue }
        $Reason = [System.Collections.Generic.List[string]]::new()
        if ([string]$Candidate.DirectoryScopeId -ne '/') { $Reason.Add('Scope') }
        if ([string]$Candidate.MemberType -ne 'Direct') { $Reason.Add('Group') }
        if ($Kind -eq 'Active' -and [string]$Candidate.AssignmentType -ne 'Assigned') { $Reason.Add('Activation') }
        if ($Excluded) {
            if ($Reason.Count -gt 0) { [PSCustomObject]@{ Assignment = $Candidate; Reason = [string[]]$Reason.ToArray() } }
        } elseif ($Reason.Count -eq 0) {
            $Candidate
        }
    }
}
