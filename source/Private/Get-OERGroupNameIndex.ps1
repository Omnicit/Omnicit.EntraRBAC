function Get-OERGroupNameIndex {
    <#
    .SYNOPSIS
    Returns an index of which groups in the tenant carry each display name.

    .DESCRIPTION
    The single owner of "which groups in the tenant carry a display name" (BL-131). Microsoft Entra ID
    does not keep group display names unique, and the apply engine refuses a name that more than one
    live group answers to, so an inventory counts a name over every group in the tenant -- Microsoft
    365 groups and distribution groups included -- and not only over the security-enabled groups it
    writes.

    The index is built from one of two sources:
    - With -Group, from the groups given (Export-OERInventory passes its roster, the unfiltered list
      of every group in the tenant): each item's Id and DisplayName, the names ConvertTo-OERGroup
      gives them. No request is made.
    - Without -Group, from ONE paged listing of every group's id and display name
      (v1.0/groups?$select=id,displayName&$top=999, every page), which Get-OERInventory makes at most
      once per invocation.

    It returns ONE tagged Omnicit.EntraRBAC.GroupNameIndex object and never writes an error record:
    - Read: true when the index was built, false when the listing failed.
    - IdsByName: a dictionary from a display name, compared without regard to letter case, to the
      lower-cased object ids of the groups that carry it, each id listed once per name. A name that
      is empty or white space only, and a group without an id, are skipped. Null when the listing
      failed: a failed read is never an empty index.
    - Message: null when the index was built; otherwise 'Could not list every group to count the
      names groups share: ' followed by the failure's message.

    A failed listing is caught, its record scrubbed first (Remove-OERErrorRecord), and returned as
    Read false; it is never thrown. The calling command must already have signed in
    (Initialize-OERAuth); this function makes no sign-in of its own.

    .PARAMETER Group
    The groups to build the index from, each with Id and DisplayName (Get-OERGroup output). A null
    item is skipped. Bound, no request is made, even when it holds no group; left out, the index is
    read with one paged listing of every group in the tenant.

    .EXAMPLE
    $Index = Get-OERGroupNameIndex -Group $RosterGroups
    $Index.IdsByName['Admins'].Count
    Builds the index from groups already read, with no request, and counts the groups named Admins in
    any letter case.

    .EXAMPLE
    $Index = Get-OERGroupNameIndex
    if (-not $Index.Read) { Write-Verbose $Index.Message }
    Lists every group in the tenant once to build the index, and reports the failure when the listing
    could not be read.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Group
    )

    $NewResult = {
        param([bool]$Read, $IdsByName, $Message)
        $O = [PSCustomObject]@{
            Read      = $Read
            IdsByName = $IdsByName
            Message   = $Message
        }
        $O.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupNameIndex')
        $O
    }

    # Each row as an id and a name: from the converter's names when the groups are given, from Graph's
    # when they are listed. The null-filter keeps an answer without a value from becoming one row.
    $Rows = [System.Collections.Generic.List[object]]::new()
    if ($PSBoundParameters.ContainsKey('Group')) {
        foreach ($Item in @($Group)) {
            if ($null -eq $Item) { continue }
            $Rows.Add([PSCustomObject]@{ Id = [string]$Item.Id; Name = [string]$Item.DisplayName })
        }
    } else {
        try {
            $Response = Invoke-OERGraphRequest -Uri 'v1.0/groups?$select=id,displayName&$top=999' -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            return (& $NewResult $false $null "Could not list every group to count the names groups share: $($PSItem.Exception.Message)")
        }
        foreach ($Item in @(@($Response.value) | Where-Object { $null -ne $PSItem })) {
            $Rows.Add([PSCustomObject]@{ Id = [string]$Item.id; Name = [string]$Item.displayName })
        }
    }

    # Keyed without regard to letter case, the key the validator refuses a duplicate on. Ids are
    # lower-cased so one group read twice, in two spellings of its id, is counted once.
    $IdsByName = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Row in $Rows) {
        if ([string]::IsNullOrWhiteSpace($Row.Name) -or [string]::IsNullOrWhiteSpace($Row.Id)) { continue }
        $Id = $Row.Id.ToLowerInvariant()
        if (-not $IdsByName.ContainsKey($Row.Name)) {
            $IdsByName[$Row.Name] = [System.Collections.Generic.List[string]]::new()
        }
        if (-not $IdsByName[$Row.Name].Contains($Id)) { $IdsByName[$Row.Name].Add($Id) }
    }
    & $NewResult $true $IdsByName $null
}
