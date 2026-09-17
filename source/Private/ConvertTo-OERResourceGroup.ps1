function ConvertTo-OERResourceGroup {
    <#
    .SYNOPSIS
    Converts a raw ARM resource group response into a tagged Omnicit.EntraRBAC.ResourceGroup object.

    .DESCRIPTION
    Maps the resourcegroups wire shape (id/name/location/managedBy/tags/properties.provisioningState)
    into a flat PSCustomObject. The SubscriptionId is parsed from the resource id. The ResourceGroup
    and SubscriptionId properties are the pipeline-alias properties bound by the Azure RBAC and PIM
    cmdlets' -ResourceGroup and -Subscription parameters, so Get-OERResourceGroup output pipes directly
    into the delegation cmdlets. The full ARM resource id is exposed as ResourceId (deliberately NOT a
    property named Id): several delegation cmdlets bind an Id-aliased pipeline parameter (e.g.
    -RoleEligibilityScheduleId, -PolicyId), so an Id property on this object would mis-bind when piped.

    .PARAMETER InputObject
    The raw resource group object (PSCustomObject) as returned by the ARM API.

    .EXAMPLE
    ConvertTo-OERResourceGroup -InputObject $Response
    Returns the tagged resource group object.
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
        $Out = [PSCustomObject]@{
            ResourceGroup     = [string]$InputObject.name
            SubscriptionId    = $SubscriptionId
            Location          = [string]$InputObject.location
            ProvisioningState = [string]$InputObject.properties.provisioningState
            ManagedBy         = [string]$InputObject.managedBy
            Tags              = $InputObject.tags
            ResourceId        = [string]$InputObject.id
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ResourceGroup')
        $Out
    }
}
