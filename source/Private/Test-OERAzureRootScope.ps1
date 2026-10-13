function Test-OERAzureRootScope {
    <#
    .SYNOPSIS
    Tests whether an Azure scope addresses the root scope '/', in any spelling the Azure Resource
    Manager transport sends there.

    .DESCRIPTION
    The single owner of what the root scope is (BL-126). The Azure root scope '/' is the tenant root
    of Azure Resource Manager, above every management group and subscription in the tenant, so a role
    assignment there grants access over every Azure resource: it is elevated access, most often User
    Access Administrator granted through the Microsoft Entra setting "Access management for Azure
    resources". A structure document never carries such an assignment, and the apply engine never
    creates or removes one (docs/development/rationale.md#root-scope-is-not-in-the-document).

    A scope is the root scope in either of two cases. First, when ConvertTo-OERCanonicalScope, the
    single owner of how a scope is compared, returns exactly '/' for it: '/' itself, and every run of
    slashes, which the offline validator already refuses as a spelling. Second, when the scope starts
    with '/' and the role assignment request the transport would send for it reaches the root scope's
    path. Invoke-OERArmRequest sends "<host><scope>/providers/Microsoft.Authorization/roleAssignments..."
    as a System.Uri, which removes dot segments, decodes '%2e' and reads '\' as '/', so '/.', '/..',
    '/%2e' and '/subscriptions/<id>/../..' are all SENT to the root. This function builds the same
    URI on the neutral host 'scope.invalid' and tests whether its path is one or more slashes
    followed by 'providers/Microsoft.Authorization/roleAssignments' and nothing else. A scope
    that cannot form a URI is not the root scope: the transport could not send it either.

    A null, empty or blank value, a path below the root (a dot segment that stays below the root
    included, such as '/subscriptions/<id>/..'), '/' followed by a space (sent as '/%20/') and a 'mg:'
    or 'sub:' shorthand are not the root scope. Pure and offline: it never calls Microsoft Graph or
    Azure Resource Manager, and it never throws.

    It is used for the Azure roleAssignments section only. It is never applied to
    roleManagementPolicies, and never to the Microsoft Entra directory role sections, whose '/' is the
    Microsoft Entra tenant scope of a directory role (directoryScopeId), not the Azure root scope.

    .PARAMETER Scope
    The scope as a document wrote it, or an Azure Resource Manager scope already resolved from it.
    Null and an empty string are accepted and are not the root scope.

    .EXAMPLE
    Test-OERAzureRootScope -Scope '/'
    Returns $true.

    .EXAMPLE
    Test-OERAzureRootScope -Scope '/.'
    Returns $true: a request for '/./providers/Microsoft.Authorization/roleAssignments' is sent to
    '/providers/Microsoft.Authorization/roleAssignments'.

    .EXAMPLE
    Test-OERAzureRootScope -Scope '/subscriptions/00000000-0000-0000-0000-000000000001'
    Returns $false.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Scope
    )
    $ScopeText = [string]$Scope
    if ((ConvertTo-OERCanonicalScope -Scope $ScopeText) -ceq '/') { return $true }
    if (-not $ScopeText.StartsWith('/', [System.StringComparison]::Ordinal)) { return $false }
    # The URI the transport sends for this scope's role assignments, on a neutral host: System.Uri
    # normalises the path exactly as it does for the request (dot segments, '%2e', '\').
    $SentUri = $null
    if (-not [uri]::TryCreate('https://scope.invalid' + $ScopeText + '/providers/Microsoft.Authorization/roleAssignments',
            [System.UriKind]::Absolute, [ref]$SentUri)) {
        return $false
    }
    return [bool]($SentUri.AbsolutePath -match '^/+providers/Microsoft\.Authorization/roleAssignments$')
}
