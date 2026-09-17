function Add-OERAdministrativeUnitScopedRole {
    <#
    .SYNOPSIS
    Assigns a directory role to a principal scoped to an Entra ID administrative unit.

    .DESCRIPTION
    Creates a scoped role membership so the principal -- named with -User (user principal name) or
    -Group (group display name), or supplied as a raw object id with -PrincipalId -- holds the specified
    directory role only over the objects in the administrative unit identified by -AdministrativeUnit.
    The role is given either by friendly name with -RoleName (resolved -- and activated if necessary --
    through Resolve-OERDirectoryRoleId) or directly by id with -RoleId; supplying both is rejected with a
    non-terminating AmbiguousRole error. At least one of -RoleName or -RoleId is required. A unit that
    cannot be resolved produces a non-terminating AdministrativeUnitNotFound error; a role name that
    cannot be resolved produces a non-terminating RoleNotFound error. A non-GUID value passed to
    -PrincipalId produces a non-terminating InvalidPrincipalId error naming the friendly alternatives.
    Output is a tagged Omnicit.EntraRBAC.AdministrativeUnitScopedRole object. Supports -WhatIf and
    -Confirm.

    .PARAMETER AdministrativeUnit
    The administrative unit to assign the scoped role on, given as either its object id (GUID) or its
    display name. Binds from the pipeline by property name, and still accepts the historical -Id,
    -AdministrativeUnitId and -DisplayName parameter names as aliases.

    .PARAMETER RoleName
    The directory-role display name (for example 'User Administrator') to assign, also accepted as
    -Role so the spelling learned on the Azure role cmdlets works here too. Resolved and activated via
    Resolve-OERDirectoryRoleId. Tab-completion offers the built-in roles that Microsoft documents as
    assignable at administrative-unit scope; custom role names are still accepted. Mutually
    exclusive with -RoleId; supply one.

    .PARAMETER RoleId
    The directory-role id to assign directly, bypassing name resolution. Supply this or -RoleName.

    .PARAMETER PrincipalId
    The object id of the principal (user or group) that receives the scoped role. Must be a canonical
    GUID; to name the principal instead, use -User or -Group.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER User
    The user that receives (or loses) the scoped role, given as a user principal name or object id
    (GUID) and resolved via Resolve-OERPrincipal. Mutually exclusive with -PrincipalId and -Group.

    .PARAMETER Group
    The group that receives (or loses) the scoped role, given as a group display name or object id
    (GUID) and resolved via Resolve-OERPrincipal. Mutually exclusive with -PrincipalId and -User.
    Group display names are not guaranteed unique in Entra ID; if more than one group shares the
    given name, the command fails with an error naming the candidate object ids, so re-run with
    the object id.

    .EXAMPLE
    Add-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr' -RoleName 'User Administrator' -PrincipalId $UserId
    Grants the user the User Administrator role scoped to the au_hr administrative unit.

    .EXAMPLE
    Add-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr' -RoleName 'User Administrator' -User 'anna.berg@contoso.com'
    Grants the user, named by UPN, the User Administrator role scoped to the au_hr administrative unit.
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

        [Alias('Role')]
        [string]$RoleName,
        [string]$RoleId,

        [string]$PrincipalId,

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [string]$User,

        [string]$Group
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # -RoleName and -RoleId are two spellings of the same input, not two independent knobs: Resolve-
        # OERDirectoryRoleId always prefers -RoleId when both are supplied (it returns $RoleId verbatim
        # regardless of -RoleName), so accepting both silently would resolve one role while echoing the
        # other's name on the output object. Reject the ambiguity up front instead.
        if ($RoleName -and $RoleId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Specify the directory role with -RoleName or -RoleId, not both.')) `
                -ErrorId 'AmbiguousRole' `
                -Category InvalidArgument `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }
        if (-not $RoleName -and -not $RoleId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Specify the directory role with -RoleName or -RoleId.')) `
                -ErrorId 'RoleNotSpecified' `
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
                -Message ([System.Exception]::new('No administrative unit found for the supplied id/display name.')) `
                -ErrorId 'AdministrativeUnitNotFound' `
                -Category ObjectNotFound `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Add-OERAdministrativeUnitScopedRole] Resolved administrative unit to '$AuId'."

        # As above: a throw is a lookup failure (403/429/5xx or a role-activation POST failure), not a
        # missing role. Keep RoleNotFound for the genuine no-match case only. Resolve-OERDirectoryRoleId's
        # own contract now returns $null for a genuine no-match (mirrors Resolve-OERAdministrativeUnitId),
        # so that is the normal path into the RoleNotFound block below. The -like check here is a narrow
        # defensive backstop only: if anything ever throws with that exact not-found message shape instead
        # of returning $null, still report the same RoleNotFound outcome rather than misreporting a
        # resolve failure for a role that simply does not exist -- the single most common failure here.
        $ResolvedRoleId = try {
            Resolve-OERDirectoryRoleId -RoleId $RoleId -RoleName $RoleName
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if ($PSItem.Exception.Message -like 'No directory role found*') {
                $null
            } else {
                Write-CmdletError `
                    -Message ([System.Exception]::new(
                        "Failed to look up directory role '$(if ($RoleId) { $RoleId } else { $RoleName })': $($PSItem.Exception.Message)")) `
                    -InnerException $PSItem.Exception `
                    -ErrorId 'DirectoryRoleResolveFailed' `
                    -Category NotSpecified `
                    -TargetObject $(if ($RoleId) { $RoleId } else { $RoleName }) `
                    -Cmdlet $PSCmdlet
                return
            }
        }
        if (-not $ResolvedRoleId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Could not resolve directory role from -RoleName '$RoleName' / -RoleId '$RoleId'.")) `
                -ErrorId 'RoleNotFound' `
                -Category ObjectNotFound `
                -TargetObject ($RoleName, $RoleId | Where-Object { $_ } | Select-Object -First 1) `
                -Cmdlet $PSCmdlet
            return
        }
        if ($RoleName) {
            Write-Verbose "[Add-OERAdministrativeUnitScopedRole] Resolved role '$RoleName' to '$ResolvedRoleId'."
        }

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User -Group $Group `
            -FriendlyParameterHint '-User or -Group'
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        $ResolvedPrincipalId = $Principal.PrincipalId
        Write-Verbose "[Add-OERAdministrativeUnitScopedRole] Resolved principal to '$ResolvedPrincipalId'."

        $Body = @{
            roleId         = $ResolvedRoleId
            roleMemberInfo = @{ id = $ResolvedPrincipalId }
        }
        if ($PSCmdlet.ShouldProcess($AuId, "Assign role '$ResolvedRoleId' to '$ResolvedPrincipalId' scoped to the unit")) {
            try {
                $Created = Invoke-OERGraphRequest -Method POST -Uri ("v1.0/directory/administrativeUnits/{0}/scopedRoleMembers" -f $AuId) -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            # Resolve-OERDirectoryRoleId always prefers -RoleId over -RoleName when both are bound (it
            # returns $RoleId verbatim), so the emitted RoleName has to be derived from the id that
            # ACTUALLY drove the resolution -- not from whichever of $RoleName/$RoleId happens to be
            # truthy -- or a caller supplying both would see the ignored -RoleName echoed back. The
            # AmbiguousRole guard above already rejects both-bound, so this is belt-and-braces.
            $EffectiveRoleName = if ($RoleId) { [string](Get-OERDirectoryRoleNameMap)[$ResolvedRoleId] } else { $RoleName }
            ConvertTo-OERScopedRoleMember -InputObject $Created -RoleName $EffectiveRoleName
        }
    }
}
