function Add-OERCatalogResource {
    <#
    .SYNOPSIS
    Onboards a group, application, or SharePoint site as a resource in an entitlement management catalog.

    .DESCRIPTION
    Creates an accessPackageResourceRequest (requestType adminAdd) through Microsoft Graph to add a
    resource to a catalog. The resource type and how it is identified are selected by parameter set:

    - -GroupId / -ApplicationId take an object id directly (no lookup).
    - -Group / -Application take a display name and resolve it to an object id (groups via
      Resolve-OERGroupId, enterprise applications via Resolve-OERApplicationId, which queries
      servicePrincipals). A name that does not resolve produces a non-terminating GroupNotFound or
      ApplicationNotFound error.
    - -SharePointSite takes a site URL (originSystem SharePointOnline).

    Groups onboard with originSystem AadGroup; applications with originSystem AadApplication (the resolved
    or supplied value is the service principal object id). The catalog is given by -Catalog (id or display
    name, resolved via Resolve-OERCatalogId). The command is idempotent: if a resource with the same origin
    already exists in the catalog it is returned and nothing is created. Output is a tagged
    Omnicit.EntraRBAC.CatalogResource object. Supports -WhatIf and -Confirm.

    .PARAMETER Catalog
    The catalog id or display name to add the resource to. Accepts pipeline input by property name:
    a piped Omnicit.EntraRBAC.Catalog object binds via its Id, DisplayName, or CatalogId property.

    .PARAMETER GroupId
    The object id of a group to onboard (originSystem AadGroup). Used as-is without a lookup.

    .PARAMETER Group
    The display name of a group to onboard; resolved to its object id via Resolve-OERGroupId
    (originSystem AadGroup).

    .PARAMETER ApplicationId
    The service principal object id of an enterprise application to onboard (originSystem AadApplication).
    Used as-is without a lookup.

    .PARAMETER Application
    The display name of an enterprise application to onboard; resolved to its service principal object id
    via Resolve-OERApplicationId (originSystem AadApplication).

    .PARAMETER SharePointSite
    The site URL of a SharePoint Online site to onboard (originSystem SharePointOnline).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Add-OERCatalogResource -Catalog 'CAT-IT-Core' -GroupId '11111111-1111-1111-1111-111111111111'
    Onboards the group by object id into the catalog, or returns it if already present.

    .EXAMPLE
    Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Group 'Sales Team'
    Resolves the group named 'Sales Team' to its object id and onboards it.

    .EXAMPLE
    Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Application 'Contoso Expense Portal'
    Resolves the enterprise application by name to its service principal id and onboards it.

    .EXAMPLE
    Add-OERCatalogResource -Catalog 'CAT-IT-Core' -SharePointSite 'https://contoso.sharepoint.com/sites/finance'
    Onboards the SharePoint site into the catalog.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'GroupByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'DisplayName', 'CatalogId')]
        [string]$Catalog,

        [Parameter(ParameterSetName = 'GroupById', Mandatory)]
        [string]$GroupId,

        [Parameter(ParameterSetName = 'GroupByName', Mandatory)]
        [string]$Group,

        [Parameter(ParameterSetName = 'AppById', Mandatory)]
        [string]$ApplicationId,

        [Parameter(ParameterSetName = 'AppByName', Mandatory)]
        [string]$Application,

        [Parameter(ParameterSetName = 'SharePointSite', Mandatory)]
        [string]$SharePointSite,

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

        switch ($PSCmdlet.ParameterSetName) {
            'GroupById' {
                $OriginId = $GroupId
                $OriginSystem = 'AadGroup'
            }
            'GroupByName' {
                # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
                $OriginId = $null
                try {
                    $OriginId = Resolve-OERGroupId -DisplayName $Group
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    if (Test-OERAmbiguousNameError -Record $PSItem) {
                        Write-CmdletError `
                            -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                            -ErrorId 'AmbiguousGroupName' -Category InvalidArgument `
                            -TargetObject $Group -Cmdlet $PSCmdlet
                        return
                    }
                }
                $OriginSystem = 'AadGroup'
                if (-not $OriginId) {
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Group '$Group' not found.")) `
                        -ErrorId 'GroupNotFound' -Category ObjectNotFound -TargetObject $Group -Cmdlet $PSCmdlet
                    return
                }
            }
            'AppById' {
                $OriginId = $ApplicationId
                $OriginSystem = 'AadApplication'
            }
            'AppByName' {
                $OriginId = try { Resolve-OERApplicationId -DisplayName $Application } catch { Remove-OERErrorRecord -Record $PSItem; $null }
                $OriginSystem = 'AadApplication'
                if (-not $OriginId) {
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Application '$Application' not found.")) `
                        -ErrorId 'ApplicationNotFound' -Category ObjectNotFound -TargetObject $Application -Cmdlet $PSCmdlet
                    return
                }
            }
            'SharePointSite' {
                $OriginId = $SharePointSite
                $OriginSystem = 'SharePointOnline'
            }
        }

        $Existing = try { Resolve-OERCatalogResource -CatalogId $CatalogId -OriginId $OriginId } catch { Remove-OERErrorRecord -Record $PSItem; $null }
        if ($Existing) {
            Write-Verbose "[Add-OERCatalogResource] Resource '$OriginId' already in catalog '$CatalogId'; returning existing."
            ConvertTo-OERCatalogResource -InputObject $Existing -CatalogId $CatalogId
            return
        }

        # For every resource type the identifier goes in originId: the directory object id for groups
        # and applications, and the site URL for SharePoint Online sites. Graph has no url field in the
        # adminAdd body, so it is never set here.
        $Body = @{
            requestType = 'adminAdd'
            resource    = @{ originId = $OriginId; originSystem = $OriginSystem }
            catalog     = @{ id = $CatalogId }
        }

        if ($PSCmdlet.ShouldProcess($OriginId, "Onboard $OriginSystem resource into catalog $CatalogId")) {
            try {
                $Request = Invoke-OERGraphRequest -Method POST `
                    -Uri 'v1.0/identityGovernance/entitlementManagement/resourceRequests' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($Request.resource) {
                ConvertTo-OERCatalogResource -InputObject $Request.resource -CatalogId $CatalogId
            } else {
                # Some tenants return the request without an inline resource; re-resolve.
                $Created = try { Resolve-OERCatalogResource -CatalogId $CatalogId -OriginId $OriginId } catch { Remove-OERErrorRecord -Record $PSItem; $null }
                if ($Created) { ConvertTo-OERCatalogResource -InputObject $Created -CatalogId $CatalogId }
            }
        }
    }
}
