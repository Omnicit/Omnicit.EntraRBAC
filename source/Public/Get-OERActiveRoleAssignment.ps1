function Get-OERActiveRoleAssignment {
    <#
    .SYNOPSIS
    Lists active Azure role assignments (PIM) at a management group, subscription, resource group,
    or resource scope.
    .DESCRIPTION
    Reads Microsoft.Authorization/roleAssignmentSchedules through the ARM API (api-version
    2020-10-01) via Invoke-OERArmRequest. A scope is required: -Scope (raw ARM id), -Subscription
    (GUID or display name, optionally narrowed with -ResourceGroup), or -ManagementGroup (name or
    display name). Without a filter, every active assignment that applies at the scope (direct and
    inherited) is returned. A principal filter (-User, -Group, or -ServicePrincipal; resolved through
    Microsoft Graph) applies $filter=assignedTo('<objectId>') so active assignments inherited via group membership
    are included. -AtScope applies $filter=atScope()
    (active assignments at or above the scope). -AsTarget applies $filter=asTarget() (the caller's own
    active assignments). A principal filter, -AtScope, and -AsTarget are mutually exclusive. Output
    objects are tagged Omnicit.EntraRBAC.ActiveRoleAssignment and expose RoleAssignmentScheduleId,
    PrincipalId, RoleDefinitionId, and Scope. Friendly RoleName/PrincipalDisplayName are returned
    directly from the API expandedProperties. Requires an ARM token; authentication is ensured via
    Initialize-OERAuth -IncludeARM.
    .PARAMETER Scope
    A raw ARM scope string such as '/subscriptions/{id}/resourceGroups/{rg}'.
    .PARAMETER Subscription
    A subscription GUID or display name. Bound from the pipeline by property name (SubscriptionId).
    .PARAMETER ResourceGroup
    A resource group name narrowing the -Subscription scope. Pipeline by property name.
    .PARAMETER ManagementGroup
    A management group name or display name. Bound from the pipeline by property name (ManagementGroupName).
    .PARAMETER ResourceType
    The full resource type (e.g. 'Microsoft.Storage/storageAccounts') that disambiguates -ResourceName
    within the -ResourceGroup. Requires -ResourceName. Pipeline by property name.
    .PARAMETER ResourceName
    A resource name within -Subscription/-ResourceGroup; resolved to the resource's full ARM id so the
    assignment applies at that single resource. Pipeline by property name.
    .PARAMETER User
    A user principal name or object id whose active assignments are listed.
    .PARAMETER Group
    A group display name or object id whose active assignments are listed.
    .PARAMETER ServicePrincipal
    A service principal display name or object id whose active assignments are listed.
    .PARAMETER AtScope
    Return only active assignments at or above the scope. Cannot be combined with a principal filter or -AsTarget.
    .PARAMETER AsTarget
    Return only the calling user's own active assignments. Cannot be combined with a principal filter or -AtScope.
    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.
    .EXAMPLE
    Get-OERActiveRoleAssignment -Subscription 'Prod'
    Lists every active role assignment that applies at the Prod subscription.
    .EXAMPLE
    Get-OERActiveRoleAssignment -ManagementGroup 'mg-platform' -User 'anna.berg@contoso.com'
    Lists Anna's active role assignments at, above, and below the mg-platform management group.
    .EXAMPLE
    Get-OERActiveRoleAssignment -Subscription 'Prod' -AsTarget
    Lists the caller's own active role assignments at the Prod subscription.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
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

        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal,
        [switch]$AtScope,
        [switch]$AsTarget,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        try {
            $TargetScope = Resolve-OERScope -Scope $Scope -Subscription $Subscription -ResourceGroup $ResourceGroup -ManagementGroup $ManagementGroup -ResourceType $ResourceType -ResourceName $ResourceName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ScopeTarget = @($Scope, $Subscription, $ManagementGroup, $ResourceGroup, $ResourceType, $ResourceName) | Where-Object { $_ } | Select-Object -First 1
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $ScopeTarget -Cmdlet $PSCmdlet
            return
        }

        $PrincipalRequested = [bool]($User -or $Group -or $ServicePrincipal)
        if ($PrincipalRequested -and ($AtScope -or $AsTarget)) {
            Write-CmdletError -Message ([System.Exception]::new('A principal filter (-User, -Group or -ServicePrincipal) cannot be combined with -AtScope or -AsTarget.')) -ErrorId 'AmbiguousFilter' -Category InvalidArgument -TargetObject $TargetScope -Cmdlet $PSCmdlet
            return
        }
        if ($AtScope -and $AsTarget) {
            Write-CmdletError -Message ([System.Exception]::new('-AtScope and -AsTarget cannot be combined.')) -ErrorId 'AmbiguousFilter' -Category InvalidArgument -TargetObject $TargetScope -Cmdlet $PSCmdlet
            return
        }

        $Filter = $null
        if ($PrincipalRequested) {
            try {
                $Principal = Resolve-OERPrincipal -User $User -Group $Group -ServicePrincipal $ServicePrincipal
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PrincipalTarget = @($User, $Group, $ServicePrincipal) | Where-Object { $_ } | Select-Object -First 1
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'PrincipalNotFound' -Category ObjectNotFound -TargetObject $PrincipalTarget -Cmdlet $PSCmdlet
                return
            }
            # assignedTo('{id}') returns the principal's schedules including those inherited via
            # group membership; principalId eq '{id}' is direct-only and missed group-inherited
            # assignments (verified against the ARM 2020-10-01 _ListForScope filter contract).
            $Filter = [uri]::EscapeDataString("assignedTo('$($Principal.PrincipalId)')")
        } elseif ($AtScope) {
            $Filter = 'atScope()'
        } elseif ($AsTarget) {
            $Filter = 'asTarget()'
        }

        $Path = "$TargetScope/providers/Microsoft.Authorization/roleAssignmentSchedules?api-version=2020-10-01"
        if ($Filter) { $Path += "&`$filter=$Filter" }

        try {
            $Response = Invoke-OERArmRequest -Path $Path -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            ConvertTo-OERActiveRoleAssignment -InputObject $Item
        }
    }
}
