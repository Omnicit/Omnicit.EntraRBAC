function ConvertTo-OERAccessReviewInstance {
    <#
    .SYNOPSIS
    Converts a raw Graph accessReviewInstance into a tagged Omnicit.EntraRBAC.AccessReviewInstance.

    .DESCRIPTION
    Maps the relevant properties of a Graph access review instance into a [PSCustomObject] tagged
    Omnicit.EntraRBAC.AccessReviewInstance. The scope query is surfaced for inspection. An optional
    -DefinitionId parameter allows the parent definition id to be attached when the raw instance
    object does not carry it (e.g. when fetched as a child of a definition). This private converter
    is the single owner of the instance output shape and is used by Get-OERAccessReviewInstance.

    .PARAMETER InputObject
    The raw Graph access review instance (hashtable or PSObject) to convert.

    .PARAMETER DefinitionId
    Optional parent access review definition id. Used to populate the DefinitionId output property
    when the raw Graph instance does not carry it inline.

    .EXAMPLE
    ConvertTo-OERAccessReviewInstance -InputObject $instance -DefinitionId 'def-123'
    Converts a single access review instance into a tagged object and attaches the parent definition id.

    .EXAMPLE
    $instances | ConvertTo-OERAccessReviewInstance -DefinitionId 'def-123'
    Converts each raw Graph access review instance in the pipeline into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$DefinitionId
    )
    process {
        $Out = [PSCustomObject]@{
            AccessReviewInstanceId   = $InputObject.id
            Status                   = $InputObject.status
            StartDateTime            = $InputObject.startDateTime
            EndDateTime              = $InputObject.endDateTime
            AccessReviewDefinitionId = $DefinitionId
            Scope                    = $InputObject.scope.query
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewInstance')
        $Out
    }
}
