function ConvertTo-OERCanonicalScope {
    <#
    .SYNOPSIS
    Returns the canonical form of a structure-document scope, for comparing two scopes offline.

    .DESCRIPTION
    The single owner of how a roleAssignments or roleManagementPolicies scope is spelled when two
    scopes are compared. It is pure and offline -- it never calls Microsoft Graph or Azure Resource
    Manager -- so the offline validator (Test-OERStructureSchema) and the apply engine
    (Invoke-OERStructure, through Resolve-OERStructureRoleAssignmentScope) share it.

    - 'mg:<x>', with the prefix in any letter case, becomes
      '/providers/Microsoft.Management/managementGroups/<x>'.
    - 'sub:<guid>' or 'subscription:<guid>', in any letter case, becomes '/subscriptions/<guid>'.
    - 'sub:<name>' or 'subscription:<name>' whose value is not a GUID becomes 'sub:<name>': a
      subscription name can only be resolved online, so the two prefixes are unified and the name is
      kept as written.
    - A value that starts with '/' loses every trailing '/', except that '/' itself stays '/'.
    - Anything else is returned unchanged.

    The trim is not a spelling rule for a document. Test-OERStructureSchema refuses a document scope
    that ends with '/' (other than '/' itself) or contains '//', so for a document it accepts the trim
    changes nothing, and a scope written with a stray '/' is never merged with another spelling or
    pruned. The trim remains for the scope the engine resolves itself.

    Letter case is preserved. Callers compare the result without regard to letter case, as Azure
    Resource Manager compares scopes.

    .PARAMETER Scope
    The scope as the document wrote it, or an Azure Resource Manager scope already resolved from it.

    .EXAMPLE
    ConvertTo-OERCanonicalScope -Scope 'SUB:00000000-0000-0000-0000-000000000001'
    Returns '/subscriptions/00000000-0000-0000-0000-000000000001'.

    .EXAMPLE
    ConvertTo-OERCanonicalScope -Scope '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/'
    Returns the same path without the trailing slash.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope
    )

    $Value = $Scope
    if ($Value -match '^(?i)mg:(.+)$') {
        $Value = "/providers/Microsoft.Management/managementGroups/$($Matches[1])"
    } elseif ($Value -match '^(?i)(?:subscription|sub):(.+)$') {
        $SubscriptionValue = $Matches[1]
        if (-not (Test-OERGuid -Value $SubscriptionValue)) { return "sub:$SubscriptionValue" }
        $Value = "/subscriptions/$SubscriptionValue"
    }
    if ($Value.StartsWith('/')) {
        $Trimmed = $Value.TrimEnd('/')
        if ($Trimmed.Length -eq 0) { return '/' }
        return $Trimmed
    }
    $Value
}
