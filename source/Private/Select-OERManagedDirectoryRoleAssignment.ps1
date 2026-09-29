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

    .PARAMETER Assignment
    Projected objects from Get-OEREligibleDirectoryRoleAssignment or Get-OERActiveDirectoryRoleAssignment.

    .PARAMETER Kind
    Eligible or Active -- which cmdlet the objects came from.

    .EXAMPLE
    Select-OERManagedDirectoryRoleAssignment -Assignment $Live -Kind Active
    Returns the direct, tenant-scope, Assigned active assignments in $Live.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()][object[]]$Assignment,
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Kind
    )
    foreach ($Candidate in @($Assignment)) {
        if ($null -eq $Candidate) { continue }
        if ([string]$Candidate.DirectoryScopeId -ne '/') { continue }
        if ([string]$Candidate.MemberType -ne 'Direct') { continue }
        if ($Kind -eq 'Active' -and [string]$Candidate.AssignmentType -ne 'Assigned') { continue }
        $Candidate
    }
}
