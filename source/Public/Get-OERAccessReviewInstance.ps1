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
    by property name via the AccessReviewDefinitionId alias. A display name that more than one
    definition carries is refused with an AmbiguousName error that lists the candidate ids; pass the
    definition id instead.

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
        [ValidateNotNullOrEmpty()]
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
                # Sprint 11 step 10 (BL-21, R-13). A missing instance is an expected ANSWER of this GET, so
                # the call DECLARES the one code Graph answers it with, 'NotFound', and gets the
                # Omnicit.EntraRBAC.GraphExpectedError marker back instead of a raised error. The code is
                # MEASURED, not guessed: a live read on 2026-10-19 (read-only, the test tenant) asked for a
                # missing instance of a missing definition and for a missing instance of an existing one, and
                # Graph answered 404 with NO error code in the body both times (so did the missing definition
                # itself and the instance list of a missing definition). Convert-GraphHttpException derives
                # the label NotFound from the HTTP status when the body names no code, which is the id the
                # module then carries, and 'NotFound' is that label. 'ResourceNotFound',
                # 'Request_ResourceNotFound' and 'ItemNotFound' used to stand beside it as a superset
                # declared while the real code was unknown; none was observed on this endpoint, and they
                # are gone, since unobserved codes are what made the set a guess (the same rule as
                # Resolve-OERAccessPackageId's declared codes). A code Graph names outside the declared one is
                # raised and published as itself, still loud and never a silent empty answer, which is the
                # safe direction to be wrong in.
                # Why: docs/development/rationale.md#measured-not-found-codes
                # The wrapper compares WHOLE tokens, and reads the failure's message text only when the id is
                # status-derived, so a 403 carrying a real Graph code (Forbidden is status-derived, but
                # Authorization_RequestDenied is not) is never softened into "not found" by prose such as
                # "the caller does not have access to the resource, or it does not exist" -- a message-based
                # signal was tried here and proven to misroute a 403 in review, and the module's whole job is
                # RBAC, where a permissions failure diagnosed as a missing object is the wrong default.
                $Response = Invoke-OERGraphRequest -Uri "$BaseUri/$Instance`?`$select=$InstanceSelect" -ExpectedErrorCode 'NotFound'
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # Every failure the marker does not answer (a 403, an exhausted 429, a 5xx, a code Graph
                # named that is not the declared one) is published as itself: the real error always beats a
                # confident wrong diagnosis.
                $PSCmdlet.WriteError($PSItem)
                return
            }

            # The marker is a missing instance, and so is a successful GET that yields nothing, from the
            # caller's point of view: report both identically instead of emitting a shell instance built
            # from the marker or silently returning no output. There is no inner exception, since the
            # marker is an answer and no exception was raised.
            if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
                $Raw = @()
            } else {
                $Raw = @($Response)
            }
            if (-not @($Raw).Where({ $null -ne $PSItem }).Count) {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "Access review instance '$Instance' was not found on definition '$Definition'. " +
                        # The definition in the example is quoted with every single-quote character doubled
                        # (CodeGeneration.EscapeSingleQuotedStringContent: the straight one and the curly ones
                        # the PowerShell tokenizer also reads as quotes), so the example stays valid as typed.
                        "Run Get-OERAccessReviewInstance -Definition '$([System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$Definition))' without -Instance to list the valid instance ids.")) `
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
