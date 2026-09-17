function Get-OERAdministrativeUnitScopedRole {
    <#
    .SYNOPSIS
    Lists the scoped directory-role assignments of an Entra ID administrative unit.

    .DESCRIPTION
    Reads the scoped role members of the administrative unit identified by -AdministrativeUnit through
    Microsoft Graph and returns them as tagged Omnicit.EntraRBAC.AdministrativeUnitScopedRole objects. Each
    object describes a directory role assigned to a principal scoped to the unit. A unit that cannot be
    resolved produces a non-terminating AdministrativeUnitNotFound error.

    .PARAMETER AdministrativeUnit
    The administrative unit whose scoped roles to list, given as either its object id (GUID) or its
    display name. Binds from the pipeline by property name, and still accepts the historical -Id,
    -AdministrativeUnitId and -DisplayName parameter names as aliases.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr'
    Lists every directory role scoped to the au_hr administrative unit.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # AdministrativeUnitId precedes Id/DisplayName so a piped AdministrativeUnitMember object binds
        # the parent unit's id, not the member's own Id/DisplayName, during ValueFromPipelineByPropertyName
        # alias resolution.
        [Alias('AdministrativeUnitId', 'Id', 'DisplayName')]
        [string]$AdministrativeUnit,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
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
                -Message ([System.Exception]::new('No administrative unit found for the supplied id/display name.')) `
                -ErrorId 'AdministrativeUnitNotFound' `
                -Category ObjectNotFound `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }

        try {
            $Scoped = @((Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}/scopedRoleMembers" -f $AuId) -All).value)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        $RoleMap = Get-OERDirectoryRoleNameMap
        foreach ($Membership in @($Scoped | Where-Object { $_ })) {
            ConvertTo-OERScopedRoleMember -InputObject $Membership -RoleName ([string]$RoleMap[[string]$Membership.roleId])
        }
    }
}
