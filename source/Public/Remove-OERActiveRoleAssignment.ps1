function Remove-OERActiveRoleAssignment {
    <#
    .SYNOPSIS
    Removes an active Azure role assignment (PIM) from a principal at a scope.
    .DESCRIPTION
    Submits a Microsoft.Authorization/roleAssignmentScheduleRequests request (api-version 2020-10-01)
    with requestType AdminRemove via Invoke-OERArmRequest to revoke an existing active assignment. The
    request name is a new client-generated GUID and no scheduleInfo is sent. The active assignment is
    identified by its principal, role definition, and scope. The principal may be given directly as
    -PrincipalId (object id, e.g. piped from Get-OERActiveRoleAssignment) or as a friendly
    -User/-Group/-ServicePrincipal value. roleDefinitionId is the FULL ARM id resolved from -Role.
    This is a destructive operation (ConfirmImpact High) and emits a warning before the request.
    Supports -WhatIf/-Confirm. Requires an ARM token; authentication is ensured via
    Initialize-OERAuth -IncludeARM.
    .PARAMETER Role
    The role: display name, role definition GUID, or full ARM id. Pipeline by property name
    (RoleDefinitionId). Tab-completion offers the five curated common Azure RBAC roles; any other
    built-in or custom role name is still accepted.
    .PARAMETER PrincipalId
    The object id (GUID) of the principal whose active assignment is removed. Pipeline by property name;
    takes precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use
    -User, -Group, or -ServicePrincipal instead.
    .PARAMETER User
    A user principal name or object id whose active assignment is removed.
    .PARAMETER Group
    A group display name or object id whose active assignment is removed.
    .PARAMETER ServicePrincipal
    A service principal display name or object id whose active assignment is removed.
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
    assignment applies at that single resource. Pipeline by property name.
    .PARAMETER Justification
    Justification recorded on the removal request.
    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.
    .EXAMPLE
    Remove-OERActiveRoleAssignment -Role 'Reader' -User 'anna.berg@contoso.com' -Subscription 'Prod'
    Removes Anna's active Reader assignment at the Prod subscription.
    .EXAMPLE
    Get-OERActiveRoleAssignment -Subscription 'Prod' -User 'anna.berg@contoso.com' | Remove-OERActiveRoleAssignment
    Removes the piped active assignments.
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

        [string]$Justification,
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
        Write-Verbose "[Remove-OERActiveRoleAssignment] Target scope: '$TargetScope'."

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -ServicePrincipal $ServicePrincipal
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        $ResolvedPrincipalId = $Principal.PrincipalId
        Write-Verbose "[Remove-OERActiveRoleAssignment] Resolved principal to '$ResolvedPrincipalId'."

        try {
            $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Remove-OERActiveRoleAssignment] Resolved role '$Role' to '$RoleDefinitionId'."

        $Body = @{ properties = @{
                principalId      = $ResolvedPrincipalId
                requestType      = 'AdminRemove'
                roleDefinitionId = $RoleDefinitionId
            } }
        if ($Justification) { $Body.properties.justification = $Justification }

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
        $Target = "active assignment of role '$Role' for principal '$PrincipalLabel' at scope '$TargetScope'"
        if ($PSCmdlet.ShouldProcess($Target, 'Remove active Azure role assignment')) {
            Write-Warning "Removing $Target."
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
