function Get-OERRoleAssignment {
    <#
    .SYNOPSIS
    Lists Azure role assignments at a management group, subscription, resource group, or resource scope.

    .DESCRIPTION
    Reads Microsoft.Authorization/roleAssignments through the ARM API (api-version 2022-04-01) via
    Invoke-OERArmRequest. A scope is required: -Scope (raw ARM id), -Subscription (GUID or display
    name, optionally narrowed with -ResourceGroup), or -ManagementGroup (name or display name).
    Without a filter, every assignment that applies at the scope (direct and inherited) is returned.
    A principal filter (-User, -Group, or -ServicePrincipal; resolved through Microsoft Graph)
    applies $filter=principalId eq '<objectId>', which returns assignments at, above, and below the
    scope for that principal. -AtScope applies $filter=atScope() (assignments at or above the scope,
    excluding children) and cannot be combined with a principal filter. Output objects are tagged
    Omnicit.EntraRBAC.RoleAssignment and expose RoleAssignmentId so they pipe into
    Set-OERRoleAssignment (an in-place description/condition edit) and Remove-OERRoleAssignment.
    Requires an ARM token; authentication is ensured at entry via Initialize-OERAuth -IncludeARM.

    With -ResolveNames, each returned object is additionally enriched with PrincipalDisplayName
    (resolved from PrincipalId via Microsoft Graph) and RoleName (resolved from RoleDefinitionId via
    ARM), and is tagged Omnicit.EntraRBAC.RoleAssignmentResolved so the default table shows
    PrincipalDisplayName/RoleName instead of the raw ids. All id properties are retained. Principal
    names are batch-resolved through Resolve-OERPrincipalName's single getByIds call per page (one
    request for every distinct principal not already cached) rather than one Graph GET per principal.
    Lookups are cached per invocation (assignments commonly share a role and principal), and a
    principal or role that cannot be resolved (deleted, or not readable) falls back to its id so no
    column is blank.

    .PARAMETER Scope
    A raw ARM scope string such as '/subscriptions/{id}/resourceGroups/{rg}'.

    .PARAMETER Subscription
    A subscription GUID or display name. Bound from the pipeline by property name (SubscriptionId).

    .PARAMETER ResourceGroup
    A resource group name narrowing the -Subscription scope. Pipeline by property name.

    .PARAMETER ManagementGroup
    A management group name or display name. Bound from the pipeline by property name
    (ManagementGroupName).

    .PARAMETER ResourceType
    The full resource type (e.g. 'Microsoft.Storage/storageAccounts') that disambiguates -ResourceName
    within the -ResourceGroup. Requires -ResourceName. Pipeline by property name.

    .PARAMETER ResourceName
    A resource name within -Subscription/-ResourceGroup; resolved to the resource's full ARM id so the
    role applies at that single resource. Pipeline by property name.

    .PARAMETER User
    A user principal name or object id whose assignments are listed.

    .PARAMETER Group
    A group display name or object id whose assignments are listed.

    .PARAMETER ServicePrincipal
    A service principal display name or object id whose assignments are listed.

    .PARAMETER AtScope
    Return only assignments at or above the scope (excludes child scopes). Cannot be combined with a
    principal filter.

    .PARAMETER ResolveNames
    Enrich each result with PrincipalDisplayName (from PrincipalId via Graph) and RoleName (from
    RoleDefinitionId via ARM), and switch the default table to show those friendly names. All id
    properties are kept; unresolvable principals or roles fall back to their id.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERRoleAssignment -Subscription 'Prod'
    Lists every role assignment that applies at the Prod subscription.

    .EXAMPLE
    Get-OERRoleAssignment -ManagementGroup 'mg-platform' -User 'anna.berg@contoso.com'
    Lists Anna's role assignments at, above, and below the mg-platform management group.

    .EXAMPLE
    Get-OERRoleAssignment -Subscription 'Prod' -ResolveNames
    Lists the Prod assignments with PrincipalDisplayName and RoleName resolved for readable output.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Scope,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('SubscriptionId')]
        [string]$Subscription,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceGroup,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ManagementGroupName')]
        [string]$ManagementGroup,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceType,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ResourceName,

        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal,
        [switch]$AtScope,
        [switch]$ResolveNames,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM

        # Per-invocation caches so a role definition or principal shared by many assignments is
        # resolved only once (begin-scoped variables are visible to the process block).
        $RoleNameCache      = @{}
        $PrincipalNameCache = @{}
    }
    process {
        try {
            $TargetScope = Resolve-OERScope -Scope $Scope -Subscription $Subscription `
                -ResourceGroup $ResourceGroup -ManagementGroup $ManagementGroup `
                -ResourceType $ResourceType -ResourceName $ResourceName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ScopeTarget = @($Scope, $Subscription, $ManagementGroup, $ResourceGroup, $ResourceType, $ResourceName) | Where-Object { $_ } | Select-Object -First 1
            Write-CmdletError `
                -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                -ErrorId 'InvalidScope' -Category InvalidArgument -TargetObject $ScopeTarget -Cmdlet $PSCmdlet
            return
        }

        $PrincipalRequested = [bool]($User -or $Group -or $ServicePrincipal)
        if ($AtScope -and $PrincipalRequested) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-AtScope cannot be combined with a principal filter (-User, -Group or -ServicePrincipal).')) `
                -ErrorId 'AmbiguousFilter' -Category InvalidArgument -TargetObject $TargetScope -Cmdlet $PSCmdlet
            return
        }

        $Filter = $null
        if ($PrincipalRequested) {
            try {
                $Principal = Resolve-OERPrincipal -User $User -Group $Group -ServicePrincipal $ServicePrincipal
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PrincipalTarget = @($User, $Group, $ServicePrincipal) | Where-Object { $_ } | Select-Object -First 1
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'PrincipalNotFound' -Category ObjectNotFound -TargetObject $PrincipalTarget -Cmdlet $PSCmdlet
                return
            }
            $Filter = [uri]::EscapeDataString("principalId eq '$($Principal.PrincipalId)'")
        } elseif ($AtScope) {
            $Filter = 'atScope()'
        }

        $Path = "$TargetScope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
        if ($Filter) { $Path += "&`$filter=$Filter" }

        try {
            $Response = Invoke-OERArmRequest -Path $Path -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        $Items = @($Response.value)
        if (-not $ResolveNames) {
            foreach ($Item in $Items) {
                ConvertTo-OERRoleAssignment -InputObject $Item
            }
            return
        }

        $Assignments = foreach ($Item in $Items) { ConvertTo-OERRoleAssignment -InputObject $Item }

        # -- Batch-resolve PrincipalDisplayName for every distinct principal on this page that is not
        # already cached from an earlier pipeline item, through a single getByIds call instead of one
        # Graph GET per principal (CONS-principal-name-resolution-has-two-owners). -PreferDisplayName
        # keeps the result a displayName even for a user principal -- never the UPN, which is a
        # different field with a different job (Get-OERInventory's 'principal'). --
        $NeedPrincipalIds = @(
            $Assignments |
                Where-Object { $_.PrincipalId -and -not $PrincipalNameCache.ContainsKey($_.PrincipalId) } |
                Select-Object -ExpandProperty PrincipalId -Unique
        )
        if ($NeedPrincipalIds.Count -gt 0) {
            $Resolved = Resolve-OERPrincipalName -Id $NeedPrincipalIds -PreferDisplayName
            foreach ($Key in $Resolved.Keys) { $PrincipalNameCache[$Key] = $Resolved[$Key] }
        }

        foreach ($Assignment in $Assignments) {
            # -- Resolve RoleName from the full ARM role definition id (cached) --
            $RoleDefId = $Assignment.RoleDefinitionId
            if ($RoleDefId -and -not $RoleNameCache.ContainsKey($RoleDefId)) {
                $RoleName = $null
                try {
                    $RoleDef  = Invoke-OERArmRequest -Path "$RoleDefId`?api-version=2022-04-01"
                    $RoleName = [string]$RoleDef.properties.roleName
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    Write-Verbose "[Get-OERRoleAssignment] Could not resolve role name for '$RoleDefId': $($PSItem.Exception.Message)"
                }
                if (-not $RoleName) { $RoleName = ($RoleDefId -split '/')[-1] }
                $RoleNameCache[$RoleDefId] = $RoleName
            }

            $PrincipalId = $Assignment.PrincipalId
            $DisplayName = if ($PrincipalId -and $PrincipalNameCache.ContainsKey($PrincipalId)) {
                $PrincipalNameCache[$PrincipalId]
            } else {
                $PrincipalId
            }

            $Assignment | Add-Member -NotePropertyName 'RoleName' -NotePropertyValue $RoleNameCache[$RoleDefId]
            $Assignment | Add-Member -NotePropertyName 'PrincipalDisplayName' -NotePropertyValue $DisplayName
            $Assignment.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleAssignmentResolved')
            $Assignment
        }
    }
}
