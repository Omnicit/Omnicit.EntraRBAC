function Get-OERAccessReviewInstanceDecision {
    <#
    .SYNOPSIS
    Reads decision items for an access review instance, optionally scoped to a specific stage.

    .DESCRIPTION
    Retrieves access review instance decision items through Microsoft Graph and returns them as tagged
    Omnicit.EntraRBAC.AccessReviewDecision objects. When -Stage is supplied the decisions are fetched
    from the stage-level endpoint; otherwise the instance-level decisions endpoint is used. The
    definition is resolved by name or GUID via Resolve-OERAccessReviewDefinitionId.

    .PARAMETER Definition
    The access review definition id or display name. Accepts pipeline input by property name via the
    AccessReviewDefinitionId alias.

    .PARAMETER Instance
    The access review instance id. Accepts pipeline input by property name via the
    AccessReviewInstanceId and InstanceId aliases.

    .PARAMETER Stage
    The optional access review stage id. When supplied, decisions are fetched from the stage-level
    decisions endpoint rather than the instance-level endpoint. Accepts pipeline input by property
    name via the AccessReviewStageId and StageId aliases, so a stage from
    Get-OERAccessReviewInstance -IncludeStages can be piped directly into this cmdlet.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAccessReviewInstanceDecision -Definition 'Q3 AP Review' -Instance 'i1'
    Lists all decisions for instance i1 of the definition named Q3 AP Review.

    .EXAMPLE
    Get-OERAccessReviewInstanceDecision -Definition 'Q3 AP Review' -Instance 'i1' -Stage 's1'
    Lists decisions for stage s1 of instance i1.

    .EXAMPLE
    Get-OERAccessReviewInstance -Definition 'Q3 AP Review' | Get-OERAccessReviewInstanceDecision
    Pipes instances to the decision reader.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewDefinitionId')]
        [string]$Definition,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewInstanceId', 'InstanceId')]
        [string]$Instance,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewStageId', 'StageId')]
        [string]$Stage,

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

        $InstBase = "v1.0/identityGovernance/accessReviews/definitions/$DefId/instances/$Instance"
        $Uri = if ($Stage) {
            "$InstBase/stages/$Stage/decisions"
        } else {
            "$InstBase/decisions"
        }

        try {
            $Response = Invoke-OERGraphRequest -Uri $Uri -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        foreach ($Item in @($Response.value | Where-Object { $_ })) {
            ConvertTo-OERAccessReviewDecision -InputObject $Item
        }
    }
}
