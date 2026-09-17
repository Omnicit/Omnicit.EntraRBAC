function Test-OERGuid {
    <#
    .SYNOPSIS
    Tests whether a string is a canonical hyphenated GUID (object id).

    .DESCRIPTION
    The single GUID predicate for the whole module: every helper that must distinguish an object id
    from a friendly name (a UPN, a display name, a role name) calls this rather than re-implementing
    the pattern, so a future change to the accepted form happens in exactly one place. Used to tell
    an object id from a friendly name (UPN or display name) supplied to -PrincipalId. Returns $true
    only for the canonical 8-4-4-4-12 hyphenated form that ARM expects for principalId; returns
    $false for null/empty, names, braced GUIDs, and dash-less hex. Makes no network calls and does
    not throw.

    Deliberately strict: only the canonical 8-4-4-4-12 hyphenated form is accepted, because that is
    the form ARM requires for principalId. A caller that must also accept braced, parenthesised or
    dash-less GUIDs uses the wider [guid] cast instead -- Get-OERInventory and New-OERGroup do
    exactly that on purpose, and must not be migrated to this predicate.

    .PARAMETER Value
    The string value to test for canonical GUID format.

    .EXAMPLE
    Test-OERGuid -Value 'aaaa0000-0000-0000-0000-000000000001'
    Returns $true.

    .EXAMPLE
    Test-OERGuid -Value 'anna@contoso.com'
    Returns $false.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [string]$Value
    )
    return [bool]($Value -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
}
