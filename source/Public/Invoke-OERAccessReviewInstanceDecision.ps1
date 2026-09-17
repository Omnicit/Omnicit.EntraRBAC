function Invoke-OERAccessReviewInstanceDecision {
    <#
    .SYNOPSIS
    Applies or resets reviewer decisions for an access review instance.

    .DESCRIPTION
    Posts an applyDecisions or resetDecisions action to an access review instance through Microsoft
    Graph. Use the default Apply parameter set to finalize and apply all reviewer decisions; use -Reset
    to clear all decisions so that reviewers can submit new ones. The definition is resolved by name or
    GUID via Resolve-OERAccessReviewDefinitionId. Supports -WhatIf and -Confirm. No output is returned
    on success (HTTP 204). ConfirmImpact is High, so BOTH the default apply path and -Reset prompt
    under the default $ConfirmPreference: applyDecisions commits real access revocations and
    resetDecisions discards every recorded reviewer decision irreversibly. This is intentional, not
    an oversight -- ConfirmImpact is per-cmdlet, not per-parameter-set. Unattended automation must
    pass -Confirm:$false for either path.

    .PARAMETER Definition
    The access review definition id or display name. Accepts pipeline input by property name via the
    AccessReviewDefinitionId alias.

    .PARAMETER Instance
    The access review instance id. Accepts pipeline input by property name via the
    AccessReviewInstanceId and InstanceId aliases.

    .PARAMETER Apply
    Apply all reviewer decisions for the instance. This is the default parameter set.

    .PARAMETER Reset
    Reset all reviewer decisions so reviewers can submit new ones.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Invoke-OERAccessReviewInstanceDecision -Definition 'Q3 AP Review' -Instance 'i1' -Confirm:$false
    Applies the reviewer decisions for instance i1.

    .EXAMPLE
    Invoke-OERAccessReviewInstanceDecision -Definition 'Q3 AP Review' -Instance 'i1' -Reset -Confirm:$false
    Resets all decisions for instance i1 so that reviewers may resubmit.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Apply',
        Justification = 'Parameter-set discriminator switch; ParameterSetName drives behavior.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Reset',
        Justification = 'Parameter-set discriminator switch; ParameterSetName drives behavior.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Apply')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewDefinitionId')]
        [string]$Definition,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewInstanceId', 'InstanceId')]
        [string]$Instance,

        [Parameter(ParameterSetName = 'Apply')]
        [switch]$Apply,

        [Parameter(ParameterSetName = 'Reset', Mandatory)]
        [switch]$Reset,

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

        $Action = if ($PSCmdlet.ParameterSetName -eq 'Reset') { 'resetDecisions' } else { 'applyDecisions' }
        $Uri = "v1.0/identityGovernance/accessReviews/definitions/$DefId/instances/$Instance/$Action"
        $ShouldProcessAction = if ($PSCmdlet.ParameterSetName -eq 'Reset') {
            'Reset access review instance decisions'
        } else {
            'Apply access review instance decisions'
        }

        if ($PSCmdlet.ShouldProcess($Instance, $ShouldProcessAction)) {
            if ($PSCmdlet.ParameterSetName -eq 'Reset') {
                Write-Warning "Resetting decisions on access review instance '$Instance'. Every recorded reviewer decision is discarded irreversibly and cannot be recovered."
            } else {
                Write-Warning "Applying decisions on access review instance '$Instance'. This commits the recorded access revocations."
            }
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
