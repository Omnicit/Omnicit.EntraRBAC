function Remove-OERAdministrativeUnitScopedRole {
    <#
    .SYNOPSIS
    Removes a scoped directory-role assignment from an Entra ID administrative unit.

    .DESCRIPTION
    Removes a scoped role membership from the administrative unit identified by -AdministrativeUnit. The
    membership to remove is identified either directly by -ScopedRoleMembershipId, or by a principal --
    named with -User (user principal name) or -Group (group display name), or supplied as a raw object id
    with -PrincipalId -- together with -RoleName or -RoleId (in which case the unit's scoped role members
    are listed in full, following @odata.nextLink across every page, and the matching membership is
    found); supplying both -RoleName and -RoleId is rejected with a non-terminating AmbiguousRole error.
    A unit that cannot be resolved produces a
    non-terminating AdministrativeUnitNotFound error; insufficient identification produces
    ScopedRoleNotSpecified; no matching membership produces ScopedRoleNotFound. A non-GUID value passed to
    -PrincipalId produces a non-terminating InvalidPrincipalId error naming the friendly alternatives.
    Supports -WhatIf and -Confirm. ConfirmImpact is High -- this revokes a delegated administrator
    privilege, so it prompts under the default $ConfirmPreference; unattended automation must pass
    -Confirm:$false.

    Because -PrincipalId, -RoleId and -ScopedRoleMembershipId all bind from the pipeline by property
    name, supplying -User or -Group together with piped input is rejected with a non-terminating
    AmbiguousPrincipal error instead of silently applying the named principal to every piped item. An
    explicit command-line -PrincipalId together with piped input whose items carry a DIFFERENT
    PrincipalId of their own is rejected the same way: PowerShell freezes an explicitly-bound parameter
    for the rest of the pipeline, so without this guard the explicit value would silently apply to
    every piped item in place of its own principal, with no warning -- the same class of "an explicit
    choice quietly wins over what the pipeline actually named" defect as the -User/-Group case above.
    An ordinary pipe that supplies no explicit -PrincipalId at all is unaffected, and so is an explicit
    -PrincipalId piped alongside items that carry no PrincipalId of their own. When
    -ScopedRoleMembershipId is supplied directly (not piped) together with -PrincipalId, -User or -Group,
    the membership id takes precedence and a warning names the ignored principal parameter(s).

    The AmbiguousRole check above runs before that -ScopedRoleMembershipId precedence handling, and
    -RoleId also binds from the pipeline by property name, so an ordinary pipe of scoped-role membership
    objects (each carrying its own RoleId and ScopedRoleMembershipId) together with an explicit
    command-line -RoleName now raises AmbiguousRole -- and removes nothing -- for every piped item,
    rather than silently ignoring -RoleName and deleting by the piped ScopedRoleMembershipId as it did
    before this AmbiguousRole guard existed. This is the safer of the two behaviors (failing loudly
    beats silently discarding a filter the caller explicitly supplied), but it is a real behavior
    change worth calling out: a piped role-removal run must not also pass -RoleName on the command
    line.

    .PARAMETER AdministrativeUnit
    The administrative unit to remove the scoped role from, given as either its object id (GUID) or its
    display name. Binds from the pipeline by property name, and still accepts the historical -Id,
    -AdministrativeUnitId and -DisplayName parameter names as aliases.

    .PARAMETER ScopedRoleMembershipId
    The id of the scoped role membership to remove. When supplied, no lookup is performed. Accepts
    pipeline input by property name from Get-OERAdministrativeUnitScopedRole or Add-OERAdministrativeUnitScopedRole.
    When supplied no principal is required.

    .PARAMETER RoleName
    The directory-role display name used (with -PrincipalId) to find the membership to remove, also
    accepted as -Role so the spelling learned on the Azure role cmdlets works here too. Resolved via
    Resolve-OERDirectoryRoleId. Tab-completion offers the built-in roles that Microsoft documents as
    assignable at administrative-unit scope; custom role names are still accepted. Mutually exclusive
    with -RoleId; supplying both raises AmbiguousRole.

    .PARAMETER RoleId
    The directory-role id used (with -PrincipalId) to find the membership to remove. Accepts
    pipeline input by property name from Get-OERAdministrativeUnitScopedRole or Add-OERAdministrativeUnitScopedRole.

    .PARAMETER PrincipalId
    The principal object id used (with -RoleName or -RoleId) to find the membership to remove. Accepts
    pipeline input by property name from Get-OERAdministrativeUnitScopedRole or Add-OERAdministrativeUnitScopedRole.
    Must be a canonical GUID; to name the principal instead, use -User or -Group.

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
    Remove-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr' -RoleName 'User Administrator' -PrincipalId $UserId
    Removes the User Administrator scoped role assignment for the user from the au_hr unit.

    .EXAMPLE
    Remove-OERAdministrativeUnitScopedRole -AdministrativeUnit $AuId -ScopedRoleMembershipId $MembershipId
    Removes the scoped role membership by its id without a lookup.

    .EXAMPLE
    Remove-OERAdministrativeUnitScopedRole -AdministrativeUnit 'au_hr' -RoleName 'User Administrator' -User 'anna.berg@contoso.com'
    Removes the User Administrator scoped role assignment for the user, named by UPN, from the au_hr unit.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # AdministrativeUnitId precedes Id/DisplayName so a piped AdministrativeUnitMember object binds
        # the parent unit's id, not the member's own Id/DisplayName, during ValueFromPipelineByPropertyName
        # alias resolution.
        [Alias('AdministrativeUnitId', 'Id', 'DisplayName')]
        [string]$AdministrativeUnit,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ScopedRoleMembershipId,
        [Alias('Role')]
        [string]$RoleName,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$RoleId,
        [Parameter(ValueFromPipelineByPropertyName)]
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

        # Captured BEFORE the first pipeline item arrives: at this point $PSBoundParameters reflects
        # only what the caller typed on the command line, not yet the per-item pipeline rebind that
        # -PrincipalId (ValueFromPipelineByPropertyName) receives on every `process` call. Comparing
        # THIS snapshot against the live $PrincipalId inside process -- rather than re-checking
        # $PSBoundParameters.ContainsKey('PrincipalId') there -- is what distinguishes an explicit
        # command-line -PrincipalId from an ordinary pipeline-bound one: pipeline binding populates
        # $PSBoundParameters too, so a naive ContainsKey check in process would misfire on every
        # ordinary pipe of Get-/Add-OERAdministrativeUnitScopedRole output.
        $ExplicitPrincipalId = if ($PSBoundParameters.ContainsKey('PrincipalId')) { $PrincipalId } else { $null }
    }
    process {
        # -RoleName and -RoleId are two spellings of the same input, not two independent knobs:
        # Resolve-OERDirectoryRoleId always prefers -RoleId when both are supplied (it returns $RoleId
        # verbatim regardless of -RoleName). Reject the ambiguity up front, mirroring the
        # Add-OERAdministrativeUnitScopedRole RoleNotSpecified-style guard's shape and placement.
        if ($RoleName -and $RoleId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Specify the directory role with -RoleName or -RoleId, not both.')) `
                -ErrorId 'AmbiguousRole' `
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
        Write-Verbose "[Remove-OERAdministrativeUnitScopedRole] Resolved administrative unit to '$AuId'."

        if ($PSCmdlet.MyInvocation.ExpectingInput -and
            ($PSBoundParameters.ContainsKey('User') -or $PSBoundParameters.ContainsKey('Group'))) {
            Write-CmdletError `
                -Message ([System.Exception]::new('A principal was supplied by name while objects are being piped in. The piped -PrincipalId takes precedence and the named principal would be ignored for every piped item. Supply either the named principal or the pipeline, not both.')) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $AuId -Cmdlet $PSCmdlet
            return
        }

        # prom-au-scopedrole-principalid-inert-on-pipe: an explicit command-line -PrincipalId must not
        # silently apply to (or worse, silently get ignored for) a piped item that names a DIFFERENT
        # principal of its own. IMPORTANT PowerShell binding fact, verified empirically: once a
        # parameter is bound from an explicit command-line argument, ValueFromPipelineByPropertyName
        # does NOT re-bind it from later pipeline objects -- $PrincipalId stays frozen at the explicit
        # value for every item in the pipeline, it is never overwritten by a piped item's own
        # PrincipalId property. So comparing the live $PrincipalId variable against the captured
        # explicit value can never detect a divergence (they are identical by construction). The
        # piped item's OWN PrincipalId is only observable through $PSItem (automatically populated in
        # `process` for every advanced function, independent of any ValueFromPipeline parameter), so
        # that -- not the frozen $PrincipalId parameter variable -- is what must be compared here.
        # $ExplicitPrincipalId (captured in `begin`, before any pipeline item arrives) is $null for an
        # ordinary pipe with no explicit -PrincipalId, so this never fires for the common case, and it
        # does not fire for a piped item that carries no PrincipalId of its own (an explicit
        # -PrincipalId alongside a pipe of bare role/AU references is a legitimate, unambiguous use).
        if ($ExplicitPrincipalId -and $PSItem.PrincipalId -and $PSItem.PrincipalId -ne $ExplicitPrincipalId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("An explicit -PrincipalId '$ExplicitPrincipalId' was supplied together with piped input carrying a different PrincipalId '$($PSItem.PrincipalId)'. Because PowerShell freezes an explicitly-bound parameter for the rest of the pipeline, the explicit value would silently apply to this item instead of its own principal, with no warning. Supply either the explicit -PrincipalId or the pipeline, not both.")) `
                -ErrorId 'AmbiguousPrincipal' -Category InvalidArgument -TargetObject $AuId -Cmdlet $PSCmdlet
            return
        }

        $MembershipId = $ScopedRoleMembershipId
        if ($MembershipId -and -not $PSCmdlet.MyInvocation.ExpectingInput -and
            ($PSBoundParameters.ContainsKey('PrincipalId') -or $PSBoundParameters.ContainsKey('User') -or
                $PSBoundParameters.ContainsKey('Group'))) {
            $IgnoredParameterNames = [System.Collections.Generic.List[string]]::new()
            if ($PSBoundParameters.ContainsKey('PrincipalId')) { $IgnoredParameterNames.Add('-PrincipalId') }
            if ($PSBoundParameters.ContainsKey('User')) { $IgnoredParameterNames.Add('-User') }
            if ($PSBoundParameters.ContainsKey('Group')) { $IgnoredParameterNames.Add('-Group') }
            Write-Warning "-ScopedRoleMembershipId takes precedence: the supplied $($IgnoredParameterNames -join ', ') value is ignored and scoped role membership '$MembershipId' is removed. Supply only one."
        }
        if (-not $MembershipId) {
            if ((-not $PrincipalId -and -not $User -and -not $Group) -or (-not $RoleName -and -not $RoleId)) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('Specify -ScopedRoleMembershipId, or a principal (-PrincipalId, -User or -Group) together with -RoleName or -RoleId.')) `
                    -ErrorId 'ScopedRoleNotSpecified' `
                    -Category InvalidArgument `
                    -TargetObject $AuId `
                    -Cmdlet $PSCmdlet
                return
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
            Write-Verbose "[Remove-OERAdministrativeUnitScopedRole] Resolved principal to '$ResolvedPrincipalId'."

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
                Write-Verbose "[Remove-OERAdministrativeUnitScopedRole] Resolved role '$RoleName' to '$ResolvedRoleId'."
            }

            try {
                $Existing = @((Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}/scopedRoleMembers" -f $AuId) -All).value)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            $Match = @($Existing) | Where-Object { $_.roleId -eq $ResolvedRoleId -and $_.roleMemberInfo.id -eq $ResolvedPrincipalId } | Select-Object -First 1
            if (-not $Match) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("No scoped role membership found for role '$ResolvedRoleId' and principal '$ResolvedPrincipalId' on the unit.")) `
                    -ErrorId 'ScopedRoleNotFound' `
                    -Category ObjectNotFound `
                    -TargetObject $ResolvedPrincipalId `
                    -Cmdlet $PSCmdlet
                return
            }
            $MembershipId = [string]$Match.id
        }

        if ($PSCmdlet.ShouldProcess($AuId, "Remove scoped role membership '$MembershipId'")) {
            Write-Warning "Removing scoped role membership '$MembershipId' from administrative unit '$AuId'. This revokes the principal's delegated administrator privilege over that unit."
            try {
                Invoke-OERGraphRequest -Method DELETE -Uri ("v1.0/directory/administrativeUnits/{0}/scopedRoleMembers/{1}" -f $AuId, $MembershipId) | Out-Null
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
