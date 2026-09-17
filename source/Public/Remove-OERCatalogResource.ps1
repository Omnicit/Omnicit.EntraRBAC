function Remove-OERCatalogResource {
    <#
    .SYNOPSIS
    Removes a resource from an entitlement management catalog.

    .DESCRIPTION
    Creates an accessPackageResourceRequest (requestType adminRemove) through Microsoft Graph to remove a
    resource from its catalog, identified by the catalog resource id -ResourceId and the containing catalog
    -Catalog (id or display name). The Graph adminRemove contract requires the catalog reference in the
    request body; without it the service rejects the request with an Unauthorized error even for a Global
    Administrator. Removing a resource that is still referenced by an access package will fail at Graph;
    remove the resource-role bindings first. ConfirmImpact is Medium. Supports -WhatIf and -Confirm.

    Omnicit.EntraRBAC.Catalog now exposes CatalogId as an alias of its own Id, so a piped Catalog object
    satisfies BOTH -ResourceId (via its Id alias) and -Catalog (via its CatalogId alias) from the very
    same underlying value. A real catalog resource id is never equal to its containing catalog's id, so
    when the resolved -ResourceId equals the resolved -Catalog this cmdlet refuses with
    ResourceIdEqualsCatalogId rather than submit a wrong-target adminRemove request.

    .PARAMETER ResourceId
    The catalog resource id (accessPackageResource id) to remove.

    .PARAMETER Catalog
    The catalog id or display name that contains the resource. Required by the Graph adminRemove contract;
    resolved to a catalog id via Resolve-OERCatalogId (GUIDs are accepted verbatim). Accepts pipeline
    input by the CatalogId property name: a piped resource carrying its own CatalogId (for example from
    Get-OERCatalogResource) or a piped Omnicit.EntraRBAC.Catalog object (which now exposes CatalogId as
    an alias of Id) both bind automatically.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERCatalogResource -ResourceId '22222222-2222-2222-2222-222222222222' -Catalog 'CAT-IT-Core'
    Removes the catalog resource after confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$ResourceId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('CatalogId')]
        [string]$Catalog,

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

        # Omnicit.EntraRBAC.Catalog exposes CatalogId as an alias of its own Id, so a piped Catalog
        # object satisfies BOTH -ResourceId (via its Id alias) and -Catalog (via its CatalogId alias)
        # from the same underlying value. A real catalog resource id is never equal to its containing
        # catalog's id, so this combination means the caller piped the wrong kind of object rather than
        # supplying a genuine resource id -- refuse it before it becomes a wrong-target adminRemove POST.
        if ($ResourceId -eq $CatalogId) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "The resolved resource id '$ResourceId' equals the resolved catalog id '$CatalogId'. " +
                    'A catalog resource id is never equal to its containing catalog id -- this usually means ' +
                    'a Catalog object was piped in without an explicit -ResourceId. Supply -ResourceId explicitly.')) `
                -ErrorId 'ResourceIdEqualsCatalogId' -Category InvalidArgument -TargetObject $ResourceId -Cmdlet $PSCmdlet
            return
        }

        $Body = @{
            requestType = 'adminRemove'
            resource    = @{ id = $ResourceId }
            catalog     = @{ id = $CatalogId }
        }
        if ($PSCmdlet.ShouldProcess($ResourceId, 'Remove resource from catalog')) {
            try {
                $null = Invoke-OERGraphRequest -Method POST `
                    -Uri 'v1.0/identityGovernance/entitlementManagement/resourceRequests' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
