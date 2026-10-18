function Resolve-OERInventoryScopeTree {
    <#
    .SYNOPSIS
    Enumerates the management group / subscription scopes to walk for a tenant inventory.

    .DESCRIPTION
    Composes the management groups (Get-OERManagementGroupList for the full tree,
    Get-OERManagementGroup -Name for one branch) and Get-OERSubscription into a flat list of ARM
    scope strings (every management group id and every subscription id) plus a nested hierarchy
    object used for the scopeHierarchy.json context file. -ManagementGroup narrows to a single branch;
    -Scope returns exactly that one raw scope without enumerating, when it may be walked (see below).
    Authentication (with ARM) is ensured at entry.

    The walk enters only the subscriptions of this tenant (BL-150, decision A19): every listed
    subscription goes through Get-OERSubscriptionHomeTenant -Subscription, which compares the tenantId
    the subscription list returned for it with the tenant the session's Microsoft Graph token was issued
    for, with no request of its own. A subscription whose home tenant is that tenant is walked as
    before. One whose home tenant is another tenant -- a customer subscription another tenant delegated
    to this one through Azure Lighthouse, for example -- is named in the output's ForeignSubscriptions
    (SubscriptionId, DisplayName, HomeTenantId, Scope) and nowhere else. One whose home tenant could not
    be decided (no tenantId that is a GUID, or a session whose token names no tenant ID) is named in
    UndecidedSubscriptions (SubscriptionId, Scope, Reason) and nowhere else. Neither is added to Scopes
    or to the hierarchy, so scopeHierarchy.json never lists it. Both lists are always arrays, empty when
    there is none. The tree writes ONE warning per call that names every undecided subscription with its
    reason; it writes none for a foreign one, which the caller reports. With -Scope, the subscription the
    scope lies in is decided by one read of it (Get-OERSubscriptionHomeTenant -Scope): a scope in the
    tenant's own subscription, or at a management group or the root scope, which lie in no subscription
    and are not read, is returned verbatim as before; a scope in a foreign subscription is named in
    ForeignSubscriptions, and one whose subscription could not be decided -- its read failed, too, or
    it breaks a scope spelling rule (Get-OERScopeSpellingProblem), a management group path included,
    and then nothing is resolved or read -- in UndecidedSubscriptions, each with the scope as given, and
    Scopes is then empty.

    With -Cache, both kinds of call pass it to Get-OERSubscriptionHomeTenant, which stores in it what it
    learned about each subscription -- the facts the list gave for a listed one, the read for the
    subscription of a -Scope -- under the subscription id in lower case (decision A20, BL-152).
    Export-OERInventory passes its run context's SubscriptionTenant, so every Get-OERInventory call it
    makes at a scope the tree returned is answered from it, with no request. The tree's requests and
    decisions are the same with and without -Cache.

    A listing that fails is never read as an empty level. For the full tree, a management-group or
    subscription listing that is refused or fails is caught, warned about, and named in the output's
    SkippedScopes ('<management groups: the listing failed>' / '<subscriptions: the listing
    failed>'), and the other level is still enumerated; the caller reports those levels as skipped.
    For a -ManagementGroup branch the read of the named branch throws, since nothing of it could be
    walked. The management-group list comes from Get-OERManagementGroupList, the listing
    Get-OERManagementGroup uses, converted here with ConvertTo-OERManagementGroup; the export does
    not read the parents of the listed groups, so it gains no failure mode from that read. A
    management group created moments ago can still be missing from the list until Azure has
    updated its hierarchy.

    .PARAMETER ManagementGroup
    A management group name or display name to narrow enumeration to one branch.

    .PARAMETER Scope
    A single raw ARM scope. When given, no enumeration occurs: the scope is returned verbatim when it
    breaks no scope spelling rule and lies in no subscription or in one of this tenant's own, and
    Scopes is empty otherwise (see above).

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.

    .PARAMETER Cache
    Optional. A dictionary passed to every Get-OERSubscriptionHomeTenant call, which stores in it what
    it learned about each subscription (see above). Export-OERInventory passes its run context's
    SubscriptionTenant.

    .EXAMPLE
    Resolve-OERInventoryScopeTree
    Returns every management group scope and the scope of each of this tenant's own subscriptions, plus
    the hierarchy, and names the subscriptions it left out in ForeignSubscriptions and
    UndecidedSubscriptions.

    .EXAMPLE
    Resolve-OERInventoryScopeTree -Cache $RunContext.SubscriptionTenant
    Returns the same, and leaves what it learned about each subscription in the cache, for the
    Get-OERInventory calls that read the scopes it returned.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [string]$ManagementGroup,
        [string]$Scope,
        [string]$TenantId,
        [System.Collections.IDictionary]$Cache
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
    # BL-150 (A19): the subscriptions the walk leaves out, since their home tenant is another tenant, or
    # could not be decided. Get-OERSubscriptionHomeTenant decides it; neither list is walked.
    $ForeignSubscriptions = [System.Collections.Generic.List[object]]::new()
    $UndecidedSubscriptions = [System.Collections.Generic.List[object]]::new()
    # ONE warning per call names every undecided subscription with its reason. A foreign one is named by
    # the caller (Export-OERInventory writes one warning for them), not here.
    $WarnUndecided = {
        if ($UndecidedSubscriptions.Count -gt 0) {
            $List = ($UndecidedSubscriptions | ForEach-Object { "'$($_.Scope)' ($($_.Reason))" }) -join '; '
            Write-Warning "Could not tell whether $($UndecidedSubscriptions.Count) subscription(s) belong to this tenant, so none of them is walked: $List"
        }
    }

    if ($Scope) {
        # One read of the subscription the scope lies in decides it; a scope at a management group or the
        # root scope lies in none and is not read. The scope is kept VERBATIM when it may be walked. With
        # -Cache the read is stored there (A20, BL-152), so the caller's own check at this scope sends none.
        $Verdict = Get-OERSubscriptionHomeTenant -Scope $Scope -Cache $Cache
        if ($Verdict.Verdict -eq 'Foreign') {
            $ForeignSubscriptions.Add([PSCustomObject]@{
                    SubscriptionId = $Verdict.SubscriptionId
                    DisplayName    = $Verdict.DisplayName
                    HomeTenantId   = $Verdict.HomeTenantId
                    Scope          = $Scope
                })
        } elseif ($Verdict.Verdict -eq 'Undecided') {
            $UndecidedSubscriptions.Add([PSCustomObject]@{
                    SubscriptionId = $Verdict.SubscriptionId
                    Scope          = $Scope
                    Reason         = $Verdict.Reason
                })
        } else {
            $Scopes.Add($Scope)
        }
        & $WarnUndecided
        $Out = [PSCustomObject]@{
            Scopes    = $Scopes.ToArray()
            Hierarchy = [PSCustomObject]@{
                managementGroups = @()
                subscriptions    = @()
            }
            SkippedScopes          = @()
            ForeignSubscriptions   = $ForeignSubscriptions.ToArray()
            UndecidedSubscriptions = $UndecidedSubscriptions.ToArray()
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
            @(Get-OERManagementGroupList | ForEach-Object { ConvertTo-OERManagementGroup -InputObject $_ })
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
        # BL-150 (A19): decided from the tenantId the list returned, with no request. Only the tenant's own
        # subscription is walked and enters the hierarchy. With -Cache the listed facts are stored there
        # (A20, BL-152), so the caller's own check at a scope in this subscription sends no request.
        $Verdict = Get-OERSubscriptionHomeTenant -Subscription $Sub -Cache $Cache
        if ($Verdict.Verdict -eq 'Foreign') {
            $ForeignSubscriptions.Add([PSCustomObject]@{
                    SubscriptionId = $Verdict.SubscriptionId
                    DisplayName    = $Verdict.DisplayName
                    HomeTenantId   = $Verdict.HomeTenantId
                    Scope          = $Verdict.Scope
                })
            continue
        }
        if ($Verdict.Verdict -ne 'Home') {
            $UndecidedSubscriptions.Add([PSCustomObject]@{
                    SubscriptionId = $Verdict.SubscriptionId
                    Scope          = $Verdict.Scope
                    Reason         = $Verdict.Reason
                })
            continue
        }
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
        SkippedScopes          = $SkippedScopes.ToArray()
        ForeignSubscriptions   = $ForeignSubscriptions.ToArray()
        UndecidedSubscriptions = $UndecidedSubscriptions.ToArray()
    }
    & $WarnUndecided
    $Out
}
