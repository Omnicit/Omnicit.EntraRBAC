function Remove-OERCatalog {
    <#
    .SYNOPSIS
    Deletes an entitlement management catalog.

    .DESCRIPTION
    Deletes an access package catalog through Microsoft Graph. Accepts the catalog by -Id or -DisplayName
    (resolved via Resolve-OERCatalogId). This is a high-impact operation: it emits an explicit warning
    before the confirmation prompt (so it also appears under -WhatIf) and defaults to ConfirmImpact
    High. Deleting a catalog that still contains access packages will fail at Graph; remove the
    access packages first. Supports -WhatIf and -Confirm.

    .PARAMETER Id
    The catalog id (GUID) to delete.

    .PARAMETER DisplayName
    The catalog display name to resolve and delete.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERCatalog -DisplayName 'CAT-IT-Core'
    Deletes the catalog after confirmation.

    .EXAMPLE
    Remove-OERCatalog -Id '00000000-0000-0000-0000-000000000001' -Confirm:$false
    Deletes the catalog by id without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # Refuse an ambiguous display name loudly, and surface any other throw as itself. Only a
        # $null return (a display name that matched nothing) reaches the not-found branch.
        $CatalogId = $null
        try {
            $CatalogId = if ($PSCmdlet.ParameterSetName -eq 'ByName') { Resolve-OERCatalogId -DisplayName $DisplayName }
            # For -Id the GUID is trusted and passed through; Graph validates existence (404) on DELETE.
            else { Resolve-OERCatalogId -Id $Id }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousCatalogName' -Category InvalidArgument `
                    -TargetObject $(if ($Id) { $Id } else { $DisplayName }) -Cmdlet $PSCmdlet
                return
            }
            # Anything else the resolver raised -- a 403, an exhausted 429, a 5xx -- is not evidence that
            # no such catalog exists: surface it as itself, never as the not-found below.
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if (-not $CatalogId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Catalog not found.')) `
                -ErrorId 'CatalogNotFound' -Category ObjectNotFound `
                -TargetObject $(if ($Id) { $Id } else { $DisplayName }) -Cmdlet $PSCmdlet
            return
        }

        # This warning stands ahead of ShouldProcess so -WhatIf and the -Confirm prompt show it.
        Write-Warning "Deleting catalog '$CatalogId'. This is irreversible and removes the catalog container."
        if ($PSCmdlet.ShouldProcess($CatalogId, 'Delete entitlement management catalog')) {
            try {
                $null = Invoke-OERGraphRequest -Method DELETE `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/catalogs/{0}" -f $CatalogId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
