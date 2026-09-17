function New-OERGroup {
    <#
    .SYNOPSIS
    Creates an Entra ID security group (static, role-assignable, or dynamic), idempotently.

    .DESCRIPTION
    Creates a security-enabled Entra ID group through Microsoft Graph. The display name is supplied
    directly with -DisplayName, or composed from -Area and -Tier through the Resolve-OERName naming
    engine using -Template (default 'role_sec_{area}_{tier}').

    The group's membership kind is selected with two mutually exclusive switches that mirror Entra ID:
    -RoleAssignable creates a group that can hold directory roles (isAssignableToRole); -Dynamic
    creates a dynamic-membership group whose members are evaluated from -MembershipRule. Entra ID does
    not allow a group to be both role-assignable and dynamic, so the two switches cannot be combined.
    With neither switch the group is a plain static (assigned) security group.

    PIM for Groups is NOT a creation-time property: a group becomes PIM-managed when you grant the first
    eligible assignment with Add-OERGroupEligibility, which works on a static or role-assignable group
    (a role-assignable, PIM-managed group is the common privileged pattern). Dynamic groups cannot have
    eligible members because their membership is rule-driven.

    The command is idempotent: when a group with the resolved display name already exists, the existing
    group is returned and no group is created. Output is a tagged Omnicit.EntraRBAC.Group object.
    Supports -WhatIf and -Confirm.

    .PARAMETER DisplayName
    The exact display name of the group to create. Used by the ByName parameter set.

    .PARAMETER Area
    The canonical area token (e.g. identity, security) used to compose the display name from -Template.

    .PARAMETER Tier
    The tier token used with -Area to compose the display name. Defaults to administrator.

    .PARAMETER Template
    The Resolve-OERName template used with -Area/-Tier. Defaults to 'role_sec_{area}_{tier}'.

    .PARAMETER RoleAssignable
    Create a role-assignable security group (isAssignableToRole) so it can hold Entra directory roles.
    Mutually exclusive with -Dynamic. Such a group can later be PIM-managed via Add-OERGroupEligibility.

    .PARAMETER Dynamic
    Create a dynamic-membership security group. Requires -MembershipRule and is mutually exclusive with
    -RoleAssignable. Members are evaluated by Entra ID from the supplied rule.

    .PARAMETER MembershipRule
    The dynamic-membership rule (e.g. '(user.department -eq "IT")') applied when -Dynamic is set.
    Required with -Dynamic and not valid without it.

    .PARAMETER MembershipRuleProcessingState
    Whether the dynamic-membership rule is evaluated (On) or suspended (Paused). Defaults to On. Only
    valid together with -Dynamic.

    .PARAMETER Description
    Optional description stored on the group.

    .PARAMETER MailNickname
    Optional mail nickname. When omitted it is derived from the resolved display name (non-alphanumeric
    characters removed).

    .PARAMETER AdministrativeUnit
    Optional administrative unit (id or display name) to create the group inside. When supplied the group
    is created through the administrative unit's members endpoint (required for restricted management units)
    rather than the top-level groups endpoint. If the group already exists it is returned and not
    re-parented (a warning is emitted).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERGroup -DisplayName 'role_sec_identity_administrator' -RoleAssignable -Description 'Identity admins'
    Creates a role-assignable security group (ready to be PIM-managed with Add-OERGroupEligibility), or
    returns it if it already exists.

    .EXAMPLE
    New-OERGroup -Area identity -Tier administrator
    Composes the name 'role_sec_identity_administrator' from the default template and creates a static
    security group.

    .EXAMPLE
    New-OERGroup -DisplayName 'dyn_all_engineers' -Dynamic -MembershipRule '(user.department -eq "Engineering")'
    Creates a dynamic-membership security group whose members are evaluated from the rule.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [Parameter(ParameterSetName = 'ByArea', Mandatory)]
        [string]$Area,

        [Parameter(ParameterSetName = 'ByArea')]
        [string]$Tier = 'administrator',

        [Parameter(ParameterSetName = 'ByArea')]
        [string]$Template = 'role_sec_{area}_{tier}',

        [switch]$RoleAssignable,

        [switch]$Dynamic,

        [string]$MembershipRule,

        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState = 'On',

        [string]$Description,
        [string]$MailNickname,
        [string]$AdministrativeUnit,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # Validate the membership-kind switches up front (before any Graph call). Entra ID does not
        # allow a role-assignable group to be dynamic, and a dynamic group needs a rule.
        if ($RoleAssignable -and $Dynamic) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-RoleAssignable and -Dynamic cannot be combined: Entra ID does not allow a role-assignable group to use dynamic membership.')) `
                -ErrorId 'RoleAndDynamicExclusive' `
                -Category InvalidArgument `
                -TargetObject $(if ($DisplayName) { $DisplayName } else { $Area }) `
                -Cmdlet $PSCmdlet
            return
        }
        if ($Dynamic -and -not $MembershipRule) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-Dynamic requires -MembershipRule (the rule that evaluates the group members).')) `
                -ErrorId 'MembershipRuleRequired' `
                -Category InvalidArgument `
                -TargetObject $(if ($DisplayName) { $DisplayName } else { $Area }) `
                -Cmdlet $PSCmdlet
            return
        }
        if (($MembershipRule -or $PSBoundParameters.ContainsKey('MembershipRuleProcessingState')) -and -not $Dynamic) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-MembershipRule and -MembershipRuleProcessingState are only valid with -Dynamic. To create a dynamic group add -Dynamic.')) `
                -ErrorId 'MembershipRuleRequiresDynamic' `
                -Category InvalidArgument `
                -TargetObject $(if ($DisplayName) { $DisplayName } else { $Area }) `
                -Cmdlet $PSCmdlet
            return
        }

        $ResolvedName = if ($PSCmdlet.ParameterSetName -eq 'ByArea') {
            try {
                Resolve-OERName -Template $Template -Tokens @{ area = $Area; tier = $Tier }
            } catch {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Failed to resolve a group name: $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'NameResolutionFailed' `
                    -Category InvalidArgument `
                    -TargetObject $Area `
                    -Cmdlet $PSCmdlet
                return
            }
        } else {
            $DisplayName
        }

        # Idempotency: return the existing group on a name match. A throw here is a
        # transport/permission/throttling failure during the pre-check, NOT evidence the group is
        # missing. Falling through to the create would attempt to create a duplicate group against
        # a tenant that is merely throttled, so report the failure and stop instead of proceeding
        # to the create below.
        $ExistingId = try {
            Resolve-OERGroupId -DisplayName $ResolvedName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up group '$ResolvedName': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'GroupResolveFailed' `
                -Category NotSpecified `
                -TargetObject $ResolvedName `
                -Cmdlet $PSCmdlet
            return
        }
        if ($ExistingId) {
            try {
                $Existing = Invoke-OERGraphRequest -Uri ("v1.0/groups/{0}" -f $ExistingId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($AdministrativeUnit) {
                Write-Warning "Group '$ResolvedName' already exists ($ExistingId); it was not re-parented into administrative unit '$AdministrativeUnit'."
            }
            Write-Verbose "[New-OERGroup] Group '$ResolvedName' already exists ($ExistingId); returning existing."
            ConvertTo-OERGroup -InputObject $Existing
            return
        }

        # Resolve the target administrative unit (if any) before building the create request.
        $AuId = $null
        if ($AdministrativeUnit) {
            $AuParams = if ($AdministrativeUnit -as [guid]) { @{ Id = $AdministrativeUnit } } else { @{ DisplayName = $AdministrativeUnit } }
            # A throw here is a transport/permission/throttling failure, NOT evidence the unit is
            # missing. Falling through to AdministrativeUnitNotFound would misreport a unit that
            # exists, so report the resolve failure and stop instead of proceeding to the create.
            try {
                $AuId = Resolve-OERAdministrativeUnitId @AuParams
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "Failed to look up administrative unit '$AdministrativeUnit': $($PSItem.Exception.Message) The group was NOT created.")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'AdministrativeUnitResolveFailed' `
                    -Category NotSpecified `
                    -TargetObject $AdministrativeUnit `
                    -Cmdlet $PSCmdlet
                return
            }
            if (-not $AuId) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No administrative unit found for '$AdministrativeUnit'.")) `
                    -ErrorId 'AdministrativeUnitNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $AdministrativeUnit `
                    -Cmdlet $PSCmdlet
                return
            }
        }

        $Nick = if ($MailNickname) { $MailNickname } else { ($ResolvedName -replace '[^A-Za-z0-9._-]', '') }
        $Body = @{
            displayName     = $ResolvedName
            mailEnabled     = $false
            mailNickname    = $Nick
            securityEnabled = $true
        }
        if ($RoleAssignable) { $Body.isAssignableToRole = $true }
        if ($Dynamic) {
            $Body.groupTypes                    = @('DynamicMembership')
            $Body.membershipRule                = $MembershipRule
            $Body.membershipRuleProcessingState = $MembershipRuleProcessingState
        }
        if ($Description) { $Body.description = $Description }

        $Kind = if ($RoleAssignable) { 'role-assignable' } elseif ($Dynamic) { 'dynamic' } else { 'static' }
        $Target = if ($AuId) { "$ResolvedName (in administrative unit $AuId)" } else { $ResolvedName }
        if ($PSCmdlet.ShouldProcess($Target, "Create $Kind security group")) {
            try {
                if ($AuId) {
                    $Body['@odata.type'] = '#microsoft.graph.group'
                    $Created = Invoke-OERGraphRequest -Method POST -Uri ("v1.0/directory/administrativeUnits/{0}/members" -f $AuId) -Body $Body
                } else {
                    $Created = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/groups' -Body $Body
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERGroup -InputObject $Created
        }
    }
}
