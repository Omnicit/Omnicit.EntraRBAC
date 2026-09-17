function Get-OERCommonDirectoryRoleName {
    <#
    .SYNOPSIS
    Returns the curated set of Entra ID directory-role display names that can be assigned at
    administrative-unit scope.

    .DESCRIPTION
    The single source of truth for the "common directory roles" set behind the -RoleName argument
    completer on Add-OERAdministrativeUnitScopedRole and Remove-OERAdministrativeUnitScopedRole.
    Defining the list in one place keeps the completer from drifting. The values are the built-in
    Microsoft Entra role DISPLAY names that Microsoft documents as assignable with administrative-unit
    scope (Assign Microsoft Entra roles, "Roles that can be assigned with administrative unit scope"),
    which is exactly the scope the scoped-role cmdlets operate at. Custom roles can also be assigned at
    administrative-unit scope but are tenant-specific and cannot be enumerated offline, so the completer
    they back stays additive with no ValidateSet. This helper performs no network call: completion must
    stay fast and must never block the prompt, which rules out the live Graph lookup in
    Get-OERDirectoryRoleNameMap. Callers resolve a name to an activated directoryRole id via
    Resolve-OERDirectoryRoleId.

    .EXAMPLE
    Get-OERCommonDirectoryRoleName
    Returns the curated directory-role display names assignable at administrative-unit scope.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    'Attribute Assignment Administrator'
    'Attribute Assignment Reader'
    'Authentication Administrator'
    'Cloud Device Administrator'
    'Groups Administrator'
    'Helpdesk Administrator'
    'License Administrator'
    'Password Administrator'
    'Printer Administrator'
    'Privileged Authentication Administrator'
    'SharePoint Administrator'
    'Teams Administrator'
    'Teams Devices Administrator'
    'User Administrator'
}
