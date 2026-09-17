function Get-OERAccessPackage {
    <#
    .SYNOPSIS
    Gets one or more access packages.

    .DESCRIPTION
    Retrieves access packages through Microsoft Graph. Supply -Id for a single package, -DisplayName for
    an exact name match, -Catalog to filter by parent catalog, -Filter for a raw OData filter, or none to
    list all. -IncludeResourceRoles and -IncludePolicies expand the corresponding navigation properties
    AND surface them on the returned object as ResourceRoleScopes and AssignmentPolicies respectively --
    each element converted through the same private converter its dedicated Get- cmdlet uses
    (ConvertTo-OERAccessPackageResourceRole, ConvertTo-OERAssignmentPolicy), so the shape matches. Neither
    property exists on the object at all (not merely $null) when the matching switch is not supplied --
    that half is guaranteed by this cmdlet's own code. When the switch IS supplied, the property is
    present whenever Graph returns the expanded relationship, including as an empty array; that half
    depends on Graph actually emitting the key for an expanded-but-empty relationship, which has not been
    verified against a live tenant. Output is one or more tagged Omnicit.EntraRBAC.AccessPackage objects.

    The catalog navigation property is ALWAYS expanded, on every parameter set, so the CatalogId on the
    returned object is populated. The v1.0 accessPackage entity has no catalogId property of its own --
    it exposes only createdDateTime, description, displayName, id, isHidden and modifiedDateTime -- so
    the parent catalog can only reach the caller through this expand. The cost is a slightly larger
    response on a full list read; that is accepted because a CatalogId the output shape advertises, and
    that the table view prints as a column, must never be empty.

    .PARAMETER Id
    The access package id (GUID) to fetch directly.

    .PARAMETER DisplayName
    The exact display name to resolve and fetch.

    .PARAMETER Catalog
    A catalog id or display name to filter packages by parent catalog. Accepts pipeline input by
    property name via the CatalogId alias, so a piped Omnicit.EntraRBAC.Catalog object binds directly
    without a separate display-name lookup.

    .PARAMETER Filter
    A raw OData $filter expression applied to the accessPackages collection. The whole expression is
    percent-encoded before it is placed in the URI, and Graph decodes it on arrival, so a reserved
    character such as & or # survives instead of truncating the query or splitting it into a bogus
    parameter.

    .PARAMETER IncludeResourceRoles
    Expand resource role scopes via $expand=resourceRoleScopes and surface them on the returned object
    as ResourceRoleScopes, one tagged Omnicit.EntraRBAC.AccessPackageResourceRole per binding.
    resourceRoleScopes is the v1.0 relationship name -- the v1.0 accessPackage entity's relationships
    are accessPackagesIncompatibleWith, assignmentPolicies, catalog, incompatibleAccessPackages,
    incompatibleGroups and resourceRoleScopes. accessPackageResourceRoleScopes is the BETA spelling and
    is rejected by the v1.0 endpoint this cmdlet calls. IMPORTANT: each element's ResourceDisplayName is
    always $null here -- that value comes from a second Graph call (a catalog-resources join by
    originId) that only Get-OERAccessPackageResourceRole makes, and this private converter must not
    perform a transport call of its own. Use Get-OERAccessPackageResourceRole directly when you need the
    resource display name populated.

    .PARAMETER IncludePolicies
    Expand assignment policies via $expand=assignmentPolicies and surface them on the returned object as
    AssignmentPolicies, one tagged Omnicit.EntraRBAC.AssignmentPolicy per policy.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAccessPackage -Id '00000000-0000-0000-0000-000000000001'
    Returns the access package with the given id.

    .EXAMPLE
    Get-OERAccessPackage -DisplayName 'AP-Sales' -IncludePolicies
    Returns the named access package with its AssignmentPolicies property populated.

    .EXAMPLE
    Get-OERAccessPackage -Catalog 'CAT-IT-Core'
    Lists all access packages belonging to the catalog named CAT-IT-Core.

    .EXAMPLE
    Get-OERAccessPackage
    Lists all access packages in the tenant.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [Parameter(ParameterSetName = 'List', ValueFromPipelineByPropertyName)]
        [Alias('CatalogId')]
        [string]$Catalog,

        [Parameter(ParameterSetName = 'List')]
        [string]$Filter,

        [switch]$IncludeResourceRoles,
        [switch]$IncludePolicies,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Base = 'v1.0/identityGovernance/entitlementManagement/accessPackages'
        # 'catalog' is expanded UNCONDITIONALLY, on both the by-id read and the list read. The v1.0
        # accessPackage entity carries no catalogId property at all -- its only properties are
        # createdDateTime, description, displayName, id, isHidden and modifiedDateTime -- and catalog
        # is a navigation property, so without this expand the CatalogId that the
        # Omnicit.EntraRBAC.AccessPackage shape advertises (and that the format view prints as a
        # column) is structurally always empty. Same class of gap, and same fix, as the
        # $expand=target,accessPackage added to Get-OERAccessPackageAssignment.
        # $expand=catalog with NO nested $select is the shape already proven live on this endpoint by
        # Get-OERAccessPackageResourceRole -- do not "optimize" it to catalog($select=id) without live
        # evidence that Graph accepts that shape here.
        $Expands = @('catalog')
        if ($IncludeResourceRoles) { $Expands += 'resourceRoleScopes' }
        if ($IncludePolicies)      { $Expands += 'assignmentPolicies' }
        $ExpandPart = if ($Expands.Count -gt 0) { "`$expand=$([string]::Join(',', $Expands))" } else { $null }

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $Uri = "$Base/$Id"
            if ($ExpandPart) { $Uri = "$Uri`?$ExpandPart" }
            try {
                $Response = Invoke-OERGraphRequest -Uri $Uri
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERAccessPackage -InputObject $Response
            return
        }

        $QueryParts = @()
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
            $QueryParts += "`$filter=displayName eq '$Escaped'"
        } elseif ($Catalog) {
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
                Write-CmdletError -Message ([System.Exception]::new("Catalog '$Catalog' not found.")) `
                    -ErrorId 'CatalogNotFound' -Category ObjectNotFound -TargetObject $Catalog -Cmdlet $PSCmdlet
                return
            }
            $QueryParts += "`$filter=catalog/id eq '$CatalogId'"
        } elseif ($Filter) {
            $Encoded = [System.Uri]::EscapeDataString($Filter)
            $QueryParts += "`$filter=$Encoded"
        }
        if ($ExpandPart) { $QueryParts += $ExpandPart }
        $Uri = if ($QueryParts.Count -gt 0) { "$Base`?$([string]::Join('&', $QueryParts))" } else { $Base }

        try {
            $Response = Invoke-OERGraphRequest -Uri $Uri -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            ConvertTo-OERAccessPackage -InputObject $Item
        }
    }
}
