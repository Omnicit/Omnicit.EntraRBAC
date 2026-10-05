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
    policy with no error. $null is also returned when Graph lists no policy assignment for the group at
    all, and when it answers 400 ResourceTypeNotSupported, which is declared to the transport as an
    expected answer so it is never raised as an error. A group that was never used with PIM for Groups
    is NOT such a case: Microsoft Graph lists its policy assignments before the group is onboarded
    (measured live 2026-09-28), so this function returns that policy's id. The first update of that
    policy, like the first eligibility or assignment request, onboards the group to PIM for Groups,
    which cannot be undone, and the policy ids change when it does (Microsoft Graph documentation,
    "Onboarding groups to PIM for Groups"). Ported from a prior internal Get-PimGroupPolicyId. Used by
    Get-OERGroupPimPolicy, Set-OERGroupPimPolicy, Get-OERGroupPermanentEligibilityState,
    Get-OERInventory and Sync-OERStructureGroup.

    .PARAMETER GroupId
    The object id of the group whose PIM policy id is resolved.

    .PARAMETER AccessType
    The access type whose policy is wanted: member (default) or owner.

    .PARAMETER NotFoundAsUnlisted
    Also reports a 404 ResourceNotFound answer as $null ("not listed yet") instead of throwing it. For
    the apply engine's wait on a group created in the same run ONLY: a group PIM does not know yet
    answers this query with 404 ResourceNotFound rather than with an empty list (measured live
    2026-09-28), and for such a group that is replication, not a failed read. The code is declared to
    the transport, so the answer leaves no record in the caller's -ErrorVariable. The same code with
    any status other than 404 is still thrown. Every other caller omits this switch and a 404 throws
    there, exactly as before.

    .EXAMPLE
    Get-OERPimGroupPolicyId -GroupId $GroupId -AccessType member
    Returns the policy id governing member activation for the group, or $null when Graph lists none.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [switch]$NotFoundAsUnlisted
    )
    $Escaped = $GroupId.Replace("'", "''")
    $Uri = Get-OERPimGroupsGraphPath -Path "policies/roleManagementPolicyAssignments?`$filter=scopeId eq '$Escaped' and scopeType eq 'Group'"
    # 400 ResourceTypeNotSupported ("Resource type not supported for onboarding") is an answer this
    # function reports as $null. Declaring it at the REQUEST is what keeps it out of the caller's
    # -ErrorVariable, which the engine fills as the record is raised: a caller that caught the throw
    # and turned it back into the same $null would do so only AFTER the engine had recorded it, and
    # no catch could ever reach those records. Every other failure -- a 403, an exhausted 429, a
    # 5xx, and a 404 unless -NotFoundAsUnlisted declared it -- still throws, and each caller's catch
    # scrubs the record first and then does what that caller's own rule says:
    # Get-OERGroupPermanentEligibilityState rethrows it, Get-OERGroupPimPolicy and
    # Set-OERGroupPimPolicy report PimPolicyReadFailed, and Get-OERInventory and
    # Sync-OERStructureGroup read the policy directly. None of them takes it for "no policy is
    # listed". -NotFoundAsUnlisted declares ResourceNotFound the same way, for the same reason: a
    # wait that caught a thrown 404 would hand the caller its records even when the policy was
    # listed on the next look.
    $Expected = @('ResourceTypeNotSupported')
    if ($NotFoundAsUnlisted) { $Expected += 'ResourceNotFound' }
    $Response = Invoke-OERGraphRequest -Uri $Uri -ExpectedErrorCode $Expected
    if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
        if ([string]$Response.ExpectedErrorCode -eq 'ResourceNotFound') {
            # Only a 404 is "not listed yet". Graph's code without that status is not the answer the
            # wait exists for, so it stays a failure and stops the wait like any other.
            if (($Response.StatusCode -as [int]) -ne 404) {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new([string]$Response.Message),
                    'ResourceNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $GroupId)
            }
            Write-Verbose "[Get-OERPimGroupPolicyId] Microsoft Graph answered 404 ResourceNotFound for the policy assignments of group '$GroupId'; reporting them as not listed yet."
        }
        return $null
    }
    if (-not $Response.value -or @($Response.value).Count -eq 0) { return $null }

    $Assignment = @($Response.value) | Where-Object { $_.roleDefinitionId -eq $AccessType } | Select-Object -First 1
    if (-not $Assignment) { return $null }
    [string]$Assignment.policyId
}
