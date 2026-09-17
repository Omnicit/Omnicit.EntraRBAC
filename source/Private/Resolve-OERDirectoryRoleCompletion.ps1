function Resolve-OERDirectoryRoleCompletion {
    <#
    .SYNOPSIS
    Builds argument-completer results for the -RoleName parameter from the curated directory-role set.

    .DESCRIPTION
    Backs the -RoleName argument completer registered for Add-OERAdministrativeUnitScopedRole and
    Remove-OERAdministrativeUnitScopedRole. It filters the curated directory-role display names (from
    Get-OERCommonDirectoryRoleName) by the text typed so far -- a case-insensitive prefix match, where an
    empty or absent word returns the entire set -- and emits one
    System.Management.Automation.CompletionResult per match. A role name that contains whitespace is
    wrapped in single quotes in the completion text so the inserted argument is valid as typed, while the
    list-item and tooltip keep the raw name. The completer is purely additive: custom directory-role
    names and role ids are still accepted on -RoleName because no ValidateSet is involved. This is the
    directory-role sibling of Resolve-OERRoleCompletion, which serves the Azure RBAC -Role parameter, and
    it performs no network call.

    .PARAMETER WordToComplete
    The partial text the user has typed for the -RoleName argument. Used as a case-insensitive prefix
    filter against the curated directory-role names (surrounding quotes are trimmed first). An empty or
    null value returns the entire curated set.

    .EXAMPLE
    Resolve-OERDirectoryRoleCompletion -WordToComplete 'User'
    Returns the completion result for 'User Administrator'.
    #>
    [OutputType([System.Management.Automation.CompletionResult])]
    [CmdletBinding()]
    param(
        [string]$WordToComplete
    )

    # WordToComplete is [string], so binding coerces an omitted value to '' (never $null). The guard is
    # defensive for callers that invoke this helper directly with $null; an empty word trims to '' and
    # matches every curated name.
    $Word = if ($WordToComplete) { $WordToComplete.Trim("'", '"') } else { '' }

    foreach ($Name in (Get-OERCommonDirectoryRoleName)) {
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
