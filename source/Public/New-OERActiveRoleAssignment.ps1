function New-OERActiveRoleAssignment {
    <#
    .SYNOPSIS
    Grants a principal an active Azure role assignment (PIM) at any scope.
    .DESCRIPTION
    Creates a Microsoft.Authorization/roleAssignmentScheduleRequests resource (api-version
    2020-10-01) with requestType AdminAssign via Invoke-OERArmRequest. The request name is a new
    client-generated GUID. The body carries the FULL ARM roleDefinitionId (resolved from a role
    display name, GUID, or full id), the principalId taken from -PrincipalId or resolved from
    -User/-Group/-ServicePrincipal, and a scheduleInfo built from -DurationDays/-Duration/
    -EndDateTime/-Permanent (default permanent). principalType is NOT sent (the schedule-request API
    treats it as response-only). Exactly one principal source and one scope source are required.
    Supports -WhatIf/-Confirm. Requires an ARM token; authentication is ensured via
    Initialize-OERAuth -IncludeARM. A permanent grant that needs the role management policy opened
    opens it only once the assignment itself is confirmed (declining the prompt weakens nothing,
    while -WhatIf still plans the policy change). A grant that then fails rolls the policy back
    first, then reports a PolicyOpenedButGrantFailed error naming the policy, whether the rollback
    succeeded and how the request failed, and only then re-publishes the grant's own error, so a
    caller running with -ErrorAction Stop is stopped by PolicyOpenedButGrantFailed after the
    rollback. Principal resolution runs BEFORE scope resolution, so a call supplying both an
    unresolvable principal and an invalid scope reports the principal error, not InvalidScope.

    Because -PrincipalId binds from the pipeline by property name and takes precedence over the
    friendly parameters, supplying -User, -Group or -ServicePrincipal while piping objects that carry
    their own PrincipalId (any assignment-shaped object, for example Get-OERActiveRoleAssignment
    output) is rejected with a non-terminating AmbiguousPrincipal error rather than silently granting
    the role to each piped item's own principal. Piping a role definition, subscription, resource
    group or resource alongside a named principal is unaffected -- none of those shapes carries a
    PrincipalId.

    Azure Resource Manager can accept the request and answer it with a status in the Failed family
    (Failed, FailedAsResourceIsLocked, or any other status that starts with Failed, in any letter
    case), which grants nothing. The cmdlet then still emits the request object (its Status reads as
    answered) and afterwards writes a non-terminating AssignmentRequestFailed error (category
    InvalidResult, target the scope), so a caller running with -ErrorAction Stop still receives the
    object, for example through -OutVariable, before the error stops it. When this invocation had
    opened the role management policy for a permanent grant, the policy is rolled back first --
    before the object is emitted, as it is before any error for a refused grant -- and the
    AssignmentRequestFailed message says whether the rollback succeeded; it is the one record, not a
    PolicyOpenedButGrantFailed as well, since the request was accepted rather than refused. Every
    other status is not an error -- Provisioned and PendingApproval included.
    .PARAMETER Role
    The role: display name (e.g. 'Reader'), role definition GUID, or full ARM id. Pipeline by
    property name (RoleDefinitionId). Tab-completion offers the five curated common Azure RBAC
    roles; any other built-in or custom role name is still accepted.
    .PARAMETER PrincipalId
    The object id (GUID) of the principal to create an active assignment for. Pipeline by property
    name; takes precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use
    -User, -Group, or -ServicePrincipal instead.
    .PARAMETER User
    A user principal name or object id to create an active assignment for.
    .PARAMETER Group
    A group display name or object id to create an active assignment for.
    .PARAMETER ServicePrincipal
    A service principal display name or object id to create an active assignment for.
    .PARAMETER Scope
    A raw ARM scope string such as '/subscriptions/{id}/resourceGroups/{rg}'.
    .PARAMETER Subscription
    A subscription GUID or display name. Pipeline by property name (SubscriptionId).
    A display name that several subscriptions share is refused, naming the candidates;
    use the subscription id.
    .PARAMETER ResourceGroup
    A resource group name narrowing the -Subscription scope. Pipeline by property name.
    .PARAMETER ManagementGroup
    A management group name or display name. Pipeline by property name (ManagementGroupName).
    A display name that several management groups share is refused, naming the candidates;
    use the management group name.
    .PARAMETER ResourceType
    The full resource type (e.g. 'Microsoft.Storage/storageAccounts') that disambiguates -ResourceName
    within the -ResourceGroup. Requires -ResourceName. Pipeline by property name.
    .PARAMETER ResourceName
    A resource name within -Subscription/-ResourceGroup; resolved to the resource's full ARM id so the
    assignment applies at that single resource. Pipeline by property name.
    .PARAMETER Duration
    ISO 8601 duration (e.g. 'P365D') for a time-bound active assignment.
    .PARAMETER DurationDays
    Friendly time-bound active-assignment lifetime in whole days (e.g. 365), converted to an ISO 8601
    duration. Mutually exclusive with the raw ISO -Duration.
    .PARAMETER EndDateTime
    Absolute end time for a time-bound active assignment.
    .PARAMETER Permanent
    Make the active assignment permanent (no expiration). Default when no schedule is supplied. When
    the role's PIM policy forbids permanent active assignment, a loud warning says so before the
    confirmation prompt, and the cmdlet opens the policy only once the assignment itself is
    confirmed, before it sends the grant: a declined prompt changes no policy, while -WhatIf still
    plans the policy change (a separate -WhatIf/-Confirm action of Set-OERRoleManagementPolicy). If
    the policy cannot be opened (e.g. missing roleManagementPolicies/write) a PolicyOpenFailed error
    is returned and no assignment is created; use -AllowPermanentActiveAssignment via
    Set-OERRoleManagementPolicy directly, or supply a time-bound schedule with -DurationDays. If the
    grant is then refused, or answered with a status in the Failed family, the policy this
    invocation opened is rolled back: a refused grant reports PolicyOpenedButGrantFailed, and a
    Failed answer says so in its one AssignmentRequestFailed record.
    .PARAMETER Justification
    Justification recorded on the request.
    .PARAMETER TicketNumber
    Ticket number recorded on the request.
    .PARAMETER TicketSystem
    Ticket system name recorded on the request.
    .PARAMETER Condition
    Optional ABAC condition expression constraining the active assignment.
    .PARAMETER ConditionVersion
    Condition syntax version. Only '2.0' is accepted; defaults to '2.0' when -Condition is supplied,
    invalid without -Condition.
    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.
    .EXAMPLE
    New-OERActiveRoleAssignment -Role 'Contributor' -Group 'role_sec_ops' -Subscription 'Prod' -Duration 'P365D'
    Creates an active assignment for the group as Contributor on the Prod subscription for one year.
    .EXAMPLE
    New-OERActiveRoleAssignment -Role 'Contributor' -Group 'role_sec_ops' -Subscription 'Prod' -DurationDays 365
    Creates an active assignment for the group as Contributor on the Prod subscription for 365 days.
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
        [ValidateNotNullOrEmpty()]
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
        # and grant the role to each piped item's OWN principal instead. Handing privileged access to
        # a principal the caller never named is refused, not warned about: the same AmbiguousPrincipal
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
                -Message ([System.Exception]::new("A principal was supplied by name while objects carrying their own PrincipalId '$($PSItem.PrincipalId)' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and the role granted to each piped item's own principal instead. Supply either the named principal or the pipeline, not both.")) `
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
        Write-Verbose "[New-OERActiveRoleAssignment] Target scope: '$TargetScope'."
        Write-Verbose "[New-OERActiveRoleAssignment] Resolved principal to '$($Principal.PrincipalId)'."
        try {
            $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[New-OERActiveRoleAssignment] Resolved role '$Role' to '$RoleDefinitionId'."

        # Name the principal that will ACTUALLY be acted on, not merely the one the operator typed.
        # -PrincipalId shares a parameter set with the friendly parameters and Resolve-OERPrincipalOrId
        # lets -PrincipalId win, so it must be tested FIRST here too (see Remove-OEREligibleRoleAssignment).
        $PrincipalLabel = if ($PrincipalId) { $Principal.PrincipalId }
        elseif ($User) { $User }
        elseif ($Group) { $Group }
        elseif ($ServicePrincipal) { $ServicePrincipal }
        else { $Principal.PrincipalId }
        $PrincipalTypeLabel = if ($Principal.PrincipalType) { $Principal.PrincipalType } else { 'principal' }
        $Target = "active role '$Role' for $PrincipalTypeLabel '$PrincipalLabel' at scope '$TargetScope'"

        # The pre-check is a READ, so it runs BEFORE the gate and its warning is emitted before the
        # operator is asked. The confirmation prompt names only the assignment, so hiding the policy
        # warning behind it would ask the operator to approve a change to every active assignment
        # for this role at this scope without saying so. Only the policy WRITE is gated below.
        $NeedsPolicyOpen = $false
        $PendingPolicyId = $null
        if ($ScheduleInfo.expiration.type -eq 'NoExpiration') {
            $PolicyState = $null
            try {
                $PolicyState = Get-OERPermanentPolicyState -Scope $TargetScope -RoleDefinitionId $RoleDefinitionId -Kind 'Active'
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Verbose "[New-OERActiveRoleAssignment] Could not pre-check the role management policy for permanent active assignment: $($PSItem.Exception.Message). Proceeding; Azure will enforce the policy."
            }
            if ($PolicyState -and -not $PolicyState.PermanentAllowed) {
                $NeedsPolicyOpen = $true
                $PendingPolicyId = $PolicyState.PolicyId
                Write-Warning "This assignment requires opening the role management policy for role '$Role' at scope '$TargetScope' to allow PERMANENT active assignments, which affects ALL active assignments for this role at this scope."
            }
        }

        # Decide ONCE. Opening the policy is a mutation and must not run when the operator declines.
        # Under -WhatIf, ShouldProcess returns $false but $WhatIfPreference is $true, and the
        # self-gating Set-OERRoleManagementPolicy only prints its own plan line -- so the -WhatIf
        # plan still shows the policy open, while a DECLINED prompt ($Proceed false,
        # $WhatIfPreference false) weakens nothing.
        $Proceed = $PSCmdlet.ShouldProcess($Target, 'Create active Azure role assignment')

        $PolicyOpened = $false
        $OpenedPolicyId = $null
        if (($Proceed -or $WhatIfPreference) -and $NeedsPolicyOpen) {
            try {
                # Set-OERRoleManagementPolicy is self-gating: under an explicit -Confirm the propagated
                # $ConfirmPreference makes it prompt on its own, and a declined prompt emits NOTHING
                # having written nothing. Take the flag from that result -- setting it unconditionally
                # would later name, and attempt to roll back, a policy that was never opened.
                $OpenResult = Set-OERRoleManagementPolicy -PolicyId $PendingPolicyId -AllowPermanentActiveAssignment $true -ErrorAction Stop
                if ($OpenResult) {
                    $PolicyOpened = $true
                    $OpenedPolicyId = $PendingPolicyId
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new("Could not open the role management policy to allow permanent active assignment: $($PSItem.Exception.Message) Run 'Set-OERRoleManagementPolicy -Role ''$Role'' <scope> -AllowPermanentActiveAssignment `$true' with Microsoft.Authorization/roleManagementPolicies/write permission, or grant a time-bound assignment with -DurationDays.")) -ErrorId 'PolicyOpenFailed' -Category PermissionDenied -TargetObject $PendingPolicyId -Cmdlet $PSCmdlet
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
            # The one rollback of a policy this invocation opened, shared by a refused grant (the
            # catch below) and a grant answered with a status in the Failed family: it puts the policy
            # back and returns the sentence that says whether it did, so automation can revert it if
            # the rollback fails too.
            $RollBackOpenedPolicy = {
                $Reverted = $false
                try {
                    $null = Set-OERRoleManagementPolicy -PolicyId $OpenedPolicyId -AllowPermanentActiveAssignment $false -ErrorAction Stop
                    $Reverted = $true
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                }
                if ($Reverted) {
                    'It was rolled back to disallow permanent assignments.'
                } else {
                    "The rollback ALSO failed, so the policy is still open. Run 'Set-OERRoleManagementPolicy -PolicyId ''$OpenedPolicyId'' -AllowPermanentActiveAssignment `$false' to close it."
                }
            }
            $Name = [guid]::NewGuid().ToString()
            try {
                $Response = Invoke-OERArmRequest -Method PUT -Path "$TargetScope/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$Name`?api-version=2020-10-01" -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $GrantError = $PSItem
                if ($PolicyOpened) {
                    # The grant failed AFTER this invocation weakened the governing policy. Put it back
                    # FIRST, then report it, and only then re-publish the grant's own error: under
                    # -ErrorAction Stop the first error written stops this command, so anything after
                    # it would never run and the policy would stay open.
                    $RevertText = & $RollBackOpenedPolicy
                    Write-CmdletError -Message ([System.Exception]::new("The active role assignment failed after role management policy '$OpenedPolicyId' had been opened to allow permanent assignments. $RevertText The request failed with: $($GrantError.Exception.Message)")) -ErrorId 'PolicyOpenedButGrantFailed' -Category InvalidOperation -TargetObject $OpenedPolicyId -Cmdlet $PSCmdlet
                }
                $PSCmdlet.WriteError($GrantError)
                return
            }
            $Request = ConvertTo-OERRoleScheduleRequest -InputObject $Response
            # Azure Resource Manager can ACCEPT the request and answer it with a status in the Failed
            # family, which grants nothing; Test-OERScheduleRequestFailed owns which statuses that is.
            $RequestFailed = Test-OERScheduleRequestFailed -Status $Request.Status
            # A Failed answer granted nothing, so a policy this invocation opened is put back as for a
            # refused grant -- BEFORE the object is emitted and the error written, so neither
            # -ErrorAction Stop nor a consumer that stops the pipeline can skip the rollback.
            $RevertText = $null
            if ($RequestFailed -and $PolicyOpened) { $RevertText = & $RollBackOpenedPolicy }
            # Emitted before the error, so a caller under -ErrorAction Stop still receives the request
            # (through -OutVariable, for example) before the error below stops it.
            $Request
            if ($RequestFailed) {
                $FailedMessage = "Azure Resource Manager accepted the active role assignment request '$($Request.Name)' (AdminAssign) of role " +
                    "'$RoleDefinitionId' for principal '$($Principal.PrincipalId)' at scope '$TargetScope' but answered status " +
                    "$($Request.Status), so nothing was granted."
                if ($PolicyOpened) {
                    # One record, not a PolicyOpenedButGrantFailed as well: the request was accepted,
                    # not refused, but it carries the same rollback text.
                    $FailedMessage += " Role management policy '$OpenedPolicyId' had been opened to allow permanent assignments before the request was sent. $RevertText"
                }
                Write-CmdletError -Message ([System.Exception]::new($FailedMessage)) `
                    -ErrorId 'AssignmentRequestFailed' -Category InvalidResult -TargetObject $TargetScope -Cmdlet $PSCmdlet
            }
        }
    }
}
