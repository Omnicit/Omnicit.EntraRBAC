function Remove-OERActiveDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Removes an active Microsoft Entra directory role assignment (PIM) from a principal.

    .DESCRIPTION
    Submits a Microsoft Graph v1.0 roleManagement/directory/roleAssignmentScheduleRequests request
    with action adminRemove via Invoke-OERGraphRequest to revoke an existing active assignment. No
    scheduleInfo is sent. The assignment is identified by its role and principal at tenant scope
    (directoryScopeId '/' -- the only scope a directory role assignment supports). The principal may
    be given directly as -PrincipalId (object id, for example piped from
    Get-OERActiveDirectoryRoleAssignment) or as a friendly -User/-Group/-ServicePrincipal value. Only
    a standing (Assigned) active assignment can be removed this way; an activation (AssignmentType
    Activated) of an eligible assignment ends on its own schedule or through the eligible
    assignment's own removal. This is a destructive operation (ConfirmImpact High) and emits a
    warning before the request. Supports -WhatIf/-Confirm. Authentication is ensured via
    Initialize-OERAuth (no ARM token is acquired; this is a Graph-only cmdlet).

    For least privilege, RoleAssignmentSchedule.ReadWrite.Directory is enough for the write and
    RoleManagement.Read.Directory resolves -Role; the module's default sign-in scope list already
    requests the broader RoleManagement.ReadWrite.Directory, which covers both. A delegated caller
    additionally needs the Privileged Role Administrator role.

    .PARAMETER Role
    The directory role: display name (matched without regard to letter case) or role definition id.
    Pipeline by property name (RoleDefinitionId). A name matching more than one role definition is
    refused (AmbiguousRoleName, listing the candidate ids); no match is RoleDefinitionNotFound; a
    failed lookup is RoleDefinitionReadFailed.

    .PARAMETER PrincipalId
    The object id (GUID) of the principal whose active assignment is removed. Pipeline by property
    name; takes precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use
    -User, -Group, or -ServicePrincipal instead.

    .PARAMETER User
    A user principal name or object id whose active assignment is removed.

    .PARAMETER Group
    A group display name or object id whose active assignment is removed.

    .PARAMETER ServicePrincipal
    A service principal display name or object id whose active assignment is removed.

    .PARAMETER Justification
    Justification recorded on the removal request. Defaults to a standard scaffolding note when
    omitted.

    .PARAMETER TicketNumber
    Ticket number recorded on the removal request.

    .PARAMETER TicketSystem
    Ticket system name recorded on the removal request.

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'anna.berg@example.com'
    Removes Anna's active assignment of the Reports Reader directory role.

    .EXAMPLE
    Get-OERActiveDirectoryRoleAssignment -Role 'Reports Reader' -User 'anna.berg@example.com' |
        Where-Object { $_.MemberType -eq 'Direct' -and $_.AssignmentType -eq 'Assigned' } |
        Remove-OERActiveDirectoryRoleAssignment
    Removes the piped active assignment, filtered to a direct, standing one --
    Get-OERActiveDirectoryRoleAssignment also returns activations and group-inherited rows, which
    this cmdlet cannot remove directly (an activation ends on its own schedule or through the
    eligible assignment's removal; a group-inherited row is removed from the group instead).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$PrincipalId,

        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal,

        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
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
        Write-Verbose "[Remove-OERActiveDirectoryRoleAssignment] Resolved role '$Role' to '$($RoleInput.RoleDefinitionId)'."

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -ServicePrincipal $ServicePrincipal
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Remove-OERActiveDirectoryRoleAssignment] Resolved principal to '$($Principal.PrincipalId)'."

        # Name the principal that will ACTUALLY be acted on, not merely the one the operator typed.
        $PrincipalLabel = if ($PrincipalId) { $Principal.PrincipalId }
        elseif ($User) { $User }
        elseif ($Group) { $Group }
        elseif ($ServicePrincipal) { $ServicePrincipal }
        else { $Principal.PrincipalId }

        $BodyParams = @{
            Action           = 'adminRemove'
            PrincipalId      = $Principal.PrincipalId
            RoleDefinitionId = $RoleInput.RoleDefinitionId
            Justification    = if ($Justification) { $Justification } else { 'Omnicit.EntraRBAC: directory role active assignment removal' }
        }
        if ($TicketNumber) { $BodyParams.TicketNumber = $TicketNumber }
        if ($TicketSystem) { $BodyParams.TicketSystem = $TicketSystem }
        $Body = New-OERDirectoryRoleScheduleRequestBody @BodyParams

        $Target = "active directory role '$Role' for principal '$PrincipalLabel' at directory scope '/'"
        if ($PSCmdlet.ShouldProcess($Target, 'Remove active directory role assignment')) {
            Write-Warning "Removing $Target."
            try {
                $Response = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERDirectoryRoleScheduleRequest -InputObject $Response -Kind Active
        }
    }
}
