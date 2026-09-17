function Set-OERAdministrativeUnit {
    <#
    .SYNOPSIS
    Updates the editable properties of an existing Entra ID administrative unit.

    .DESCRIPTION
    Patches an existing administrative unit identified by -AdministrativeUnit. Only the supplied
    properties are sent: -NewDisplayName, -Description, -Visibility, -MembershipRule,
    -MembershipRuleProcessingState, and -MembershipType. At least one updatable property must be
    supplied or a non-terminating NothingToUpdate error is emitted. A unit that cannot be resolved
    produces a non-terminating AdministrativeUnitNotFound error.

    Converting an assigned unit to Dynamic requires a membership rule: when -MembershipType Dynamic is
    supplied without -MembershipRule and the live unit has no rule of its own, a non-terminating
    MembershipRuleRequired error is emitted and no PATCH is sent. When both are supplied they travel in
    the same PATCH, so the unit is never momentarily dynamic with no rule. Changing -MembershipType emits
    a warning before the PATCH: Microsoft Graph documents that the existing membership might change based
    on the rule supplied for dynamic membership, and on a dynamic unit the rule owns the membership --
    members can no longer be added or removed manually at all.

    Microsoft Graph documents administrativeUnit.visibility as either null (public) or HiddenMembership;
    'Public' is not a REST value, so -Visibility Public is translated to a JSON null, which is what
    actually reverts a hidden unit to public.

    The restricted-management flag (isMemberManagementRestricted) is immutable in Microsoft Graph and can
    only be set at creation with New-OERAdministrativeUnit -Restricted; there is intentionally no parameter
    for it here. After the PATCH the updated unit is re-read and returned as a tagged
    Omnicit.EntraRBAC.AdministrativeUnit object. Supports -WhatIf and -Confirm.

    .PARAMETER AdministrativeUnit
    The administrative unit to update, given as either its object id (GUID) or its display name. Binds
    from the pipeline by property name, and still accepts the historical -Id, -AdministrativeUnitId and
    -DisplayName parameter names as aliases, so a name-only or id-only object pipes in unchanged.

    .PARAMETER NewDisplayName
    New display name to rename the administrative unit to. Distinct from -AdministrativeUnit (or its
    -DisplayName alias), which only locates the existing unit.

    .PARAMETER Description
    New description for the administrative unit.

    .PARAMETER Visibility
    New visibility for the administrative unit: HiddenMembership to hide members from nonmembers, or
    Public to revert to a publicly listed membership (sent as a JSON null, which is how Microsoft Graph
    represents a public unit).

    .PARAMETER MembershipRule
    New dynamic-membership rule. Only effective on a dynamic administrative unit.

    .PARAMETER MembershipRuleProcessingState
    Processing state for the dynamic-membership rule: On or Paused.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER MembershipType
    Membership type for the administrative unit: Assigned for manually managed members, or Dynamic for
    rule-driven membership. Converting to Dynamic requires a membership rule, either supplied through
    -MembershipRule in the same call or already present on the unit. Changing this can change the unit's
    existing membership, so the cmdlet warns before sending the PATCH.

    .EXAMPLE
    Set-OERAdministrativeUnit -AdministrativeUnit 'au_hr' -Description 'Human Resources unit'
    Updates the description of the named administrative unit and returns the refreshed object.

    .EXAMPLE
    Set-OERAdministrativeUnit -AdministrativeUnit 'au_hr' -NewDisplayName 'au_hr_emea'
    Renames the administrative unit from au_hr to au_hr_emea.

    .EXAMPLE
    Set-OERAdministrativeUnit -AdministrativeUnit 'au_hr' -MembershipType 'Dynamic' -MembershipRule '(user.department -eq "HR")'
    Converts the assigned unit to a dynamic unit and sets its membership rule in a single PATCH.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # AdministrativeUnitId precedes Id/DisplayName so a piped AdministrativeUnitMember object binds
        # the parent unit's id, not the member's own Id/DisplayName, during ValueFromPipelineByPropertyName
        # alias resolution.
        [Alias('AdministrativeUnitId', 'Id', 'DisplayName')]
        [string]$AdministrativeUnit,

        [string]$NewDisplayName,

        [string]$Description,

        [ValidateSet('Public', 'HiddenMembership')]
        [string]$Visibility,

        [string]$MembershipRule,

        [ValidateSet('On', 'Paused')]
        [string]$MembershipRuleProcessingState,

        [string]$TenantId,

        # Declared LAST: this module has no Position attributes, so declaration order is positional
        # binding order and inserting a parameter mid-block silently re-binds existing calls.
        [ValidateSet('Assigned', 'Dynamic')]
        [string]$MembershipType
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Body = @{}
        if ($PSBoundParameters.ContainsKey('NewDisplayName'))                { $Body.displayName = $NewDisplayName }
        if ($PSBoundParameters.ContainsKey('Description'))                   { $Body.description = $Description }
        # Microsoft Graph documents visibility as null (public) or 'HiddenMembership'; 'Public' is not a
        # REST value. The ValidateSet keeps 'Public' for back-compat and it is translated to the JSON
        # null that actually clears the property. The key is still present, so the NothingToUpdate
        # guard below counts it.
        if ($PSBoundParameters.ContainsKey('Visibility'))                    { $Body.visibility = $(if ($Visibility -eq 'Public') { $null } else { $Visibility }) }
        if ($PSBoundParameters.ContainsKey('MembershipRule'))                { $Body.membershipRule = $MembershipRule }
        if ($PSBoundParameters.ContainsKey('MembershipRuleProcessingState')) { $Body.membershipRuleProcessingState = $MembershipRuleProcessingState }
        if ($PSBoundParameters.ContainsKey('MembershipType'))                { $Body.membershipType = $MembershipType }

        if ($Body.Count -eq 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No updatable property was supplied. Pass at least one of -NewDisplayName, -Description, -Visibility, -MembershipRule, -MembershipRuleProcessingState, or -MembershipType.')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }

        # A throw here is a transport/permission/throttling failure, NOT a missing unit. Reporting it as
        # AdministrativeUnitNotFound would send the operator hunting for a unit that exists, so the two
        # outcomes are reported separately (mirrors Get-OERAccessReviewInstance's definition handling).
        # Resolve-OERAdministrativeUnitId has no GUID short-circuit of its own, so the dispatch happens
        # here: a canonical GUID goes to -Id (no Graph call), anything else goes to -DisplayName.
        $AuId = try {
            if (Test-OERGuid -Value $AdministrativeUnit) {
                Resolve-OERAdministrativeUnitId -Id $AdministrativeUnit
            } else {
                Resolve-OERAdministrativeUnitId -DisplayName $AdministrativeUnit
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up administrative unit '$AdministrativeUnit': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'AdministrativeUnitResolveFailed' `
                -Category NotSpecified `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }
        if (-not $AuId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No administrative unit found to update for the supplied id/display name.')) `
                -ErrorId 'AdministrativeUnitNotFound' `
                -Category ObjectNotFound `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }

        # A dynamic unit without a membership rule is an invalid state. When the caller converts to
        # Dynamic without supplying a rule, the live unit must already carry one -- otherwise fail here
        # with an actionable error instead of letting Graph reject the PATCH with a vaguer message.
        # Both values go in the SAME PATCH below; the unit is never momentarily dynamic with no rule.
        if ($MembershipType -eq 'Dynamic' -and -not $PSBoundParameters.ContainsKey('MembershipRule')) {
            $LiveUnit = $null
            try {
                $LiveUnit = Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}" -f $AuId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            # Graph returns a hashtable -- dot-access the key directly, never via PSObject.Properties.
            if (-not $LiveUnit.membershipRule) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Administrative unit '$AuId' has no membership rule, so it cannot be converted to a dynamic unit. Supply -MembershipRule with -MembershipType Dynamic.")) `
                    -ErrorId 'MembershipRuleRequired' `
                    -Category InvalidArgument `
                    -TargetObject $AuId `
                    -Cmdlet $PSCmdlet
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($AuId, 'Update administrative unit properties')) {
            # Changing the membership type is not a metadata edit: Microsoft Graph documents that the
            # existing membership might change based on the rule supplied for dynamic membership, and a
            # dynamic unit's members can no longer be added or removed manually at all. Warn loudly (the
            # cmdlet's ConfirmImpact stays put -- raising it would prompt on every unrelated edit).
            if ($PSBoundParameters.ContainsKey('MembershipType')) {
                Write-Warning "Changing the membership type of administrative unit '$AuId' to '$MembershipType'. The unit's existing membership can change as a result; on a Dynamic unit the membership rule owns the membership and members can no longer be added or removed manually."
            }
            try {
                Invoke-OERGraphRequest -Method PATCH -Uri ("v1.0/directory/administrativeUnits/{0}" -f $AuId) -Body $Body | Out-Null
                $Updated = Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}" -f $AuId)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERAdministrativeUnit -InputObject $Updated
        }
    }
}
