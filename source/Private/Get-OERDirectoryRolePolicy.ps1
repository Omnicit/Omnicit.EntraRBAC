function Get-OERDirectoryRolePolicy {
    <#
    .SYNOPSIS
    Reads one Microsoft Entra directory-role role management policy by its Microsoft Graph id.

    .DESCRIPTION
    Returns the raw unifiedRoleManagementPolicy resource, with its rules expanded
    ($expand=rules), from Microsoft Graph v1.0 for the given policy id -- the id
    Get-OERDirectoryRolePolicyAssignment lists on each assignment (for example
    'DirectoryRole_<tenantId>_<policyGuid>'). Before returning, the policy's own scopeId and
    scopeType (both required properties of every unifiedRoleManagementPolicy) are checked: scopeId
    must be '/' and scopeType must be 'Directory' or 'DirectoryRole' (case-insensitive) -- the two
    shapes Microsoft Graph documents for a tenant-wide directory policy. Microsoft Graph serves
    every roleManagementPolicy, directory-role or PIM-for-Groups alike, from the same
    /policies/roleManagementPolicies collection, and a PIM for Groups policy id (scopeType
    'Group', scopeId the group's object id) is not syntactically distinguishable from a
    directory-role one before it is read. This is therefore the single owner of that check: a
    policy that fails it throws an ErrorRecord with ErrorId 'NotDirectoryRolePolicy' (a missing
    scopeId or scopeType counts as failing it too), so a Group policy id typed or piped into a
    directory-role cmdlet is refused here instead of being read, tagged with Scope '/' regardless
    of its real scope, and possibly written to on a later Set. A transport or permission failure is
    not caught here and propagates to the caller unchanged.

    .PARAMETER PolicyId
    The Microsoft Graph roleManagementPolicy id to read.

    .EXAMPLE
    Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_00000000-0000-0000-0000-000000000064_00000000-0000-0000-0000-000000000065'
    Returns the raw policy resource with its rules expanded.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyId
    )
    $Uri = "v1.0/policies/roleManagementPolicies/$PolicyId`?`$expand=rules"
    $Policy = Invoke-OERGraphRequest -Uri $Uri
    $ScopeId = [string]$Policy.scopeId
    $ScopeType = [string]$Policy.scopeType
    if ($ScopeId -ne '/' -or $ScopeType -notin @('Directory', 'DirectoryRole')) {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Policy '$PolicyId' is not a directory-role policy (scopeType '$ScopeType', scopeId '$ScopeId'). " +
                'A PIM for Groups policy is read and changed with Get-OERGroupPimPolicy and Set-OERGroupPimPolicy.'),
            'NotDirectoryRolePolicy',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $PolicyId)
    }
    $Policy
}
