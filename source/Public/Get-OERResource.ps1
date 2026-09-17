function Get-OERResource {
    <#
    .SYNOPSIS
    Lists Azure resources in a subscription or resource group, optionally with their role assignments.

    .DESCRIPTION
    Reads resources through the ARM API (api-version 2025-04-01) via Invoke-OERArmRequest. The
    subscription (GUID or display name) is resolved with Resolve-OERScope. With -ResourceGroup the
    listing is scoped to one resource group; without it, every resource in the subscription is listed
    (paged) -- which can be large. -Name and -ResourceType filter the results client-side
    (case-insensitive). With -IncludeRoleAssignments, each returned resource gains a RoleAssignments
    property holding the role assignments at that resource's scope (via Get-OERRoleAssignment -AtScope)
    -- a light aggregator for the delegations on a single resource. -ResolveNames is forwarded to
    Get-OERRoleAssignment so those assignments carry PrincipalDisplayName and RoleName; it requires
    -IncludeRoleAssignments. Output objects are tagged Omnicit.EntraRBAC.Resource and expose
    SubscriptionId, ResourceGroup, ResourceType, and ResourceName, so they pipe into the Azure RBAC and
    PIM cmdlets at resource scope. Requires an ARM token; authentication is ensured at entry via
    Initialize-OERAuth -IncludeARM.

    .PARAMETER Subscription
    A subscription GUID or display name. Bound from the pipeline by property name (SubscriptionId).

    .PARAMETER ResourceGroup
    A resource group name. When omitted, all resources in the subscription are listed. Bound from the
    pipeline by property name.

    .PARAMETER Name
    A resource name filter applied client-side (case-insensitive). Only resources whose name matches
    are returned.

    .PARAMETER ResourceType
    A resource type filter applied client-side (e.g. 'Microsoft.Storage/storageAccounts'). Only
    resources of the given type are returned.

    .PARAMETER IncludeRoleAssignments
    For each resource, attach a RoleAssignments property with the role assignments that apply at that
    resource's scope. This uses atScope() semantics, so the list includes assignments inherited from the
    resource group, subscription, and management group, not only assignments defined directly on the
    resource.

    .PARAMETER ResolveNames
    Enrich the attached role assignments with PrincipalDisplayName and RoleName. Requires
    -IncludeRoleAssignments.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app'
    Lists every resource in the rg-app resource group of the Prod subscription.

    .EXAMPLE
    Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -Name 'stgfoo' | New-OERRoleAssignment -Role 'Reader' -Group 'role_sec_readers'
    Grants Reader on the single storage account stgfoo by piping the resource into the delegation cmdlet.

    .EXAMPLE
    Get-OERResource -Subscription 'Prod' -ResourceGroup 'rg-app' -IncludeRoleAssignments -ResolveNames
    Lists rg-app's resources with the delegations on each, principal and role names resolved.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceGroup,

        [string]$Name,
        [string]$ResourceType,
        [switch]$IncludeRoleAssignments,
        [switch]$ResolveNames,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($ResolveNames -and -not $IncludeRoleAssignments) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-ResolveNames requires -IncludeRoleAssignments.')) `
                -ErrorId 'ResolveNamesWithoutRoleAssignments' -Category InvalidArgument -TargetObject $Subscription -Cmdlet $PSCmdlet
            return
        }

        try {
            $SubScope = Resolve-OERScope -Subscription $Subscription
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $Subscription -Cmdlet $PSCmdlet
            return
        }
        $SubscriptionId = ($SubScope -split '/')[-1]

        if ($ResourceGroup) {
            $Path = "/subscriptions/$SubscriptionId/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/resources?api-version=2025-04-01"
        } else {
            $Path = "/subscriptions/$SubscriptionId/resources?api-version=2025-04-01"
        }

        try {
            $Response = Invoke-OERArmRequest -Path $Path -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        $Items = @($Response.value)
        if ($Name) { $Items = @($Items | Where-Object { $PSItem.name -eq $Name }) }
        if ($ResourceType) { $Items = @($Items | Where-Object { $PSItem.type -eq $ResourceType }) }

        foreach ($Item in $Items) {
            $Resource = ConvertTo-OERResource -InputObject $Item
            if ($IncludeRoleAssignments) {
                $RaParams = @{ Scope = $Resource.ResourceId; AtScope = $true }
                if ($ResolveNames) { $RaParams.ResolveNames = $true }
                $Assignments = @(Get-OERRoleAssignment @RaParams)
                $Resource | Add-Member -NotePropertyName 'RoleAssignments' -NotePropertyValue $Assignments
            }
            $Resource
        }
    }
}
