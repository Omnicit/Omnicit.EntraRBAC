function New-OEREligibleDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Grants a principal an eligible Microsoft Entra directory role assignment (PIM) at tenant scope.

    .DESCRIPTION
    Creates a Microsoft Graph v1.0 roleManagement/directory/roleEligibilityScheduleRequests resource
    with action adminAssign (default) or adminUpdate via Invoke-OERGraphRequest. The body carries the
    resolved role definition id, the principalId taken from -PrincipalId or resolved from
    -User/-Group/-ServicePrincipal, directoryScopeId '/' (tenant scope -- the only scope a directory
    role eligibility supports), and a schedule built from -Duration/-DurationDays/-EndDateTime/
    -Permanent (default permanent). Supports -WhatIf/-Confirm. Authentication is ensured via
    Initialize-OERAuth (no ARM token is acquired; this is a Graph-only cmdlet).

    Because -PrincipalId binds from the pipeline by property name and takes precedence over the
    friendly parameters, supplying -User, -Group or -ServicePrincipal while piping objects that carry
    their own PrincipalId (for example Get-OEREligibleDirectoryRoleAssignment output) is rejected with
    a non-terminating AmbiguousPrincipal error rather than silently making each piped item's own
    principal eligible.

    Before the request, when the resolved principal is a group (or of unknown type, i.e. a raw
    -PrincipalId), the cmdlet reads whether that group is role-assignable
    (isAssignableToRole) with the private Get-OERRoleAssignableState helper: a group created without
    the role-assignable flag can never hold a directory role, and Microsoft Graph itself reports this
    only after the request is submitted, so the check runs first and fails fast with a
    GroupNotRoleAssignable error naming the offending group. A read that fails for any other reason
    (permission denied, transport failure) is written to Verbose and the request proceeds, letting
    Microsoft Graph enforce it.

    A permanent request (no -Duration/-DurationDays/-EndDateTime bound, whether by omission or by an
    explicit -Permanent) is pre-checked against the role's own PIM policy through the private
    Test-OERDirectoryRolePermanentAllowed helper. When the policy does not allow permanent eligible
    assignments the cmdlet reports PermanentAssignmentNotAllowed and submits NO request at all --
    Omnicit.EntraRBAC never changes a directory role's PIM policy implicitly, unlike the ARM eligible
    role assignment cmdlet, which auto-opens the equivalent Azure policy. A pre-check that fails to
    read (permission denied, transport failure) is written to Verbose and the request proceeds,
    letting Microsoft Graph enforce the policy.

    For least privilege, RoleEligibilitySchedule.ReadWrite.Directory is enough for the write and
    RoleManagement.Read.Directory resolves -Role; the module's default sign-in scope list already
    requests the broader RoleManagement.ReadWrite.Directory, which covers both. A delegated caller
    additionally needs the Privileged Role Administrator role.

    .PARAMETER Role
    The directory role: display name (matched without regard to letter case, e.g. 'Reports Reader')
    or role definition id. Pipeline by property name (RoleDefinitionId). A name matching more than
    one role definition is refused (AmbiguousRoleName, listing the candidate ids); no match is
    RoleDefinitionNotFound; a failed lookup is RoleDefinitionReadFailed.

    .PARAMETER User
    A user principal name or object id to make eligible.

    .PARAMETER Group
    A group display name or object id to make eligible. If the group is not role-assignable
    (isAssignableToRole false) the request fails fast with GroupNotRoleAssignable before any write.

    .PARAMETER ServicePrincipal
    A service principal display name or object id to make eligible.

    .PARAMETER Duration
    ISO 8601 duration (e.g. 'P30D') for a time-bound eligibility. Mutually exclusive with
    -DurationDays, -EndDateTime and -Permanent.

    .PARAMETER DurationDays
    Friendly time-bound eligibility lifetime in whole days (1-3650), converted to an ISO 8601
    duration. Mutually exclusive with -Duration, -EndDateTime and -Permanent.

    .PARAMETER EndDateTime
    Absolute end time for a time-bound eligibility; must be in the future. Mutually exclusive with
    -Duration, -DurationDays and -Permanent.

    .PARAMETER Permanent
    Make the eligibility permanent (no expiration). This is also the default when no schedule
    parameter is supplied at all. When the role's PIM policy forbids permanent eligible assignments
    the request is refused up front with PermanentAssignmentNotAllowed; nothing is changed.

    .PARAMETER Justification
    Justification recorded on the request. Defaults to a standard scaffolding note when omitted.

    .PARAMETER TicketNumber
    Ticket number recorded on the request.

    .PARAMETER TicketSystem
    Ticket system name recorded on the request.

    .PARAMETER Action
    The Microsoft Graph admin operation: adminAssign (default) creates a new eligibility; adminUpdate
    changes an existing one. The apply engine passes adminUpdate when re-issuing an eligibility whose
    declared window has drifted from the live schedule.

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.

    .PARAMETER PrincipalId
    The object id (GUID) of the principal to make eligible. Pipeline by property name; takes
    precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use -User,
    -Group, or -ServicePrincipal instead.

    .EXAMPLE
    New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -User 'anna.berg@example.com' -DurationDays 30
    Makes the user eligible for the Reports Reader directory role for 30 days.

    .EXAMPLE
    New-OEREligibleDirectoryRoleAssignment -Role 'Reports Reader' -Group 'oer-rag'
    Makes a role-assignable group permanently eligible for the Reports Reader directory role.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal,

        [ValidatePattern('^P(?=[YMWD0-9T])(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(\d+[HMS])+)?$')]
        [string]$Duration,
        [ValidateRange(1, 3650)]
        [int]$DurationDays,
        [datetime]$EndDateTime,
        [switch]$Permanent,

        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,

        [ValidateSet('adminAssign', 'adminUpdate')]
        [string]$Action = 'adminAssign',

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$PrincipalId
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
        # ignore a named principal and make each piped item's OWN principal eligible instead. Refused,
        # not warned about -- the same AmbiguousPrincipal treatment New-OEREligibleRoleAssignment gives
        # the identical collision. $PSItem is read rather than the frozen -PrincipalId parameter
        # variable, since PowerShell freezes an explicitly bound parameter for the rest of the pipeline.
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $PSItem.PrincipalId -and
            ($PSBoundParameters.ContainsKey('User') -or $PSBoundParameters.ContainsKey('Group') -or
                $PSBoundParameters.ContainsKey('ServicePrincipal'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new("A principal was supplied by name while objects carrying their own PrincipalId '$($PSItem.PrincipalId)' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and each piped item's own principal made eligible instead. Supply either the named principal or the pipeline, not both.")) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $PSItem.PrincipalId -Cmdlet $PSCmdlet
            return
        }

        # Cheap, purely local parameter-shape checks run before any resolution.
        $ScheduleParamCount = 0
        if ($PSBoundParameters.ContainsKey('Duration')) { $ScheduleParamCount++ }
        if ($PSBoundParameters.ContainsKey('DurationDays')) { $ScheduleParamCount++ }
        if ($PSBoundParameters.ContainsKey('EndDateTime')) { $ScheduleParamCount++ }
        if ($Permanent) { $ScheduleParamCount++ }
        if ($ScheduleParamCount -gt 1) {
            Write-CmdletError -Message ([System.Exception]::new('Supply only one of -Duration, -DurationDays, -EndDateTime or -Permanent.')) `
                -ErrorId 'AmbiguousSchedule' -Category InvalidArgument -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }
        if ($PSBoundParameters.ContainsKey('EndDateTime') -and $EndDateTime.ToUniversalTime() -le [DateTime]::UtcNow) {
            Write-CmdletError -Message ([System.Exception]::new("-EndDateTime '$EndDateTime' must be in the future.")) `
                -ErrorId 'InvalidSchedule' -Category InvalidArgument -TargetObject $EndDateTime -Cmdlet $PSCmdlet
            return
        }
        $IsoDuration = if ($Duration) { $Duration }
        elseif ($PSBoundParameters.ContainsKey('DurationDays')) { ConvertTo-OERDuration -Days $DurationDays }
        else { $null }
        $IsPermanentRequest = -not ($PSBoundParameters.ContainsKey('Duration') -or
            $PSBoundParameters.ContainsKey('DurationDays') -or $PSBoundParameters.ContainsKey('EndDateTime'))

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
        Write-Verbose "[New-OEREligibleDirectoryRoleAssignment] Resolved role '$Role' to '$($RoleInput.RoleDefinitionId)'."

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -ServicePrincipal $ServicePrincipal
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[New-OEREligibleDirectoryRoleAssignment] Resolved principal to '$($Principal.PrincipalId)'."

        # Name the principal that will ACTUALLY be acted on, not merely the one the operator typed.
        $PrincipalLabel = if ($PrincipalId) { $Principal.PrincipalId }
        elseif ($User) { $User }
        elseif ($Group) { $Group }
        elseif ($ServicePrincipal) { $ServicePrincipal }
        else { $Principal.PrincipalId }
        $PrincipalTypeLabel = if ($Principal.PrincipalType) { $Principal.PrincipalType } else { 'principal' }

        # The role-assignable check runs when the principal is a group or of unknown type (a raw
        # -PrincipalId). Ruling R6.
        if ([string]::IsNullOrEmpty($Principal.PrincipalType) -or $Principal.PrincipalType -eq 'Group') {
            $Assignable = $null
            try {
                $Assignable = Get-OERRoleAssignableState -PrincipalId $Principal.PrincipalId
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Verbose "[New-OEREligibleDirectoryRoleAssignment] Could not check whether principal '$($Principal.PrincipalId)' is a role-assignable group: $($PSItem.Exception.Message). Proceeding; Microsoft Graph will enforce it."
            }
            if ($Assignable -and $Assignable.IsGroup -and -not $Assignable.IsAssignableToRole) {
                Write-CmdletError -Message ([System.Exception]::new(
                        "Group '$PrincipalLabel' is not role-assignable (isAssignableToRole is false), so it cannot " +
                        'hold a Microsoft Entra directory role. isAssignableToRole can only be set when a group is ' +
                        'created: create a role-assignable group (New-OERGroup -RoleAssignable) and assign the role to it.')) `
                    -ErrorId 'GroupNotRoleAssignable' -Category InvalidOperation -TargetObject $Principal.PrincipalId -Cmdlet $PSCmdlet
                return
            }
        }

        # The permanent pre-check is a READ, so it runs before ShouldProcess, like the ARM pre-check.
        # Ruling R7: it never opens the policy itself -- a refusal here submits NO request at all.
        if ($IsPermanentRequest) {
            $Allowed = $null
            try {
                $Allowed = Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId $RoleInput.RoleDefinitionId -Kind Eligible
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Verbose "[New-OEREligibleDirectoryRoleAssignment] Could not pre-check whether the PIM policy for role '$Role' allows a permanent eligible assignment: $($PSItem.Exception.Message). Proceeding; Microsoft Graph will enforce the policy."
            }
            if ($Allowed -eq $false) {
                Write-CmdletError -Message ([System.Exception]::new(
                        "The PIM policy of Microsoft Entra directory role '$Role' does not allow permanent eligible " +
                        'assignments, so Microsoft Graph would refuse this one, and Omnicit.EntraRBAC never changes a ' +
                        "policy implicitly. Nothing was changed. Allow it first with Set-OERDirectoryRoleManagementPolicy -Role '$Role' " +
                        "-AllowPermanentEligibility `$true, or declare allowPermanentEligibility: true for the role under " +
                        'directoryRoleManagementPolicies in the same apply document (that section runs first), or pass ' +
                        '-DurationDays for a time-bound assignment.')) `
                    -ErrorId 'PermanentAssignmentNotAllowed' -Category InvalidOperation -TargetObject $Role -Cmdlet $PSCmdlet
                return
            }
        }

        $BodyParams = @{
            Action           = $Action
            PrincipalId      = $Principal.PrincipalId
            RoleDefinitionId = $RoleInput.RoleDefinitionId
            Justification    = if ($Justification) { $Justification } else { 'Omnicit.EntraRBAC: directory role eligible assignment' }
        }
        if ($IsoDuration) { $BodyParams.Duration = $IsoDuration }
        elseif ($PSBoundParameters.ContainsKey('EndDateTime')) { $BodyParams.EndDateTime = $EndDateTime }
        if ($TicketNumber) { $BodyParams.TicketNumber = $TicketNumber }
        if ($TicketSystem) { $BodyParams.TicketSystem = $TicketSystem }
        $Body = New-OERDirectoryRoleScheduleRequestBody @BodyParams

        $Verb = if ($Action -eq 'adminUpdate') { 'Update' } else { 'Create' }
        $Target = "eligible directory role '$Role' for $PrincipalTypeLabel '$PrincipalLabel' at directory scope '/'"
        if ($PSCmdlet.ShouldProcess($Target, "$Verb eligible directory role assignment")) {
            try {
                $Response = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleEligibilityScheduleRequests' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERDirectoryRoleScheduleRequest -InputObject $Response -Kind Eligible
        }
    }
}
