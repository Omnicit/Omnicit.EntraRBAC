function Set-OERResourceGroup {
    <#
    .SYNOPSIS
    Updates the tags of an existing Azure resource group.

    .DESCRIPTION
    Updates a Microsoft.Resources/resourceGroups resource through the ARM API (api-version 2025-04-01)
    via Invoke-OERArmRequest. Because an ARM resource group PUT replaces the whole object and requires
    the (immutable) location, this cmdlet first GETs the current resource group -- a missing one yields
    a clean ResourceGroupNotFound error -- then PUTs the preserved location together with the tags. The
    -Tag set REPLACES the existing tags (an empty hashtable clears them); -Tag is required, and omitting
    it emits a non-terminating NothingToUpdate error instead of silently re-applying the current tags.
    The resource group location cannot be changed once created, so it is not exposed. Supports
    -WhatIf/-Confirm. Requires an ARM token; authentication is ensured at entry via
    Initialize-OERAuth -IncludeARM.

    .PARAMETER Subscription
    A subscription GUID or display name. Bound from the pipeline by property name (SubscriptionId).

    .PARAMETER Name
    The resource group name to update. Bound from the pipeline by property name (ResourceGroup).

    .PARAMETER Tag
    The complete tag set to apply (replaces existing tags). An empty hashtable clears all tags. This
    parameter is required for an update to occur; omitting it emits a non-terminating NothingToUpdate
    error.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-network' -Tag @{ env = 'prod'; owner = 'net-team' }
    Replaces the tags on rg-network with env=prod and owner=net-team.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ResourceGroup')]
        [string]$Name,

        [hashtable]$Tag,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if (-not $PSBoundParameters.ContainsKey('Tag')) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No updatable property was supplied. Pass -Tag with the complete tag set to apply; an empty hashtable (-Tag @{}) clears all tags.')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject $Name `
                -Cmdlet $PSCmdlet
            return
        }

        try {
            $TargetScope = Resolve-OERScope -Subscription $Subscription -ResourceGroup $Name
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $Subscription -Cmdlet $PSCmdlet
            return
        }

        try {
            $Current = Invoke-OERArmRequest -Path "$TargetScope`?api-version=2025-04-01"
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if ($PSItem.FullyQualifiedErrorId -in 'ResourceGroupNotFound', 'NotFound') {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Resource group '$Name' was not found; create it with New-OERResourceGroup.")) `
                    -ErrorId 'ResourceGroupNotFound' -Category ObjectNotFound -TargetObject $Name -Cmdlet $PSCmdlet
            } else {
                $PSCmdlet.WriteError($PSItem)
            }
            return
        }

        # -Tag is guaranteed bound here -- the NothingToUpdate guard above already returned otherwise.
        $Body = @{ location = [string]$Current.location; tags = $Tag }

        if ($PSCmdlet.ShouldProcess("resource group '$Name' at scope '$TargetScope'", 'Update Azure resource group')) {
            try {
                $Response = Invoke-OERArmRequest -Method PUT -Path "$TargetScope`?api-version=2025-04-01" -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERResourceGroup -InputObject $Response
        }
    }
}
