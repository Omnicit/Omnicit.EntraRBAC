function Send-OERAccessReviewReminder {
    <#
    .SYNOPSIS
    Sends a reminder notification to reviewers for an in-progress access review instance.

    .DESCRIPTION
    Posts the sendReminder action to an access review instance through Microsoft Graph, causing an
    email reminder to be dispatched to all pending reviewers. The definition is resolved by name or GUID
    via Resolve-OERAccessReviewDefinitionId. Supports -WhatIf and -Confirm. No output is returned on
    success (HTTP 204).

    .PARAMETER Definition
    The access review definition id or display name. Accepts pipeline input by property name via the
    AccessReviewDefinitionId alias. A display name that more than one definition carries is refused
    with an AmbiguousName error that lists the candidate ids, and no reminder is sent; pass the
    definition id instead.

    .PARAMETER Instance
    The access review instance id. Accepts pipeline input by property name via the
    AccessReviewInstanceId and InstanceId aliases.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Send-OERAccessReviewReminder -Definition 'Q3 AP Review' -Instance 'i1'
    Sends a reminder to all pending reviewers for instance i1.

    .EXAMPLE
    Send-OERAccessReviewReminder -Definition 'Q3 AP Review' -Instance 'i1' -Confirm:$false
    Sends the reminder without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess)]
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
        # A lookup that cannot name ONE definition is not "not found", and what it was is not dropped.
        # A display name that matches more than one definition (Graph does not enforce unique review
        # names) is published as itself, with the candidate ids the operator needs, and nothing is
        # read or acted on. Any other failure (a 403, an exhausted 429, a 5xx) keeps
        # AccessReviewDefinitionResolveFailed, as a ReadError that carries the cause in its message
        # and chains the original exception: a failed read is never a not-found.
        $DefId = try {
            Resolve-OERAccessReviewDefinitionId -DisplayName $Definition
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                $PSCmdlet.WriteError($PSItem)
                return
            }
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to resolve access review definition '$Definition': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'AccessReviewDefinitionResolveFailed' `
                -Category ReadError `
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

        $Uri = "v1.0/identityGovernance/accessReviews/definitions/$DefId/instances/$Instance/sendReminder"

        if ($PSCmdlet.ShouldProcess($Instance, 'Send access review reminder')) {
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
