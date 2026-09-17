function New-OERCatalog {
    <#
    .SYNOPSIS
    Creates an entitlement management catalog, idempotently.

    .DESCRIPTION
    Creates an access package catalog through Microsoft Graph. The display name is supplied directly
    with -DisplayName, or composed from -Org and -Scope through the Resolve-OERName naming engine using
    -Template (default 'CAT-{org}-{scope}'). -Description sets the catalog description.
    -ExternallyVisible makes the catalog's access packages requestable by users outside the directory.

    The command is idempotent: when a catalog with the resolved display name already exists, the existing
    catalog is returned and nothing is created. Output is a tagged Omnicit.EntraRBAC.Catalog object.
    Supports -WhatIf and -Confirm.

    .PARAMETER DisplayName
    The exact display name of the catalog to create. Used by the ByName parameter set.

    .PARAMETER Org
    The org token used to compose the display name from -Template. Used by the ByTemplate parameter set.

    .PARAMETER Scope
    The scope token used to compose the display name from -Template. Used by the ByTemplate parameter set.

    .PARAMETER Template
    The Resolve-OERName template used with -Org/-Scope. Defaults to 'CAT-{org}-{scope}'.

    .PARAMETER Description
    Optional description stored on the catalog.

    .PARAMETER ExternallyVisible
    Set the catalog's isExternallyVisible to true so its access packages can be requested by external users.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERCatalog -DisplayName 'CAT-IT-Core' -Description 'Core IT access'
    Creates the catalog, or returns it if it already exists.

    .EXAMPLE
    New-OERCatalog -Org 'IT' -Scope 'Core'
    Composes the name 'CAT-IT-Core' from the default template and creates the catalog.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [Parameter(ParameterSetName = 'ByTemplate', Mandatory)]
        [string]$Org,

        [Parameter(ParameterSetName = 'ByTemplate', Mandatory)]
        [string]$Scope,

        [Parameter(ParameterSetName = 'ByTemplate')]
        [string]$Template = 'CAT-{org}-{scope}',

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
        $ResolvedName = if ($PSCmdlet.ParameterSetName -eq 'ByTemplate') {
            try {
                Resolve-OERName -Template $Template -Tokens @{ org = $Org; scope = $Scope }
            } catch {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Failed to resolve a catalog name: $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'NameResolutionFailed' `
                    -Category InvalidArgument `
                    -TargetObject $Org `
                    -Cmdlet $PSCmdlet
                return
            }
        } else {
            $DisplayName
        }

        # A throw here is a transport/permission/throttling failure during the idempotency pre-check,
        # NOT evidence the catalog is missing. Falling through to the create would attempt to create
        # a duplicate catalog against a tenant that is merely throttled, so report the failure and
        # stop instead of proceeding to the create below.
        $ExistingId = try {
            Resolve-OERCatalogId -DisplayName $ResolvedName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up catalog '$ResolvedName': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'CatalogResolveFailed' `
                -Category NotSpecified `
                -TargetObject $ResolvedName `
                -Cmdlet $PSCmdlet
            return
        }
        if ($ExistingId) {
            try {
                $Existing = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/catalogs/{0}" -f $ExistingId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            Write-Verbose "[New-OERCatalog] Catalog '$ResolvedName' already exists ($ExistingId); returning existing."
            ConvertTo-OERCatalog -InputObject $Existing
            return
        }

        $Body = @{ displayName = $ResolvedName; catalogType = 'userManaged' }
        if ($Description)       { $Body.description = $Description }
        if ($ExternallyVisible) { $Body.isExternallyVisible = $true }

        if ($PSCmdlet.ShouldProcess($ResolvedName, 'Create entitlement management catalog')) {
            try {
                $Created = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/identityGovernance/entitlementManagement/catalogs' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERCatalog -InputObject $Created
        }
    }
}
