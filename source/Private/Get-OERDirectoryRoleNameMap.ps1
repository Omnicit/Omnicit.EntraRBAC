function Get-OERDirectoryRoleNameMap {
    <#
    .SYNOPSIS
    Builds a lookup map from directory-role id (and role template id) to role display name.

    .DESCRIPTION
    Lists the activated Entra ID directory roles through Microsoft Graph and returns a hashtable keyed by
    both the directoryRole object id and the role template id, each mapping to the role's display name. A
    scopedRoleMembership carries only a role id, so this map lets the scoped-role cmdlets surface a friendly
    RoleName without an extra Graph call per membership. By default, on any failure the function removes
    the error record (bearer-token safety) and returns an empty map rather than throwing, so name
    resolution is a best-effort enrichment that never blocks the primary result. A caller that cannot
    treat an unreadable list as an empty one passes -ThrowOnFailure: the failure is then scrubbed the same
    way and thrown, instead of being returned as a map with nothing in it.

    .PARAMETER ThrowOnFailure
    When set, a failed read of the directory roles throws (after the error record is scrubbed) instead of
    returning an empty map. The exception names the read ('v1.0/directoryRoles'), carries the cause in its
    message and keeps the original exception as its InnerException. Without it the function stays
    best-effort, which is what the read-only listing cmdlets rely on. Get-OERAdministrativeUnit
    -IncludeScopedRoles sets it, because an empty map there would give every scoped role an empty RoleName
    that the apply engine reads as roles nobody declared. A read that SUCCEEDS and lists no activated role
    is a genuine empty map and is returned as such, with or without this switch.

    .EXAMPLE
    $Map = Get-OERDirectoryRoleNameMap
    $Map['00000000-0000-0000-0000-000000000048']  # -> 'User Administrator'
    Returns the role-id-to-name map and looks up a single role name.

    .EXAMPLE
    $Map = Get-OERDirectoryRoleNameMap -ThrowOnFailure
    Returns the same map, but throws when the directory roles cannot be read instead of returning an
    empty map.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [switch]$ThrowOnFailure
    )
    $Map = @{}
    try {
        $Roles = Invoke-OERGraphRequest -Uri 'v1.0/directoryRoles' -All
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        if ($ThrowOnFailure) {
            throw [System.Exception]::new(
                "Could not read the directory roles ('v1.0/directoryRoles') that name the roles: $($PSItem.Exception.Message)",
                $PSItem.Exception)
        }
        return $Map
    }
    foreach ($Role in @($Roles.value)) {
        if ($Role.id)             { $Map[[string]$Role.id] = [string]$Role.displayName }
        if ($Role.roleTemplateId) { $Map[[string]$Role.roleTemplateId] = [string]$Role.displayName }
    }
    return $Map
}
