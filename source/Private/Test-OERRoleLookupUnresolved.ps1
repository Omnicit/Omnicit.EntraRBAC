function Test-OERRoleLookupUnresolved {
    <#
    .SYNOPSIS
    Tells a role or policy lookup that matched nothing from one that failed.

    .DESCRIPTION
    The single owner of that decision for Get-OERRoleManagementPolicy and Set-OERRoleManagementPolicy
    (Sprint 12 step 3) and the seven Azure role assignment cmdlets (Sprint 13 step 1, BL-167b).
    Resolve-OERRoleDefinitionId and Get-OERRoleManagementPolicyId, called with
    -ThrowUnresolved, throw an ErrorRecord with the internal id RoleDefinitionUnresolved or
    RolePolicyUnresolved when the lookup SUCCEEDED and found nothing. This helper answers true for
    such a record: its FullyQualifiedErrorId starts, ordinally, with either id. A prefix test, so a
    record that has already crossed a WriteError boundary and carries the qualified
    '<ErrorId>,<CommandName>' form is still recognised.

    Anything else -- a 403, an exhausted 429, a 5xx, GraphPagingIncomplete or ArmPagingIncomplete, an
    AmbiguousName, a null record -- answers false: that is no evidence that the role or policy is
    missing, so the caller publishes the record as itself. The two internal ids are never published.
    Pure: no request, and it never throws. The cohort check in
    tests/Unit/Private/Test-OERRoleLookupUnresolved.Tests.ps1 holds that no other file under source/
    names either id, the two producers excepted.

    .PARAMETER Record
    The ErrorRecord caught around the lookup. A null record answers false.

    .EXAMPLE
    if (Test-OERRoleLookupUnresolved -Record $PSItem) { 'no match' } else { 'failed read' }
    Tells a role that does not exist from a lookup that failed.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Management.Automation.ErrorRecord]$Record
    )

    if ($null -eq $Record) { return $false }
    $ErrorId = [string]$Record.FullyQualifiedErrorId
    return ($ErrorId.StartsWith('RoleDefinitionUnresolved', [System.StringComparison]::Ordinal) -or
        $ErrorId.StartsWith('RolePolicyUnresolved', [System.StringComparison]::Ordinal))
}
