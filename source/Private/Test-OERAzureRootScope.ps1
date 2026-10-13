function Test-OERAzureRootScope {
    <#
    .SYNOPSIS
    Tests whether an Azure scope is the root scope '/'.

    .DESCRIPTION
    The single owner of what the root scope is (BL-126). The Azure root scope '/' is the tenant root
    of Azure Resource Manager, above every management group and subscription in the tenant, so a role
    assignment there grants access over every Azure resource: it is elevated access, most often User
    Access Administrator granted through the Microsoft Entra setting "Access management for Azure
    resources". A structure document never carries such an assignment, and the apply engine never
    creates or removes one (docs/development/rationale.md#root-scope-is-not-in-the-document).

    A scope is the root scope when ConvertTo-OERCanonicalScope, the single owner of how a scope is
    compared, returns exactly '/' for it: '/' itself, and every run of slashes, which the offline
    validator already refuses as a spelling. A null, empty or blank value, a path below the root and
    a 'mg:' or 'sub:' shorthand are not the root scope. Pure and offline: it never calls Microsoft
    Graph or Azure Resource Manager, and it never throws.

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
    Test-OERAzureRootScope -Scope '/subscriptions/00000000-0000-0000-0000-000000000001'
    Returns $false.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Scope
    )
    return [bool]((ConvertTo-OERCanonicalScope -Scope ([string]$Scope)) -ceq '/')
}
