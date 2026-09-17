function Get-OERResourceGroup {
    <#
    .SYNOPSIS
    Lists Azure resource groups in a subscription, gets one, and optionally lists their role assignments.

    .DESCRIPTION
    Reads Microsoft.Resources/resourceGroups through the ARM API (api-version 2025-04-01) via
    Invoke-OERArmRequest. The subscription (GUID or display name) is resolved with Resolve-OERScope.
    Without -Name, every resource group in the subscription is listed (paged); with -Name, the single
    resource group is fetched and a missing one yields a clean ResourceGroupNotFound error. With
    -IncludeRoleAssignments, each returned resource group gains a RoleAssignments property holding the
    role assignments at that resource group scope (via Get-OERRoleAssignment -AtScope) -- this is the
    light aggregator that lists every delegation on every resource group under a subscription.
    -ResolveNames is forwarded to Get-OERRoleAssignment so those assignments carry PrincipalDisplayName
    and RoleName; it requires -IncludeRoleAssignments. Output objects are tagged
    Omnicit.EntraRBAC.ResourceGroup and expose SubscriptionId and ResourceGroup so they pipe into the
    RBAC and PIM cmdlets. Requires an ARM token; authentication is ensured at entry via
    Initialize-OERAuth -IncludeARM.

    .PARAMETER Subscription
    A subscription GUID or display name. Bound from the pipeline by property name (SubscriptionId).

    .PARAMETER Name
    A resource group name. When omitted, all resource groups in the subscription are listed.

    .PARAMETER IncludeRoleAssignments
    For each resource group, attach a RoleAssignments property with the role assignments at that
    resource group scope.

    .PARAMETER ResolveNames
    Enrich the attached role assignments with PrincipalDisplayName and RoleName. Requires
    -IncludeRoleAssignments.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERResourceGroup -Subscription 'Prod'
    Lists every resource group in the Prod subscription.

    .EXAMPLE
    Get-OERResourceGroup -Subscription 'Prod' -IncludeRoleAssignments -ResolveNames
    Lists every resource group in Prod with the role assignments (delegations) on each, names resolved.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ResourceGroup')]
        [string]$Name,

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

        if ($Name) {
            try {
                $Response = Invoke-OERArmRequest -Path "/subscriptions/$SubscriptionId/resourcegroups/$([uri]::EscapeDataString($Name))?api-version=2025-04-01"
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -in 'ResourceGroupNotFound', 'NotFound') {
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Resource group '$Name' was not found in subscription '$SubscriptionId'.")) `
                        -ErrorId 'ResourceGroupNotFound' -Category ObjectNotFound -TargetObject $Name -Cmdlet $PSCmdlet
                } else {
                    $PSCmdlet.WriteError($PSItem)
                }
                return
            }
            $ResourceGroups = @($Response)
        } else {
            try {
                $Response = Invoke-OERArmRequest -Path "/subscriptions/$SubscriptionId/resourcegroups?api-version=2025-04-01" -All
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            $ResourceGroups = @($Response.value)
        }

        foreach ($Item in $ResourceGroups) {
            $Rg = ConvertTo-OERResourceGroup -InputObject $Item
            if ($IncludeRoleAssignments) {
                $RaParams = @{ Scope = $Rg.ResourceId; AtScope = $true }
                if ($ResolveNames) { $RaParams.ResolveNames = $true }
                $Assignments = @(Get-OERRoleAssignment @RaParams)
                $Rg | Add-Member -NotePropertyName 'RoleAssignments' -NotePropertyValue $Assignments
            }
            $Rg
        }
    }
}
