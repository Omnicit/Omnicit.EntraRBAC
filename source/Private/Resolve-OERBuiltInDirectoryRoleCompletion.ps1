function Resolve-OERBuiltInDirectoryRoleCompletion {
    <#
    .SYNOPSIS
    Builds argument-completer results for the -Role parameter from the built-in directory-role set.

    .DESCRIPTION
    Backs the -Role argument completer registered for Get-OERDirectoryRoleManagementPolicy and
    Set-OERDirectoryRoleManagementPolicy. It filters the tenant-wide built-in directory-role display
    names (from Get-OERBuiltInDirectoryRoleName) by the text typed so far -- a case-insensitive prefix
    match, where an empty or absent word returns the entire set -- and emits one
    System.Management.Automation.CompletionResult per match. A role name that contains whitespace is
    wrapped in single quotes in the completion text so the inserted argument is valid as typed, while
    the list-item and tooltip keep the raw name. The completer is purely additive: custom directory-
    role names and role definition ids are still accepted on -Role because no ValidateSet is involved.
    This is the tenant-wide sibling of Resolve-OERDirectoryRoleCompletion, which serves the
    administrative-unit-scoped -RoleName parameter, and it performs no network call.

    .PARAMETER WordToComplete
    The partial text the user has typed for the -Role argument. Used as a case-insensitive prefix
    filter against the built-in directory-role names (surrounding quotes are trimmed first). An empty
    or null value returns the entire set.

    .EXAMPLE
    Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete 'Reports'
    Returns the completion result for 'Reports Reader'.
    #>
    [OutputType([System.Management.Automation.CompletionResult])]
    [CmdletBinding()]
    param(
        [string]$WordToComplete
    )

    # WordToComplete is [string], so binding coerces an omitted value to '' (never $null). The guard is
    # defensive for callers that invoke this helper directly with $null; an empty word trims to '' and
    # matches every built-in name.
    $Word = if ($WordToComplete) { $WordToComplete.Trim("'", '"') } else { '' }

    foreach ($Name in (Get-OERBuiltInDirectoryRoleName)) {
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
