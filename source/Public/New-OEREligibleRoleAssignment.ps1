function New-OEREligibleRoleAssignment {
    <#
    .SYNOPSIS
    Grants a principal an eligible Azure role assignment (PIM) at any scope.
    .DESCRIPTION
    Creates a Microsoft.Authorization/roleEligibilityScheduleRequests resource (api-version
    2020-10-01) with requestType AdminAssign via Invoke-OERArmRequest. The request name is a new
    client-generated GUID. The body carries the FULL ARM roleDefinitionId (resolved from a role
    display name, GUID, or full id), the principalId taken from -PrincipalId or resolved from
    -User/-Group/-ServicePrincipal, and a scheduleInfo built from -DurationDays/-Duration/
    -EndDateTime/-Permanent (default permanent). principalType is NOT sent (the schedule-request API
    treats it as response-only). Exactly one principal source and one scope source are required.
    Supports -WhatIf/-Confirm. Requires an ARM token; authentication is
    ensured via Initialize-OERAuth -IncludeARM. A permanent grant that needs the role management
    policy opened opens it only once the assignment itself is confirmed (declining the prompt
    weakens nothing, while -WhatIf still plans the policy change), and a grant that then fails rolls
    the policy back and reports a PolicyOpenedButGrantFailed error naming the policy. Principal
    resolution runs BEFORE scope resolution, so a call supplying both an unresolvable principal and
    an invalid scope reports the principal error, not InvalidScope.

    Because -PrincipalId binds from the pipeline by property name and takes precedence over the
    friendly parameters, supplying -User, -Group or -ServicePrincipal while piping objects that carry
    their own PrincipalId (any assignment-shaped object, for example Get-OEREligibleRoleAssignment
    output) is rejected with a non-terminating AmbiguousPrincipal error rather than silently making
    each piped item's own principal eligible. Piping a role definition, subscription, resource group
    or resource alongside a named principal is unaffected -- none of those shapes carries a
    PrincipalId.
    .PARAMETER Role
    The role: display name (e.g. 'Reader'), role definition GUID, or full ARM id. Pipeline by
    property name (RoleDefinitionId). Tab-completion offers the five curated common Azure RBAC
    roles; any other built-in or custom role name is still accepted.
    .PARAMETER PrincipalId
    The object id (GUID) of the principal to make eligible. Pipeline by property name; takes
    precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use -User,
    -Group, or -ServicePrincipal instead.
    .PARAMETER User
    A user principal name or object id to make eligible.
    .PARAMETER Group
    A group display name or object id to make eligible.
    .PARAMETER ServicePrincipal
    A service principal display name or object id to make eligible.
    .PARAMETER Scope
    A raw ARM scope string such as '/subscriptions/{id}/resourceGroups/{rg}'.
    .PARAMETER Subscription
    A subscription GUID or display name. Pipeline by property name (SubscriptionId).
    .PARAMETER ResourceGroup
    A resource group name narrowing the -Subscription scope. Pipeline by property name.
    .PARAMETER ManagementGroup
    A management group name or display name. Pipeline by property name (ManagementGroupName).
    .PARAMETER ResourceType
    The full resource type (e.g. 'Microsoft.Storage/storageAccounts') that disambiguates -ResourceName
    within the -ResourceGroup. Requires -ResourceName. Pipeline by property name.
    .PARAMETER ResourceName
    A resource name within -Subscription/-ResourceGroup; resolved to the resource's full ARM id so the
    eligibility applies at that single resource. Pipeline by property name.
    .PARAMETER Duration
    ISO 8601 duration (e.g. 'P365D') for a time-bound eligibility.
    .PARAMETER DurationDays
    Friendly time-bound eligibility lifetime in whole days (e.g. 365), converted to an ISO 8601
    duration. Mutually exclusive with the raw ISO -Duration.
    .PARAMETER EndDateTime
    Absolute end time for a time-bound eligibility.
    .PARAMETER Permanent
    Make the eligibility permanent (no expiration). Default when no schedule is supplied. When the
    role's PIM policy forbids permanent eligibility, the cmdlet opens it first (a loud warning is
    emitted and the policy change is a separate -WhatIf/-Confirm action); if the policy cannot be
    opened (e.g. missing roleManagementPolicies/write) a PolicyOpenFailed error is returned and no
    assignment is created.
    .PARAMETER Justification
    Justification recorded on the request.
    .PARAMETER TicketNumber
    Ticket number recorded on the request.
    .PARAMETER TicketSystem
    Ticket system name recorded on the request.
    .PARAMETER Condition
    Optional ABAC condition expression constraining the eligibility.
    .PARAMETER ConditionVersion
    Condition syntax version. Only '2.0' is accepted; defaults to '2.0' when -Condition is supplied,
    invalid without -Condition.
    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.
    .EXAMPLE
    New-OEREligibleRoleAssignment -Role 'Contributor' -Group 'role_sec_ops' -Subscription 'Prod' -Duration 'P365D'
    Makes the group eligible for Contributor on the Prod subscription for one year.
    .EXAMPLE
    New-OEREligibleRoleAssignment -Role 'Contributor' -Group 'role_sec_ops' -Subscription 'Prod' -DurationDays 365
    Makes the group eligible for Contributor on the Prod subscription for 365 days.
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

        [string]$Scope,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceGroup,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ManagementGroupName')]
        [string]$ManagementGroup,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceType,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceName,

        [ValidatePattern('^P(?=[YMWD0-9T])(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(\d+[HMS])+)?$')]
        [string]$Duration,
        [ValidateRange(1, 3650)]
        [int]$DurationDays,
        [datetime]$EndDateTime,
        [switch]$Permanent,

        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [string]$Condition,
        # '2.0' is the only condition syntax version ARM currently accepts on create. If Microsoft
        # ships a 3.0, add it to this list.
        [ValidateSet('2.0')]
        [string]$ConditionVersion,
        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        # These cmdlets have no PositionalBinding=$false, so every parameter is implicitly
        # positional in declaration order.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$PrincipalId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        # Cheap, purely local parameter-shape checks run BEFORE any principal resolution: resolving a
        # friendly -User/-Group/-ServicePrincipal touches Graph, and a caller who only fat-fingered
        # -ConditionVersion or the duration parameters should get instant local feedback rather than
        # pay for (or fail on) a network round-trip that has nothing to do with the actual mistake.
        if ($ConditionVersion -and -not $Condition) {
            Write-CmdletError -Message ([System.Exception]::new('-ConditionVersion requires -Condition.')) -ErrorId 'ConditionVersionWithoutCondition' -Category InvalidArgument -TargetObject $ConditionVersion -Cmdlet $PSCmdlet
            return
        }

        # -PrincipalId binds from the pipeline by property name and Resolve-OERPrincipalOrId gives it
        # precedence over -User/-Group/-ServicePrincipal, so a pipe of assignment-shaped objects --
        # every one of which carries its own PrincipalId -- would silently ignore the named principal
        # and make each piped item's OWN principal eligible instead. Handing privileged access to a
        # principal the caller never named is refused, not warned about: the same AmbiguousPrincipal
        # treatment Remove-OERGroupEligibility and Remove-OERAdministrativeUnitScopedRole already give
        # the identical collision.
        #
        # The test is deliberately narrower than the one in those two cmdlets, because this cmdlet's
        # pipeline is POLYMORPHIC: a role definition, subscription, resource group or resource pipes in
        # to supply the ROLE or the SCOPE, and pairing one of those with a named principal is a
        # documented, intended use. None of those shapes carries a PrincipalId, so the guard keys on
        # the piped item's OWN PrincipalId and fires only on a genuine collision. That value is read
        # through $PSItem, which the process block populates for every advanced function independently
        # of any ValueFromPipeline parameter: PowerShell freezes an explicitly bound parameter for the
        # rest of the pipeline, so the $PrincipalId parameter variable can never reveal the divergence
        # -- $PSItem is the only place the piped item's own principal is observable.
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $PSItem.PrincipalId -and
            ($PSBoundParameters.ContainsKey('User') -or $PSBoundParameters.ContainsKey('Group') -or
                $PSBoundParameters.ContainsKey('ServicePrincipal'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new("A principal was supplied by name while objects carrying their own PrincipalId '$($PSItem.PrincipalId)' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and each piped item's own principal made eligible instead. Supply either the named principal or the pipeline, not both.")) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $PSItem.PrincipalId -Cmdlet $PSCmdlet
            return
        }

        if ($Duration -and $PSBoundParameters.ContainsKey('DurationDays')) {
            Write-CmdletError -Message ([System.Exception]::new('Supply only one of -Duration or -DurationDays.')) -ErrorId 'AmbiguousDuration' -Category InvalidArgument -TargetObject $Duration -Cmdlet $PSCmdlet
            return
        }
        $ScheduleParams = @{}
        if ($PSBoundParameters.ContainsKey('DurationDays')) { $ScheduleParams.Duration = ConvertTo-OERDuration -Days $DurationDays }
        elseif ($Duration) { $ScheduleParams.Duration = $Duration }
        if ($PSBoundParameters.ContainsKey('EndDateTime')) { $ScheduleParams.EndDateTime = $EndDateTime }
        if ($Permanent) { $ScheduleParams.Permanent = $true }
        try {
            $ScheduleInfo = New-OERScheduleInfo @ScheduleParams
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ScheduleTarget = if ($Duration) { $Duration } elseif ($PSBoundParameters.ContainsKey('EndDateTime')) { $EndDateTime } elseif ($PSBoundParameters.ContainsKey('DurationDays')) { $DurationDays } else { $Role }
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidSchedule' -Category InvalidArgument -TargetObject $ScheduleTarget -Cmdlet $PSCmdlet
            return
        }

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -ServicePrincipal $ServicePrincipal
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }

        try {
            $TargetScope = Resolve-OERScope -Scope $Scope -Subscription $Subscription -ResourceGroup $ResourceGroup -ManagementGroup $ManagementGroup -ResourceType $ResourceType -ResourceName $ResourceName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ScopeTarget = @($Scope, $Subscription, $ManagementGroup, $ResourceGroup, $ResourceType, $ResourceName) | Where-Object { $_ } | Select-Object -First 1
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $ScopeTarget -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[New-OEREligibleRoleAssignment] Target scope: '$TargetScope'."
        Write-Verbose "[New-OEREligibleRoleAssignment] Resolved principal to '$($Principal.PrincipalId)'."
        try {
            $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[New-OEREligibleRoleAssignment] Resolved role '$Role' to '$RoleDefinitionId'."

        # Name the principal that will ACTUALLY be acted on, not merely the one the operator typed.
        # -PrincipalId shares a parameter set with the friendly parameters and Resolve-OERPrincipalOrId
        # lets -PrincipalId win, so it must be tested FIRST here too (see Remove-OEREligibleRoleAssignment).
        $PrincipalLabel = if ($PrincipalId) { $Principal.PrincipalId }
        elseif ($User) { $User }
        elseif ($Group) { $Group }
        elseif ($ServicePrincipal) { $ServicePrincipal }
        else { $Principal.PrincipalId }
        $PrincipalTypeLabel = if ($Principal.PrincipalType) { $Principal.PrincipalType } else { 'principal' }
        $Target = "eligible role '$Role' for $PrincipalTypeLabel '$PrincipalLabel' at scope '$TargetScope'"

        # The pre-check is a READ, so it runs BEFORE the gate and its warning is emitted before the
        # operator is asked. The confirmation prompt names only the assignment, so hiding the policy
        # warning behind it would ask the operator to approve a change to every eligible assignment
        # for this role at this scope without saying so. Only the policy WRITE is gated below.
        $NeedsPolicyOpen = $false
        $PendingPolicyId = $null
        if ($ScheduleInfo.expiration.type -eq 'NoExpiration') {
            $PolicyState = $null
            try {
                $PolicyState = Get-OERPermanentPolicyState -Scope $TargetScope -RoleDefinitionId $RoleDefinitionId -Kind 'Eligible'
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Verbose "[New-OEREligibleRoleAssignment] Could not pre-check the role management policy for permanent eligibility: $($PSItem.Exception.Message). Proceeding; Azure will enforce the policy."
            }
            if ($PolicyState -and -not $PolicyState.PermanentAllowed) {
                $NeedsPolicyOpen = $true
                $PendingPolicyId = $PolicyState.PolicyId
                Write-Warning "This assignment requires opening the role management policy for role '$Role' at scope '$TargetScope' to allow PERMANENT eligible assignments, which affects ALL eligible assignments for this role at this scope."
            }
        }

        # Decide ONCE. Opening the policy is a mutation and must not run when the operator declines.
        # Under -WhatIf, ShouldProcess returns $false but $WhatIfPreference is $true, and the
        # self-gating Set-OERRoleManagementPolicy only prints its own plan line -- so the -WhatIf
        # plan still shows the policy open, while a DECLINED prompt ($Proceed false,
        # $WhatIfPreference false) weakens nothing.
        $Proceed = $PSCmdlet.ShouldProcess($Target, 'Create eligible Azure role assignment')

        $PolicyOpened = $false
        $OpenedPolicyId = $null
        if (($Proceed -or $WhatIfPreference) -and $NeedsPolicyOpen) {
            try {
                # Set-OERRoleManagementPolicy is self-gating: under an explicit -Confirm the propagated
                # $ConfirmPreference makes it prompt on its own, and a declined prompt emits NOTHING
                # having written nothing. Take the flag from that result -- setting it unconditionally
                # would later name, and attempt to roll back, a policy that was never opened.
                $OpenResult = Set-OERRoleManagementPolicy -PolicyId $PendingPolicyId -AllowPermanentEligibility $true -ErrorAction Stop
                if ($OpenResult) {
                    $PolicyOpened = $true
                    $OpenedPolicyId = $PendingPolicyId
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new("Could not open the role management policy to allow permanent eligibility: $($PSItem.Exception.Message) Run 'Set-OERRoleManagementPolicy -Role ''$Role'' <scope> -AllowPermanentEligibility `$true' with Microsoft.Authorization/roleManagementPolicies/write permission, or grant a time-bound eligibility with -DurationDays.")) -ErrorId 'PolicyOpenFailed' -Category PermissionDenied -TargetObject $PendingPolicyId -Cmdlet $PSCmdlet
                return
            }
        }

        $Body = @{ properties = @{
                principalId      = $Principal.PrincipalId
                requestType      = 'AdminAssign'
                roleDefinitionId = $RoleDefinitionId
                scheduleInfo     = $ScheduleInfo
            } }
        if ($Justification) { $Body.properties.justification = $Justification }
        if ($TicketNumber -or $TicketSystem) {
            $Body.properties.ticketInfo = @{ ticketNumber = $TicketNumber; ticketSystem = $TicketSystem }
        }
        if ($Condition) {
            $Body.properties.condition = $Condition
            $Body.properties.conditionVersion = if ($ConditionVersion) { $ConditionVersion } else { '2.0' }
        }

        if ($Proceed) {
            $Name = [guid]::NewGuid().ToString()
            try {
                $Response = Invoke-OERArmRequest -Method PUT -Path "$TargetScope/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/$Name`?api-version=2020-10-01" -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                if ($PolicyOpened) {
                    # The grant failed AFTER this invocation weakened the governing policy. Put it
                    # back, and if that fails too, name the policy so automation can revert it.
                    $Reverted = $false
                    try {
                        $null = Set-OERRoleManagementPolicy -PolicyId $OpenedPolicyId -AllowPermanentEligibility $false -ErrorAction Stop
                        $Reverted = $true
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                    }
                    $RevertText = if ($Reverted) {
                        'It was rolled back to disallow permanent assignments.'
                    } else {
                        "The rollback ALSO failed, so the policy is still open. Run 'Set-OERRoleManagementPolicy -PolicyId ''$OpenedPolicyId'' -AllowPermanentEligibility `$false' to close it."
                    }
                    Write-CmdletError -Message ([System.Exception]::new("The eligible role assignment failed after role management policy '$OpenedPolicyId' had been opened to allow permanent assignments. $RevertText")) -ErrorId 'PolicyOpenedButGrantFailed' -Category InvalidOperation -TargetObject $OpenedPolicyId -Cmdlet $PSCmdlet
                }
                return
            }
            ConvertTo-OERRoleScheduleRequest -InputObject $Response
        }
    }
}
