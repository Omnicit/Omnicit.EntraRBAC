function Resolve-OERStructureRoleAssignmentScope {
    <#
    .SYNOPSIS
    Resolves the scope of every roleAssignments entry once, before the apply engine dispatches any.

    .DESCRIPTION
    The roleAssignments scope pre-pass of the apply engine. Invoke-OERStructure calls it before the
    first entry of the section is dispatched, so every entry's scope is resolved exactly once per run
    and the engine can group the entries on the scope they resolve to rather than on the text the
    document wrote.

    For each entry, in document order, the scope text is parsed by ConvertTo-OERScopeSplat, resolved
    to an Azure Resource Manager scope by Resolve-OERScope, and normalized by
    ConvertTo-OERCanonicalScope, so a trailing '/' never reaches a comparison. Each distinct scope
    TEXT is resolved once per run: a successful resolution is cached by its exact text (ordinal, so
    'sub:Prod' and 'SUB:Prod' are two lookups) and reused by every later entry with the same text.
    Only successes are cached. A failure is never shared, so a transient failure on one entry does
    not fail the next entry with the same text, which resolves again on its own.

    A failure does not throw. The record is scrubbed with Remove-OERErrorRecord and returned on the
    entry's own result, with a null Scope, for the engine to publish as itself and report that entry
    Failed without dispatching it.

    Returns one PSCustomObject per entry, in document order, with these properties:
    - Index: the entry's position in the section.
    - Item: the document entry itself.
    - Label: '<role> -> <principal> @ <scope>', with the scope exactly as the document wrote it, the
      label every row of this entry carries.
    - RawScope: the scope exactly as the document wrote it.
    - Scope: the canonical resolved scope, or null when the scope could not be resolved.
    - ErrorRecord: the scrubbed record of a failed resolution, or null on success.

    .PARAMETER Item
    The roleAssignments[] entries of the structure document, in document order. Each is expected to
    carry scope, role and principal.

    .EXAMPLE
    $RaScope = @(Resolve-OERStructureRoleAssignmentScope -Item @($Document.roleAssignments))
    Resolves every roleAssignments scope once and returns one record per entry, in document order.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Item
    )

    $Resolved = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    for ($Index = 0; $Index -lt $Item.Count; $Index++) {
        $Entry = $Item[$Index]
        $RawScope = [string]$Entry.scope
        $Scope = $null
        $ErrorRecord = $null
        if ($Resolved.ContainsKey($RawScope)) {
            $Scope = $Resolved[$RawScope]
        } else {
            try {
                $Splat = ConvertTo-OERScopeSplat -Scope $RawScope
                $Scope = ConvertTo-OERCanonicalScope -Scope (Resolve-OERScope @Splat)
                $Resolved[$RawScope] = $Scope
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $ErrorRecord = $PSItem
            }
        }
        [PSCustomObject]@{
            Index       = $Index
            Item        = $Entry
            Label       = "$($Entry.role) -> $($Entry.principal) @ $RawScope"
            RawScope    = $RawScope
            Scope       = $Scope
            ErrorRecord = $ErrorRecord
        }
    }
}
