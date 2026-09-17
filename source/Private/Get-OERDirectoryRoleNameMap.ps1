function Get-OERDirectoryRoleNameMap {
    <#
    .SYNOPSIS
    Builds a lookup map from directory-role id (and role template id) to role display name.

    .DESCRIPTION
    Lists the activated Entra ID directory roles through Microsoft Graph and returns a hashtable keyed by
    both the directoryRole object id and the role template id, each mapping to the role's display name. A
    scopedRoleMembership carries only a role id, so this map lets the scoped-role cmdlets surface a friendly
    RoleName without an extra Graph call per membership. On any failure the function removes the error
    record (bearer-token safety) and returns an empty map rather than throwing, so name resolution is a
    best-effort enrichment that never blocks the primary result.

    .EXAMPLE
    $Map = Get-OERDirectoryRoleNameMap
    $Map['00000000-0000-0000-0000-000000000048']  # -> 'User Administrator'
    Returns the role-id-to-name map and looks up a single role name.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param()
    $Map = @{}
    try {
        $Roles = Invoke-OERGraphRequest -Uri 'v1.0/directoryRoles' -All
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        return $Map
    }
    foreach ($Role in @($Roles.value)) {
        if ($Role.id)             { $Map[[string]$Role.id] = [string]$Role.displayName }
        if ($Role.roleTemplateId) { $Map[[string]$Role.roleTemplateId] = [string]$Role.displayName }
    }
    return $Map
}
