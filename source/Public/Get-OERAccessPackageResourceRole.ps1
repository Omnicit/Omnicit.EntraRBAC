function Get-OERAccessPackageResourceRole {
    <#
    .SYNOPSIS
    Lists the resource role bindings configured on an access package.

    .DESCRIPTION
    Reads an access package's resourceRoleScopes through Microsoft Graph
    (accessPackages/{id}?$expand=resourceRoleScopes($expand=role,scope),catalog) via
    Invoke-OERGraphRequest and returns one tagged Omnicit.EntraRBAC.AccessPackageResourceRole object per
    binding. The access package is given by -AccessPackage (display name or GUID, resolved via
    Resolve-OERAccessPackageId) and binds from the pipeline by property name so Get-OERAccessPackage
    pipes straight in. The output exposes ResourceRoleScopeId so it pipes into
    Remove-OERAccessPackageResourceRole. An access package with no bindings returns nothing (not an
    error).

    Each binding's scope carries only a scope LABEL (commonly the literal string 'Root' for a
    root-scoped resource) and the resource's originId -- never the resource's own display name. To
    report the real resource name, this cmdlet resolves the package's catalog and reads that catalog's
    resources once, then joins every binding to its resource by originId, stamping the result as
    ResourceDisplayName. That join is best-effort: when the catalog cannot be resolved or its resources
    cannot be read, a verbose message is written and every binding is still returned with
    ResourceDisplayName left $null -- a reporting nicety never fails the read.

    .PARAMETER AccessPackage
    The access package display name or GUID whose resource role bindings are listed.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales'
    Lists the resource role bindings on the AP-Sales access package.

    .EXAMPLE
    Get-OERAccessPackage -DisplayName 'AP-Sales' | Get-OERAccessPackageResourceRole
    Pipes an access package into the resource-role read.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$AccessPackage,

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
        $PackageId = $null
        try {
            $PackageId = Resolve-OERAccessPackageId -DisplayName $AccessPackage
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousAccessPackageName' -Category InvalidArgument `
                    -TargetObject $AccessPackage -Cmdlet $PSCmdlet
                return
            }
            # Anything else the resolver raised is surfaced AS ITSELF, never folded into the
            # not-found branch below. Its own AccessPackageNotFound already names the id and why it
            # may be wrong, and a 403 or an exhausted 429 from its existence read is not evidence
            # that no such package exists -- reporting either as not found is the failed-read-as-an-
            # empty-fact defect of issue #76. A display name matching nothing still returns $null
            # rather than throwing, so the not-found branch below is unchanged for it.
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if (-not $PackageId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Access package '$AccessPackage' not found.")) `
                -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound -TargetObject $AccessPackage -Cmdlet $PSCmdlet
            return
        }
        # Deliberately NOT narrowed with a nested $select=id: this endpoint has returned a 400 (ASP.NET
        # Runtime Error) on an unproven query shape before, and $expand=catalog without $select is the
        # shape already proven live by Resolve-OERAccessReviewScopeTarget.ps1 -- do not "optimize" this
        # back to catalog($select=id) without live evidence that Graph accepts it on this endpoint.
        $Uri = "v1.0/identityGovernance/entitlementManagement/accessPackages/$PackageId`?`$expand=resourceRoleScopes(`$expand=role,scope),catalog"
        try {
            $Response = Invoke-OERGraphRequest -Uri $Uri
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        # Best-effort join: resourceRoleScopes never carries the resource's own display name (only a
        # scope label such as 'Root'), so read the package's catalog resources once and map
        # originId -> DisplayName. Never let this reporting nicety fail the read.
        $ResourceNameMap = @{}
        $CatalogId = (ConvertTo-OERAccessPackage -InputObject $Response).CatalogId
        if ($CatalogId) {
            try {
                foreach ($CatalogResource in @(Get-OERCatalogResource -Catalog $CatalogId -ErrorAction Stop)) {
                    if ($CatalogResource.OriginId) {
                        $ResourceNameMap[[string]$CatalogResource.OriginId] = [string]$CatalogResource.DisplayName
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Verbose "Could not read catalog resources for access package '$PackageId'; ResourceDisplayName will be `$null on every binding: $($PSItem.Exception.Message)"
            }
        } else {
            Write-Verbose "Access package '$PackageId' has no resolvable catalog id; ResourceDisplayName will be `$null on every binding."
        }

        foreach ($Item in @($Response.resourceRoleScopes)) {
            if ($null -eq $Item) { continue }
            $ItemResourceDisplayName = $null
            if ($Item.scope.originId -and $ResourceNameMap.ContainsKey([string]$Item.scope.originId)) {
                $ItemResourceDisplayName = $ResourceNameMap[[string]$Item.scope.originId]
            }
            ConvertTo-OERAccessPackageResourceRole -InputObject $Item -AccessPackageId $PackageId `
                -ResourceDisplayName $ItemResourceDisplayName
        }
    }
}
