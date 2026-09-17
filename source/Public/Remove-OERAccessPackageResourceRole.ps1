function Remove-OERAccessPackageResourceRole {
    <#
    .SYNOPSIS
    Removes a resource role binding from an access package.

    .DESCRIPTION
    Deletes an accessPackageResourceRoleScope through Microsoft Graph, unbinding a resource role from an
    access package. The package is given by -AccessPackage (id or display name) and the binding by
    -ResourceRoleScopeId. ConfirmImpact is Medium. Supports -WhatIf and -Confirm.

    .PARAMETER AccessPackage
    The access package id or display name the binding belongs to. Accepts pipeline input by property
    name via the AccessPackageId alias, so Get-OERAccessPackageResourceRole | Remove-OERAccessPackageResourceRole
    binds directly.

    .PARAMETER ResourceRoleScopeId
    The id of the resource role scope to remove. Accepts pipeline input by property name, so
    Get-OERAccessPackageResourceRole | Remove-OERAccessPackageResourceRole binds directly.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-guid'
    Unbinds the resource role from the access package.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessPackageId')]
        [string]$AccessPackage,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$ResourceRoleScopeId,

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
            Write-CmdletError -Message ([System.Exception]::new("Access package '$AccessPackage' not found.")) `
                -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound -TargetObject $AccessPackage -Cmdlet $PSCmdlet
            return
        }
        if ($PSCmdlet.ShouldProcess($ResourceRoleScopeId, "Remove resource role binding from $PackageId")) {
            try {
                $null = Invoke-OERGraphRequest -Method DELETE `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}/resourceRoleScopes/{1}" -f $PackageId, $ResourceRoleScopeId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
