function ConvertTo-OERInventory {
    <#
    .SYNOPSIS
    Assembles the section arrays of a tenant inventory into a tagged Omnicit.EntraRBAC.Inventory object.

    .DESCRIPTION
    Builds the top-level read structure produced by Get-OERInventory: a [PSCustomObject] tagged
    Omnicit.EntraRBAC.Inventory carrying a schema version, the tenant it was read from (tenantId,
    directly after the version, only when one is given as a GUID) and one array property per RBAC
    building block, in the order the apply engine dispatches them: groups, administrativeUnits,
    catalogs, accessPackages, accessReviews, directoryRoleManagementPolicies,
    directoryRoleAssignments, roleAssignments and roleManagementPolicies -- every section the schema
    declares. The root keys are emitted in the lowercase spelling Get-OERStructureSchemaJson
    declares, so the inventory.json an Export-OERInventory bundle writes validates against the
    schema.json written beside it. PowerShell member lookup is case-insensitive, so a consumer
    reading $Inventory.Groups is unaffected. Each section defaults to an empty array so the object
    always serializes every section it carries. This private helper is the single owner of the
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

    .PARAMETER DirectoryRoleManagementPolicies
    The projected Microsoft Entra directory role PIM policy entries to place in the
    DirectoryRoleManagementPolicies section.

    .PARAMETER DirectoryRoleAssignments
    The projected Microsoft Entra directory role eligible and active assignment entries to place in
    the DirectoryRoleAssignments section.

    .PARAMETER RoleAssignments
    The projected Azure role assignment entries to place in the RoleAssignments section.

    .PARAMETER RoleManagementPolicies
    The projected Azure PIM policy entries to place in the RoleManagementPolicies section.

    .PARAMETER TenantId
    The tenant ID the inventory names, from Get-OERInventoryTenantId. Emitted as the top-level
    tenantId, directly after version, only when it is a GUID (Test-OERGuid); otherwise the key is left
    out and the document carries no tenant check.

    .EXAMPLE
    ConvertTo-OERInventory -Groups $Groups -Catalogs $Catalogs
    Returns a tagged inventory object with the supplied Groups and Catalogs sections populated.

    .EXAMPLE
    ConvertTo-OERInventory -TenantId (Get-OERInventoryTenantId) -Groups $Groups
    Returns a tagged inventory object that names the tenant the session's Graph token was issued for,
    when it is a GUID, directly after its version.

    .EXAMPLE
    ConvertTo-OERInventory -DirectoryRoleManagementPolicies $Policies -DirectoryRoleAssignments $Assignments
    Returns a tagged inventory object carrying the two Microsoft Entra directory role sections.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Groups = @(),
        [AllowEmptyCollection()][object[]]$AdministrativeUnits = @(),
        [AllowEmptyCollection()][object[]]$Catalogs = @(),
        [AllowEmptyCollection()][object[]]$AccessPackages = @(),
        [AllowEmptyCollection()][object[]]$AccessReviews = @(),
        [AllowEmptyCollection()][object[]]$DirectoryRoleManagementPolicies = @(),
        [AllowEmptyCollection()][object[]]$DirectoryRoleAssignments = @(),
        [AllowEmptyCollection()][object[]]$RoleAssignments = @(),
        [AllowEmptyCollection()][object[]]$RoleManagementPolicies = @(),
        [string]$TenantId
    )
    # The key spelling is the schema's, not PowerShell's: Get-OERStructureSchemaJson declares these
    # root keys lowercase with additionalProperties:false, and Export-OERInventory writes this object
    # as inventory.json beside that schema. PowerShell member lookup is case-insensitive, so
    # $Inventory.Groups still resolves 'groups' for existing consumers -- and a case-only ETS alias
    # is impossible anyway, so no Update-TypeData entry backs this.
    #
    # tenantId (BL-88, A14) sits directly after version and is written only when it is a GUID: a
    # document with no tenantId is applied with no tenant check, and a value that is not a GUID would
    # be refused by the validator, so none is ever written. The nine sections keep their order.
    $Root = [ordered]@{ version = '1.0' }
    if (Test-OERGuid -Value $TenantId) { $Root.tenantId = $TenantId }
    $Root.groups                          = @($Groups)
    $Root.administrativeUnits             = @($AdministrativeUnits)
    $Root.catalogs                        = @($Catalogs)
    $Root.accessPackages                  = @($AccessPackages)
    $Root.accessReviews                   = @($AccessReviews)
    $Root.directoryRoleManagementPolicies = @($DirectoryRoleManagementPolicies)
    $Root.directoryRoleAssignments        = @($DirectoryRoleAssignments)
    $Root.roleAssignments                 = @($RoleAssignments)
    $Root.roleManagementPolicies          = @($RoleManagementPolicies)
    $Out = [PSCustomObject]$Root
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
    $Out
}
