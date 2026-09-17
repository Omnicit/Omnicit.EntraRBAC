function Set-OERCatalog {
    <#
    .SYNOPSIS
    Updates an entitlement management catalog.

    .DESCRIPTION
    Patches an access package catalog through Microsoft Graph. Accepts the catalog by -Id or -DisplayName
    (resolved via Resolve-OERCatalogId). -NewDisplayName renames the catalog; -Description updates the
    description; -ExternallyVisible updates isExternallyVisible. Only supplied properties are changed. When
    the Graph PATCH returns 204 No Content (no body) the function completes silently; when the patched
    object is returned it is converted and emitted as a tagged Omnicit.EntraRBAC.Catalog object. At least
    one property must be supplied or a non-terminating NothingToUpdate error is emitted. Supports -WhatIf
    and -Confirm.

    .PARAMETER Id
    The catalog id (GUID) to update.

    .PARAMETER DisplayName
    The catalog display name to resolve and update.

    .PARAMETER NewDisplayName
    New display name to rename the catalog to. Distinct from -DisplayName, which only locates the existing
    catalog.

    .PARAMETER Description
    New description for the catalog.

    .PARAMETER ExternallyVisible
    New value for isExternallyVisible. Pass -ExternallyVisible:$false to clear it.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERCatalog -DisplayName 'CAT-IT-Core' -Description 'Updated core IT access'
    Updates the catalog description.

    .EXAMPLE
    Set-OERCatalog -Id 'cat-guid' -ExternallyVisible:$false
    Hides the catalog from external users.

    .EXAMPLE
    Set-OERCatalog -DisplayName 'CAT-IT-Core' -NewDisplayName 'CAT-IT-Core-EMEA'
    Renames the catalog from CAT-IT-Core to CAT-IT-Core-EMEA.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ById')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [string]$NewDisplayName,
        [string]$Description,
        [switch]$ExternallyVisible,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Body = @{}
        if ($PSBoundParameters.ContainsKey('NewDisplayName'))    { $Body.displayName = $NewDisplayName }
        if ($PSBoundParameters.ContainsKey('Description'))       { $Body.description = $Description }
        if ($PSBoundParameters.ContainsKey('ExternallyVisible')) { $Body.isExternallyVisible = [bool]$ExternallyVisible }

        if ($Body.Count -eq 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Specify at least one property to change (-NewDisplayName, -Description, or -ExternallyVisible).')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject ($DisplayName ? $DisplayName : $Id) `
                -Cmdlet $PSCmdlet
            return
        }

        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
        $CatalogId = $null
        try {
            $CatalogId = if ($PSCmdlet.ParameterSetName -eq 'ByName') { Resolve-OERCatalogId -DisplayName $DisplayName }
            else { Resolve-OERCatalogId -Id $Id }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousCatalogName' -Category InvalidArgument `
                    -TargetObject ($DisplayName ? $DisplayName : $Id) -Cmdlet $PSCmdlet
                return
            }
        }

        if (-not $CatalogId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Catalog not found.')) `
                -ErrorId 'CatalogNotFound' `
                -Category ObjectNotFound `
                -TargetObject ($DisplayName ? $DisplayName : $Id) `
                -Cmdlet $PSCmdlet
            return
        }

        if ($PSCmdlet.ShouldProcess($CatalogId, 'Update entitlement management catalog')) {
            try {
                $Updated = Invoke-OERGraphRequest -Method PATCH `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/catalogs/{0}" -f $CatalogId) `
                    -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($Updated) { ConvertTo-OERCatalog -InputObject $Updated }
        }
    }
}
