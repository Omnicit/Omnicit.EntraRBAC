function Get-OERPipedAccessPackageId {
    <#
    .SYNOPSIS
    Returns the id of an access package piped from Get-OERAccessPackage when -Catalog is in use,
    else $null.

    .DESCRIPTION
    Get-OERAccessPackageAssignmentPolicy and New-OERAccessPackageAssignment bind a piped access
    package by its DisplayName, since the object carries no AccessPackageId. A display name is unique
    only within its catalog, so with -Catalog the name would be looked up in the named catalog and the
    call could land on another catalog's package of the same name. This helper is the single owner of
    that decision: when every one of these holds it returns the piped object's own Id, which the
    caller passes to Resolve-OERAccessPackageId so the id path checks the package against -Catalog
    (AccessPackageNotInCatalog for one of another catalog):

      * -CatalogBound is set (the caller's -Catalog was bound);
      * -Expecting is set (the caller's $MyInvocation.ExpectingInput: the command itself receives
        pipeline input);
      * the piped object is tagged Omnicit.EntraRBAC.AccessPackage;
      * its Id is a GUID (Test-OERGuid);
      * its DisplayName equals -AccessPackage exactly (ordinal), so the value bound is that object's
        name and not one the caller typed.

    In every other case it returns $null and the caller resolves -AccessPackage as it always did.

    .PARAMETER InputObject
    The object the caller received from the pipeline, the caller's $PSItem.

    .PARAMETER AccessPackage
    The caller's bound -AccessPackage value, a display name or an id.

    .PARAMETER CatalogBound
    Set when the caller's -Catalog parameter was bound on the call.

    .PARAMETER Expecting
    The caller's $MyInvocation.ExpectingInput value, true when it receives pipeline input.

    .EXAMPLE
    Get-OERPipedAccessPackageId -InputObject $PSItem -AccessPackage $AccessPackage -CatalogBound:$Bound -Expecting:$MyInvocation.ExpectingInput
    Returns the piped package's id, or $null when the value should be resolved as given.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [string]$AccessPackage,

        [switch]$CatalogBound,

        [switch]$Expecting
    )
    if (-not $CatalogBound -or -not $Expecting -or $null -eq $InputObject) { return $null }
    if (@($InputObject.PSObject.TypeNames) -notcontains 'Omnicit.EntraRBAC.AccessPackage') { return $null }
    $PipedId = [string]$InputObject.Id
    if (-not (Test-OERGuid -Value $PipedId)) { return $null }
    if (-not ([string]$InputObject.DisplayName).Equals($AccessPackage, [System.StringComparison]::Ordinal)) { return $null }
    return $PipedId
}
