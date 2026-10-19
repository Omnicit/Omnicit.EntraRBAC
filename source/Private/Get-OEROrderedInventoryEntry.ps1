function Get-OEROrderedInventoryEntry {
    <#
    .SYNOPSIS
    Puts the entries of one list of an inventory document in the module's one fixed order.

    .DESCRIPTION
    The single owner of the order the inventory writes its lists in (Sprint 11 step 10, BL-121): the
    members and owners of a group, the eligibility of a group and the members of an administrative
    unit. Graph answers each of these in no fixed order, so two reads of one unchanged tenant used to
    write the same set in two different orders, and the files differed for nothing; a document that is
    compared, versioned or read by a reviewer has to be stable. Never order such a list anywhere else.

    The order is total, so the same set of entries comes out the same whatever order it went in:
    - Text is ordered by [System.StringComparer]::OrdinalIgnoreCase first and by
      [System.StringComparer]::Ordinal where the two texts differ only in letter case, so 'Alice'
      stands before 'alice' and both stand before 'Bob'. Both comparers are culture independent, so the
      order is the same on every machine and in every session.
    - A number is ordered ascending, and an absent or null value stands before every number.
    - Without -Property each entry is itself a text. With -Property the entries are ordered by the
      named properties in turn, the first one the most significant: a property whose present values
      are all numbers is ordered as a number, and every other property as text, an absent one as the
      empty text. A property is read with PSObject.Properties, so a missing property is no error.
    - An entry that is a null is dropped. An entry that ties with another on every key keeps its place
      relative to it (the sort is stable), which is only visible when the entries differ in a property
      that is not named.

    It is pure: no request, no sign-in, no write. It writes the ordered entries to the pipeline, so a
    caller that needs an array wraps the call in @( ).

    .PARAMETER InputObject
    The entries of the list: texts, or objects when -Property is given. An empty collection or a null
    returns nothing.

    .PARAMETER Property
    The names of the properties to order the entries by, in order of significance. Omit it for a list of
    texts.

    .EXAMPLE
    @(Get-OEROrderedInventoryEntry -InputObject @('bob@contoso.com', 'Alice@contoso.com', 'alice@contoso.com'))
    Returns Alice@contoso.com, alice@contoso.com, bob@contoso.com.

    .EXAMPLE
    @(Get-OEROrderedInventoryEntry -InputObject $Eligibility -Property principal, accessType, durationDays, id)
    Orders eligibility entries by principal, then access type, then duration (a permanent eligibility,
    which has no durationDays, first), then id.
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [string[]]$Property
    )

    $Ordered = [object[]]@($InputObject | Where-Object { $null -ne $_ })
    if ($Ordered.Count -lt 2) { return $Ordered }

    # The key functions read nothing but the pair they are given: the key is carried by the pair, so the
    # delegate reads nothing else.
    $TextKey = [System.Func[object, string]] { param($Pair) $Pair.Key }
    $NumberKey = [System.Func[object, double]] { param($Pair) $Pair.Key }

    # One stable pass per key, the LEAST significant key first: a stable sort by the most significant
    # key last leaves the entries that tie on it in the order the earlier passes gave them, which is the
    # order by all the keys in turn. With no property there is one key, and a null key name stands for the
    # entry itself (a list of texts).
    $KeyCount = if (@($Property).Count -gt 0) { @($Property).Count } else { 1 }
    for ($KeyIndex = $KeyCount - 1; $KeyIndex -ge 0; $KeyIndex--) {
        $KeyName = if (@($Property).Count -gt 0) { @($Property)[$KeyIndex] } else { $null }
        # The value of this key for every entry: the entry itself, or the property of that name ($null for
        # an entry that has none). The key is a number only when every present value is one.
        $Values = [object[]]::new($Ordered.Count)
        $IsNumber = $true
        for ($EntryIndex = 0; $EntryIndex -lt $Ordered.Count; $EntryIndex++) {
            $Value = $Ordered[$EntryIndex]
            if ($null -ne $KeyName) {
                $KeyProperty = $Value.PSObject.Properties[$KeyName]
                $Value = if ($KeyProperty) { $KeyProperty.Value } else { $null }
            }
            $Values[$EntryIndex] = $Value
            if ($null -ne $Value -and $Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) {
                $IsNumber = $false
            }
        }
        $Pairs = [object[]]::new($Ordered.Count)
        for ($EntryIndex = 0; $EntryIndex -lt $Ordered.Count; $EntryIndex++) {
            $Key = if ($IsNumber) {
                if ($null -eq $Values[$EntryIndex]) { [double]::NegativeInfinity } else { [double]$Values[$EntryIndex] }
            } else {
                [string]$Values[$EntryIndex]
            }
            $Pairs[$EntryIndex] = [PSCustomObject]@{ Key = $Key; Entry = $Ordered[$EntryIndex] }
        }
        # OrderBy and ThenBy are .NET's own, with .NET's own comparers, and OrderBy is stable: a text pass
        # (OrderBy, then ThenBy) calls the key function twice per entry and a number pass once, never once
        # per comparison. The generic arguments are INFERRED from the typed arguments ($Pairs is an
        # [object[]], the key is a [Func[object, string]] or [Func[object, double]]), never written out:
        # an explicit type argument on a generic method call (::OrderBy[object, string](...)) is syntax
        # PowerShell has only since 7.3, a parse error in a module whose floor is 7.2, which fails the
        # whole merged module and which CI (a current PowerShell only) would not show. The test file
        # holds it: no call in this file may carry generic type arguments.
        $Sorted = if ($IsNumber) {
            [System.Linq.Enumerable]::ToArray(
                [System.Linq.Enumerable]::OrderBy($Pairs, $NumberKey))
        } else {
            [System.Linq.Enumerable]::ToArray(
                [System.Linq.Enumerable]::ThenBy(
                    [System.Linq.Enumerable]::OrderBy($Pairs, $TextKey, [System.StringComparer]::OrdinalIgnoreCase),
                    $TextKey, [System.StringComparer]::Ordinal))
        }
        $Ordered = [object[]]@(foreach ($Pair in $Sorted) { $Pair.Entry })
    }
    $Ordered
}
