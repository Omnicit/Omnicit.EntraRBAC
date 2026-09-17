function ConvertTo-OERAccessReviewDecision {
    <#
    .SYNOPSIS
    Converts a raw Graph accessReviewInstanceDecisionItem into a tagged Omnicit.EntraRBAC.AccessReviewDecision.

    .DESCRIPTION
    Maps the relevant properties of a Graph access review decision item into a [PSCustomObject] tagged
    Omnicit.EntraRBAC.AccessReviewDecision. Nested identities are flattened to the module-wide
    convention of an id plus a display name -- PrincipalId/PrincipalDisplayName and
    ResourceId/ResourceDisplayName -- and the reviewer and applier display names to
    ReviewedByDisplayName/AppliedByDisplayName. The historical bare Principal, Resource, ReviewedBy and
    AppliedBy names are kept as aliases so existing scripts keep working. The principal id and resource
    id are newly exposed; Graph returns them on the identity and resource objects and they were
    previously dropped. This private converter is the single owner of the decision output shape and is
    used by Get-OERAccessReviewInstanceDecision and Get-OERAccessReviewInstance -IncludeDecisions.

    .PARAMETER InputObject
    The raw Graph access review instance decision item (hashtable or PSObject) to convert.

    .EXAMPLE
    ConvertTo-OERAccessReviewDecision -InputObject $decision
    Converts a single access review decision item into a tagged object.

    .EXAMPLE
    $decisions | ConvertTo-OERAccessReviewDecision
    Converts each raw Graph access review decision item in the pipeline into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $Out = [PSCustomObject]@{
            Id                    = $InputObject.id
            Decision              = $InputObject.decision
            Justification         = $InputObject.justification
            ReviewedByDisplayName = $InputObject.reviewedBy.displayName
            ReviewedDateTime      = $InputObject.reviewedDateTime
            AppliedByDisplayName  = $InputObject.appliedBy.displayName
            ApplyResult           = $InputObject.applyResult
            PrincipalId           = $InputObject.principal.id
            PrincipalDisplayName  = $InputObject.principal.displayName
            ResourceId            = $InputObject.resource.id
            ResourceDisplayName   = $InputObject.resource.displayName
            Recommendation        = $InputObject.recommendation
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewDecision')
        $Out
    }
}
