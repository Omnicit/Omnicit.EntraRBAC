function Format-OERRootScopeAssignment {
    <#
    .SYNOPSIS
    Orders the role assignments at the Azure root scope that a read left out, and words their list.

    .DESCRIPTION
    The single owner of the order and the list text of the role assignments at the Azure root scope
    '/' (BL-126) that Get-OERInventory and Export-OERInventory leave out of the document and name in
    their warnings instead (docs/development/rationale.md#root-scope-is-not-in-the-document), so the
    two warnings list the rows the same way.

    The rows are deduplicated first, on RoleAssignmentId compared without regard to letter case, or on
    '<Role>|<Principal>' (also without regard to letter case) for a row with no RoleAssignmentId: the
    first row of each key is kept. Export-OERInventory reads every walked scope, and the read at each
    management group and subscription returns the same root assignment as inherited, so it is listed
    once. The kept rows are then sorted by Role, then Principal, then RoleAssignmentId, each compared
    ordinal and without regard to letter case, so the list reads the same on every run and every
    machine.

    Each row is worded as '<Role>' for '<Principal>', followed by ' (<PrincipalType>)' when the type
    is not empty, and the rows are joined with '; '. A null entry is skipped. Pure: no request, no
    warning and no error record.

    Returns a PSCustomObject with Assignments (the deduplicated, sorted rows, as given) and Text (the
    joined list, an empty string for no row).

    .PARAMETER Assignment
    The rows to order and word: objects with RoleAssignmentId, Role, Principal and PrincipalType, as
    Get-OERInventory writes them into its Omnicit.EntraRBAC.RootScopeAssignment information record.

    .EXAMPLE
    Format-OERRootScopeAssignment -Assignment @([PSCustomObject]@{ RoleAssignmentId = 'ra-1'; Role = 'Owner'; Principal = 'Ops'; PrincipalType = 'Group' })
    Returns the one row and the text "'Owner' for 'Ops' (Group)".
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Assignment
    )

    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Row in @($Assignment)) {
        if ($null -eq $Row) { continue }
        $Key = if ($Row.RoleAssignmentId) { [string]$Row.RoleAssignmentId } else { '{0}|{1}' -f $Row.Role, $Row.Principal }
        if ($Seen.Add($Key)) { $Rows.Add($Row) }
    }
    $Rows.Sort([System.Comparison[object]] {
            param($Left, $Right)
            $Order = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.Role, [string]$Right.Role)
            if ($Order -eq 0) { $Order = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.Principal, [string]$Right.Principal) }
            if ($Order -eq 0) { $Order = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.RoleAssignmentId, [string]$Right.RoleAssignmentId) }
            $Order
        })
    $Text = @(foreach ($Row in $Rows) {
            $Type = [string]$Row.PrincipalType
            "'$($Row.Role)' for '$($Row.Principal)'" + $(if ($Type) { " ($Type)" } else { '' })
        }) -join '; '
    [PSCustomObject]@{
        Assignments = $Rows.ToArray()
        Text        = $Text
    }
}
