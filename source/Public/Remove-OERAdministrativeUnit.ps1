function Remove-OERAdministrativeUnit {
    <#
    .SYNOPSIS
    Deletes an Entra ID administrative unit. High-impact: prompts for confirmation by default.

    .DESCRIPTION
    Permanently deletes an administrative unit identified by -AdministrativeUnit through Microsoft Graph.
    Deleting a unit is a high-impact, hard-to-reverse operation, so the command declares
    ConfirmImpact = High (it prompts unless -Confirm:$false is passed) and emits an explicit warning before
    the delete. The warning is written BEFORE the confirmation prompt, so it also appears under -WhatIf
    and under -Confirm:$false. Deleting the unit does not delete its member objects; it removes the unit
    and any role assignments scoped to it. A unit that cannot be resolved produces a non-terminating
    AdministrativeUnitNotFound error. Supports -WhatIf and -Confirm.

    .PARAMETER AdministrativeUnit
    The administrative unit to delete, given as either its object id (GUID) or its display name. Binds
    from the pipeline by property name, and still accepts the historical -Id, -AdministrativeUnitId and
    -DisplayName parameter names as aliases, so a name-only or id-only object pipes in unchanged. This is
    the cmdlet's only mandatory parameter, so it also binds positionally.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERAdministrativeUnit -AdministrativeUnit 'au_obsolete' -Confirm:$false
    Deletes the named administrative unit without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # AdministrativeUnitId precedes Id/DisplayName so a piped AdministrativeUnitMember object binds
        # the parent unit's id, not the member's own Id/DisplayName, during ValueFromPipelineByPropertyName
        # alias resolution.
        [Alias('AdministrativeUnitId', 'Id', 'DisplayName')]
        [string]$AdministrativeUnit,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # A throw here is a transport/permission/throttling failure, NOT a missing unit. Reporting it as
        # AdministrativeUnitNotFound would send the operator hunting for a unit that exists, so the two
        # outcomes are reported separately (mirrors Get-OERAccessReviewInstance's definition handling).
        # Resolve-OERAdministrativeUnitId has no GUID short-circuit of its own, so the dispatch happens
        # here: a canonical GUID goes to -Id (no Graph call), anything else goes to -DisplayName.
        $AuId = try {
            if (Test-OERGuid -Value $AdministrativeUnit) {
                Resolve-OERAdministrativeUnitId -Id $AdministrativeUnit
            } else {
                Resolve-OERAdministrativeUnitId -DisplayName $AdministrativeUnit
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up administrative unit '$AdministrativeUnit': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'AdministrativeUnitResolveFailed' `
                -Category NotSpecified `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }
        if (-not $AuId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No administrative unit found to delete for the supplied id/display name.')) `
                -ErrorId 'AdministrativeUnitNotFound' `
                -Category ObjectNotFound `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }

        # MEASURED LIVE: this warning sits AHEAD of ShouldProcess on purpose. Emitted after it, it
        # printed only once the operator had already answered the ConfirmImpact = High prompt, and never
        # at all under -WhatIf -- a warning the operator sees only after committing to the delete is not
        # a guard. Do not move it back.
        Write-Warning "Deleting Entra ID administrative unit '$AuId'. This is a high-impact, hard-to-reverse operation."
        if ($PSCmdlet.ShouldProcess($AuId, 'Permanently delete Entra ID administrative unit')) {
            try {
                Invoke-OERGraphRequest -Method DELETE -Uri ("v1.0/directory/administrativeUnits/{0}" -f $AuId) | Out-Null
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
