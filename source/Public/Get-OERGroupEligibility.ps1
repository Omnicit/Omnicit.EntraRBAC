function Get-OERGroupEligibility {
    <#
    .SYNOPSIS
    Lists the PIM-for-groups eligible assignments configured on an Entra ID group.

    .DESCRIPTION
    Reads a group's current PIM-for-groups eligibility schedule instances and returns one tagged
    Omnicit.EntraRBAC.GroupEligibilitySchedule object per instance (carrying AccessType, MemberType,
    and the StartDateTime/EndDateTime window). The group is given by -Group (display name
    or GUID, resolved via Resolve-OERGroupId) and binds from the pipeline by property name so
    Get-OERGroup pipes straight in. Internally this reuses Get-OERGroup -IncludePimEligibility, which
    reads the beta eligibilityScheduleInstances endpoint and tolerates a group not onboarded to PIM for
    Groups (the beta endpoint returns 400 ResourceTypeNotSupported, treated as "no eligibility"); such
    a group simply returns nothing.

    .PARAMETER Group
    The group whose PIM eligibility is listed, given as a display name or object id (GUID) and
    resolved via Resolve-OERGroupId. Binds from the pipeline by property name and accepts the Id,
    GroupId, and DisplayName aliases. GroupId is checked before Id during pipeline binding, so a
    piped Get-OERGroupMember object (which carries both the principal's Id and the group's GroupId)
    binds the group correctly instead of mistaking the principal for the target group.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERGroupEligibility -Group 'role_sec_identity_administrator'
    Lists the eligible assignments for the group.

    .EXAMPLE
    Get-OERGroup -DisplayName 'role_sec_identity_administrator' | Get-OERGroupEligibility
    Pipes a group in and lists its PIM eligibility.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
        $GroupId = $null
        try {
            $GroupId = Resolve-OERGroupId -DisplayName $Group
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousGroupName' -Category InvalidArgument `
                    -TargetObject $Group -Cmdlet $PSCmdlet
                return
            }
        }
        if (-not $GroupId) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Group '$Group' not found. Verify the display name matches exactly (leading or trailing spaces " +
                    "and punctuation count) or pass the group object id instead.")) `
                -ErrorId 'GroupNotFound' -Category ObjectNotFound -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }
        $GroupObj = try {
            Get-OERGroup -Id $GroupId -IncludePimEligibility
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($GroupObj.PimEligibility)) {
            if ($null -eq $Item) { continue }
            ConvertTo-OERGroupEligibility -InputObject $Item -GroupId $GroupId
        }
    }
}
