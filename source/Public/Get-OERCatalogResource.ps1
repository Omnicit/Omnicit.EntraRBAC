function Get-OERCatalogResource {
    <#
    .SYNOPSIS
    Lists the resources onboarded into an entitlement management catalog.

    .DESCRIPTION
    Retrieves the resources of a catalog through Microsoft Graph. The catalog is given by -Catalog (id or
    display name, resolved via Resolve-OERCatalogId). -IncludeRoles expands each resource's roles
    (group Member/Owner, app roles). Output is zero or more tagged Omnicit.EntraRBAC.CatalogResource
    objects.

    .PARAMETER Catalog
    The catalog id or display name whose resources are listed. Accepts pipeline input by property name:
    a piped Omnicit.EntraRBAC.Catalog object binds via its Id, DisplayName, or CatalogId property.

    .PARAMETER IncludeRoles
    Read each resource's roles from the catalog resourceRoles endpoint (reliable for role-assignable
    and PIM-managed groups) and attach them as a Roles property.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERCatalogResource -Catalog 'CAT-IT-Core'
    Lists all resources in the catalog with that display name.

    .EXAMPLE
    Get-OERCatalogResource -Catalog 'CAT-IT-Core' -IncludeRoles
    Lists the catalog's resources with their roles expanded.

    .EXAMPLE
    Get-OERCatalogResource -Catalog '00000000-0000-0000-0000-000000000001'
    Lists all resources in the catalog with the given id.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'DisplayName', 'CatalogId')]
        [string]$Catalog,

        [switch]$IncludeRoles,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
        $CatalogId = $null
        try {
            $CatalogId = Resolve-OERCatalogId -DisplayName $Catalog
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousCatalogName' -Category InvalidArgument `
                    -TargetObject $Catalog -Cmdlet $PSCmdlet
                return
            }
        }
        if (-not $CatalogId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Catalog '$Catalog' not found.")) `
                -ErrorId 'CatalogNotFound' -Category ObjectNotFound -TargetObject $Catalog -Cmdlet $PSCmdlet
            return
        }
        $Uri = "v1.0/identityGovernance/entitlementManagement/catalogs/$CatalogId/resources"
        try {
            $Response = Invoke-OERGraphRequest -Uri $Uri -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            if ($IncludeRoles -and $Item.originSystem -and $Item.id) {
                try {
                    $Item['roles'] = Get-OERCatalogResourceRole -CatalogId $CatalogId -OriginSystem $Item.originSystem -ResourceId $Item.id
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    Write-Warning "Could not read roles for resource '$($Item.displayName)': $($PSItem.Exception.Message)"
                }
            }
            ConvertTo-OERCatalogResource -InputObject $Item -CatalogId $CatalogId
        }
    }
}
