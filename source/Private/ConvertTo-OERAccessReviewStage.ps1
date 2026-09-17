function ConvertTo-OERAccessReviewStage {
    <#
    .SYNOPSIS
    Converts a raw Graph accessReviewStage into a tagged Omnicit.EntraRBAC.AccessReviewStage.

    .DESCRIPTION
    Maps the relevant properties of a Graph access review stage into a [PSCustomObject] tagged
    Omnicit.EntraRBAC.AccessReviewStage. This private converter is the single owner of the stage
    output shape and is used by Get-OERAccessReviewInstance under -IncludeStages.

    Reviewers and FallbackReviewers are the stage's own reviewer scope queries, wrapped with
    Where-Object { $_ } because a stage without either carries $null there and
    @($NullVar.someProperty) yields a one-element array containing $null, not an empty array.
    Deliberately NOT surfaced here: DependsOn and DecisionsThatWillMoveToNextStage. Microsoft Learn's
    accessReviewStage resource does not carry either property -- its complete v1.0 property set is id,
    startDateTime, endDateTime, status, reviewers, fallbackReviewers. The two escalation properties
    live on accessReviewStageSettings, a property of the DEFINITION, and are surfaced by
    ConvertTo-OERAccessReviewDefinition's StageSettings instead. Adding them here would always read
    $null.

    An optional -InstanceId and -DefinitionId let the caller stamp the parent instance and definition
    ids onto the emitted AccessReviewStageId/AccessReviewInstanceId/AccessReviewDefinitionId
    properties. Get-OERAccessReviewInstance passes both when it attaches Stages under -IncludeStages,
    so a stage piped onward into Get-OERAccessReviewInstanceDecision carries the two ids that
    cmdlet's mandatory -Definition/-Instance parameters need, instead of forcing a double prompt.
    Both parameters are optional: the converter's own test file calls it with -InputObject alone.

    .PARAMETER InputObject
    The raw Graph access review stage (hashtable or PSObject) to convert.

    .PARAMETER InstanceId
    Optional parent access review instance id. Used to populate the AccessReviewInstanceId output
    property when the raw Graph stage does not carry it inline (it never does).

    .PARAMETER DefinitionId
    Optional parent access review definition id. Used to populate the AccessReviewDefinitionId output
    property when the raw Graph stage does not carry it inline (it never does).

    .EXAMPLE
    ConvertTo-OERAccessReviewStage -InputObject $stage
    Converts a single access review stage into a tagged object.

    .EXAMPLE
    $stages | ConvertTo-OERAccessReviewStage
    Converts each raw Graph access review stage in the pipeline into a tagged object.

    .EXAMPLE
    $stages | ConvertTo-OERAccessReviewStage -InstanceId 'i1' -DefinitionId 'd1'
    Converts each raw Graph access review stage in the pipeline into a tagged object, attaching the
    parent instance and definition ids so the result can be piped into a cmdlet that needs them.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$InstanceId,

        [string]$DefinitionId
    )
    process {
        $Out = [PSCustomObject]@{
            Status                   = $InputObject.status
            StartDateTime            = $InputObject.startDateTime
            EndDateTime              = $InputObject.endDateTime
            Reviewers                = @($InputObject.reviewers | Where-Object { $_ })
            FallbackReviewers        = @($InputObject.fallbackReviewers | Where-Object { $_ })
            AccessReviewStageId      = $InputObject.id
            AccessReviewInstanceId   = $InstanceId
            AccessReviewDefinitionId = $DefinitionId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewStage')
        $Out
    }
}
