function New-OERAdministrativeUnit {
    <#
    .SYNOPSIS
    Creates an Entra ID administrative unit (regular, restricted, or dynamic), idempotently.

    .DESCRIPTION
    Creates an administrative unit through Microsoft Graph. The display name is supplied directly with
    -DisplayName, or composed from -Name (and an optional -Prefix) through the Resolve-OERName naming
    engine using -Template (default '{prefix}_au_{name}').

    -Restricted creates a restricted management administrative unit (isMemberManagementRestricted = true),
    whose member objects can only be managed by administrators scoped to the unit. This property is
    immutable: it can only be set at creation and can never be changed afterwards (Set-OERAdministrativeUnit
    has no parameter for it). -Dynamic creates a dynamic-membership unit evaluated from -MembershipRule;
    -Restricted and -Dynamic may be combined. -HiddenMembership hides the membership from non-members.

    The command is idempotent: when a unit with the resolved display name already exists, the existing unit
    is returned and nothing is created. Output is a tagged Omnicit.EntraRBAC.AdministrativeUnit object.
    Supports -WhatIf and -Confirm.

    .PARAMETER DisplayName
    The exact display name of the administrative unit to create. Used by the ByName parameter set.

    .PARAMETER Name
    The name token used to compose the display name from -Template. Used by the ByTemplate parameter set.

    .PARAMETER Template
    The Resolve-OERName template used with -Name/-Prefix. Defaults to '{prefix}_au_{name}'.

    .PARAMETER Prefix
    Prefix token for -Template. Required when the template contains a {prefix} placeholder; the default
    template always does, so omitting -Prefix with the default template produces a name-resolution error.

    .PARAMETER Description
    Optional description stored on the administrative unit.

    .PARAMETER Restricted
    Create a restricted management administrative unit (isMemberManagementRestricted = true). Immutable
    after creation.

    .PARAMETER Dynamic
    Create a dynamic-membership administrative unit. Requires -MembershipRule.

    .PARAMETER MembershipRule
    The dynamic-membership rule (for example '(user.country -eq "SE")') applied when -Dynamic is set.
    Required with -Dynamic and not valid without it.

    .PARAMETER MembershipRuleProcessingState
    Whether the dynamic-membership rule is evaluated (On) or suspended (Paused). Defaults to On. Only valid
    together with -Dynamic.

    .PARAMETER HiddenMembership
    Set the unit's visibility to HiddenMembership so only members can list other members.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERAdministrativeUnit -DisplayName 'au_exec' -Restricted -Description 'Executive division'
    Creates a restricted management administrative unit, or returns it if it already exists.

    .EXAMPLE
    New-OERAdministrativeUnit -DisplayName 'au_se' -Dynamic -MembershipRule '(user.country -eq "SE")'
    Creates a dynamic administrative unit whose members are evaluated from the rule.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [Parameter(ParameterSetName = 'ByTemplate', Mandatory)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByTemplate')]
        [string]$Template = '{prefix}_au_{name}',

        [Parameter(ParameterSetName = 'ByTemplate')]
        [string]$Prefix,

        [string]$Description,
        [switch]$Restricted,
        [switch]$Dynamic,
        [string]$MembershipRule,

        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState = 'On',

        [switch]$HiddenMembership,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        if ($Dynamic -and -not $MembershipRule) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-Dynamic requires -MembershipRule (the rule that evaluates the unit members).')) `
                -ErrorId 'MembershipRuleRequired' `
                -Category InvalidArgument `
                -TargetObject $(if ($DisplayName) { $DisplayName } else { $Name }) `
                -Cmdlet $PSCmdlet
            return
        }
        if (($MembershipRule -or $PSBoundParameters.ContainsKey('MembershipRuleProcessingState')) -and -not $Dynamic) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-MembershipRule and -MembershipRuleProcessingState are only valid with -Dynamic. To create a dynamic unit add -Dynamic.')) `
                -ErrorId 'MembershipRuleRequiresDynamic' `
                -Category InvalidArgument `
                -TargetObject $(if ($DisplayName) { $DisplayName } else { $Name }) `
                -Cmdlet $PSCmdlet
            return
        }

        $ResolvedName = if ($PSCmdlet.ParameterSetName -eq 'ByTemplate') {
            $Tokens = @{ name = $Name }
            if ($PSBoundParameters.ContainsKey('Prefix')) { $Tokens.prefix = $Prefix }
            try {
                Resolve-OERName -Template $Template -Tokens $Tokens
            } catch {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Failed to resolve an administrative unit name: $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'NameResolutionFailed' `
                    -Category InvalidArgument `
                    -TargetObject $Name `
                    -Cmdlet $PSCmdlet
                return
            }
        } else {
            $DisplayName
        }

        # A throw here is a transport/permission/throttling failure during the idempotency pre-check,
        # NOT evidence the unit is missing. Falling through to the create would attempt to create a
        # duplicate unit against a tenant that is merely throttled, so report the failure and stop
        # instead of proceeding to the create below.
        $ExistingId = try {
            Resolve-OERAdministrativeUnitId -DisplayName $ResolvedName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up administrative unit '$ResolvedName': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'AdministrativeUnitResolveFailed' `
                -Category NotSpecified `
                -TargetObject $ResolvedName `
                -Cmdlet $PSCmdlet
            return
        }
        if ($ExistingId) {
            try {
                $Existing = Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}" -f $ExistingId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            Write-Verbose "[New-OERAdministrativeUnit] Unit '$ResolvedName' already exists ($ExistingId); returning existing."
            ConvertTo-OERAdministrativeUnit -InputObject $Existing
            return
        }

        $Body = @{ displayName = $ResolvedName }
        if ($Description)      { $Body.description = $Description }
        if ($Restricted)       { $Body.isMemberManagementRestricted = $true }
        if ($Dynamic) {
            $Body.membershipType                = 'Dynamic'
            $Body.membershipRule                = $MembershipRule
            $Body.membershipRuleProcessingState = $MembershipRuleProcessingState
        }
        if ($HiddenMembership) { $Body.visibility = 'HiddenMembership' }

        $Kind = if ($Restricted -and $Dynamic) { 'restricted dynamic' }
            elseif ($Restricted) { 'restricted' }
            elseif ($Dynamic) { 'dynamic' }
            else { 'regular' }
        if ($PSCmdlet.ShouldProcess($ResolvedName, "Create $Kind administrative unit")) {
            try {
                $Created = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/directory/administrativeUnits' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERAdministrativeUnit -InputObject $Created
        }
    }
}
