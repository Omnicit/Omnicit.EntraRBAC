function Resolve-OERDirectoryRoleId {
    <#
    .SYNOPSIS
    Resolves a directory-role display name to its activated directoryRole object id, activating the role
    from its template when necessary.

    .DESCRIPTION
    Returns the object id of an activated Entra ID directory role. When -RoleId is supplied it is returned
    unchanged without any Graph call. When -RoleName is supplied the activated directoryRoles are listed
    in full (following @odata.nextLink across every page) and matched client-side on displayName
    (directory role $filter support is inconsistent, so matching is done in-process). When the role is not
    yet activated in the tenant, the matching directoryRoleTemplate is found the same way and the role is
    activated via POST /directoryRoles with its roleTemplateId; the new id is returned. Returns $null when
    the name matches neither an activated role nor a template -- a genuine
    no-match, mirroring Resolve-OERAdministrativeUnitId's null-on-no-match contract. A Graph/transport/
    permission failure during either lookup, or a failure activating the role from its template, still
    throws, as does calling with neither -RoleId nor -RoleName (a caller-error, not a lookup outcome).
    This private helper is reused by the scoped-role cmdlets (and later phases).

    .PARAMETER RoleId
    The directoryRole object id (or role template id accepted by the scopedRoleMembers API) to return
    verbatim. Takes precedence over -RoleName when both are supplied; no Graph call is made.

    .PARAMETER RoleName
    The directory-role display name (for example 'User Administrator') to resolve to an activated id.

    .EXAMPLE
    Resolve-OERDirectoryRoleId -RoleName 'User Administrator'
    Returns the activated directoryRole id, activating the role from its template if needed.

    .EXAMPLE
    Resolve-OERDirectoryRoleId -RoleName 'No Such Role'
    Returns $null: no activated role or template matches the name.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$RoleId,
        [string]$RoleName
    )
    if ($RoleId) { return $RoleId }
    if (-not $RoleName) {
        throw 'Resolve-OERDirectoryRoleId requires either -RoleId or -RoleName.'
    }

    $Active = Invoke-OERGraphRequest -Uri 'v1.0/directoryRoles' -All
    $ActiveMatch = @($Active.value) | Where-Object { $_.displayName -eq $RoleName } | Select-Object -First 1
    if ($ActiveMatch) { return [string]$ActiveMatch.id }

    $Templates = Invoke-OERGraphRequest -Uri 'v1.0/directoryRoleTemplates' -All
    $TemplateMatch = @($Templates.value) | Where-Object { $_.displayName -eq $RoleName } | Select-Object -First 1
    if (-not $TemplateMatch) {
        return $null
    }

    $Created = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/directoryRoles' -Body @{ roleTemplateId = [string]$TemplateMatch.id }
    return [string]$Created.id
}
