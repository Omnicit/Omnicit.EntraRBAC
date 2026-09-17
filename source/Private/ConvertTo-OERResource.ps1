function ConvertTo-OERResource {
    <#
    .SYNOPSIS
    Converts a raw ARM resource response into a tagged Omnicit.EntraRBAC.Resource object.

    .DESCRIPTION
    Maps the resources wire shape (id/name/type/location/kind/managedBy/tags) into a flat
    PSCustomObject. The SubscriptionId and ResourceGroup are parsed from the resource id. The
    SubscriptionId, ResourceGroup, ResourceType, and ResourceName properties are the pipeline-alias
    properties bound by the Azure RBAC and PIM cmdlets' -Subscription, -ResourceGroup, -ResourceType,
    and -ResourceName parameters, so Get-OERResource output pipes directly into the delegation cmdlets
    at resource scope. The full ARM resource id is exposed as ResourceId (deliberately NOT a property
    named Id or Scope): an Id or Scope property would mis-bind when the object is piped (an Id-aliased
    parameter, or the new resolver path) and would also trip the single-scope guard in Resolve-OERScope.

    .PARAMETER InputObject
    The raw resource object (PSCustomObject) as returned by the ARM resources endpoint.

    .EXAMPLE
    ConvertTo-OERResource -InputObject $Response
    Returns the tagged resource object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    process {
        $SubscriptionId = ''
        if ([string]$InputObject.id -match '/subscriptions/([^/]+)') {
            $SubscriptionId = $Matches[1]
        }
        $ResourceGroupName = ''
        if ([string]$InputObject.id -match '/resourceGroups/([^/]+)') {
            $ResourceGroupName = $Matches[1]
        }
        $Out = [PSCustomObject]@{
            ResourceName   = [string]$InputObject.name
            ResourceType   = [string]$InputObject.type
            ResourceGroup  = $ResourceGroupName
            SubscriptionId = $SubscriptionId
            Location       = [string]$InputObject.location
            Kind           = [string]$InputObject.kind
            ManagedBy      = [string]$InputObject.managedBy
            Tags           = $InputObject.tags
            ResourceId     = [string]$InputObject.id
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Resource')
        $Out
    }
}
