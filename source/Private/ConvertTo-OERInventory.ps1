function ConvertTo-OERInventory {
    <#
    .SYNOPSIS
    Assembles the section arrays of a tenant inventory into a tagged Omnicit.EntraRBAC.Inventory object.

    .DESCRIPTION
    Builds the top-level read structure produced by Get-OERInventory: a [PSCustomObject] tagged
    Omnicit.EntraRBAC.Inventory carrying a schema version and one array property per RBAC building
    block (groups, administrativeUnits, catalogs, accessPackages, accessReviews, roleAssignments,
    roleManagementPolicies). The root keys are emitted in the lowercase spelling
    Get-OERStructureSchemaJson declares, so the inventory.json an Export-OERInventory bundle writes
    validates against the schema.json written beside it. PowerShell member lookup is case-insensitive,
    so a consumer reading $Inventory.Groups is unaffected. Each section defaults to an empty array so
    the object always serializes to the full schema. This private helper is the single owner of the
    inventory output shape.

    .PARAMETER Groups
    The projected group entries (schema shape) to place in the Groups section.

    .PARAMETER AdministrativeUnits
    The projected administrative unit entries to place in the AdministrativeUnits section.

    .PARAMETER Catalogs
    The projected catalog entries to place in the Catalogs section.

    .PARAMETER AccessPackages
    The projected access package entries to place in the AccessPackages section.

    .PARAMETER AccessReviews
    The projected access review entries to place in the AccessReviews section.

    .PARAMETER RoleAssignments
    The projected Azure role assignment entries to place in the RoleAssignments section.

    .PARAMETER RoleManagementPolicies
    The projected Azure PIM policy entries to place in the RoleManagementPolicies section.

    .EXAMPLE
    ConvertTo-OERInventory -Groups $Groups -Catalogs $Catalogs
    Returns a tagged inventory object with the supplied Groups and Catalogs sections populated.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Groups = @(),
        [AllowEmptyCollection()][object[]]$AdministrativeUnits = @(),
        [AllowEmptyCollection()][object[]]$Catalogs = @(),
        [AllowEmptyCollection()][object[]]$AccessPackages = @(),
        [AllowEmptyCollection()][object[]]$AccessReviews = @(),
        [AllowEmptyCollection()][object[]]$RoleAssignments = @(),
        [AllowEmptyCollection()][object[]]$RoleManagementPolicies = @()
    )
    # The key spelling is the schema's, not PowerShell's: Get-OERStructureSchemaJson declares these
    # root keys lowercase with additionalProperties:false, and Export-OERInventory writes this object
    # as inventory.json beside that schema. PowerShell member lookup is case-insensitive, so
    # $Inventory.Groups still resolves 'groups' for existing consumers -- and a case-only ETS alias
    # is impossible anyway, so no Update-TypeData entry backs this.
    $Out = [PSCustomObject]@{
        version                = '1.0'
        groups                 = @($Groups)
        administrativeUnits    = @($AdministrativeUnits)
        catalogs               = @($Catalogs)
        accessPackages         = @($AccessPackages)
        accessReviews          = @($AccessReviews)
        roleAssignments        = @($RoleAssignments)
        roleManagementPolicies = @($RoleManagementPolicies)
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
    $Out
}
