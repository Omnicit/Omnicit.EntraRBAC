function Get-OERCommonRoleName {
    <#
    .SYNOPSIS
    Returns the curated set of common Azure built-in role display names used across the module.

    .DESCRIPTION
    The single source of truth for the "common roles" set shared by the -Role argument completer and
    the -CommonRoles switch on Get-OERRoleManagementPolicy and Get-OERInventory. Defining the list in
    one place guarantees the completer and the -CommonRoles expansion cannot drift apart. The values
    are built-in Azure RBAC role DISPLAY names (verified against the Azure built-in roles reference):
    Reader, Contributor, Owner, User Access Administrator, and Role Based Access Control
    Administrator. Callers resolve each name to a full ARM role definition id via
    Resolve-OERRoleDefinitionId at the target scope; this helper performs no network call.

    .EXAMPLE
    Get-OERCommonRoleName
    Returns the five curated common Azure role display names.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    'Reader'
    'Contributor'
    'Owner'
    'User Access Administrator'
    'Role Based Access Control Administrator'
}
