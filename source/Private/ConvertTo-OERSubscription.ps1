function ConvertTo-OERSubscription {
    <#
    .SYNOPSIS
    Converts a raw ARM subscription response into a tagged Omnicit.EntraRBAC.Subscription object.

    .DESCRIPTION
    Maps the subscriptions wire shape (id/subscriptionId/displayName/state/tenantId/tags) into a flat
    PSCustomObject. The ARM resource path is exposed as ResourceId (never a bare Id) so it cannot
    mis-bind downstream -PolicyId or -RoleEligibilityScheduleId parameters that carry an Id alias.
    The SubscriptionId property is the pipeline-alias property bound by downstream cmdlets'
    -Subscription parameter (Alias SubscriptionId), so Get-OERSubscription output pipes
    directly into the RBAC cmdlets.

    .PARAMETER InputObject
    The raw subscription object (hashtable or PSCustomObject) as returned by the ARM API.

    .EXAMPLE
    ConvertTo-OERSubscription -InputObject $Response
    Returns the tagged subscription object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    process {
        $Out = [PSCustomObject]@{
            ResourceId     = [string]$InputObject.id
            SubscriptionId = [string]$InputObject.subscriptionId
            DisplayName    = [string]$InputObject.displayName
            State          = [string]$InputObject.state
            TenantId       = [string]$InputObject.tenantId
            Tags           = $InputObject.tags
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Subscription')
        $Out
    }
}
