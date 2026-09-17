function Get-OERCatalog {
    <#
    .SYNOPSIS
    Gets one or more entitlement management catalogs.

    .DESCRIPTION
    Retrieves access package catalogs through Microsoft Graph. Supply -Id to fetch a single catalog,
    -DisplayName to fetch by exact display name, -Filter to pass a raw OData filter, or none of these to
    list all catalogs. -IncludeResources expands each catalog's resources via
    $expand=accessPackageResources. Output is one or more tagged Omnicit.EntraRBAC.Catalog objects.

    .PARAMETER Id
    The catalog id (GUID) to fetch a single catalog directly.

    .PARAMETER DisplayName
    The exact display name to match via an OData filter.

    .PARAMETER Filter
    A raw OData $filter expression applied to the catalogs collection. The whole expression is
    percent-encoded before it is placed in the URI, and Graph decodes it on arrival, so a reserved
    character such as & or # survives instead of truncating the query or splitting it into a bogus
    parameter.

    .PARAMETER IncludeResources
    When set, expands the catalog's resources via $expand=accessPackageResources.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERCatalog -Id '00000000-0000-0000-0000-000000000001'
    Returns the catalog with the given id.

    .EXAMPLE
    Get-OERCatalog -DisplayName 'CAT-IT-Core'
    Returns the catalog with that exact display name.

    .EXAMPLE
    Get-OERCatalog
    Lists all catalogs in the tenant.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [Parameter(ParameterSetName = 'List')]
        [string]$Filter,

        [switch]$IncludeResources,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Base = 'v1.0/identityGovernance/entitlementManagement/catalogs'
        $Expand = if ($IncludeResources) { "`$expand=accessPackageResources" } else { $null }

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $Uri = "$Base/$Id"
            if ($Expand) { $Uri = "$Uri`?$Expand" }
            try {
                $Response = Invoke-OERGraphRequest -Uri $Uri
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERCatalog -InputObject $Response
            return
        }

        $QueryParts = @()
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
            $QueryParts += "`$filter=displayName eq '$Escaped'"
        } elseif ($Filter) {
            $Encoded = [System.Uri]::EscapeDataString($Filter)
            $QueryParts += "`$filter=$Encoded"
        }
        if ($Expand) { $QueryParts += $Expand }
        $Uri = if ($QueryParts.Count -gt 0) { "$Base`?$([string]::Join('&', $QueryParts))" } else { $Base }

        try {
            $Response = Invoke-OERGraphRequest -Uri $Uri -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            ConvertTo-OERCatalog -InputObject $Item
        }
    }
}
