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

    Because -PrincipalId binds from the pipeline by property name and takes precedence over the
    friendly parameters, supplying -User, -Group or -ServicePrincipal while piping objects that carry
    their own PrincipalId (for example Get-OERActiveDirectoryRoleAssignment output) is rejected with
    a non-terminating AmbiguousPrincipal error (Ruling P3) rather than silently removing each piped
    item's own principal's active assignment.

    Only a DIRECT, standing active assignment can be removed. A piped row whose MemberType is set to
    anything other than Direct (a row Get-OERActiveDirectoryRoleAssignment returns for a member who
    holds the role through a group), or whose AssignmentType is Activated (an activation of an
    eligible assignment), is refused with a non-terminating NotDirectAssignment error before any
    Graph call: the request names only the role and the principal, so it would remove that
    principal's own direct active assignment instead, if one exists. Remove the group's own
    assignment, or the member from the group; an activation ends on its own schedule or through the
    eligible assignment's removal.

    For least privilege, RoleAssignmentSchedule.ReadWrite.Directory is enough for the write and
    RoleManagement.Read.Directory resolves -Role; the module's default sign-in scope list already
    requests the broader RoleManagement.ReadWrite.Directory, which covers both. A delegated caller
    additionally needs the Privileged Role Administrator role.

    Microsoft Graph refuses the removal with ActiveDurationTooShort until the principal's active
    assignment of the role has run for five minutes (measured live); remove it again after that.

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
    Get-OERActiveDirectoryRoleAssignment also returns activations and rows inherited through a
    group, which this cmdlet refuses with NotDirectAssignment (an activation ends on its own
    schedule or through the eligible assignment's removal; an inherited row is removed through the
    group instead); the filter keeps them out of the pipe.
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
        # -PrincipalId binds from the pipeline by property name and Resolve-OERPrincipalOrId gives it
        # precedence over -User/-Group/-ServicePrincipal, so a pipe of objects that each carry their
        # own PrincipalId (for example Get-OERActiveDirectoryRoleAssignment output) would silently
        # ignore a named principal and remove each piped item's OWN principal's active assignment
        # instead. Refused, not warned about -- Ruling P3, the same AmbiguousPrincipal treatment the
        # New twin and Remove-OERGroupEligibility give the identical collision. $PSItem is read rather
        # than the frozen -PrincipalId parameter variable, since PowerShell freezes an explicitly
        # bound parameter for the rest of the pipeline. Placed first in process, before any Graph call.
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $PSItem.PrincipalId -and
            ($PSBoundParameters.ContainsKey('User') -or $PSBoundParameters.ContainsKey('Group') -or
                $PSBoundParameters.ContainsKey('ServicePrincipal'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new("A principal was supplied by name while objects carrying their own PrincipalId '$($PSItem.PrincipalId)' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and each piped item's own principal would lose its active assignment instead. Supply either the named principal or the pipeline, not both.")) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $PSItem.PrincipalId -Cmdlet $PSCmdlet
            return
        }

        # A piped row inherited through a group carries the MEMBER's PrincipalId, and an Activated row
        # the activating principal's; the adminRemove request names only the role and the principal,
        # so either would remove that principal's own DIRECT, standing active assignment (if one
        # exists) instead of the piped row. Refused before any Graph call. A piped object with neither
        # property (not Get- output) is left to the request as before.
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $NotDirectReason = $null
            $NotDirectAdvice = $null
            if ($PSItem.MemberType -and [string]$PSItem.MemberType -ne 'Direct') {
                $NotDirectReason = "is inherited through a group (MemberType '$($PSItem.MemberType)'), not a direct one"
                $NotDirectAdvice = " Remove the group's own active assignment, or the principal from the group."
            } elseif ([string]$PSItem.AssignmentType -eq 'Activated') {
                $NotDirectReason = 'is an activation, which PIM ends on its own, not a standing assignment'
                $NotDirectAdvice = ' It ends when its window closes, or when the eligible assignment is removed.'
            }
            if ($NotDirectReason) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("The piped active assignment of directory role '$Role' for principal '$($PSItem.PrincipalId)' $NotDirectReason, so it is not removed: the request names only the role and the principal, and would remove that principal's own direct active assignment instead, if one exists.$NotDirectAdvice")) `
                    -ErrorId 'NotDirectAssignment' -Category InvalidArgument -TargetObject $PSItem.PrincipalId -Cmdlet $PSCmdlet
                return
            }
        }

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
