function Get-OERDirectoryRolePolicy {
    <#
    .SYNOPSIS
    Reads one Microsoft Entra directory-role role management policy by its Microsoft Graph id.

    .DESCRIPTION
    Returns the raw unifiedRoleManagementPolicy resource, with its rules expanded
    ($expand=rules), from Microsoft Graph v1.0 for the given policy id -- the id
    Get-OERDirectoryRolePolicyAssignment lists on each assignment (for example
    'DirectoryRole_<roleId>_<templateId>'). A transport or permission failure is not caught here
    and propagates to the caller unchanged.

    .PARAMETER PolicyId
    The Microsoft Graph roleManagementPolicy id to read.

    .EXAMPLE
    Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'
    Returns the raw policy resource with its rules expanded.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId
    )
    $Uri = "v1.0/policies/roleManagementPolicies/$PolicyId`?`$expand=rules"
    Invoke-OERGraphRequest -Uri $Uri
}
