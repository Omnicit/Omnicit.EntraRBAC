function ConvertTo-OERAccessPackage {
    <#
    .SYNOPSIS
    Converts a raw Microsoft Graph accessPackage into a tagged Omnicit.EntraRBAC.AccessPackage object.

    .DESCRIPTION
    Maps the relevant properties of a Graph access package (returned by Invoke-OERGraphRequest as a
    hashtable) into a [PSCustomObject] tagged Omnicit.EntraRBAC.AccessPackage so Format and Types views
    apply. This private converter is the single owner of the access-package output shape and is used by
    New/Get/Set-OERAccessPackage. IsHidden is coerced to [bool] so a missing value becomes $false rather
    than $null.

    CatalogId in practice comes from the nested .catalog.id, and ONLY when the caller asked Graph to
    expand the catalog navigation property. The v1.0 accessPackage entity has no catalogId property at
    all: its properties are createdDateTime, description, displayName, id, isHidden and modifiedDateTime,
    and catalog is a navigation property that is absent from an unexpanded response. So a bare read, and
    equally the POST and PATCH responses that New- and Set-OERAccessPackage feed in, produce a $null
    CatalogId here -- the converter cannot invent one. Get-OERAccessPackage therefore expands catalog
    unconditionally. The .catalogId source is still read first, because the beta accessPackage entity
    does expose that flat property and a beta-shaped object must keep converting correctly, but it is
    never the source on the v1.0 path this module uses.

    Two more properties are added conditionally, and ONLY when the raw input actually carries the
    matching expanded relationship (checked by key/property presence, not truthiness, so an empty
    expanded array still counts as present): AssignmentPolicies, each element routed through
    ConvertTo-OERAssignmentPolicy -AccessPackageId $InputObject.id, and ResourceRoleScopes, each element
    routed through ConvertTo-OERAccessPackageResourceRole -AccessPackageId $InputObject.id. Both are pure
    converter-to-converter calls (no Graph traffic), which is why ResourceRoleScopes' ResourceDisplayName
    is always $null here: joining a binding's scope.originId to its resource's real display name needs a
    second Graph call (the catalog's resources), which only Get-OERAccessPackageResourceRole makes -- a
    private converter must never perform a transport call of its own. When the raw input does not carry
    the relationship at all (the caller did not ask Graph to expand it), the corresponding property is
    absent from the output entirely, not merely $null, so existing consumers that never expand either
    relationship see the same five-property shape as before. Both are appended AFTER the five original
    properties so member order (and therefore default display and ConvertTo-Json order) stays stable for
    existing consumers.

    .PARAMETER InputObject
    The raw Graph accessPackage object (hashtable or PSObject) to convert into a tagged object.

    .EXAMPLE
    ConvertTo-OERAccessPackage -InputObject $Package
    Converts a single access package into a tagged object.

    .EXAMPLE
    $Packages | ConvertTo-OERAccessPackage
    Converts each raw Graph access package in the pipeline into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $CatalogId = if ($InputObject.catalogId) {
            $InputObject.catalogId
        }
        elseif ($InputObject.catalog) {
            $InputObject.catalog.id
        }
        else {
            $null
        }
        $Out = [PSCustomObject]@{
            Id          = $InputObject.id
            DisplayName = $InputObject.displayName
            Description = $InputObject.description
            CatalogId   = $CatalogId
            IsHidden    = [bool]$InputObject.isHidden
        }

        # Presence, not truthiness: a raw Graph response is a hashtable (ContainsKey), while a
        # hand-built or re-converted input is a PSCustomObject (.PSObject.Properties). An expanded
        # relationship that comes back as an empty array must still count as present.
        $HasAssignmentPolicies = if ($InputObject -is [System.Collections.IDictionary]) {
            $InputObject.ContainsKey('assignmentPolicies')
        } else {
            $null -ne $InputObject.PSObject -and ($InputObject.PSObject.Properties.Name -contains 'assignmentPolicies')
        }
        if ($HasAssignmentPolicies) {
            $AssignmentPolicies = @(foreach ($Policy in @($InputObject.assignmentPolicies)) {
                if ($null -ne $Policy) { ConvertTo-OERAssignmentPolicy -InputObject $Policy -AccessPackageId $InputObject.id }
            })
            Add-Member -InputObject $Out -MemberType NoteProperty -Name 'AssignmentPolicies' -Value $AssignmentPolicies
        }

        $HasResourceRoleScopes = if ($InputObject -is [System.Collections.IDictionary]) {
            $InputObject.ContainsKey('resourceRoleScopes')
        } else {
            $null -ne $InputObject.PSObject -and ($InputObject.PSObject.Properties.Name -contains 'resourceRoleScopes')
        }
        if ($HasResourceRoleScopes) {
            $ResourceRoleScopes = @(foreach ($Scope in @($InputObject.resourceRoleScopes)) {
                if ($null -ne $Scope) { ConvertTo-OERAccessPackageResourceRole -InputObject $Scope -AccessPackageId $InputObject.id }
            })
            Add-Member -InputObject $Out -MemberType NoteProperty -Name 'ResourceRoleScopes' -Value $ResourceRoleScopes
        }

        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
        $Out
    }
}
