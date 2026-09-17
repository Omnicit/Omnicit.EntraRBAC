function ConvertTo-OERAccessPackageResourceRole {
    <#
    .SYNOPSIS
    Converts a raw Graph resourceRoleScope into a tagged Omnicit.EntraRBAC.AccessPackageResourceRole.

    .DESCRIPTION
    Maps a single resourceRoleScope (from accessPackages/{id}?$expand=resourceRoleScopes($expand=role,scope))
    into a [PSCustomObject] tagged Omnicit.EntraRBAC.AccessPackageResourceRole so Format views apply.
    Exposes ResourceRoleScopeId (the binding id, used by Remove-OERAccessPackageResourceRole), RoleName,
    ResourceDisplayName, ScopeDisplayName, OriginId, OriginSystem, and AccessPackageId. This private
    converter is the single owner of the access-package resource-role output shape and is used by
    Get-OERAccessPackageResourceRole and Add-OERAccessPackageResourceRole.

    Live Graph responses confirm accessPackageResourceScope.displayName is the display name of the
    SCOPE, not of the resource -- for a root-scoped Entra group binding Graph literally returns
    'Root'. The resourceRoleScopes payload has no nested resource object at all, so the resource's own
    display name is never present in this call; it is mapped honestly to ScopeDisplayName instead.
    ResourceDisplayName is populated only when the caller supplies -ResourceDisplayName -- typically
    joined from the access package's catalog resources by scope.originId -- and stays $null otherwise.

    .PARAMETER InputObject
    The raw Graph resourceRoleScope object (hashtable or PSObject) to convert. Accepts pipeline input.

    .PARAMETER AccessPackageId
    The id of the access package the binding belongs to, stamped onto the output for round-tripping.

    .PARAMETER ResourceDisplayName
    The resource's real display name, resolved and stamped on by the caller (for example by joining
    scope.originId against the catalog's resources). Left $null when the caller does not supply it,
    since the resourceRoleScopes payload never carries the resource's own display name.

    .EXAMPLE
    ConvertTo-OERAccessPackageResourceRole -InputObject $rrs -AccessPackageId 'ap-1'
    Converts a single resource role scope into a tagged object, with ResourceDisplayName left $null.

    .EXAMPLE
    ConvertTo-OERAccessPackageResourceRole -InputObject $rrs -AccessPackageId 'ap-1' -ResourceDisplayName 'Sales Group'
    Converts a single resource role scope, stamping the caller-resolved resource display name.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$AccessPackageId,

        [string]$ResourceDisplayName
    )
    process {
        $Out = [PSCustomObject]@{
            ResourceRoleScopeId = $InputObject.id
            RoleName            = $InputObject.role.displayName
            ResourceDisplayName = $ResourceDisplayName
            ScopeDisplayName    = $InputObject.scope.displayName
            OriginId            = $InputObject.scope.originId
            OriginSystem        = $InputObject.scope.originSystem
            AccessPackageId     = $AccessPackageId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackageResourceRole')
        $Out
    }
}
