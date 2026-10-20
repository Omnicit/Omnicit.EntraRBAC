function Resolve-OERName {
    <#
    .SYNOPSIS
    Builds a standardized object name from a template and a set of token values.

    .DESCRIPTION
    Substitutes {token} placeholders in a naming template with values from the Tokens hashtable to
    produce a standardized name for a group, Administrative Unit, catalog, or other object. Token
    matching is case-insensitive. The template is read in a single pass and each value is inserted as
    text: a '$' in a value is never interpreted (it is not a replacement pattern), and a value is
    never read again as a template, so a value that looks like a {token} stays as it is. Any
    placeholder of the template that has no value is treated as a caller error and raises a
    terminating error so that no malformed name is ever returned. The result is validated
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

    # BL-139: the template is read in ONE pass and each value is inserted as text. The earlier loop ran a
    # -replace per token, which read a value as a .NET replacement pattern (a '$&' in a value inserted the
    # matched '{token}' text, '$$' became '$') and read it again as a template for the tokens that came
    # after it (a value of '{other}' was replaced by other's value, or left behind to be reported as an
    # unresolved token). A MatchEvaluator returns the value as it is and never scans it again, and the
    # unresolved tokens are the template's own: the ones with no key.
    $Lookup = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Key in $Tokens.Keys) {
        $Lookup[[string]$Key] = [string]$Tokens[$Key]
    }

    $Unresolved = [System.Collections.Generic.List[string]]::new()
    $Substitute = [System.Text.RegularExpressions.MatchEvaluator] {
        param($Match)
        $TokenName = $Match.Groups['token'].Value
        if ($Lookup.ContainsKey($TokenName)) {
            return $Lookup[$TokenName]
        }
        $Unresolved.Add($TokenName)
        return $Match.Value
    }
    $Result = [regex]::Replace($Template, '\{(?<token>[^}]+)\}', $Substitute)

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
