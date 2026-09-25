function Get-OERPimGroupPolicyId {
    <#
    .SYNOPSIS
    Resolves the roleManagementPolicy id governing a group's PIM-for-groups access.

    .DESCRIPTION
    Queries the beta roleManagementPolicyAssignments for the given group (scopeType Group) and returns
    the policyId of the assignment whose roleDefinitionId equals the requested access type, and $null
    when there is none -- never another access type's policy: right after a group is created, one
    access type's assignment can be listed before the other, and falling back to the first assignment
    then returned the MEMBER policy for an OWNER lookup, so owner settings were written to the member
    policy with no error. $null is also returned when the group has no policy assignment at all yet
    (it has not been onboarded to PIM for Groups) -- including when Graph says so with 400
    ResourceTypeNotSupported, which is declared to the transport as an expected answer so it is never
    raised as an error. Ported from a prior internal Get-PimGroupPolicyId. Used by
    Get-OERGroupPimPolicy, Set-OERGroupPimPolicy, Get-OERGroupPermanentEligibilityState and
    Get-OERInventory.

    .PARAMETER GroupId
    The object id of the group whose PIM policy id is resolved.

    .PARAMETER AccessType
    The access type whose policy is wanted: member (default) or owner.

    .EXAMPLE
    Get-OERPimGroupPolicyId -GroupId $GroupId -AccessType member
    Returns the policy id governing member activation for the group, or $null if not onboarded.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member'
    )
    $Escaped = $GroupId.Replace("'", "''")
    $Uri = Get-OERPimGroupsGraphPath -Path "policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$Escaped' and scopeType eq 'Group'"
    # A group that is not onboarded to PIM for Groups answers this beta endpoint with 400
    # ResourceTypeNotSupported, which is exactly the "no policy assignment yet" this function is
    # documented to report as $null. Declaring it at the REQUEST is what keeps it out of the
    # caller's -ErrorVariable: all three callers already wrap this call in
    # try { } catch { Remove-OERErrorRecord; $null }, which turned the throw back into the same
    # $null only AFTER the engine had recorded it -- and -ErrorVariable is filled by the engine, so
    # no catch could ever reach those records. Every other failure (403, 429, 500) still throws and
    # those catches still handle it.
    $Response = Invoke-OERGraphRequest -Uri $Uri -ExpectedErrorCode 'ResourceTypeNotSupported'
    if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') { return $null }
    if (-not $Response.value -or @($Response.value).Count -eq 0) { return $null }

    $Assignment = @($Response.value) | Where-Object { $_.roleDefinitionId -eq $AccessType } | Select-Object -First 1
    if (-not $Assignment) { return $null }
    [string]$Assignment.policyId
}
