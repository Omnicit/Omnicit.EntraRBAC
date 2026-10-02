function Resolve-OERAccessReviewDefinitionId {
    <#
    .SYNOPSIS
    Resolves an access review definition to its id, accepting either an id or a display name.

    .DESCRIPTION
    Returns the access review definition id. When -Id is supplied it is returned unchanged without any
    Graph call. When -DisplayName is supplied and the value is a GUID it is returned verbatim (treated
    as an id) with no Graph call. Otherwise a filtered query against the access reviews definitions
    collection is issued through Invoke-OERGraphRequest. Exactly one match returns that definition's id
    and no match returns $null; more than one match throws an ErrorRecord with ErrorId 'AmbiguousName'
    listing the candidate ids, because access review definition display names are not unique and
    picking the first match would silently act on an arbitrary definition -- delete it, overwrite it,
    or stop or decide one of its instances.
    The display name is escaped through
    ConvertTo-OERODataFilterValue, which doubles embedded single quotes and percent-encodes the value
    so reserved characters survive transport. This private helper is the single
    access-review-definition-lookup entry point used by the access review cmdlets.

    .PARAMETER Id
    The access review definition id (GUID) to return verbatim. Takes precedence over -DisplayName; no
    Graph call is made.

    .PARAMETER DisplayName
    The access review definition display name to resolve to an id via a filtered query when -Id is not
    supplied. If the value is a GUID it is returned verbatim (treated as an id) with no Graph call.

    .EXAMPLE
    Resolve-OERAccessReviewDefinitionId -DisplayName 'Q3 Review'
    Returns the id of the access review definition with that display name, or $null when it does not
    exist. Throws an AmbiguousName error naming every candidate id when more than one definition
    carries that display name.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$DisplayName
    )
    if ($Id) { return $Id }
    if (-not $DisplayName) {
        throw 'Resolve-OERAccessReviewDefinitionId requires either -Id or -DisplayName.'
    }
    if (Test-OERGuid -Value $DisplayName) {
        return $DisplayName
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
    $Uri = "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Access review definition display name '$DisplayName' matches $($Candidates.Count) definitions ($Ids). " +
                'Access reviews do not enforce unique definition display names, so this name ' +
                'cannot identify a single definition. Re-run with the definition id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $DisplayName)
    }
    if ($Candidates.Count -eq 1) {
        return [string]$Candidates[0].id
    }
    return $null
}
