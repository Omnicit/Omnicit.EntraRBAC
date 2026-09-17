function Remove-OERAccessPackageAssignment {
    <#
    .SYNOPSIS
    Removes a user's access package assignment as an administrator.

    .DESCRIPTION
    Creates an accessPackageAssignmentRequest with requestType adminRemove through Microsoft Graph,
    revoking the assignment identified by -AssignmentId. High-impact: emits an explicit warning and
    defaults to ConfirmImpact High. The revocation is processed asynchronously by Graph. Supports -WhatIf
    and -Confirm.

    .PARAMETER AssignmentId
    The accessPackageAssignment id to remove (as returned by Get-OERAccessPackageAssignment).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERAccessPackageAssignment -AssignmentId $assignmentId
    Revokes the assignment after confirmation.

    .EXAMPLE
    Remove-OERAccessPackageAssignment -AssignmentId $assignmentId -Confirm:$false
    Revokes the assignment without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$AssignmentId,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Body = @{
            requestType = 'adminRemove'
            assignment  = @{ id = $AssignmentId }
        }
        if ($PSCmdlet.ShouldProcess($AssignmentId, 'Revoke access package assignment')) {
            Write-Warning "Revoking access package assignment '$AssignmentId'."
            try {
                $null = Invoke-OERGraphRequest -Method POST `
                    -Uri 'v1.0/identityGovernance/entitlementManagement/assignmentRequests' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
