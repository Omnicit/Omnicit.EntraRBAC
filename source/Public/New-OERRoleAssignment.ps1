function New-OERRoleAssignment {
    <#
    .SYNOPSIS
    Creates an Azure role assignment for a user, group, or service principal at any scope.

    .DESCRIPTION
    Creates a Microsoft.Authorization/roleAssignments resource through the ARM API (api-version
    2022-04-01) via Invoke-OERArmRequest. The assignment name is a new client-generated GUID and the
    request body follows the verified contract: properties.roleDefinitionId is the FULL ARM resource
    id (resolved from a role display name, GUID, or full id by Resolve-OERRoleDefinitionId at the
    target scope), properties.principalId is taken from -PrincipalId or resolved from the friendly
    -User/-Group/-ServicePrincipal value, and properties.principalType is sent whenever it is known
    (it avoids replication-delay failures for freshly created principals -- ARM's documented
    mitigation for assigning to a principal that has not yet replicated, which is precisely the
    canonical use of a raw -PrincipalId: a script that just created a managed identity or service
    principal). When the principal was resolved via -User/-Group/-ServicePrincipal, its type is
    known automatically; when supplied as a raw -PrincipalId (no Graph lookup happens on that path),
    pass -PrincipalType explicitly to still get the mitigation, or omit it and let ARM resolve the
    type itself. Exactly one principal source and exactly one scope source (-Scope, -Subscription
    optionally with -ResourceGroup, or -ManagementGroup) must be supplied. An existing identical
    assignment surfaces as the ARM 409 RoleAssignmentExists error. Supports -WhatIf/-Confirm.
    Requires an ARM token; authentication is ensured at entry via Initialize-OERAuth -IncludeARM.
    Principal resolution runs BEFORE scope resolution, so a call supplying both an unresolvable
    principal and an invalid scope reports the principal error, not InvalidScope.

    Because -PrincipalId binds from the pipeline by property name and takes precedence over the
    friendly parameters, supplying -User, -Group or -ServicePrincipal while piping objects that carry
    their own PrincipalId (any assignment-shaped object, for example Get-OERRoleAssignment output) is
    rejected with a non-terminating AmbiguousPrincipal error rather than silently granting the role to
    each piped item's own principal. Piping a role definition, subscription, resource group or
    resource alongside a named principal is unaffected -- none of those shapes carries a PrincipalId.

    .PARAMETER Role
    The role to assign: display name (e.g. 'Reader'), role definition GUID, or full ARM id. Bound
    from the pipeline by property name (RoleDefinitionId), so Get-OERRoleDefinition pipes in.
    Tab-completion offers the five curated common Azure RBAC roles; any other built-in or custom role
    name is still accepted.

    .PARAMETER PrincipalId
    The object id (GUID) of the principal to assign the role to. Pipeline by property name; takes
    precedence over -User/-Group/-ServicePrincipal. To look up a principal by name, use -User,
    -Group, or -ServicePrincipal instead.

    .PARAMETER PrincipalType
    The principal type (User, Group, ServicePrincipal, ForeignGroup, or Device) to send alongside a
    raw -PrincipalId, so ARM's replication-delay mitigation still applies when the principal id is
    supplied directly rather than resolved via -User/-Group/-ServicePrincipal (which already
    determines the type automatically). When supplied, -PrincipalType always wins over an
    automatically resolved type. The accepted set also carries the historical ARM spellings
    (Unknown, DirectoryRoleTemplate, Application, MSI, DirectoryObjectOrGroup, Everyone) because the
    parameter binds from the pipeline: a piped record carrying one of those must round-trip rather
    than fail validation and drop out of the pipeline unnoticed.

    .PARAMETER User
    A user principal name or user object id to assign the role to.

    .PARAMETER Group
    A group display name or group object id to assign the role to.

    .PARAMETER ServicePrincipal
    A service principal display name or service principal OBJECT id (a GUID is treated as the object
    id, never the appId) to assign the role to.

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

    .PARAMETER Description
    Optional description stored on the role assignment.

    .PARAMETER Condition
    Optional ABAC condition expression constraining the assignment.

    .PARAMETER ConditionVersion
    The condition syntax version. Only '2.0' is accepted. Defaults to '2.0' when -Condition is
    supplied; invalid without -Condition.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERRoleAssignment -Role 'Reader' -User 'anna.berg@contoso.com' -Subscription 'Prod'
    Assigns the Reader role to Anna at the Prod subscription scope.

    .EXAMPLE
    Get-OERRoleDefinition -Role 'Contributor' | New-OERRoleAssignment -Group 'role_sec_contributors' -ManagementGroup 'mg-platform'
    Assigns Contributor to a group at a management group scope via the pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal,

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

        [string]$Description,
        [string]$Condition,
        # '2.0' is the only condition syntax version ARM currently accepts on create. If Microsoft
        # ships a 3.0, add it to this list.
        [ValidateSet('2.0')]
        [string]$ConditionVersion,
        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        # These cmdlets have no PositionalBinding=$false, so every parameter is implicitly
        # positional in declaration order.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$PrincipalId,

        # '' is deliberately part of the set, not just the four real principal types: this parameter
        # is ValueFromPipelineByPropertyName, and both ConvertTo-OERRoleAssignment and
        # ConvertTo-OEREligibleRoleAssignment cast PrincipalType via [string]$P.principalType, which
        # turns an absent/null wire value into '' -- a piped object with that empty PrincipalType
        # property is bound (not skipped; a property is only skipped when ABSENT, never when present
        # but empty), and would fail ValidateSet on every such pipe without '' in the set. Empirically
        # confirmed: this reproduces the ConvertTo-OEREligibleRoleAssignment | New-OERRoleAssignment
        # pipe test failing with ParameterBindingValidationException before this fix. The empty value
        # is harmless downstream -- "if ($PrincipalType) { ... }" already treats '' as not-supplied.
        #
        # The set is deliberately WIDER than the five types ARM documents today. Because the parameter
        # is ValueFromPipelineByPropertyName and fed by converters, a closed set turns an unexpected
        # value into a per-item BINDING failure: that item is silently skipped while the rest of the
        # pipeline continues, so a tenant carrying a legacy principalType would lose assignments
        # without an obvious cause. Unknown, DirectoryRoleTemplate, Application, MSI,
        # DirectoryObjectOrGroup and Everyone are the historical PrincipalType values ARM has emitted
        # on read; they are accepted so a piped record round-trips instead of dropping. ARM itself
        # remains the authority on what it will accept on write -- a value it no longer honors comes
        # back as an ARM error naming the field, which is a far better diagnostic than a vanished
        # pipeline item.
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('User', 'Group', 'ServicePrincipal', 'ForeignGroup', 'Device',
            'Unknown', 'DirectoryRoleTemplate', 'Application', 'MSI', 'DirectoryObjectOrGroup', 'Everyone', '')]
        [string]$PrincipalType
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        # Cheap, purely local parameter-shape checks run BEFORE any principal resolution: resolving a
        # friendly -User/-Group/-ServicePrincipal touches Graph, and a caller who only fat-fingered
        # -ConditionVersion should get instant local feedback rather than pay for (or fail on) a
        # network round-trip that has nothing to do with the actual mistake.
        if ($ConditionVersion -and -not $Condition) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-ConditionVersion requires -Condition.')) `
                -ErrorId 'ConditionVersionWithoutCondition' -Category InvalidArgument -TargetObject $ConditionVersion -Cmdlet $PSCmdlet
            return
        }

        # -PrincipalId binds from the pipeline by property name and Resolve-OERPrincipalOrId gives it
        # precedence over -User/-Group/-ServicePrincipal, so a pipe of assignment-shaped objects --
        # every one of which carries its own PrincipalId -- would silently ignore the named principal
        # and grant the role to each piped item's OWN principal instead. Handing privileged access to
        # a principal the caller never named is refused, not warned about: the same AmbiguousPrincipal
        # treatment Remove-OERGroupEligibility and Remove-OERAdministrativeUnitScopedRole already give
        # the identical collision.
        #
        # The test is deliberately narrower than the one in those two cmdlets, because this cmdlet's
        # pipeline is POLYMORPHIC: a role definition, subscription, resource group or resource pipes in
        # to supply the ROLE or the SCOPE, and pairing one of those with a named principal is a
        # documented, intended use (see the second .EXAMPLE). None of those shapes carries a
        # PrincipalId, so the guard keys on the piped item's OWN PrincipalId and fires only on a
        # genuine collision. That value is read through $PSItem, which the process block populates for
        # every advanced function independently of any ValueFromPipeline parameter: PowerShell freezes
        # an explicitly bound parameter for the rest of the pipeline, so the $PrincipalId parameter
        # variable can never reveal the divergence -- $PSItem is the only place the piped item's own
        # principal is observable.
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $PSItem.PrincipalId -and
            ($PSBoundParameters.ContainsKey('User') -or $PSBoundParameters.ContainsKey('Group') -or
                $PSBoundParameters.ContainsKey('ServicePrincipal'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new("A principal was supplied by name while objects carrying their own PrincipalId '$($PSItem.PrincipalId)' are being piped in. The piped -PrincipalId takes precedence, so the named principal would be ignored and the role granted to each piped item's own principal instead. Supply either the named principal or the pipeline, not both.")) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $PSItem.PrincipalId -Cmdlet $PSCmdlet
            return
        }

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -ServicePrincipal $ServicePrincipal
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }

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
        Write-Verbose "[New-OERRoleAssignment] Target scope: '$TargetScope'."
        Write-Verbose "[New-OERRoleAssignment] Resolved principal to '$($Principal.PrincipalId)'."

        try {
            $RoleDefinitionId = Resolve-OERRoleDefinitionId -Role $Role -Scope $TargetScope
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[New-OERRoleAssignment] Resolved role '$Role' to '$RoleDefinitionId'."

        $Body = @{
            properties = @{
                roleDefinitionId = $RoleDefinitionId
                principalId      = $Principal.PrincipalId
            }
        }
        # principalType is sent whenever it is known (it avoids replication-delay failures for freshly
        # created principals -- exactly the case a raw -PrincipalId is used for, e.g. right after
        # creating a managed identity or service principal). An explicit -PrincipalType always wins;
        # otherwise fall back to the type Resolve-OERPrincipalOrId resolved (empty for a raw id, since
        # that path performs no Graph lookup) -- ARM resolves principalType itself if both are absent.
        if ($PrincipalType) { $Body.properties.principalType = $PrincipalType }
        elseif ($Principal.PrincipalType) { $Body.properties.principalType = $Principal.PrincipalType }
        if ($Description) { $Body.properties.description = $Description }
        if ($Condition) {
            $Body.properties.condition = $Condition
            $Body.properties.conditionVersion = if ($ConditionVersion) { $ConditionVersion } else { '2.0' }
        }

        # Name the principal that will ACTUALLY be acted on, not merely the one the operator typed.
        # -PrincipalId shares a parameter set with the friendly parameters and Resolve-OERPrincipalOrId
        # lets -PrincipalId win, so it must be tested FIRST here too (see Remove-OEREligibleRoleAssignment).
        $PrincipalLabel = if ($PrincipalId) { $Principal.PrincipalId }
        elseif ($User) { $User }
        elseif ($Group) { $Group }
        elseif ($ServicePrincipal) { $ServicePrincipal }
        else { $Principal.PrincipalId }
        $PrincipalTypeLabel = if ($PrincipalType) { $PrincipalType } elseif ($Principal.PrincipalType) { $Principal.PrincipalType } else { 'principal' }
        $Target = "role '$Role' to $PrincipalTypeLabel '$PrincipalLabel' at scope '$TargetScope'"
        if ($PSCmdlet.ShouldProcess($Target, 'Create Azure role assignment')) {
            $AssignmentName = [guid]::NewGuid().ToString()
            try {
                $Response = Invoke-OERArmRequest -Method PUT `
                    -Path "$TargetScope/providers/Microsoft.Authorization/roleAssignments/$AssignmentName`?api-version=2022-04-01" `
                    -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERRoleAssignment -InputObject $Response
        }
    }
}
