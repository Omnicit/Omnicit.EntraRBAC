function Get-OERRoleDefinition {
    <#
    .SYNOPSIS
    Lists Azure role definitions or gets one role definition by name, GUID, or full ARM id.

    .DESCRIPTION
    Reads Microsoft.Authorization/roleDefinitions through the ARM API (api-version 2022-04-01) via
    Invoke-OERArmRequest. Without a scope parameter the tenant-level collection is used; -Scope,
    -Subscription (optionally with -ResourceGroup), or -ManagementGroup narrow the scope via
    Resolve-OERScope. -Role accepts the exact role display name (resolved with the documented
    $filter=roleName eq '...' filter), a role definition GUID, or a full ARM id (both fetched
    directly). -Custom lists only custom roles ($filter=type eq 'CustomRole') and cannot be combined
    with -Role. Output objects are tagged Omnicit.EntraRBAC.RoleDefinition and expose
    RoleDefinitionId so they pipe into New-OERRoleAssignment. Requires an ARM token; authentication
    is ensured at entry via Initialize-OERAuth -IncludeARM.

    .PARAMETER Role
    The role display name (e.g. 'Reader'), role definition GUID, or full ARM id. Tab-completion
    offers the five curated common Azure RBAC roles; any other built-in or custom role name is still
    accepted.

    .PARAMETER Custom
    List only custom role definitions. Cannot be combined with -Role.

    .PARAMETER Scope
    A raw ARM scope string. One of -Scope/-Subscription/-ManagementGroup may be supplied; when none
    is, the tenant-level collection is read.

    .PARAMETER Subscription
    A subscription GUID or display name to scope the query.

    .PARAMETER ResourceGroup
    A resource group name narrowing the -Subscription scope. Pipeline by property name.

    .PARAMETER ManagementGroup
    A management group name or display name to scope the query.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERRoleDefinition -Role 'User Access Administrator'
    Gets the built-in User Access Administrator role definition.

    .EXAMPLE
    Get-OERRoleDefinition -Custom -Subscription 'Prod'
    Lists the custom roles visible at the Prod subscription scope.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [switch]$Custom,

        [string]$Scope,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceGroup,

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
        if ($Custom -and $Role) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-Custom cannot be combined with -Role.')) `
                -ErrorId 'AmbiguousFilter' -Category InvalidArgument -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }

        $TargetScope = ''
        if ($Scope -or $Subscription -or $ResourceGroup -or $ManagementGroup) {
            try {
                $TargetScope = Resolve-OERScope -Scope $Scope -Subscription $Subscription `
                    -ResourceGroup $ResourceGroup -ManagementGroup $ManagementGroup
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $ScopeTarget = @($Scope, $Subscription, $ManagementGroup, $ResourceGroup) | Where-Object { $_ } | Select-Object -First 1
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $ScopeTarget -Cmdlet $PSCmdlet
                return
            }
        }
        $Base = "$TargetScope/providers/Microsoft.Authorization/roleDefinitions"

        if ($Role -like '*/providers/Microsoft.Authorization/roleDefinitions/*') {
            $Path = "$Role`?api-version=2022-04-01"
        } elseif (Test-OERGuid -Value $Role) {
            $Path = "$Base/$Role`?api-version=2022-04-01"
        } else {
            $Path = $null
        }

        if ($Path) {
            try {
                $Response = Invoke-OERArmRequest -Path $Path
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERRoleDefinition -InputObject $Response
            return
        }

        $ListPath = "$Base`?api-version=2022-04-01"
        if ($Role) {
            $Escaped = $Role.Replace("'", "''")
            $ListPath += "&`$filter=$([uri]::EscapeDataString("roleName eq '$Escaped'"))"
        } elseif ($Custom) {
            $ListPath += "&`$filter=$([uri]::EscapeDataString("type eq 'CustomRole'"))"
        }

        try {
            $Response = if ($Role) {
                Invoke-OERArmRequest -Path $ListPath
            } else {
                Invoke-OERArmRequest -Path $ListPath -All
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        $Items = @($Response.value)
        if ($Role -and $Items.Count -eq 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Role definition '$Role' was not found$(if ($TargetScope) { " at scope '$TargetScope'" }). Run Get-OERRoleDefinition$(if ($TargetScope) { " -Scope '$TargetScope'" }) without -Role to list the roles available there, or supply the role definition GUID or its full ARM id.")) `
                -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }
        foreach ($Item in $Items) {
            ConvertTo-OERRoleDefinition -InputObject $Item
        }
    }
}
