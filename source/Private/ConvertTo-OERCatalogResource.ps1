function ConvertTo-OERCatalogResource {
    <#
    .SYNOPSIS
    Converts a raw Microsoft Graph accessPackageResource into a tagged Omnicit.EntraRBAC.CatalogResource.

    .DESCRIPTION
    Maps the relevant properties of a Graph catalog resource (returned by Invoke-OERGraphRequest as a
    hashtable) into a [PSCustomObject] tagged Omnicit.EntraRBAC.CatalogResource so Format and Types
    views apply. The mapped properties are Id, DisplayName, ResourceType, OriginId, OriginSystem,
    Url, Roles (when the resource was read with roles attached), and CatalogId (when the caller
    supplies it). This private converter is the single owner of the catalog-resource output shape
    and is used by Add/Get-OERCatalogResource.

    Graph populates the resourceType field asynchronously during resource onboarding, so it is often
    empty immediately after a resource is added. When the Graph value is empty, ResourceType falls back
    to a friendly label derived from the originSystem (AadGroup -> Group, AadApplication -> Application,
    SharePointOnline -> SharePoint Online Site); once Graph populates the real value it is used as-is.

    .PARAMETER InputObject
    The raw Graph accessPackageResource object (hashtable or PSObject) to convert into a tagged object.
    Accepts pipeline input so a collection can be piped directly.

    .PARAMETER CatalogId
    The id of the catalog the resource belongs to, stamped onto the output by the caller (which
    already resolved it) so a piped resource carries its parent catalog without a second lookup.
    Left $null when the caller does not supply it, since the raw Graph accessPackageResource payload
    carries no catalog reference of its own.

    .EXAMPLE
    ConvertTo-OERCatalogResource -InputObject $resource
    Converts a single catalog resource into a tagged Omnicit.EntraRBAC.CatalogResource object.

    .EXAMPLE
    $resources | ConvertTo-OERCatalogResource -CatalogId 'cat-1'
    Converts each resource in a collection via the pipeline, stamping the same CatalogId on each.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        # Declared last so pre-existing positional and pipeline binding is unchanged.
        [string]$CatalogId
    )
    process {
        $ResourceType = if ($InputObject.resourceType) {
            $InputObject.resourceType
        } else {
            switch ($InputObject.originSystem) {
                'AadGroup'         { 'Group' }
                'AadApplication'   { 'Application' }
                'SharePointOnline' { 'SharePoint Online Site' }
                default            { $InputObject.originSystem }
            }
        }
        $Roles = $null
        if ($InputObject.roles) {
            $Roles = @(foreach ($Role in @($InputObject.roles)) {
                [PSCustomObject]@{
                    DisplayName = $Role.displayName
                    Id          = $Role.id
                    OriginId    = $Role.originId
                }
            })
        }
        $Out = [PSCustomObject]@{
            Id           = $InputObject.id
            DisplayName  = $InputObject.displayName
            ResourceType = $ResourceType
            OriginId     = $InputObject.originId
            OriginSystem = $InputObject.originSystem
            Url          = $InputObject.url
            Roles        = $Roles
            CatalogId    = $CatalogId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.CatalogResource')
        $Out
    }
}
