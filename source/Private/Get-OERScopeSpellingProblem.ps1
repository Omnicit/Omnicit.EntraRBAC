function Get-OERScopeSpellingProblem {
    <#
    .SYNOPSIS
    Returns every scope spelling rule an Azure scope breaks, with the validator's message for each.

    .DESCRIPTION
    The single owner of the two scope spelling rules that Test-OERStructureSchema applies to the scope
    of a roleAssignments and a roleManagementPolicies entry, that Get-OERInventory applies to the
    scope of every role assignment it reads (A13, A15; docs/development/rationale.md#undeclarable-scope),
    and that Get-OERSubscriptionHomeTenant applies to every scope it is asked about other than an 'mg:'
    form (BL-150, Ruling R-27; docs/development/rationale.md#home-tenant-subscriptions). The validator
    refuses a scope that breaks either rule, so a document can never declare it; the inventory leaves a
    role assignment at such a scope out of the document it writes; and the home tenant owner rates such
    a scope Undecided, resolving and reading nothing for it, so an Export-OERInventory -Scope spelled so
    is not read and is named in IncompleteReads.

    The first rule (A15): a scope that ends with '/' (other than the root '/' itself) or contains '//'
    anywhere. ConvertTo-OERCanonicalScope strips every trailing '/', so such a spelling would be merged
    with the scope written without it. It applies to every scope, a friendly form included.

    The second rule (A13): a scope written as an Azure Resource Manager path is sent as written, as part
    of a System.Uri, while the engine groups entries on the text's canonical form, so a spelling the
    request reads as another scope would let two spellings of one scope form two groups. Each check is a
    problem of its own, so one scope can break several:
    - DotSegment: a '.' or '..' segment, with '/' or '\' as the separator (System.Uri removes it);
    - Escape: any '%' (an escape can let two spellings reach one resource);
    - Backslash: any '\' (System.Uri reads it as '/');
    - QueryOrFragment: any '?' or '#' (either ends the path of the request URI);
    - WhiteSpace: white space at the start or end of the scope or of a segment, white space other than
      a space (U+0020) anywhere, or a control character anywhere. One or more spaces BETWEEN other
      characters of a segment are accepted, since an Azure resource name can hold them.
    The mg:, sub: and subscription: forms are exempt from the second rule: they name a management group
    or subscription by id, name or display name and are resolved by a lookup, never sent as written.
    ConvertTo-OERScopeSplat owns that syntax, so the exemption asks it: only a scope it returns as
    @{ Scope = ... } is checked.

    This help is the reference list of the rules. Seven texts hold no full list and point elsewhere:
    the help of Test-OERStructureSchema and of Get-OERStructureSchemaJson point at this help; the help
    of Get-OERInventory and of Export-OERInventory give an example and point at the about topic
    (about_Omnicit.EntraRBAC, RENAMES, MAIL ALIASES AND SCOPE SPELLING), and the help of
    Get-OERInventory points at Test-OERStructure as well; the bundle README Get-OERInventoryReadme
    writes gives an example and leaves the rules to each listed entry's Reason; and the prompt and
    docs/inventory-to-llm/README.md point at the scope description in schema.json. Five texts do list
    them for their readers, and a rule added here is added to each: README.md, the about topic
    (RENAMES, MAIL ALIASES AND SCOPE SPELLING), the two scope descriptions in the JSON
    Get-OERStructureSchemaJson returns, the ConvertTo-OERCanonicalScope bullet of CLAUDE.md, and the
    words Get-OERInventory gives each Rule in the Reason of its UndeclarableScope record (a Rule it has
    no words for is named there by its Rule name). docs/development/rationale.md records why each rule
    exists.

    Returns one PSCustomObject per broken rule, in the order the validator reports them -- Slash, then
    DotSegment, Escape, Backslash, QueryOrFragment and WhiteSpace -- with Rule (one of those six names)
    and Message (the validator's exact message for the scope at -Path). Returns nothing for a scope that
    breaks no rule, an empty or null scope included. Pure and offline: no request, no warning, no error
    record, and it never throws for a scope.

    .PARAMETER Scope
    The scope as a document wrote it, or as Azure Resource Manager returned it. Null and an empty string
    are accepted and break no rule.

    .PARAMETER Path
    The path of the entry the scope belongs to, as the validator names it ('roleAssignments[0]', for
    instance). It is used in the messages only: "'scope' at <Path> must be written without ...".

    .EXAMPLE
    Get-OERScopeSpellingProblem -Scope '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Sql/servers/srv1/databases/db#1' -Path 'roleAssignments[0]'
    Returns one problem with Rule QueryOrFragment and the message "'scope' at roleAssignments[0] must be
    written without a '?' or '#': ...".

    .EXAMPLE
    Get-OERScopeSpellingProblem -Scope 'mg:Contoso Root' -Path 'roleManagementPolicies[2]'
    Returns nothing: a friendly form is looked up, never sent as written, and holds no stray '/'.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Scope,
        [Parameter(Mandatory)][string]$Path
    )

    $ScopeText = [string]$Scope
    if (($ScopeText.EndsWith('/') -and $ScopeText -cne '/') -or $ScopeText.Contains('//')) {
        [PSCustomObject]@{
            Rule    = 'Slash'
            Message = "'scope' at $Path must be written without a trailing or doubled '/'. Got: '$ScopeText'."
        }
    }

    if (-not (ConvertTo-OERScopeSplat -Scope $ScopeText).ContainsKey('Scope')) { return }
    $Segments = @($ScopeText -split '[/\\]')
    if (@($Segments | Where-Object { $_ -ceq '.' -or $_ -ceq '..' }).Count -gt 0) {
        [PSCustomObject]@{
            Rule    = 'DotSegment'
            Message = "'scope' at $Path must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '$ScopeText'."
        }
    }
    if ($ScopeText.Contains('%')) {
        [PSCustomObject]@{
            Rule    = 'Escape'
            Message = ("'scope' at $Path must be written without a '%': an escape can let two spellings reach one resource, and the " +
                "names of most Azure resource types hold no '%'. Got: '$ScopeText'. A resource whose name holds one cannot be " +
                'declared in a document; remove the entry.')
        }
    }
    if ($ScopeText.Contains('\')) {
        [PSCustomObject]@{
            Rule    = 'Backslash'
            Message = ("'scope' at $Path must be written without a '\': the request reads it as '/', so the scope would be a second " +
                "spelling of the one written with '/'. Got: '$ScopeText'. A resource whose name holds one cannot be declared in a " +
                'document; remove the entry.')
        }
    }
    if ($ScopeText.Contains('?') -or $ScopeText.Contains('#')) {
        [PSCustomObject]@{
            Rule    = 'QueryOrFragment'
            Message = ("'scope' at $Path must be written without a '?' or '#': either ends the path of the request, which would " +
                "then name another scope than the one written. Got: '$ScopeText'. A resource whose name holds one cannot be " +
                'declared in a document; remove the entry.')
        }
    }
    # String.Trim() removes exactly the characters [char]::IsWhiteSpace reports, at both ends.
    $EdgeWhiteSpace = @($Segments | Where-Object { $_ -cne $_.Trim() }).Count -gt 0
    $OtherWhiteSpace = @($ScopeText.ToCharArray() | Where-Object {
            [char]::IsControl($_) -or ([char]::IsWhiteSpace($_) -and [int]$_ -ne 32)
        } | Select-Object -Unique)
    if ($EdgeWhiteSpace -or $OtherWhiteSpace.Count -gt 0) {
        $Named = if ($OtherWhiteSpace.Count -gt 0) {
            ' It contains ' + (($OtherWhiteSpace | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ', ') + '.'
        } else { '' }
        [PSCustomObject]@{
            Rule    = 'WhiteSpace'
            Message = ("'scope' at $Path must be written without white space at the start or end of the scope or of a segment, " +
                "white space other than a space (U+0020) or a control character; a space between other characters of a segment " +
                "is accepted. Got: '$ScopeText'.$Named A resource whose name holds one of these cannot be declared in a " +
                'document; remove the entry.')
        }
    }
}
