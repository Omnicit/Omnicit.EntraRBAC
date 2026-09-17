function Set-OERAccessPackage {
    <#
    .SYNOPSIS
    Updates an access package.

    .DESCRIPTION
    Patches an access package through Microsoft Graph. Accepts the package by -Id or -DisplayName
    (resolved via Resolve-OERAccessPackageId). -NewDisplayName renames the package; -Description updates
    the description; -Hidden updates isHidden. Only supplied properties are changed. When the Graph PATCH
    returns 204 No Content (no body) the function completes silently; when the patched object is returned it
    is converted and emitted as a tagged Omnicit.EntraRBAC.AccessPackage object. At least one property must
    be supplied or a non-terminating NothingToUpdate error is emitted. Supports -WhatIf and -Confirm.

    When an object IS emitted its CatalogId is populated. The v1.0 accessPackage entity has no
    catalogId property -- only createdDateTime, description, displayName, id, isHidden and
    modifiedDateTime -- and Graph does not echo the catalog navigation property on a PATCH, so the
    update response alone cannot carry it. A successful PATCH that returned a body is therefore
    followed by one confirmation read using $expand=catalog, the same shape Get-OERAccessPackage uses,
    so an updated package and the same package read back are identical. The 204 No Content behaviour
    is unchanged: no body still means no output and no confirmation read. The confirmation read is
    best effort -- if it fails the PATCH response is emitted instead (CatalogId $null) with a verbose
    message, because the package was already updated and a failed confirmation must never be reported
    as a failed update.

    .PARAMETER Id
    The access package id (GUID) to update. This value is used as given, with no existence check:
    the PATCH that follows fails loudly on its own when the id is wrong. Passing the same GUID to
    -DisplayName instead does check it first, and reports AccessPackageNotFound before any write.

    .PARAMETER DisplayName
    The access package display name to resolve and update.

    .PARAMETER NewDisplayName
    New display name to rename the access package to. Distinct from -DisplayName, which only locates the
    existing access package.

    .PARAMETER Description
    New description for the access package.

    .PARAMETER Hidden
    New value for isHidden. Pass -Hidden:$false to unhide.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERAccessPackage -DisplayName 'AP-Sales' -Description 'Updated sales tooling access'
    Updates the description of the access package.

    .EXAMPLE
    Set-OERAccessPackage -Id 'ap-guid' -Hidden:$false
    Unhides the access package in the My Access portal.

    .EXAMPLE
    Set-OERAccessPackage -DisplayName 'AP-Sales' -NewDisplayName 'AP-Sales-EMEA'
    Renames the access package from AP-Sales to AP-Sales-EMEA.
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
        [switch]$Hidden,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Body = @{}
        if ($PSBoundParameters.ContainsKey('NewDisplayName')) { $Body.displayName = $NewDisplayName }
        if ($PSBoundParameters.ContainsKey('Description'))    { $Body.description = $Description }
        if ($PSBoundParameters.ContainsKey('Hidden'))         { $Body.isHidden = [bool]$Hidden }

        if ($Body.Count -eq 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Specify at least one property to change (-NewDisplayName, -Description, or -Hidden).')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject ($DisplayName ? $DisplayName : $Id) `
                -Cmdlet $PSCmdlet
            return
        }

        # Refuse an ambiguous display name loudly, and surface any other throw as itself. Only a
        # $null return (a display name that matched nothing) reaches the not-found branch.
        $PackageId = $null
        try {
            $PackageId = if ($PSCmdlet.ParameterSetName -eq 'ByName') { Resolve-OERAccessPackageId -DisplayName $DisplayName }
            else { Resolve-OERAccessPackageId -Id $Id }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousAccessPackageName' -Category InvalidArgument `
                    -TargetObject ($DisplayName ? $DisplayName : $Id) -Cmdlet $PSCmdlet
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
                -Message ([System.Exception]::new('Access package not found.')) `
                -ErrorId 'AccessPackageNotFound' `
                -Category ObjectNotFound `
                -TargetObject ($DisplayName ? $DisplayName : $Id) `
                -Cmdlet $PSCmdlet
            return
        }

        if ($PSCmdlet.ShouldProcess($PackageId, 'Update access package')) {
            try {
                $Updated = Invoke-OERGraphRequest -Method PATCH `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}" -f $PackageId) `
                    -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            # Graph answers the PATCH with the accessPackage ENTITY, or with 204 No Content. The v1.0
            # entity has no catalogId property and does not echo the catalog navigation property, so
            # converting the PATCH response directly yields a $null CatalogId and update output
            # disagrees with read output on the very same package. When the PATCH DID return a body,
            # re-read through the same $expand=catalog shape the read path uses so the two agree.
            #
            # The 204 No Content contract above is deliberately preserved: when Graph returns no body
            # this function still completes silently and emits nothing. The confirmation read only
            # enriches an object that was going to be emitted anyway -- it never turns a silent update
            # into an emitting one, so no existing pipeline changes shape.
            if ($Updated) {
                $Confirmed = $null
                try {
                    $Confirmed = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?`$expand=catalog" -f $PackageId)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    Write-Verbose "[Set-OERAccessPackage] Could not re-read access package '$PackageId' to populate CatalogId: $($PSItem.Exception.Message)"
                }
                # The access package WAS updated -- a failed or empty confirmation read must never be
                # reported as a failure. Fall back to the PATCH response, on which CatalogId is $null.
                if ($Confirmed) {
                    ConvertTo-OERAccessPackage -InputObject $Confirmed
                } else {
                    Write-Verbose "[Set-OERAccessPackage] Falling back to the PATCH response for '$PackageId'; CatalogId will be `$null."
                    ConvertTo-OERAccessPackage -InputObject $Updated
                }
            }
        }
    }
}
