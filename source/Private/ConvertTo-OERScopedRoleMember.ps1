function ConvertTo-OERScopedRoleMember {
    <#
    .SYNOPSIS
    Converts a raw Microsoft Graph scopedRoleMembership into a tagged
    Omnicit.EntraRBAC.AdministrativeUnitScopedRole object.

    .DESCRIPTION
    Maps a Graph scopedRoleMembership (a directory-role assignment scoped to an administrative unit) into a
    [PSCustomObject] tagged with the type name Omnicit.EntraRBAC.AdministrativeUnitScopedRole so Format and
    Types views apply. The Graph membership carries only the role id, so the friendly RoleName is supplied
    by the caller via -RoleName (resolved from the directory roles); RoleId is retained on the object but is
    hidden from the default table view. This private converter is the single owner of the scoped-role output
    shape and is used by Add-OERAdministrativeUnitScopedRole, Get-OERAdministrativeUnitScopedRole, and
    Get-OERAdministrativeUnit -IncludeScopedRoles.

    .PARAMETER InputObject
    The raw Graph scopedRoleMembership object (hashtable or PSObject) to convert into a tagged object.

    .PARAMETER RoleName
    The directory-role display name resolved by the caller for the membership's role id. Surfaced as the
    RoleName property and the primary role column in the default view. Optional; null when not supplied.

    .EXAMPLE
    $Scoped = ConvertTo-OERScopedRoleMember -InputObject $GraphScopedRoleMembership -RoleName 'User Administrator'
    Converts a single scoped role membership into a tagged object with its friendly role name.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$RoleName
    )
    process {
        $Out = [PSCustomObject]@{
            ScopedRoleMembershipId = $InputObject.id
            AdministrativeUnitId   = $InputObject.administrativeUnitId
            RoleName               = $RoleName
            RoleId                 = $InputObject.roleId
            PrincipalId            = $InputObject.roleMemberInfo.id
            PrincipalDisplayName   = $InputObject.roleMemberInfo.displayName
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitScopedRole')
        $Out
    }
}
