function Get-OERActiveDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Lists Microsoft Entra directory role assignment schedules (PIM active assignments).

    .DESCRIPTION
    Reads unifiedRoleAssignmentSchedule objects from Microsoft Graph v1.0
    (roleManagement/directory/roleAssignmentSchedules) at tenant scope (directoryScopeId '/'), with
    principal and roleDefinition expanded in the same call ($expand=principal,roleDefinition), and
    the list is paged with -All. Without a filter every assignment schedule at tenant scope is
    returned, direct and group-inherited alike -- MemberType on the returned object tells them apart
    (Direct or Group). Each row's AssignmentType is either Assigned (a standing active assignment
    made directly, without going through PIM eligibility) or Activated (the currently-active window
    created by activating an eligible assignment); an activation of an eligible assignment appears
    as its own row here, alongside any directly-assigned row for the same role and principal, rather
    than merging into one. -Role narrows the read to one directory role, given as a display name in
    any letter case or as a role definition id, resolved through the shared Resolve-OERDirectoryRoleInput
    helper: a name that matches more than one role definition is refused (AmbiguousRoleName, listing
    the candidate ids), a lookup that fails is RoleDefinitionReadFailed (existence unknown, not
    reported as missing), and no match is RoleDefinitionNotFound -- each a non-terminating error that
    returns nothing and issues no schedule request. A principal filter (-PrincipalId, or one of
    -User, -Group, -ServicePrincipal resolved through Microsoft Graph) narrows the read to one
    principal's own assignment schedules, direct and group-inherited alike. No ARM token is
    acquired: Initialize-OERAuth is called without -IncludeARM. For least privilege,
    RoleAssignmentSchedule.Read.Directory is enough to read this list; the module's default sign-in
    scope list already requests the broader RoleManagement.ReadWrite.Directory, so no separate
    consent step is needed.

    .PARAMETER Role
    The directory role to filter on: a display name (matched without regard to letter case) or a
    role definition id. A name that is ambiguous in either exact or case-insensitive form refuses
    with AmbiguousRoleName, listing the candidate ids; no match is RoleDefinitionNotFound; a failed
    lookup is RoleDefinitionReadFailed. Omit to list every directory role's assignment schedules.

    .PARAMETER User
    A user to filter on, given as a user principal name or object id and resolved via
    Resolve-OERPrincipal. Mutually exclusive with -Group, -ServicePrincipal and -PrincipalId.

    .PARAMETER Group
    A group to filter on, given as a display name or object id and resolved via Resolve-OERPrincipal.
    This is the assigned PRINCIPAL, not a target group -- this cmdlet has no target group. Mutually
    exclusive with -User, -ServicePrincipal and -PrincipalId.

    .PARAMETER ServicePrincipal
    A service principal to filter on, given as a display name or object id and resolved via
    Resolve-OERPrincipal. Mutually exclusive with -User, -Group and -PrincipalId.

    .PARAMETER PrincipalId
    The raw object id (GUID) of the principal to filter on. Mutually exclusive with -User, -Group
    and -ServicePrincipal. A non-GUID value yields an InvalidPrincipalId error directing you to the
    friendly parameters instead.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERActiveDirectoryRoleAssignment -Role 'Reports Reader'
    Lists every active assignment schedule (standing and activated alike) for the built-in Reports
    Reader directory role, tenant-wide.

    .EXAMPLE
    Get-OERActiveDirectoryRoleAssignment -User 'anna.berg@example.com'
    Lists every directory role assignment schedule for that user, direct and group-inherited alike.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal,
        [string]$PrincipalId,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Filter = "directoryScopeId eq '/'"

        if ($Role) {
            $RoleInput = Resolve-OERDirectoryRoleInput -Role $Role
            if ($RoleInput.ErrorId) {
                $ErrParams = @{
                    Message      = [System.Exception]::new($RoleInput.Message)
                    ErrorId      = $RoleInput.ErrorId
                    Category     = $RoleInput.Category
                    TargetObject = $Role
                    Cmdlet       = $PSCmdlet
                }
                if ($RoleInput.InnerException) { $ErrParams.InnerException = $RoleInput.InnerException }
                Write-CmdletError @ErrParams
                return
            }
            $Filter += " and roleDefinitionId eq '$(ConvertTo-OERODataFilterValue -Value $RoleInput.RoleDefinitionId)'"
        }

        if ($PrincipalId -or $User -or $Group -or $ServicePrincipal) {
            $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group -ServicePrincipal $ServicePrincipal
            if ($Principal.ErrorId) {
                Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                    -ErrorId $Principal.ErrorId -Category $Principal.Category `
                    -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
                return
            }
            # Lower-cased like the role id (Resolve-OERDirectoryRoleDefinitionId), so a -PrincipalId
            # typed in upper case still matches the lower-case id Graph stores.
            $Filter += " and principalId eq '$(ConvertTo-OERODataFilterValue -Value ([string]$Principal.PrincipalId).ToLowerInvariant())'"
        }

        try {
            $Response = Invoke-OERGraphRequest -Uri "v1.0/roleManagement/directory/roleAssignmentSchedules?`$filter=$Filter&`$expand=principal,roleDefinition" -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            if ($null -ne $Item) { ConvertTo-OERDirectoryRoleAssignment -InputObject $Item -Kind Active }
        }
    }
}
