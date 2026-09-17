function Get-OERAccessReviewInstance {
    <#
    .SYNOPSIS
    Reads access review instances for a given access review definition.

    .DESCRIPTION
    Retrieves access review instances through Microsoft Graph for the specified definition and returns
    them as tagged Omnicit.EntraRBAC.AccessReviewInstance objects. Supply -Instance to read a single
    instance directly; omit it to list all instances under the definition. The definition is resolved by
    name or GUID via Resolve-OERAccessReviewDefinitionId. When -IncludeStages is set, each instance's
    stages are attached as a Stages property. When -IncludeDecisions is set, each instance's decisions
    are attached as a Decisions property. Errors during stage or decision retrieval are surfaced as
    non-terminating warnings so that the instance is still returned.

    The instance and decision reads request only the fields the converters use, via $select, so each
    response carries less data to transfer and deserialize -- which is what Microsoft Graph itself
    recommends $select for, and it flags a GET made without one. The returned shape is unchanged. The
    stage read sends no $select, since the stage converter reads every property the v1.0 resource has.

    When -Instance names an instance that does not exist, the cmdlet reports a typed
    AccessReviewInstanceNotFound error rather than surfacing the raw Graph failure.

    .PARAMETER Definition
    The access review definition id or display name whose instances to retrieve. Accepts pipeline input
    by property name via the AccessReviewDefinitionId alias.

    .PARAMETER Instance
    The access review instance id to read. Omit it to list every instance of the definition. Named
    -Instance to match Stop-, Send- and Invoke-OERAccessReviewInstanceDecision, and still bindable
    as -Id, -InstanceId or -AccessReviewInstanceId.

    .PARAMETER IncludeStages
    When set, each returned instance has a Stages property containing the instance's review stages as
    tagged Omnicit.EntraRBAC.AccessReviewStage objects.

    .PARAMETER IncludeDecisions
    When set, each returned instance has a Decisions property containing the instance's decision items
    as tagged Omnicit.EntraRBAC.AccessReviewDecision objects.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAccessReviewInstance -Definition 'Q3 AP Review'
    Lists all instances of the access review definition named Q3 AP Review.

    .EXAMPLE
    Get-OERAccessReviewInstance -Definition 'Q3 AP Review' -Instance 'i1' -IncludeDecisions
    Reads instance i1 and attaches its decisions.

    .EXAMPLE
    Get-OERAccessReviewDefinition -DisplayName 'Q3 AP Review' | Get-OERAccessReviewInstance
    Pipes a definition into the instance reader.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewDefinitionId')]
        [string]$Definition,

        [Alias('Id', 'AccessReviewInstanceId', 'InstanceId')]
        [string]$Instance,

        [switch]$IncludeStages,
        [switch]$IncludeDecisions,
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

        $BaseUri = "v1.0/identityGovernance/accessReviews/definitions/$DefId/instances"

        # -- $select: ask only for what the converters read --
        # WHAT THIS BUYS: a SMALLER PAYLOAD, not a smaller quota charge. Every response carries less
        # to transfer and deserialize, and this cmdlet's fan-out is where that adds up -- a definition
        # with 30 instances read with -IncludeStages -IncludeDecisions issues 60+ paged requests in a
        # tight loop (issue #74). Microsoft Graph recommends $select for exactly this reason and
        # emits a '@microsoft.graph.tips' hint on a GET made without one.
        #
        # THE RESOURCEUNIT REDUCTION ISSUE #74 CITES DOES NOT APPLY HERE, and the claim must not be
        # re-added. Measured against Learn's throttling-limits page: the "using $select decreases the
        # cost by 1" rule lives in the "Identity and access service limits" section, which applies to
        # an EXPLICIT resource list (application, device, directoryObject, domain, group,
        # servicePrincipal, user and so on). No accessReview resource appears in it, and the page has
        # no identity-governance or entitlement-management section at all. Even inside that section
        # the rule would not bite: an identity path not named in its table has a base GET cost of 1,
        # and the page states that a request cost can never be lower than 1 -- so the documented
        # decrement floors out at zero reduction. The payload argument above stands on its own.
        #
        # THE LISTS MUST STAY IN STEP WITH THE CONVERTERS. A $select that drops a field a converter
        # reads makes that property arrive $null with no error anywhere -- the exact null-field class
        # of bug PR #45 fixed. tests/Unit/Public/Get-OERAccessReviewInstance.Tests.ps1 pins the
        # returned shape and derives the required instance fields from the converter's own source, so
        # adding a read to a converter without adding it here fails the gate rather than the tenant.
        #   ConvertTo-OERAccessReviewInstance reads id, status, startDateTime, endDateTime, scope.
        #   ConvertTo-OERAccessReviewDecision reads id, decision, justification, reviewedBy,
        #     reviewedDateTime, appliedBy, applyResult, principal, resource, recommendation.
        # reviewedBy/appliedBy/principal/resource are complex types selected WHOLE. What the
        # converter reaches into differs per type: .id AND .displayName on principal and resource,
        # .displayName alone on reviewedBy and appliedBy. Either way it is the PARENT property that
        # has to be named, so 'principal/id' would not be correct -- and naming the parent is also
        # what lets a converter later start reading reviewedBy.id without a select change.
        #
        # THE STAGES READ GETS NO $select, DELIBERATELY. accessReviewStage's complete v1.0 property
        # set is id, startDateTime, endDateTime, status, reviewers, fallbackReviewers -- and
        # ConvertTo-OERAccessReviewStage reads all six. Naming every property a resource has is a
        # longer URL for no reduction. This omission is measured, not overlooked.
        $InstanceSelect = 'id,status,startDateTime,endDateTime,scope'
        $DecisionSelect = 'id,decision,justification,reviewedBy,reviewedDateTime,appliedBy,' +
                          'applyResult,principal,resource,recommendation'

        if ($Instance) {
            try {
                $Raw = @(Invoke-OERGraphRequest -Uri "$BaseUri/$Instance`?`$select=$InstanceSelect")
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # A not-found on a single-item GET is a normal, expected outcome and deserves the same
                # friendly, greppable ErrorId this cmdlet already uses for a missing definition.
                # Convert-GraphHttpException sets FullyQualifiedErrorId from the Graph error.code when the
                # body carries one, and derives the literal label NotFound from the HTTP status when it does
                # not (a bare 404 with no body code) -- so every genuine not-found already arrives with a
                # recognisable id. Match ONLY that converted code, deliberately excluding any free-text
                # message check: Graph uses existence-ambiguous wording for some authorization failures (for
                # example "the caller does not have access to the resource, or it does not exist", or
                # "Resource ... does not exist or one of its queried reference-property objects are not
                # present") precisely so it does not confirm existence to an unauthorized caller, and that
                # phrasing carries no reliable authorization keyword to filter on -- a message-based signal
                # was tried and proven to misroute a 403 in review. The message adds no coverage the code
                # allowlist lacks, only the risk of misdiagnosing a permissions failure as a missing object,
                # which is the wrong default for a module whose entire job is RBAC. Anything outside the
                # allowlist (throttling, an uncategorized 403/5xx) falls through to the verbatim re-emit --
                # surfacing the real error always beats a confident wrong diagnosis.
                $KnownNotFoundCodes = @('ResourceNotFound', 'Request_ResourceNotFound', 'ItemNotFound', 'NotFound')
                $ErrorIdCode = ([string]$PSItem.FullyQualifiedErrorId) -replace ',.*$', ''
                $LooksNotFound = $KnownNotFoundCodes -contains $ErrorIdCode
                if ($LooksNotFound) {
                    Write-CmdletError `
                        -Message ([System.Exception]::new(
                            "Access review instance '$Instance' was not found on definition '$Definition'. " +
                            "Run Get-OERAccessReviewInstance -Definition '$Definition' without -Instance to list the valid instance ids.")) `
                        -InnerException $PSItem.Exception `
                        -ErrorId 'AccessReviewInstanceNotFound' `
                        -Category ObjectNotFound `
                        -TargetObject $Instance `
                        -Cmdlet $PSCmdlet
                    return
                }
                $PSCmdlet.WriteError($PSItem)
                return
            }

            # A successful GET that yields nothing is the same condition as a 404 from the caller's
            # point of view, so report it identically instead of silently returning no output.
            if (-not @($Raw).Where({ $null -ne $PSItem }).Count) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "Access review instance '$Instance' was not found on definition '$Definition'. " +
                        "Run Get-OERAccessReviewInstance -Definition '$Definition' without -Instance to list the valid instance ids.")) `
                    -ErrorId 'AccessReviewInstanceNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $Instance `
                    -Cmdlet $PSCmdlet
                return
            }
        } else {
            try {
                $Raw = @((Invoke-OERGraphRequest -Uri "$BaseUri`?`$select=$InstanceSelect" -All).value)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }

        $Raw = @($Raw | Where-Object { $_ })
        foreach ($GraphInst in $Raw) {
            $Inst = ConvertTo-OERAccessReviewInstance -InputObject $GraphInst -DefinitionId $DefId

            if ($IncludeStages) {
                try {
                    $Stages = @((Invoke-OERGraphRequest -Uri "$BaseUri/$($Inst.Id)/stages" -All).value)
                    $Stages = @($Stages | Where-Object { $_ } | ForEach-Object {
                        ConvertTo-OERAccessReviewStage -InputObject $_ -InstanceId $Inst.Id -DefinitionId $DefId
                    })
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Stages = @()
                    Write-Warning "Could not read stages for access review instance $($Inst.Id): $($PSItem.Exception.Message)"
                }
                $Inst | Add-Member -NotePropertyName Stages -NotePropertyValue $Stages -Force
            }

            if ($IncludeDecisions) {
                try {
                    $Decisions = @((Invoke-OERGraphRequest -Uri "$BaseUri/$($Inst.Id)/decisions`?`$select=$DecisionSelect" -All).value)
                    $Decisions = @($Decisions | Where-Object { $_ } | ForEach-Object {
                        ConvertTo-OERAccessReviewDecision -InputObject $_
                    })
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Decisions = @()
                    Write-Warning "Could not read decisions for access review instance $($Inst.Id): $($PSItem.Exception.Message)"
                }
                $Inst | Add-Member -NotePropertyName Decisions -NotePropertyValue $Decisions -Force
            }

            $Inst
        }
    }
}
