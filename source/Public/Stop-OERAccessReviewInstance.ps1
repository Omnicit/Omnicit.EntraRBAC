function Stop-OERAccessReviewInstance {
    <#
    .SYNOPSIS
    Stops an in-progress access review instance.

    .DESCRIPTION
    Posts the stop action to an access review instance through Microsoft Graph, causing the instance to
    end immediately regardless of its scheduled end date. The definition is resolved by name or GUID via
    Resolve-OERAccessReviewDefinitionId. Supports -WhatIf and -Confirm. No output is returned on
    success (HTTP 204). ConfirmImpact is High -- a stopped instance cannot be restarted, so this
    prompts under the default $ConfirmPreference; unattended automation must pass -Confirm:$false.

    .PARAMETER Definition
    The access review definition id or display name. Accepts pipeline input by property name via the
    AccessReviewDefinitionId alias.

    .PARAMETER Instance
    The access review instance id. Accepts pipeline input by property name via the
    AccessReviewInstanceId and InstanceId aliases.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Stop-OERAccessReviewInstance -Definition 'Q3 AP Review' -Instance 'i1'
    Stops instance i1 of the Q3 AP Review definition after confirmation.

    .EXAMPLE
    Stop-OERAccessReviewInstance -Definition 'Q3 AP Review' -Instance 'i1' -Confirm:$false
    Stops the instance without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewDefinitionId')]
        [string]$Definition,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewInstanceId', 'InstanceId')]
        [string]$Instance,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $DefId = try {
            Resolve-OERAccessReviewDefinitionId -DisplayName $Definition
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new("Failed to resolve access review definition '$Definition'.")) `
                -ErrorId 'AccessReviewDefinitionResolveFailed' `
                -Category ObjectNotFound `
                -TargetObject $Definition `
                -Cmdlet $PSCmdlet
            return
        }

        if (-not $DefId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Access review definition '$Definition' not found.")) `
                -ErrorId 'AccessReviewDefinitionNotFound' `
                -Category ObjectNotFound `
                -TargetObject $Definition `
                -Cmdlet $PSCmdlet
            return
        }

        $Uri = "v1.0/identityGovernance/accessReviews/definitions/$DefId/instances/$Instance/stop"

        if ($PSCmdlet.ShouldProcess($Instance, 'Stop access review instance')) {
            Write-Warning "Stopping access review instance '$Instance'. An instance cannot be restarted once stopped."
            try {
                $null = Invoke-OERGraphRequest -Method POST -Uri $Uri
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
