function Resolve-OERDirectoryRoleDefinitionId {
    <#
    .SYNOPSIS
    Resolves a Microsoft Entra directory role definition name to its unifiedRoleDefinition id.

    .DESCRIPTION
    Returns the unifiedRoleDefinition id for a directory role, given either its display name or its
    id. When -Role is a GUID it is returned lower-cased (treated as an id) with no Graph call: the
    callers put it into a roleDefinitionId eq '...' OData filter, where Microsoft Graph's handling
    of letter case is not established, so the id always goes out in the lower-case form Graph
    itself returns. Otherwise the match runs in up to two steps. First, a filtered
    v1.0/roleManagement/directory/roleDefinitions query (displayName eq '...') is issued through
    Invoke-OERGraphRequest, which covers both built-in and custom role definitions -- unlike
    Resolve-OERDirectoryRoleId, this helper never activates a directory role from its template: a
    role definition already exists for every role, activated or not, so no POST is ever made and
    no call ever targets v1.0/directoryRoles. Microsoft Graph compares displayName on
    roleDefinitions case-sensitively, so when that exact-case request finds nothing, the whole list
    of role definitions is read (-All) and compared against -Role without regard to letter case
    (OrdinalIgnoreCase); the exact-case request always runs first, so a name typed in its exact
    case costs one request and never meets a case-only twin. A unique match in either step returns
    that definition's id; no match in either step returns $null; more than one match in either
    step throws an ErrorRecord with ErrorId 'AmbiguousName' listing the candidate ids, since a
    caller-supplied display name is not guaranteed unique. The display name is escaped through
    ConvertTo-OERODataFilterValue, which doubles embedded single quotes and percent-encodes the
    value so reserved characters (including a space) survive transport. A Graph transport or
    permission failure is not caught here and propagates to the caller unchanged.

    .PARAMETER Role
    The directory role definition display name or id to resolve. Mandatory: an empty string is
    rejected at parameter binding, the same as a missing value. If the value is a GUID it is returned
    lower-cased (treated as an id) with no Graph call. Otherwise escaped through
    ConvertTo-OERODataFilterValue (quote-doubling plus percent-encoding) before the OData filter is
    built.

    .EXAMPLE
    Resolve-OERDirectoryRoleDefinitionId -Role 'Reports Reader'
    Returns the unifiedRoleDefinition id of the built-in 'Reports Reader' role, or $null when no
    directory role definition has that display name.

    .EXAMPLE
    Resolve-OERDirectoryRoleDefinitionId -Role '11111111-1111-1111-1111-111111111111'
    Returns '11111111-1111-1111-1111-111111111111' with no Graph call, since the value is already a
    GUID; a GUID typed in upper case comes back lower-cased.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Role
    )
    if (Test-OERGuid -Value $Role) { return $Role.ToLowerInvariant() }
    $Escaped = ConvertTo-OERODataFilterValue -Value $Role
    $Response = Invoke-OERGraphRequest -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -eq 0) {
        # Microsoft Graph compares displayName on roleDefinitions CASE-SENSITIVELY (measured live,
        # step 3 check 1.2b: 'reports reader' matched nothing). A name typed in another letter case
        # is therefore matched here, against the whole list, ignoring case. The exact-case request
        # above stays first so an exactly typed name still costs one request and never meets a
        # case-only twin.
        $All = Invoke-OERGraphRequest -Uri 'v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName' -All
        $Candidates = @($All.value | Where-Object {
                $null -ne $_ -and [string]::Equals([string]$_.displayName, $Role, [System.StringComparison]::OrdinalIgnoreCase)
            })
    }
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Directory role name '$Role' matches $($Candidates.Count) role definitions ($Ids). " +
                'Re-run with the role definition id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $Role)
    }
    if ($Candidates.Count -eq 1) { return [string]$Candidates[0].id }
    return $null
}
