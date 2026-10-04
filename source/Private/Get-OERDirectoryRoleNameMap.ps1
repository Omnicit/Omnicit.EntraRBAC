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
    way and thrown, instead of being returned as a map with nothing in it. For such a caller a listing
    that succeeds with no role at all counts as unread too, and throws.

    A map that was read is not guaranteed to name every role id a membership carries: it holds the
    roles the directory role list returned (the activated ones), and this function does not check a
    membership's role id against it. A role id the map does not name is looked up as empty by the
    caller, which decides what that means: Get-OERAdministrativeUnit keeps the role id with an empty
    RoleName, and Sync-OERStructureAdministrativeUnit withholds the add and the prune of a role it
    cannot name instead of treating it as undeclared. That case has not been seen live.

    .PARAMETER ThrowOnFailure
    When set, a failed read of the directory roles throws (after the error record is scrubbed) instead of
    returning an empty map. The exception names the read ('v1.0/directoryRoles'), carries the cause in its
    message and keeps the original exception as its InnerException. Without it the function stays
    best-effort, which is what the two other callers rely on: Get-OERAdministrativeUnitScopedRole, a read
    that only enriches its listing, and Add-OERAdministrativeUnitScopedRole, which only names the role in
    its output after the POST has succeeded. Get-OERAdministrativeUnit -IncludeScopedRoles sets the
    switch, because an empty map there would give every scoped role an empty RoleName that the apply
    engine reads as roles nobody declared. With the switch a read that SUCCEEDS and lists no activated
    role is treated as unread as well, and throws the same way with a message saying the listing came
    back empty: the map is read only for an administrative unit that has scoped roles, so at least one
    directory role is expected to be activated, and an empty answer is taken as evidence of a bad
    read. Without the switch that listing is returned as an empty map.

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
    $RoleList = @($Roles.value | Where-Object { $null -ne $_ })
    if ($ThrowOnFailure -and $RoleList.Count -eq 0) {
        # The map is read only for a unit that has at least one scoped role, so at least one directory
        # role is expected to be activated. A listing that succeeds with none is taken as a bad read, not
        # a genuine empty list, and this caller reads an empty map as roles nobody declared. Thrown
        # outside the try above: it is not a transport error. (That a NON-empty listing names every
        # membership's role id is not checked either -- see the .DESCRIPTION.)
        throw [System.Exception]::new(
            "Could not read the directory roles ('v1.0/directoryRoles') that name the roles: the listing came back empty, " +
            'although a unit with scoped roles is expected to have at least one directory role activated, so it is treated as unread.')
    }
    foreach ($Role in $RoleList) {
        if ($Role.id)             { $Map[[string]$Role.id] = [string]$Role.displayName }
        if ($Role.roleTemplateId) { $Map[[string]$Role.roleTemplateId] = [string]$Role.displayName }
    }
    return $Map
}
