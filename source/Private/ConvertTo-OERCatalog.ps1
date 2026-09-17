function ConvertTo-OERCatalog {
    <#
    .SYNOPSIS
    Converts a raw Microsoft Graph accessPackageCatalog into a tagged Omnicit.EntraRBAC.Catalog object.

    .DESCRIPTION
    Maps the relevant properties of a Graph entitlement management catalog (returned by
    Invoke-OERGraphRequest as a hashtable) into a [PSCustomObject] tagged Omnicit.EntraRBAC.Catalog so
    Format and Types views apply. This private converter is the single owner of the catalog output
    shape and is used by New/Get/Set-OERCatalog. The isExternallyVisible property is coerced to [bool]
    so a missing value becomes $false rather than $null.

    .PARAMETER InputObject
    The raw Graph catalog object (hashtable or PSObject) to convert into a tagged object.

    .EXAMPLE
    ConvertTo-OERCatalog -InputObject (Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/entitlementManagement/catalogs/cat-1')
    Converts a single fetched catalog into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $Out = [PSCustomObject]@{
            Id                = $InputObject.id
            DisplayName       = $InputObject.displayName
            Description       = $InputObject.description
            CatalogType       = $InputObject.catalogType
            State             = $InputObject.state
            ExternallyVisible = [bool]$InputObject.isExternallyVisible
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Catalog')
        $Out
    }
}
