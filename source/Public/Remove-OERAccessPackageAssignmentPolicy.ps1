function Remove-OERAccessPackageAssignmentPolicy {
    <#
    .SYNOPSIS
    Deletes an access package assignment policy.

    .DESCRIPTION
    Deletes an assignment policy through Microsoft Graph by -Id. Deleting a policy that still has active
    assignments will fail at Graph. High-impact: emits an explicit warning and defaults to ConfirmImpact
    High. The warning is written BEFORE the confirmation prompt, so it also appears under -WhatIf and
    under -Confirm:$false. Supports -WhatIf and -Confirm.

    .PARAMETER Id
    The assignment policy id (GUID) to delete.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERAccessPackageAssignmentPolicy -Id 'pol-guid'
    Deletes the policy after confirmation.

    .EXAMPLE
    Remove-OERAccessPackageAssignmentPolicy -Id 'pol-guid' -Confirm:$false
    Deletes the policy by id without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # MEASURED LIVE: this warning sits AHEAD of ShouldProcess on purpose. Emitted after it, it
        # printed only once the operator had already answered the ConfirmImpact = High prompt, and never
        # at all under -WhatIf -- a warning the operator sees only after committing to the delete is not
        # a guard. Do not move it back.
        Write-Warning "Deleting assignment policy '$Id'. This is irreversible."
        if ($PSCmdlet.ShouldProcess($Id, 'Delete assignment policy')) {
            try {
                $null = Invoke-OERGraphRequest -Method DELETE `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/assignmentPolicies/{0}" -f $Id)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
