function Resolve-OERInventoryScopeTree {
    <#
    .SYNOPSIS
    Enumerates the management group / subscription scopes to walk for a tenant inventory.

    .DESCRIPTION
    Composes Get-OERManagementGroup and Get-OERSubscription into a flat list of ARM scope strings
    (every management group id and every subscription id) plus a nested hierarchy object used for the
    scopeHierarchy.json context file. -ManagementGroup narrows to a single branch; -Scope returns
    exactly that one raw scope without enumerating. Authentication (with ARM) is ensured at entry.

    .PARAMETER ManagementGroup
    A management group name or display name to narrow enumeration to one branch.

    .PARAMETER Scope
    A single raw ARM scope. When given, that scope is returned verbatim and no enumeration occurs.

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.

    .EXAMPLE
    Resolve-OERInventoryScopeTree
    Returns all management group and subscription scopes plus the hierarchy.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [string]$ManagementGroup,
        [string]$Scope,
        [string]$TenantId
    )
    $AuthParams = @{}
    if ($TenantId) { $AuthParams.TenantId = $TenantId }
    Initialize-OERAuth @AuthParams -IncludeARM

    $Scopes = [System.Collections.Generic.List[string]]::new()
    $MgNodes = [System.Collections.Generic.List[object]]::new()
    $SubNodes = [System.Collections.Generic.List[object]]::new()

    if ($Scope) {
        $Scopes.Add($Scope)
        $Out = [PSCustomObject]@{
            Scopes    = $Scopes.ToArray()
            Hierarchy = [PSCustomObject]@{
                managementGroups = @()
                subscriptions    = @()
            }
        }
        return $Out
    }

    $ManagementGroups = if ($ManagementGroup) {
        @(Get-OERManagementGroup -Name $ManagementGroup)
    } else {
        @(Get-OERManagementGroup)
    }
    foreach ($Mg in $ManagementGroups) {
        if ($Mg.ResourceId) { $Scopes.Add([string]$Mg.ResourceId) }
        $MgNodes.Add([PSCustomObject]@{
            name        = [string]$Mg.Name
            displayName = [string]$Mg.DisplayName
            id          = [string]$Mg.ResourceId
        })
    }

    $Subscriptions = if ($ManagementGroup) {
        @(Get-OERSubscription -ManagementGroup $ManagementGroup)
    } else {
        @(Get-OERSubscription)
    }
    foreach ($Sub in $Subscriptions) {
        if ($Sub.ResourceId) { $Scopes.Add([string]$Sub.ResourceId) }
        $SubNodes.Add([PSCustomObject]@{
            subscriptionId = [string]$Sub.SubscriptionId
            displayName    = [string]$Sub.DisplayName
            id             = [string]$Sub.ResourceId
            state          = [string]$Sub.State
        })
    }

    $Out = [PSCustomObject]@{
        Scopes    = $Scopes.ToArray()
        Hierarchy = [PSCustomObject]@{
            managementGroups = $MgNodes.ToArray()
            subscriptions    = $SubNodes.ToArray()
        }
    }
    $Out
}
