function Enable-OEREligibleRoleAssignment {
    <#
    .SYNOPSIS
    Activates (self-activates) one of the caller's eligible Azure role assignments (PIM).
    .DESCRIPTION
    Submits a Microsoft.Authorization/roleAssignmentScheduleRequests request (api-version 2020-10-01)
    with requestType SelfActivate and a linkedRoleEligibilityScheduleId pointing at the eligibility
    being activated, via Invoke-OERArmRequest. The request name is a new client-generated GUID.
    Activations are always time-bound: the schedule is built from -DurationHours or -Duration or -EndDateTime, defaulting
    to PT8H (8 hours). The eligibility may be supplied directly as -RoleEligibilityScheduleId (the full schedule
    id, e.g. piped from Get-OEREligibleRoleAssignment) or located by -Role plus scope and principal
    (the cmdlet lists the principal's eligibilities and matches the role). principalId is taken from
    -PrincipalId or resolved from -User/-Group/-ServicePrincipal. Supports -WhatIf/-Confirm. Requires
    an ARM token; authentication is ensured via Initialize-OERAuth -IncludeARM.
    .PARAMETER Role
    The role to activate: display name, role definition GUID, or full ARM id. Pipeline by property
    name (RoleDefinitionId). Tab-completion offers the five curated common Azure RBAC roles; any
    other built-in or custom role name is still accepted.
    .PARAMETER RoleEligibilityScheduleId
    The full ARM id of the eligibility schedule to activate (sent as linkedRoleEligibilityScheduleId).
    Pipeline by property name (Id). When omitted, the eligibility is located by -Role, scope, and principal.
    .PARAMETER PrincipalId
    The object id (GUID) of the activating principal. Pipeline by property name; takes precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use -User, -Group, or -ServicePrincipal instead.
    .PARAMETER User
    A user principal name or object id of the activating principal.
    .PARAMETER Group
    A group display name or object id of the activating principal.
    .PARAMETER ServicePrincipal
    A service principal display name or object id of the activating principal.
    .PARAMETER Scope
    A raw ARM scope string. Pipeline by property name.
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
    activation applies at that single resource. Pipeline by property name.
    .PARAMETER Duration
    ISO 8601 activation duration (e.g. 'PT8H'). Defaults to PT8H when none of -DurationHours, -Duration, or -EndDateTime is supplied.
    .PARAMETER DurationHours
    Friendly activation duration in whole hours (e.g. 4), converted to an ISO 8601 duration. Mutually
    exclusive with the raw ISO -Duration. When neither is supplied the activation defaults to 8 hours.
    .PARAMETER EndDateTime
    Absolute end time for the activation.
    .PARAMETER Justification
    Justification recorded on the activation request (often required by the role's PIM policy).
    .PARAMETER TicketNumber
    Ticket number recorded on the request.
    .PARAMETER TicketSystem
    Ticket system name recorded on the request.
    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.
    .EXAMPLE
    Get-OEREligibleRoleAssignment -Subscription 'Prod' -AsTarget | Enable-OEREligibleRoleAssignment -Duration 'PT4H' -Justification 'deploy'
    Activates the caller's eligibilities at the Prod subscription for four hours.
    .EXAMPLE
    Enable-OEREligibleRoleAssignment -Role 'Contributor' -User 'me@contoso.com' -Subscription 'Prod' -Justification 'hotfix'
    Locates the caller's Contributor eligibility at Prod and activates it for the default eight hours.
    .EXAMPLE
    Enable-OEREligibleRoleAssignment -Role 'Contributor' -User 'me@contoso.com' -Subscription 'Prod' -DurationHours 4 -Justification 'deploy'
    Activates the caller's Contributor eligibility at Prod for four hours.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$RoleEligibilityScheduleId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$PrincipalId,

        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal,

        [Parameter(ValueFromPipelineByPropertyName)]
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
        [ValidateRange(1, 8760)]
        [int]$DurationHours,
        [datetime]$EndDateTime,

        [string]$Justification,
        [string]$TicketNumber,
        [string]$TicketSystem,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($Duration -and $PSBoundParameters.ContainsKey('DurationHours')) {
            Write-CmdletError -Message ([System.Exception]::new('Supply only one of -Duration or -DurationHours.')) -ErrorId 'AmbiguousDuration' -Category InvalidArgument -TargetObject $Duration -Cmdlet $PSCmdlet
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
        Write-Verbose "[Enable-OEREligibleRoleAssignment] Target scope: '$TargetScope'."

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -ServicePrincipal $ServicePrincipal `
            -NoPrincipalHint 'or pipe from Get-OEREligibleRoleAssignment'
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        $ResolvedPrincipalId = $Principal.PrincipalId
        Write-Verbose "[Enable-OEREligibleRoleAssignment] Resolved principal to '$ResolvedPrincipalId'."

        try {
            $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Enable-OEREligibleRoleAssignment] Resolved role '$Role' to '$RoleDefinitionId'."

        # The linked eligibility schedule id: use the supplied full schedule id, otherwise locate the
        # caller's matching eligibility. We send the FULL roleEligibilitySchedules/{guid} id; the
        # Microsoft Learn example shows a bare GUID name -- if ARM rejects the full id during live
        # testing, fall back to ($LinkedId -split '/')[-1].
        if ($RoleEligibilityScheduleId) {
            $LinkedId = $RoleEligibilityScheduleId
        } else {
            $Filter = [uri]::EscapeDataString("principalId eq '$ResolvedPrincipalId'")
            try {
                $Eligibilities = Invoke-OERArmRequest -Path "$TargetScope/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01&`$filter=$Filter" -All
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            $Match = @($Eligibilities.value) | Where-Object { [string]$PSItem.properties.roleDefinitionId -eq $RoleDefinitionId } | Select-Object -First 1
            if (-not $Match) {
                Write-CmdletError -Message ([System.Exception]::new("No eligible role assignment for role '$Role' was found for the principal at scope '$TargetScope' to activate.")) -ErrorId 'EligibilityNotFound' -Category ObjectNotFound -TargetObject $TargetScope -Cmdlet $PSCmdlet
                return
            }
            $LinkedId = [string]$Match.id
            Write-Verbose "[Enable-OEREligibleRoleAssignment] Resolved eligibility schedule id: '$LinkedId'."
        }

        $ScheduleParams = @{}
        if ($PSBoundParameters.ContainsKey('DurationHours')) { $ScheduleParams.Duration = ConvertTo-OERDuration -Hours $DurationHours }
        elseif ($Duration) { $ScheduleParams.Duration = $Duration }
        if ($PSBoundParameters.ContainsKey('EndDateTime')) { $ScheduleParams.EndDateTime = $EndDateTime }
        if ($ScheduleParams.Count -eq 0) { $ScheduleParams.Duration = 'PT8H' }
        try {
            $ScheduleInfo = New-OERScheduleInfo @ScheduleParams
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ScheduleTarget = if ($Duration) { $Duration } elseif ($PSBoundParameters.ContainsKey('EndDateTime')) { $EndDateTime } elseif ($PSBoundParameters.ContainsKey('DurationHours')) { $DurationHours } else { $Role }
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidSchedule' -Category InvalidArgument -TargetObject $ScheduleTarget -Cmdlet $PSCmdlet
            return
        }

        $Body = @{ properties = @{
                principalId                     = $ResolvedPrincipalId
                requestType                     = 'SelfActivate'
                roleDefinitionId                = $RoleDefinitionId
                linkedRoleEligibilityScheduleId = $LinkedId
                scheduleInfo                    = $ScheduleInfo
            } }
        if ($Justification) { $Body.properties.justification = $Justification }
        if ($TicketNumber -or $TicketSystem) {
            $Body.properties.ticketInfo = @{ ticketNumber = $TicketNumber; ticketSystem = $TicketSystem }
        }

        # Name the principal that will ACTUALLY be acted on, not merely the one the operator typed.
        # -PrincipalId shares a parameter set with the friendly parameters, and Resolve-OERPrincipalOrId
        # lets -PrincipalId win (warning that the friendly value is ignored), so -PrincipalId MUST be
        # tested FIRST. Testing $User first made the destructive prompt name a principal the module
        # was about to ignore -- worse than the bare GUID it replaced, because it is actively wrong.
        # The resolved GUID stays on the Write-Verbose line above for either input form.
        $PrincipalLabel = if ($PrincipalId) { $ResolvedPrincipalId }
        elseif ($User) { $User }
        elseif ($Group) { $Group }
        elseif ($ServicePrincipal) { $ServicePrincipal }
        else { $ResolvedPrincipalId }
        $Target = "active role '$Role' for principal '$PrincipalLabel' at scope '$TargetScope'"
        if ($PSCmdlet.ShouldProcess($Target, 'Activate eligible Azure role assignment')) {
            $Name = [guid]::NewGuid().ToString()
            try {
                $Response = Invoke-OERArmRequest -Method PUT -Path "$TargetScope/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$Name`?api-version=2020-10-01" -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERRoleScheduleRequest -InputObject $Response
        }
    }
}
