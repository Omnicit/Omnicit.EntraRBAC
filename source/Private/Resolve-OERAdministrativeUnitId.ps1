function Resolve-OERAdministrativeUnitId {
    <#
    .SYNOPSIS
    Resolves an Entra ID administrative unit to its object id, accepting either an id or a display name.

    .DESCRIPTION
    Returns the object id for an administrative unit. When -Id is supplied it is returned unchanged
    without any Graph call. When -DisplayName is supplied a filtered v1.0/directory/administrativeUnits
    query is issued through Invoke-OERGraphRequest. Exactly one match returns that unit's id and no
    match returns $null; more than one match throws an ErrorRecord with ErrorId 'AmbiguousName'
    listing the candidate ids, because Entra does not enforce unique administrative unit display
    names and picking the first match would silently act on an arbitrary unit.
    The display name is escaped through ConvertTo-OERODataFilterValue, which
    doubles embedded single quotes and percent-encodes the value so reserved characters survive
    transport. This private helper is the single AU-lookup entry point used by the administrative-unit
    cmdlets.

    .PARAMETER Id
    The administrative unit object id (GUID) to return verbatim. Takes precedence over -DisplayName when
    both are supplied and no Graph call is made.

    .PARAMETER DisplayName
    The administrative unit display name to resolve to an id via a filtered query when -Id is not supplied.
    Escaped through ConvertTo-OERODataFilterValue (quote-doubling plus percent-encoding) before the OData
    filter is built.

    .EXAMPLE
    Resolve-OERAdministrativeUnitId -DisplayName 'au_hr_restricted'
    Returns the object id of the administrative unit with that display name, or $null when it does not exist.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$DisplayName
    )
    if ($Id) { return $Id }
    if (-not $DisplayName) {
        throw 'Resolve-OERAdministrativeUnitId requires either -Id or -DisplayName.'
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
    $Uri = "v1.0/directory/administrativeUnits?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Administrative unit display name '$DisplayName' matches $($Candidates.Count) units ($Ids). " +
                'Entra does not enforce unique administrative unit display names, so this name cannot ' +
                'identify a single unit. Re-run with the object id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $DisplayName)
    }
    if ($Candidates.Count -eq 1) {
        return [string]$Candidates[0].id
    }
    return $null
}
