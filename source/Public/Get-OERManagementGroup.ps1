function Get-OERManagementGroup {
    <#
    .SYNOPSIS
    Lists Azure management groups or gets one management group, optionally with its child hierarchy.

    .DESCRIPTION
    Reads Microsoft.Management/managementGroups through the ARM API (api-version 2020-05-01) via
    Invoke-OERArmRequest. Without -Name, all management groups visible to the caller are listed
    (paged). With -Name, the single management group is fetched; -Expand includes the direct
    children (management groups and subscriptions) and -Recurse includes the entire hierarchy
    (-Recurse implies -Expand because the API requires $expand=children with $recurse=true).
    Output objects are tagged Omnicit.EntraRBAC.ManagementGroup and expose ManagementGroupName so
    they pipe into Get-OERSubscription and the RBAC cmdlets. Requires an ARM token; authentication
    is ensured at entry via Initialize-OERAuth -IncludeARM.

    A management group created in the last few minutes can be missing from the management-group
    list, although a -Name read already finds it, and an Export-OERInventory run in that window does
    not walk it, because it cannot know it exists. Measured live: sending 'Cache-Control: no-cache'
    with the list does not shorten that window.

    .PARAMETER Name
    The management group name (its id segment, not the display name). Also bindable as
    -ManagementGroup, the name every RBAC and PIM cmdlet uses for the same scope target, or as
    -ManagementGroupName. Binds from the pipeline by property name. When omitted, all management
    groups are listed.

    .PARAMETER Expand
    Include the direct children (child management groups and subscriptions) in the response.

    .PARAMETER Recurse
    Include the entire hierarchy below the management group. Implies -Expand.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERManagementGroup
    Lists all management groups visible to the caller.

    .EXAMPLE
    Get-OERManagementGroup -Name 'mg-platform' -Recurse
    Gets the mg-platform management group with its full child hierarchy.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('ManagementGroupName', 'ManagementGroup')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByName')]
        [switch]$Expand,

        [Parameter(ParameterSetName = 'ByName')]
        [switch]$Recurse,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $Path ="/providers/Microsoft.Management/managementGroups/$([uri]::EscapeDataString($Name))?api-version=2020-05-01"
            if ($Expand -or $Recurse) { $Path += '&$expand=children' }
            if ($Recurse) { $Path += '&$recurse=true' }
            try {
                $Response = Invoke-OERArmRequest -Path $Path
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # ARM returns 403 AuthorizationFailed (not 404) for a management group name that does
                # not exist OR that the caller cannot read ("...or the scope is invalid") -- the two
                # are indistinguishable. Surface a clear not-found message instead of the raw
                # authorization error; genuine throttling/server failures pass through unchanged.
                if ($PSItem.FullyQualifiedErrorId -in 'AuthorizationFailed', 'NotFound') {
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Management group '$Name' was not found, or you do not have access to it (Microsoft.Management/managementGroups/read).")) `
                        -ErrorId 'ManagementGroupNotFound' -Category ObjectNotFound -TargetObject $Name -Cmdlet $PSCmdlet
                } else {
                    $PSCmdlet.WriteError($PSItem)
                }
                return
            }
            ConvertTo-OERManagementGroup -InputObject $Response
            return
        }

        try {
            $Items = @(Get-OERManagementGroupList)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        # The tenant root group's name is its tenant id. It has no parent, so it is never looked up
        # and is never reported as unread.
        $IsRoot = @(foreach ($Item in $Items) {
                $ItemName = [string]$Item.name
                $ItemName -ne '' -and $ItemName -eq [string]$Item.properties.tenantId
            })

        # The Management Groups - List answer carries no parent (Microsoft Learn: a listed item has
        # only id, name, type, displayName and tenantId), so the parents are read separately: ONE
        # Entities - List call per list, not one GET per group. A parent that could not be read is
        # reported as an error and never shown as an empty parent, since an empty ParentId otherwise
        # reads as "this group has no parent".
        $ParentByName = @{}
        $ParentReadError = $null
        if ($IsRoot -contains $false) {
            try {
                $ParentByName = Get-OERManagementGroupParent
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $ParentReadError = $PSItem
            }
        }

        # Every group is emitted, in list order, before the error below is written, so a caller under
        # -ErrorAction Stop still receives all of them.
        $Unread = [System.Collections.Generic.List[string]]::new()
        for ($Index = 0; $Index -lt $Items.Count; $Index++) {
            $Item = $Items[$Index]
            $ItemName = [string]$Item.name
            if ($IsRoot[$Index]) {
                ConvertTo-OERManagementGroup -InputObject $Item -Parent $null
            } elseif ($ParentByName.ContainsKey($ItemName)) {
                ConvertTo-OERManagementGroup -InputObject $Item -Parent $ParentByName[$ItemName]
            } else {
                $Unread.Add($ItemName)
                ConvertTo-OERManagementGroup -InputObject $Item -Parent $null
            }
        }

        if ($Unread.Count -gt 0) {
            $Names = @($Unread | ForEach-Object { "'$_'" }) -join ', '
            $Reason = if ($ParentReadError) {
                "the entity listing failed: $($ParentReadError.Exception.Message)"
            } else {
                'the entity listing (Entities - List) returned no parent for them'
            }
            $ErrorParams = @{
                Message      = [System.Exception]::new("Could not read the parent of $($Unread.Count) management group(s): $Names -- $Reason. Their ParentId, ParentName and ParentDisplayName are empty, which here does not mean that they have no parent.")
                ErrorId      = 'ManagementGroupParentReadFailed'
                Category     = 'ReadError'
                TargetObject = [string[]]$Unread.ToArray()
                Cmdlet       = $PSCmdlet
            }
            if ($ParentReadError) { $ErrorParams.InnerException = $ParentReadError.Exception }
            Write-CmdletError @ErrorParams
        }
    }
}
