function Remove-OERAccessPackage {
    <#
    .SYNOPSIS
    Deletes an access package.

    .DESCRIPTION
    Deletes an access package through Microsoft Graph. Accepts the package by -Id or -DisplayName
    (resolved via Resolve-OERAccessPackageId). High-impact: emits an explicit warning and defaults to
    ConfirmImpact High. Deleting a package with active assignments will fail at Graph; remove assignments
    first. Supports -WhatIf and -Confirm.

    .PARAMETER Id
    The access package id (GUID) to delete. This value is used as given, with no existence check:
    the DELETE that follows fails loudly on its own when the id is wrong. Passing the same GUID to
    -DisplayName instead does check it first, and reports AccessPackageNotFound before any write.

    .PARAMETER DisplayName
    The access package display name to resolve and delete.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERAccessPackage -DisplayName 'AP-Sales'
    Deletes the access package after confirmation.

    .EXAMPLE
    Remove-OERAccessPackage -Id '00000000-0000-0000-0000-000000000001' -Confirm:$false
    Deletes the access package by id without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

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
            $PackageId = if ($PSCmdlet.ParameterSetName -eq 'ByName') { Resolve-OERAccessPackageId -DisplayName $DisplayName }
            else { Resolve-OERAccessPackageId -Id $Id }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousAccessPackageName' -Category InvalidArgument `
                    -TargetObject $(if ($Id) { $Id } else { $DisplayName }) -Cmdlet $PSCmdlet
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
                -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound `
                -TargetObject $(if ($Id) { $Id } else { $DisplayName }) -Cmdlet $PSCmdlet
            return
        }

        if ($PSCmdlet.ShouldProcess($PackageId, 'Delete access package')) {
            Write-Warning "Deleting access package '$PackageId'. This is irreversible."
            try {
                $null = Invoke-OERGraphRequest -Method DELETE `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}" -f $PackageId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
