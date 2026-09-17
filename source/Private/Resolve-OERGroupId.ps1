function Resolve-OERGroupId {
    <#
    .SYNOPSIS
    Resolves an Entra ID group to its object id, accepting either an explicit id or a display name.

    .DESCRIPTION
    Returns the object id for a group. When -Id is supplied it is returned unchanged without any
    Graph call. When -DisplayName is supplied and the value is a GUID it is returned verbatim
    (treated as an id) with no Graph call. Otherwise a filtered v1.0/groups query is issued through
    Invoke-OERGraphRequest. Exactly one match returns that group's id and no match returns $null;
    more than one match throws an ErrorRecord with ErrorId 'AmbiguousName' listing the candidate
    ids, because Entra does not enforce unique group display names and picking the first match would
    silently act on an arbitrary group. The display name is escaped through
    ConvertTo-OERODataFilterValue, which doubles
    embedded single quotes and percent-encodes the value so reserved characters survive transport.
    This private helper is the single group-lookup entry point used by the group sub-cmdlets.

    .PARAMETER Id
    The group object id (GUID) to return verbatim. Takes precedence over -DisplayName when both
    are supplied and no Graph call is made.

    .PARAMETER DisplayName
    The group display name to resolve to an id via a filtered groups query when -Id is not supplied.
    If the value is a GUID it is returned verbatim (treated as an id) with no Graph call.
    Escaped through ConvertTo-OERODataFilterValue (quote-doubling plus percent-encoding) before
    the OData filter is built.

    .EXAMPLE
    Resolve-OERGroupId -DisplayName 'role_sec_identity_administrator'
    Returns the object id of the group with that display name, or $null when it does not exist.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$DisplayName
    )
    if ($Id) { return $Id }
    if (-not $DisplayName) {
        throw 'Resolve-OERGroupId requires either -Id or -DisplayName.'
    }
    if (Test-OERGuid -Value $DisplayName) {
        return $DisplayName
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
    $Uri = "v1.0/groups?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Group display name '$DisplayName' matches $($Candidates.Count) groups ($Ids). " +
                'Entra does not enforce unique group display names, so this name cannot identify a ' +
                'single group. Re-run with the object id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $DisplayName)
    }
    if ($Candidates.Count -eq 1) {
        return [string]$Candidates[0].id
    }
    return $null
}
