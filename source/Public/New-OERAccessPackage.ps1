function New-OERAccessPackage {
    <#
    .SYNOPSIS
    Creates an access package inside an entitlement management catalog, idempotently.

    .DESCRIPTION
    Creates an access package through Microsoft Graph. The display name is supplied directly with
    -DisplayName, or composed from -Name (and optional -Prefix) through Resolve-OERName using -Template.
    -Catalog selects the parent catalog (id or display name, resolved via Resolve-OERCatalogId).
    -Description sets the description; -Hidden sets isHidden. The command is idempotent: when a package
    with the resolved display name already exists it is returned and nothing is created. Output is a tagged
    Omnicit.EntraRBAC.AccessPackage object. Supports -WhatIf and -Confirm.

    Both output paths return a populated CatalogId. The v1.0 accessPackage entity has no catalogId
    property of its own -- it exposes only createdDateTime, description, displayName, id, isHidden and
    modifiedDateTime -- and Graph does not echo the catalog navigation property on a POST, so the
    create response alone cannot carry it. The already-exists read therefore uses $expand=catalog, and
    the create path follows its POST with one confirmation read of the same shape, so a created package
    and the same package read back through Get-OERAccessPackage are identical. That confirmation read
    is best effort: if it fails or returns nothing the create response is emitted instead (CatalogId
    $null) and a verbose message says so, because the package was already created and a failed
    confirmation must never be reported as a failed creation.

    .PARAMETER DisplayName
    The exact display name of the access package to create. Used by the ByName parameter set.

    .PARAMETER Name
    The name token used to compose the display name from -Template. Used by the ByTemplate parameter set.

    .PARAMETER Template
    The Resolve-OERName template used with -Name/-Prefix. Defaults to '{name}'.

    .PARAMETER Prefix
    Prefix token for -Template, used when the template contains a {prefix} placeholder.

    .PARAMETER Catalog
    The catalog id or catalog GUID the access package is created in. Accepts pipeline input by property
    name: a piped Omnicit.EntraRBAC.Catalog object binds via its Id or CatalogId property.

    .PARAMETER Description
    Optional description stored on the access package.

    .PARAMETER Hidden
    Set isHidden so the package is not visible in the My Access portal unless directly assigned.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Description 'Sales tooling'
    Creates the access package, or returns it if it already exists.

    .EXAMPLE
    New-OERAccessPackage -Name 'Sales' -Catalog 'CAT-IT-Core'
    Composes the name 'Sales' from the default template '{name}' and creates the access package.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [Parameter(ParameterSetName = 'ByTemplate', Mandatory)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByTemplate')]
        [string]$Template = '{name}',

        [Parameter(ParameterSetName = 'ByTemplate')]
        [string]$Prefix,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'CatalogId')]
        [string]$Catalog,

        [string]$Description,
        [switch]$Hidden,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # A throw here is a transport/permission/throttling failure during the catalog lookup, NOT
        # evidence the catalog is missing. Falling through to CatalogNotFound would misreport a
        # catalog that exists, so report the resolve failure and stop instead of proceeding -- the
        # access package is NOT created either way.
        $CatalogId = try {
            Resolve-OERCatalogId -DisplayName $Catalog
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up catalog '$Catalog': $($PSItem.Exception.Message) The access package was NOT created.")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'CatalogResolveFailed' `
                -Category NotSpecified `
                -TargetObject $Catalog `
                -Cmdlet $PSCmdlet
            return
        }
        if (-not $CatalogId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Catalog '$Catalog' not found.")) `
                -ErrorId 'CatalogNotFound' -Category ObjectNotFound -TargetObject $Catalog -Cmdlet $PSCmdlet
            return
        }

        $ResolvedName = if ($PSCmdlet.ParameterSetName -eq 'ByTemplate') {
            $Tokens = @{ name = $Name }
            if ($PSBoundParameters.ContainsKey('Prefix')) { $Tokens.prefix = $Prefix }
            try {
                Resolve-OERName -Template $Template -Tokens $Tokens
            } catch {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Failed to resolve an access package name: $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception -ErrorId 'NameResolutionFailed' `
                    -Category InvalidArgument -TargetObject $Name -Cmdlet $PSCmdlet
                return
            }
        } else {
            $DisplayName
        }

        # A throw here is a transport/permission/throttling failure during the idempotency pre-check,
        # NOT evidence the access package is missing. Falling through to the create would attempt to
        # create a duplicate package against a tenant that is merely throttled, so report the
        # failure and stop instead of proceeding to the create below.
        $ExistingId = try {
            Resolve-OERAccessPackageId -DisplayName $ResolvedName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up access package '$ResolvedName': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'AccessPackageResolveFailed' `
                -Category NotSpecified `
                -TargetObject $ResolvedName `
                -Cmdlet $PSCmdlet
            return
        }
        if ($ExistingId) {
            # This branch is a READ, so it uses the same $expand=catalog shape as Get-OERAccessPackage:
            # the v1.0 accessPackage entity has no catalogId property and catalog is a navigation
            # property, so a bare GET here would return the existing package with a $null CatalogId
            # while Get-OERAccessPackage returned the same package with it populated.
            try {
                $Existing = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?`$expand=catalog" -f $ExistingId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            Write-Verbose "[New-OERAccessPackage] Package '$ResolvedName' already exists ($ExistingId); returning existing."
            ConvertTo-OERAccessPackage -InputObject $Existing
            return
        }

        $Body = @{ displayName = $ResolvedName; catalog = @{ id = $CatalogId } }
        if ($Description) { $Body.description = $Description }
        if ($Hidden)      { $Body.isHidden = $true }

        if ($PSCmdlet.ShouldProcess($ResolvedName, 'Create access package')) {
            try {
                $Created = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/identityGovernance/entitlementManagement/accessPackages' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            # Graph answers the POST with the accessPackage ENTITY, whose v1.0 properties are only
            # createdDateTime, description, displayName, id, isHidden and modifiedDateTime. catalog is
            # a navigation property and is NOT echoed, so converting the create response directly
            # yields a $null CatalogId and create output disagrees with read output on the very same
            # package. Re-read through the same $expand=catalog shape the read path uses so the two
            # agree BY CONSTRUCTION. The catalog id is known locally ($CatalogId), but hand-composing
            # the value into the create response is exactly the pattern that made create and read
            # disagree on Add-OERAccessPackageResourceRole; the converter stays the single owner of
            # the shape and is fed a real Graph response instead.
            $Confirmed = $null
            if ($Created.id) {
                try {
                    $Confirmed = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?`$expand=catalog" -f $Created.id)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    Write-Verbose "[New-OERAccessPackage] Could not re-read the created access package '$($Created.id)' to populate CatalogId: $($PSItem.Exception.Message)"
                }
            }
            # The access package WAS created -- a failed or empty confirmation read must never be
            # reported as a failure. Fall back to the create response, on which CatalogId stays $null.
            if ($Confirmed) {
                ConvertTo-OERAccessPackage -InputObject $Confirmed
            } else {
                Write-Verbose "[New-OERAccessPackage] Falling back to the create response for '$ResolvedName'; CatalogId will be `$null."
                ConvertTo-OERAccessPackage -InputObject $Created
            }
        }
    }
}
