function Remove-OERResourceGroup {
    <#
    .SYNOPSIS
    Deletes an Azure resource group and ALL resources it contains. High-impact: prompts by default.

    .DESCRIPTION
    Deletes a Microsoft.Resources/resourceGroups resource through the ARM API (api-version 2025-04-01)
    via Invoke-OERArmRequest. Deleting a resource group permanently deletes every resource inside it,
    so the command declares ConfirmImpact = High (it prompts unless -Confirm:$false is passed) and
    emits an explicit warning before the destructive call. The ARM delete is asynchronous: Azure
    returns 202 Accepted and the cmdlet returns once the deletion is accepted (it does not poll to
    completion). The scope is resolved with Resolve-OERScope from a subscription GUID or display name.
    Supports -WhatIf and -Confirm. Requires an ARM token; authentication is ensured at entry via
    Initialize-OERAuth -IncludeARM.

    .PARAMETER Subscription
    A subscription GUID or display name. Bound from the pipeline by property name (SubscriptionId).

    .PARAMETER Name
    The resource group name to delete. Bound from the pipeline by property name (ResourceGroup).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERResourceGroup -Subscription 'Prod' -Name 'rg-obsolete' -Confirm:$false
    Deletes the rg-obsolete resource group (and everything in it) without an interactive prompt.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ResourceGroup')]
        [string]$Name,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        try {
            $TargetScope = Resolve-OERScope -Subscription $Subscription -ResourceGroup $Name
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $Subscription -Cmdlet $PSCmdlet
            return
        }

        if ($PSCmdlet.ShouldProcess("resource group '$Name' at scope '$TargetScope'", 'Delete Azure resource group (and ALL resources it contains)')) {
            Write-Warning "Deleting resource group '$Name' permanently deletes ALL resources it contains."
            try {
                $null = Invoke-OERArmRequest -Method DELETE -Path "$TargetScope`?api-version=2025-04-01"
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            Write-Verbose "[Remove-OERResourceGroup] Deletion of '$Name' accepted (asynchronous)."
        }
    }
}
