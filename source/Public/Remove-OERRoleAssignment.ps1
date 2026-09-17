function Remove-OERRoleAssignment {
    <#
    .SYNOPSIS
    Deletes an Azure role assignment by its full ARM resource id.

    .DESCRIPTION
    Deletes a Microsoft.Authorization/roleAssignments resource through the ARM API (api-version
    2022-04-01) via Invoke-OERArmRequest. -Id is the FULL ARM role assignment id (the Id /
    RoleAssignmentId property emitted by Get-OERRoleAssignment), so Get | Remove works directly over
    the pipeline. The value is validated to actually be a role assignment id before any call is made
    -- a piped non-assignment object's Id produces a clear InvalidRoleAssignmentId error instead of a
    bogus DELETE. A 204 response (ARM's signal that the resource did not exist) surfaces as a
    non-terminating RoleAssignmentNotFound error. This is a high-impact operation: ConfirmImpact
    High, an explicit warning precedes the destructive call, and -WhatIf/-Confirm are supported.
    Requires an ARM token; authentication is ensured at entry via Initialize-OERAuth -IncludeARM.

    .PARAMETER Id
    The full ARM role assignment resource id in the form
    {scope}/providers/Microsoft.Authorization/roleAssignments/{guid}. Bound from the pipeline by
    property name (RoleAssignmentId alias).

    .PARAMETER PassThru
    Return the deleted role assignment object (ARM echoes it on a 200 response).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERRoleAssignment -Subscription 'Prod' -User 'anna.berg@contoso.com' | Remove-OERRoleAssignment
    Removes Anna's role assignments at the Prod subscription after confirmation.

    .EXAMPLE
    Remove-OERRoleAssignment -Id '/subscriptions/abc/providers/Microsoft.Authorization/roleAssignments/def' -Confirm:$false
    Removes one role assignment without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('RoleAssignmentId')]
        [string]$Id,

        [switch]$PassThru,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($Id -notmatch '(?i)/providers/Microsoft\.Authorization/roleAssignments/[^/]+$') {
            Write-CmdletError `
                -Message ([System.Exception]::new("'$Id' is not an Azure role assignment resource id ({scope}/providers/Microsoft.Authorization/roleAssignments/{guid}).")) `
                -ErrorId 'InvalidRoleAssignmentId' -Category InvalidArgument -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        if ($PSCmdlet.ShouldProcess($Id, 'Delete Azure role assignment')) {
            Write-Warning "Deleting Azure role assignment '$Id'. This removes the principal's access at that scope."
            try {
                $Response = Invoke-OERArmRequest -Method DELETE -Path "$Id`?api-version=2022-04-01"
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($null -eq $Response) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Role assignment '$Id' was not found.")) `
                    -ErrorId 'RoleAssignmentNotFound' -Category ObjectNotFound -TargetObject $Id -Cmdlet $PSCmdlet
                return
            }
            if ($PassThru) { ConvertTo-OERRoleAssignment -InputObject $Response }
        }
    }
}
