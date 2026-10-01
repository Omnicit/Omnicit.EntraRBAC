function Resolve-OERInventoryScopeTree {
    <#
    .SYNOPSIS
    Enumerates the management group / subscription scopes to walk for a tenant inventory.

    .DESCRIPTION
    Composes Get-OERManagementGroup and Get-OERSubscription into a flat list of ARM scope strings
    (every management group id and every subscription id) plus a nested hierarchy object used for the
    scopeHierarchy.json context file. -ManagementGroup narrows to a single branch; -Scope returns
    exactly that one raw scope without enumerating. Authentication (with ARM) is ensured at entry.

    A listing that fails is never read as an empty level. For the full tree, a management-group or
    subscription listing that is refused or fails is caught, warned about, and named in the output's
    SkippedScopes ('<management groups: the listing failed>' / '<subscriptions: the listing
    failed>'), and the other level is still enumerated; the caller reports those levels as skipped.
    For a -ManagementGroup branch the read of the named branch throws, since nothing of it could be
    walked. The management-group list comes from Get-OERManagementGroup, which bypasses the
    service's cache; a management group created moments ago can still be missing until Azure has
    updated its hierarchy.

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
    # A level of the tree that could not be LISTED. A refused or failed listing is never taken as
    # "there is nothing at that level": the level is named here, and the caller reports it as skipped
    # (Export-OERInventory folds it into SkippedScopes and SkippedEligibilityScopes, so the bundle is
    # InventoryPartial). Measured live 2026-09-30: app-only, the management-group listing answers
    # AuthorizationFailed, and the walk used to read that as "no management groups".
    $SkippedScopes = [System.Collections.Generic.List[string]]::new()

    if ($Scope) {
        $Scopes.Add($Scope)
        $Out = [PSCustomObject]@{
            Scopes    = $Scopes.ToArray()
            Hierarchy = [PSCustomObject]@{
                managementGroups = @()
                subscriptions    = @()
            }
            SkippedScopes = @()
        }
        return $Out
    }

    # A named branch that cannot be read leaves nothing to walk, so its failure throws and the caller
    # records the whole Azure walk as skipped. The full tree's listings are caught one by one instead:
    # the level that could not be listed is named in SkippedScopes, and the other level is still walked.
    $ManagementGroups = if ($ManagementGroup) {
        @(Get-OERManagementGroup -Name $ManagementGroup -ErrorAction Stop)
    } else {
        try {
            @(Get-OERManagementGroup -ErrorAction Stop)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-Warning "Could not list the management groups, so no management group is walked: $($PSItem.Exception.Message)"
            $SkippedScopes.Add('<management groups: the listing failed>')
            @()
        }
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
        @(Get-OERSubscription -ManagementGroup $ManagementGroup -ErrorAction Stop)
    } else {
        try {
            @(Get-OERSubscription -ErrorAction Stop)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-Warning "Could not list the subscriptions, so no subscription is walked: $($PSItem.Exception.Message)"
            $SkippedScopes.Add('<subscriptions: the listing failed>')
            @()
        }
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
        SkippedScopes = $SkippedScopes.ToArray()
    }
    $Out
}
