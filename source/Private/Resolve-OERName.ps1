function Resolve-OERName {
    <#
    .SYNOPSIS
    Builds a standardized object name from a template and a set of token values.

    .DESCRIPTION
    Substitutes {token} placeholders in a naming template with values from the Tokens hashtable to
    produce a standardized name for a group, Administrative Unit, catalog, or other object. Token
    matching is case-insensitive. Any placeholder left unresolved is treated as a caller error and
    raises a terminating error so that no malformed name is ever returned. The result is validated
    against an optional maximum length and, when -Strict is set, against a set of characters that
    are disallowed in Entra ID object names.

    .PARAMETER Template
    The naming template containing zero or more {token} placeholders, e.g. 'role_sec_{area}_{tier}'.

    .PARAMETER Tokens
    A hashtable mapping token names (without braces) to their replacement string values.

    .PARAMETER MaxLength
    The maximum allowed length of the resolved name. Defaults to 256. A longer result is rejected.

    .PARAMETER Strict
    When set, rejects resolved names containing characters that are not allowed in Entra ID object
    display names or mail nicknames.

    .EXAMPLE
    Resolve-OERName -Template 'role_sec_{area}_{tier}' -Tokens @{ area = 'identity'; tier = 'administrator' }
    Returns 'role_sec_identity_administrator'.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Template,
        [Parameter(Mandatory)]
        [hashtable]$Tokens,
        [int]$MaxLength = 256,
        [switch]$Strict
    )

    $Result = $Template
    foreach ($Key in $Tokens.Keys) {
        $Result = $Result -replace ('\{' + [regex]::Escape($Key) + '\}'), [string]$Tokens[$Key]
    }

    $Unresolved = [regex]::Matches($Result, '\{(?<token>[^}]+)\}') | ForEach-Object { $_.Groups['token'].Value }
    if ($Unresolved.Count -gt 0) {
        throw "Naming template '$Template' has unresolved token(s): $($Unresolved -join ', '). Supply a value for each token."
    }

    if ($Result.Length -gt $MaxLength) {
        throw "Resolved name '$Result' exceeds the maximum length of $MaxLength characters."
    }

    if ($Strict -and $Result -match '[\\/\[\]:;|=,+*?<>@"]') {
        throw "Resolved name '$Result' contains a disallowed character for an Entra ID object name."
    }

    $Result
}
