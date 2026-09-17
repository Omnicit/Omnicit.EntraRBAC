function Resolve-OERScope {
    <#
    .SYNOPSIS
    Resolves friendly scope parameters into an ARM scope string.

    .DESCRIPTION
    The single scope-resolution entry point for the Azure RBAC cmdlets. Exactly one of -Scope,
    -Subscription, or -ManagementGroup must be supplied; -ResourceGroup may only accompany
    -Subscription. A raw -Scope must start with '/' and is passed through unchanged. A -Subscription
    GUID is used directly; any other value is resolved by listing /subscriptions and matching
    displayName case-insensitively. A -ManagementGroup value is first tried verbatim as the
    management group name (the URL id segment); when that GET fails, the management group list is
    matched on displayName. Throws on caller error -- the public cmdlets catch and route the message
    through Write-CmdletError.

    .PARAMETER Scope
    A raw ARM scope string such as '/subscriptions/{id}/resourceGroups/{rg}'. Must start with '/'.

    .PARAMETER Subscription
    A subscription GUID or display name.

    .PARAMETER ResourceGroup
    A resource group name that narrows the -Subscription scope. Requires -Subscription.

    .PARAMETER ManagementGroup
    A management group name (id segment) or display name.

    .PARAMETER ResourceType
    The full resource type (e.g. 'Microsoft.Storage/storageAccounts') used to disambiguate a resource
    name within the resource group. Requires -ResourceName.

    .PARAMETER ResourceName
    A resource name within the -ResourceGroup. When supplied (with -Subscription and -ResourceGroup),
    the resource's full ARM id is resolved by listing the resource group and matching the name.

    .EXAMPLE
    Resolve-OERScope -Subscription 'Prod' -ResourceGroup 'rg-network'
    Returns '/subscriptions/<guid>/resourceGroups/rg-network'.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Scope,
        [string]$Subscription,
        [string]$ResourceGroup,
        [string]$ManagementGroup,
        [string]$ResourceType,
        [string]$ResourceName
    )

    $Supplied = @()
    if ($Scope) { $Supplied += '-Scope' }
    if ($Subscription) { $Supplied += '-Subscription' }
    if ($ManagementGroup) { $Supplied += '-ManagementGroup' }
    if ($Supplied.Count -gt 1) {
        throw "Supply only one of -Scope, -Subscription or -ManagementGroup (got: $($Supplied -join ', '))."
    }
    if ($ResourceGroup -and -not $Subscription) {
        throw '-ResourceGroup requires -Subscription.'
    }
    if ($ResourceType -and -not $ResourceName) {
        throw '-ResourceType requires -ResourceName.'
    }
    if ($ResourceName -and -not ($Subscription -and $ResourceGroup)) {
        throw '-ResourceName requires -Subscription and -ResourceGroup.'
    }
    if ($Supplied.Count -eq 0) {
        throw 'A scope is required: supply -Scope, -Subscription (optionally with -ResourceGroup) or -ManagementGroup.'
    }

    if ($Scope) {
        if ($Scope -notlike '/*') {
            throw "Scope '$Scope' is not a valid ARM resource id: it must start with '/'."
        }
        return $Scope
    }

    if ($Subscription) {
        $SubscriptionId = if (Test-OERGuid -Value $Subscription) {
            $Subscription
        } else {
            $Response = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
            $Match = @($Response.value) | Where-Object { $PSItem.displayName -eq $Subscription } | Select-Object -First 1
            if (-not $Match) {
                throw "Subscription '$Subscription' was not found or you do not have access to it."
            }
            [string]$Match.subscriptionId
        }
        if ($ResourceName) {
            $ResourcesPath = "/subscriptions/$SubscriptionId/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/resources?api-version=2025-04-01"
            $ResourcesResponse = Invoke-OERArmRequest -Path $ResourcesPath -All
            $ResourceMatches = @($ResourcesResponse.value) | Where-Object { $PSItem.name -eq $ResourceName }
            if ($ResourceType) {
                $ResourceMatches = @($ResourceMatches) | Where-Object { $PSItem.type -eq $ResourceType }
            }
            $ResourceMatches = @($ResourceMatches)
            if ($ResourceMatches.Count -eq 0) {
                $TypeHint = if ($ResourceType) { " of type '$ResourceType'" } else { '' }
                throw "Resource '$ResourceName'$TypeHint was not found in resource group '$ResourceGroup'."
            }
            if ($ResourceMatches.Count -gt 1) {
                throw "Resource '$ResourceName' is ambiguous in resource group '$ResourceGroup' (more than one type matches); specify -ResourceType."
            }
            return [string]$ResourceMatches[0].id
        }
        if ($ResourceGroup) { return "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" }
        return "/subscriptions/$SubscriptionId"
    }

    # Management group: the name IS the URL segment, so try it verbatim first (no list round-trip),
    # then fall back to a displayName match over the list.
    $Verbatim = $null
    try {
        $Verbatim = Invoke-OERArmRequest -Path "/providers/Microsoft.Management/managementGroups/$([uri]::EscapeDataString($ManagementGroup))?api-version=2020-05-01"
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        # ARM returns 403 AuthorizationFailed (not 404) for a management group name that does not
        # exist OR that the caller cannot read ("...or the scope is invalid") -- the two cannot be
        # told apart. Treat that family (and a 404) as "the value may be a display name, not the id
        # segment" and fall through to the displayName list match. Genuine throttling/server/transport
        # failures (429/5xx/ArmTransportError) must surface as-is, not masquerade as not-found.
        if ($PSItem.FullyQualifiedErrorId -notin 'NotFound', 'AuthorizationFailed') {
            throw $PSItem
        }
    }
    if ($Verbatim) { return [string]$Verbatim.id }

    $List = Invoke-OERArmRequest -Path '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -All
    $MgMatch = @($List.value) | Where-Object { $PSItem.properties.displayName -eq $ManagementGroup } | Select-Object -First 1
    if (-not $MgMatch) {
        throw "Management group '$ManagementGroup' was not found, or you do not have access to it."
    }
    return [string]$MgMatch.id
}
