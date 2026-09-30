function Test-OERDirectoryRoleAssignmentGone {
    <#
    .SYNOPSIS
    Decides, by reading it again, whether a directory role assignment that a removal was answered
    RoleAssignmentDoesNotExist for is gone.

    .DESCRIPTION
    The single owner of how Remove-OEREligibleDirectoryRoleAssignment and
    Remove-OERActiveDirectoryRoleAssignment treat a RoleAssignmentDoesNotExist answer to their
    adminRemove request. Measured live: Microsoft Graph answered an adminRemove of an active
    assignment with RoleAssignmentDoesNotExist although it lists the removal request as Revoked and
    the assignment is gone. The module sent one request; whether the Microsoft Graph SDK below it
    resent that request cannot be seen from here, since the SDK's own retry handler resends a request
    answered 503 or 504 and hands back only the last answer.

    Returns an object with Gone, Detail and StillHeld, and never throws for a failed read:
    - The record is not RoleAssignmentDoesNotExist (neither the first segment of its error id nor
      the start of its message names that code): Gone is $false, Detail and StillHeld are $null, and
      nothing is read.
    - Otherwise the principal's schedules of the role are read again, at every directory scope, in
      one Microsoft Graph request (roleEligibilitySchedules for Eligible, roleAssignmentSchedules for
      Active), and passed through Select-OERManagedDirectoryRoleAssignment, the single owner of which
      schedule a removal stands for: a direct, tenant-scope one, and for Active an Assigned one.
      Gone is $true only when that read succeeded and kept no schedule of the role and principal. A
      schedule still in place gives Gone $false, and so does a read that fails or returns no answer:
      a failed read is never an absent assignment (the step 1 rule). Detail says which of the three
      it was, for the caller's verbose line.
    - When Gone is $true but the same read holds schedules of the role and principal that the
      selector sets aside (its -Excluded side), the principal still holds the role another way.
      StillHeld then names how, without ids -- "as an activation of an eligible assignment",
      "through a group" and "at a directory scope narrower than the tenant, such as an
      administrative unit", joined in that order -- for the caller's warning. Otherwise it is $null.
      The read is the same one: the filter names no directory scope, so no second request is made.

    .PARAMETER Record
    The error record the removal request raised.

    .PARAMETER Kind
    Eligible or Active: which schedules are read again.

    .PARAMETER RoleDefinitionId
    The role definition id the removal request named.

    .PARAMETER PrincipalId
    The principal object id the removal request named.

    .EXAMPLE
    $Check = Test-OERDirectoryRoleAssignmentGone -Record $RemoveError -Kind Active -RoleDefinitionId $RoleId -PrincipalId $PrincipalId
    Returns Gone $true when the active assignment is proven gone after a RoleAssignmentDoesNotExist
    answer, with StillHeld set when the principal still holds the role another way, and Gone $false,
    with the reason in Detail, otherwise.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$Record,
        [Parameter(Mandatory)][ValidateSet('Eligible', 'Active')][string]$Kind,
        [Parameter(Mandatory)][string]$RoleDefinitionId,
        [Parameter(Mandatory)][string]$PrincipalId
    )
    $Code = 'RoleAssignmentDoesNotExist'
    $IdHead = @(([string]$Record.FullyQualifiedErrorId) -split ',')[0].Trim()
    $IsDoesNotExist = $IdHead -ceq $Code -or
        ([string]$Record.Exception.Message).StartsWith("$Code`:", [System.StringComparison]::Ordinal)
    if (-not $IsDoesNotExist) { return [PSCustomObject]@{ Gone = $false; Detail = $null; StillHeld = $null } }

    $Target = "$($Kind.ToLowerInvariant()) assignment of directory role '$RoleDefinitionId' for principal '$PrincipalId'"
    $Path = if ($Kind -eq 'Eligible') { 'roleEligibilitySchedules' } else { 'roleAssignmentSchedules' }
    # No directoryScopeId clause: a schedule at a narrower scope must come back too, so the warning
    # can name it. Lower-cased like the Get- cmdlets' principal filter, so an id typed in upper case
    # still matches.
    $Filter = "roleDefinitionId eq '$(ConvertTo-OERODataFilterValue -Value $RoleDefinitionId)' and " +
        "principalId eq '$(ConvertTo-OERODataFilterValue -Value $PrincipalId.ToLowerInvariant())'"
    try {
        $Response = Invoke-OERGraphRequest -Uri "v1.0/roleManagement/directory/$Path`?`$filter=$Filter" -All
        # -All always answers @{ value = <array> } or throws; anything else is no answer at all.
        if ($null -eq $Response -or $null -eq $Response.value) {
            return [PSCustomObject]@{
                Gone      = $false
                Detail    = "Microsoft Graph answered $Code, and reading the $Target again returned no answer, so whether it is gone is unknown; the error stands."
                StillHeld = $null
            }
        }
        $Rows = @(foreach ($Item in @($Response.value)) {
                if ($null -ne $Item) { ConvertTo-OERDirectoryRoleAssignment -InputObject $Item -Kind $Kind }
            })
        $Mine = @($Rows | Where-Object { $_.RoleDefinitionId -eq $RoleDefinitionId -and $_.PrincipalId -eq $PrincipalId })
        $Left = @(Select-OERManagedDirectoryRoleAssignment -Assignment $Mine -Kind $Kind)
        $Reasons = @(Select-OERManagedDirectoryRoleAssignment -Assignment $Mine -Kind $Kind -Excluded | ForEach-Object { $_.Reason })
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        return [PSCustomObject]@{
            Gone      = $false
            Detail    = "Microsoft Graph answered $Code, and reading the $Target again failed, so whether it is gone is unknown; the error stands: $($PSItem.Exception.Message)"
            StillHeld = $null
        }
    }
    if ($Left.Count -gt 0) {
        return [PSCustomObject]@{
            Gone      = $false
            Detail    = "Microsoft Graph answered $Code, but reading the $Target again found it still in place; the error stands."
            StillHeld = $null
        }
    }
    $Ways = @(
        if ($Reasons -contains 'Activation') { 'as an activation of an eligible assignment' }
        if ($Reasons -contains 'Group') { 'through a group' }
        if ($Reasons -contains 'Scope') { 'at a directory scope narrower than the tenant, such as an administrative unit' }
    )
    $StillHeld = switch ($Ways.Count) {
        0 { $null }
        1 { $Ways[0] }
        2 { "$($Ways[0]) and $($Ways[1])" }
        default { "$($Ways[0]), $($Ways[1]) and $($Ways[2])" }
    }
    $Kept = if ($Kind -eq 'Active') { 'direct, standing' } else { 'direct' }
    [PSCustomObject]@{
        Gone      = $true
        Detail    = "Microsoft Graph answered $Code, and reading the $Target again found no $Kept one at tenant scope, so it is gone and the removal is reported as done. (Graph has been measured answering this to a removal it carried out.)"
        StillHeld = $StillHeld
    }
}
