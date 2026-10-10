function Test-OERRolePolicyModified {
    <#
    .SYNOPSIS
    Decides whether an Azure role management policy has been changed -- the single owner of that rule.

    .DESCRIPTION
    Reads the policy metadata an Azure role management policy assignment list row carries
    (properties.policyAssignmentProperties.policy, as Get-OERRoleManagementPolicyForScope returns it
    in PolicyMetadata) and decides whether the policy has been changed: a non-empty
    lastModifiedDateTime, a lastModifiedBy with a non-empty id, or a lastModifiedBy with a non-empty
    displayName -- the same three fields Test-OERGroupPimInUse reads for a PIM-for-Groups policy.
    Measured live on 2026-10-10 on one subscription's list: every untouched policy carried an id and
    an EMPTY lastModifiedBy object and no lastModifiedDateTime key, and every changed one a date and
    a display name. So an empty lastModifiedBy object is not a change, and neither is a value of white
    space only. A hashtable and a PSCustomObject are read the same way. Returns $null when there is no
    metadata at all, since there is nothing to judge: the caller keeps such a policy and names it as
    not judged, and never reads the null as "not changed". Sends nothing.

    .PARAMETER Metadata
    The policy metadata of one list row (PolicyMetadata of a Get-OERRoleManagementPolicyForScope
    result), or $null when the row carried none.

    .EXAMPLE
    Test-OERRolePolicyModified -Metadata ([PSCustomObject]@{ id = 'policy-1'; lastModifiedBy = [PSCustomObject]@{} })
    Returns $false: the measured shape of a policy nobody has changed.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Metadata
    )
    if ($null -eq $Metadata) { return $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$Metadata.lastModifiedDateTime)) { return $true }
    $LastModifiedBy = $Metadata.lastModifiedBy
    if ($null -ne $LastModifiedBy) {
        if (-not [string]::IsNullOrWhiteSpace([string]$LastModifiedBy.id)) { return $true }
        if (-not [string]::IsNullOrWhiteSpace([string]$LastModifiedBy.displayName)) { return $true }
    }
    $false
}
