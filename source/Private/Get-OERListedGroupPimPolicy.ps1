function Get-OERListedGroupPimPolicy {
    <#
    .SYNOPSIS
    Reads a PIM-for-groups policy the caller has just seen listed, reporting a 404 as not readable yet.

    .DESCRIPTION
    Reads the rules of the roleManagementPolicy PolicyId -- an id Get-OERPimGroupPolicyId has just
    listed for the group -- and projects them through ConvertTo-OERGroupPimPolicy, the single owner of
    the policy read shape, exactly as Get-OERGroupPimPolicy does. For the apply engine's wait on a
    group created in the same run ONLY: right after a group is created, the assignment query can list
    its policy while the read of that policy a second later answers 404 ResourceNotFound (measured live
    2026-09-28, replicas that do not agree yet), and for such a group that is replication, not a failed
    read. ResourceNotFound is therefore declared to the transport, so a 404 comes back as $null and
    leaves no record in the caller's -ErrorVariable; the caller starts over from the listing. The same
    code with any status other than 404 is thrown, and so is every other failure (a 403, an
    exhausted 429, a 5xx), for the caller to handle as a refusal. Get-OERGroupPimPolicy keeps its
    own read, in which a 404 is an error.

    .PARAMETER GroupId
    The object id of the group the policy governs, stamped onto the output.

    .PARAMETER PolicyId
    The roleManagementPolicy id to read, as Get-OERPimGroupPolicyId listed it for the group.

    .PARAMETER AccessType
    The access type the policy governs, member or owner, stamped onto the output.

    .EXAMPLE
    Get-OERListedGroupPimPolicy -GroupId $Gid -PolicyId $ListedPolicyId -AccessType member
    Returns the tagged member-access policy of the group, or $null while Microsoft Graph answers 404.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [string]$PolicyId,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member'
    )
    $Uri = Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules" -f $PolicyId)
    # Declared at the REQUEST, as in Get-OERPimGroupPolicyId -NotFoundAsUnlisted: a caught throw would
    # still hand the caller its records, since -ErrorVariable is filled before any catch runs.
    $Response = Invoke-OERGraphRequest -Uri $Uri -All -ExpectedErrorCode 'ResourceNotFound'
    if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
        # Only a 404 is "not readable yet"; Graph's code without that status stays a failure.
        if (($Response.StatusCode -as [int]) -ne 404) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new([string]$Response.Message),
                'ResourceNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $PolicyId)
        }
        Write-Verbose "[Get-OERListedGroupPimPolicy] Microsoft Graph answered 404 ResourceNotFound for policy '$PolicyId' of group '$GroupId'; reporting it as not readable yet."
        return $null
    }
    ConvertTo-OERGroupPimPolicy -Rules @($Response.value) -GroupId $GroupId -PolicyId $PolicyId -AccessType $AccessType
}
