function Resolve-OERDirectoryRoleDefinitionId {
    <#
    .SYNOPSIS
    Resolves a Microsoft Entra directory role definition name to its unifiedRoleDefinition id.

    .DESCRIPTION
    Returns the unifiedRoleDefinition id for a directory role, given either its display name or its
    id. When -Role is a GUID it is returned verbatim (treated as an id) with no Graph call. Otherwise
    a filtered v1.0/roleManagement/directory/roleDefinitions query is issued through
    Invoke-OERGraphRequest, which covers both built-in and custom role definitions -- unlike
    Resolve-OERDirectoryRoleId, this helper never activates a directory role from its template: a
    role definition already exists for every role, activated or not, so no POST is ever made and no
    call ever targets v1.0/directoryRoles. Exactly one match returns that definition's id; no match
    returns $null; more than one match throws an ErrorRecord with ErrorId 'AmbiguousName' listing the
    candidate ids, since a caller-supplied display name is not guaranteed unique. The display name is
    escaped through ConvertTo-OERODataFilterValue, which doubles embedded single quotes and
    percent-encodes the value so reserved characters (including a space) survive transport. A Graph
    transport or permission failure is not caught here and propagates to the caller unchanged.

    .PARAMETER Role
    The directory role definition display name or id to resolve. Mandatory: an empty string is
    rejected at parameter binding, the same as a missing value. If the value is a GUID it is returned
    verbatim (treated as an id) with no Graph call. Otherwise escaped through
    ConvertTo-OERODataFilterValue (quote-doubling plus percent-encoding) before the OData filter is
    built.

    .EXAMPLE
    Resolve-OERDirectoryRoleDefinitionId -Role 'Reports Reader'
    Returns the unifiedRoleDefinition id of the built-in 'Reports Reader' role, or $null when no
    directory role definition has that display name.

    .EXAMPLE
    Resolve-OERDirectoryRoleDefinitionId -Role '11111111-1111-1111-1111-111111111111'
    Returns '11111111-1111-1111-1111-111111111111' unchanged, since the value is already a GUID and
    no Graph call is made.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Role
    )
    if (Test-OERGuid -Value $Role) { return $Role }
    $Escaped = ConvertTo-OERODataFilterValue -Value $Role
    $Response = Invoke-OERGraphRequest -Uri "v1.0/roleManagement/directory/roleDefinitions?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
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
