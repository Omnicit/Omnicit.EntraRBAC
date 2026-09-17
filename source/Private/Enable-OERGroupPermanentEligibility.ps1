function Enable-OERGroupPermanentEligibility {
    <#
    .SYNOPSIS
    Surgically opens a PIM-for-groups policy to allow permanent eligible assignments.

    .DESCRIPTION
    Reads the Expiration_Admin_Eligibility rule of a PIM-for-groups roleManagementPolicy and PATCHes
    only its isExpirationRequired flag to false (preserving the rule's @odata.type, id, maximumDuration,
    and target). Unlike Set-OERGroupPimPolicy -- which rebuilds the entire activation rule set from a
    template and would reset the activation window, durations, and enablement rules -- this changes the
    single permanence flag and leaves every other rule untouched. The change is performed under
    ShouldProcess so an inherited -WhatIf reports it without writing and -Confirm can decline it.
    Returns $true when the PATCH was actually sent and $false when that gate declined it, so the caller
    can tell whether the policy was really opened rather than assuming the call wrote. Graph failures
    are re-thrown (after removing the request from $Error for bearer-token hygiene) so the calling
    cmdlet can route a clear PolicyOpenFailed error. Used by the permanent self-heal in
    Add-OERGroupEligibility.

    .PARAMETER PolicyId
    The id of the group's roleManagementPolicy whose eligibility expiration rule is opened.

    .EXAMPLE
    Enable-OERGroupPermanentEligibility -PolicyId 'Group_00000000-0000-0000-0000-000000000001_member'
    Sets isExpirationRequired to false on the group's eligibility expiration rule and returns $true.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId
    )

    $RuleUri = Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules/Expiration_Admin_Eligibility" -f $PolicyId)
    try {
        $Rule = Invoke-OERGraphRequest -Uri $RuleUri
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw
    }

    # Clone via a JSON round-trip so the source object is never mutated, then add-or-set the flag
    # (a default policy may omit it). -AsHashtable produces a [hashtable] compatible with the
    # [hashtable]$Body parameter of Invoke-OERGraphRequest. Direct key assignment adds or replaces
    # uniformly (equivalent to Add-Member -Force on a PSCustomObject).
    $Clone = $Rule | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
    $Clone['isExpirationRequired'] = $false

    if ($PSCmdlet.ShouldProcess("PIM-for-groups policy '$PolicyId'", 'Allow permanent eligible assignments')) {
        try {
            Invoke-OERGraphRequest -Method PATCH -Uri $RuleUri -Body $Clone | Out-Null
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            throw
        }
        return $true
    }
    # -WhatIf, or a -Confirm prompt answered No: nothing was written, and the caller must not later
    # claim (or try to roll back) a policy this call never touched.
    return $false
}
