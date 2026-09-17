function Remove-OERGroupEligibility {
    <#
    .SYNOPSIS
    Removes a principal's PIM-for-groups eligibility for a group.

    .DESCRIPTION
    Creates a PIM-for-groups eligibility schedule request with action adminRemove to revoke a principal's
    eligibility for the member (or owner) access of a group given by -Group (display name or object id,
    resolved via Resolve-OERGroupId). The principal is named with -User (user principal name or object id),
    -GroupPrincipal (group display name or object id), or -ServicePrincipal (service principal display
    name or object id), or supplied as a raw object id with -PrincipalId. Supply exactly one. Note that
    -Group is the TARGET group whose access is granted, while -GroupPrincipal is the group whose
    eligibility is revoked. The request body is built by the private New-OERGroupEligibilityBody helper.
    The result is a tagged Omnicit.EntraRBAC.GroupEligibility object. Supports -WhatIf and -Confirm.

    Because -PrincipalId binds from the pipeline by property name, supplying -User, -GroupPrincipal or
    -ServicePrincipal together with piped input is rejected with a non-terminating AmbiguousPrincipal
    error instead of silently applying the named principal's precedence rule to every piped item.

    .PARAMETER Group
    The target group from which eligibility is removed, given as a display name or object id (GUID) and
    resolved via Resolve-OERGroupId. Accepts the GroupId, Id, and DisplayName aliases (GroupId takes
    precedence during pipeline binding so a piped Get-OERGroupMember object binds the group's GroupId
    instead of a principal's Id) and binds from the pipeline by property name so Get-OERGroup pipes
    straight in.

    .PARAMETER PrincipalId
    The object id (GUID) of the principal whose eligibility is revoked -- a user, group, or service
    principal. Mutually exclusive with -User; supply exactly one. A non-GUID value yields an
    InvalidPrincipalId error directing you to -User, -GroupPrincipal or -ServicePrincipal. Binds from the
    pipeline by property name so Get-OERGroupEligibility pipes an existing eligibility straight in for
    revocation.

    .PARAMETER User
    The user whose eligibility is revoked, given as a user principal name or object id (GUID) and resolved
    via Resolve-OERPrincipal. Mutually exclusive with -PrincipalId, -GroupPrincipal and -ServicePrincipal;
    supply exactly one.

    .PARAMETER GroupPrincipal
    The group whose eligibility is revoked, given as a group display name or object id (GUID) and
    resolved via Resolve-OERPrincipal. This is the principal being revoked, not the target group -- the
    target group is -Group. Mutually exclusive with the other principal parameters. Group display
    names are not guaranteed unique in Entra ID; if more than one group shares the given name, the
    command fails with an error naming the candidate object ids, so re-run with the object id.

    .PARAMETER ServicePrincipal
    The service principal whose eligibility is revoked, given as a service principal display name or
    object id (GUID) and resolved via Resolve-OERPrincipal. A GUID is treated as the service principal
    object id, never as an application id. Mutually exclusive with the other principal parameters.

    .PARAMETER AccessType
    Whether the eligibility being removed is for member or owner access of the group. Defaults to member.
    Binds from the pipeline by property name so a piped Get-OERGroupEligibility object revokes the same
    access (member or owner) it reported.

    .PARAMETER Justification
    Justification text recorded on the eligibility schedule request for audit purposes.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERGroupEligibility -Group 'role_sec_identity_administrator' -User 'anna.berg@contoso.com'
    Revokes the user's PIM-for-groups member eligibility for the group.

    .EXAMPLE
    Get-OERGroupEligibility -Group 'role_sec_identity_administrator' | Remove-OERGroupEligibility -WhatIf
    Pipes the group's existing eligibilities in and previews revoking each (group, principal, and access
    type all bind from the pipeline).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$PrincipalId,

        [string]$User,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [string]$Justification = 'Omnicit.EntraRBAC: remove PIM-for-groups eligibility',

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [string]$GroupPrincipal,

        [string]$ServicePrincipal
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
        Write-Verbose "[Remove-OERGroupEligibility] Resolved group to '$GroupId'."

        if ($PSCmdlet.MyInvocation.ExpectingInput -and
            ($PSBoundParameters.ContainsKey('User') -or $PSBoundParameters.ContainsKey('GroupPrincipal') -or
                $PSBoundParameters.ContainsKey('ServicePrincipal'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new('A principal was supplied by name while objects are being piped in. The piped -PrincipalId takes precedence and the named principal would be ignored for every piped item. Supply either the named principal or the pipeline, not both.')) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User `
            -Group $GroupPrincipal -GroupParameterName 'GroupPrincipal' -ServicePrincipal $ServicePrincipal `
            -FriendlyParameterHint '-User, -GroupPrincipal or -ServicePrincipal'
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        $ResolvedPrincipalId = $Principal.PrincipalId
        Write-Verbose "[Remove-OERGroupEligibility] Resolved principal to '$ResolvedPrincipalId'."

        $Body = New-OERGroupEligibilityBody `
            -GroupId      $GroupId `
            -PrincipalId  $ResolvedPrincipalId `
            -AccessType   $AccessType `
            -Action       'adminRemove' `
            -Justification $Justification

        if ($PSCmdlet.ShouldProcess($GroupId, "Remove PIM $AccessType eligibility from '$ResolvedPrincipalId'")) {
            Write-Warning "Removing PIM $AccessType eligibility for principal '$ResolvedPrincipalId' from group '$GroupId'. The principal loses the ability to activate this $AccessType access."
            try {
                $Response = Invoke-OERGraphRequest -Method POST -Uri (Get-OERPimGroupsGraphPath -Path 'identityGovernance/privilegedAccess/group/eligibilityScheduleRequests') -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERGroupEligibilityRequest -InputObject $Response `
                -GroupId $GroupId -PrincipalId $ResolvedPrincipalId -AccessType $AccessType -Action 'adminRemove'
        }
    }
}
