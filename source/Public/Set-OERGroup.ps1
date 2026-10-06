function Set-OERGroup {
    <#
    .SYNOPSIS
    Updates the editable properties of an existing Entra ID group.

    .DESCRIPTION
    Patches an existing Entra ID group identified by -Group. Only the supplied properties are sent:
    -NewDisplayName, -Description, -MailNickname, -MembershipRule, and -MembershipRuleProcessingState.
    At least one updatable property must be supplied or a non-terminating NothingToUpdate error is
    emitted. A group name that matches nothing produces a non-terminating GroupNotFound error; a
    group lookup that itself fails (a refused, throttled or failed read) is reported as that
    failure, never as GroupNotFound.

    -MembershipRule and -MembershipRuleProcessingState only apply to a dynamic-membership group (one
    whose groupTypes contains DynamicMembership). A static or role-assignable group cannot be converted
    to dynamic after creation, so when either parameter targets a non-dynamic group the command emits a
    non-terminating NotDynamicGroup error instead of silently doing nothing; create the group with
    New-OERGroup -Dynamic -MembershipRule instead. After the PATCH the updated group is re-read and
    returned as a tagged Omnicit.EntraRBAC.Group object. Owners are managed separately with
    Add-OERGroupMember/Remove-OERGroupMember -AccessType owner. Supports -WhatIf and -Confirm.

    .PARAMETER Group
    The group to act on, given as either its object id (GUID) or its display name -- the same
    name-or-GUID target every membership, eligibility and PIM cmdlet in the module accepts. Binds
    from the pipeline by property name, and still accepts the historical -Id, -GroupId and
    -DisplayName parameter names as aliases. GroupId takes precedence during pipeline binding so a
    piped Get-OERGroupMember object binds the group's GroupId instead of a principal's Id.

    .PARAMETER NewDisplayName
    New display name to rename the group to. Distinct from -Group (or its -DisplayName alias),
    which only locates the existing group. Entra does not enforce unique group display names, so a
    rename to a name another group already carries is not refused.

    .PARAMETER Description
    New description for the group.

    .PARAMETER MailNickname
    New mail nickname for the group.

    .PARAMETER MembershipRule
    New dynamic-membership rule for the group. The target group must already be a dynamic-membership
    group; otherwise a NotDynamicGroup error is emitted (a static group cannot be made dynamic by patch).

    .PARAMETER MembershipRuleProcessingState
    Processing state for the dynamic-membership rule: On or Paused.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERGroup -Group 'role_sec_identity_administrator' -Description 'Updated identity admins'
    Updates the description of the named group and returns the refreshed group object.

    .EXAMPLE
    Set-OERGroup -Group 'role_sec_hr' -NewDisplayName 'role_sec_hr_emea'
    Renames the group from role_sec_hr to role_sec_hr_emea.

    .EXAMPLE
    Set-OERGroup -DisplayName 'role_sec_identity_administrator' -Description 'Updated identity admins'
    Updates the group, using the historical -DisplayName alias for -Group.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [ValidateNotNullOrEmpty()]
        [string]$NewDisplayName,

        [string]$Description,
        [string]$MailNickname,
        [string]$MembershipRule,

        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Body = @{}
        if ($PSBoundParameters.ContainsKey('NewDisplayName'))                { $Body.displayName = $NewDisplayName }
        if ($PSBoundParameters.ContainsKey('Description'))                   { $Body.description = $Description }
        if ($PSBoundParameters.ContainsKey('MailNickname'))                  { $Body.mailNickname = $MailNickname }
        if ($PSBoundParameters.ContainsKey('MembershipRule'))                { $Body.membershipRule = $MembershipRule }
        if ($PSBoundParameters.ContainsKey('MembershipRuleProcessingState')) { $Body.membershipRuleProcessingState = $MembershipRuleProcessingState }

        if ($Body.Count -eq 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No updatable property was supplied. Pass at least one of -NewDisplayName, -Description, -MailNickname, -MembershipRule, or -MembershipRuleProcessingState.')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject $Group `
                -Cmdlet $PSCmdlet
            return
        }

        # Refuse an ambiguous display name loudly, and surface any other throw as itself. Only a
        # $null return (a display name that matched nothing) reaches the not-found branch.
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
            # Anything else the resolver raised -- a 403, an exhausted 429, a 5xx -- is not evidence that
            # no such group exists: surface it as itself, never as the not-found below.
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if (-not $GroupId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("No group found to update for '$Group'.")) `
                -ErrorId 'GroupNotFound' `
                -Category ObjectNotFound `
                -TargetObject $Group `
                -Cmdlet $PSCmdlet
            return
        }

        # Membership-rule properties only take effect on a dynamic-membership group. Microsoft Graph
        # silently ignores them on a static/role-assignable group (and the kind cannot be changed by
        # patch), so verify up front and emit a clear error instead of a silent no-op.
        $TouchesMembership = $Body.ContainsKey('membershipRule') -or $Body.ContainsKey('membershipRuleProcessingState')
        if ($TouchesMembership) {
            try {
                $Current = Invoke-OERGraphRequest -Uri ("v1.0/groups/{0}?`$select=id,groupTypes" -f $GroupId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if (@($Current.groupTypes) -notcontains 'DynamicMembership') {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Group '$GroupId' is not a dynamic-membership group, so -MembershipRule/-MembershipRuleProcessingState cannot be applied. A static or role-assignable group cannot be converted to dynamic; create a dynamic group with New-OERGroup -Dynamic -MembershipRule instead.")) `
                    -ErrorId 'NotDynamicGroup' `
                    -Category InvalidOperation `
                    -TargetObject $GroupId `
                    -Cmdlet $PSCmdlet
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($GroupId, 'Update group properties')) {
            try {
                Invoke-OERGraphRequest -Method PATCH -Uri ("v1.0/groups/{0}" -f $GroupId) -Body $Body | Out-Null
                $Updated = Invoke-OERGraphRequest -Uri ("v1.0/groups/{0}" -f $GroupId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERGroup -InputObject $Updated
        }
    }
}
