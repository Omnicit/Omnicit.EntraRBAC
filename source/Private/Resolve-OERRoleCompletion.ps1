function Resolve-OERRoleCompletion {
    <#
    .SYNOPSIS
    Builds argument-completer results for the -Role parameter from the curated common-role set.

    .DESCRIPTION
    Backs the -Role argument completer registered on every cmdlet that takes an Azure RBAC role name.
    The authoritative, current list of those cmdlets is the -CommandName argument of the
    Register-ArgumentCompleter call for -Role in source/suffix.ps1 (mirrored in the dev-mode
    Omnicit.EntraRBAC.psm1 loader) -- consult that call, not this help text, when wiring up a new
    role-taking cmdlet, since re-enumerating cmdlet names here would only drift again. It filters the
    curated common-role display names (from Get-OERCommonRoleName) by the text typed so far -- a
    case-insensitive prefix match, where an empty or absent word returns the entire set -- and emits
    one System.Management.Automation.CompletionResult per match. A role name that contains whitespace
    is wrapped in single quotes in the completion text so the inserted argument is valid as typed,
    while the list-item and tooltip keep the raw name. The completer is purely additive: free-text
    role names and role definition GUIDs are still accepted on -Role because no ValidateSet is
    involved.

    .PARAMETER WordToComplete
    The partial text the user has typed for the -Role argument. Used as a case-insensitive prefix
    filter against the curated role names (surrounding quotes are trimmed first). An empty or null
    value returns the entire curated set.

    .EXAMPLE
    Resolve-OERRoleCompletion -WordToComplete 'R'
    Returns completion results for 'Reader' and 'Role Based Access Control Administrator'.
    #>
    [OutputType([System.Management.Automation.CompletionResult])]
    [CmdletBinding()]
    param(
        [string]$WordToComplete
    )

    # WordToComplete is [string], so binding coerces an omitted value to '' (never $null). The guard
    # is defensive for callers that invoke this helper directly with $null; an empty word trims to ''
    # and matches every curated name.
    $Word = if ($WordToComplete) { $WordToComplete.Trim("'", '"') } else { '' }

    foreach ($Name in (Get-OERCommonRoleName)) {
        # StartsWith, not -like: every one of this module's completion helpers documents its filter
        # as "a case-insensitive prefix match", which is exactly what StartsWith does. -like instead
        # interprets the typed word as a wildcard pattern (undocumented, untested), which throws on
        # an unbalanced '['. StartsWith cannot throw for any input string and preserves the
        # documented behaviour exactly, including the empty-word case ('' matches every candidate).
        if ($Name.StartsWith($Word, [System.StringComparison]::OrdinalIgnoreCase)) {
            $CompletionText = if ($Name -match '\s') { "'$Name'" } else { $Name }
            [System.Management.Automation.CompletionResult]::new(
                $CompletionText,
                $Name,
                [System.Management.Automation.CompletionResultType]::ParameterValue,
                $Name
            )
        }
    }
}
