function Get-OEROmittedPruneCollection {
    <#
    .SYNOPSIS
    Lists the collection keys an apply document omits although Invoke-OERStructure -Prune still reconciles them.

    .DESCRIPTION
    The single owner of the rule "which omitted collection keys prune". Five collections in an apply
    document are reconciled even when their key is OMITTED -- against an empty declared set -- so
    Invoke-OERStructure -Prune removes every live entry in them: groups[].members,
    administrativeUnits[].members, administrativeUnits[].scopedRoles, catalogs[].resources and
    accessPackages[].resourceRoles. This helper finds every such omission so that
    Test-OERStructureSchema can report it as a Warning finding and Invoke-OERStructure -Prune can
    list it in one warning before anything is written.

    A key counts as omitted only when it is absent altogether: neither Test-OERDeclaredProperty nor
    Test-OERDeclaredNull holds for it. An explicit null is the documented "leave this collection
    untouched" signal and is never listed, and a declared array -- an empty one included -- is a
    deliberate reconcile and is never listed either. The members key of a group or an administrative
    unit that the document declares "dynamic": true is not listed, since both handlers skip the member
    prune on a dynamic object; the scopedRoles of a dynamic unit still prune and are still listed. A
    live-dynamic object the document does not declare dynamic cannot be known offline, so its omitted
    members key is listed -- the conservative direction.

    Owners and eligibility are deliberately not listed: an omitted owners or eligibility key leaves
    that collection completely untouched, since both passes run only when the key is declared, so
    omitting either one can never prune.

    Returns one record per (item, collection), carrying Section (the document key, for example
    groups), Item (the item's displayName when declared, otherwise its path, the same label the
    validator uses -- a template group has no displayName), Path (for example groups[0]) and
    Collection (for example members). Records come in the engine's dispatch order -- groups,
    administrativeUnits, catalogs, accessPackages -- then in document order, and for an
    administrative unit members before scopedRoles. A section that is absent, null or not an array,
    and an item that is not an object, are skipped without error, since the offline validator also
    calls this helper on an invalid document.

    .PARAMETER Document
    The parsed apply document (from Read-OERStructureDocument or ConvertFrom-Json) to inspect.

    .EXAMPLE
    Get-OEROmittedPruneCollection -Document ('{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }' | ConvertFrom-Json)

    Returns one record: Section groups, Item g1, Path groups[0], Collection members.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Document
    )

    # Every collection the Sync-OERStructure* handlers reconcile on an omitted key, per section, in the
    # order Invoke-OERStructure dispatches the sections.
    $PruningCollection = @(
        [PSCustomObject]@{ Section = 'groups';              Collection = @('members') }
        [PSCustomObject]@{ Section = 'administrativeUnits'; Collection = @('members', 'scopedRoles') }
        [PSCustomObject]@{ Section = 'catalogs';            Collection = @('resources') }
        [PSCustomObject]@{ Section = 'accessPackages';      Collection = @('resourceRoles') }
    )

    foreach ($Entry in $PruningCollection) {
        if (-not (Test-OERDeclaredProperty -Node $Document -Name $Entry.Section)) { continue }
        $SectionValue = $Document.($Entry.Section)
        if ($SectionValue -isnot [System.Collections.IEnumerable] -or $SectionValue -is [string]) { continue }

        $Items = @($SectionValue)
        for ($I = 0; $I -lt $Items.Count; $I++) {
            $Node = $Items[$I]
            if ($Node -isnot [System.Management.Automation.PSCustomObject]) { continue }

            $ItemPath = '{0}[{1}]' -f $Entry.Section, $I
            $ItemLabel = if (Test-OERDeclaredProperty -Node $Node -Name 'displayName') { [string]$Node.displayName } else { $ItemPath }
            # Both handlers skip the member prune on an object that is dynamic, and on the create path
            # the document's own "dynamic": true is what makes it so.
            $DeclaredDynamic = (Test-OERDeclaredProperty -Node $Node -Name 'dynamic') -and [bool]$Node.dynamic

            foreach ($Key in $Entry.Collection) {
                if (Test-OERDeclaredProperty -Node $Node -Name $Key) { continue }
                if (Test-OERDeclaredNull -Node $Node -Name $Key) { continue }
                if ($Key -eq 'members' -and $DeclaredDynamic) { continue }
                [PSCustomObject]@{
                    Section    = $Entry.Section
                    Item       = $ItemLabel
                    Path       = $ItemPath
                    Collection = $Key
                }
            }
        }
    }
}
