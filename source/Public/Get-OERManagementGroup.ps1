function Get-OERManagementGroup {
    <#
    .SYNOPSIS
    Lists Azure management groups or gets one management group, optionally with its child hierarchy.

    .DESCRIPTION
    Reads Microsoft.Management/managementGroups through the ARM API (api-version 2020-05-01) via
    Invoke-OERArmRequest. Without -Name, all management groups visible to the caller are listed
    (paged). With -Name, the single management group is fetched; -Expand includes the direct
    children (management groups and subscriptions) and -Recurse includes the entire hierarchy
    (-Recurse implies -Expand because the API requires $expand=children with $recurse=true).
    Output objects are tagged Omnicit.EntraRBAC.ManagementGroup and expose ManagementGroupName so
    they pipe into Get-OERSubscription and the RBAC cmdlets. Requires an ARM token; authentication
    is ensured at entry via Initialize-OERAuth -IncludeARM.

    .PARAMETER Name
    The management group name (its id segment, not the display name). Also bindable as
    -ManagementGroup, the name every RBAC and PIM cmdlet uses for the same scope target, or as
    -ManagementGroupName. Binds from the pipeline by property name. When omitted, all management
    groups are listed.

    .PARAMETER Expand
    Include the direct children (child management groups and subscriptions) in the response.

    .PARAMETER Recurse
    Include the entire hierarchy below the management group. Implies -Expand.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERManagementGroup
    Lists all management groups visible to the caller.

    .EXAMPLE
    Get-OERManagementGroup -Name 'mg-platform' -Recurse
    Gets the mg-platform management group with its full child hierarchy.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ManagementGroupName', 'ManagementGroup')]
        [string]$Name,

        [switch]$Expand,
        [switch]$Recurse,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($Name) {
            $Path = "/providers/Microsoft.Management/managementGroups/$([uri]::EscapeDataString($Name))?api-version=2020-05-01"
            if ($Expand -or $Recurse) { $Path += '&$expand=children' }
            if ($Recurse) { $Path += '&$recurse=true' }
            try {
                $Response = Invoke-OERArmRequest -Path $Path
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # ARM returns 403 AuthorizationFailed (not 404) for a management group name that does
                # not exist OR that the caller cannot read ("...or the scope is invalid") -- the two
                # are indistinguishable. Surface a clear not-found message instead of the raw
                # authorization error; genuine throttling/server failures pass through unchanged.
                if ($PSItem.FullyQualifiedErrorId -in 'AuthorizationFailed', 'NotFound') {
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Management group '$Name' was not found, or you do not have access to it (Microsoft.Management/managementGroups/read).")) `
                        -ErrorId 'ManagementGroupNotFound' -Category ObjectNotFound -TargetObject $Name -Cmdlet $PSCmdlet
                } else {
                    $PSCmdlet.WriteError($PSItem)
                }
                return
            }
            ConvertTo-OERManagementGroup -InputObject $Response
            return
        }

        try {
            $Response = Invoke-OERArmRequest -Path '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            ConvertTo-OERManagementGroup -InputObject $Item
        }
    }
}
