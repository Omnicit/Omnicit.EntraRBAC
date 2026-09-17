function Resolve-OERTenantAliasCompletion {
    <#
    .SYNOPSIS
    Builds argument-completer results for the -TenantAlias parameter from the Tenant Profile files on
    disk.

    .DESCRIPTION
    Backs the -TenantAlias argument completer registered for Connect-OER, Get-OERConfiguration,
    Set-OERConfiguration and Remove-OERConfiguration. It lists the *.psd1 Tenant Profile files under the
    profile base directory, uses each file's base name as the alias, and filters them by the text typed
    so far -- a case-insensitive prefix match, where an empty or absent word returns every alias. One
    System.Management.Automation.CompletionResult is emitted per match. An alias that contains
    whitespace is wrapped in single quotes in the completion text so the inserted argument is valid as
    typed, while the list-item and tooltip keep the raw alias. Completion must never fail or block the
    prompt, so a missing or unreadable profile directory simply yields no results instead of an error.
    The completer is purely additive: any alias string is still accepted on -TenantAlias because no
    ValidateSet is involved. This helper performs no network call.

    .PARAMETER WordToComplete
    The partial text the user has typed for the -TenantAlias argument. Used as a case-insensitive
    prefix filter against the profile base names (surrounding quotes are trimmed first). An empty or
    null value returns every stored alias.

    .PARAMETER BasePath
    The base directory that contains the per-alias profile files. Defaults to the user's
    Omnicit.EntraRBAC config folder, and is overridden by the -BasePath / -ProfileBasePath value the
    user has already typed on the command line being completed.

    .EXAMPLE
    Resolve-OERTenantAliasCompletion -WordToComplete 'con'
    Returns completion results for every stored tenant alias that starts with 'con'.
    #>
    [OutputType([System.Management.Automation.CompletionResult])]
    [CmdletBinding()]
    param(
        [string]$WordToComplete,
        # USERPROFILE is a Windows-only variable and this module declares CompatiblePSEditions
        # Core, so binding this default threw on Linux and macOS before the body ever ran. .NET
        # returns the same directory as $env:USERPROFILE on Windows -- the resolved path is
        # unchanged there -- and the home directory on Linux and macOS.
        [string]$BasePath = (Join-Path $(
                $ProfileRoot = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
                if ($ProfileRoot) { $ProfileRoot } else { $HOME }
            ) '.config/Omnicit.EntraRBAC/Profiles')
    )

    # A completer runs on the interactive prompt path: it must never throw and never emit an error
    # record, so an absent or unreadable profile directory yields an empty completion list instead.
    if (-not $BasePath -or -not (Test-Path -LiteralPath $BasePath)) { return }

    # WordToComplete is [string], so binding coerces an omitted value to '' (never $null). The guard is
    # defensive for callers that invoke this helper directly with $null; an empty word trims to '' and
    # matches every alias.
    $Word = if ($WordToComplete) { $WordToComplete.Trim("'", '"') } else { '' }

    $Files = @(Get-ChildItem -LiteralPath $BasePath -Filter '*.psd1' -File -ErrorAction SilentlyContinue)
    foreach ($File in ($Files | Sort-Object -Property Name)) {
        $TenantAlias = $File.BaseName
        # StartsWith, not -like: every one of this module's completion helpers documents its filter
        # as "a case-insensitive prefix match", which is exactly what StartsWith does. -like instead
        # interprets the typed word as a wildcard pattern (undocumented, untested), which throws on
        # an unbalanced '['. StartsWith cannot throw for any input string and preserves the
        # documented behaviour exactly, including the empty-word case ('' matches every candidate).
        if ($TenantAlias.StartsWith($Word, [System.StringComparison]::OrdinalIgnoreCase)) {
            $CompletionText = if ($TenantAlias -match '\s') { "'$TenantAlias'" } else { $TenantAlias }
            [System.Management.Automation.CompletionResult]::new(
                $CompletionText,
                $TenantAlias,
                [System.Management.Automation.CompletionResultType]::ParameterValue,
                $TenantAlias
            )
        }
    }
}
