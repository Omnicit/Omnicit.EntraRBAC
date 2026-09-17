function New-OERResourceGroup {
    <#
    .SYNOPSIS
    Creates or updates an Azure resource group.

    .DESCRIPTION
    Creates (or idempotently updates) a Microsoft.Resources/resourceGroups resource through the ARM
    API (api-version 2025-04-01) via Invoke-OERArmRequest. The resource group name is validated
    client-side (1-90 characters of letters, digits, '-', '_', '.', '(' or ')', not ending in a
    period) before any call. The scope is resolved with Resolve-OERScope from a subscription GUID or
    display name. The PUT body carries the required location and, when supplied, the tag set. ARM
    treats the PUT as create-or-update; the location cannot be changed once the resource group exists.
    Supports -WhatIf/-Confirm. Requires an ARM token; authentication is ensured at entry via
    Initialize-OERAuth -IncludeARM.

    .PARAMETER Subscription
    A subscription GUID or display name. Bound from the pipeline by property name (SubscriptionId).

    .PARAMETER Name
    The resource group name to create or update.

    .PARAMETER Location
    The Azure region for the resource group (e.g. 'westeurope'). Immutable after creation.

    .PARAMETER Tag
    Optional hashtable of tags to attach. When supplied, it is the complete tag set on the resource group.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERResourceGroup -Subscription 'Prod' -Name 'rg-network' -Location 'westeurope' -Tag @{ env = 'prod' }
    Creates the rg-network resource group in the Prod subscription with an env=prod tag.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(Mandatory)]
        [Alias('ResourceGroup')]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Location,

        [hashtable]$Tag,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($Name.Length -gt 90 -or $Name -notmatch '^[-\w\.\(\)]+$' -or $Name.EndsWith('.')) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Resource group name '$Name' is invalid: it must be 1-90 characters of letters, digits, '-', '_', '.', '(' or ')', and must not end with a period.")) `
                -ErrorId 'InvalidResourceGroupName' -Category InvalidArgument -TargetObject $Name -Cmdlet $PSCmdlet
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

        $Body = @{ location = $Location }
        if ($PSBoundParameters.ContainsKey('Tag')) { $Body.tags = $Tag }

        if ($PSCmdlet.ShouldProcess("resource group '$Name' at scope '$TargetScope'", 'Create or update Azure resource group')) {
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
