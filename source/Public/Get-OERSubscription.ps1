function Get-OERSubscription {
    <#
    .SYNOPSIS
    Lists Azure subscriptions, gets one subscription, or lists the subscriptions under a management group.

    .DESCRIPTION
    Reads subscriptions through the ARM API (api-version 2022-12-01) via Invoke-OERArmRequest.
    Without parameters, all subscriptions visible to the caller are listed (paged). -Name accepts a
    subscription GUID (direct GET) or a display name (client-side case-insensitive match; the API has
    no server-side name filter). -ManagementGroup limits the result to subscriptions anywhere under
    the given management group: the management group tree is fetched with $expand=children and
    $recurse=true (api-version 2020-05-01), descendant subscription ids are collected, and the
    subscription list is intersected with them -- subscriptions in the tree that the caller cannot
    read are skipped. When -Name and -ManagementGroup are combined, the name match is applied to the
    management-group-scoped list. Output objects are tagged Omnicit.EntraRBAC.Subscription and
    expose SubscriptionId so they pipe into the RBAC cmdlets. Requires an ARM token; authentication
    is ensured at entry via Initialize-OERAuth -IncludeARM.

    .PARAMETER Name
    The subscription display name or subscription id to filter on. Also bindable as -Subscription,
    the name every RBAC and PIM cmdlet uses for the same scope target, or as -SubscriptionId. This
    parameter deliberately does not bind from the pipeline, so a piped management group's Name
    property is never read as a subscription.

    .PARAMETER ManagementGroup
    A management group name or display name whose descendant subscriptions are listed. Bound from
    the pipeline by property name (ManagementGroupName), so Get-OERManagementGroup pipes in.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERSubscription
    Lists all subscriptions visible to the caller.

    .EXAMPLE
    Get-OERManagementGroup -Name 'mg-platform' | Get-OERSubscription
    Lists the subscriptions under the mg-platform management group.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Alias('SubscriptionId', 'Subscription')]
        [string]$Name,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ManagementGroupName')]
        [string]$ManagementGroup,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($Name -and (Test-OERGuid -Value $Name) -and -not $ManagementGroup) {
            try {
                $Response = Invoke-OERArmRequest -Path "/subscriptions/$Name`?api-version=2022-12-01"
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERSubscription -InputObject $Response
            return
        }

        try {
            $ListResponse = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        $Subscriptions = @($ListResponse.value)

        if ($ManagementGroup) {
            try {
                $MgScope = Resolve-OERScope -ManagementGroup $ManagementGroup
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'ManagementGroupNotFound' -Category ObjectNotFound -TargetObject $ManagementGroup -Cmdlet $PSCmdlet
                return
            }
            $MgName = $MgScope.Split('/')[-1]
            try {
                $Tree = Invoke-OERArmRequest -Path "/providers/Microsoft.Management/managementGroups/$([uri]::EscapeDataString($MgName))?api-version=2020-05-01&`$expand=children&`$recurse=true"
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }

            $DescendantIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $Stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($Child in @($Tree.properties.children)) { if ($Child) { $Stack.Push($Child) } }
            while ($Stack.Count -gt 0) {
                $Node = $Stack.Pop()
                if ([string]$Node.type -eq '/subscriptions') { $null = $DescendantIds.Add([string]$Node.name) }
                foreach ($Child in @($Node.children)) { if ($Child) { $Stack.Push($Child) } }
            }
            $Subscriptions = @($Subscriptions | Where-Object { $DescendantIds.Contains([string]$PSItem.subscriptionId) })
        }

        if ($Name) {
            $Subscriptions = @($Subscriptions | Where-Object { $PSItem.displayName -ieq $Name -or $PSItem.subscriptionId -ieq $Name })
            if ($Subscriptions.Count -eq 0) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Subscription '$Name' was not found or you do not have access to it.")) `
                    -ErrorId 'SubscriptionNotFound' -Category ObjectNotFound -TargetObject $Name -Cmdlet $PSCmdlet
                return
            }
        }

        foreach ($Item in $Subscriptions) {
            ConvertTo-OERSubscription -InputObject $Item
        }
    }
}
