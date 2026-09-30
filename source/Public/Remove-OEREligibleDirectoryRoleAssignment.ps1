function Remove-OEREligibleDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Removes an eligible Microsoft Entra directory role assignment (PIM) from a principal.

    .DESCRIPTION
    Submits a Microsoft Graph v1.0 roleManagement/directory/roleEligibilityScheduleRequests request
    with action adminRemove via Invoke-OERGraphRequest to revoke an existing eligibility. No
    scheduleInfo is sent. The eligibility is identified by its role and principal at tenant scope
    (directoryScopeId '/' -- the only scope a directory role eligibility supports). The principal may
    be given directly as -PrincipalId (object id, for example piped from
    Get-OEREligibleDirectoryRoleAssignment) or as a friendly -User/-Group/-ServicePrincipal value.
    This is a destructive operation (ConfirmImpact High) and emits a warning before the request.
    Supports -WhatIf/-Confirm. Authentication is ensured via Initialize-OERAuth (no ARM token is
    acquired; this is a Graph-only cmdlet).

    Because -PrincipalId binds from the pipeline by property name and takes precedence over the
    friendly parameters, supplying -User, -Group or -ServicePrincipal while piping objects that carry
    their own PrincipalId (for example Get-OEREligibleDirectoryRoleAssignment output) is rejected with
    a non-terminating AmbiguousPrincipal error (Ruling P3) rather than silently removing each piped
    item's own principal's eligibility.

    Only a DIRECT eligibility can be removed. A piped row whose MemberType is set to anything other
    than Direct (a row Get-OEREligibleDirectoryRoleAssignment returns for a member who is eligible
    through a group) is refused with a non-terminating NotDirectAssignment error before any Graph
    call: the request names only the role and the principal, so it would remove that member's own
    direct eligibility instead, if one exists. Remove the group's own eligibility, or the member from
    the group, instead.

    For least privilege, RoleEligibilitySchedule.ReadWrite.Directory is enough for the write and
    RoleManagement.Read.Directory resolves -Role; the module's default sign-in scope list already
    requests the broader RoleManagement.ReadWrite.Directory, which covers both. A delegated caller
    additionally needs the Privileged Role Administrator role.

    Microsoft Graph refuses the removal with ActiveDurationTooShort until the principal's active
    assignment of the role has run for five minutes (measured live); remove it again after that.

    Microsoft Graph can answer RoleAssignmentDoesNotExist to a removal it carried out (measured live
    for an active assignment: the request is listed Revoked and the assignment is gone). On that
    answer the cmdlet reads the principal's eligible assignments of the role again. When that read
    succeeds and finds no direct eligible assignment of the role at tenant scope, the removal counts
    as done: no error is written, no request object is returned, and a verbose line says why. That
    also holds for an eligible assignment that was already gone before the call. When the read fails,
    or finds the eligible assignment still in place, the RoleAssignmentDoesNotExist error is written
    as before. When the removal counts as done but the read shows the principal still eligible
    another way -- through a group, or at a directory scope narrower than the tenant -- a warning
    says which.

    .PARAMETER Role
    The directory role: display name (matched without regard to letter case) or role definition id.
    Pipeline by property name (RoleDefinitionId). A name matching more than one role definition is
    refused (AmbiguousRoleName, listing the candidate ids); no match is RoleDefinitionNotFound; a
    failed lookup is RoleDefinitionReadFailed.

    .PARAMETER PrincipalId
    The object id (GUID) of the principal whose eligibility is removed. Pipeline by property name;
    takes precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use -User,
    -Group, or -ServicePrincipal instead.

    .PARAMETER User
    A user principal name or object id whose eligibility is removed.

    .PARAMETER Group
    A group display name or object id whose eligibility is removed.

    .PARAMETER ServicePrincipal
    A service principal display name or object id whose eligibility is removed.

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
    Remove-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'anna.berg@example.com'
    Removes Anna's eligibility for the Reports Reader directory role.

    .EXAMPLE
    Get-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'anna.berg@example.com' |
        Where-Object { $_.MemberType -eq 'Direct' } | Remove-OEREligibleDirectoryRoleAssignment
    Removes the piped eligibility, filtered to a direct one -- Get-OEREligibleDirectoryRoleAssignment
    also returns rows inherited through a group, which this cmdlet refuses with NotDirectAssignment
    (remove the group's own eligibility instead); the filter keeps them out of the pipe.
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
        # own PrincipalId (for example Get-OEREligibleDirectoryRoleAssignment output) would silently
        # ignore a named principal and remove each piped item's OWN principal's eligibility instead.
        # Refused, not warned about -- Ruling P3, the same AmbiguousPrincipal treatment the New twin
        # and Remove-OERGroupEligibility give the identical collision. $PSItem is read rather than the
        # frozen -PrincipalId parameter variable, since PowerShell freezes an explicitly bound
        # parameter for the rest of the pipeline. Placed first in process, before any Graph call.
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $PSItem.PrincipalId -and
            ($PSBoundParameters.ContainsKey('User') -or $PSBoundParameters.ContainsKey('Group') -or
                $PSBoundParameters.ContainsKey('ServicePrincipal'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new("A principal was supplied by name while objects carrying their own PrincipalId '$($PSItem.PrincipalId)' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and each piped item's own principal would lose its eligible assignment instead. Supply either the named principal or the pipeline, not both.")) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $PSItem.PrincipalId -Cmdlet $PSCmdlet
            return
        }

        # A piped row inherited through a group carries the MEMBER's PrincipalId; the adminRemove
        # request names only the role and the principal, so it would remove that principal's own
        # DIRECT eligible assignment (if one exists) instead of the piped row. Refused before any
        # Graph call. A piped object without MemberType (not Get- output) is left to the request as
        # before. An eligibility has no AssignmentType, so the Active twin's activation branch has
        # no counterpart here.
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $NotDirectReason = $null
            $NotDirectAdvice = $null
            if ($PSItem.MemberType -and [string]$PSItem.MemberType -ne 'Direct') {
                $NotDirectReason = "is inherited through a group (MemberType '$($PSItem.MemberType)'), not a direct one"
                $NotDirectAdvice = " Remove the group's own eligible assignment, or the principal from the group."
            }
            if ($NotDirectReason) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("The piped eligible assignment of directory role '$Role' for principal '$($PSItem.PrincipalId)' $NotDirectReason, so it is not removed: the request names only the role and the principal, and would remove that principal's own direct eligible assignment instead, if one exists.$NotDirectAdvice")) `
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
        Write-Verbose "[Remove-OEREligibleDirectoryRoleAssignment] Resolved role '$Role' to '$($RoleInput.RoleDefinitionId)'."

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -ServicePrincipal $ServicePrincipal
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Remove-OEREligibleDirectoryRoleAssignment] Resolved principal to '$($Principal.PrincipalId)'."

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
            Justification    = if ($Justification) { $Justification } else { 'Omnicit.EntraRBAC: directory role eligible assignment removal' }
        }
        if ($TicketNumber) { $BodyParams.TicketNumber = $TicketNumber }
        if ($TicketSystem) { $BodyParams.TicketSystem = $TicketSystem }
        $Body = New-OERDirectoryRoleScheduleRequestBody @BodyParams

        $Target = "eligible directory role '$Role' for principal '$PrincipalLabel' at directory scope '/'"
        if ($PSCmdlet.ShouldProcess($Target, 'Remove eligible directory role assignment')) {
            Write-Warning "Removing $Target."
            try {
                $Response = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleEligibilityScheduleRequests' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $RemoveError = $PSItem
                # Measured live: Graph can answer RoleAssignmentDoesNotExist to a removal it carried out.
                # Only a re-read that succeeds and finds no direct eligibility left makes it a success;
                # a failed re-read, or an eligibility still in place, keeps the error.
                $Check = Test-OERDirectoryRoleAssignmentGone -Record $RemoveError -Kind Eligible `
                    -RoleDefinitionId $RoleInput.RoleDefinitionId -PrincipalId $Principal.PrincipalId
                if ($Check.Detail) { Write-Verbose "[Remove-OEREligibleDirectoryRoleAssignment] $($Check.Detail)" }
                if ($Check.Gone) {
                    # Done, but the principal keeps the role another way: say so, with no id beyond $Target's.
                    if ($Check.StillHeld) { Write-Warning "Removed $Target, but the principal still holds the role $($Check.StillHeld)." }
                    return
                }
                $PSCmdlet.WriteError($RemoveError)
                return
            }
            ConvertTo-OERDirectoryRoleScheduleRequest -InputObject $Response -Kind Eligible
        }
    }
}
